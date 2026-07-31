import Foundation

nonisolated enum DeliveryRiskLevel: String, CaseIterable, Codable, Sendable {
    case low
    case medium
    case high
}

nonisolated enum DeliveryContainerKind: String, Codable, Sendable {
    case xcodeProject
    case xcodeWorkspace
    case swiftPackage
}

nonisolated enum DeliveryPlanGenerationIssueSeverity: String, Equatable, Codable, Sendable {
    case warning
    case blocking
}

nonisolated enum DeliveryPlanGenerationIssueCode: String, Equatable, Codable, Sendable {
    case taskCountOutOfRange
    case invalidRevision
    case missingTaskKey
    case duplicateTaskKey
    case missingAcceptanceCriterionKey
    case duplicateAcceptanceCriterionKey
    case missingEvidenceRequirementKey
    case duplicateEvidenceRequirementKey
    case missingRiskLevel
    case unknownRiskLevel
    case unknownEvidenceKind
    case unknownAcceptanceCriterionKey
    case unknownDependencyTaskKey
    case ambiguousDependencyTaskKey
    case textualDependencyNotAllowed
    case missingPlanningHint
    case unknownTargetHint
    case unknownSchemeHint
    case invalidPlan

    nonisolated var severity: DeliveryPlanGenerationIssueSeverity {
        switch self {
        case .missingTaskKey,
             .duplicateTaskKey,
             .missingAcceptanceCriterionKey,
             .duplicateAcceptanceCriterionKey,
             .missingEvidenceRequirementKey,
             .duplicateEvidenceRequirementKey,
             .missingRiskLevel,
             .unknownRiskLevel,
             .unknownEvidenceKind,
             .ambiguousDependencyTaskKey,
             .unknownTargetHint,
             .unknownSchemeHint:
            return .blocking
        case .taskCountOutOfRange,
             .invalidRevision,
             .unknownAcceptanceCriterionKey,
             .unknownDependencyTaskKey,
             .textualDependencyNotAllowed,
             .missingPlanningHint,
             .invalidPlan:
            return .warning
        }
    }
}

nonisolated struct DeliveryPlanGenerationIssue: Equatable, Codable, Sendable {
    let code: DeliveryPlanGenerationIssueCode
    let fieldPath: String
    let message: String

    nonisolated var severity: DeliveryPlanGenerationIssueSeverity {
        code.severity
    }

    nonisolated init(
        code: DeliveryPlanGenerationIssueCode,
        fieldPath: String,
        message: String
    ) {
        self.code = code
        self.fieldPath = fieldPath
        self.message = message
    }
}

nonisolated struct DeliveryRepositoryReference: Equatable, Codable, Sendable {
    var rootPath: String
    var baseBranch: String
    var xcodeContainerRelativePath: String?

    nonisolated init(
        rootPath: String,
        baseBranch: String,
        xcodeContainerRelativePath: String? = nil
    ) {
        self.rootPath = rootPath
        self.baseBranch = baseBranch
        self.xcodeContainerRelativePath = xcodeContainerRelativePath
    }
}

nonisolated struct DeliveryRepositoryIdentitySnapshot: Equatable, Codable, Sendable {
    let repositoryRootPath: String
    let resolvedRepositoryRootPath: String
    let repositoryFileIdentity: String
    let containerKind: DeliveryContainerKind
    let containerRelativePath: String
    let resolvedContainerPath: String
    let containerFileIdentity: String
    let gitCommonDirectoryPath: String
    let gitCommonDirectoryFileIdentity: String
    let baseCommitIdentifier: String

    private enum CodingKeys: String, CodingKey {
        case repositoryRootPath
        case resolvedRepositoryRootPath
        case repositoryFileIdentity
        case containerKind
        case containerRelativePath
        case resolvedContainerPath
        case containerFileIdentity
        case gitCommonDirectoryPath
        case gitCommonDirectoryFileIdentity
        case baseCommitIdentifier
    }

    nonisolated init(
        repositoryRootPath: String,
        resolvedRepositoryRootPath: String,
        repositoryFileIdentity: String,
        containerKind: DeliveryContainerKind,
        containerRelativePath: String,
        resolvedContainerPath: String,
        containerFileIdentity: String,
        gitCommonDirectoryPath: String,
        gitCommonDirectoryFileIdentity: String,
        baseCommitIdentifier: String
    ) {
        self.repositoryRootPath = repositoryRootPath
        self.resolvedRepositoryRootPath = resolvedRepositoryRootPath
        self.repositoryFileIdentity = repositoryFileIdentity
        self.containerKind = containerKind
        self.containerRelativePath = containerRelativePath
        self.resolvedContainerPath = resolvedContainerPath
        self.containerFileIdentity = containerFileIdentity
        self.gitCommonDirectoryPath = gitCommonDirectoryPath
        self.gitCommonDirectoryFileIdentity = gitCommonDirectoryFileIdentity
        self.baseCommitIdentifier = baseCommitIdentifier
    }

    nonisolated init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        repositoryRootPath = try container.decode(
            String.self,
            forKey: .repositoryRootPath
        )
        resolvedRepositoryRootPath = try container.decode(
            String.self,
            forKey: .resolvedRepositoryRootPath
        )
        repositoryFileIdentity = try container.decodeIfPresent(
            String.self,
            forKey: .repositoryFileIdentity
        ) ?? ""
        containerKind = try container.decode(
            DeliveryContainerKind.self,
            forKey: .containerKind
        )
        containerRelativePath = try container.decode(
            String.self,
            forKey: .containerRelativePath
        )
        resolvedContainerPath = try container.decode(
            String.self,
            forKey: .resolvedContainerPath
        )
        containerFileIdentity = try container.decodeIfPresent(
            String.self,
            forKey: .containerFileIdentity
        ) ?? ""
        gitCommonDirectoryPath = try container.decodeIfPresent(
            String.self,
            forKey: .gitCommonDirectoryPath
        ) ?? ""
        gitCommonDirectoryFileIdentity = try container.decodeIfPresent(
            String.self,
            forKey: .gitCommonDirectoryFileIdentity
        ) ?? ""
        baseCommitIdentifier = try container.decodeIfPresent(
            String.self,
            forKey: .baseCommitIdentifier
        ) ?? ""
    }
}

nonisolated struct FeatureBrief: Identifiable, Equatable, Codable, Sendable {
    let id: UUID
    var title: String
    var body: String
    var repository: DeliveryRepositoryReference
    let createdAt: Date

    nonisolated init(
        id: UUID = UUID(),
        title: String,
        body: String,
        repository: DeliveryRepositoryReference,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.body = body
        self.repository = repository
        self.createdAt = createdAt
    }
}

nonisolated struct AcceptanceCriterion: Identifiable, Equatable, Codable, Sendable {
    let id: UUID
    var statement: String

    nonisolated init(id: UUID = UUID(), statement: String) {
        self.id = id
        self.statement = statement
    }
}

nonisolated enum EvidenceKind: String, CaseIterable, Codable, Sendable {
    case xcodeBuild
    case xcodeTest
    case changedFiles
    case screenshot
    case pullRequest
    case ciChecks
    case reviewApproval
    case custom
}

nonisolated struct EvidenceRequirement: Identifiable, Equatable, Codable, Sendable {
    let id: UUID
    var kind: EvidenceKind
    var description: String
    var coveredCriterionIDs: [UUID]

    nonisolated init(
        id: UUID = UUID(),
        kind: EvidenceKind,
        description: String,
        coveredCriterionIDs: [UUID]
    ) {
        self.id = id
        self.kind = kind
        self.description = description
        self.coveredCriterionIDs = coveredCriterionIDs
    }
}

nonisolated struct DeliveryTask: Identifiable, Equatable, Codable, Sendable {
    let id: UUID
    var title: String
    var workerPrompt: String
    var acceptanceCriteria: [AcceptanceCriterion]
    var riskLevel: DeliveryRiskLevel
    var evidenceRequirements: [EvidenceRequirement]
    var targetHints: [String]
    var schemeHints: [String]
    var humanActionHint: String?

    nonisolated init(
        id: UUID = UUID(),
        title: String,
        workerPrompt: String,
        acceptanceCriteria: [AcceptanceCriterion],
        riskLevel: DeliveryRiskLevel,
        evidenceRequirements: [EvidenceRequirement],
        targetHints: [String] = [],
        schemeHints: [String] = [],
        humanActionHint: String? = nil
    ) {
        self.id = id
        self.title = title
        self.workerPrompt = workerPrompt
        self.acceptanceCriteria = acceptanceCriteria
        self.riskLevel = riskLevel
        self.evidenceRequirements = evidenceRequirements
        self.targetHints = targetHints
        self.schemeHints = schemeHints
        self.humanActionHint = humanActionHint
    }
}

nonisolated struct DependencyEdge: Equatable, Hashable, Codable, Sendable {
    let prerequisiteTaskID: UUID
    let dependentTaskID: UUID

    nonisolated init(prerequisiteTaskID: UUID, dependentTaskID: UUID) {
        self.prerequisiteTaskID = prerequisiteTaskID
        self.dependentTaskID = dependentTaskID
    }
}

nonisolated struct DeliveryPlanApproval: Equatable, Codable, Sendable {
    nonisolated static let maximumReviewerByteCount = 1_024

    let planID: UUID
    let planRevision: Int
    let planFingerprint: String
    let scopeFingerprint: String
    let approvedAt: Date
    let approvedBy: String

    private enum CodingKeys: String, CodingKey {
        case planID
        case planRevision
        case planFingerprint
        case scopeFingerprint
        case approvedAt
        case approvedBy
    }

    nonisolated init(
        planID: UUID,
        planRevision: Int,
        planFingerprint: String,
        scopeFingerprint: String,
        approvedAt: Date = Date(),
        approvedBy: String
    ) {
        self.planID = planID
        self.planRevision = planRevision
        self.planFingerprint = planFingerprint
        self.scopeFingerprint = scopeFingerprint
        self.approvedAt = approvedAt
        self.approvedBy = approvedBy
    }

    nonisolated init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        planID = try container.decode(UUID.self, forKey: .planID)
        planRevision = try container.decode(Int.self, forKey: .planRevision)
        planFingerprint = try container.decode(String.self, forKey: .planFingerprint)
        scopeFingerprint = try container.decodeIfPresent(
            String.self,
            forKey: .scopeFingerprint
        ) ?? ""
        approvedAt = try container.decode(Date.self, forKey: .approvedAt)
        approvedBy = try container.decode(String.self, forKey: .approvedBy)
    }
}

nonisolated struct DeliveryPlan: Identifiable, Equatable, Codable, Sendable {
    let id: UUID
    var revision: Int
    var tasks: [DeliveryTask]
    var dependencyEdges: [DependencyEdge]
    var unresolvedGenerationBlockers: [DeliveryPlanGenerationIssue]
    var approval: DeliveryPlanApproval?
    let createdAt: Date
    var updatedAt: Date

    private enum CodingKeys: String, CodingKey {
        case id
        case revision
        case tasks
        case dependencyEdges
        case unresolvedGenerationBlockers
        case approval
        case createdAt
        case updatedAt
    }

    nonisolated init(
        id: UUID = UUID(),
        revision: Int = 1,
        tasks: [DeliveryTask],
        dependencyEdges: [DependencyEdge] = [],
        unresolvedGenerationBlockers: [DeliveryPlanGenerationIssue] = [],
        approval: DeliveryPlanApproval? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.revision = revision
        self.tasks = tasks
        self.dependencyEdges = dependencyEdges
        self.unresolvedGenerationBlockers = unresolvedGenerationBlockers
        self.approval = approval
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    nonisolated init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        revision = try container.decode(Int.self, forKey: .revision)
        tasks = try container.decode([DeliveryTask].self, forKey: .tasks)
        dependencyEdges = try container.decode([DependencyEdge].self, forKey: .dependencyEdges)
        unresolvedGenerationBlockers = try container.decodeIfPresent(
            [DeliveryPlanGenerationIssue].self,
            forKey: .unresolvedGenerationBlockers
        ) ?? []
        approval = try container.decodeIfPresent(DeliveryPlanApproval.self, forKey: .approval)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }
}

nonisolated enum ExecutionAttemptStatus: String, Codable, Sendable {
    case queued
    case running
    case blocked
    case succeeded
    case failed
    case stopped
    case unknown
}

nonisolated struct ExternalSessionRef: Equatable, Hashable, Codable, Sendable {
    let backendID: String
    let projectID: String
    let sessionID: String
    let branch: String?
    let verificationWorkspacePath: String?

    nonisolated init(
        backendID: String,
        projectID: String,
        sessionID: String,
        branch: String? = nil,
        verificationWorkspacePath: String? = nil
    ) {
        self.backendID = backendID
        self.projectID = projectID
        self.sessionID = sessionID
        self.branch = branch
        self.verificationWorkspacePath = verificationWorkspacePath
    }
}

nonisolated struct ExecutionAttempt: Identifiable, Equatable, Codable, Sendable {
    let id: UUID
    let taskID: UUID
    let planID: UUID
    let planRevision: Int
    let sequence: Int
    let backendID: String
    let projectID: String?
    let idempotencyKey: UUID
    var status: ExecutionAttemptStatus
    var externalSession: ExternalSessionRef?
    let createdAt: Date
    var dispatchRequestedAt: Date?
    var dispatchFailureReason: String?
    var lastReconcileFailureReason: String?
    var lastReconcileFailedAt: Date?
    var startedAt: Date?
    var endedAt: Date?
    var stopRequestedAt: Date?
    var nextFactCursor: String?
    var lastFactSequence: UInt64?
    var isFactStreamExhausted: Bool

    private enum CodingKeys: String, CodingKey {
        case id
        case taskID
        case planID
        case planRevision
        case sequence
        case backendID
        case projectID
        case idempotencyKey
        case status
        case externalSession
        case createdAt
        case dispatchRequestedAt
        case dispatchFailureReason
        case lastReconcileFailureReason
        case lastReconcileFailedAt
        case startedAt
        case endedAt
        case stopRequestedAt
        case nextFactCursor
        case lastFactSequence
        case isFactStreamExhausted
    }

    nonisolated init(
        id: UUID = UUID(),
        taskID: UUID,
        planID: UUID,
        planRevision: Int,
        sequence: Int,
        backendID: String,
        projectID: String? = nil,
        idempotencyKey: UUID = UUID(),
        status: ExecutionAttemptStatus = .queued,
        externalSession: ExternalSessionRef? = nil,
        createdAt: Date = Date(),
        dispatchRequestedAt: Date? = nil,
        dispatchFailureReason: String? = nil,
        lastReconcileFailureReason: String? = nil,
        lastReconcileFailedAt: Date? = nil,
        startedAt: Date? = nil,
        endedAt: Date? = nil,
        stopRequestedAt: Date? = nil,
        nextFactCursor: String? = nil,
        lastFactSequence: UInt64? = nil,
        isFactStreamExhausted: Bool = false
    ) {
        self.id = id
        self.taskID = taskID
        self.planID = planID
        self.planRevision = planRevision
        self.sequence = sequence
        self.backendID = backendID
        self.projectID = projectID
        self.idempotencyKey = idempotencyKey
        self.status = status
        self.externalSession = externalSession
        self.createdAt = createdAt
        self.dispatchRequestedAt = dispatchRequestedAt
        self.dispatchFailureReason = dispatchFailureReason
        self.lastReconcileFailureReason = lastReconcileFailureReason
        self.lastReconcileFailedAt = lastReconcileFailedAt
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.stopRequestedAt = stopRequestedAt
        self.nextFactCursor = nextFactCursor
        self.lastFactSequence = lastFactSequence
        self.isFactStreamExhausted = isFactStreamExhausted
    }

    nonisolated init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        taskID = try container.decode(UUID.self, forKey: .taskID)
        planID = try container.decode(UUID.self, forKey: .planID)
        planRevision = try container.decode(Int.self, forKey: .planRevision)
        sequence = try container.decode(Int.self, forKey: .sequence)
        backendID = try container.decode(String.self, forKey: .backendID)
        projectID = try container.decodeIfPresent(String.self, forKey: .projectID)
        idempotencyKey = try container.decode(UUID.self, forKey: .idempotencyKey)
        status = try container.decode(
            ExecutionAttemptStatus.self,
            forKey: .status
        )
        externalSession = try container.decodeIfPresent(
            ExternalSessionRef.self,
            forKey: .externalSession
        )
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        dispatchRequestedAt = try container.decodeIfPresent(
            Date.self,
            forKey: .dispatchRequestedAt
        )
        dispatchFailureReason = try container.decodeIfPresent(
            String.self,
            forKey: .dispatchFailureReason
        )
        lastReconcileFailureReason = try container.decodeIfPresent(
            String.self,
            forKey: .lastReconcileFailureReason
        )
        lastReconcileFailedAt = try container.decodeIfPresent(
            Date.self,
            forKey: .lastReconcileFailedAt
        )
        startedAt = try container.decodeIfPresent(Date.self, forKey: .startedAt)
        endedAt = try container.decodeIfPresent(Date.self, forKey: .endedAt)
        stopRequestedAt = try container.decodeIfPresent(
            Date.self,
            forKey: .stopRequestedAt
        )
        nextFactCursor = try container.decodeIfPresent(
            String.self,
            forKey: .nextFactCursor
        )
        lastFactSequence = try container.decodeIfPresent(
            UInt64.self,
            forKey: .lastFactSequence
        )
        isFactStreamExhausted = try container.decodeIfPresent(
            Bool.self,
            forKey: .isFactStreamExhausted
        ) ?? false
    }
}

nonisolated enum ExecutionBackendObservationKind: String, Codable, Sendable {
    case phase
    case inputRequested
    case commandEvidence
    case changedFilesEvidence
    case pullRequestEvidence
    case diagnostic
    case unknown
}

nonisolated struct ExecutionBackendObservation:
    Identifiable,
    Equatable,
    Codable,
    Sendable
{
    let id: String
    let taskID: UUID
    let attemptID: UUID
    let sequence: UInt64
    let occurredAt: Date
    let receivedAt: Date
    let kind: ExecutionBackendObservationKind
    let summary: String
    let rawPayload: String?
    let retryable: Bool?

    nonisolated init(
        id: String,
        taskID: UUID,
        attemptID: UUID,
        sequence: UInt64,
        occurredAt: Date,
        receivedAt: Date,
        kind: ExecutionBackendObservationKind,
        summary: String,
        rawPayload: String? = nil,
        retryable: Bool? = nil
    ) {
        self.id = id
        self.taskID = taskID
        self.attemptID = attemptID
        self.sequence = sequence
        self.occurredAt = occurredAt
        self.receivedAt = receivedAt
        self.kind = kind
        self.summary = summary
        self.rawPayload = rawPayload
        self.retryable = retryable
    }
}

nonisolated enum EvidenceResult: String, Codable, Sendable {
    case passed
    case failed
    case unavailable
    case unknown
}

nonisolated enum EvidenceSource: String, Codable, Sendable {
    case executionBackend
    case git
    case xcodeVerifier
    case github
    case human
}

nonisolated enum XcodeVerificationKind: String, Codable, Sendable {
    case build
    case test

    nonisolated var evidenceKind: EvidenceKind {
        switch self {
        case .build:
            return .xcodeBuild
        case .test:
            return .xcodeTest
        }
    }
}

nonisolated struct XcodeVerificationRecord:
    Identifiable,
    Equatable,
    Codable,
    Sendable
{
    let id: UUID
    let kind: XcodeVerificationKind
    let scheme: String
    let command: String
    let workingDirectoryPath: String
    let exitCode: Int32
    let timedOut: Bool
    let summary: String
    let resultBundlePath: String?
    let startedAt: Date
    let endedAt: Date

    nonisolated init(
        id: UUID = UUID(),
        kind: XcodeVerificationKind,
        scheme: String,
        command: String,
        workingDirectoryPath: String,
        exitCode: Int32,
        timedOut: Bool,
        summary: String,
        resultBundlePath: String? = nil,
        startedAt: Date,
        endedAt: Date
    ) {
        self.id = id
        self.kind = kind
        self.scheme = scheme
        self.command = command
        self.workingDirectoryPath = workingDirectoryPath
        self.exitCode = exitCode
        self.timedOut = timedOut
        self.summary = summary
        self.resultBundlePath = resultBundlePath
        self.startedAt = startedAt
        self.endedAt = endedAt
    }
}

nonisolated struct EvidenceFact: Identifiable, Equatable, Codable, Sendable {
    let id: UUID
    let taskID: UUID
    let attemptID: UUID
    let requirementID: UUID
    var result: EvidenceResult
    var source: EvidenceSource
    var summary: String
    var sourceReference: String?
    let observedAt: Date
    let receivedAt: Date
    let rawObservationID: String?
    let supersedesFactID: UUID?
    let xcodeVerification: XcodeVerificationRecord?

    nonisolated init(
        id: UUID = UUID(),
        taskID: UUID,
        attemptID: UUID,
        requirementID: UUID,
        result: EvidenceResult,
        source: EvidenceSource,
        summary: String,
        sourceReference: String? = nil,
        observedAt: Date = Date(),
        receivedAt: Date = Date(),
        rawObservationID: String? = nil,
        supersedesFactID: UUID? = nil,
        xcodeVerification: XcodeVerificationRecord? = nil
    ) {
        self.id = id
        self.taskID = taskID
        self.attemptID = attemptID
        self.requirementID = requirementID
        self.result = result
        self.source = source
        self.summary = summary
        self.sourceReference = sourceReference
        self.observedAt = observedAt
        self.receivedAt = receivedAt
        self.rawObservationID = rawObservationID
        self.supersedesFactID = supersedesFactID
        self.xcodeVerification = xcodeVerification
    }
}

nonisolated enum PullRequestState: String, Codable, Sendable {
    case open
    case merged
    case closed
    case unknown
}

nonisolated enum PullRequestChecksState: String, Codable, Sendable {
    case pending
    case passed
    case failed
    case unknown
}

nonisolated enum PullRequestReviewState: String, Codable, Sendable {
    case pending
    case approved
    case changesRequested
    case notRequired
    case unknown
}

nonisolated struct PullRequestRef: Identifiable, Equatable, Codable, Sendable {
    let id: String
    let taskID: UUID
    let attemptID: UUID
    var url: URL
    var headBranch: String
    var headCommitIdentifier: String?
    var baseBranch: String
    var state: PullRequestState
    var checksState: PullRequestChecksState
    var reviewState: PullRequestReviewState

    nonisolated init(
        id: String,
        taskID: UUID,
        attemptID: UUID,
        url: URL,
        headBranch: String,
        headCommitIdentifier: String? = nil,
        baseBranch: String,
        state: PullRequestState = .open,
        checksState: PullRequestChecksState = .unknown,
        reviewState: PullRequestReviewState = .unknown
    ) {
        self.id = id
        self.taskID = taskID
        self.attemptID = attemptID
        self.url = url
        self.headBranch = headBranch
        self.headCommitIdentifier = headCommitIdentifier
        self.baseBranch = baseBranch
        self.state = state
        self.checksState = checksState
        self.reviewState = reviewState
    }
}

nonisolated enum DerivedDeliveryState: String, CaseIterable, Codable, Sendable {
    case draft
    case awaitingApproval
    case queued
    case running
    case needsYou
    case verifying
    case readyToMerge
    case done
    case stopped
}

nonisolated struct DeliveryRun: Identifiable, Equatable, Codable, Sendable {
    let id: UUID
    var brief: FeatureBrief
    var repositoryIdentity: DeliveryRepositoryIdentitySnapshot?
    var plan: DeliveryPlan?
    var attempts: [ExecutionAttempt]
    var executionObservations: [ExecutionBackendObservation]
    var evidenceFacts: [EvidenceFact]
    var pullRequests: [PullRequestRef]
    let createdAt: Date
    var updatedAt: Date
    var stoppedAt: Date?

    private enum CodingKeys: String, CodingKey {
        case id
        case brief
        case repositoryIdentity
        case plan
        case attempts
        case executionObservations
        case evidenceFacts
        case pullRequests
        case createdAt
        case updatedAt
        case stoppedAt
    }

    nonisolated init(
        id: UUID = UUID(),
        brief: FeatureBrief,
        repositoryIdentity: DeliveryRepositoryIdentitySnapshot? = nil,
        plan: DeliveryPlan? = nil,
        attempts: [ExecutionAttempt] = [],
        executionObservations: [ExecutionBackendObservation] = [],
        evidenceFacts: [EvidenceFact] = [],
        pullRequests: [PullRequestRef] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        stoppedAt: Date? = nil
    ) {
        self.id = id
        self.brief = brief
        self.repositoryIdentity = repositoryIdentity
        self.plan = plan
        self.attempts = attempts
        self.executionObservations = executionObservations
        self.evidenceFacts = evidenceFacts
        self.pullRequests = pullRequests
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.stoppedAt = stoppedAt
    }

    nonisolated init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        brief = try container.decode(FeatureBrief.self, forKey: .brief)
        repositoryIdentity = try container.decodeIfPresent(
            DeliveryRepositoryIdentitySnapshot.self,
            forKey: .repositoryIdentity
        )
        plan = try container.decodeIfPresent(DeliveryPlan.self, forKey: .plan)
        attempts = try container.decode([ExecutionAttempt].self, forKey: .attempts)
        executionObservations = try container.decodeIfPresent(
            [ExecutionBackendObservation].self,
            forKey: .executionObservations
        ) ?? []
        evidenceFacts = try container.decode([EvidenceFact].self, forKey: .evidenceFacts)
        pullRequests = try container.decode([PullRequestRef].self, forKey: .pullRequests)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        stoppedAt = try container.decodeIfPresent(Date.self, forKey: .stoppedAt)
    }
}
