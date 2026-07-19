import Foundation

nonisolated enum DeliveryRunValidationIssueCode: String, Equatable, Sendable {
    case invalidPlan
    case attemptWithoutApproval
    case duplicateAttemptID
    case missingAttemptTask
    case attemptPlanMismatch
    case invalidAttemptSequence
    case duplicateAttemptSequence
    case duplicateAttemptIdempotencyKey
    case multipleActiveAttempts
    case reusedExternalSession
    case sessionBackendMismatch
    case duplicateEvidenceFactID
    case duplicateRawObservationID
    case missingEvidenceTask
    case missingEvidenceAttempt
    case evidenceAttemptTaskMismatch
    case missingEvidenceRequirement
    case invalidSupersededEvidence
    case cyclicEvidenceSupersession
    case missingPullRequestTask
    case duplicatePullRequestID
    case missingPullRequestAttempt
    case pullRequestAttemptTaskMismatch
}

nonisolated struct DeliveryRunValidationIssue: Equatable, Sendable {
    let code: DeliveryRunValidationIssueCode
    let message: String
    let taskID: UUID?
    let attemptID: UUID?

    nonisolated init(
        code: DeliveryRunValidationIssueCode,
        message: String,
        taskID: UUID? = nil,
        attemptID: UUID? = nil
    ) {
        self.code = code
        self.message = message
        self.taskID = taskID
        self.attemptID = attemptID
    }
}

nonisolated enum DeliveryRunValidator {
    nonisolated static func validate(_ run: DeliveryRun) -> [DeliveryRunValidationIssue] {
        var issues: [DeliveryRunValidationIssue] = []

        guard let plan = run.plan else {
            if !run.attempts.isEmpty || !run.evidenceFacts.isEmpty || !run.pullRequests.isEmpty {
                issues.append(
                    DeliveryRunValidationIssue(
                        code: .invalidPlan,
                        message: "A run cannot contain attempts or evidence without a delivery plan."
                    )
                )
            }
            return issues
        }

        let hasDeliveryFacts = !run.attempts.isEmpty
            || !run.evidenceFacts.isEmpty
            || !run.pullRequests.isEmpty
        if !DeliveryPlanValidator.isValid(plan)
            && (plan.approval != nil || hasDeliveryFacts) {
            issues.append(
                DeliveryRunValidationIssue(
                    code: .invalidPlan,
                    message: "Only an unapproved draft without delivery facts may contain an invalid plan."
                )
            )
        }

        if !run.attempts.isEmpty && plan.approval == nil {
            issues.append(
                DeliveryRunValidationIssue(
                    code: .attemptWithoutApproval,
                    message: "Execution attempts require an approved delivery plan."
                )
            )
        }

        var tasksByID: [UUID: DeliveryTask] = [:]
        for task in plan.tasks where tasksByID[task.id] == nil {
            tasksByID[task.id] = task
        }
        let attemptsByID = uniqueAttemptsByID(run.attempts)
        validateAttempts(
            run.attempts,
            plan: plan,
            tasksByID: tasksByID,
            issues: &issues
        )
        validateEvidence(
            run.evidenceFacts,
            tasksByID: tasksByID,
            attemptsByID: attemptsByID,
            issues: &issues
        )
        validatePullRequests(
            run.pullRequests,
            tasksByID: tasksByID,
            attemptsByID: attemptsByID,
            issues: &issues
        )
        return issues
    }

    nonisolated static func isValid(_ run: DeliveryRun) -> Bool {
        validate(run).isEmpty
    }

    nonisolated private static func validateAttempts(
        _ attempts: [ExecutionAttempt],
        plan: DeliveryPlan,
        tasksByID: [UUID: DeliveryTask],
        issues: inout [DeliveryRunValidationIssue]
    ) {
        var seenAttemptIDs: Set<UUID> = []
        var seenSequenceKeys: Set<String> = []
        var seenIdempotencyKeys: Set<UUID> = []
        var activeAttemptCountByTaskID: [UUID: Int] = [:]
        var taskIDByExternalSession: [ExternalSessionRef: UUID] = [:]

        for attempt in attempts {
            if !seenAttemptIDs.insert(attempt.id).inserted {
                issues.append(
                    DeliveryRunValidationIssue(
                        code: .duplicateAttemptID,
                        message: "Execution attempt IDs must be unique.",
                        taskID: attempt.taskID,
                        attemptID: attempt.id
                    )
                )
            }

            if tasksByID[attempt.taskID] == nil {
                issues.append(
                    DeliveryRunValidationIssue(
                        code: .missingAttemptTask,
                        message: "An execution attempt references a task outside the active plan.",
                        taskID: attempt.taskID,
                        attemptID: attempt.id
                    )
                )
            }

            if attempt.planID != plan.id || attempt.planRevision != plan.revision {
                issues.append(
                    DeliveryRunValidationIssue(
                        code: .attemptPlanMismatch,
                        message: "An execution attempt references a different plan revision.",
                        taskID: attempt.taskID,
                        attemptID: attempt.id
                    )
                )
            }

            if attempt.sequence < 1 {
                issues.append(
                    DeliveryRunValidationIssue(
                        code: .invalidAttemptSequence,
                        message: "Attempt sequence numbers start at one.",
                        taskID: attempt.taskID,
                        attemptID: attempt.id
                    )
                )
            }

            let sequenceKey = "\(attempt.taskID.uuidString):\(attempt.sequence)"
            if !seenSequenceKeys.insert(sequenceKey).inserted {
                issues.append(
                    DeliveryRunValidationIssue(
                        code: .duplicateAttemptSequence,
                        message: "Attempt sequence numbers must be unique within a task.",
                        taskID: attempt.taskID,
                        attemptID: attempt.id
                    )
                )
            }

            if !seenIdempotencyKeys.insert(attempt.idempotencyKey).inserted {
                issues.append(
                    DeliveryRunValidationIssue(
                        code: .duplicateAttemptIdempotencyKey,
                        message: "Each execution attempt needs a unique idempotency key.",
                        taskID: attempt.taskID,
                        attemptID: attempt.id
                    )
                )
            }

            if isActive(attempt.status) {
                activeAttemptCountByTaskID[attempt.taskID, default: 0] += 1
            }

            if let session = attempt.externalSession {
                if session.backendID != attempt.backendID {
                    issues.append(
                        DeliveryRunValidationIssue(
                            code: .sessionBackendMismatch,
                            message: "The external session backend does not match its execution attempt.",
                            taskID: attempt.taskID,
                            attemptID: attempt.id
                        )
                    )
                }
                if taskIDByExternalSession[session] != nil {
                    issues.append(
                        DeliveryRunValidationIssue(
                            code: .reusedExternalSession,
                            message: "An external session can belong to only one execution attempt.",
                            taskID: attempt.taskID,
                            attemptID: attempt.id
                        )
                    )
                } else {
                    taskIDByExternalSession[session] = attempt.taskID
                }
            }
        }

        for (taskID, activeCount) in activeAttemptCountByTaskID where activeCount > 1 {
            issues.append(
                DeliveryRunValidationIssue(
                    code: .multipleActiveAttempts,
                    message: "A task can have at most one active or unresolved attempt.",
                    taskID: taskID
                )
            )
        }
    }

    nonisolated private static func validateEvidence(
        _ facts: [EvidenceFact],
        tasksByID: [UUID: DeliveryTask],
        attemptsByID: [UUID: ExecutionAttempt],
        issues: inout [DeliveryRunValidationIssue]
    ) {
        var seenFactIDs: Set<UUID> = []
        var seenRawObservationIDs: Set<String> = []
        var factsByID: [UUID: EvidenceFact] = [:]
        for fact in facts where factsByID[fact.id] == nil {
            factsByID[fact.id] = fact
        }

        for fact in facts {
            if !seenFactIDs.insert(fact.id).inserted {
                issues.append(
                    DeliveryRunValidationIssue(
                        code: .duplicateEvidenceFactID,
                        message: "Evidence fact IDs must be unique.",
                        taskID: fact.taskID,
                        attemptID: fact.attemptID
                    )
                )
            }

            if let rawObservationID = fact.rawObservationID,
               !seenRawObservationIDs.insert(rawObservationID).inserted {
                issues.append(
                    DeliveryRunValidationIssue(
                        code: .duplicateRawObservationID,
                        message: "An external observation can be imported only once.",
                        taskID: fact.taskID,
                        attemptID: fact.attemptID
                    )
                )
            }

            guard let task = tasksByID[fact.taskID] else {
                issues.append(
                    DeliveryRunValidationIssue(
                        code: .missingEvidenceTask,
                        message: "Evidence references a task outside the active plan.",
                        taskID: fact.taskID,
                        attemptID: fact.attemptID
                    )
                )
                continue
            }

            guard let attempt = attemptsByID[fact.attemptID] else {
                issues.append(
                    DeliveryRunValidationIssue(
                        code: .missingEvidenceAttempt,
                        message: "Evidence references a missing execution attempt.",
                        taskID: fact.taskID,
                        attemptID: fact.attemptID
                    )
                )
                continue
            }

            if attempt.taskID != fact.taskID {
                issues.append(
                    DeliveryRunValidationIssue(
                        code: .evidenceAttemptTaskMismatch,
                        message: "Evidence task and attempt identities do not match.",
                        taskID: fact.taskID,
                        attemptID: fact.attemptID
                    )
                )
            }

            if !task.evidenceRequirements.contains(where: { $0.id == fact.requirementID }) {
                issues.append(
                    DeliveryRunValidationIssue(
                        code: .missingEvidenceRequirement,
                        message: "Evidence references a requirement outside its task.",
                        taskID: fact.taskID,
                        attemptID: fact.attemptID
                    )
                )
            }

            if let supersededID = fact.supersedesFactID {
                guard let superseded = factsByID[supersededID],
                      superseded.taskID == fact.taskID,
                      superseded.attemptID == fact.attemptID,
                      superseded.requirementID == fact.requirementID else {
                    issues.append(
                        DeliveryRunValidationIssue(
                            code: .invalidSupersededEvidence,
                            message: "A superseding fact must reference evidence for the same task, attempt, and requirement.",
                            taskID: fact.taskID,
                            attemptID: fact.attemptID
                        )
                    )
                    continue
                }
            }
        }

        if hasSupersessionCycle(factsByID: factsByID) {
            issues.append(
                DeliveryRunValidationIssue(
                    code: .cyclicEvidenceSupersession,
                    message: "Evidence supersession must be acyclic."
                )
            )
        }
    }

    nonisolated private static func hasSupersessionCycle(
        factsByID: [UUID: EvidenceFact]
    ) -> Bool {
        enum VisitState: Equatable {
            case visiting
            case visited
        }

        var states: [UUID: VisitState] = [:]

        func visit(_ factID: UUID) -> Bool {
            if let state = states[factID] {
                return state == .visiting
            }

            states[factID] = .visiting
            if let supersededID = factsByID[factID]?.supersedesFactID,
               factsByID[supersededID] != nil,
               visit(supersededID) {
                return true
            }
            states[factID] = .visited
            return false
        }

        return factsByID.keys.contains(where: visit)
    }

    nonisolated private static func validatePullRequests(
        _ pullRequests: [PullRequestRef],
        tasksByID: [UUID: DeliveryTask],
        attemptsByID: [UUID: ExecutionAttempt],
        issues: inout [DeliveryRunValidationIssue]
    ) {
        var seenPullRequestIDs: Set<String> = []
        for pullRequest in pullRequests {
            if !seenPullRequestIDs.insert(pullRequest.id).inserted {
                issues.append(
                    DeliveryRunValidationIssue(
                        code: .duplicatePullRequestID,
                        message: "Pull request identities must be unique within a delivery run.",
                        taskID: pullRequest.taskID,
                        attemptID: pullRequest.attemptID
                    )
                )
            }

            if tasksByID[pullRequest.taskID] == nil {
                issues.append(
                    DeliveryRunValidationIssue(
                        code: .missingPullRequestTask,
                        message: "A pull request references a task outside the active plan.",
                        taskID: pullRequest.taskID,
                        attemptID: pullRequest.attemptID
                    )
                )
            }

            guard let attempt = attemptsByID[pullRequest.attemptID] else {
                issues.append(
                    DeliveryRunValidationIssue(
                        code: .missingPullRequestAttempt,
                        message: "A pull request references a missing execution attempt.",
                        taskID: pullRequest.taskID,
                        attemptID: pullRequest.attemptID
                    )
                )
                continue
            }

            if attempt.taskID != pullRequest.taskID {
                issues.append(
                    DeliveryRunValidationIssue(
                        code: .pullRequestAttemptTaskMismatch,
                        message: "Pull request task and attempt identities do not match.",
                        taskID: pullRequest.taskID,
                        attemptID: pullRequest.attemptID
                    )
                )
            }
        }
    }

    nonisolated private static func uniqueAttemptsByID(
        _ attempts: [ExecutionAttempt]
    ) -> [UUID: ExecutionAttempt] {
        var result: [UUID: ExecutionAttempt] = [:]
        for attempt in attempts where result[attempt.id] == nil {
            result[attempt.id] = attempt
        }
        return result
    }

    nonisolated private static func isActive(_ status: ExecutionAttemptStatus) -> Bool {
        switch status {
        case .queued, .running, .blocked, .unknown:
            return true
        case .succeeded, .failed, .stopped:
            return false
        }
    }
}
