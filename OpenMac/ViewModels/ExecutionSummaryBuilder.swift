import Foundation

@MainActor
enum ExecutionSummaryBuilder {
    private static func message(_ key: String) -> String {
        L10n.string(key)
    }

    private static func message(_ key: String, _ arguments: CVarArg...) -> String {
        L10n.format(key, locale: nil, arguments: arguments)
    }

    static var noRunnableAssignedTasksMessage: String {
        message("No assigned tasks are ready to run")
    }

    static func noRunnableAssignedBatchMessage(
        detailsMissingCount: Int,
        dependencyBlockedCount: Int,
        approvalBlockedCount: Int,
        quotaBlockedCount: Int,
        qualitySafetyBlockedCount: Int = 0
    ) -> String {
        if detailsMissingCount > 0 {
            let label = detailsMissingCount == 1 ? message("task") : message("tasks")
            return message(
                "%d assigned %@ with empty details. Fill details before batch run.",
                detailsMissingCount,
                label
            )
        }

        if approvalBlockedCount > 0 {
            let label = approvalBlockedCount == 1 ? message("task") : message("tasks")
            return message(
                "%d assigned %@ awaiting human approval before batch run.",
                approvalBlockedCount,
                label
            )
        }

        if quotaBlockedCount > 0 {
            let label = quotaBlockedCount == 1 ? message("task") : message("tasks")
            return message(
                "%d assigned %@ blocked by quota limits. Increase quota or reset usage before batch run.",
                quotaBlockedCount,
                label
            )
        }

        if qualitySafetyBlockedCount > 0 {
            let label = qualitySafetyBlockedCount == 1 ? message("task") : message("tasks")
            return message(
                "%d assigned %@ blocked by quality/safety gate. Fix task quality notes before batch run.",
                qualitySafetyBlockedCount,
                label
            )
        }

        if dependencyBlockedCount > 0 {
            let label = dependencyBlockedCount == 1 ? message("task") : message("tasks")
            return message(
                "%d assigned %@ blocked by dependencies. Resolve dependencies before batch run.",
                dependencyBlockedCount,
                label
            )
        }

        return noRunnableAssignedTasksMessage
    }

    static func batchRunFinishedMessage(
        counters: BatchRunCounters,
        detailsMissingCount: Int,
        dependencyBlockedCount: Int,
        approvalBlockedCount: Int,
        quotaBlockedCount: Int,
        qualitySafetyBlockedCount: Int = 0,
        wasCancelled: Bool
    ) -> String {
        var summaryParts = [
            message("Batch run finished"),
            message("%d started", counters.startedCount),
            message("%d succeeded", counters.succeededCount),
            message("%d failed", counters.failedCount)
        ]

        if wasCancelled {
            summaryParts.append(message("Cancelled"))
        }
        if counters.skippedCount > 0 {
            summaryParts.append(message("%d skipped", counters.skippedCount))
        }
        if detailsMissingCount > 0 {
            summaryParts.append(message("%d missing details", detailsMissingCount))
        }
        if approvalBlockedCount > 0 {
            summaryParts.append(message("%d awaiting approval", approvalBlockedCount))
        }
        if quotaBlockedCount > 0 {
            summaryParts.append(message("%d blocked by quota", quotaBlockedCount))
        }
        if qualitySafetyBlockedCount > 0 {
            summaryParts.append(message("%d blocked by quality/safety gate", qualitySafetyBlockedCount))
        }
        if dependencyBlockedCount > 0 {
            summaryParts.append(message("%d blocked by dependencies", dependencyBlockedCount))
        }

        return summaryParts.joined(separator: " · ")
    }

    static var autoCycleNoRunnableMessage: String {
        message("Auto cycle finished with no runnable assigned tasks")
    }

    static func autoCycleFinishedMessage(
        completedPasses: Int,
        totalStarted: Int,
        wasCancelled: Bool,
        createdDependencyTaskCount: Int,
        remainingDetailsMissing: Int,
        remainingDependencyBlocked: Int,
        remainingApprovalBlocked: Int,
        remainingQuotaBlocked: Int,
        remainingQualitySafetyBlocked: Int = 0
    ) -> String {
        var summaryParts: [String] = [
            message("Auto cycle finished · %d pass(es) · %d started", completedPasses, totalStarted)
        ]

        if wasCancelled {
            summaryParts.append(message("Cancelled"))
        }
        if createdDependencyTaskCount > 0 {
            summaryParts.append(message("Created %d dependency placeholder task(s)", createdDependencyTaskCount))
        }
        if remainingDetailsMissing > 0 {
            summaryParts.append(message("%d missing details", remainingDetailsMissing))
        }
        if remainingApprovalBlocked > 0 {
            summaryParts.append(message("%d awaiting approval", remainingApprovalBlocked))
        }
        if remainingQuotaBlocked > 0 {
            summaryParts.append(message("%d blocked by quota", remainingQuotaBlocked))
        }
        if remainingQualitySafetyBlocked > 0 {
            summaryParts.append(message("%d blocked by quality/safety gate", remainingQualitySafetyBlocked))
        }
        if remainingDependencyBlocked > 0 {
            summaryParts.append(message("%d blocked by dependencies", remainingDependencyBlocked))
        }

        return summaryParts.joined(separator: " · ")
    }

    static func pmAutopilotFinishedMessage(
        createdAgents: Int,
        createdTickets: Int,
        startedExecutions: Int,
        completedPasses: Int,
        roadmapMilestoneCount: Int,
        roadmapEpicCount: Int,
        roadmapSections: [String],
        autoCycleCreatedDependencyTaskCount: Int,
        remainingDetailsMissing: Int,
        remainingDependencyBlocked: Int,
        remainingApprovalBlocked: Int,
        remainingQuotaBlocked: Int,
        remainingQualitySafetyBlocked: Int = 0
    ) -> String {
        var summaryParts: [String] = [
            message(
                "PM autopilot finished · %d agent(s) · %d ticket(s) · %d execution(s) · %d pass(es)",
                createdAgents,
                createdTickets,
                startedExecutions,
                completedPasses
            ),
            message("Total Milestones: %d", roadmapMilestoneCount),
            message("Total Epics: %d", roadmapEpicCount)
        ]

        summaryParts.append(contentsOf: roadmapSections)

        if autoCycleCreatedDependencyTaskCount > 0 {
            summaryParts.append(
                message(
                    "Created %d dependency placeholder task(s)",
                    autoCycleCreatedDependencyTaskCount
                )
            )
        }
        if remainingDetailsMissing > 0 {
            summaryParts.append(message("%d missing details", remainingDetailsMissing))
        }
        if remainingApprovalBlocked > 0 {
            summaryParts.append(message("%d awaiting approval", remainingApprovalBlocked))
        }
        if remainingQuotaBlocked > 0 {
            summaryParts.append(message("%d blocked by quota", remainingQuotaBlocked))
        }
        if remainingQualitySafetyBlocked > 0 {
            summaryParts.append(message("%d blocked by quality/safety gate", remainingQualitySafetyBlocked))
        }
        if remainingDependencyBlocked > 0 {
            summaryParts.append(message("%d blocked by dependencies", remainingDependencyBlocked))
        }

        return summaryParts.joined(separator: " · ")
    }
}
