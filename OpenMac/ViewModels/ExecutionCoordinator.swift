import Foundation

struct PreparedTaskExecution {
    let taskID: UUID
    let taskSnapshot: WorkTask
    let agent: AgentProfile
}

struct ExecutionAttemptResult {
    let outcome: AgentTaskExecutionOutcome
    let retriesPerformed: Int
}

struct AssignedBatchRunPreparation {
    let runnableTaskIDs: [UUID]
    let detailsMissingCount: Int
    let dependencyBlockedCount: Int
}

struct BatchRunCounters {
    var startedCount = 0
    var succeededCount = 0
    var failedCount = 0
    var skippedCount = 0
}

struct BatchRunCompletionState {
    let counters: BatchRunCounters
    let finalPreparation: AssignedBatchRunPreparation
    let wasCancelled: Bool
}

struct AutoCycleCompletionState {
    let totalStarted: Int
    let completedPasses: Int
    let hadWarning: Bool
    let createdDependencyTaskCount: Int
    let wasCancelled: Bool
    let remainingPreparation: AssignedBatchRunPreparation
}

struct PMAutopilotPreparation<CreatedTaskDescriptor> {
    let createdAgents: Int
    let createdTaskDescriptors: [CreatedTaskDescriptor]
    let roadmapMilestoneCount: Int
    let roadmapEpicCount: Int
}

struct PMAutopilotCompletionState<CreatedTaskDescriptor> {
    let createdAgents: Int
    let createdTaskDescriptors: [CreatedTaskDescriptor]
    let roadmapMilestoneCount: Int
    let roadmapEpicCount: Int
    let startedExecutions: Int
    let completedPasses: Int
    let cycleHadWarning: Bool
    let remainingPreparation: AssignedBatchRunPreparation
    let autoCycleCreatedDependencyTaskCount: Int
}

@MainActor
enum ExecutionCoordinator {
    @discardableResult
    static func runTaskExecution(
        taskID: UUID,
        requiresTaskDetails: Bool,
        prepareTaskExecution: (UUID, Bool) -> PreparedTaskExecution?,
        executeWithAutoRetry: (WorkTask, AgentProfile, @escaping (String) -> Void) -> ExecutionAttemptResult,
        captureExecutionProgress: @escaping (String, PreparedTaskExecution) -> Void,
        applyRetryRunCount: (UUID, Int) -> Void,
        finalizeTaskExecution: (PreparedTaskExecution, AgentTaskExecutionOutcome) -> Void
    ) -> Bool {
        guard let prepared = prepareTaskExecution(taskID, requiresTaskDetails) else {
            return false
        }

        let result = executeWithAutoRetry(prepared.taskSnapshot, prepared.agent) { update in
            captureExecutionProgress(update, prepared)
        }
        applyRetryRunCount(prepared.taskID, result.retriesPerformed)
        finalizeTaskExecution(prepared, result.outcome)
        return true
    }

    static func runTaskExecutionInBackground(
        taskID: UUID,
        requiresTaskDetails: Bool,
        prepareTaskExecution: (UUID, Bool) -> PreparedTaskExecution?,
        executeWithAutoRetry: @escaping (WorkTask, AgentProfile, @escaping (String) -> Void) -> ExecutionAttemptResult,
        runOnBackground: @escaping (@escaping () -> Void) -> Void,
        runOnMain: @escaping (@escaping () -> Void) -> Void,
        captureExecutionProgress: @escaping (String, PreparedTaskExecution) -> Void,
        applyRetryRunCount: @escaping (UUID, Int) -> Void,
        finalizeTaskExecution: @escaping (PreparedTaskExecution, AgentTaskExecutionOutcome) -> Void,
        completion: @escaping (Bool) -> Void
    ) {
        guard let prepared = prepareTaskExecution(taskID, requiresTaskDetails) else {
            completion(false)
            return
        }

        runOnBackground {
            let result = executeWithAutoRetry(prepared.taskSnapshot, prepared.agent) { update in
                runOnMain {
                    captureExecutionProgress(update, prepared)
                }
            }

            runOnMain {
                applyRetryRunCount(prepared.taskID, result.retriesPerformed)
                finalizeTaskExecution(prepared, result.outcome)
                completion(true)
            }
        }
    }

    @discardableResult
    static func retryTaskExecution(
        taskID: UUID,
        canRetryTask: (UUID) -> Bool,
        onRetryRejected: () -> Void,
        runTaskExecution: (UUID, Bool) -> Bool
    ) -> Bool {
        guard canRetryTask(taskID) else {
            onRetryRejected()
            return false
        }

        return runTaskExecution(taskID, false)
    }

    static func retryTaskExecutionInBackground(
        taskID: UUID,
        canRetryTask: (UUID) -> Bool,
        onRetryRejected: () -> Void,
        runTaskExecutionInBackground: (UUID, Bool, @escaping (Bool) -> Void) -> Void,
        completion: @escaping (Bool) -> Void
    ) {
        guard canRetryTask(taskID) else {
            onRetryRejected()
            completion(false)
            return
        }

        runTaskExecutionInBackground(taskID, false, completion)
    }

    @discardableResult
    static func runAssignedTaskExecutions(
        prepareQueue: (Set<UUID>) -> AssignedBatchRunPreparation,
        runTaskExecution: (UUID) -> Bool,
        executionStatusForTask: (UUID) -> TaskExecutionStatus?,
        handleNoRunnable: (AssignedBatchRunPreparation) -> Void,
        handleFinished: (BatchRunCompletionState) -> Void
    ) -> Int {
        var attemptedTaskIDs: Set<UUID> = []
        var batchPreparation = prepareQueue(attemptedTaskIDs)

        guard !batchPreparation.runnableTaskIDs.isEmpty else {
            handleNoRunnable(batchPreparation)
            return 0
        }

        var counters = BatchRunCounters()

        while !batchPreparation.runnableTaskIDs.isEmpty {
            for taskID in batchPreparation.runnableTaskIDs {
                attemptedTaskIDs.insert(taskID)

                let didRun = runTaskExecution(taskID)
                guard didRun else {
                    counters.skippedCount += 1
                    continue
                }

                counters.startedCount += 1
                switch executionStatusForTask(taskID) {
                case .succeeded:
                    counters.succeededCount += 1
                case .failed:
                    counters.failedCount += 1
                case .running, .none:
                    break
                }
            }

            batchPreparation = prepareQueue(attemptedTaskIDs)
        }

        handleFinished(
            BatchRunCompletionState(
                counters: counters,
                finalPreparation: batchPreparation,
                wasCancelled: false
            )
        )
        return counters.startedCount
    }

    static func runAssignedTaskExecutionsInBackground(
        setCancelRequested: @escaping (Bool) -> Void,
        isCancelRequested: @escaping () -> Bool,
        prepareQueue: @escaping (Set<UUID>) -> AssignedBatchRunPreparation,
        runTaskExecutionInBackground: @escaping (UUID, @escaping (Bool) -> Void) -> Void,
        executionStatusForTask: @escaping (UUID) -> TaskExecutionStatus?,
        handleNoRunnable: @escaping (AssignedBatchRunPreparation) -> Void,
        handleFinished: @escaping (BatchRunCompletionState) -> Void,
        completion: @escaping (Int) -> Void
    ) {
        setCancelRequested(false)

        var attemptedTaskIDs: Set<UUID> = []
        var batchPreparation = prepareQueue(attemptedTaskIDs)
        var counters = BatchRunCounters()
        var wasCancelled = false
        var hasFinished = false

        guard !batchPreparation.runnableTaskIDs.isEmpty else {
            handleNoRunnable(batchPreparation)
            setCancelRequested(false)
            completion(0)
            return
        }

        func finish(_ finalPreparation: AssignedBatchRunPreparation) {
            guard !hasFinished else { return }
            hasFinished = true
            handleFinished(
                BatchRunCompletionState(
                    counters: counters,
                    finalPreparation: finalPreparation,
                    wasCancelled: wasCancelled
                )
            )
            setCancelRequested(false)
            completion(counters.startedCount)
        }

        func runNextRunnableBatch() {
            batchPreparation = prepareQueue(attemptedTaskIDs)
            if isCancelRequested() {
                wasCancelled = true
                finish(batchPreparation)
                return
            }
            guard !batchPreparation.runnableTaskIDs.isEmpty else {
                finish(batchPreparation)
                return
            }
            runBatch(batchPreparation.runnableTaskIDs, at: 0)
        }

        func runBatch(_ runnableTaskIDs: [UUID], at index: Int) {
            if isCancelRequested() {
                wasCancelled = true
                finish(batchPreparation)
                return
            }
            guard index < runnableTaskIDs.count else {
                runNextRunnableBatch()
                return
            }

            let taskID = runnableTaskIDs[index]
            attemptedTaskIDs.insert(taskID)
            runTaskExecutionInBackground(taskID) { didRun in
                if !didRun {
                    counters.skippedCount += 1
                    runBatch(runnableTaskIDs, at: index + 1)
                    return
                }

                counters.startedCount += 1
                switch executionStatusForTask(taskID) {
                case .succeeded:
                    counters.succeededCount += 1
                case .failed:
                    counters.failedCount += 1
                case .running, .none:
                    break
                }

                if isCancelRequested() {
                    wasCancelled = true
                    finish(batchPreparation)
                    return
                }
                runBatch(runnableTaskIDs, at: index + 1)
            }
        }

        runBatch(batchPreparation.runnableTaskIDs, at: 0)
    }

    static func runAutoDispatchCycleInBackground(
        maxPasses: Int,
        autoCreateMissingDependencies: Bool,
        autoAssignBeforeRun: Bool,
        setCancelRequested: @escaping (Bool) -> Void,
        isCancelRequested: @escaping () -> Bool,
        setCreatedDependencyTaskCount: @escaping (Int) -> Void,
        createMissingDependencyTasks: @escaping () -> Int,
        autoAssignTasks: @escaping () -> Void,
        runAssignedTaskExecutionsInBackground: @escaping (@escaping (Int) -> Void) -> Void,
        boardMessageSeverity: @escaping () -> BoardMessageSeverity?,
        isTerminalNoRunnablePass: @escaping (_ started: Int, _ totalStarted: Int) -> Bool,
        prepareRemainingQueue: @escaping () -> AssignedBatchRunPreparation,
        handleFinished: @escaping (AutoCycleCompletionState) -> Void,
        completion: @escaping (_ totalStarted: Int, _ completedPasses: Int) -> Void
    ) {
        setCancelRequested(false)

        let cappedPasses = min(12, max(1, maxPasses))
        var totalStarted = 0
        var completedPasses = 0
        var hadWarning = false
        var createdDependencyTaskCount = 0
        var wasCancelled = false
        var hasFinished = false

        setCreatedDependencyTaskCount(0)

        func finish() {
            guard !hasFinished else { return }
            hasFinished = true
            setCreatedDependencyTaskCount(createdDependencyTaskCount)

            let remainingPreparation = prepareRemainingQueue()
            handleFinished(
                AutoCycleCompletionState(
                    totalStarted: totalStarted,
                    completedPasses: completedPasses,
                    hadWarning: hadWarning,
                    createdDependencyTaskCount: createdDependencyTaskCount,
                    wasCancelled: wasCancelled,
                    remainingPreparation: remainingPreparation
                )
            )

            setCancelRequested(false)
            completion(totalStarted, completedPasses)
        }

        func runPass(_ passIndex: Int) {
            guard passIndex < cappedPasses else {
                finish()
                return
            }
            if isCancelRequested() {
                wasCancelled = true
                finish()
                return
            }

            completedPasses += 1
            if autoCreateMissingDependencies {
                createdDependencyTaskCount += createMissingDependencyTasks()
            }
            if autoAssignBeforeRun {
                autoAssignTasks()
            }

            runAssignedTaskExecutionsInBackground { started in
                totalStarted += started
                if boardMessageSeverity() == .warning,
                   !isTerminalNoRunnablePass(started, totalStarted) {
                    hadWarning = true
                }

                if isCancelRequested() {
                    wasCancelled = true
                    finish()
                    return
                }
                guard started > 0 else {
                    finish()
                    return
                }
                runPass(passIndex + 1)
            }
        }

        runPass(0)
    }

    static func runPMAutopilotInBackground<CreatedTaskDescriptor>(
        plannedTickets: [PMPlannedTicket],
        autoAssign: Bool,
        autoCreateMissingDependenciesDuringCycle: Bool,
        maxAutoCyclePasses: Int,
        preparePMAutopilot: ([PMPlannedTicket], Bool) -> PMAutopilotPreparation<CreatedTaskDescriptor>?,
        runAutoDispatchCycleInBackground: (
            _ maxPasses: Int,
            _ autoCreateMissingDependencies: Bool,
            _ autoAssignBeforeRun: Bool,
            _ completion: @escaping (_ totalStarted: Int, _ completedPasses: Int) -> Void
        ) -> Void,
        boardMessageSeverity: @escaping () -> BoardMessageSeverity?,
        prepareAssignedBatchRunQueue: @escaping () -> AssignedBatchRunPreparation,
        lastAutoCycleCreatedDependencyTaskCount: @escaping () -> Int,
        handleFinished: @escaping (PMAutopilotCompletionState<CreatedTaskDescriptor>) -> Void,
        completion: @escaping (
            _ createdAgents: Int,
            _ createdTickets: Int,
            _ startedExecutions: Int,
            _ completedPasses: Int
        ) -> Void
    ) {
        guard let preparation = preparePMAutopilot(plannedTickets, autoAssign) else {
            completion(0, 0, 0, 0)
            return
        }

        let createdTickets = preparation.createdTaskDescriptors.count
        guard createdTickets > 0 else {
            completion(preparation.createdAgents, 0, 0, 0)
            return
        }

        runAutoDispatchCycleInBackground(
            maxAutoCyclePasses,
            autoCreateMissingDependenciesDuringCycle,
            autoAssign
        ) { startedExecutions, completedPasses in
            let state = PMAutopilotCompletionState(
                createdAgents: preparation.createdAgents,
                createdTaskDescriptors: preparation.createdTaskDescriptors,
                roadmapMilestoneCount: preparation.roadmapMilestoneCount,
                roadmapEpicCount: preparation.roadmapEpicCount,
                startedExecutions: startedExecutions,
                completedPasses: completedPasses,
                cycleHadWarning: boardMessageSeverity() == .warning,
                remainingPreparation: prepareAssignedBatchRunQueue(),
                autoCycleCreatedDependencyTaskCount: lastAutoCycleCreatedDependencyTaskCount()
            )
            handleFinished(state)
            completion(preparation.createdAgents, createdTickets, startedExecutions, completedPasses)
        }
    }
}
