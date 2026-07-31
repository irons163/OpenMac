import Foundation
import Testing
@testable import OpenMac

private struct CapturedAORequest: Sendable {
    let method: String
    let path: String
    let query: String
    let body: Data?
}

private struct CapturedAOStub: Sendable {
    let method: String
    let path: String
    let query: String
    let response: AgentOrchestratorHTTPResponse

    init(
        _ path: String,
        method: String = "GET",
        query: String = "",
        status: Int = 200,
        data: Data
    ) {
        self.method = method
        self.path = path
        self.query = query
        self.response = AgentOrchestratorHTTPResponse(
            data: data,
            statusCode: status
        )
    }
}

private actor CapturedAOTransport: AgentOrchestratorHTTPTransport {
    private struct Key: Hashable {
        let method: String
        let path: String
        let query: String
    }

    private var responses: [Key: [AgentOrchestratorHTTPResponse]]
    private var capturedRequests: [CapturedAORequest] = []

    init(stubs: [CapturedAOStub]) {
        var responses: [Key: [AgentOrchestratorHTTPResponse]] = [:]
        for stub in stubs {
            let key = Key(
                method: stub.method,
                path: stub.path,
                query: stub.query
            )
            responses[key, default: []].append(stub.response)
        }
        self.responses = responses
    }

    func send(
        _ request: URLRequest
    ) async throws -> AgentOrchestratorHTTPResponse {
        guard let url = request.url else {
            throw URLError(.badURL)
        }
        let method = request.httpMethod ?? "GET"
        let query = URLComponents(
            url: url,
            resolvingAgainstBaseURL: false
        )?.queryItems?
            .map { "\($0.name)=\($0.value ?? "")" }
            .sorted()
            .joined(separator: "&") ?? ""
        let captured = CapturedAORequest(
            method: method,
            path: url.path,
            query: query,
            body: request.httpBody
        )
        capturedRequests.append(captured)

        let key = Key(
            method: method,
            path: url.path,
            query: query
        )
        guard var queue = responses[key],
              !queue.isEmpty else {
            throw URLError(
                .resourceUnavailable,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "No captured AO response for \(method) \(url.path)?\(query)"
                ]
            )
        }
        let response = queue.removeFirst()
        responses[key] = queue
        return response
    }

    func requests() -> [CapturedAORequest] {
        capturedRequests
    }
}

private enum AgentOrchestratorAdapterTestFixture {
    static let requestID = UUID(
        uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA"
    )!
    static let observedAt = Date(timeIntervalSince1970: 1_785_474_000)

    static var rootURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures", isDirectory: true)
            .appendingPathComponent(
                "AgentOrchestrator",
                isDirectory: true
            )
    }

    static func data(_ name: String) throws -> Data {
        try Data(
            contentsOf: rootURL.appendingPathComponent(name)
        )
    }

    static func commonStubs(
        _ additional: [CapturedAOStub] = []
    ) throws -> [CapturedAOStub] {
        [
            CapturedAOStub(
                "/healthz",
                data: try data("health.json")
            ),
            CapturedAOStub(
                "/readyz",
                data: try data("ready.json")
            ),
            CapturedAOStub(
                "/api/v1/openapi.yaml",
                data: try data("openapi.yaml")
            )
        ] + additional
    }

    static func backend(
        stubs: [CapturedAOStub],
        supportedVersions: Set<String> = [
            AgentOrchestratorBackendConfiguration.capturedAPIVersion
        ],
        expectedDaemonPID: Int? = nil
    ) throws -> (
        AgentOrchestratorExecutionBackend,
        CapturedAOTransport
    ) {
        let transport = CapturedAOTransport(stubs: stubs)
        let configuration = try AgentOrchestratorBackendConfiguration(
            baseURL: URL(string: "http://127.0.0.1:3001")!,
            supportedAPIVersions: supportedVersions,
            expectedDaemonPID: expectedDaemonPID
        )
        return (
            AgentOrchestratorExecutionBackend(
                configuration: configuration,
                transport: transport,
                now: { observedAt }
            ),
            transport
        )
    }

    static func startRequest(
        baseBranch: String = "main"
    ) -> ExecutionStartRequest {
        ExecutionStartRequest(
            requestID: requestID,
            projectID: ExecutionProjectID("openmac"),
            deliveryRunID: UUID(
                uuidString: "11111111-1111-1111-1111-111111111111"
            )!,
            taskID: UUID(
                uuidString: "33333333-3333-3333-3333-333333333333"
            )!,
            planID: UUID(
                uuidString: "22222222-2222-2222-2222-222222222222"
            )!,
            planRevision: 1,
            approvalFingerprint: "approved-fingerprint",
            title: "Login button",
            instructions: "Implement the login button.",
            baseBranch: baseBranch,
            baseCommitIdentifier: "abc123"
        )
    }
}

@Suite("Agent Orchestrator reference adapter", .serialized)
struct AgentOrchestratorAdapterTests {
    @Test("captured daemon probes and OpenAPI version produce ready health")
    func compatibleHealth() async throws {
        let (backend, transport) =
            try AgentOrchestratorAdapterTestFixture.backend(
                stubs: try AgentOrchestratorAdapterTestFixture.commonStubs(),
                expectedDaemonPID: 4812
            )

        let health = try await backend.health()

        #expect(health.state == .ready)
        #expect(health.backendName == "Agent Orchestrator")
        #expect(
            health.version
                == AgentOrchestratorBackendConfiguration.capturedAPIVersion
        )
        #expect(health.message == nil)
        let requests = await transport.requests()
        #expect(
            requests.map(\.path)
                == ["/healthz", "/readyz", "/api/v1/openapi.yaml"]
        )
    }

    @Test("discovered PID must match the responding daemon")
    func discoveredPIDMismatchFailsClosed() async throws {
        let (backend, transport) =
            try AgentOrchestratorAdapterTestFixture.backend(
                stubs: try AgentOrchestratorAdapterTestFixture
                    .commonStubs(),
                expectedDaemonPID: 9999
            )

        do {
            _ = try await backend.health()
            Issue.record("Expected discovered PID mismatch")
        } catch let error as ExecutionBackendError {
            guard case let .malformedResponse(operation, reason) = error else {
                Issue.record("Expected malformed health response, got \(error)")
                return
            }
            #expect(operation == .health)
            #expect(reason.contains("does not match"))
            #expect(reason.contains("9999"))
        }
        let requests = await transport.requests()
        #expect(requests.map(\.path) == ["/healthz"])
    }

    @Test("healthy daemon that is not ready degrades before OpenAPI")
    func notReadyDaemonDegradesBeforeCompatibilityProbe() async throws {
        let notReady = Data(
            """
            {
              "status": "not_ready",
              "service": "agent-orchestrator-daemon",
              "pid": 4812
            }
            """.utf8
        )
        let stubs = [
            CapturedAOStub(
                "/healthz",
                data: try AgentOrchestratorAdapterTestFixture.data(
                    "health.json"
                )
            ),
            CapturedAOStub("/readyz", data: notReady)
        ]
        let (backend, transport) =
            try AgentOrchestratorAdapterTestFixture.backend(
                stubs: stubs,
                expectedDaemonPID: 4812
            )

        let health = try await backend.health()

        #expect(health.state == .degraded)
        #expect(health.version == nil)
        #expect(health.message?.contains("not ready") == true)
        #expect(health.message?.contains("not_ready") == true)
        let requests = await transport.requests()
        #expect(requests.map(\.path) == ["/healthz", "/readyz"])
    }

    @Test("health and readiness probes must identify the same daemon")
    func readinessPIDMismatchFailsClosed() async throws {
        let mismatchedReadiness = Data(
            """
            {
              "status": "ready",
              "service": "agent-orchestrator-daemon",
              "pid": 9812
            }
            """.utf8
        )
        let stubs = [
            CapturedAOStub(
                "/healthz",
                data: try AgentOrchestratorAdapterTestFixture.data(
                    "health.json"
                )
            ),
            CapturedAOStub("/readyz", data: mismatchedReadiness)
        ]
        let (backend, transport) =
            try AgentOrchestratorAdapterTestFixture.backend(
                stubs: stubs
            )

        do {
            _ = try await backend.health()
            Issue.record("Expected readiness PID mismatch")
        } catch let error as ExecutionBackendError {
            guard case let .malformedResponse(operation, reason) = error else {
                Issue.record("Expected malformed health response, got \(error)")
                return
            }
            #expect(operation == .health)
            #expect(reason.contains("9812"))
            #expect(reason.contains("4812"))
        }
        let requests = await transport.requests()
        #expect(requests.map(\.path) == ["/healthz", "/readyz"])
    }

    @Test("unsupported served API version degrades with an actionable message")
    func incompatibleVersionFailsClosed() async throws {
        let incompatibleSpec = Data(
            """
            openapi: 3.1.0
            info:
              title: Agent Orchestrator HTTP daemon
              version: 99.0.0
            paths: {}
            """.utf8
        )
        let stubs = [
            CapturedAOStub(
                "/healthz",
                data: try AgentOrchestratorAdapterTestFixture.data(
                    "health.json"
                )
            ),
            CapturedAOStub(
                "/readyz",
                data: try AgentOrchestratorAdapterTestFixture.data(
                    "ready.json"
                )
            ),
            CapturedAOStub(
                "/api/v1/openapi.yaml",
                data: incompatibleSpec
            )
        ]
        let (backend, _) = try AgentOrchestratorAdapterTestFixture.backend(
            stubs: stubs
        )

        let health = try await backend.health()

        #expect(health.state == .degraded)
        #expect(health.version == "99.0.0")
        #expect(health.message?.contains("incompatible") == true)
        #expect(health.message?.contains("fixture backend") == true)
    }

    @Test("supported API version without a required route degrades")
    func missingRequiredOpenAPIOperationFailsClosed() async throws {
        let incompleteSpec = Data(
            """
            openapi: 3.1.0
            info:
              title: Agent Orchestrator HTTP daemon
              version: 0.1.0-route-shell
            paths:
              /api/v1/projects:
                get: {}
              /api/v1/projects/{projectId}:
                get: {}
              /api/v1/sessions:
                get: {}
                post: {}
              /api/v1/sessions/{sessionId}:
                get: {}
              /api/v1/sessions/{sessionId}/workspace/files:
                get: {}
            """.utf8
        )
        let stubs = [
            CapturedAOStub(
                "/healthz",
                data: try AgentOrchestratorAdapterTestFixture.data(
                    "health.json"
                )
            ),
            CapturedAOStub(
                "/readyz",
                data: try AgentOrchestratorAdapterTestFixture.data(
                    "ready.json"
                )
            ),
            CapturedAOStub(
                "/api/v1/openapi.yaml",
                data: incompleteSpec
            )
        ]
        let (backend, transport) =
            try AgentOrchestratorAdapterTestFixture.backend(
                stubs: stubs
            )

        let health = try await backend.health()

        #expect(health.state == .degraded)
        #expect(
            health.version
                == AgentOrchestratorBackendConfiguration.capturedAPIVersion
        )
        #expect(
            health.message?.contains(
                "POST /api/v1/sessions/{id}/kill"
            ) == true
        )
        #expect(health.message?.contains("missing operations") == true)
        let requests = await transport.requests()
        #expect(
            requests.map(\.path)
                == ["/healthz", "/readyz", "/api/v1/openapi.yaml"]
        )
    }

    @Test("project summaries map isolation without leaking AO wire types")
    func projectSelectionContract() async throws {
        let stubs = try AgentOrchestratorAdapterTestFixture.commonStubs([
            CapturedAOStub(
                "/api/v1/projects",
                data: try AgentOrchestratorAdapterTestFixture.data(
                    "projects.json"
                )
            )
        ])
        let (backend, _) = try AgentOrchestratorAdapterTestFixture.backend(
            stubs: stubs
        )

        let projects = try await backend.listProjects()
        let openMac = try #require(
            projects.first(where: { $0.id.rawValue == "openmac" })
        )
        let scratch = try #require(
            projects.first(where: { $0.id.rawValue == "scratch" })
        )
        let broken = try #require(
            projects.first(where: { $0.id.rawValue == "broken" })
        )

        #expect(openMac.isolation == .isolatedWorkspace)
        #expect(openMac.repositoryURL?.path == "/Volumes/M2SSD/OpenMac")
        #expect(scratch.isolation == .sharedWorkspace)
        #expect(broken.isolation == .unknown)
        #expect(broken.workspaceHint?.contains("missing") == true)
    }

    @Test("spawn uses a stable isolated branch and is idempotent")
    func startSessionContract() async throws {
        let stubs = try AgentOrchestratorAdapterTestFixture.commonStubs([
            CapturedAOStub(
                "/api/v1/projects/openmac",
                data: try AgentOrchestratorAdapterTestFixture.data(
                    "project.json"
                )
            ),
            CapturedAOStub(
                "/api/v1/sessions",
                query: "project=openmac",
                data: try AgentOrchestratorAdapterTestFixture.data(
                    "sessions-empty.json"
                )
            ),
            CapturedAOStub(
                "/api/v1/sessions",
                method: "POST",
                status: 201,
                data: try AgentOrchestratorAdapterTestFixture.data(
                    "spawn.json"
                )
            )
        ])
        let (backend, transport) =
            try AgentOrchestratorAdapterTestFixture.backend(
                stubs: stubs
            )
        let request = AgentOrchestratorAdapterTestFixture.startRequest()

        async let first = backend.start(request)
        async let second = backend.start(request)
        let receipts = try await (first, second)
        let requests = await transport.requests()
        let spawnCandidate = requests.first {
            $0.method == "POST" && $0.path == "/api/v1/sessions"
        }
        let spawn = try #require(spawnCandidate)
        let bodyCandidate = spawn.body
        let body = try #require(bodyCandidate)
        let object = try JSONSerialization.jsonObject(with: body)
        let jsonCandidate = object as? [String: Any]
        let json = try #require(jsonCandidate)
        let spawnCount = requests.filter {
            $0.method == "POST"
                && $0.path == "/api/v1/sessions"
        }.count
        let healthCount = requests.filter {
            $0.method == "GET" && $0.path == "/healthz"
        }.count
        let readinessCount = requests.filter {
            $0.method == "GET" && $0.path == "/readyz"
        }.count
        let specCount = requests.filter {
            $0.method == "GET"
                && $0.path == "/api/v1/openapi.yaml"
        }.count

        #expect(receipts.0 == receipts.1)
        #expect(receipts.0.requestID == request.requestID)
        #expect(receipts.0.executionID == ExecutionID("openmac-7"))
        #expect(spawnCount == 1)
        #expect(healthCount == 1)
        #expect(readinessCount == 1)
        #expect(specCount == 1)
        #expect((json["projectId"] as? String) == "openmac")
        #expect((json["kind"] as? String) == "worker")
        #expect((json["harness"] as? String) == "codex")
        #expect(
            json["branch"] as? String
                == "openmac/aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"
        )
        #expect(
            (json["prompt"] as? String)?.contains(
                "main @ abc123"
            ) == true
        )
    }

    @Test("a new adapter recovers the stable branch without another spawn")
    func restartRecoversSession() async throws {
        let stubs = try AgentOrchestratorAdapterTestFixture.commonStubs([
            CapturedAOStub(
                "/api/v1/projects/openmac",
                data: try AgentOrchestratorAdapterTestFixture.data(
                    "project.json"
                )
            ),
            CapturedAOStub(
                "/api/v1/sessions",
                query: "project=openmac",
                data: try AgentOrchestratorAdapterTestFixture.data(
                    "session-existing.json"
                )
            )
        ])
        let (backend, transport) =
            try AgentOrchestratorAdapterTestFixture.backend(
                stubs: stubs
            )

        let receipt = try await backend.start(
            AgentOrchestratorAdapterTestFixture.startRequest()
        )
        let requests = await transport.requests()

        #expect(receipt.executionID == ExecutionID("openmac-7"))
        #expect(!requests.contains(where: { $0.method == "POST" }))
    }

    @Test("base branch mismatch prevents AO side effects")
    func baseBranchMismatchFailsClosed() async throws {
        let stubs = try AgentOrchestratorAdapterTestFixture.commonStubs([
            CapturedAOStub(
                "/api/v1/projects/openmac",
                data: try AgentOrchestratorAdapterTestFixture.data(
                    "project.json"
                )
            )
        ])
        let (backend, transport) =
            try AgentOrchestratorAdapterTestFixture.backend(
                stubs: stubs
            )

        do {
            _ = try await backend.start(
                AgentOrchestratorAdapterTestFixture.startRequest(
                    baseBranch: "develop"
                )
            )
            Issue.record("Expected AO base-branch mismatch")
        } catch let error as ExecutionBackendError {
            guard case let .conflict(message) = error else {
                Issue.record("Unexpected AO error: \(error)")
                return
            }
            #expect(message.contains("develop"))
            #expect(message.contains("main"))
        }

        let requests = await transport.requests()
        #expect(!requests.contains(where: { $0.method == "POST" }))
    }

    @Test("session snapshots map running, files, PR, and terminal facts")
    func factsContract() async throws {
        let stubs = try AgentOrchestratorAdapterTestFixture.commonStubs([
            CapturedAOStub(
                "/api/v1/sessions/openmac-7",
                data: try AgentOrchestratorAdapterTestFixture.data(
                    "session-running.json"
                )
            ),
            CapturedAOStub(
                "/api/v1/sessions/openmac-7",
                data: try AgentOrchestratorAdapterTestFixture.data(
                    "session-merged.json"
                )
            ),
            CapturedAOStub(
                "/api/v1/sessions/openmac-7/workspace/files",
                data: try AgentOrchestratorAdapterTestFixture.data(
                    "workspace-files.json"
                )
            ),
            CapturedAOStub(
                "/api/v1/sessions/openmac-7/workspace/files",
                data: try AgentOrchestratorAdapterTestFixture.data(
                    "workspace-files.json"
                )
            )
        ])
        let (backend, _) = try AgentOrchestratorAdapterTestFixture.backend(
            stubs: stubs
        )
        let executionID = ExecutionID("openmac-7")

        let running = try await backend.facts(
            for: executionID,
            after: nil
        )
        let terminal = try await backend.facts(
            for: executionID,
            after: running.nextCursor
        )

        #expect(running.hasMore)
        #expect(running.nextCursor != nil)
        #expect(
            running.facts.contains(where: {
                if case .phase(.running) = $0.body {
                    return true
                }
                return false
            })
        )
        #expect(
            running.facts.contains(where: {
                if case let .changedFilesEvidence(evidence) = $0.body {
                    return evidence.paths.count == 2
                }
                return false
            })
        )
        #expect(
            running.facts.contains(where: {
                if case let .pullRequestEvidence(evidence) = $0.body {
                    return evidence.state == .open
                        && evidence.checks == .passing
                        && evidence.review == .approved
                }
                return false
            })
        )
        #expect(!terminal.hasMore)
        #expect(
            terminal.facts.first?.sequence
                == (running.facts.last?.sequence ?? 0) + 1
        )
        #expect(
            terminal.facts.contains(where: {
                if case .phase(.succeeded) = $0.body {
                    return true
                }
                return false
            })
        )
        #expect(
            terminal.facts.contains(where: {
                if case let .pullRequestEvidence(evidence) = $0.body {
                    return evidence.state == .merged
                }
                return false
            })
        )
    }

    @Test("an unchanged running snapshot produces an idle polling page")
    func unchangedSnapshotDoesNotReplayFacts() async throws {
        let stubs = try AgentOrchestratorAdapterTestFixture.commonStubs([
            CapturedAOStub(
                "/api/v1/sessions/openmac-7",
                data: try AgentOrchestratorAdapterTestFixture.data(
                    "session-running.json"
                )
            ),
            CapturedAOStub(
                "/api/v1/sessions/openmac-7",
                data: try AgentOrchestratorAdapterTestFixture.data(
                    "session-running.json"
                )
            ),
            CapturedAOStub(
                "/api/v1/sessions/openmac-7/workspace/files",
                data: try AgentOrchestratorAdapterTestFixture.data(
                    "workspace-files.json"
                )
            ),
            CapturedAOStub(
                "/api/v1/sessions/openmac-7/workspace/files",
                data: try AgentOrchestratorAdapterTestFixture.data(
                    "workspace-files.json"
                )
            )
        ])
        let (backend, _) = try AgentOrchestratorAdapterTestFixture.backend(
            stubs: stubs
        )
        let executionID = ExecutionID("openmac-7")

        let first = try await backend.facts(for: executionID, after: nil)
        let second = try await backend.facts(
            for: executionID,
            after: first.nextCursor
        )

        #expect(!first.facts.isEmpty)
        #expect(second.facts.isEmpty)
        #expect(second.nextCursor == first.nextCursor)
        #expect(second.hasMore)
    }

    @Test("unknown AO session state maps to Unknown and never success")
    func unknownSessionStateFailsClosed() async throws {
        let stubs = try AgentOrchestratorAdapterTestFixture.commonStubs([
            CapturedAOStub(
                "/api/v1/sessions/openmac-7",
                data: try AgentOrchestratorAdapterTestFixture.data(
                    "session-unknown.json"
                )
            ),
            CapturedAOStub(
                "/api/v1/sessions/openmac-7/workspace/files",
                data: try AgentOrchestratorAdapterTestFixture.data(
                    "workspace-files.json"
                )
            )
        ])
        let (backend, _) = try AgentOrchestratorAdapterTestFixture.backend(
            stubs: stubs
        )

        let page = try await backend.facts(
            for: ExecutionID("openmac-7"),
            after: nil
        )

        #expect(page.hasMore)
        #expect(page.facts.contains(where: {
            if case .unknown = $0.body { return true }
            return false
        }))
        #expect(!page.facts.contains(where: {
            if case .phase(.succeeded) = $0.body { return true }
            return false
        }))
    }

    @Test("terminated AO session requires an explicit stopped fact")
    func terminatedSessionMapsStopped() async throws {
        let stubs = try AgentOrchestratorAdapterTestFixture.commonStubs([
            CapturedAOStub(
                "/api/v1/sessions/openmac-7",
                data: try AgentOrchestratorAdapterTestFixture.data(
                    "session-terminated.json"
                )
            ),
            CapturedAOStub(
                "/api/v1/sessions/openmac-7/workspace/files",
                data: try AgentOrchestratorAdapterTestFixture.data(
                    "workspace-files.json"
                )
            )
        ])
        let (backend, _) = try AgentOrchestratorAdapterTestFixture.backend(
            stubs: stubs
        )

        let page = try await backend.facts(
            for: ExecutionID("openmac-7"),
            after: nil
        )

        #expect(!page.hasMore)
        #expect(page.facts.contains(where: {
            if case .phase(.stopped) = $0.body { return true }
            return false
        }))
        #expect(!page.facts.contains(where: {
            if case .phase(.succeeded) = $0.body { return true }
            return false
        }))
    }

    @Test("kill maps the AO acknowledgement to a stop receipt")
    func stopContract() async throws {
        let stubs = try AgentOrchestratorAdapterTestFixture.commonStubs([
            CapturedAOStub(
                "/api/v1/sessions/openmac-7",
                data: try AgentOrchestratorAdapterTestFixture.data(
                    "session-running.json"
                )
            ),
            CapturedAOStub(
                "/api/v1/sessions/openmac-7/kill",
                method: "POST",
                data: try AgentOrchestratorAdapterTestFixture.data(
                    "kill.json"
                )
            )
        ])
        let (backend, _) = try AgentOrchestratorAdapterTestFixture.backend(
            stubs: stubs
        )

        let receipt = try await backend.stop(
            executionID: ExecutionID("openmac-7")
        )

        #expect(receipt.executionID == ExecutionID("openmac-7"))
        #expect(receipt.disposition == .accepted)
        #expect(
            receipt.acknowledgedAt
                == AgentOrchestratorAdapterTestFixture.observedAt
        )
    }

    @Test("configuration rejects non-loopback daemon URLs")
    func rejectsRemoteDaemonURL() {
        #expect(throws: AgentOrchestratorAdapterConfigurationError.self) {
            _ = try AgentOrchestratorBackendConfiguration(
                baseURL: URL(string: "https://ao.example.com")!
            )
        }
        #expect(throws: AgentOrchestratorAdapterConfigurationError.self) {
            _ = try AgentOrchestratorBackendConfiguration(
                baseURL: URL(string: "http://127.0.0.1:3001")!,
                expectedDaemonPID: 0
            )
        }
    }
}
