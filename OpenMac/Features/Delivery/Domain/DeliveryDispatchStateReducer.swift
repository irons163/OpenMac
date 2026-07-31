import Foundation

nonisolated enum DeliveryTaskExecutionState: String, Equatable, Sendable {
    case pending
    case ready
    case dispatching
    case dispatchFailed
    case running
    case blocked
    case succeeded
    case failed
    case stopped
    case unknown
}

nonisolated enum DeliveryDispatchStateReducer {
    nonisolated static func readyTaskIDs(in run: DeliveryRun) -> [UUID] {
        guard run.stoppedAt == nil,
              let plan = run.plan,
              plan.approval != nil,
              DeliveryRunValidator.isValid(run) else {
            return []
        }

        let latestAttempts = latestAttemptsByTaskID(in: run)
        let prerequisitesByTaskID = Dictionary(
            grouping: plan.dependencyEdges,
            by: \.dependentTaskID
        ).mapValues { edges in
            edges.map(\.prerequisiteTaskID)
        }

        return plan.tasks.compactMap { task in
            guard latestAttempts[task.id] == nil else {
                return nil
            }
            let prerequisites = prerequisitesByTaskID[task.id] ?? []
            let dependenciesSucceeded = prerequisites.allSatisfy {
                latestAttempts[$0]?.status == .succeeded
            }
            return dependenciesSucceeded ? task.id : nil
        }
    }

    nonisolated static func taskStates(
        in run: DeliveryRun
    ) -> [UUID: DeliveryTaskExecutionState] {
        guard let plan = run.plan else {
            return [:]
        }
        let readyTaskIDs = Set(readyTaskIDs(in: run))
        let latestAttempts = latestAttemptsByTaskID(in: run)
        var result: [UUID: DeliveryTaskExecutionState] = [:]

        for task in plan.tasks {
            guard let attempt = latestAttempts[task.id] else {
                result[task.id] = readyTaskIDs.contains(task.id) ? .ready : .pending
                continue
            }
            result[task.id] = taskState(for: attempt)
        }
        return result
    }

    nonisolated static func state(for run: DeliveryRun) -> DerivedDeliveryState {
        if run.stoppedAt != nil {
            return .stopped
        }
        guard let plan = run.plan else {
            return .draft
        }
        guard plan.approval != nil else {
            return .awaitingApproval
        }
        guard DeliveryRunValidator.isValid(run) else {
            return .needsYou
        }

        let states = Array(taskStates(in: run).values)
        if states.contains(where: {
            switch $0 {
            case .dispatchFailed, .blocked, .failed, .stopped, .unknown:
                return true
            case .pending, .ready, .dispatching, .running, .succeeded:
                return false
            }
        }) {
            return .needsYou
        }
        if hasFailedVerification(in: run) {
            return .needsYou
        }
        if states.contains(.dispatching) || states.contains(.running) {
            return .running
        }
        if !states.isEmpty && states.allSatisfy({ $0 == .succeeded }) {
            if hasCompleteVerification(in: run),
               hasReadyPullRequest(in: run) {
                return .readyToMerge
            }
            return .verifying
        }
        return .queued
    }

    nonisolated static func latestAttemptsByTaskID(
        in run: DeliveryRun
    ) -> [UUID: ExecutionAttempt] {
        var result: [UUID: ExecutionAttempt] = [:]
        for attempt in run.attempts {
            guard let current = result[attempt.taskID] else {
                result[attempt.taskID] = attempt
                continue
            }
            if attempt.sequence > current.sequence
                || (attempt.sequence == current.sequence
                    && attempt.createdAt > current.createdAt) {
                result[attempt.taskID] = attempt
            }
        }
        return result
    }

    nonisolated private static func taskState(
        for attempt: ExecutionAttempt
    ) -> DeliveryTaskExecutionState {
        if attempt.lastReconcileFailureReason != nil {
            return .unknown
        }
        switch attempt.status {
        case .queued:
            return attempt.dispatchFailureReason == nil
                ? .dispatching
                : .dispatchFailed
        case .running:
            return .running
        case .blocked:
            return .blocked
        case .succeeded:
            return .succeeded
        case .failed:
            return .failed
        case .stopped:
            return .stopped
        case .unknown:
            return .unknown
        }
    }

    nonisolated private static func hasFailedVerification(
        in run: DeliveryRun
    ) -> Bool {
        let latestAttempts = latestAttemptsByTaskID(in: run)
        let latestFacts = latestEvidenceFacts(in: run)
        let hasFailedEvidence = (run.plan?.tasks ?? []).contains { task in
            guard let attempt = latestAttempts[task.id] else { return false }
            return task.evidenceRequirements.contains { requirement in
                guard let fact = latestFacts[
                    evidenceKey(
                        attemptID: attempt.id,
                        requirementID: requirement.id
                    )
                ] else {
                    return false
                }
                return fact.result == .failed || fact.result == .unavailable
            }
        }
        let latestAttemptIDs = Set(latestAttempts.values.map(\.id))
        let hasFailedPullRequest = run.pullRequests.contains {
            latestAttemptIDs.contains($0.attemptID)
                && ($0.state == .closed
                    || $0.checksState == .failed
                    || $0.reviewState == .changesRequested)
        }
        return hasFailedEvidence || hasFailedPullRequest
    }

    nonisolated private static func hasCompleteVerification(
        in run: DeliveryRun
    ) -> Bool {
        guard let plan = run.plan else { return false }
        let latestAttempts = latestAttemptsByTaskID(in: run)
        let latestFacts = latestEvidenceFacts(in: run)
        return plan.tasks.allSatisfy { task in
            guard let attempt = latestAttempts[task.id] else { return false }
            return task.evidenceRequirements.allSatisfy { requirement in
                latestFacts[
                    evidenceKey(
                        attemptID: attempt.id,
                        requirementID: requirement.id
                    )
                ]?.result == .passed
            }
        }
    }

    nonisolated private static func hasReadyPullRequest(
        in run: DeliveryRun
    ) -> Bool {
        let latestAttemptIDs = Set(
            latestAttemptsByTaskID(in: run).values.map(\.id)
        )
        return run.pullRequests.contains {
            latestAttemptIDs.contains($0.attemptID)
                && ($0.state == .open || $0.state == .merged)
                && $0.checksState == .passed
                && ($0.reviewState == .approved
                    || $0.reviewState == .notRequired)
        }
    }

    nonisolated private static func latestEvidenceFacts(
        in run: DeliveryRun
    ) -> [String: EvidenceFact] {
        var result: [String: EvidenceFact] = [:]
        for fact in run.evidenceFacts {
            let key = evidenceKey(
                attemptID: fact.attemptID,
                requirementID: fact.requirementID
            )
            guard let current = result[key] else {
                result[key] = fact
                continue
            }
            if fact.receivedAt > current.receivedAt
                || (fact.receivedAt == current.receivedAt
                    && fact.id.uuidString > current.id.uuidString) {
                result[key] = fact
            }
        }
        return result
    }

    nonisolated private static func evidenceKey(
        attemptID: UUID,
        requirementID: UUID
    ) -> String {
        "\(attemptID.uuidString):\(requirementID.uuidString)"
    }
}
