import Foundation

nonisolated enum AgentOrchestratorAdapterConfigurationError:
    Error,
    Equatable,
    LocalizedError,
    Sendable
{
    case invalidBaseURL(URL)
    case nonLoopbackBaseURL(URL)
    case missingSupportedAPIVersion
    case invalidHarness

    nonisolated var errorDescription: String? {
        switch self {
        case let .invalidBaseURL(url):
            return "The Agent Orchestrator URL is not a daemon root URL: \(url.absoluteString)"
        case let .nonLoopbackBaseURL(url):
            return "Agent Orchestrator must use a loopback URL, not \(url.absoluteString)."
        case .missingSupportedAPIVersion:
            return "At least one supported Agent Orchestrator API version is required."
        case .invalidHarness:
            return "The Agent Orchestrator harness identifier is empty."
        }
    }
}

nonisolated struct AgentOrchestratorBackendConfiguration: Sendable {
    static let capturedUpstreamRevision =
        "9caafbee89383c9bf7e904936eb88c48add2fa88"
    static let capturedAPIVersion = "0.1.0-route-shell"

    let baseURL: URL
    let supportedAPIVersions: Set<String>
    let harness: String
    let requestTimeout: TimeInterval

    nonisolated init(
        baseURL: URL,
        supportedAPIVersions: Set<String> = [capturedAPIVersion],
        harness: String = "codex",
        requestTimeout: TimeInterval = 10
    ) throws {
        guard let components = URLComponents(
            url: baseURL,
            resolvingAgainstBaseURL: false
        ),
        let scheme = components.scheme?.lowercased(),
        scheme == "http" || scheme == "https",
        components.user == nil,
        components.password == nil,
        components.query == nil,
        components.fragment == nil,
        components.path.isEmpty || components.path == "/" else {
            throw AgentOrchestratorAdapterConfigurationError
                .invalidBaseURL(baseURL)
        }
        let host = components.host?.lowercased() ?? ""
        guard host == "localhost"
                || host == "127.0.0.1"
                || host == "::1" else {
            throw AgentOrchestratorAdapterConfigurationError
                .nonLoopbackBaseURL(baseURL)
        }
        guard !supportedAPIVersions.isEmpty else {
            throw AgentOrchestratorAdapterConfigurationError
                .missingSupportedAPIVersion
        }
        let normalizedHarness = harness.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !normalizedHarness.isEmpty else {
            throw AgentOrchestratorAdapterConfigurationError.invalidHarness
        }

        self.baseURL = baseURL
        self.supportedAPIVersions = supportedAPIVersions
        self.harness = normalizedHarness
        self.requestTimeout = max(1, requestTimeout)
    }
}

actor AgentOrchestratorExecutionBackend: ExecutionBackend {
    nonisolated let backendID = "agent-orchestrator"

    private struct InFlightHealth: Sendable {
        let id: UUID
        let task: Task<ExecutionBackendHealth, any Error>
    }

    private enum WorkspaceFilesResult: Sendable {
        case success(AgentOrchestratorWire.WorkspaceFiles)
        case failure(String)
    }

    private let configuration: AgentOrchestratorBackendConfiguration
    private let transport: any AgentOrchestratorHTTPTransport
    private let now: @Sendable () -> Date
    private var compatibleAPIVersion: String?
    private var inFlightHealth: InFlightHealth?
    private var startRequestByID: [UUID: ExecutionStartRequest] = [:]
    private var startTaskByID:
        [UUID: Task<ExecutionStartReceipt, any Error>] = [:]

    init(
        configuration: AgentOrchestratorBackendConfiguration,
        transport: any AgentOrchestratorHTTPTransport =
            URLSessionAgentOrchestratorHTTPTransport(),
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.configuration = configuration
        self.transport = transport
        self.now = now
    }

    func health() async throws -> ExecutionBackendHealth {
        let probe: InFlightHealth
        if let existing = inFlightHealth {
            probe = existing
        } else {
            let identifier = UUID()
            let configuration = configuration
            let transport = transport
            let checkedAt = now()
            let task = Task {
                try await Self.performHealth(
                    configuration: configuration,
                    transport: transport,
                    checkedAt: checkedAt
                )
            }
            probe = InFlightHealth(id: identifier, task: task)
            inFlightHealth = probe
        }

        do {
            let result = try await probe.task.value
            if inFlightHealth?.id == probe.id {
                inFlightHealth = nil
            }
            if result.state == .ready,
               let version = result.version {
                compatibleAPIVersion = version
            } else {
                compatibleAPIVersion = nil
            }
            return result
        } catch {
            if inFlightHealth?.id == probe.id {
                inFlightHealth = nil
            }
            compatibleAPIVersion = nil
            throw error
        }
    }

    func listProjects() async throws -> [ExecutionProject] {
        try await requireCompatibleAPI()
        let request = makeRequest(
            pathComponents: ["api", "v1", "projects"],
            operation: .listProjects
        )
        let response = try await send(
            request,
            operation: .listProjects
        )
        try requireStatus(
            response,
            expected: [200],
            operation: .listProjects
        )
        let payload: AgentOrchestratorWire.ProjectList = try decode(
            response.data,
            operation: .listProjects
        )
        return payload.projects.map(Self.executionProject)
    }

    func start(
        _ request: ExecutionStartRequest
    ) async throws -> ExecutionStartReceipt {
        if let existing = startRequestByID[request.requestID],
           existing != request {
            throw ExecutionBackendError.conflict(
                "The OpenMac request ID was reused with different AO session inputs."
            )
        }
        startRequestByID[request.requestID] = request
        if let existingTask = startTaskByID[request.requestID] {
            return try await existingTask.value
        }

        try await requireCompatibleAPI()
        if let existingTask = startTaskByID[request.requestID] {
            return try await existingTask.value
        }

        let configuration = configuration
        let transport = transport
        let task = Task {
            try await Self.performStart(
                request,
                configuration: configuration,
                transport: transport
            )
        }
        startTaskByID[request.requestID] = task
        do {
            return try await task.value
        } catch {
            startTaskByID[request.requestID] = nil
            throw error
        }
    }

    func facts(
        for executionID: ExecutionID,
        after cursor: ExecutionFactCursor?
    ) async throws -> ExecutionFactPage {
        try await requireCompatibleAPI()
        let decodedCursor = try Self.decodeFactCursor(
            cursor,
            executionID: executionID
        )
        let request = makeRequest(
            pathComponents: [
                "api", "v1", "sessions", executionID.rawValue
            ],
            operation: .facts
        )
        let response = try await send(request, operation: .facts)
        if response.statusCode == 404 {
            throw ExecutionBackendError.executionNotFound(executionID)
        }
        try requireStatus(
            response,
            expected: [200],
            operation: .facts
        )
        let envelope: AgentOrchestratorWire.SessionEnvelope = try decode(
            response.data,
            operation: .facts
        )
        guard envelope.session.id == executionID.rawValue else {
            throw ExecutionBackendError.malformedResponse(
                operation: .facts,
                reason: "The session response identity does not match the requested execution."
            )
        }

        let observedAt = now()
        let workspaceResult = await workspaceFiles(
            executionID: executionID
        )
        let mapped = Self.factBodies(
            session: envelope.session,
            workspaceResult: workspaceResult,
            observedAt: observedAt
        )
        guard !mapped.bodies.isEmpty else {
            throw ExecutionBackendError.malformedResponse(
                operation: .facts,
                reason: "The AO session snapshot produced no observable facts."
            )
        }
        guard decodedCursor.nextSequence <= UInt64.max
                - UInt64(mapped.bodies.count) else {
            throw ExecutionBackendError.malformedResponse(
                operation: .facts,
                reason: "The fact sequence is exhausted."
            )
        }

        let facts = mapped.bodies.enumerated().map { offset, item in
            let sequence = decodedCursor.nextSequence + UInt64(offset)
            return ExecutionFact(
                id: ExecutionFactID(
                    "\(executionID.rawValue)-ao-snapshot-\(sequence)"
                ),
                executionID: executionID,
                sequence: sequence,
                occurredAt: item.occurredAt,
                body: item.body
            )
        }
        let nextSequence = decodedCursor.nextSequence
            + UInt64(facts.count)
        let nextCursor = try Self.encodeFactCursor(
            AgentOrchestratorWire.FactCursor(
                executionID: executionID.rawValue,
                nextSequence: nextSequence
            )
        )
        return ExecutionFactPage(
            facts: facts,
            nextCursor: nextCursor,
            hasMore: !mapped.isTerminal
        )
    }

    func stop(
        executionID: ExecutionID
    ) async throws -> ExecutionStopReceipt {
        try await requireCompatibleAPI()
        let sessionRequest = makeRequest(
            pathComponents: [
                "api", "v1", "sessions", executionID.rawValue
            ],
            operation: .stop
        )
        let sessionResponse = try await send(
            sessionRequest,
            operation: .stop
        )
        if sessionResponse.statusCode == 404 {
            throw ExecutionBackendError.executionNotFound(executionID)
        }
        try requireStatus(
            sessionResponse,
            expected: [200],
            operation: .stop
        )
        let sessionEnvelope: AgentOrchestratorWire.SessionEnvelope = try decode(
            sessionResponse.data,
            operation: .stop
        )
        guard sessionEnvelope.session.id == executionID.rawValue else {
            throw ExecutionBackendError.malformedResponse(
                operation: .stop,
                reason: "The session response identity does not match the requested execution."
            )
        }
        if sessionEnvelope.session.isTerminated {
            return ExecutionStopReceipt(
                executionID: executionID,
                disposition: .alreadyTerminal,
                acknowledgedAt: now()
            )
        }

        var killRequest = makeRequest(
            pathComponents: [
                "api", "v1", "sessions", executionID.rawValue, "kill"
            ],
            operation: .stop,
            method: "POST"
        )
        killRequest.httpBody = Data()
        let killResponse = try await send(
            killRequest,
            operation: .stop
        )
        if killResponse.statusCode == 404 {
            throw ExecutionBackendError.executionNotFound(executionID)
        }
        try requireStatus(
            killResponse,
            expected: [200],
            operation: .stop
        )
        let payload: AgentOrchestratorWire.KillSessionResponse = try decode(
            killResponse.data,
            operation: .stop
        )
        guard payload.ok,
              payload.sessionId == executionID.rawValue else {
            throw ExecutionBackendError.malformedResponse(
                operation: .stop,
                reason: "AO did not acknowledge the requested session kill."
            )
        }
        return ExecutionStopReceipt(
            executionID: executionID,
            disposition: payload.freed == false
                ? .alreadyStopped
                : .accepted,
            acknowledgedAt: now()
        )
    }

    private func requireCompatibleAPI() async throws {
        if compatibleAPIVersion != nil {
            return
        }
        let current = try await health()
        guard current.state == .ready else {
            throw ExecutionBackendError.unavailable(
                current.message
                    ?? "Agent Orchestrator has an incompatible API version."
            )
        }
    }

    private func workspaceFiles(
        executionID: ExecutionID
    ) async -> WorkspaceFilesResult {
        let request = makeRequest(
            pathComponents: [
                "api", "v1", "sessions", executionID.rawValue,
                "workspace", "files"
            ],
            operation: .facts
        )
        do {
            let response = try await send(request, operation: .facts)
            guard response.statusCode == 200 else {
                return .failure(
                    Self.apiFailureMessage(
                        response,
                        fallback: "AO workspace files returned HTTP \(response.statusCode)."
                    )
                )
            }
            let payload: AgentOrchestratorWire.WorkspaceFiles = try decode(
                response.data,
                operation: .facts
            )
            guard payload.sessionId == executionID.rawValue else {
                return .failure(
                    "AO workspace files referenced another session."
                )
            }
            return .success(payload)
        } catch {
            return .failure(Self.errorMessage(error))
        }
    }

    private func makeRequest(
        pathComponents: [String],
        operation: ExecutionBackendOperation,
        method: String = "GET",
        accept: String = "application/json"
    ) -> URLRequest {
        Self.makeRequest(
            configuration: configuration,
            pathComponents: pathComponents,
            operation: operation,
            method: method,
            accept: accept
        )
    }

    private func send(
        _ request: URLRequest,
        operation: ExecutionBackendOperation
    ) async throws -> AgentOrchestratorHTTPResponse {
        try await Self.send(
            request,
            operation: operation,
            transport: transport
        )
    }

    private func requireStatus(
        _ response: AgentOrchestratorHTTPResponse,
        expected: Set<Int>,
        operation: ExecutionBackendOperation
    ) throws {
        try Self.requireStatus(
            response,
            expected: expected,
            operation: operation
        )
    }

    private func decode<T: Decodable>(
        _ data: Data,
        operation: ExecutionBackendOperation
    ) throws -> T {
        try Self.decode(data, operation: operation)
    }

    private nonisolated static func performStart(
        _ request: ExecutionStartRequest,
        configuration: AgentOrchestratorBackendConfiguration,
        transport: any AgentOrchestratorHTTPTransport
    ) async throws -> ExecutionStartReceipt {
        let projectRequest = makeRequest(
            configuration: configuration,
            pathComponents: [
                "api", "v1", "projects", request.projectID.rawValue
            ],
            operation: .start
        )
        let projectResponse = try await send(
            projectRequest,
            operation: .start,
            transport: transport
        )
        if projectResponse.statusCode == 404 {
            throw ExecutionBackendError.projectNotFound(request.projectID)
        }
        try requireStatus(
            projectResponse,
            expected: [200],
            operation: .start
        )
        let project: AgentOrchestratorWire.ProjectEnvelope = try decode(
            projectResponse.data,
            operation: .start
        )
        guard project.status == "ok",
              project.project.resolveError?.isEmpty != false else {
            throw ExecutionBackendError.rejected(
                "The selected AO project is degraded. Repair it in Agent Orchestrator and retry."
            )
        }
        guard project.project.id == request.projectID.rawValue else {
            throw ExecutionBackendError.malformedResponse(
                operation: .start,
                reason: "The AO project identity does not match the request."
            )
        }
        guard project.project.defaultBranch == request.baseBranch else {
            throw ExecutionBackendError.conflict(
                "AO project \(request.projectID.rawValue) uses base branch \(project.project.defaultBranch ?? "(unknown)"), but the approved plan uses \(request.baseBranch). Update the AO project before dispatch."
            )
        }

        let branch = idempotencyBranch(request.requestID)
        let existingRequest = makeRequest(
            configuration: configuration,
            pathComponents: ["api", "v1", "sessions"],
            operation: .start,
            queryItems: [
                URLQueryItem(
                    name: "project",
                    value: request.projectID.rawValue
                )
            ]
        )
        let existingResponse = try await send(
            existingRequest,
            operation: .start,
            transport: transport
        )
        try requireStatus(
            existingResponse,
            expected: [200],
            operation: .start
        )
        let existing: AgentOrchestratorWire.SessionList = try decode(
            existingResponse.data,
            operation: .start
        )
        let matches = existing.sessions.filter {
            $0.projectId == request.projectID.rawValue
                && $0.branch == branch
        }
        if matches.count > 1 {
            throw ExecutionBackendError.conflict(
                "AO returned multiple sessions for OpenMac branch \(branch). Resolve the duplicate sessions in AO before retrying."
            )
        }
        if let match = matches.first {
            return try recoveredReceipt(
                match,
                request: request,
                configuration: configuration
            )
        }

        let prompt = taskPrompt(request)
        guard prompt.utf8.count <= 4_096 else {
            throw ExecutionBackendError.rejected(
                "The AO task prompt is \(prompt.utf8.count) bytes; AO accepts at most 4096. Shorten the worker prompt and approve the plan again."
            )
        }
        let body = AgentOrchestratorWire.SpawnSessionRequest(
            projectId: request.projectID.rawValue,
            kind: "worker",
            harness: configuration.harness,
            branch: branch,
            prompt: prompt,
            displayName: displayName(
                title: request.title,
                requestID: request.requestID
            )
        )
        var spawnRequest = makeRequest(
            configuration: configuration,
            pathComponents: ["api", "v1", "sessions"],
            operation: .start,
            method: "POST"
        )
        spawnRequest.setValue(
            "application/json",
            forHTTPHeaderField: "Content-Type"
        )
        do {
            spawnRequest.httpBody = try JSONEncoder().encode(body)
        } catch {
            throw ExecutionBackendError.rejected(
                "The AO session request could not be encoded."
            )
        }
        let spawnResponse = try await send(
            spawnRequest,
            operation: .start,
            transport: transport
        )
        if spawnResponse.statusCode == 404 {
            throw ExecutionBackendError.projectNotFound(request.projectID)
        }
        try requireStatus(
            spawnResponse,
            expected: [201],
            operation: .start
        )
        let spawned: AgentOrchestratorWire.SpawnSessionResponse = try decode(
            spawnResponse.data,
            operation: .start
        )
        guard spawned.promptBytes == prompt.utf8.count,
              spawned.session.projectId == request.projectID.rawValue,
              spawned.session.kind == "worker",
              spawned.session.harness == configuration.harness,
              spawned.session.branch == branch,
              !spawned.session.id.trimmingCharacters(
                  in: .whitespacesAndNewlines
              ).isEmpty,
              let acceptedAt = parseDate(spawned.session.createdAt) else {
            throw ExecutionBackendError.malformedResponse(
                operation: .start,
                reason: "The AO spawn receipt does not match the requested session."
            )
        }
        return ExecutionStartReceipt(
            requestID: request.requestID,
            executionID: ExecutionID(spawned.session.id),
            acceptedAt: acceptedAt
        )
    }

    private nonisolated static func performHealth(
        configuration: AgentOrchestratorBackendConfiguration,
        transport: any AgentOrchestratorHTTPTransport,
        checkedAt: Date
    ) async throws -> ExecutionBackendHealth {
        let probeRequest = makeRequest(
            configuration: configuration,
            pathComponents: ["healthz"],
            operation: .health
        )
        let probeResponse = try await send(
            probeRequest,
            operation: .health,
            transport: transport
        )
        try requireStatus(
            probeResponse,
            expected: [200],
            operation: .health
        )
        let probe: AgentOrchestratorWire.Health = try decode(
            probeResponse.data,
            operation: .health
        )
        guard probe.status == "ok",
              probe.service == "agent-orchestrator-daemon",
              probe.pid > 0 else {
            throw ExecutionBackendError.malformedResponse(
                operation: .health,
                reason: "The daemon identity or liveness payload is invalid."
            )
        }

        let specRequest = makeRequest(
            configuration: configuration,
            pathComponents: ["api", "v1", "openapi.yaml"],
            operation: .health,
            accept: "application/yaml, text/yaml, text/plain"
        )
        let specResponse = try await send(
            specRequest,
            operation: .health,
            transport: transport
        )
        guard specResponse.statusCode == 200,
              let version = openAPIVersion(in: specResponse.data) else {
            return ExecutionBackendHealth(
                state: .degraded,
                backendName: "Agent Orchestrator",
                checkedAt: checkedAt,
                message: "AO is running, but its served OpenAPI version could not be read. Update AO or select the fixture backend."
            )
        }

        guard configuration.supportedAPIVersions.contains(version) else {
            let supported = configuration.supportedAPIVersions.sorted()
                .joined(separator: ", ")
            return ExecutionBackendHealth(
                state: .degraded,
                backendName: "Agent Orchestrator",
                version: version,
                checkedAt: checkedAt,
                message: "AO API \(version) is incompatible. OpenMac currently supports \(supported); update the AO adapter or use the fixture backend."
            )
        }

        return ExecutionBackendHealth(
            state: .ready,
            backendName: "Agent Orchestrator",
            version: version,
            checkedAt: checkedAt
        )
    }

    private nonisolated static func recoveredReceipt(
        _ session: AgentOrchestratorWire.Session,
        request: ExecutionStartRequest,
        configuration: AgentOrchestratorBackendConfiguration
    ) throws -> ExecutionStartReceipt {
        guard session.kind == "worker",
              session.harness == configuration.harness,
              let acceptedAt = parseDate(session.createdAt) else {
            throw ExecutionBackendError.conflict(
                "The existing AO session for this OpenMac request has incompatible identity or harness data."
            )
        }
        return ExecutionStartReceipt(
            requestID: request.requestID,
            executionID: ExecutionID(session.id),
            acceptedAt: acceptedAt
        )
    }

    private nonisolated static func executionProject(
        _ project: AgentOrchestratorWire.ProjectSummary
    ) -> ExecutionProject {
        let hasResolveError = project.resolveError?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty == false
        let isolation: ExecutionProjectIsolation
        switch project.kind {
        case "single_repo", "workspace":
            isolation = hasResolveError
                ? .unknown
                : .isolatedWorkspace
        case "scratch":
            isolation = .sharedWorkspace
        default:
            isolation = .unknown
        }
        let repositoryURL: URL?
        if project.path.hasPrefix("/") {
            repositoryURL = URL(
                fileURLWithPath: project.path,
                isDirectory: true
            )
        } else {
            repositoryURL = nil
        }
        return ExecutionProject(
            id: ExecutionProjectID(project.id),
            name: project.name,
            repositoryURL: repositoryURL,
            workspaceHint: hasResolveError
                ? project.resolveError
                : project.sessionPrefix,
            isolation: isolation
        )
    }

    private struct MappedFactBodies: Sendable {
        struct Item: Sendable {
            let occurredAt: Date
            let body: ExecutionFactBody
        }

        let bodies: [Item]
        let isTerminal: Bool
    }

    private nonisolated static func factBodies(
        session: AgentOrchestratorWire.Session,
        workspaceResult: WorkspaceFilesResult,
        observedAt: Date
    ) -> MappedFactBodies {
        let sessionAt = boundedDate(
            session.updatedAt,
            fallback: observedAt,
            upperBound: observedAt
        )
        var bodies: [MappedFactBodies.Item] = []
        var isTerminal = false

        func append(
            _ body: ExecutionFactBody,
            at date: Date = sessionAt
        ) {
            bodies.append(
                MappedFactBodies.Item(
                    occurredAt: min(date, observedAt),
                    body: body
                )
            )
        }

        switch session.status {
        case "working":
            append(.phase(.running))
        case "needs_input":
            append(.phase(.waitingForInput))
            let prompt = session.activity.state == "blocked"
                ? "AO is waiting on a permission or approval decision. Open Agent Orchestrator and review the pending decision."
                : "AO is waiting for the next instruction. Open Agent Orchestrator to continue the session."
            append(.inputRequested(prompt: prompt))
        case "ci_failed":
            append(
                .diagnostic(
                    ExecutionDiagnostic(
                        severity: .error,
                        code: "AO_CI_FAILED",
                        message: "AO reports failing pull-request checks. Open the AO session for details.",
                        retryable: true
                    )
                )
            )
        case "changes_requested":
            append(
                .diagnostic(
                    ExecutionDiagnostic(
                        severity: .error,
                        code: "AO_CHANGES_REQUESTED",
                        message: "AO reports requested review changes. Open the pull request or AO session.",
                        retryable: true
                    )
                )
            )
        case "no_signal":
            append(
                .diagnostic(
                    ExecutionDiagnostic(
                        severity: .error,
                        code: "AO_NO_SIGNAL",
                        message: "AO has not received an activity signal from the agent. Check the AO session and hook configuration.",
                        retryable: true
                    )
                )
            )
        case "merged":
            append(.phase(.succeeded))
            isTerminal = true
        case "exited", "terminated":
            append(.phase(.stopped))
            isTerminal = true
        case "pr_open", "draft", "review_pending", "approved",
             "mergeable", "idle":
            append(.phase(.running))
        default:
            append(
                .unknown(
                    kind: "ao.session.status.\(session.status)",
                    rawPayload: nil
                )
            )
        }

        if session.isTerminated && !isTerminal {
            append(.phase(.stopped))
            isTerminal = true
        }

        switch workspaceResult {
        case let .success(workspace):
            let paths = workspace.files
                .filter { $0.status != "unmodified" }
                .map(\.path)
                .sorted()
            if !paths.isEmpty {
                append(
                    .changedFilesEvidence(
                        ExecutionChangedFilesEvidence(paths: paths)
                    )
                )
            }
            if workspace.truncated {
                append(
                    .diagnostic(
                        ExecutionDiagnostic(
                            severity: .warning,
                            code: "AO_WORKSPACE_FILES_TRUNCATED",
                            message: "AO truncated the workspace file list; changed-file evidence is incomplete.",
                            retryable: true
                        )
                    )
                )
            }
        case let .failure(message):
            append(
                .diagnostic(
                    ExecutionDiagnostic(
                        severity: .warning,
                        code: "AO_WORKSPACE_FILES_UNAVAILABLE",
                        message: message,
                        retryable: true
                    )
                )
            )
        }

        for pullRequest in session.prs.sorted(by: {
            if $0.number != $1.number {
                return $0.number < $1.number
            }
            return $0.url < $1.url
        }) {
            guard let url = URL(string: pullRequest.url),
                  let state = pullRequestState(pullRequest.state) else {
                append(
                    .unknown(
                        kind: "ao.pull-request",
                        rawPayload: pullRequest.url
                    )
                )
                continue
            }
            let pullRequestAt = boundedDate(
                pullRequest.updatedAt,
                fallback: sessionAt,
                upperBound: observedAt
            )
            append(
                .pullRequestEvidence(
                    ExecutionPullRequestEvidence(
                        url: url,
                        state: state,
                        checks: checkState(pullRequest.ci),
                        review: reviewState(pullRequest.review)
                    )
                ),
                at: pullRequestAt
            )
        }

        return MappedFactBodies(
            bodies: bodies,
            isTerminal: isTerminal
        )
    }

    private nonisolated static func pullRequestState(
        _ value: String
    ) -> ExecutionPullRequestState? {
        switch value {
        case "draft", "open":
            return .open
        case "merged":
            return .merged
        case "closed":
            return .closed
        default:
            return nil
        }
    }

    private nonisolated static func checkState(
        _ value: String
    ) -> ExecutionCheckState {
        switch value {
        case "pending":
            return .pending
        case "passing":
            return .passing
        case "failing":
            return .failing
        default:
            return .unknown
        }
    }

    private nonisolated static func reviewState(
        _ value: String
    ) -> ExecutionReviewState {
        switch value {
        case "approved":
            return .approved
        case "changes_requested":
            return .changesRequested
        case "review_required":
            return .required
        default:
            return .unknown
        }
    }

    private nonisolated static func idempotencyBranch(
        _ requestID: UUID
    ) -> String {
        "openmac/\(requestID.uuidString.lowercased())"
    }

    private nonisolated static func displayName(
        title: String,
        requestID: UUID
    ) -> String {
        let normalized = title.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        if !normalized.isEmpty {
            return String(normalized.prefix(20))
        }
        return "OpenMac \(requestID.uuidString.prefix(8))"
    }

    private nonisolated static func taskPrompt(
        _ request: ExecutionStartRequest
    ) -> String {
        """
        \(request.instructions)

        OpenMac approved delivery context:
        - Task: \(request.title)
        - Base: \(request.baseBranch) @ \(request.baseCommitIdentifier)
        - Plan: \(request.planID.uuidString) revision \(request.planRevision)
        """
    }

    private nonisolated static func decodeFactCursor(
        _ cursor: ExecutionFactCursor?,
        executionID: ExecutionID
    ) throws -> AgentOrchestratorWire.FactCursor {
        guard let cursor else {
            return AgentOrchestratorWire.FactCursor(
                executionID: executionID.rawValue,
                nextSequence: 1
            )
        }
        guard let data = Data(
            base64Encoded: cursor.rawValue
        ),
        let decoded = try? JSONDecoder().decode(
            AgentOrchestratorWire.FactCursor.self,
            from: data
        ),
        decoded.executionID == executionID.rawValue,
        decoded.nextSequence > 0 else {
            throw ExecutionBackendError.malformedResponse(
                operation: .facts,
                reason: "The AO fact cursor is invalid for this execution."
            )
        }
        return decoded
    }

    private nonisolated static func encodeFactCursor(
        _ cursor: AgentOrchestratorWire.FactCursor
    ) throws -> ExecutionFactCursor {
        do {
            let data = try JSONEncoder().encode(cursor)
            return ExecutionFactCursor(data.base64EncodedString())
        } catch {
            throw ExecutionBackendError.malformedResponse(
                operation: .facts,
                reason: "The next AO fact cursor could not be encoded."
            )
        }
    }

    private nonisolated static func makeRequest(
        configuration: AgentOrchestratorBackendConfiguration,
        pathComponents: [String],
        operation: ExecutionBackendOperation,
        method: String = "GET",
        accept: String = "application/json",
        queryItems: [URLQueryItem] = []
    ) -> URLRequest {
        var url = configuration.baseURL
        for component in pathComponents {
            url.appendPathComponent(component)
        }
        if !queryItems.isEmpty,
           var components = URLComponents(
               url: url,
               resolvingAgainstBaseURL: false
           ) {
            components.queryItems = queryItems
            url = components.url ?? url
        }
        var request = URLRequest(
            url: url,
            timeoutInterval: configuration.requestTimeout
        )
        request.httpMethod = method
        request.setValue(accept, forHTTPHeaderField: "Accept")
        request.setValue(
            "OpenMac/\(operation.rawValue)",
            forHTTPHeaderField: "User-Agent"
        )
        return request
    }

    private nonisolated static func send(
        _ request: URLRequest,
        operation: ExecutionBackendOperation,
        transport: any AgentOrchestratorHTTPTransport
    ) async throws -> AgentOrchestratorHTTPResponse {
        do {
            return try await transport.send(request)
        } catch let error as URLError {
            if error.code == .timedOut {
                throw ExecutionBackendError.timedOut(operation)
            }
            throw ExecutionBackendError.unavailable(
                "Could not reach Agent Orchestrator at \(request.url?.host ?? "the configured host"). Start the AO desktop app and retry. (\(error.localizedDescription))"
            )
        } catch let error as ExecutionBackendError {
            throw error
        } catch {
            throw ExecutionBackendError.unavailable(
                "Could not reach Agent Orchestrator. Start the AO desktop app and retry. (\(errorMessage(error)))"
            )
        }
    }

    private nonisolated static func requireStatus(
        _ response: AgentOrchestratorHTTPResponse,
        expected: Set<Int>,
        operation: ExecutionBackendOperation
    ) throws {
        guard !expected.contains(response.statusCode) else { return }
        let message = apiFailureMessage(
            response,
            fallback: "AO returned HTTP \(response.statusCode) during \(operation.rawValue)."
        )
        switch response.statusCode {
        case 401, 403:
            throw ExecutionBackendError.unauthorized
        case 409:
            throw ExecutionBackendError.conflict(message)
        case 400..<500:
            throw ExecutionBackendError.rejected(message)
        default:
            throw ExecutionBackendError.unavailable(message)
        }
    }

    private nonisolated static func decode<T: Decodable>(
        _ data: Data,
        operation: ExecutionBackendOperation
    ) throws -> T {
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw ExecutionBackendError.malformedResponse(
                operation: operation,
                reason: "AO returned invalid JSON for \(String(describing: T.self)): \(error.localizedDescription)"
            )
        }
    }

    private nonisolated static func apiFailureMessage(
        _ response: AgentOrchestratorHTTPResponse,
        fallback: String
    ) -> String {
        guard let payload = try? JSONDecoder().decode(
            AgentOrchestratorWire.APIError.self,
            from: response.data
        ) else {
            return fallback
        }
        let requestSuffix = payload.requestId.map {
            " Request ID: \($0)."
        } ?? ""
        return "\(payload.code): \(payload.message)\(requestSuffix)"
    }

    private nonisolated static func openAPIVersion(
        in data: Data
    ) -> String? {
        guard let source = String(data: data, encoding: .utf8) else {
            return nil
        }
        var isInsideInfo = false
        for rawLine in source.split(
            separator: "\n",
            omittingEmptySubsequences: false
        ) {
            let line = String(rawLine)
            if line == "info:" {
                isInsideInfo = true
                continue
            }
            guard isInsideInfo else { continue }
            if !line.hasPrefix("  ") {
                return nil
            }
            let trimmed = line.trimmingCharacters(
                in: .whitespaces
            )
            guard trimmed.hasPrefix("version:") else { continue }
            let value = trimmed
                .dropFirst("version:".count)
                .trimmingCharacters(
                    in: .whitespacesAndNewlines
                )
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            return value.isEmpty ? nil : value
        }
        return nil
    }

    private nonisolated static func parseDate(
        _ source: String
    ) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [
            .withInternetDateTime,
            .withFractionalSeconds
        ]
        if let date = fractional.date(from: source) {
            return date
        }
        return ISO8601DateFormatter().date(from: source)
    }

    private nonisolated static func boundedDate(
        _ source: String,
        fallback: Date,
        upperBound: Date
    ) -> Date {
        min(parseDate(source) ?? fallback, upperBound)
    }

    private nonisolated static func errorMessage(
        _ error: Error
    ) -> String {
        if let localized = error as? any LocalizedError,
           let description = localized.errorDescription {
            return description
        }
        return String(describing: error)
    }
}
