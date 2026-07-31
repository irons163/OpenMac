import Foundation

nonisolated enum DeliveryRunValidationIssueCode: String, Equatable, Sendable {
    case invalidPlan
    case missingRepositoryIdentity
    case incompleteRepositoryIdentity
    case repositoryIdentityMismatch
    case staleApprovalScope
    case invalidApprovalMetadata
    case attemptWithoutApproval
    case duplicateAttemptID
    case missingAttemptTask
    case attemptPlanMismatch
    case invalidAttemptSequence
    case invalidAttemptChronology
    case duplicateAttemptSequence
    case duplicateAttemptIdempotencyKey
    case multipleActiveAttempts
    case invalidAttemptDispatchBinding
    case invalidAttemptFactCursor
    case reusedExternalSession
    case sessionBackendMismatch
    case sessionProjectMismatch
    case duplicateExecutionObservationID
    case duplicateExecutionObservationSequence
    case missingExecutionObservationTask
    case missingExecutionObservationAttempt
    case executionObservationAttemptTaskMismatch
    case invalidExecutionObservationChronology
    case duplicateEvidenceFactID
    case duplicateRawObservationID
    case missingEvidenceTask
    case missingEvidenceAttempt
    case evidenceAttemptTaskMismatch
    case missingEvidenceRequirement
    case invalidEvidenceChronology
    case invalidXcodeVerification
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
            if !run.attempts.isEmpty
                || !run.executionObservations.isEmpty
                || !run.evidenceFacts.isEmpty
                || !run.pullRequests.isEmpty {
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
            || !run.executionObservations.isEmpty
            || !run.evidenceFacts.isEmpty
            || !run.pullRequests.isEmpty

        if let identity = run.repositoryIdentity {
            let briefRoot = standardizedPath(run.brief.repository.rootPath)
            let identityRoot = standardizedPath(identity.repositoryRootPath)
            let briefContainer = run.brief.repository.xcodeContainerRelativePath
                .map(standardizedPath)
            let identityContainer = standardizedPath(identity.containerRelativePath)
            if briefRoot != identityRoot
                || (briefContainer != nil && briefContainer != identityContainer) {
                issues.append(
                    DeliveryRunValidationIssue(
                        code: .repositoryIdentityMismatch,
                        message: "The persisted repository identity does not match the feature brief."
                    )
                )
            }
        }

        if !DeliveryPlanValidator.isValid(plan)
            && (plan.approval != nil || hasDeliveryFacts) {
            issues.append(
                DeliveryRunValidationIssue(
                    code: .invalidPlan,
                    message: "Only an unapproved draft without delivery facts may contain an invalid plan."
                )
            )
        }

        if let approval = plan.approval {
            let reviewer = approval.approvedBy.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            if reviewer.isEmpty
                || reviewer.utf8.count > DeliveryPlanApproval.maximumReviewerByteCount
                || approval.scopeFingerprint
                    .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || approval.approvedAt != plan.updatedAt
                || approval.approvedAt < plan.createdAt
                || approval.approvedAt < run.createdAt
                || approval.approvedAt > run.updatedAt {
                issues.append(
                    DeliveryRunValidationIssue(
                        code: .invalidApprovalMetadata,
                        message: "Approval metadata, reviewer, and chronology must be valid."
                    )
                )
            }

            if let repositoryIdentity = run.repositoryIdentity {
                if !hasCompleteRepositoryIdentity(repositoryIdentity) {
                    issues.append(
                        DeliveryRunValidationIssue(
                            code: .incompleteRepositoryIdentity,
                            message: "Approval requires repository, container, Git common-directory, and base-commit identities."
                        )
                    )
                }
                let planFingerprint = DeliveryPlanFingerprint.make(for: plan)
                let scopeFingerprint = planFingerprint.flatMap {
                    DeliveryApprovalScopeFingerprint.make(
                        runID: run.id,
                        runCreatedAt: run.createdAt,
                        brief: run.brief,
                        repositoryIdentity: repositoryIdentity,
                        planFingerprint: $0,
                        approvedAt: approval.approvedAt,
                        approvedBy: approval.approvedBy
                    )
                }
                if scopeFingerprint == nil
                    || approval.scopeFingerprint != scopeFingerprint {
                    issues.append(
                        DeliveryRunValidationIssue(
                            code: .staleApprovalScope,
                            message: "The approval does not match the current brief and repository scope."
                        )
                    )
                }
            } else {
                issues.append(
                    DeliveryRunValidationIssue(
                        code: .missingRepositoryIdentity,
                        message: "An approved plan requires a trusted repository identity."
                    )
                )
            }
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
            runCreatedAt: run.createdAt,
            runUpdatedAt: run.updatedAt,
            tasksByID: tasksByID,
            issues: &issues
        )
        validateExecutionObservations(
            run.executionObservations,
            attempts: run.attempts,
            runCreatedAt: run.createdAt,
            runUpdatedAt: run.updatedAt,
            tasksByID: tasksByID,
            attemptsByID: attemptsByID,
            issues: &issues
        )
        validateEvidence(
            run.evidenceFacts,
            runCreatedAt: run.createdAt,
            runUpdatedAt: run.updatedAt,
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

    nonisolated private static func hasCompleteRepositoryIdentity(
        _ identity: DeliveryRepositoryIdentitySnapshot
    ) -> Bool {
        let values = [
            identity.repositoryRootPath,
            identity.resolvedRepositoryRootPath,
            identity.repositoryFileIdentity,
            identity.containerRelativePath,
            identity.resolvedContainerPath,
            identity.containerFileIdentity,
            identity.gitCommonDirectoryPath,
            identity.gitCommonDirectoryFileIdentity,
            identity.baseCommitIdentifier
        ]
        guard values.allSatisfy({
            !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }) else {
            return false
        }
        let commit = identity.baseCommitIdentifier.lowercased()
        let hexadecimal = CharacterSet(charactersIn: "0123456789abcdef")
        return (commit.count == 40 || commit.count == 64)
            && commit.unicodeScalars.allSatisfy(hexadecimal.contains)
    }

    nonisolated private static func standardizedPath(_ value: String) -> String {
        (value.trimmingCharacters(in: .whitespacesAndNewlines) as NSString)
            .standardizingPath
    }

    nonisolated private static func validateAttempts(
        _ attempts: [ExecutionAttempt],
        plan: DeliveryPlan,
        runCreatedAt: Date,
        runUpdatedAt: Date,
        tasksByID: [UUID: DeliveryTask],
        issues: inout [DeliveryRunValidationIssue]
    ) {
        var seenAttemptIDs: Set<UUID> = []
        var seenSequenceKeys: Set<String> = []
        var seenIdempotencyKeys: Set<UUID> = []
        var activeAttemptCountByTaskID: [UUID: Int] = [:]
        var taskIDByExternalSession: [ExternalSessionRef: UUID] = [:]

        for attempt in attempts {
            let eventDates = [
                attempt.dispatchRequestedAt,
                attempt.startedAt,
                attempt.endedAt,
                attempt.stopRequestedAt,
                attempt.lastReconcileFailedAt
            ].compactMap { $0 }
            let hasInvalidBounds = attempt.createdAt < runCreatedAt
                || attempt.createdAt > runUpdatedAt
                || eventDates.contains {
                    $0 < attempt.createdAt || $0 > runUpdatedAt
                }
            let hasInvalidOrdering =
                (attempt.dispatchRequestedAt != nil
                    && attempt.startedAt != nil
                    && attempt.dispatchRequestedAt! > attempt.startedAt!)
                || (attempt.startedAt != nil
                    && attempt.endedAt != nil
                    && attempt.startedAt! > attempt.endedAt!)
                || (attempt.dispatchRequestedAt != nil
                    && attempt.endedAt != nil
                    && attempt.dispatchRequestedAt! > attempt.endedAt!)
            if hasInvalidBounds || hasInvalidOrdering {
                issues.append(
                    DeliveryRunValidationIssue(
                        code: .invalidAttemptChronology,
                        message: "Execution attempt timestamps must be ordered within the delivery run.",
                        taskID: attempt.taskID,
                        attemptID: attempt.id
                    )
                )
            }

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

            let backendID = attempt.backendID.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            let projectID = attempt.projectID?.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            let sessionIdentityIsEmpty = attempt.externalSession.map {
                $0.backendID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || $0.projectID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || $0.sessionID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            } ?? false
            let sessionVerificationIdentityIsInvalid =
                attempt.externalSession.map {
                    $0.branch?.trimmingCharacters(
                        in: .whitespacesAndNewlines
                    ).isEmpty == true
                        || $0.verificationWorkspacePath.map {
                            !$0.trimmingCharacters(
                                in: .whitespacesAndNewlines
                            ).isEmpty
                                && ($0 as NSString).isAbsolutePath
                        } == false
                } ?? false
            let reconcileFailureIsEmpty = attempt.lastReconcileFailureReason?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .isEmpty == true
            let reconcileFailurePairIsIncomplete =
                (attempt.lastReconcileFailureReason == nil)
                    != (attempt.lastReconcileFailedAt == nil)
            let statusRequiresSession: Bool
            switch attempt.status {
            case .running, .blocked, .succeeded, .failed, .stopped:
                statusRequiresSession = true
            case .queued, .unknown:
                statusRequiresSession = false
            }
            if backendID.isEmpty
                || projectID?.isEmpty != false
                || attempt.dispatchRequestedAt == nil
                || sessionIdentityIsEmpty
                || sessionVerificationIdentityIsInvalid
                || (statusRequiresSession && attempt.externalSession == nil)
                || (attempt.status == .queued && attempt.externalSession != nil)
                || (attempt.dispatchFailureReason != nil
                    && attempt.externalSession != nil)
                || reconcileFailureIsEmpty
                || reconcileFailurePairIsIncomplete
                || (attempt.lastReconcileFailureReason != nil
                    && attempt.externalSession == nil) {
                issues.append(
                    DeliveryRunValidationIssue(
                        code: .invalidAttemptDispatchBinding,
                        message: "Execution attempts must bind a dispatch request, backend project, status, and external session consistently.",
                        taskID: attempt.taskID,
                        attemptID: attempt.id
                    )
                )
            }
            if attempt.nextFactCursor?.trimmingCharacters(
                in: .whitespacesAndNewlines
            ).isEmpty == true
                || (attempt.nextFactCursor != nil
                    && attempt.lastFactSequence == nil)
                || attempt.lastFactSequence == 0 {
                issues.append(
                    DeliveryRunValidationIssue(
                        code: .invalidAttemptFactCursor,
                        message: "Execution fact cursors require a non-empty cursor and a positive last sequence.",
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
                if session.projectID != attempt.projectID {
                    issues.append(
                        DeliveryRunValidationIssue(
                            code: .sessionProjectMismatch,
                            message: "The external session project does not match its execution attempt.",
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

    nonisolated private static func validateExecutionObservations(
        _ observations: [ExecutionBackendObservation],
        attempts: [ExecutionAttempt],
        runCreatedAt: Date,
        runUpdatedAt: Date,
        tasksByID: [UUID: DeliveryTask],
        attemptsByID: [UUID: ExecutionAttempt],
        issues: inout [DeliveryRunValidationIssue]
    ) {
        var seenIDs: Set<String> = []
        var seenSequences: Set<String> = []
        var maximumSequenceByAttemptID: [UUID: UInt64] = [:]

        for observation in observations {
            if observation.id.trimmingCharacters(
                in: .whitespacesAndNewlines
            ).isEmpty
                || observation.summary.trimmingCharacters(
                    in: .whitespacesAndNewlines
                ).isEmpty
                || observation.sequence < 1
                || observation.occurredAt < runCreatedAt
                || observation.occurredAt > observation.receivedAt
                || observation.receivedAt > runUpdatedAt {
                issues.append(
                    DeliveryRunValidationIssue(
                        code: .invalidExecutionObservationChronology,
                        message: "Execution observations require stable identities, summaries, sequences, and timestamps within the run.",
                        taskID: observation.taskID,
                        attemptID: observation.attemptID
                    )
                )
            }
            if !seenIDs.insert(observation.id).inserted {
                issues.append(
                    DeliveryRunValidationIssue(
                        code: .duplicateExecutionObservationID,
                        message: "Execution observation IDs must be unique.",
                        taskID: observation.taskID,
                        attemptID: observation.attemptID
                    )
                )
            }
            let sequenceKey = "\(observation.attemptID.uuidString):\(observation.sequence)"
            if !seenSequences.insert(sequenceKey).inserted {
                issues.append(
                    DeliveryRunValidationIssue(
                        code: .duplicateExecutionObservationSequence,
                        message: "Execution observation sequences must be unique within an attempt.",
                        taskID: observation.taskID,
                        attemptID: observation.attemptID
                    )
                )
            }
            if tasksByID[observation.taskID] == nil {
                issues.append(
                    DeliveryRunValidationIssue(
                        code: .missingExecutionObservationTask,
                        message: "An execution observation references a task outside the active plan.",
                        taskID: observation.taskID,
                        attemptID: observation.attemptID
                    )
                )
            }
            guard let attempt = attemptsByID[observation.attemptID] else {
                issues.append(
                    DeliveryRunValidationIssue(
                        code: .missingExecutionObservationAttempt,
                        message: "An execution observation references a missing attempt.",
                        taskID: observation.taskID,
                        attemptID: observation.attemptID
                    )
                )
                continue
            }
            if attempt.taskID != observation.taskID {
                issues.append(
                    DeliveryRunValidationIssue(
                        code: .executionObservationAttemptTaskMismatch,
                        message: "Execution observation task and attempt identities do not match.",
                        taskID: observation.taskID,
                        attemptID: observation.attemptID
                    )
                )
            }
            maximumSequenceByAttemptID[attempt.id] = max(
                maximumSequenceByAttemptID[attempt.id] ?? 0,
                observation.sequence
            )
        }

        for attempt in attempts {
            let maximumSequence = maximumSequenceByAttemptID[attempt.id]
            if maximumSequence != attempt.lastFactSequence {
                if maximumSequence != nil || attempt.lastFactSequence != nil {
                    issues.append(
                        DeliveryRunValidationIssue(
                            code: .invalidAttemptFactCursor,
                            message: "The persisted fact sequence does not match its observations.",
                            taskID: attempt.taskID,
                            attemptID: attempt.id
                        )
                    )
                }
            }
        }
    }

    nonisolated private static func validateEvidence(
        _ facts: [EvidenceFact],
        runCreatedAt: Date,
        runUpdatedAt: Date,
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
            if fact.observedAt > fact.receivedAt
                || fact.observedAt < runCreatedAt
                || fact.receivedAt > runUpdatedAt {
                issues.append(
                    DeliveryRunValidationIssue(
                        code: .invalidEvidenceChronology,
                        message: "Evidence must be observed before receipt and remain within the delivery run timeline.",
                        taskID: fact.taskID,
                        attemptID: fact.attemptID
                    )
                )
            }

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

            let requirement = task.evidenceRequirements.first {
                $0.id == fact.requirementID
            }
            if requirement == nil {
                issues.append(
                    DeliveryRunValidationIssue(
                        code: .missingEvidenceRequirement,
                        message: "Evidence references a requirement outside its task.",
                        taskID: fact.taskID,
                        attemptID: fact.attemptID
                    )
                )
            }

            let xcodeRecordIsValid: Bool
            switch (fact.source, fact.xcodeVerification, requirement) {
            case let (.xcodeVerifier, .some(record), .some(requirement)):
                let expectedResult: EvidenceResult =
                    record.exitCode == 0 && !record.timedOut
                        ? .passed
                        : .failed
                xcodeRecordIsValid =
                    record.kind.evidenceKind == requirement.kind
                        && fact.result == expectedResult
                        && fact.summary == record.summary
                        && fact.observedAt == record.endedAt
                        && record.startedAt <= record.endedAt
                        && record.endedAt <= fact.receivedAt
                        && !record.scheme.trimmingCharacters(
                            in: .whitespacesAndNewlines
                        ).isEmpty
                        && !record.command.trimmingCharacters(
                            in: .whitespacesAndNewlines
                        ).isEmpty
                        && !record.workingDirectoryPath.trimmingCharacters(
                            in: .whitespacesAndNewlines
                        ).isEmpty
                        && !record.summary.trimmingCharacters(
                            in: .whitespacesAndNewlines
                        ).isEmpty
                        && record.summary.utf8.count <= 4_096
            case (.xcodeVerifier, .none, _):
                xcodeRecordIsValid = false
            case (_, .some, _):
                xcodeRecordIsValid = false
            case (_, .none, _):
                xcodeRecordIsValid = true
            }
            if !xcodeRecordIsValid {
                issues.append(
                    DeliveryRunValidationIssue(
                        code: .invalidXcodeVerification,
                        message: "Xcode verifier evidence must preserve a matching command, exit status, scheme, workspace, summary, and chronology.",
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
