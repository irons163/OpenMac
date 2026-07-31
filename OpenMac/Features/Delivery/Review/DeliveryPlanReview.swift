import Foundation

nonisolated struct DeliveryPlanReviewWave: Identifiable, Equatable, Sendable {
    let number: Int
    let taskIDs: [UUID]

    nonisolated var id: Int {
        number
    }
}

nonisolated struct DeliveryPlanReviewSummary: Equatable, Sendable {
    let taskCount: Int
    let estimatedSessionCount: Int
    let maximumParallelSessionCount: Int
    let lowRiskTaskCount: Int
    let mediumRiskTaskCount: Int
    let highRiskTaskCount: Int
    let waves: [DeliveryPlanReviewWave]
    let unresolvedTaskIDs: [UUID]

    nonisolated var isGraphFullyScheduled: Bool {
        unresolvedTaskIDs.isEmpty
    }

    nonisolated func waveNumber(for taskID: UUID) -> Int? {
        waves.first(where: { $0.taskIDs.contains(taskID) })?.number
    }
}

nonisolated enum DeliveryPlanReviewAnalyzer {
    nonisolated static func summarize(_ plan: DeliveryPlan) -> DeliveryPlanReviewSummary {
        var taskOrder: [UUID] = []
        var seenTaskIDs: Set<UUID> = []
        for task in plan.tasks where seenTaskIDs.insert(task.id).inserted {
            taskOrder.append(task.id)
        }

        let graph = DeliveryPlanGraphAnalyzer.analyze(plan)
        guard graph.isAvailable else {
            return makeSummary(
                plan: plan,
                waves: [],
                unresolvedTaskIDs: taskOrder
            )
        }

        return makeSummary(
            plan: plan,
            waves: graph.waves.map {
                DeliveryPlanReviewWave(number: $0.number, taskIDs: $0.taskIDs)
            },
            unresolvedTaskIDs: []
        )
    }

    nonisolated private static func makeSummary(
        plan: DeliveryPlan,
        waves: [DeliveryPlanReviewWave],
        unresolvedTaskIDs: [UUID]
    ) -> DeliveryPlanReviewSummary {
        DeliveryPlanReviewSummary(
            taskCount: plan.tasks.count,
            estimatedSessionCount: plan.tasks.count,
            maximumParallelSessionCount: waves.map(\.taskIDs.count).max() ?? 0,
            lowRiskTaskCount: plan.tasks.count(where: { $0.riskLevel == .low }),
            mediumRiskTaskCount: plan.tasks.count(where: { $0.riskLevel == .medium }),
            highRiskTaskCount: plan.tasks.count(where: { $0.riskLevel == .high }),
            waves: waves,
            unresolvedTaskIDs: unresolvedTaskIDs
        )
    }
}

nonisolated struct DeliveryPlanReviewDraft: Equatable, Sendable {
    private(set) var plan: DeliveryPlan

    nonisolated init(plan: DeliveryPlan) {
        self.plan = plan
    }

    @discardableResult
    nonisolated mutating func updateTaskTitle(taskID: UUID, title: String) -> Bool {
        updateTask(taskID: taskID) { $0.title = title }
    }

    @discardableResult
    nonisolated mutating func updateWorkerPrompt(taskID: UUID, prompt: String) -> Bool {
        updateTask(taskID: taskID) { $0.workerPrompt = prompt }
    }

    @discardableResult
    nonisolated mutating func updateRiskLevel(
        taskID: UUID,
        riskLevel: DeliveryRiskLevel
    ) -> Bool {
        updateTask(taskID: taskID) { $0.riskLevel = riskLevel }
    }

    @discardableResult
    nonisolated mutating func updateHumanActionHint(
        taskID: UUID,
        hint: String?
    ) -> Bool {
        updateTask(taskID: taskID) { $0.humanActionHint = hint }
    }

    @discardableResult
    nonisolated mutating func updateAcceptanceCriterion(
        taskID: UUID,
        criterionID: UUID,
        statement: String
    ) -> Bool {
        guard plan.approval == nil,
              let taskIndex = plan.tasks.firstIndex(where: { $0.id == taskID }),
              let criterionIndex = plan.tasks[taskIndex].acceptanceCriteria
                .firstIndex(where: { $0.id == criterionID }) else {
            return false
        }
        plan.tasks[taskIndex].acceptanceCriteria[criterionIndex].statement = statement
        return true
    }

    @discardableResult
    nonisolated mutating func addTask(_ task: DeliveryTask) -> Bool {
        guard plan.approval == nil,
              !plan.tasks.contains(where: { $0.id == task.id }) else {
            return false
        }
        plan.tasks.append(task)
        return true
    }

    @discardableResult
    nonisolated mutating func removeTask(taskID: UUID) -> Bool {
        guard plan.approval == nil,
              plan.tasks.contains(where: { $0.id == taskID }) else {
            return false
        }
        plan.tasks.removeAll { $0.id == taskID }
        plan.dependencyEdges.removeAll {
            $0.prerequisiteTaskID == taskID || $0.dependentTaskID == taskID
        }
        return true
    }

    @discardableResult
    nonisolated mutating func addAcceptanceCriterion(
        taskID: UUID,
        criterion: AcceptanceCriterion
    ) -> Bool {
        guard plan.approval == nil,
              let taskIndex = plan.tasks.firstIndex(where: { $0.id == taskID }),
              !plan.tasks[taskIndex].acceptanceCriteria
                .contains(where: { $0.id == criterion.id }) else {
            return false
        }
        plan.tasks[taskIndex].acceptanceCriteria.append(criterion)
        return true
    }

    @discardableResult
    nonisolated mutating func removeAcceptanceCriterion(
        taskID: UUID,
        criterionID: UUID
    ) -> Bool {
        guard plan.approval == nil,
              let taskIndex = plan.tasks.firstIndex(where: { $0.id == taskID }),
              plan.tasks[taskIndex].acceptanceCriteria
                .contains(where: { $0.id == criterionID }) else {
            return false
        }
        plan.tasks[taskIndex].acceptanceCriteria.removeAll { $0.id == criterionID }
        for evidenceIndex in plan.tasks[taskIndex].evidenceRequirements.indices {
            plan.tasks[taskIndex].evidenceRequirements[evidenceIndex]
                .coveredCriterionIDs.removeAll { $0 == criterionID }
        }
        return true
    }

    @discardableResult
    nonisolated mutating func addEvidenceRequirement(
        taskID: UUID,
        requirement: EvidenceRequirement
    ) -> Bool {
        guard plan.approval == nil,
              let taskIndex = plan.tasks.firstIndex(where: { $0.id == taskID }),
              !plan.tasks[taskIndex].evidenceRequirements
                .contains(where: { $0.id == requirement.id }) else {
            return false
        }
        plan.tasks[taskIndex].evidenceRequirements.append(requirement)
        return true
    }

    @discardableResult
    nonisolated mutating func removeEvidenceRequirement(
        taskID: UUID,
        requirementID: UUID
    ) -> Bool {
        guard plan.approval == nil,
              let taskIndex = plan.tasks.firstIndex(where: { $0.id == taskID }),
              plan.tasks[taskIndex].evidenceRequirements
                .contains(where: { $0.id == requirementID }) else {
            return false
        }
        plan.tasks[taskIndex].evidenceRequirements.removeAll {
            $0.id == requirementID
        }
        return true
    }

    @discardableResult
    nonisolated mutating func updateEvidenceKind(
        taskID: UUID,
        requirementID: UUID,
        kind: EvidenceKind
    ) -> Bool {
        updateEvidenceRequirement(
            taskID: taskID,
            requirementID: requirementID
        ) {
            $0.kind = kind
        }
    }

    @discardableResult
    nonisolated mutating func updateEvidenceDescription(
        taskID: UUID,
        requirementID: UUID,
        description: String
    ) -> Bool {
        updateEvidenceRequirement(
            taskID: taskID,
            requirementID: requirementID
        ) {
            $0.description = description
        }
    }

    @discardableResult
    nonisolated mutating func setEvidenceCoverage(
        taskID: UUID,
        requirementID: UUID,
        criterionID: UUID,
        isCovered: Bool
    ) -> Bool {
        guard plan.approval == nil,
              let task = plan.tasks.first(where: { $0.id == taskID }),
              task.acceptanceCriteria.contains(where: { $0.id == criterionID }) else {
            return false
        }
        return updateEvidenceRequirement(
            taskID: taskID,
            requirementID: requirementID
        ) { requirement in
            let currentlyCovered = requirement.coveredCriterionIDs.contains(criterionID)
            guard currentlyCovered != isCovered else { return }
            if isCovered {
                requirement.coveredCriterionIDs.append(criterionID)
            } else {
                requirement.coveredCriterionIDs.removeAll { $0 == criterionID }
            }
        }
    }

    @discardableResult
    nonisolated mutating func setDependency(
        prerequisiteTaskID: UUID,
        dependentTaskID: UUID,
        isEnabled: Bool
    ) -> Bool {
        guard plan.approval == nil,
              prerequisiteTaskID != dependentTaskID else {
            return false
        }
        let taskIDs = Set(plan.tasks.map(\.id))
        guard taskIDs.contains(prerequisiteTaskID),
              taskIDs.contains(dependentTaskID) else {
            return false
        }

        let edge = DependencyEdge(
            prerequisiteTaskID: prerequisiteTaskID,
            dependentTaskID: dependentTaskID
        )
        let currentlyEnabled = plan.dependencyEdges.contains(edge)
        guard currentlyEnabled != isEnabled else { return false }

        if isEnabled {
            plan.dependencyEdges.append(edge)
        } else {
            plan.dependencyEdges.removeAll { $0 == edge }
        }
        return true
    }

    @discardableResult
    nonisolated mutating func removeDependency(_ edge: DependencyEdge) -> Bool {
        guard plan.approval == nil,
              plan.dependencyEdges.contains(edge) else {
            return false
        }
        plan.dependencyEdges.removeAll { $0 == edge }
        return true
    }

    @discardableResult
    nonisolated mutating func resolveGenerationIssue(
        _ issue: DeliveryPlanGenerationIssue
    ) -> Bool {
        guard plan.approval == nil,
              plan.unresolvedGenerationBlockers.contains(issue) else {
            return false
        }
        plan.unresolvedGenerationBlockers.removeAll { $0 == issue }
        return true
    }

    nonisolated func hasDependency(
        prerequisiteTaskID: UUID,
        dependentTaskID: UUID
    ) -> Bool {
        plan.dependencyEdges.contains(
            DependencyEdge(
                prerequisiteTaskID: prerequisiteTaskID,
                dependentTaskID: dependentTaskID
            )
        )
    }

    @discardableResult
    nonisolated private mutating func updateTask(
        taskID: UUID,
        mutation: (inout DeliveryTask) -> Void
    ) -> Bool {
        guard plan.approval == nil,
              let taskIndex = plan.tasks.firstIndex(where: { $0.id == taskID }) else {
            return false
        }
        mutation(&plan.tasks[taskIndex])
        return true
    }

    @discardableResult
    nonisolated private mutating func updateEvidenceRequirement(
        taskID: UUID,
        requirementID: UUID,
        mutation: (inout EvidenceRequirement) -> Void
    ) -> Bool {
        guard plan.approval == nil,
              let taskIndex = plan.tasks.firstIndex(where: { $0.id == taskID }),
              let requirementIndex = plan.tasks[taskIndex].evidenceRequirements
                .firstIndex(where: { $0.id == requirementID }) else {
            return false
        }
        mutation(&plan.tasks[taskIndex].evidenceRequirements[requirementIndex])
        return true
    }
}

nonisolated enum DeliveryPlanReviewError: Error, Equatable, LocalizedError, Sendable {
    case missingPlan
    case planIdentityChanged
    case stalePlanRevision(expected: Int, current: Int)
    case storeRevisionChanged(expected: Int, current: Int)
    case planRevisionExhausted(current: Int)
    case approvedPlanCannotBeEdited
    case planAlreadyApproved
    case stoppedRunCannotBeEdited
    case deliveryFactsAlreadyExist
    case proposedApprovalNotAllowed
    case noChanges
    case reviewerRequired
    case reviewerTooLong(maximumBytes: Int)
    case reviewTimestampPrecedesPersistedState
    case invalidPlan(issueCodes: [DeliveryPlanValidationIssueCode])
    case fingerprintUnavailable
    case missingRepositoryIdentity
    case scopeFingerprintUnavailable
    case invalidRun(issueCodes: [DeliveryRunValidationIssueCode])

    nonisolated var errorDescription: String? {
        switch self {
        case .missingPlan:
            return "A delivery plan is required for review."
        case .planIdentityChanged:
            return "The reviewed plan does not match the active delivery plan."
        case let .stalePlanRevision(expected, current):
            return "Plan revision changed from \(expected) to \(current)."
        case let .storeRevisionChanged(expected, current):
            return "Delivery store revision changed from \(expected) to \(current)."
        case let .planRevisionExhausted(current):
            return "Plan revision \(current) cannot be incremented."
        case .approvedPlanCannotBeEdited:
            return "An approved plan cannot be edited."
        case .planAlreadyApproved:
            return "The delivery plan is already approved."
        case .stoppedRunCannotBeEdited:
            return "A stopped delivery run cannot be edited or approved."
        case .deliveryFactsAlreadyExist:
            return "A plan cannot be reviewed after delivery facts exist."
        case .proposedApprovalNotAllowed:
            return "A review draft cannot provide its own approval record."
        case .noChanges:
            return "The review draft has no changes to save."
        case .reviewerRequired:
            return "A reviewer identity is required."
        case let .reviewerTooLong(maximumBytes):
            return "The reviewer identity exceeds \(maximumBytes) UTF-8 bytes."
        case .reviewTimestampPrecedesPersistedState:
            return "The review timestamp cannot precede the persisted delivery state."
        case let .invalidPlan(issueCodes):
            return "The plan cannot be approved: \(issueCodes.map(\.rawValue).joined(separator: ", "))."
        case .fingerprintUnavailable:
            return "The approved plan fingerprint could not be created."
        case .missingRepositoryIdentity:
            return "Approval requires a trusted repository identity."
        case .scopeFingerprintUnavailable:
            return "The approval scope fingerprint could not be created."
        case let .invalidRun(issueCodes):
            return "The approved delivery run is invalid: \(issueCodes.map(\.rawValue).joined(separator: ", "))."
        }
    }
}

nonisolated enum DeliveryPlanReviewApplicator {
    nonisolated static let maximumReviewerByteCount =
        DeliveryPlanApproval.maximumReviewerByteCount

    nonisolated static func hasContentChanges(
        proposedPlan: DeliveryPlan,
        persistedPlan: DeliveryPlan
    ) -> Bool {
        proposedPlan.tasks != persistedPlan.tasks
            || proposedPlan.dependencyEdges != persistedPlan.dependencyEdges
            || proposedPlan.unresolvedGenerationBlockers
                != persistedPlan.unresolvedGenerationBlockers
    }

    nonisolated static func savingDraft(
        _ proposedPlan: DeliveryPlan,
        to run: DeliveryRun,
        expectedPlanRevision: Int,
        savedAt: Date = Date()
    ) throws -> DeliveryRun {
        let prepared = try prepareDraft(
            proposedPlan,
            in: run,
            expectedPlanRevision: expectedPlanRevision,
            requireChanges: true,
            changedAt: savedAt
        )
        var updatedRun = run
        updatedRun.plan = prepared
        updatedRun.updatedAt = savedAt
        return updatedRun
    }

    nonisolated static func approving(
        _ proposedPlan: DeliveryPlan,
        in run: DeliveryRun,
        expectedPlanRevision: Int,
        approvedBy: String,
        approvedAt: Date = Date()
    ) throws -> DeliveryRun {
        guard run.plan?.approval == nil else {
            throw DeliveryPlanReviewError.planAlreadyApproved
        }

        let reviewer = approvedBy.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !reviewer.isEmpty else {
            throw DeliveryPlanReviewError.reviewerRequired
        }
        guard reviewer.utf8.count <= maximumReviewerByteCount else {
            throw DeliveryPlanReviewError.reviewerTooLong(
                maximumBytes: maximumReviewerByteCount
            )
        }

        var prepared = try prepareDraft(
            proposedPlan,
            in: run,
            expectedPlanRevision: expectedPlanRevision,
            requireChanges: false,
            changedAt: approvedAt
        )
        let issueCodes = DeliveryPlanValidator.validate(prepared).map(\.code)
        guard issueCodes.isEmpty else {
            throw DeliveryPlanReviewError.invalidPlan(issueCodes: issueCodes)
        }
        guard let fingerprint = DeliveryPlanFingerprint.make(for: prepared) else {
            throw DeliveryPlanReviewError.fingerprintUnavailable
        }
        guard let repositoryIdentity = run.repositoryIdentity else {
            throw DeliveryPlanReviewError.missingRepositoryIdentity
        }
        guard let scopeFingerprint = DeliveryApprovalScopeFingerprint.make(
            runID: run.id,
            runCreatedAt: run.createdAt,
            brief: run.brief,
            repositoryIdentity: repositoryIdentity,
            planFingerprint: fingerprint,
            approvedAt: approvedAt,
            approvedBy: reviewer
        ) else {
            throw DeliveryPlanReviewError.scopeFingerprintUnavailable
        }

        prepared.approval = DeliveryPlanApproval(
            planID: prepared.id,
            planRevision: prepared.revision,
            planFingerprint: fingerprint,
            scopeFingerprint: scopeFingerprint,
            approvedAt: approvedAt,
            approvedBy: reviewer
        )
        prepared.updatedAt = approvedAt
        let approvedIssueCodes = DeliveryPlanValidator.validate(prepared).map(\.code)
        guard approvedIssueCodes.isEmpty else {
            throw DeliveryPlanReviewError.invalidPlan(issueCodes: approvedIssueCodes)
        }

        var updatedRun = run
        updatedRun.plan = prepared
        updatedRun.updatedAt = approvedAt
        let runIssueCodes = DeliveryRunValidator.validate(updatedRun).map(\.code)
        guard runIssueCodes.isEmpty else {
            throw DeliveryPlanReviewError.invalidRun(issueCodes: runIssueCodes)
        }
        return updatedRun
    }

    nonisolated private static func prepareDraft(
        _ proposedPlan: DeliveryPlan,
        in run: DeliveryRun,
        expectedPlanRevision: Int,
        requireChanges: Bool,
        changedAt: Date
    ) throws -> DeliveryPlan {
        guard let persistedPlan = run.plan else {
            throw DeliveryPlanReviewError.missingPlan
        }
        guard persistedPlan.id == proposedPlan.id else {
            throw DeliveryPlanReviewError.planIdentityChanged
        }
        guard persistedPlan.revision == expectedPlanRevision else {
            throw DeliveryPlanReviewError.stalePlanRevision(
                expected: expectedPlanRevision,
                current: persistedPlan.revision
            )
        }
        guard persistedPlan.approval == nil else {
            throw DeliveryPlanReviewError.approvedPlanCannotBeEdited
        }
        guard proposedPlan.approval == nil else {
            throw DeliveryPlanReviewError.proposedApprovalNotAllowed
        }
        guard run.stoppedAt == nil else {
            throw DeliveryPlanReviewError.stoppedRunCannotBeEdited
        }
        guard run.attempts.isEmpty,
              run.executionObservations.isEmpty,
              run.evidenceFacts.isEmpty,
              run.pullRequests.isEmpty else {
            throw DeliveryPlanReviewError.deliveryFactsAlreadyExist
        }
        guard changedAt >= run.createdAt,
              changedAt >= run.updatedAt,
              changedAt >= persistedPlan.createdAt,
              changedAt >= persistedPlan.updatedAt else {
            throw DeliveryPlanReviewError.reviewTimestampPrecedesPersistedState
        }

        let hasChanges = hasContentChanges(
            proposedPlan: proposedPlan,
            persistedPlan: persistedPlan
        )
        if requireChanges, !hasChanges {
            throw DeliveryPlanReviewError.noChanges
        }

        let revision: Int
        if hasChanges {
            guard persistedPlan.revision < Int.max else {
                throw DeliveryPlanReviewError.planRevisionExhausted(
                    current: persistedPlan.revision
                )
            }
            revision = persistedPlan.revision + 1
        } else {
            revision = persistedPlan.revision
        }

        return DeliveryPlan(
            id: persistedPlan.id,
            revision: revision,
            tasks: proposedPlan.tasks,
            dependencyEdges: proposedPlan.dependencyEdges,
            unresolvedGenerationBlockers: proposedPlan.unresolvedGenerationBlockers,
            createdAt: persistedPlan.createdAt,
            updatedAt: hasChanges ? changedAt : persistedPlan.updatedAt
        )
    }
}

nonisolated protocol DeliveryPlanReviewPersisting: DeliveryFixtureReviewPersisting {
    func saveReviewedPlanDraft(
        _ proposedPlan: DeliveryPlan,
        toRunID runID: UUID,
        expectedStoreRevision: Int,
        expectedPlanRevision: Int
    ) async throws -> DeliveryRunSnapshot

    func approveReviewedPlan(
        _ proposedPlan: DeliveryPlan,
        inRunID runID: UUID,
        expectedStoreRevision: Int,
        expectedPlanRevision: Int,
        approvedBy: String
    ) async throws -> DeliveryRunSnapshot
}
