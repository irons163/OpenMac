import Foundation

enum ExecutionSeverityPolicy {
    static var noRunnableAssignedBatch: BoardMessageSeverity {
        .warning
    }

    static func batchRunFinished(
        counters: BatchRunCounters,
        wasCancelled: Bool,
        detailsMissingCount: Int,
        dependencyBlockedCount: Int,
        approvalBlockedCount: Int,
        quotaBlockedCount: Int,
        qualitySafetyBlockedCount: Int = 0
    ) -> BoardMessageSeverity {
        (
            counters.failedCount > 0 ||
                wasCancelled ||
                counters.skippedCount > 0 ||
                detailsMissingCount > 0 ||
                approvalBlockedCount > 0 ||
                quotaBlockedCount > 0 ||
                qualitySafetyBlockedCount > 0 ||
                dependencyBlockedCount > 0
        ) ? .warning : .info
    }

    static func autoCycleFinished(
        hadWarning: Bool,
        wasCancelled: Bool,
        remainingDetailsMissing: Int,
        remainingDependencyBlocked: Int,
        remainingApprovalBlocked: Int,
        remainingQuotaBlocked: Int,
        remainingQualitySafetyBlocked: Int = 0
    ) -> BoardMessageSeverity {
        (
            hadWarning ||
                wasCancelled ||
                remainingDetailsMissing > 0 ||
                remainingApprovalBlocked > 0 ||
                remainingQuotaBlocked > 0 ||
                remainingQualitySafetyBlocked > 0 ||
                remainingDependencyBlocked > 0
        ) ? .warning : .info
    }

    static var autoCycleNoRunnable: BoardMessageSeverity {
        .warning
    }

    static func pmAutopilotFinished(
        cycleHadWarning: Bool,
        startedExecutions: Int,
        remainingDetailsMissing: Int,
        remainingDependencyBlocked: Int,
        remainingApprovalBlocked: Int,
        remainingQuotaBlocked: Int,
        remainingQualitySafetyBlocked: Int = 0
    ) -> BoardMessageSeverity {
        (
            cycleHadWarning ||
                startedExecutions == 0 ||
                remainingDetailsMissing > 0 ||
                remainingApprovalBlocked > 0 ||
                remainingQuotaBlocked > 0 ||
                remainingQualitySafetyBlocked > 0 ||
                remainingDependencyBlocked > 0
        ) ? .warning : .info
    }
}
