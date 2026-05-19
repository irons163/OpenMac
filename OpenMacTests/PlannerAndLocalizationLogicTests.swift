import Foundation
import SwiftUI
import Testing
@testable import OpenMac

@MainActor
struct ExecutionSummaryBuilderTests {
    @Test("no runnable assigned tasks message returns localized default")
    func noRunnableAssignedTasksMessageDefault() {
        #expect(ExecutionSummaryBuilder.noRunnableAssignedTasksMessage == L10n.string("No assigned tasks are ready to run"))
    }

    @Test("no runnable batch message prefers empty-details branch with singular label")
    func noRunnableBatchMessageDetailsSingular() {
        let message = ExecutionSummaryBuilder.noRunnableAssignedBatchMessage(
            detailsMissingCount: 1,
            dependencyBlockedCount: 3,
            approvalBlockedCount: 0,
            quotaBlockedCount: 0
        )

        #expect(message == L10n.format(
            "%d assigned %@ with empty details. Fill details before batch run.",
            1,
            L10n.string("task")
        ))
    }

    @Test("no runnable batch message uses blocked-dependency branch when details are clear")
    func noRunnableBatchMessageDependencyBlocked() {
        let message = ExecutionSummaryBuilder.noRunnableAssignedBatchMessage(
            detailsMissingCount: 0,
            dependencyBlockedCount: 2,
            approvalBlockedCount: 0,
            quotaBlockedCount: 0
        )

        #expect(message == L10n.format(
            "%d assigned %@ blocked by dependencies. Resolve dependencies before batch run.",
            2,
            L10n.string("tasks")
        ))
    }

    @Test("no runnable batch message prioritizes approval branch before quota and dependencies")
    func noRunnableBatchMessageApprovalBlocked() {
        let message = ExecutionSummaryBuilder.noRunnableAssignedBatchMessage(
            detailsMissingCount: 0,
            dependencyBlockedCount: 3,
            approvalBlockedCount: 1,
            quotaBlockedCount: 2
        )

        #expect(message == L10n.format(
            "%d assigned %@ awaiting human approval before batch run.",
            1,
            L10n.string("task")
        ))
    }

    @Test("no runnable batch message uses quota branch when approval is clear")
    func noRunnableBatchMessageQuotaBlocked() {
        let message = ExecutionSummaryBuilder.noRunnableAssignedBatchMessage(
            detailsMissingCount: 0,
            dependencyBlockedCount: 1,
            approvalBlockedCount: 0,
            quotaBlockedCount: 2
        )

        #expect(message == L10n.format(
            "%d assigned %@ blocked by quota limits. Increase quota or reset usage before batch run.",
            2,
            L10n.string("tasks")
        ))
    }

    @Test("no runnable batch message uses quality safety branch before dependency branch")
    func noRunnableBatchMessageQualitySafetyBlocked() {
        let message = ExecutionSummaryBuilder.noRunnableAssignedBatchMessage(
            detailsMissingCount: 0,
            dependencyBlockedCount: 2,
            approvalBlockedCount: 0,
            quotaBlockedCount: 0,
            qualitySafetyBlockedCount: 1
        )

        #expect(message == L10n.format(
            "%d assigned %@ blocked by quality/safety gate. Fix task quality notes before batch run.",
            1,
            L10n.string("task")
        ))
    }

    @Test("no runnable batch message falls back to generic text")
    func noRunnableBatchMessageFallback() {
        let message = ExecutionSummaryBuilder.noRunnableAssignedBatchMessage(
            detailsMissingCount: 0,
            dependencyBlockedCount: 0,
            approvalBlockedCount: 0,
            quotaBlockedCount: 0
        )

        #expect(message == ExecutionSummaryBuilder.noRunnableAssignedTasksMessage)
    }

    @Test("batch finished message includes optional summary segments when present")
    func batchFinishedMessageIncludesOptionalSegments() {
        var counters = BatchRunCounters()
        counters.startedCount = 5
        counters.succeededCount = 3
        counters.failedCount = 1
        counters.skippedCount = 1

        let message = ExecutionSummaryBuilder.batchRunFinishedMessage(
            counters: counters,
            detailsMissingCount: 2,
            dependencyBlockedCount: 1,
            approvalBlockedCount: 1,
            quotaBlockedCount: 1,
            qualitySafetyBlockedCount: 2,
            wasCancelled: true
        )

        #expect(message.contains(L10n.string("Batch run finished")))
        #expect(message.contains(L10n.format("%d started", 5)))
        #expect(message.contains(L10n.format("%d succeeded", 3)))
        #expect(message.contains(L10n.format("%d failed", 1)))
        #expect(message.contains(L10n.string("Cancelled")))
        #expect(message.contains(L10n.format("%d skipped", 1)))
        #expect(message.contains(L10n.format("%d missing details", 2)))
        #expect(message.contains(L10n.format("%d awaiting approval", 1)))
        #expect(message.contains(L10n.format("%d blocked by quota", 1)))
        #expect(message.contains(L10n.format("%d blocked by quality/safety gate", 2)))
        #expect(message.contains(L10n.format("%d blocked by dependencies", 1)))
    }

    @Test("batch finished message omits optional segments when values are zero")
    func batchFinishedMessageOmitsOptionalSegments() {
        var counters = BatchRunCounters()
        counters.startedCount = 1
        counters.succeededCount = 1
        counters.failedCount = 0
        counters.skippedCount = 0

        let message = ExecutionSummaryBuilder.batchRunFinishedMessage(
            counters: counters,
            detailsMissingCount: 0,
            dependencyBlockedCount: 0,
            approvalBlockedCount: 0,
            quotaBlockedCount: 0,
            wasCancelled: false
        )

        #expect(message.contains(L10n.string("Batch run finished")))
        #expect(message.contains(L10n.string("Cancelled")) == false)
        #expect(message.contains(L10n.format("%d skipped", 0)) == false)
        #expect(message.contains(L10n.format("%d missing details", 0)) == false)
        #expect(message.contains(L10n.format("%d blocked by dependencies", 0)) == false)
    }

    @Test("auto cycle no-runnable message returns localized default")
    func autoCycleNoRunnableMessageDefault() {
        #expect(ExecutionSummaryBuilder.autoCycleNoRunnableMessage == L10n.string("Auto cycle finished with no runnable assigned tasks"))
    }

    @Test("auto cycle finished message includes optional segments when present")
    func autoCycleFinishedMessageIncludesOptionalSegments() {
        let message = ExecutionSummaryBuilder.autoCycleFinishedMessage(
            completedPasses: 3,
            totalStarted: 4,
            wasCancelled: true,
            createdDependencyTaskCount: 2,
            remainingDetailsMissing: 1,
            remainingDependencyBlocked: 5,
            remainingApprovalBlocked: 1,
            remainingQuotaBlocked: 2,
            remainingQualitySafetyBlocked: 3
        )

        #expect(message.contains(L10n.format("Auto cycle finished · %d pass(es) · %d started", 3, 4)))
        #expect(message.contains(L10n.string("Cancelled")))
        #expect(message.contains(L10n.format("Created %d dependency placeholder task(s)", 2)))
        #expect(message.contains(L10n.format("%d missing details", 1)))
        #expect(message.contains(L10n.format("%d awaiting approval", 1)))
        #expect(message.contains(L10n.format("%d blocked by quota", 2)))
        #expect(message.contains(L10n.format("%d blocked by quality/safety gate", 3)))
        #expect(message.contains(L10n.format("%d blocked by dependencies", 5)))
    }

    @Test("pm autopilot finished message includes roadmap and optional segments")
    func pmAutopilotFinishedMessageIncludesRoadmapAndOptionalSegments() {
        let message = ExecutionSummaryBuilder.pmAutopilotFinishedMessage(
            createdAgents: 2,
            createdTickets: 6,
            startedExecutions: 4,
            completedPasses: 3,
            roadmapMilestoneCount: 2,
            roadmapEpicCount: 4,
            roadmapSections: ["Roadmap A", "Roadmap B"],
            autoCycleCreatedDependencyTaskCount: 1,
            remainingDetailsMissing: 2,
            remainingDependencyBlocked: 3,
            remainingApprovalBlocked: 1,
            remainingQuotaBlocked: 2,
            remainingQualitySafetyBlocked: 4
        )

        #expect(message.contains(L10n.format(
            "PM autopilot finished · %d agent(s) · %d ticket(s) · %d execution(s) · %d pass(es)",
            2,
            6,
            4,
            3
        )))
        #expect(message.contains(L10n.format("Total Milestones: %d", 2)))
        #expect(message.contains(L10n.format("Total Epics: %d", 4)))
        #expect(message.contains("Roadmap A"))
        #expect(message.contains("Roadmap B"))
        #expect(message.contains(L10n.format("Created %d dependency placeholder task(s)", 1)))
        #expect(message.contains(L10n.format("%d missing details", 2)))
        #expect(message.contains(L10n.format("%d awaiting approval", 1)))
        #expect(message.contains(L10n.format("%d blocked by quota", 2)))
        #expect(message.contains(L10n.format("%d blocked by quality/safety gate", 4)))
        #expect(message.contains(L10n.format("%d blocked by dependencies", 3)))
    }

    @Test("batch summary snapshot remains stable")
    func batchSummarySnapshot() {
        var counters = BatchRunCounters()
        counters.startedCount = 2
        counters.succeededCount = 1
        counters.failedCount = 1
        counters.skippedCount = 3

        let message = ExecutionSummaryBuilder.batchRunFinishedMessage(
            counters: counters,
            detailsMissingCount: 4,
            dependencyBlockedCount: 6,
            approvalBlockedCount: 2,
            quotaBlockedCount: 1,
            qualitySafetyBlockedCount: 5,
            wasCancelled: true
        )

        #expect(
            message ==
                "Batch run finished · 2 started · 1 succeeded · 1 failed · Cancelled · 3 skipped · 4 missing details · 2 awaiting approval · 1 blocked by quota · 5 blocked by quality/safety gate · 6 blocked by dependencies"
        )
    }

    @Test("pm autopilot summary snapshot remains stable")
    func pmAutopilotSummarySnapshot() {
        let message = ExecutionSummaryBuilder.pmAutopilotFinishedMessage(
            createdAgents: 3,
            createdTickets: 7,
            startedExecutions: 5,
            completedPasses: 4,
            roadmapMilestoneCount: 4,
            roadmapEpicCount: 5,
            roadmapSections: [
                "Milestone M1: 2/2",
                "Milestone M2: 1/3"
            ],
            autoCycleCreatedDependencyTaskCount: 2,
            remainingDetailsMissing: 1,
            remainingDependencyBlocked: 3,
            remainingApprovalBlocked: 0,
            remainingQuotaBlocked: 2,
            remainingQualitySafetyBlocked: 1
        )

        #expect(
            message ==
                "PM autopilot finished · 3 agent(s) · 7 ticket(s) · 5 execution(s) · 4 pass(es) · Total Milestones: 4 · Total Epics: 5 · Milestone M1: 2/2 · Milestone M2: 1/3 · Created 2 dependency placeholder task(s) · 1 missing details · 2 blocked by quota · 1 blocked by quality/safety gate · 3 blocked by dependencies"
        )
    }
}

@MainActor
struct ExecutionSeverityPolicyTests {
    @Test("batch severity is info when run completed cleanly")
    func batchSeverityInfoWhenClean() {
        var counters = BatchRunCounters()
        counters.startedCount = 2
        counters.succeededCount = 2
        counters.failedCount = 0
        counters.skippedCount = 0

        let severity = ExecutionSeverityPolicy.batchRunFinished(
            counters: counters,
            wasCancelled: false,
            detailsMissingCount: 0,
            dependencyBlockedCount: 0,
            approvalBlockedCount: 0,
            quotaBlockedCount: 0
        )

        #expect(severity == .info)
    }

    @Test("batch severity is warning when cancellation or blockers occurred")
    func batchSeverityWarningWhenCancelledOrBlocked() {
        var counters = BatchRunCounters()
        counters.startedCount = 2
        counters.succeededCount = 1
        counters.failedCount = 0
        counters.skippedCount = 1

        let severity = ExecutionSeverityPolicy.batchRunFinished(
            counters: counters,
            wasCancelled: true,
            detailsMissingCount: 1,
            dependencyBlockedCount: 0,
            approvalBlockedCount: 0,
            quotaBlockedCount: 1
        )

        #expect(severity == .warning)
    }

    @Test("auto cycle severity reflects warnings and remaining blockers")
    func autoCycleSeverity() {
        let warningSeverity = ExecutionSeverityPolicy.autoCycleFinished(
            hadWarning: false,
            wasCancelled: false,
            remainingDetailsMissing: 0,
            remainingDependencyBlocked: 1,
            remainingApprovalBlocked: 0,
            remainingQuotaBlocked: 0
        )
        let infoSeverity = ExecutionSeverityPolicy.autoCycleFinished(
            hadWarning: false,
            wasCancelled: false,
            remainingDetailsMissing: 0,
            remainingDependencyBlocked: 0,
            remainingApprovalBlocked: 0,
            remainingQuotaBlocked: 0
        )

        #expect(warningSeverity == .warning)
        #expect(infoSeverity == .info)
        #expect(ExecutionSeverityPolicy.autoCycleNoRunnable == .warning)
        #expect(ExecutionSeverityPolicy.noRunnableAssignedBatch == .warning)
    }

    @Test("pm autopilot severity warns when no executions started")
    func pmAutopilotSeverityWarnsWithoutExecution() {
        let warningSeverity = ExecutionSeverityPolicy.pmAutopilotFinished(
            cycleHadWarning: false,
            startedExecutions: 0,
            remainingDetailsMissing: 0,
            remainingDependencyBlocked: 0,
            remainingApprovalBlocked: 0,
            remainingQuotaBlocked: 0
        )
        let infoSeverity = ExecutionSeverityPolicy.pmAutopilotFinished(
            cycleHadWarning: false,
            startedExecutions: 2,
            remainingDetailsMissing: 0,
            remainingDependencyBlocked: 0,
            remainingApprovalBlocked: 0,
            remainingQuotaBlocked: 0
        )

        #expect(warningSeverity == .warning)
        #expect(infoSeverity == .info)
    }
}

@MainActor
struct PMRoadmapSummaryBuilderTests {
    private struct Descriptor {
        let taskID: UUID
        let milestone: String
        let epic: String
    }

    @Test("buildSections composes roadmap totals distributions and grouped progress")
    func buildSectionsComposesAllRoadmapSegments() {
        let agentID = UUID()
        let taskA = WorkTask(
            title: "Task A",
            details: "details",
            requiredSkills: ["swiftui"],
            storyPoints: 2,
            status: .todo,
            assignedAgentID: nil,
            executionRecord: TaskExecutionRecord(status: .failed)
        )
        let taskB = WorkTask(
            title: "Task B",
            details: "details",
            requiredSkills: ["swiftui"],
            storyPoints: 3,
            status: .inProgress,
            assignedAgentID: agentID,
            executionRecord: TaskExecutionRecord(status: .running)
        )
        let taskC = WorkTask(
            title: "Task C",
            details: "details",
            requiredSkills: ["swiftui"],
            storyPoints: 1,
            status: .review,
            assignedAgentID: agentID,
            executionRecord: TaskExecutionRecord(status: .succeeded)
        )

        let descriptors = [
            Descriptor(taskID: taskA.id, milestone: "M2 MVP Complete", epic: "Core"),
            Descriptor(taskID: taskB.id, milestone: "M1 Setup", epic: ""),
            Descriptor(taskID: taskC.id, milestone: "M2 MVP Complete", epic: "Growth")
        ]

        let sections = PMRoadmapSummaryBuilder.buildSections(
            createdTasks: descriptors,
            tasks: [taskA, taskB, taskC],
            taskID: { $0.taskID },
            milestone: { $0.milestone },
            epic: { $0.epic }
        )

        #expect(sections.count == 6)
        #expect(sections.contains("\(L10n.string("Roadmap")) [\(L10n.string("Total"))]: 2/3 (67%)"))
        #expect(sections.contains("\(L10n.string("Roadmap")) [\(L10n.string("Unassigned"))]: 1/3"))
        #expect(sections.contains("\(L10n.string("Roadmap")) [\(L10n.string("To Do"))/\(L10n.string("In Progress"))/\(L10n.string("Review"))/\(L10n.string("Done"))]: 1/1/0/1"))
        #expect(sections.contains("\(L10n.string("Roadmap")) [\(L10n.string("Succeeded"))/\(L10n.string("Failed"))/\(L10n.string("Running"))]: 1/1/1"))

        let milestoneSection = sections.first { $0.contains("[\(L10n.string("Milestone"))]") }
        #expect(milestoneSection?.contains("\(L10n.format("Milestone: %@", "M1 Setup")) 1/1") == true)
        #expect(milestoneSection?.contains("\(L10n.format("Milestone: %@", "M2 MVP Complete")) 1/2") == true)

        let epicSection = sections.first { $0.contains("[\(L10n.string("Epic"))]") }
        #expect(epicSection?.contains("\(L10n.format("Epic: %@", "Core")) 0/1") == true)
        #expect(epicSection?.contains("\(L10n.format("Epic: %@", "Growth")) 1/1") == true)
    }

    @Test("buildSections returns empty list for empty roadmap")
    func buildSectionsEmptyRoadmap() {
        let sections = PMRoadmapSummaryBuilder.buildSections(
            createdTasks: [Descriptor](),
            tasks: [],
            taskID: { $0.taskID },
            milestone: { $0.milestone },
            epic: { $0.epic }
        )

        #expect(sections.isEmpty)
    }

    @Test("buildSections skips missing status rows and omits outcome section when no executions exist")
    func buildSectionsHandlesMissingTaskRowsWithoutExecutions() {
        let knownTask = WorkTask(
            title: "Known",
            details: "details",
            requiredSkills: ["swiftui"],
            storyPoints: 2,
            status: .todo,
            assignedAgentID: nil
        )
        let missingTaskID = UUID()
        let descriptors = [
            Descriptor(taskID: knownTask.id, milestone: "M1", epic: "Core"),
            Descriptor(taskID: missingTaskID, milestone: "M2", epic: "Growth")
        ]

        let sections = PMRoadmapSummaryBuilder.buildSections(
            createdTasks: descriptors,
            tasks: [knownTask],
            taskID: { $0.taskID },
            milestone: { $0.milestone },
            epic: { $0.epic }
        )

        #expect(sections.contains("\(L10n.string("Roadmap")) [\(L10n.string("Total"))]: 0/2 (0%)"))
        #expect(sections.contains("\(L10n.string("Roadmap")) [\(L10n.string("Unassigned"))]: 2/2"))
        #expect(sections.contains("\(L10n.string("Roadmap")) [\(L10n.string("To Do"))/\(L10n.string("In Progress"))/\(L10n.string("Review"))/\(L10n.string("Done"))]: 1/0/0/0"))
        #expect(sections.contains { $0.contains("[\(L10n.string("Succeeded"))/\(L10n.string("Failed"))/\(L10n.string("Running"))]") } == false)

        let milestoneSection = sections.first { $0.contains("[\(L10n.string("Milestone"))]") }
        #expect(milestoneSection?.contains("\(L10n.format("Milestone: %@", "M1")) 0/1") == true)
        #expect(milestoneSection?.contains("\(L10n.format("Milestone: %@", "M2")) 0/1") == true)

        let epicSection = sections.first { $0.contains("[\(L10n.string("Epic"))]") }
        #expect(epicSection?.contains("\(L10n.format("Epic: %@", "Core")) 0/1") == true)
        #expect(epicSection?.contains("\(L10n.format("Epic: %@", "Growth")) 0/1") == true)
    }

    @Test("buildSections omits epic section when every epic is blank")
    func buildSectionsOmitsEpicSectionWhenBlank() {
        let task = WorkTask(
            title: "Task",
            details: "details",
            requiredSkills: ["swiftui"],
            storyPoints: 1,
            status: .inProgress,
            assignedAgentID: UUID()
        )
        let descriptors = [
            Descriptor(taskID: task.id, milestone: "M1", epic: ""),
            Descriptor(taskID: task.id, milestone: "M1", epic: "   ")
        ]

        let sections = PMRoadmapSummaryBuilder.buildSections(
            createdTasks: descriptors,
            tasks: [task],
            taskID: { $0.taskID },
            milestone: { $0.milestone },
            epic: { $0.epic }
        )

        #expect(sections.contains { $0.contains("[\(L10n.string("Epic"))]") } == false)
    }
}

struct AppLanguageResolverTests {
    private static let userDefaultsMutationLock = NSLock()
    private static let runtimeLocaleMutationLock = NSLock()

    private func withLanguageOverrideInDefaults<T>(_ value: String?, run body: () throws -> T) rethrows -> T {
        Self.userDefaultsMutationLock.lock()
        defer { Self.userDefaultsMutationLock.unlock() }

        let defaults = UserDefaults.standard
        let key = AppLanguageSettings.userDefaultsKey
        let previousValue = defaults.object(forKey: key)

        if let value {
            defaults.set(value, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }

        defer {
            if let previousValue {
                defaults.set(previousValue, forKey: key)
            } else {
                defaults.removeObject(forKey: key)
            }
        }

        return try body()
    }

    private func resolve(_ preferredLanguages: [String]) -> AppLanguage {
        AppLanguageResolver.resolvedLanguage(
            preferredLanguages: preferredLanguages,
            overrideRawValue: AppLanguageSettings.systemValue
        )
    }

    @Test("maps traditional Chinese locales to zh-Hant")
    func mapsTraditionalChineseLocales() {
        #expect(resolve(["zh-TW"]).rawValue == "zh-Hant")
        #expect(resolve(["zh-HK"]).rawValue == "zh-Hant")
        #expect(resolve(["zh-Hant"]).rawValue == "zh-Hant")
        #expect(resolve(["zh"]).rawValue == "zh-Hant")
    }

    @Test("maps simplified Chinese locales to zh-Hans")
    func mapsSimplifiedChineseLocales() {
        #expect(resolve(["zh-CN"]).rawValue == "zh-Hans")
        #expect(resolve(["zh-SG"]).rawValue == "zh-Hans")
        #expect(resolve(["zh-Hans"]).rawValue == "zh-Hans")
    }

    @Test("maps supported non-Chinese locales")
    func mapsSupportedLocales() {
        #expect(resolve(["en-US"]).rawValue == "en")
        #expect(resolve(["fr-FR"]).rawValue == "fr")
        #expect(resolve(["es-ES"]).rawValue == "es")
        #expect(resolve(["ja-JP"]).rawValue == "ja")
        #expect(resolve(["ko-KR"]).rawValue == "ko")
    }

    @Test("falls back to English when no preferred language is supported")
    func fallsBackToEnglishForUnsupportedLocales() {
        #expect(resolve(["de-DE", "it-IT"]).rawValue == "en")
    }

    @Test("uses first supported preferred language in order")
    func picksFirstSupportedPreferredLanguage() {
        #expect(resolve(["de-DE", "ja-JP", "fr-FR"]).rawValue == "ja")
    }

    @Test("uses explicit language override when provided")
    func usesExplicitOverrideLanguage() {
        #expect(
            AppLanguageResolver.resolvedLanguage(
                preferredLanguages: ["en-US"],
                overrideRawValue: "ja"
            ).rawValue == "ja"
        )
    }

    @Test("system override follows preferred languages")
    func systemOverrideUsesPreferredLanguages() {
        #expect(
            AppLanguageResolver.resolvedLanguage(
                preferredLanguages: ["fr-FR"],
                overrideRawValue: AppLanguageSettings.systemValue
            ).rawValue == "fr"
        )
    }

    @Test("invalid override falls back to preferred language matching")
    func invalidOverrideFallsBackToPreferredLanguages() {
        #expect(
            AppLanguageResolver.resolvedLanguage(
                preferredLanguages: ["es-ES"],
                overrideRawValue: "invalid-language-code"
            ).rawValue == "es"
        )
    }

    @Test("app language preference raw value getter returns stable storage values")
    func appLanguagePreferenceRawValueGetter() {
        #expect(AppLanguagePreference.system.rawValue == AppLanguageSettings.systemValue)
        #expect(AppLanguagePreference.language(.japanese).rawValue == AppLanguage.japanese.rawValue)
    }

    @Test("app language preference initializer normalizes nil/empty/system/invalid and valid values")
    func appLanguagePreferenceInitializerNormalization() {
        #expect(AppLanguagePreference(rawValue: nil).rawValue == AppLanguageSettings.systemValue)
        #expect(AppLanguagePreference(rawValue: "").rawValue == AppLanguageSettings.systemValue)
        #expect(AppLanguagePreference(rawValue: " system ").rawValue == AppLanguageSettings.systemValue)
        #expect(AppLanguagePreference(rawValue: "ja").rawValue == AppLanguage.japanese.rawValue)
        #expect(AppLanguagePreference(rawValue: "unknown-language").rawValue == AppLanguageSettings.systemValue)
    }

    @Test("resolved language defaults to English in test host when no explicit override is provided")
    func resolvedLanguageDefaultArgumentsInTests() {
        #expect(AppLanguageResolver.resolvedLanguage() == .english)
    }

    @Test("resolved language reads persisted override when overrideRawValue is nil and preferred list is explicit")
    func resolvedLanguageReadsPersistedOverrideFromDefaults() {
        let resolved = withLanguageOverrideInDefaults(AppLanguage.japanese.rawValue) {
            AppLanguageResolver.resolvedLanguage(
                preferredLanguages: ["fr-FR"],
                overrideRawValue: nil
            )
        }

        #expect(resolved == .japanese)
    }

    @Test("resolved default locale keeps runtime locale when language matches override")
    func resolvedDefaultLocaleKeepsMatchingRuntimeLanguage() {
        let resolved = L10n.resolvedDefaultLocale(
            overrideRawValue: AppLanguage.english.rawValue,
            runtimeLocale: Locale(identifier: "en-US")
        )

        #expect(resolved.identifier == "en-US")
    }

    @Test("resolved default locale falls back to override locale when runtime language mismatches")
    func resolvedDefaultLocaleFallsBackWhenRuntimeLanguageDiffers() {
        let resolved = L10n.resolvedDefaultLocale(
            overrideRawValue: AppLanguage.english.rawValue,
            runtimeLocale: Locale(identifier: "zh-Hant")
        )

        #expect(AppLanguage.resolve(preferredLanguages: [resolved.identifier]) == .english)
    }

    @Test("resolved default locale returns configured locale when runtime locale is nil")
    func resolvedDefaultLocaleUsesConfiguredLocaleWhenRuntimeIsMissing() {
        let resolved = L10n.resolvedDefaultLocale(
            overrideRawValue: AppLanguage.french.rawValue,
            runtimeLocale: nil
        )

        #expect(AppLanguage.resolve(preferredLanguages: [resolved.identifier]) == .french)
    }

    @Test("L10n test-host detection covers environment class and bundle fallbacks")
    func l10nIsRunningTestsDetectionCoverage() {
        #expect(
            AppLanguageTestHooks.l10nIsRunningTests(
                environment: ["XCTestConfigurationFilePath": "/tmp/test.xctestconfiguration"],
                xctestClassExists: false,
                bundlePaths: []
            )
        )
        #expect(
            AppLanguageTestHooks.l10nIsRunningTests(
                environment: [:],
                xctestClassExists: true,
                bundlePaths: []
            )
        )
        #expect(
            AppLanguageTestHooks.l10nIsRunningTests(
                environment: [:],
                xctestClassExists: false,
                bundlePaths: ["/tmp/OpenMacTests.xctest"]
            )
        )
        #expect(
            !AppLanguageTestHooks.l10nIsRunningTests(
                environment: [:],
                xctestClassExists: false,
                bundlePaths: ["/tmp/OpenMac.app"]
            )
        )
    }

    @Test("L10n active runtime locale getter tracks set and clear operations")
    func l10nActiveRuntimeLocaleCoverage() {
        Self.runtimeLocaleMutationLock.lock()
        defer {
            _ = AppLanguageTestHooks.l10nSetAndReadActiveRuntimeLocale(nil)
            Self.runtimeLocaleMutationLock.unlock()
        }

        let assignedIdentifier = AppLanguageTestHooks.l10nSetAndReadActiveRuntimeLocale("fr-FR")
        #expect(assignedIdentifier == "fr-FR")

        let clearedIdentifier = AppLanguageTestHooks.l10nSetAndReadActiveRuntimeLocale(nil)
        #expect(clearedIdentifier == nil)
    }

    @Test("L10n internal default locale resolver normalizes overrides and runtime matching")
    func l10nInternalResolvedDefaultLocaleCoverage() {
        let forcedEnglish = AppLanguageTestHooks.l10nResolvedDefaultLocale(
            storedOverride: nil,
            runtimeLocaleIdentifier: "ja-JP",
            runningTests: true
        )
        #expect(AppLanguage.resolve(preferredLanguages: [forcedEnglish.identifier]) == .english)

        let systemNormalized = AppLanguageTestHooks.l10nResolvedDefaultLocale(
            storedOverride: " system ",
            runtimeLocaleIdentifier: nil,
            runningTests: false
        )
        #expect(AppLanguage.resolve(preferredLanguages: [systemNormalized.identifier]) == .english)

        let matchedRuntime = AppLanguageTestHooks.l10nResolvedDefaultLocale(
            storedOverride: AppLanguage.japanese.rawValue,
            runtimeLocaleIdentifier: "ja-JP",
            runningTests: false
        )
        #expect(matchedRuntime.identifier == "ja-JP")

        let mismatchedRuntime = AppLanguageTestHooks.l10nResolvedDefaultLocale(
            storedOverride: AppLanguage.japanese.rawValue,
            runtimeLocaleIdentifier: "fr-FR",
            runningTests: false
        )
        #expect(AppLanguage.resolve(preferredLanguages: [mismatchedRuntime.identifier]) == .japanese)
    }

    @Test("L10n string resolves localized value for explicit locale and falls back to key for unknown key")
    func localizedStringLookupAndUnknownKeyFallback() {
        let localized = L10n.string("New Task", locale: Locale(identifier: "zh-Hant"))
        #expect(localized == "新增任務")

        let unknownKey = "UNIT_TEST_UNKNOWN_LOCALIZATION_KEY_\(UUID().uuidString)"
        let fallback = L10n.string(unknownKey, locale: Locale(identifier: "zh-Hant"))
        #expect(fallback == unknownKey)
    }
}
