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
        if states.contains(.dispatching) || states.contains(.running) {
            return .running
        }
        if !states.isEmpty && states.allSatisfy({ $0 == .succeeded }) {
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
}
