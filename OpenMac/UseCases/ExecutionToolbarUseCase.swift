import Foundation

@MainActor
enum ExecutionToolbarUseCase {
    @discardableResult
    static func runAssignedExecutions(
        isBatchRunning: Bool,
        isAutoCycleRunning: Bool,
        setBatchRunning: @escaping (Bool) -> Void,
        runAssignedExecutionsInBackground: (@escaping (Int) -> Void) -> Void,
        refresh: @escaping () -> Void
    ) -> Bool {
        guard !isBatchRunning else { return false }
        guard !isAutoCycleRunning else { return false }

        setBatchRunning(true)
        runAssignedExecutionsInBackground { startedCount in
            setBatchRunning(false)
            if startedCount > 0 {
                refresh()
            }
        }
        return true
    }

    @discardableResult
    static func cancelAssignedExecutions(
        isBatchRunning: Bool,
        requestCancelAssignedTaskExecutions: () -> Void
    ) -> Bool {
        guard isBatchRunning else { return false }
        requestCancelAssignedTaskExecutions()
        return true
    }

    @discardableResult
    static func runAutoCycle(
        isAutoCycleRunning: Bool,
        isBatchRunning: Bool,
        setAutoCycleRunning: @escaping (Bool) -> Void,
        runAutoDispatchCycleInBackground: (@escaping (Int) -> Void) -> Void,
        refresh: @escaping () -> Void
    ) -> Bool {
        guard !isAutoCycleRunning else { return false }
        guard !isBatchRunning else { return false }

        setAutoCycleRunning(true)
        runAutoDispatchCycleInBackground { startedCount in
            setAutoCycleRunning(false)
            if startedCount > 0 {
                refresh()
            }
        }
        return true
    }

    @discardableResult
    static func cancelAutoCycle(
        isAutoCycleRunning: Bool,
        requestCancelAutoDispatchCycle: () -> Void
    ) -> Bool {
        guard isAutoCycleRunning else { return false }
        requestCancelAutoDispatchCycle()
        return true
    }

    static func selectedRetryableErrorTypes(
        retryNetwork: Bool,
        retryRateLimit: Bool,
        retryServer: Bool
    ) -> Set<RetryableExecutionErrorType> {
        var retryableTypes: Set<RetryableExecutionErrorType> = []
        if retryNetwork {
            retryableTypes.insert(.network)
        }
        if retryRateLimit {
            retryableTypes.insert(.rateLimit)
        }
        if retryServer {
            retryableTypes.insert(.server)
        }
        return retryableTypes
    }
}
