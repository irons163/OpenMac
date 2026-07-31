import Foundation

nonisolated struct ExecutionProjectID: Hashable, Codable, Sendable {
    let rawValue: String

    nonisolated init(_ rawValue: String) {
        self.rawValue = rawValue
    }
}

nonisolated struct ExecutionID: Hashable, Codable, Sendable {
    let rawValue: String

    nonisolated init(_ rawValue: String) {
        self.rawValue = rawValue
    }
}

nonisolated struct ExecutionFactID: Hashable, Codable, Sendable {
    let rawValue: String

    nonisolated init(_ rawValue: String) {
        self.rawValue = rawValue
    }
}

nonisolated struct ExecutionFactCursor: Hashable, Codable, Sendable {
    let rawValue: String

    nonisolated init(_ rawValue: String) {
        self.rawValue = rawValue
    }
}

nonisolated enum ExecutionBackendHealthState: String, Sendable {
    case ready
    case degraded
}

nonisolated struct ExecutionBackendHealth: Equatable, Sendable {
    let state: ExecutionBackendHealthState
    let backendName: String
    let version: String?
    let checkedAt: Date
    let message: String?

    nonisolated init(
        state: ExecutionBackendHealthState,
        backendName: String,
        version: String? = nil,
        checkedAt: Date = Date(),
        message: String? = nil
    ) {
        self.state = state
        self.backendName = backendName
        self.version = version
        self.checkedAt = checkedAt
        self.message = message
    }
}

nonisolated enum ExecutionProjectIsolation: String, Sendable {
    case isolatedWorkspace
    case sharedWorkspace
    case unknown
}

nonisolated struct ExecutionProject: Identifiable, Equatable, Sendable {
    let id: ExecutionProjectID
    let name: String
    let repositoryURL: URL?
    let workspaceHint: String?
    let isolation: ExecutionProjectIsolation

    nonisolated init(
        id: ExecutionProjectID,
        name: String,
        repositoryURL: URL? = nil,
        workspaceHint: String? = nil,
        isolation: ExecutionProjectIsolation = .unknown
    ) {
        self.id = id
        self.name = name
        self.repositoryURL = repositoryURL
        self.workspaceHint = workspaceHint
        self.isolation = isolation
    }
}

nonisolated struct ExecutionStartRequest: Equatable, Sendable {
    let requestID: UUID
    let projectID: ExecutionProjectID
    let deliveryRunID: UUID
    let taskID: UUID
    let planID: UUID
    let planRevision: Int
    let approvalFingerprint: String
    let title: String
    let instructions: String
    let baseBranch: String
    let baseCommitIdentifier: String

    nonisolated init(
        requestID: UUID,
        projectID: ExecutionProjectID,
        deliveryRunID: UUID,
        taskID: UUID,
        planID: UUID,
        planRevision: Int,
        approvalFingerprint: String,
        title: String,
        instructions: String,
        baseBranch: String,
        baseCommitIdentifier: String
    ) {
        self.requestID = requestID
        self.projectID = projectID
        self.deliveryRunID = deliveryRunID
        self.taskID = taskID
        self.planID = planID
        self.planRevision = planRevision
        self.approvalFingerprint = approvalFingerprint
        self.title = title
        self.instructions = instructions
        self.baseBranch = baseBranch
        self.baseCommitIdentifier = baseCommitIdentifier
    }
}

nonisolated struct ExecutionStartReceipt: Equatable, Sendable {
    let requestID: UUID
    let executionID: ExecutionID
    let acceptedAt: Date

    nonisolated init(requestID: UUID, executionID: ExecutionID, acceptedAt: Date) {
        self.requestID = requestID
        self.executionID = executionID
        self.acceptedAt = acceptedAt
    }
}

nonisolated enum ExecutionPhase: String, Sendable {
    case accepted
    case running
    case waitingForInput
    case stopping
    case stopped
    case succeeded
    case failed
}

nonisolated enum ExecutionCommandKind: String, Sendable {
    case xcodeBuild
    case test
    case other
}

nonisolated struct ExecutionCommandEvidence: Equatable, Sendable {
    let kind: ExecutionCommandKind
    let command: String
    let exitCode: Int
    let summary: String
    let artifactPaths: [String]

    nonisolated init(
        kind: ExecutionCommandKind,
        command: String,
        exitCode: Int,
        summary: String,
        artifactPaths: [String] = []
    ) {
        self.kind = kind
        self.command = command
        self.exitCode = exitCode
        self.summary = summary
        self.artifactPaths = artifactPaths
    }
}

nonisolated struct ExecutionChangedFilesEvidence: Equatable, Sendable {
    let paths: [String]

    nonisolated init(paths: [String]) {
        self.paths = paths
    }
}

nonisolated enum ExecutionPullRequestState: String, Sendable {
    case open
    case merged
    case closed
}

nonisolated enum ExecutionCheckState: String, Sendable {
    case unknown
    case pending
    case passing
    case failing
}

nonisolated enum ExecutionReviewState: String, Sendable {
    case unknown
    case required
    case approved
    case changesRequested
}

nonisolated struct ExecutionPullRequestEvidence: Equatable, Sendable {
    let url: URL
    let headSHA: String?
    let state: ExecutionPullRequestState
    let checks: ExecutionCheckState
    let review: ExecutionReviewState

    nonisolated init(
        url: URL,
        headSHA: String? = nil,
        state: ExecutionPullRequestState,
        checks: ExecutionCheckState,
        review: ExecutionReviewState
    ) {
        self.url = url
        self.headSHA = headSHA
        self.state = state
        self.checks = checks
        self.review = review
    }
}

nonisolated enum ExecutionDiagnosticSeverity: String, Sendable {
    case info
    case warning
    case error
}

nonisolated struct ExecutionDiagnostic: Equatable, Sendable {
    let severity: ExecutionDiagnosticSeverity
    let code: String?
    let message: String
    let retryable: Bool

    nonisolated init(
        severity: ExecutionDiagnosticSeverity,
        code: String? = nil,
        message: String,
        retryable: Bool
    ) {
        self.severity = severity
        self.code = code
        self.message = message
        self.retryable = retryable
    }
}

nonisolated enum ExecutionFactBody: Equatable, Sendable {
    case phase(ExecutionPhase)
    case inputRequested(prompt: String)
    case commandEvidence(ExecutionCommandEvidence)
    case changedFilesEvidence(ExecutionChangedFilesEvidence)
    case pullRequestEvidence(ExecutionPullRequestEvidence)
    case diagnostic(ExecutionDiagnostic)
    case unknown(kind: String, rawPayload: String?)
}

nonisolated struct ExecutionFact: Identifiable, Equatable, Sendable {
    let id: ExecutionFactID
    let executionID: ExecutionID
    let sequence: UInt64
    let occurredAt: Date
    let body: ExecutionFactBody

    nonisolated init(
        id: ExecutionFactID,
        executionID: ExecutionID,
        sequence: UInt64,
        occurredAt: Date,
        body: ExecutionFactBody
    ) {
        self.id = id
        self.executionID = executionID
        self.sequence = sequence
        self.occurredAt = occurredAt
        self.body = body
    }
}

nonisolated struct ExecutionFactPage: Equatable, Sendable {
    let facts: [ExecutionFact]
    let nextCursor: ExecutionFactCursor?
    let hasMore: Bool

    nonisolated init(
        facts: [ExecutionFact],
        nextCursor: ExecutionFactCursor?,
        hasMore: Bool
    ) {
        self.facts = facts
        self.nextCursor = nextCursor
        self.hasMore = hasMore
    }
}

nonisolated enum ExecutionStopDisposition: String, Sendable {
    case accepted
    case alreadyStopped
    case alreadyTerminal
}

nonisolated struct ExecutionStopReceipt: Equatable, Sendable {
    let executionID: ExecutionID
    let disposition: ExecutionStopDisposition
    let acknowledgedAt: Date

    nonisolated init(
        executionID: ExecutionID,
        disposition: ExecutionStopDisposition,
        acknowledgedAt: Date
    ) {
        self.executionID = executionID
        self.disposition = disposition
        self.acknowledgedAt = acknowledgedAt
    }
}

nonisolated enum ExecutionBackendOperation: String, Hashable, Sendable {
    case health
    case listProjects
    case start
    case facts
    case stop
}

nonisolated enum ExecutionBackendError:
    Error,
    Equatable,
    LocalizedError,
    Sendable
{
    case unavailable(String)
    case unauthorized
    case projectNotFound(ExecutionProjectID)
    case executionNotFound(ExecutionID)
    case rejected(String)
    case conflict(String)
    case malformedResponse(operation: ExecutionBackendOperation, reason: String)
    case timedOut(ExecutionBackendOperation)

    nonisolated var errorDescription: String? {
        switch self {
        case let .unavailable(message), let .rejected(message):
            return message
        case .unauthorized:
            return "The execution backend rejected authorization."
        case let .projectNotFound(projectID):
            return "Execution project \(projectID.rawValue) was not found."
        case let .executionNotFound(executionID):
            return "Execution \(executionID.rawValue) was not found."
        case let .conflict(message):
            return message
        case let .malformedResponse(operation, reason):
            return "The \(operation.rawValue) response was malformed: \(reason)"
        case let .timedOut(operation):
            return "The execution backend timed out during \(operation.rawValue)."
        }
    }
}

nonisolated protocol ExecutionBackend: Sendable {
    var backendID: String { get }
    var supportsPersistedSessionReconciliation: Bool { get }

    func health() async throws -> ExecutionBackendHealth
    func listProjects() async throws -> [ExecutionProject]
    func start(_ request: ExecutionStartRequest) async throws -> ExecutionStartReceipt
    func facts(
        for executionID: ExecutionID,
        after cursor: ExecutionFactCursor?
    ) async throws -> ExecutionFactPage
    func stop(executionID: ExecutionID) async throws -> ExecutionStopReceipt
}

extension ExecutionBackend {
    nonisolated var supportsPersistedSessionReconciliation: Bool { false }
}
