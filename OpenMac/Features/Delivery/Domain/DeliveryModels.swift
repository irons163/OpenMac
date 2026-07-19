import Foundation

nonisolated enum DeliveryRiskLevel: String, CaseIterable, Codable, Sendable {
    case low
    case medium
    case high
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
    let planID: UUID
    let planRevision: Int
    let planFingerprint: String
    let approvedAt: Date
    let approvedBy: String

    nonisolated init(
        planID: UUID,
        planRevision: Int,
        planFingerprint: String,
        approvedAt: Date = Date(),
        approvedBy: String
    ) {
        self.planID = planID
        self.planRevision = planRevision
        self.planFingerprint = planFingerprint
        self.approvedAt = approvedAt
        self.approvedBy = approvedBy
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

    nonisolated init(backendID: String, projectID: String, sessionID: String) {
        self.backendID = backendID
        self.projectID = projectID
        self.sessionID = sessionID
    }
}

nonisolated struct ExecutionAttempt: Identifiable, Equatable, Codable, Sendable {
    let id: UUID
    let taskID: UUID
    let planID: UUID
    let planRevision: Int
    let sequence: Int
    let backendID: String
    let idempotencyKey: UUID
    var status: ExecutionAttemptStatus
    var externalSession: ExternalSessionRef?
    let createdAt: Date
    var dispatchRequestedAt: Date?
    var dispatchFailureReason: String?
    var startedAt: Date?
    var endedAt: Date?
    var stopRequestedAt: Date?

    nonisolated init(
        id: UUID = UUID(),
        taskID: UUID,
        planID: UUID,
        planRevision: Int,
        sequence: Int,
        backendID: String,
        idempotencyKey: UUID = UUID(),
        status: ExecutionAttemptStatus = .queued,
        externalSession: ExternalSessionRef? = nil,
        createdAt: Date = Date(),
        dispatchRequestedAt: Date? = nil,
        dispatchFailureReason: String? = nil,
        startedAt: Date? = nil,
        endedAt: Date? = nil,
        stopRequestedAt: Date? = nil
    ) {
        self.id = id
        self.taskID = taskID
        self.planID = planID
        self.planRevision = planRevision
        self.sequence = sequence
        self.backendID = backendID
        self.idempotencyKey = idempotencyKey
        self.status = status
        self.externalSession = externalSession
        self.createdAt = createdAt
        self.dispatchRequestedAt = dispatchRequestedAt
        self.dispatchFailureReason = dispatchFailureReason
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.stopRequestedAt = stopRequestedAt
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
        supersedesFactID: UUID? = nil
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
    var plan: DeliveryPlan?
    var attempts: [ExecutionAttempt]
    var evidenceFacts: [EvidenceFact]
    var pullRequests: [PullRequestRef]
    let createdAt: Date
    var updatedAt: Date
    var stoppedAt: Date?

    nonisolated init(
        id: UUID = UUID(),
        brief: FeatureBrief,
        plan: DeliveryPlan? = nil,
        attempts: [ExecutionAttempt] = [],
        evidenceFacts: [EvidenceFact] = [],
        pullRequests: [PullRequestRef] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        stoppedAt: Date? = nil
    ) {
        self.id = id
        self.brief = brief
        self.plan = plan
        self.attempts = attempts
        self.evidenceFacts = evidenceFacts
        self.pullRequests = pullRequests
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.stoppedAt = stoppedAt
    }
}
