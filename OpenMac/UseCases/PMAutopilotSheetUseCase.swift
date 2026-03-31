import Foundation

struct PMGeneratedPlan {
    let projectName: String
    let summary: String
    let tickets: [PMPlannedTicket]
}

enum PMAutopilotPreparationStatus {
    case ready
    case blockedByAutoCycle
    case blockedByBatchRun
    case missingTickets
    case boardCreationFailed
}

struct PMAutopilotPreparationResult {
    let status: PMAutopilotPreparationStatus
    let shouldStart: Bool
    let plannedTickets: [PMPlannedTicket]
    let testPlanText: String
    let projectName: String
    let generatedPlanSummary: String?
    let didSwitchBoardContext: Bool
}

@MainActor
enum PMAutopilotSheetUseCase {
    static func prepareForRun(
        isAutoCycleRunning: Bool,
        isBatchRunning: Bool,
        plannedTickets: [PMPlannedTicket],
        testPlanText: String,
        projectName: String,
        shouldCreateNewBoard: Bool,
        existingBoardNames: [String],
        generatePlan: () -> PMGeneratedPlan?,
        applyAutoAcceptanceCriteria: ([PMPlannedTicket]) -> [PMPlannedTicket],
        generateTestPlan: (_ projectName: String, _ tickets: [PMPlannedTicket]) -> String,
        uniqueBoardName: (_ baseName: String, _ existingNames: [String]) -> String,
        createBoard: (_ boardName: String) -> Bool
    ) -> PMAutopilotPreparationResult {
        guard !isAutoCycleRunning else {
            return PMAutopilotPreparationResult(
                status: .blockedByAutoCycle,
                shouldStart: false,
                plannedTickets: plannedTickets,
                testPlanText: testPlanText,
                projectName: projectName,
                generatedPlanSummary: nil,
                didSwitchBoardContext: false
            )
        }
        guard !isBatchRunning else {
            return PMAutopilotPreparationResult(
                status: .blockedByBatchRun,
                shouldStart: false,
                plannedTickets: plannedTickets,
                testPlanText: testPlanText,
                projectName: projectName,
                generatedPlanSummary: nil,
                didSwitchBoardContext: false
            )
        }

        var resolvedProjectName = projectName
        var resolvedTickets = plannedTickets
        var generatedPlanSummary: String?

        if resolvedTickets.isEmpty {
            guard let generatedPlan = generatePlan() else {
                return PMAutopilotPreparationResult(
                    status: .missingTickets,
                    shouldStart: false,
                    plannedTickets: [],
                    testPlanText: testPlanText,
                    projectName: projectName,
                    generatedPlanSummary: nil,
                    didSwitchBoardContext: false
                )
            }
            resolvedProjectName = generatedPlan.projectName
            generatedPlanSummary = generatedPlan.summary
            resolvedTickets = generatedPlan.tickets
        }
        guard !resolvedTickets.isEmpty else {
            return PMAutopilotPreparationResult(
                status: .missingTickets,
                shouldStart: false,
                plannedTickets: [],
                testPlanText: testPlanText,
                projectName: resolvedProjectName,
                generatedPlanSummary: generatedPlanSummary,
                didSwitchBoardContext: false
            )
        }

        resolvedTickets = applyAutoAcceptanceCriteria(resolvedTickets)
        var resolvedTestPlanText = testPlanText
        if resolvedTestPlanText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            resolvedTestPlanText = generateTestPlan(resolvedProjectName, resolvedTickets)
        }

        var didSwitchBoardContext = false
        if shouldCreateNewBoard {
            let resolvedBoardName = uniqueBoardName(resolvedProjectName, existingBoardNames)
            guard createBoard(resolvedBoardName) else {
                return PMAutopilotPreparationResult(
                    status: .boardCreationFailed,
                    shouldStart: false,
                    plannedTickets: resolvedTickets,
                    testPlanText: resolvedTestPlanText,
                    projectName: resolvedProjectName,
                    generatedPlanSummary: generatedPlanSummary,
                    didSwitchBoardContext: false
                )
            }
            resolvedProjectName = resolvedBoardName
            didSwitchBoardContext = true
        }

        return PMAutopilotPreparationResult(
            status: .ready,
            shouldStart: true,
            plannedTickets: resolvedTickets,
            testPlanText: resolvedTestPlanText,
            projectName: resolvedProjectName,
            generatedPlanSummary: generatedPlanSummary,
            didSwitchBoardContext: didSwitchBoardContext
        )
    }
}
