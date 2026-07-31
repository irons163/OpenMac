import Foundation

nonisolated struct DeliveryAttentionItem: Identifiable, Equatable, Sendable {
    let id: String
    let taskID: UUID?
    let title: String
    let detail: String
    let nextStep: String
    let sourceURL: URL?
    let canRetryDispatch: Bool
}

nonisolated struct DeliveryAttentionDashboard: Equatable, Sendable {
    let state: DerivedDeliveryState
    let needsYou: [DeliveryAttentionItem]
    let running: [DeliveryAttentionItem]
    let verifying: [DeliveryAttentionItem]
    let readyToMerge: [DeliveryAttentionItem]
    let queuedTaskCount: Int

    nonisolated static func make(for run: DeliveryRun) -> DeliveryAttentionDashboard {
        guard let plan = run.plan else {
            return DeliveryAttentionDashboard(
                state: .draft,
                needsYou: [],
                running: [],
                verifying: [],
                readyToMerge: [],
                queuedTaskCount: 0
            )
        }

        let state = DeliveryDispatchStateReducer.state(for: run)
        let taskStates = DeliveryDispatchStateReducer.taskStates(in: run)
        let latestAttempts = DeliveryDispatchStateReducer
            .latestAttemptsByTaskID(in: run)
        let latestEvidence = latestEvidenceByRequirement(in: run)
        let repositoryURL = URL(
            fileURLWithPath: run.brief.repository.rootPath,
            isDirectory: true
        )
        var needsYou: [DeliveryAttentionItem] = []
        var running: [DeliveryAttentionItem] = []
        var verifying: [DeliveryAttentionItem] = []
        var queuedTaskCount = 0

        for task in plan.tasks {
            let taskState = taskStates[task.id] ?? .pending
            let attempt = latestAttempts[task.id]
            let observation = attempt.flatMap {
                latestObservation(for: $0.id, in: run)
            }
            let sourceURL = attempt.flatMap {
                latestPullRequestURL(for: $0.id, in: run)
            } ?? repositoryURL

            switch taskState {
            case .pending, .ready:
                queuedTaskCount += 1
            case .dispatching:
                running.append(
                    item(
                        task: task,
                        detail: "Dispatch reservation is waiting for a backend session.",
                        nextStep: "Wait for the fixture step or stop future dispatch.",
                        sourceURL: sourceURL
                    )
                )
            case .running:
                running.append(
                    item(
                        task: task,
                        detail: observation?.summary
                            ?? "The isolated backend session is running.",
                        nextStep: "Advance the fixture to import its next fact.",
                        sourceURL: sourceURL
                    )
                )
            case .dispatchFailed:
                needsYou.append(
                    item(
                        task: task,
                        detail: attempt?.dispatchFailureReason
                            ?? "The backend did not bind a session.",
                        nextStep: "Retry the same idempotent dispatch reservation.",
                        sourceURL: sourceURL,
                        canRetryDispatch: true
                    )
                )
            case .blocked:
                needsYou.append(
                    item(
                        task: task,
                        detail: observation?.summary
                            ?? "The backend session is waiting for input.",
                        nextStep: task.humanActionHint
                            ?? "Open the source and resolve the requested input before continuing.",
                        sourceURL: sourceURL
                    )
                )
            case .failed:
                let canRetry = canCreateRetryAttempt(
                    taskID: task.id,
                    plan: plan,
                    run: run
                )
                needsYou.append(
                    item(
                        task: task,
                        detail: observation?.summary
                            ?? "The backend session failed.",
                        nextStep: canRetry
                            ? "Inspect the failure, then create a new isolated attempt."
                            : "Inspect the failure. A dependent task already started, so retry is blocked to avoid mixing attempt lineages.",
                        sourceURL: sourceURL,
                        canRetryDispatch: canRetry
                    )
                )
            case .stopped:
                let canRetry = canCreateRetryAttempt(
                    taskID: task.id,
                    plan: plan,
                    run: run
                )
                needsYou.append(
                    item(
                        task: task,
                        detail: "The backend session stopped before verification completed.",
                        nextStep: canRetry
                            ? "Inspect the source, then create a new isolated attempt."
                            : "Inspect the source. A dependent task already started, so retry is blocked to avoid mixing attempt lineages.",
                        sourceURL: sourceURL,
                        canRetryDispatch: canRetry
                    )
                )
            case .unknown:
                needsYou.append(
                    item(
                        task: task,
                        detail: attempt?.lastReconcileFailureReason
                            ?? (attempt?.isFactStreamExhausted == true
                                ? "The backend fact stream ended without a terminal state."
                                : observation?.summary
                                    ?? "The backend reported an unknown state."),
                        nextStep: attempt?.lastReconcileFailureReason == nil
                            ? "Open the source and reconcile the backend identity before continuing."
                            : "Reconnect the execution backend and reconcile this persisted session before continuing.",
                        sourceURL: sourceURL
                    )
                )
            case .succeeded:
                guard let attempt else { continue }
                let failedRequirements = task.evidenceRequirements.filter {
                    guard let fact = latestEvidence[
                        evidenceKey(
                            attemptID: attempt.id,
                            requirementID: $0.id
                        )
                    ] else {
                        return false
                    }
                    return fact.result == .failed
                        || fact.result == .unavailable
                }
                if !failedRequirements.isEmpty {
                    needsYou.append(
                        item(
                            task: task,
                            detail: "Failed evidence: "
                                + failedRequirements
                                    .map(\.description)
                                    .joined(separator: " · "),
                            nextStep: "Open the source and fix the failing verification.",
                            sourceURL: sourceURL
                        )
                    )
                    continue
                }
                let missingRequirements = task.evidenceRequirements.filter {
                    latestEvidence[
                        evidenceKey(
                            attemptID: attempt.id,
                            requirementID: $0.id
                        )
                    ]?.result != .passed
                }
                if !missingRequirements.isEmpty {
                    verifying.append(
                        item(
                            task: task,
                            detail: "Missing evidence: "
                                + missingRequirements
                                    .map(\.description)
                                    .joined(separator: " · "),
                            nextStep: "Advance the fixture or open the source to collect the required evidence.",
                            sourceURL: sourceURL
                        )
                    )
                } else if state != .readyToMerge {
                    verifying.append(
                        item(
                            task: task,
                            detail: "Task evidence passed; delivery-level pull request checks are still pending.",
                            nextStep: "Advance the fixture to reconcile pull request facts.",
                            sourceURL: sourceURL
                        )
                    )
                }
            }
        }

        let readyToMerge: [DeliveryAttentionItem]
        if state == .readyToMerge {
            readyToMerge = [
                DeliveryAttentionItem(
                    id: "run:\(run.id.uuidString)",
                    taskID: nil,
                    title: run.brief.title,
                    detail: "All task evidence, pull request checks, and review facts passed.",
                    nextStep: "Open the pull request or source for final human review; OpenMac will not merge automatically.",
                    sourceURL: run.pullRequests.last?.url ?? repositoryURL,
                    canRetryDispatch: false
                )
            ]
        } else {
            readyToMerge = []
        }

        return DeliveryAttentionDashboard(
            state: state,
            needsYou: needsYou,
            running: running,
            verifying: verifying,
            readyToMerge: readyToMerge,
            queuedTaskCount: queuedTaskCount
        )
    }

    nonisolated private static func item(
        task: DeliveryTask,
        detail: String,
        nextStep: String,
        sourceURL: URL?,
        canRetryDispatch: Bool = false
    ) -> DeliveryAttentionItem {
        DeliveryAttentionItem(
            id: "task:\(task.id.uuidString)",
            taskID: task.id,
            title: task.title,
            detail: detail,
            nextStep: nextStep,
            sourceURL: sourceURL,
            canRetryDispatch: canRetryDispatch
        )
    }

    nonisolated private static func latestObservation(
        for attemptID: UUID,
        in run: DeliveryRun
    ) -> ExecutionBackendObservation? {
        run.executionObservations
            .filter { $0.attemptID == attemptID }
            .max {
                if $0.sequence != $1.sequence {
                    return $0.sequence < $1.sequence
                }
                return $0.receivedAt < $1.receivedAt
            }
    }

    nonisolated private static func latestPullRequestURL(
        for attemptID: UUID,
        in run: DeliveryRun
    ) -> URL? {
        run.pullRequests.last(where: { $0.attemptID == attemptID })?.url
    }

    nonisolated private static func latestEvidenceByRequirement(
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

    nonisolated private static func canCreateRetryAttempt(
        taskID: UUID,
        plan: DeliveryPlan,
        run: DeliveryRun
    ) -> Bool {
        guard run.stoppedAt == nil else { return false }
        let dependentTaskIDs = Set(
            plan.dependencyEdges.compactMap {
                $0.prerequisiteTaskID == taskID
                    ? $0.dependentTaskID
                    : nil
            }
        )
        return !run.attempts.contains {
            dependentTaskIDs.contains($0.taskID)
        }
    }
}
