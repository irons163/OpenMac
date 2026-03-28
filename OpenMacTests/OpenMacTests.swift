import Foundation
import SwiftUI
import Testing
@testable import OpenMac

struct AutoAssignmentEngineTests {

    @Test("assigns task to an agent with all required skills")
    func assignsTaskToSkillMatchedAgent() {
        let task = WorkTask(
            title: "Design onboarding flow",
            details: "Create welcome flow for first-time users",
            requiredSkills: ["ui", "ux"],
            storyPoints: 3,
            status: .todo,
            assignedAgentID: nil
        )

        let matchingAgent = AgentProfile(name: "Vision Agent", skills: ["ui", "ux", "swiftui"], maxConcurrentTasks: 2)
        let nonMatchingAgent = AgentProfile(name: "Backend Agent", skills: ["api", "db"], maxConcurrentTasks: 2)

        let result = AutoAssignmentEngine().assign(tasks: [task], agents: [matchingAgent, nonMatchingAgent])

        #expect(result.tasks[0].assignedAgentID == matchingAgent.id)
    }

    @Test("prefers less-loaded agent among eligible candidates")
    func prefersLessLoadedAgent() {
        let todoTask = WorkTask(
            title: "Implement cards",
            details: "Create kanban card UI",
            requiredSkills: ["swiftui"],
            storyPoints: 2,
            status: .todo,
            assignedAgentID: nil
        )

        let busyAgent = AgentProfile(name: "Agent A", skills: ["swiftui"], maxConcurrentTasks: 4)
        let freeAgent = AgentProfile(name: "Agent B", skills: ["swiftui"], maxConcurrentTasks: 4)
        let existingTask = WorkTask(
            title: "Existing",
            details: "Existing in-progress work",
            requiredSkills: ["swiftui"],
            storyPoints: 2,
            status: .inProgress,
            assignedAgentID: busyAgent.id
        )

        let result = AutoAssignmentEngine().assign(tasks: [existingTask, todoTask], agents: [busyAgent, freeAgent])
        let assignedTodo = result.tasks.first { $0.title == "Implement cards" }

        #expect(assignedTodo?.assignedAgentID == freeAgent.id)
    }

    @Test("keeps task unassigned when no agent has required skills")
    func keepsTaskUnassignedWithoutSkillMatch() {
        let task = WorkTask(
            title: "Train ranking model",
            details: "Need ml expertise",
            requiredSkills: ["ml"],
            storyPoints: 5,
            status: .todo,
            assignedAgentID: nil
        )

        let result = AutoAssignmentEngine().assign(
            tasks: [task],
            agents: [AgentProfile(name: "UI Agent", skills: ["swiftui"], maxConcurrentTasks: 2)]
        )

        #expect(result.tasks[0].assignedAgentID == nil)
        #expect(result.unassignedTaskIDs.contains(task.id))
    }

    @Test("uses task context keywords to break ties between equally-loaded candidates")
    func prefersContextRelevantAgent() {
        let task = WorkTask(
            title: "Polish animation transition",
            details: "Need smoother animation timing for drag interaction",
            requiredSkills: ["swiftui"],
            storyPoints: 2,
            status: .todo,
            assignedAgentID: nil
        )
        let generalAgent = AgentProfile(name: "General Agent", skills: ["swiftui"], maxConcurrentTasks: 3)
        let animationAgent = AgentProfile(name: "Motion Agent", skills: ["swiftui", "animation"], maxConcurrentTasks: 3)

        let result = AutoAssignmentEngine().assign(tasks: [task], agents: [generalAgent, animationAgent])

        #expect(result.tasks[0].assignedAgentID == animationAgent.id)
    }

    @Test("returns assignment explanation for assigned task")
    func includesAssignmentReason() {
        let task = WorkTask(
            title: "Implement board",
            details: "Create board UI",
            requiredSkills: ["swiftui"],
            storyPoints: 3,
            status: .todo,
            assignedAgentID: nil
        )
        let agent = AgentProfile(name: "UI Agent", skills: ["swiftui", "ui"], maxConcurrentTasks: 2)

        let result = AutoAssignmentEngine().assign(tasks: [task], agents: [agent])

        let decision = result.decisions[task.id]
        #expect(decision?.agentID == agent.id)
        #expect(!(decision?.reason.isEmpty ?? true))
        #expect((decision?.score ?? 0) > 0)
    }
}

struct AppearanceModeTests {

    @Test("maps appearance mode to preferred color scheme")
    func mapsAppearanceModeToPreferredColorScheme() {
        #expect(AppAppearanceMode.system.preferredColorScheme == nil)
        #expect(AppAppearanceMode.light.preferredColorScheme == .light)
        #expect(AppAppearanceMode.dark.preferredColorScheme == .dark)
    }

    @Test("defaults invalid stored appearance mode to system")
    func defaultsInvalidStoredAppearanceModeToSystem() {
        #expect(AppAppearanceMode.resolve(rawValue: "invalid") == .system)
    }

    @Test("cycles appearance mode in stable order")
    func cyclesAppearanceModeInStableOrder() {
        #expect(AppAppearanceMode.system.next() == .light)
        #expect(AppAppearanceMode.light.next() == .dark)
        #expect(AppAppearanceMode.dark.next() == .system)
    }

    @Test("resolves effective color scheme from system scheme and selected appearance mode")
    func resolvesEffectiveColorSchemeFromAppearanceSelection() {
        #expect(AppearanceSchemeResolver.resolve(systemScheme: .light, appearanceMode: .system) == .light)
        #expect(AppearanceSchemeResolver.resolve(systemScheme: .dark, appearanceMode: .system) == .dark)
        #expect(AppearanceSchemeResolver.resolve(systemScheme: .light, appearanceMode: .dark) == .dark)
        #expect(AppearanceSchemeResolver.resolve(systemScheme: .dark, appearanceMode: .light) == .light)
    }

    @Test("board message palette falls back to error tone when severity is missing")
    func boardMessagePaletteFallbacksToError() {
        let fallbackDark = BoardMessageColorPalette.token(for: nil, scheme: .dark)
        let fallbackLight = BoardMessageColorPalette.token(for: nil, scheme: .light)
        let errorDark = BoardMessageColorPalette.token(for: .error, scheme: .dark)
        let errorLight = BoardMessageColorPalette.token(for: .error, scheme: .light)

        #expect(fallbackDark.red == errorDark.red)
        #expect(fallbackDark.green == errorDark.green)
        #expect(fallbackDark.blue == errorDark.blue)
        #expect(fallbackDark.opacity == errorDark.opacity)

        #expect(fallbackLight.red == errorLight.red)
        #expect(fallbackLight.green == errorLight.green)
        #expect(fallbackLight.blue == errorLight.blue)
        #expect(fallbackLight.opacity == errorLight.opacity)
    }

    @Test("board message palette maintains dark mode contrast for all severities")
    func boardMessagePaletteDarkContrast() {
        let background = BoardMessageColorPalette.darkBoardBackground
        let infoContrast = BoardMessageColorPalette.token(for: .info, scheme: .dark).contrastRatio(against: background)
        let warningContrast = BoardMessageColorPalette.token(for: .warning, scheme: .dark).contrastRatio(against: background)
        let errorContrast = BoardMessageColorPalette.token(for: .error, scheme: .dark).contrastRatio(against: background)

        #expect(infoContrast >= 4.5)
        #expect(warningContrast >= 4.5)
        #expect(errorContrast >= 4.5)
    }

    @Test("board message palette maintains light mode contrast for all severities")
    func boardMessagePaletteLightContrast() {
        let background = BoardMessageColorPalette.lightBoardBackground
        let infoContrast = BoardMessageColorPalette.token(for: .info, scheme: .light).contrastRatio(against: background)
        let warningContrast = BoardMessageColorPalette.token(for: .warning, scheme: .light).contrastRatio(against: background)
        let errorContrast = BoardMessageColorPalette.token(for: .error, scheme: .light).contrastRatio(against: background)

        #expect(infoContrast >= 4.5)
        #expect(warningContrast >= 4.5)
        #expect(errorContrast >= 4.5)
    }

    @Test("summary badge palette maintains dark mode contrast across all accents")
    func summaryBadgePaletteDarkContrast() {
        let primaryText = BoardMessageColorToken(red: 1.0, green: 1.0, blue: 1.0, opacity: 1.0)

        for accent in SummaryBadgeAccent.allCases {
            let token = SummaryBadgePalette.token(for: accent, scheme: .dark)
            #expect(primaryText.contrastRatio(against: token) >= 4.5)
        }
    }

    @Test("summary badge palette maintains light mode contrast across all accents")
    func summaryBadgePaletteLightContrast() {
        let primaryText = BoardMessageColorToken(red: 0.0, green: 0.0, blue: 0.0, opacity: 1.0)

        for accent in SummaryBadgeAccent.allCases {
            let token = SummaryBadgePalette.token(for: accent, scheme: .light)
            #expect(primaryText.contrastRatio(against: token) >= 7.0)
        }
    }

    @Test("semantic status text palette keeps contrast in dark and light board backgrounds")
    func semanticStatusTextPaletteContrast() {
        let darkBackground = BoardMessageColorPalette.darkBoardBackground
        let lightBackground = BoardMessageColorPalette.lightBoardBackground
        let darkSupplementary = BoardSurfacePalette.supplementaryCardToken(for: .dark)
        let lightSupplementary = BoardSurfacePalette.supplementaryCardToken(for: .light)

        let successDark = BoardSemanticTextPalette.token(for: .success, scheme: .dark)
        let successLight = BoardSemanticTextPalette.token(for: .success, scheme: .light)
        let warningDark = BoardSemanticTextPalette.token(for: .warning, scheme: .dark)
        let warningLight = BoardSemanticTextPalette.token(for: .warning, scheme: .light)
        let errorDark = BoardSemanticTextPalette.token(for: .error, scheme: .dark)
        let errorLight = BoardSemanticTextPalette.token(for: .error, scheme: .light)

        #expect(successDark.contrastRatio(against: darkBackground) >= 4.5)
        #expect(successLight.contrastRatio(against: lightBackground) >= 4.5)
        #expect(warningDark.contrastRatio(against: darkBackground) >= 4.5)
        #expect(warningLight.contrastRatio(against: lightBackground) >= 4.5)
        #expect(errorDark.contrastRatio(against: darkBackground) >= 4.5)
        #expect(errorLight.contrastRatio(against: lightBackground) >= 4.5)
        #expect(errorDark.contrastRatio(against: darkSupplementary) >= 4.5)
        #expect(errorLight.contrastRatio(against: lightSupplementary) >= 4.5)
    }

    @Test("semantic error text keeps contrast on WIP counter surfaces")
    func semanticErrorTextCounterContrast() {
        let errorDark = BoardSemanticTextPalette.token(for: .error, scheme: .dark)
        let errorLight = BoardSemanticTextPalette.token(for: .error, scheme: .light)
        let counterDark = BoardChromePalette.counterToken(for: .dark)
        let counterLight = BoardChromePalette.counterToken(for: .light)

        #expect(errorDark.contrastRatio(against: counterDark) >= 4.5)
        #expect(errorLight.contrastRatio(against: counterLight) >= 4.5)
    }

    @Test("neutral secondary text palette remains readable across board surfaces")
    func neutralSecondaryTextPaletteContrast() {
        let secondaryDark = BoardNeutralTextPalette.token(for: .secondary, scheme: .dark)
        let secondaryLight = BoardNeutralTextPalette.token(for: .secondary, scheme: .light)

        let darkSurfaces = KanbanStatus.allCases.map { BoardSurfacePalette.columnToken(for: $0, scheme: .dark) }
            + [
                BoardSurfacePalette.taskCardToken(for: .dark),
                BoardSurfacePalette.supplementaryCardToken(for: .dark)
            ]

        let lightSurfaces = KanbanStatus.allCases.map { BoardSurfacePalette.columnToken(for: $0, scheme: .light) }
            + [
                BoardSurfacePalette.taskCardToken(for: .light),
                BoardSurfacePalette.supplementaryCardToken(for: .light)
            ]

        for surface in darkSurfaces {
            #expect(secondaryDark.contrastRatio(against: surface) >= 4.5)
        }

        for surface in lightSurfaces {
            #expect(secondaryLight.contrastRatio(against: surface) >= 4.5)
        }
    }

    @Test("dark task cards stay visually distinct from each kanban column background")
    func darkTaskCardsRemainDistinctFromColumns() {
        let taskCard = BoardSurfacePalette.taskCardToken(for: .dark)

        for status in KanbanStatus.allCases {
            let column = BoardSurfacePalette.columnToken(for: status, scheme: .dark)
            #expect(taskCard.contrastRatio(against: column) >= 1.5)
        }
    }

    @Test("dark board surfaces keep readable primary text contrast")
    func darkBoardSurfacesKeepReadablePrimaryTextContrast() {
        let primaryText = BoardMessageColorToken(red: 1.0, green: 1.0, blue: 1.0, opacity: 1.0)
        let taskCardContrast = primaryText.contrastRatio(against: BoardSurfacePalette.taskCardToken(for: .dark))

        #expect(taskCardContrast >= 4.5)
        for status in KanbanStatus.allCases {
            let columnContrast = primaryText.contrastRatio(against: BoardSurfacePalette.columnToken(for: status, scheme: .dark))
            #expect(columnContrast >= 4.5)
        }
    }

    @Test("dark supplementary surfaces keep readable primary text contrast")
    func darkSupplementarySurfacesKeepReadablePrimaryTextContrast() {
        let primaryText = BoardMessageColorToken(red: 1.0, green: 1.0, blue: 1.0, opacity: 1.0)
        let supplementaryContrast = primaryText.contrastRatio(against: BoardSurfacePalette.supplementaryCardToken(for: .dark))
        let emptyStateContrast = primaryText.contrastRatio(against: BoardSurfacePalette.emptyStateToken(for: .dark))

        #expect(supplementaryContrast >= 4.5)
        #expect(emptyStateContrast >= 4.5)
    }

    @Test("dark empty state remains distinct from dark task card")
    func darkEmptyStateRemainsDistinctFromTaskCard() {
        let emptyState = BoardSurfacePalette.emptyStateToken(for: .dark)
        let taskCard = BoardSurfacePalette.taskCardToken(for: .dark)

        #expect(emptyState.contrastRatio(against: taskCard) >= 1.2)
    }

    @Test("dark chrome surfaces keep readable primary text contrast")
    func darkChromeSurfacesKeepReadablePrimaryTextContrast() {
        let primaryText = BoardMessageColorToken(red: 1.0, green: 1.0, blue: 1.0, opacity: 1.0)
        let counterContrast = primaryText.contrastRatio(against: BoardChromePalette.counterToken(for: .dark))
        let storyPointContrast = primaryText.contrastRatio(against: BoardChromePalette.storyPointToken(for: .dark))

        #expect(counterContrast >= 4.5)
        #expect(storyPointContrast >= 4.5)
    }

    @Test("dark chrome borders remain visible against their host surfaces")
    func darkChromeBordersRemainVisibleAgainstHostSurfaces() {
        let columnBorder = BoardChromePalette.columnBorderToken(for: .dark)
        let taskBorder = BoardChromePalette.taskCardBorderToken(for: .dark)
        let supplementaryBorder = BoardChromePalette.supplementaryCardBorderToken(for: .dark)

        for status in KanbanStatus.allCases {
            let column = BoardSurfacePalette.columnToken(for: status, scheme: .dark)
            #expect(columnBorder.contrastRatio(against: column) >= 1.3)
        }

        #expect(taskBorder.contrastRatio(against: BoardSurfacePalette.taskCardToken(for: .dark)) >= 1.3)
        #expect(supplementaryBorder.contrastRatio(against: BoardSurfacePalette.supplementaryCardToken(for: .dark)) >= 1.3)
    }

    @Test("light chrome surfaces keep readable primary text contrast")
    func lightChromeSurfacesKeepReadablePrimaryTextContrast() {
        let primaryText = BoardMessageColorToken(red: 0.0, green: 0.0, blue: 0.0, opacity: 1.0)
        let counterContrast = primaryText.contrastRatio(against: BoardChromePalette.counterToken(for: .light))
        let storyPointContrast = primaryText.contrastRatio(against: BoardChromePalette.storyPointToken(for: .light))

        #expect(counterContrast >= 7.0)
        #expect(storyPointContrast >= 7.0)
    }

    @Test("light chrome borders remain visible against their host surfaces")
    func lightChromeBordersRemainVisibleAgainstHostSurfaces() {
        let columnBorder = BoardChromePalette.columnBorderToken(for: .light)
        let taskBorder = BoardChromePalette.taskCardBorderToken(for: .light)
        let supplementaryBorder = BoardChromePalette.supplementaryCardBorderToken(for: .light)

        for status in KanbanStatus.allCases {
            let column = BoardSurfacePalette.columnToken(for: status, scheme: .light)
            #expect(columnBorder.contrastRatio(against: column) >= 1.25)
        }

        #expect(taskBorder.contrastRatio(against: BoardSurfacePalette.taskCardToken(for: .light)) >= 1.25)
        #expect(supplementaryBorder.contrastRatio(against: BoardSurfacePalette.supplementaryCardToken(for: .light)) >= 1.25)
    }
}

struct KanbanFlowTests {

    @Test("allows adjacent forward and backward transitions")
    func allowsAdjacentTransitions() {
        #expect(KanbanStatus.todo.canMove(to: .inProgress))
        #expect(KanbanStatus.inProgress.canMove(to: .review))
        #expect(KanbanStatus.review.canMove(to: .done))
        #expect(KanbanStatus.review.canMove(to: .inProgress))
        #expect(KanbanStatus.inProgress.canMove(to: .todo))
    }

    @Test("prevents skipping columns")
    func preventsSkippingColumns() {
        #expect(!KanbanStatus.todo.canMove(to: .review))
        #expect(!KanbanStatus.todo.canMove(to: .done))
        #expect(!KanbanStatus.done.canMove(to: .todo))
    }

    @Test("view model applies valid move and rejects invalid move")
    func viewModelMoveValidation() {
        let task = WorkTask(
            title: "Write tests",
            details: "TDD first",
            requiredSkills: ["swift"],
            storyPoints: 1,
            status: .todo,
            assignedAgentID: nil
        )

        let viewModel = KanbanBoardViewModel(tasks: [task], agents: [])
        viewModel.moveTask(task.id, to: .done)

        #expect(viewModel.tasks[0].status == .todo)

        viewModel.moveTask(task.id, to: .inProgress)
        #expect(viewModel.tasks[0].status == .inProgress)
    }

    @Test("moving task back to todo clears assignment for redispatch")
    func moveBackToTodoClearsAssignment() {
        let agent = AgentProfile(name: "Dispatch Agent", skills: ["swift"], maxConcurrentTasks: 2)
        let task = WorkTask(
            title: "Refine flow",
            details: "Needs another iteration",
            requiredSkills: ["swift"],
            storyPoints: 2,
            status: .inProgress,
            assignedAgentID: agent.id
        )

        let viewModel = KanbanBoardViewModel(tasks: [task], agents: [agent])
        viewModel.moveTask(task.id, to: .todo)

        #expect(viewModel.tasks[0].status == .todo)
        #expect(viewModel.tasks[0].assignedAgentID == nil)
    }

    @Test("drop handler applies adjacent move and rejects skipped columns")
    func dropHandlerRespectsWorkflow() {
        let task = WorkTask(
            title: "Drop test",
            details: "Validate drag and drop routing",
            requiredSkills: ["swiftui"],
            storyPoints: 1,
            status: .todo,
            assignedAgentID: nil
        )
        let viewModel = KanbanBoardViewModel(tasks: [task], agents: [])

        let skipped = viewModel.handleDrop(task.id, to: .review)
        #expect(!skipped)
        #expect(viewModel.tasks[0].status == .todo)

        let adjacent = viewModel.handleDrop(task.id, to: .inProgress)
        #expect(adjacent)
        #expect(viewModel.tasks[0].status == .inProgress)
    }

    @Test("prevents move into a column that reached WIP limit")
    func preventsMoveWhenWIPLimitReached() {
        let activeTask = WorkTask(
            title: "Already active",
            details: "Occupies WIP slot",
            requiredSkills: ["swiftui"],
            storyPoints: 2,
            status: .inProgress,
            assignedAgentID: nil
        )
        let todoTask = WorkTask(
            title: "Queued task",
            details: "Should wait for capacity",
            requiredSkills: ["swiftui"],
            storyPoints: 1,
            status: .todo,
            assignedAgentID: nil
        )

        let viewModel = KanbanBoardViewModel(
            tasks: [activeTask, todoTask],
            agents: [],
            wipLimits: [.inProgress: 1]
        )

        let moved = viewModel.handleDrop(todoTask.id, to: .inProgress)

        #expect(!moved)
        #expect(viewModel.tasks.first(where: { $0.id == todoTask.id })?.status == .todo)
        #expect(viewModel.lastBoardMessage == "WIP limit reached for In Progress (1)")
    }

    @Test("allows move once WIP slot becomes available")
    func allowsMoveAfterWIPSlotFreesUp() {
        let activeTask = WorkTask(
            title: "In progress task",
            details: "Will move forward",
            requiredSkills: ["swiftui"],
            storyPoints: 2,
            status: .inProgress,
            assignedAgentID: nil
        )
        let queuedTask = WorkTask(
            title: "Queued",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 1,
            status: .todo,
            assignedAgentID: nil
        )

        let viewModel = KanbanBoardViewModel(
            tasks: [activeTask, queuedTask],
            agents: [],
            wipLimits: [.inProgress: 1]
        )

        viewModel.moveTask(activeTask.id, to: .review)
        let moved = viewModel.handleDrop(queuedTask.id, to: .inProgress)

        #expect(moved)
        #expect(viewModel.tasks.first(where: { $0.id == queuedTask.id })?.status == .inProgress)
    }

    @Test("auto assign in view model updates task owner")
    func viewModelAutoAssign() {
        let task = WorkTask(
            title: "Build drag and drop",
            details: "Kanban interaction",
            requiredSkills: ["swiftui"],
            storyPoints: 3,
            status: .todo,
            assignedAgentID: nil
        )
        let agent = AgentProfile(name: "UI Agent", skills: ["swiftui"], maxConcurrentTasks: 2)
        let viewModel = KanbanBoardViewModel(tasks: [task], agents: [agent])

        viewModel.autoAssignTasks()

        #expect(viewModel.tasks[0].assignedAgentID == agent.id)
        #expect(viewModel.assignmentReason(for: task.id) != nil)
    }

    @Test("filters tasks by search query across title details skills and assignee name")
    func filtersTasksBySearchQuery() {
        let searchAgent = AgentProfile(name: "Search Agent", skills: ["swiftui"], maxConcurrentTasks: 2)
        let matchByTitle = WorkTask(
            title: "Implement search panel",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 2,
            status: .todo,
            assignedAgentID: nil
        )
        let matchByDetails = WorkTask(
            title: "Board metrics",
            details: "Need search query parser",
            requiredSkills: ["swift"],
            storyPoints: 2,
            status: .todo,
            assignedAgentID: nil
        )
        let matchBySkills = WorkTask(
            title: "Styling",
            details: "",
            requiredSkills: ["search"],
            storyPoints: 1,
            status: .todo,
            assignedAgentID: searchAgent.id
        )
        let nonMatch = WorkTask(
            title: "Notifications",
            details: "No filter keyword",
            requiredSkills: ["backend"],
            storyPoints: 1,
            status: .todo,
            assignedAgentID: nil
        )
        let matchByAssignee = WorkTask(
            title: "Polish transitions",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 1,
            status: .todo,
            assignedAgentID: searchAgent.id
        )
        let viewModel = KanbanBoardViewModel(
            tasks: [matchByTitle, matchByDetails, matchBySkills, matchByAssignee, nonMatch],
            agents: [searchAgent]
        )

        let filtered = viewModel.filteredTasks(in: .todo, query: "search", assigneeFilter: .all)

        #expect(filtered.count == 4)
        #expect(filtered.contains(where: { $0.id == matchByTitle.id }))
        #expect(filtered.contains(where: { $0.id == matchByDetails.id }))
        #expect(filtered.contains(where: { $0.id == matchBySkills.id }))
        #expect(filtered.contains(where: { $0.id == matchByAssignee.id }))
        #expect(!filtered.contains(where: { $0.id == nonMatch.id }))
    }

    @Test("filters tasks by assignee option")
    func filtersTasksByAssigneeOption() {
        let agent = AgentProfile(name: "UI Agent", skills: ["swiftui"], maxConcurrentTasks: 2)
        let assigned = WorkTask(
            title: "Assigned",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 2,
            status: .inProgress,
            assignedAgentID: agent.id
        )
        let unassigned = WorkTask(
            title: "Unassigned",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 1,
            status: .inProgress,
            assignedAgentID: nil
        )
        let viewModel = KanbanBoardViewModel(tasks: [assigned, unassigned], agents: [agent])

        let onlyAssigned = viewModel.filteredTasks(in: .inProgress, query: "", assigneeFilter: .assigned(agent.id))
        let onlyUnassigned = viewModel.filteredTasks(in: .inProgress, query: "", assigneeFilter: .unassigned)

        #expect(onlyAssigned.count == 1)
        #expect(onlyAssigned.first?.id == assigned.id)
        #expect(onlyUnassigned.count == 1)
        #expect(onlyUnassigned.first?.id == unassigned.id)
    }

    @Test("matches multi-word search query across mixed fields")
    func matchesMultiWordSearchAcrossMixedFields() {
        let agent = AgentProfile(name: "Panel Crew", skills: ["ux"], maxConcurrentTasks: 2)
        let crossFieldMatch = WorkTask(
            title: "Polish panel layout",
            details: "Add better search parser",
            requiredSkills: ["swiftui"],
            storyPoints: 2,
            status: .todo,
            assignedAgentID: nil
        )
        let assigneeMatch = WorkTask(
            title: "Accessibility fixes",
            details: "Improve search support",
            requiredSkills: ["swiftui"],
            storyPoints: 1,
            status: .todo,
            assignedAgentID: agent.id
        )
        let partialMatch = WorkTask(
            title: "Search only",
            details: "No layout term here",
            requiredSkills: ["swiftui"],
            storyPoints: 1,
            status: .todo,
            assignedAgentID: nil
        )
        let viewModel = KanbanBoardViewModel(
            tasks: [crossFieldMatch, assigneeMatch, partialMatch],
            agents: [agent]
        )

        let filtered = viewModel.filteredTasks(in: .todo, query: "search panel", assigneeFilter: .all)

        #expect(filtered.count == 2)
        #expect(filtered.contains(where: { $0.id == crossFieldMatch.id }))
        #expect(filtered.contains(where: { $0.id == assigneeMatch.id }))
        #expect(!filtered.contains(where: { $0.id == partialMatch.id }))
    }

    @Test("computes agent load ratio and overload state")
    func computesAgentLoadMetrics() {
        let agent = AgentProfile(name: "UI Agent", skills: ["swiftui"], maxConcurrentTasks: 2)
        let taskA = WorkTask(
            title: "Task A",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 2,
            status: .inProgress,
            assignedAgentID: agent.id
        )
        let taskB = WorkTask(
            title: "Task B",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 1,
            status: .todo,
            assignedAgentID: agent.id
        )
        let taskC = WorkTask(
            title: "Task C",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 1,
            status: .review,
            assignedAgentID: agent.id
        )
        let viewModel = KanbanBoardViewModel(tasks: [taskA, taskB, taskC], agents: [agent])

        let ratio = viewModel.loadRatio(for: agent.id)
        let percent = viewModel.loadPercent(for: agent.id)
        let overloaded = viewModel.isAgentOverloaded(agent.id)

        #expect(ratio > 1.0)
        #expect(percent == 150)
        #expect(overloaded)
    }

    @Test("reports rebalance availability when overloaded todo can move")
    func canRebalanceWhenOverloadedTodoHasEligibleTarget() {
        let overloaded = AgentProfile(name: "A Agent", skills: ["swiftui"], maxConcurrentTasks: 1)
        let target = AgentProfile(name: "B Agent", skills: ["swiftui"], maxConcurrentTasks: 2)
        let taskA = WorkTask(
            title: "Task A",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 2,
            status: .todo,
            assignedAgentID: overloaded.id
        )
        let taskB = WorkTask(
            title: "Task B",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 1,
            status: .todo,
            assignedAgentID: overloaded.id
        )
        let viewModel = KanbanBoardViewModel(tasks: [taskA, taskB], agents: [overloaded, target])

        #expect(viewModel.canRebalanceTodoAssignments())
    }

    @Test("reports no rebalance availability when overloaded work is not todo")
    func cannotRebalanceWhenOnlyInProgressIsOverloaded() {
        let overloaded = AgentProfile(name: "A Agent", skills: ["swiftui"], maxConcurrentTasks: 1)
        let target = AgentProfile(name: "B Agent", skills: ["swiftui"], maxConcurrentTasks: 2)
        let taskA = WorkTask(
            title: "Task A",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 2,
            status: .inProgress,
            assignedAgentID: overloaded.id
        )
        let taskB = WorkTask(
            title: "Task B",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 1,
            status: .inProgress,
            assignedAgentID: overloaded.id
        )
        let viewModel = KanbanBoardViewModel(tasks: [taskA, taskB], agents: [overloaded, target])

        #expect(!viewModel.canRebalanceTodoAssignments())
    }

    @Test("computes board health counters")
    func computesBoardHealthCounters() {
        let overloaded = AgentProfile(name: "A Agent", skills: ["swiftui"], maxConcurrentTasks: 1)
        let healthy = AgentProfile(name: "B Agent", skills: ["swiftui"], maxConcurrentTasks: 3)
        let todoAssigned = WorkTask(
            title: "Todo Assigned",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 1,
            status: .todo,
            assignedAgentID: overloaded.id
        )
        let todoUnassigned = WorkTask(
            title: "Todo Unassigned",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 1,
            status: .todo,
            assignedAgentID: nil
        )
        let inProgress = WorkTask(
            title: "In Progress",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 2,
            status: .inProgress,
            assignedAgentID: overloaded.id
        )
        let done = WorkTask(
            title: "Done",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 3,
            status: .done,
            assignedAgentID: healthy.id
        )
        let viewModel = KanbanBoardViewModel(tasks: [todoAssigned, todoUnassigned, inProgress, done], agents: [overloaded, healthy])

        #expect(viewModel.totalTaskCount == 4)
        #expect(viewModel.todoTaskCount == 2)
        #expect(viewModel.unassignedTodoTaskCount == 1)
        #expect(viewModel.overloadedAgentCount == 1)
    }

    @Test("reports perfect health score for stable board")
    func reportsPerfectHealthScoreForStableBoard() {
        let agent = AgentProfile(name: "UI Agent", skills: ["swiftui"], maxConcurrentTasks: 3)
        let todoAssigned = WorkTask(
            title: "Todo Assigned",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 1,
            status: .todo,
            assignedAgentID: agent.id
        )
        let inProgress = WorkTask(
            title: "In Progress",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 2,
            status: .inProgress,
            assignedAgentID: agent.id
        )
        let viewModel = KanbanBoardViewModel(
            tasks: [todoAssigned, inProgress],
            agents: [agent],
            wipLimits: [.inProgress: 4, .review: 2]
        )

        #expect(viewModel.boardHealthScore == 100)
        #expect(viewModel.boardHealthLabel == "Excellent")
        #expect(viewModel.boardHealthBreakdownText == "No active penalties")
    }

    @Test("reduces health score for unassigned work overload and WIP pressure")
    func reducesHealthScoreForBoardRisks() {
        let overloaded = AgentProfile(name: "A Agent", skills: ["swiftui"], maxConcurrentTasks: 1)
        let healthy = AgentProfile(name: "B Agent", skills: ["swiftui"], maxConcurrentTasks: 3)
        let todoAssignedA = WorkTask(
            title: "Todo A",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 1,
            status: .todo,
            assignedAgentID: overloaded.id
        )
        let todoAssignedB = WorkTask(
            title: "Todo B",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 1,
            status: .todo,
            assignedAgentID: overloaded.id
        )
        let todoUnassigned = WorkTask(
            title: "Todo C",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 1,
            status: .todo,
            assignedAgentID: nil
        )
        let inProgress = WorkTask(
            title: "In Progress",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 1,
            status: .inProgress,
            assignedAgentID: overloaded.id
        )
        let review = WorkTask(
            title: "Review",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 1,
            status: .review,
            assignedAgentID: healthy.id
        )
        let done = WorkTask(
            title: "Done",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 1,
            status: .done,
            assignedAgentID: nil
        )
        let viewModel = KanbanBoardViewModel(
            tasks: [todoAssignedA, todoAssignedB, todoUnassigned, inProgress, review, done],
            agents: [overloaded, healthy],
            wipLimits: [.inProgress: 1, .review: 1]
        )

        #expect(viewModel.boardHealthScore == 55)
        #expect(viewModel.boardHealthLabel == "Critical")
        #expect(viewModel.boardHealthBreakdownText.contains("Unassigned To Do: -10"))
        #expect(viewModel.boardHealthBreakdownText.contains("Overloaded Agents: -10"))
        #expect(viewModel.boardHealthBreakdownText.contains("In Progress WIP Pressure: -10"))
        #expect(viewModel.boardHealthBreakdownText.contains("Review WIP Pressure: -10"))
        #expect(viewModel.boardHealthBreakdownText.contains("Done Backlog: -5"))
        #expect(viewModel.boardHealthBreakdownText.contains("Total Penalty: -45"))
        #expect(viewModel.boardHealthBreakdownText.contains("Health Score: 55"))
    }

    @Test("maps medium health scores to watch label")
    func mapsMediumHealthScoresToWatchLabel() {
        let agent = AgentProfile(name: "UI Agent", skills: ["swiftui"], maxConcurrentTasks: 2)
        let todoAssigned = WorkTask(
            title: "Todo",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 1,
            status: .todo,
            assignedAgentID: agent.id
        )
        let done = WorkTask(
            title: "Done",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 1,
            status: .done,
            assignedAgentID: nil
        )
        let viewModel = KanbanBoardViewModel(
            tasks: [todoAssigned, done],
            agents: [agent],
            wipLimits: [.inProgress: 3, .review: 2]
        )

        #expect(viewModel.boardHealthScore == 95)
        #expect(viewModel.boardHealthLabel == "Excellent")

        _ = viewModel.addTask(
            title: "Unassigned",
            details: "",
            requiredSkillsText: "swiftui",
            storyPoints: 1
        )

        #expect(viewModel.boardHealthScore == 85)
        #expect(viewModel.boardHealthLabel == "Excellent")

        _ = viewModel.addTask(
            title: "Unassigned 2",
            details: "",
            requiredSkillsText: "swiftui",
            storyPoints: 1
        )

        #expect(viewModel.boardHealthScore == 75)
        #expect(viewModel.boardHealthLabel == "Watch")
    }

    @Test("computes wip pressure ratio against configured limits")
    func computesWIPPressureRatio() {
        let inProgressA = WorkTask(
            title: "A",
            details: "",
            requiredSkills: [],
            storyPoints: 1,
            status: .inProgress,
            assignedAgentID: nil
        )
        let inProgressB = WorkTask(
            title: "B",
            details: "",
            requiredSkills: [],
            storyPoints: 1,
            status: .inProgress,
            assignedAgentID: nil
        )
        let review = WorkTask(
            title: "Review",
            details: "",
            requiredSkills: [],
            storyPoints: 1,
            status: .review,
            assignedAgentID: nil
        )
        let viewModel = KanbanBoardViewModel(
            tasks: [inProgressA, inProgressB, review],
            agents: [],
            wipLimits: [.inProgress: 4, .review: 2]
        )

        #expect(viewModel.wipPressurePercent(for: .inProgress) == 50)
        #expect(viewModel.wipPressurePercent(for: .review) == 50)
    }

    @Test("builds actionable health recommendations from board state")
    func buildsActionableHealthRecommendations() {
        let overloaded = AgentProfile(name: "A Agent", skills: ["swiftui"], maxConcurrentTasks: 1)
        let available = AgentProfile(name: "B Agent", skills: ["swiftui"], maxConcurrentTasks: 3)
        let todoAssignedA = WorkTask(
            title: "Todo A",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 2,
            status: .todo,
            assignedAgentID: overloaded.id
        )
        let todoAssignedB = WorkTask(
            title: "Todo B",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 1,
            status: .todo,
            assignedAgentID: overloaded.id
        )
        let todoUnassigned = WorkTask(
            title: "Todo Unassigned",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 1,
            status: .todo,
            assignedAgentID: nil
        )
        let inProgress = WorkTask(
            title: "In Progress",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 3,
            status: .inProgress,
            assignedAgentID: overloaded.id
        )
        let done = WorkTask(
            title: "Done",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 1,
            status: .done,
            assignedAgentID: nil
        )
        let viewModel = KanbanBoardViewModel(
            tasks: [todoAssignedA, todoAssignedB, todoUnassigned, inProgress, done],
            agents: [overloaded, available],
            wipLimits: [.inProgress: 1, .review: 2]
        )

        let actions = viewModel.healthRecommendations().map(\.action)

        #expect(actions.contains(.autoAssignUnassignedTodo))
        #expect(actions.contains(.rebalanceTodoLoad))
        #expect(actions.contains(.increaseWIPLimit(.inProgress)))
        #expect(actions.contains(.archiveDone))
    }

    @Test("applies increase WIP health recommendation")
    func appliesIncreaseWIPHealthRecommendation() {
        let reviewTask = WorkTask(
            title: "Review",
            details: "",
            requiredSkills: ["testing"],
            storyPoints: 2,
            status: .review,
            assignedAgentID: nil
        )
        let viewModel = KanbanBoardViewModel(
            tasks: [reviewTask],
            agents: [],
            wipLimits: [.review: 1]
        )

        let applied = viewModel.applyHealthRecommendation(.increaseWIPLimit(.review))

        #expect(applied)
        #expect(viewModel.wipLimit(for: .review) == 2)
    }

    @Test("includes manual triage recommendation when unassigned todo exists")
    func includesManualTriageRecommendation() {
        let task = WorkTask(
            title: "Needs assignment",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 2,
            status: .todo,
            assignedAgentID: nil
        )
        let agent = AgentProfile(name: "UI Agent", skills: ["swiftui"], maxConcurrentTasks: 2)
        let viewModel = KanbanBoardViewModel(tasks: [task], agents: [agent])

        let actions = viewModel.healthRecommendations().map(\.action)

        #expect(actions.contains(.openManualTriage))
    }

    @Test("includes add agent recommendation when unassigned todo exists and no agents are available")
    func includesAddAgentRecommendationWhenNoAgents() {
        let task = WorkTask(
            title: "Needs assignment",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 2,
            status: .todo,
            assignedAgentID: nil
        )
        let viewModel = KanbanBoardViewModel(tasks: [task], agents: [])

        let actions = viewModel.healthRecommendations().map(\.action)

        #expect(actions.contains(.openNewAgent))
        #expect(!actions.contains(.openManualTriage))
        #expect(!actions.contains(.autoAssignUnassignedTodo))
    }

    @Test("flags pending manual triage when unassigned todo exists and agents are available")
    func flagsPendingManualTriageWhenAgentsExist() {
        let task = WorkTask(
            title: "Needs assignment",
            details: "",
            requiredSkills: ["ml"],
            storyPoints: 2,
            status: .todo,
            assignedAgentID: nil
        )
        let agent = AgentProfile(name: "UI Agent", skills: ["swiftui"], maxConcurrentTasks: 2)
        let viewModel = KanbanBoardViewModel(tasks: [task], agents: [agent])

        viewModel.autoAssignTasks()

        #expect(viewModel.hasPendingManualTriage)
    }

    @Test("does not flag manual triage when no agents exist")
    func doesNotFlagManualTriageWhenNoAgentsExist() {
        let task = WorkTask(
            title: "Needs assignment",
            details: "",
            requiredSkills: ["ml"],
            storyPoints: 2,
            status: .todo,
            assignedAgentID: nil
        )
        let viewModel = KanbanBoardViewModel(tasks: [task], agents: [])

        #expect(!viewModel.hasPendingManualTriage)
    }

    @Test("counts auto-fixable health recommendations")
    func countsAutoFixableHealthRecommendations() {
        let overloaded = AgentProfile(name: "A Agent", skills: ["swiftui"], maxConcurrentTasks: 1)
        let available = AgentProfile(name: "B Agent", skills: ["swiftui"], maxConcurrentTasks: 3)
        let todoAssignedA = WorkTask(
            title: "Todo A",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 2,
            status: .todo,
            assignedAgentID: overloaded.id
        )
        let todoAssignedB = WorkTask(
            title: "Todo B",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 1,
            status: .todo,
            assignedAgentID: overloaded.id
        )
        let todoUnassigned = WorkTask(
            title: "Todo C",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 1,
            status: .todo,
            assignedAgentID: nil
        )
        let inProgress = WorkTask(
            title: "In Progress",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 3,
            status: .inProgress,
            assignedAgentID: overloaded.id
        )
        let done = WorkTask(
            title: "Done",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 1,
            status: .done,
            assignedAgentID: nil
        )
        let viewModel = KanbanBoardViewModel(
            tasks: [todoAssignedA, todoAssignedB, todoUnassigned, inProgress, done],
            agents: [overloaded, available],
            wipLimits: [.inProgress: 1, .review: 2]
        )

        #expect(viewModel.autoFixableHealthRecommendationCount == 4)
        #expect(viewModel.hasAutoFixableHealthRecommendations)
    }

    @Test("reports no auto-fixable health recommendations when only navigation actions exist")
    func reportsNoAutoFixableHealthRecommendationsForNavigationOnlyActions() {
        let task = WorkTask(
            title: "Needs assignment",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 2,
            status: .todo,
            assignedAgentID: nil
        )
        let viewModel = KanbanBoardViewModel(tasks: [task], agents: [])

        #expect(viewModel.autoFixableHealthRecommendationCount == 0)
        #expect(!viewModel.hasAutoFixableHealthRecommendations)
    }

    @Test("applies all mutating health recommendations in one pass")
    func appliesAllMutatingHealthRecommendationsInOnePass() {
        let overloaded = AgentProfile(name: "A Agent", skills: ["swiftui"], maxConcurrentTasks: 1)
        let available = AgentProfile(name: "B Agent", skills: ["swiftui"], maxConcurrentTasks: 3)
        let todoAssignedA = WorkTask(
            title: "Todo A",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 2,
            status: .todo,
            assignedAgentID: overloaded.id
        )
        let todoAssignedB = WorkTask(
            title: "Todo B",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 1,
            status: .todo,
            assignedAgentID: overloaded.id
        )
        let todoUnassigned = WorkTask(
            title: "Todo C",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 1,
            status: .todo,
            assignedAgentID: nil
        )
        let inProgress = WorkTask(
            title: "In Progress",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 3,
            status: .inProgress,
            assignedAgentID: overloaded.id
        )
        let done = WorkTask(
            title: "Done",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 1,
            status: .done,
            assignedAgentID: nil
        )
        let viewModel = KanbanBoardViewModel(
            tasks: [todoAssignedA, todoAssignedB, todoUnassigned, inProgress, done],
            agents: [overloaded, available],
            wipLimits: [.inProgress: 1, .review: 2]
        )

        let appliedCount = viewModel.applyAllHealthRecommendations()

        #expect(appliedCount == 4)
        #expect(viewModel.doneTaskCount == 0)
        #expect(viewModel.wipLimit(for: .inProgress) == 2)
        #expect(viewModel.unassignedTodoTaskCount == 0)
        #expect(viewModel.activeTaskCount(for: overloaded.id) == 1)
        #expect(viewModel.healthRecommendations().isEmpty)
        #expect(viewModel.lastBoardMessage == "Applied 4 health recommendation(s)")
        #expect(viewModel.lastBoardMessageSeverity?.rawValue == "info")
    }

    @Test("reports when apply-all has no automatic fixes available")
    func reportsWhenApplyAllHasNoAutomaticFixes() {
        let task = WorkTask(
            title: "Needs assignment",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 2,
            status: .todo,
            assignedAgentID: nil
        )
        let viewModel = KanbanBoardViewModel(tasks: [task], agents: [])

        let appliedCount = viewModel.applyAllHealthRecommendations()

        #expect(appliedCount == 0)
        #expect(viewModel.lastBoardMessage == "No automatic fixes available for current recommendations")
        #expect(viewModel.lastBoardMessageSeverity?.rawValue == "warning")
    }

    @Test("reports info tone when board is already stable during apply-all")
    func applyAllReportsInfoWhenBoardAlreadyStable() {
        let agent = AgentProfile(name: "UI Agent", skills: ["swiftui"], maxConcurrentTasks: 2)
        let task = WorkTask(
            title: "Assigned task",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 2,
            status: .todo,
            assignedAgentID: agent.id
        )
        let viewModel = KanbanBoardViewModel(tasks: [task], agents: [agent])

        let appliedCount = viewModel.applyAllHealthRecommendations()

        #expect(appliedCount == 0)
        #expect(viewModel.lastBoardMessage == "Board health already stable")
        #expect(viewModel.lastBoardMessageSeverity?.rawValue == "info")
    }

    @Test("returns no health recommendations when board is healthy")
    func returnsNoHealthRecommendationsWhenHealthy() {
        let agent = AgentProfile(name: "UI Agent", skills: ["swiftui"], maxConcurrentTasks: 3)
        let todoAssigned = WorkTask(
            title: "Todo Assigned",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 1,
            status: .todo,
            assignedAgentID: agent.id
        )
        let inProgress = WorkTask(
            title: "In Progress",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 2,
            status: .inProgress,
            assignedAgentID: agent.id
        )
        let viewModel = KanbanBoardViewModel(
            tasks: [todoAssigned, inProgress],
            agents: [agent],
            wipLimits: [.inProgress: 3, .review: 2]
        )

        #expect(viewModel.healthRecommendations().isEmpty)
    }
}

struct KanbanPersistenceTests {

    @Test("persists board snapshot after successful state mutation")
    func persistsBoardAfterMove() {
        let task = WorkTask(
            title: "Persist me",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 1,
            status: .todo,
            assignedAgentID: nil
        )
        let store = SpyBoardStore()
        let viewModel = KanbanBoardViewModel(tasks: [task], agents: [], boardStore: store)

        let moved = viewModel.moveTask(task.id, to: .inProgress)

        #expect(moved)
        #expect(store.savedSnapshots.count == 1)
        #expect(store.savedSnapshots.last?.tasks.first?.status == .inProgress)
    }

    @Test("loads saved snapshot when creating persistent board")
    func persistentBoardLoadsSnapshot() {
        let persistedTask = WorkTask(
            title: "Loaded task",
            details: "From disk",
            requiredSkills: ["testing"],
            storyPoints: 2,
            status: .review,
            assignedAgentID: nil
        )
        let persistedAgent = AgentProfile(name: "Stored Agent", skills: ["testing"], maxConcurrentTasks: 2)
        let snapshot = KanbanBoardSnapshot(
            tasks: [persistedTask],
            agents: [persistedAgent],
            wipLimits: [.inProgress: 1, .review: 1]
        )
        let store = SpyBoardStore(loadSnapshot: snapshot)

        let viewModel = KanbanBoardViewModel.persistentBoard(boardStore: store)

        #expect(viewModel.tasks.count == 1)
        #expect(viewModel.tasks[0].title == "Loaded task")
        #expect(viewModel.agents[0].name == "Stored Agent")
        #expect(viewModel.wipLimit(for: .inProgress) == 1)
    }

    @Test("creates a new board and switches to it with isolated state")
    func createsBoardAndSwitchesToIsolatedContext() {
        let seedTask = WorkTask(
            title: "Seed task",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 2,
            status: .todo,
            assignedAgentID: nil
        )
        let seedAgent = AgentProfile(name: "Seed Agent", skills: ["swiftui"], maxConcurrentTasks: 2)
        let viewModel = KanbanBoardViewModel(tasks: [seedTask], agents: [seedAgent])

        let created = viewModel.createBoard(name: "Platform Board")

        #expect(created)
        #expect(viewModel.boards.count == 2)
        #expect(viewModel.selectedBoardName == "Platform Board")
        #expect(viewModel.tasks.isEmpty)
        #expect(viewModel.agents.isEmpty)
        #expect(viewModel.wipLimit(for: .inProgress) == 3)
        #expect(viewModel.wipLimit(for: .review) == 2)
    }

    @Test("switching boards restores each board's independent tasks and agents")
    func switchingBoardsRestoresIndependentState() {
        let defaultTask = WorkTask(
            title: "Default task",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 2,
            status: .todo,
            assignedAgentID: nil
        )
        let defaultAgent = AgentProfile(name: "Default Agent", skills: ["swiftui"], maxConcurrentTasks: 2)
        let viewModel = KanbanBoardViewModel(tasks: [defaultTask], agents: [defaultAgent])
        let defaultBoardID = viewModel.selectedBoardID

        _ = viewModel.createBoard(name: "Research Board")
        _ = viewModel.addTask(
            title: "Research task",
            details: "",
            requiredSkillsText: "analysis",
            storyPoints: 1
        )
        _ = viewModel.addAgent(name: "Research Agent", skillsText: "analysis", maxConcurrentTasks: 1)

        let switchedBack = viewModel.switchBoard(to: defaultBoardID)
        #expect(switchedBack)
        #expect(viewModel.selectedBoardID == defaultBoardID)
        #expect(viewModel.tasks.count == 1)
        #expect(viewModel.tasks.first?.title == "Default task")
        #expect(viewModel.agents.count == 1)
        #expect(viewModel.agents.first?.name == "Default Agent")

        let researchBoardID = viewModel.boards.first(where: { $0.name == "Research Board" })?.id
        #expect(researchBoardID != nil)

        if let researchBoardID {
            let switchedToResearch = viewModel.switchBoard(to: researchBoardID)
            #expect(switchedToResearch)
            #expect(viewModel.selectedBoardID == researchBoardID)
            #expect(viewModel.tasks.count == 1)
            #expect(viewModel.tasks.first?.title == "Research task")
            #expect(viewModel.agents.count == 1)
            #expect(viewModel.agents.first?.name == "Research Agent")
        }
    }

    @Test("loads selected board from multi-board snapshot")
    func persistentBoardLoadsSelectedBoardFromMultiBoardSnapshot() {
        let deliveryTask = WorkTask(
            title: "Delivery task",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 2,
            status: .todo,
            assignedAgentID: nil
        )
        let qaTask = WorkTask(
            title: "QA task",
            details: "",
            requiredSkills: ["testing"],
            storyPoints: 1,
            status: .review,
            assignedAgentID: nil
        )
        let deliveryBoard = KanbanBoardRecord(name: "Delivery", tasks: [deliveryTask], agents: [], wipLimits: [.inProgress: 3, .review: 2])
        let qaBoard = KanbanBoardRecord(name: "QA", tasks: [qaTask], agents: [], wipLimits: [.inProgress: 2, .review: 1])
        let snapshot = KanbanBoardSnapshot(
            tasks: deliveryBoard.tasks,
            agents: deliveryBoard.agents,
            wipLimits: deliveryBoard.wipLimits,
            boards: [deliveryBoard, qaBoard],
            selectedBoardID: qaBoard.id
        )
        let store = SpyBoardStore(loadSnapshot: snapshot)

        let viewModel = KanbanBoardViewModel.persistentBoard(boardStore: store)

        #expect(viewModel.boards.count == 2)
        #expect(viewModel.selectedBoardID == qaBoard.id)
        #expect(viewModel.selectedBoardName == "QA")
        #expect(viewModel.tasks.count == 1)
        #expect(viewModel.tasks.first?.title == "QA task")
    }

    @Test("renames selected board and persists updated board metadata")
    func renamesSelectedBoardAndPersists() {
        let store = SpyBoardStore()
        let viewModel = KanbanBoardViewModel(tasks: [], agents: [], boardStore: store)
        _ = viewModel.createBoard(name: "Research Board")
        let selectedBoardID = viewModel.selectedBoardID

        let renamed = viewModel.renameBoard(selectedBoardID, to: "Strategy Board")

        #expect(renamed)
        #expect(viewModel.selectedBoardName == "Strategy Board")
        #expect(viewModel.boards.contains(where: { $0.id == selectedBoardID && $0.name == "Strategy Board" }))
        #expect(store.savedSnapshots.last?.boards?.contains(where: { $0.id == selectedBoardID && $0.name == "Strategy Board" }) == true)
    }

    @Test("rejects board rename when target name already exists")
    func rejectsDuplicateBoardRename() {
        let viewModel = KanbanBoardViewModel(tasks: [], agents: [])
        let defaultBoardID = viewModel.selectedBoardID
        _ = viewModel.createBoard(name: "Research Board")

        let renamed = viewModel.renameBoard(defaultBoardID, to: "research board")

        #expect(!renamed)
        #expect(viewModel.lastBoardMessage == "Board name already exists")
    }

    @Test("removes selected board and switches to remaining board")
    func removesSelectedBoardAndSwitchesContext() {
        let baselineTask = WorkTask(
            title: "Baseline",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 1,
            status: .todo,
            assignedAgentID: nil
        )
        let store = SpyBoardStore()
        let viewModel = KanbanBoardViewModel(tasks: [baselineTask], agents: [], boardStore: store)
        let defaultBoardID = viewModel.selectedBoardID
        _ = viewModel.createBoard(name: "Research Board")
        let researchBoardID = viewModel.selectedBoardID
        _ = viewModel.addTask(
            title: "Research Task",
            details: "",
            requiredSkillsText: "analysis",
            storyPoints: 2
        )

        let removed = viewModel.removeBoard(researchBoardID)

        #expect(removed)
        #expect(viewModel.boards.count == 1)
        #expect(viewModel.selectedBoardID == defaultBoardID)
        #expect(viewModel.tasks.count == 1)
        #expect(viewModel.tasks.first?.title == "Baseline")
        #expect(store.savedSnapshots.last?.boards?.count == 1)
    }

    @Test("prevents removing the last remaining board")
    func preventsRemovingLastBoard() {
        let viewModel = KanbanBoardViewModel(tasks: [], agents: [])

        let removed = viewModel.removeBoard(viewModel.selectedBoardID)

        #expect(!removed)
        #expect(viewModel.boards.count == 1)
        #expect(viewModel.lastBoardMessage == "At least one board is required")
    }

    @Test("duplicates board with copied state and switches context")
    func duplicatesBoardAndSwitchesContext() {
        let baselineTask = WorkTask(
            title: "Baseline",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 2,
            status: .todo,
            assignedAgentID: nil
        )
        let baselineAgent = AgentProfile(name: "Baseline Agent", skills: ["swiftui"], maxConcurrentTasks: 2)
        let store = SpyBoardStore()
        let viewModel = KanbanBoardViewModel(
            tasks: [baselineTask],
            agents: [baselineAgent],
            wipLimits: [.inProgress: 4, .review: 3],
            boardStore: store
        )
        let sourceBoardID = viewModel.selectedBoardID

        let duplicated = viewModel.duplicateBoard(sourceBoardID)

        #expect(duplicated)
        #expect(viewModel.boards.count == 2)
        #expect(viewModel.selectedBoardID != sourceBoardID)
        #expect(viewModel.selectedBoardName == "Default Board Copy")
        #expect(viewModel.tasks.count == 1)
        #expect(viewModel.tasks.first?.title == "Baseline")
        #expect(viewModel.agents.count == 1)
        #expect(viewModel.agents.first?.name == "Baseline Agent")
        #expect(viewModel.wipLimit(for: .inProgress) == 4)
        #expect(store.savedSnapshots.last?.boards?.count == 2)
        #expect(store.savedSnapshots.last?.selectedBoardID == viewModel.selectedBoardID)
    }

    @Test("rejects board duplication when explicit target name already exists")
    func rejectsDuplicateBoardCopyName() {
        let viewModel = KanbanBoardViewModel(tasks: [], agents: [])
        let sourceBoardID = viewModel.selectedBoardID
        _ = viewModel.createBoard(name: "Research Board")

        let duplicated = viewModel.duplicateBoard(sourceBoardID, name: "Research Board")

        #expect(!duplicated)
        #expect(viewModel.lastBoardMessage == "Board name already exists")
    }

    @Test("moves task to another board and persists both board states")
    func movesTaskToAnotherBoardAndPersists() {
        let task = WorkTask(
            title: "Cross board task",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 2,
            status: .todo,
            assignedAgentID: nil
        )
        let store = SpyBoardStore()
        let viewModel = KanbanBoardViewModel(tasks: [task], agents: [], boardStore: store)
        let sourceBoardID = viewModel.selectedBoardID
        _ = viewModel.createBoard(name: "Target Board")
        let targetBoardID = viewModel.selectedBoardID
        _ = viewModel.switchBoard(to: sourceBoardID)

        let moved = viewModel.moveTask(task.id, toBoard: targetBoardID)

        #expect(moved)
        #expect(viewModel.tasks.isEmpty)
        #expect(store.savedSnapshots.last?.boards?.count == 2)

        let switched = viewModel.switchBoard(to: targetBoardID)
        #expect(switched)
        #expect(viewModel.tasks.count == 1)
        #expect(viewModel.tasks.first?.title == "Cross board task")
    }

    @Test("moving task to board without assigned agent unassigns task")
    func movingTaskToBoardWithoutAgentUnassignsTask() {
        let agent = AgentProfile(name: "Source Agent", skills: ["swiftui"], maxConcurrentTasks: 2)
        let task = WorkTask(
            title: "Assigned cross board task",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 2,
            status: .todo,
            assignedAgentID: agent.id
        )
        let viewModel = KanbanBoardViewModel(tasks: [task], agents: [agent])
        let sourceBoardID = viewModel.selectedBoardID
        _ = viewModel.createBoard(name: "Agentless Target")
        let targetBoardID = viewModel.selectedBoardID
        _ = viewModel.switchBoard(to: sourceBoardID)

        let moved = viewModel.moveTask(task.id, toBoard: targetBoardID)

        #expect(moved)
        let switched = viewModel.switchBoard(to: targetBoardID)
        #expect(switched)
        #expect(viewModel.tasks.first?.assignedAgentID == nil)
    }

    @Test("global task search finds tasks across boards with board metadata")
    func globalTaskSearchFindsTasksAcrossBoards() {
        let sourceTask = WorkTask(
            title: "Design Home",
            details: "",
            requiredSkills: ["ui"],
            storyPoints: 2,
            status: .todo,
            assignedAgentID: nil
        )
        let viewModel = KanbanBoardViewModel(tasks: [sourceTask], agents: [])
        _ = viewModel.createBoard(name: "Ops Board")
        _ = viewModel.addTask(
            title: "Incident Response",
            details: "Fix prod issue",
            requiredSkillsText: "ops",
            storyPoints: 3
        )

        let results = viewModel.globalTaskSearchResults(query: "incident")

        #expect(results.count == 1)
        #expect(results.first?.boardName == "Ops Board")
        #expect(results.first?.taskTitle == "Incident Response")
    }

    @Test("open task switches board context and persists selection")
    func openTaskSwitchesBoardContextAndPersists() {
        let defaultTask = WorkTask(
            title: "Default Task",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 1,
            status: .todo,
            assignedAgentID: nil
        )
        let store = SpyBoardStore()
        let viewModel = KanbanBoardViewModel(tasks: [defaultTask], agents: [], boardStore: store)
        let defaultBoardID = viewModel.selectedBoardID
        _ = viewModel.createBoard(name: "Release Board")
        _ = viewModel.addTask(
            title: "Ship Candidate",
            details: "",
            requiredSkillsText: "release",
            storyPoints: 2
        )
        let targetBoardID = viewModel.selectedBoardID
        let targetTaskID = viewModel.tasks.first?.id
        _ = viewModel.switchBoard(to: defaultBoardID)

        #expect(targetTaskID != nil)
        guard let targetTaskID else { return }

        let opened = viewModel.openTask(targetTaskID, in: targetBoardID)

        #expect(opened)
        #expect(viewModel.selectedBoardID == targetBoardID)
        #expect(viewModel.tasks.contains(where: { $0.id == targetTaskID }))
        #expect(store.savedSnapshots.last?.selectedBoardID == targetBoardID)
    }

    @Test("exports workspace snapshot JSON including multi-board metadata")
    func exportsWorkspaceSnapshotJSON() throws {
        let seedTask = WorkTask(
            title: "Seed",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 1,
            status: .todo,
            assignedAgentID: nil
        )
        let viewModel = KanbanBoardViewModel(tasks: [seedTask], agents: [])
        _ = viewModel.createBoard(name: "Ops Board")

        let exported = viewModel.workspaceExportData()

        #expect(exported != nil)
        guard let exported else { return }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let snapshot = try decoder.decode(KanbanBoardSnapshot.self, from: exported)
        #expect(snapshot.boards?.count == 2)
        #expect(snapshot.selectedBoardID == viewModel.selectedBoardID)
    }

    @Test("imports workspace snapshot and persists board selection")
    func importsWorkspaceSnapshotAndPersistsSelection() throws {
        let deliveryTask = WorkTask(
            title: "Delivery",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 2,
            status: .todo,
            assignedAgentID: nil
        )
        let qaTask = WorkTask(
            title: "QA",
            details: "",
            requiredSkills: ["testing"],
            storyPoints: 2,
            status: .review,
            assignedAgentID: nil
        )
        let deliveryBoard = KanbanBoardRecord(name: "Delivery", tasks: [deliveryTask], agents: [], wipLimits: [.inProgress: 3, .review: 2])
        let qaBoard = KanbanBoardRecord(name: "QA", tasks: [qaTask], agents: [], wipLimits: [.inProgress: 2, .review: 1])
        let snapshot = KanbanBoardSnapshot(
            tasks: deliveryBoard.tasks,
            agents: deliveryBoard.agents,
            wipLimits: deliveryBoard.wipLimits,
            boards: [deliveryBoard, qaBoard],
            selectedBoardID: qaBoard.id
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .secondsSince1970
        let data = try encoder.encode(snapshot)

        let store = SpyBoardStore()
        let viewModel = KanbanBoardViewModel(tasks: [], agents: [], boardStore: store)

        let imported = viewModel.importWorkspaceData(data)

        #expect(imported)
        #expect(viewModel.boards.count == 2)
        #expect(viewModel.selectedBoardID == qaBoard.id)
        #expect(viewModel.selectedBoardName == "QA")
        #expect(viewModel.tasks.first?.title == "QA")
        #expect(store.savedSnapshots.last?.selectedBoardID == qaBoard.id)
    }

    @Test("rejects invalid workspace JSON import")
    func rejectsInvalidWorkspaceImport() {
        let viewModel = KanbanBoardViewModel(tasks: [], agents: [])
        let invalidData = Data("not-valid-json".utf8)

        let imported = viewModel.importWorkspaceData(invalidData)

        #expect(!imported)
        #expect(viewModel.lastBoardMessage == "Invalid workspace JSON")
    }

    @Test("file store saves and loads snapshot round trip")
    func fileStoreRoundTrip() throws {
        let directoryURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directoryURL) }
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        let fileURL = directoryURL.appendingPathComponent("kanban-board.json")
        let task = WorkTask(
            title: "Round trip",
            details: "Verify disk persistence",
            requiredSkills: ["swift"],
            storyPoints: 3,
            status: .todo,
            assignedAgentID: nil
        )
        let agent = AgentProfile(name: "Disk Agent", skills: ["swift"], maxConcurrentTasks: 2)
        let snapshot = KanbanBoardSnapshot(
            tasks: [task],
            agents: [agent],
            wipLimits: [.inProgress: 2]
        )

        let store = FileKanbanBoardStore(fileURL: fileURL)
        try store.save(snapshot)

        let loaded = try store.load()
        #expect(loaded?.agents == snapshot.agents)
        #expect(loaded?.wipLimits == snapshot.wipLimits)
        #expect(loaded?.tasks.count == snapshot.tasks.count)

        let loadedTask = loaded?.tasks.first
        let snapshotTask = snapshot.tasks.first
        #expect(loadedTask?.id == snapshotTask?.id)
        #expect(loadedTask?.title == snapshotTask?.title)
        #expect(loadedTask?.details == snapshotTask?.details)
        #expect(loadedTask?.requiredSkills == snapshotTask?.requiredSkills)
        #expect(loadedTask?.storyPoints == snapshotTask?.storyPoints)
        #expect(loadedTask?.status == snapshotTask?.status)
        #expect(loadedTask?.assignedAgentID == snapshotTask?.assignedAgentID)
        #expect(abs((loadedTask?.createdAt.timeIntervalSince(snapshotTask?.createdAt ?? .distantPast) ?? 1)) < 0.01)
    }

    @Test("updates WIP limit and persists new board snapshot")
    func updatesWIPLimitAndPersists() {
        let task = WorkTask(
            title: "Active task",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 2,
            status: .inProgress,
            assignedAgentID: nil
        )
        let store = SpyBoardStore()
        let viewModel = KanbanBoardViewModel(
            tasks: [task],
            agents: [],
            wipLimits: [.inProgress: 3],
            boardStore: store
        )

        let updated = viewModel.updateWIPLimit(for: .inProgress, limit: 4)

        #expect(updated)
        #expect(viewModel.wipLimit(for: .inProgress) == 4)
        #expect(store.savedSnapshots.count == 1)
        #expect(store.savedSnapshots.last?.wipLimits[.inProgress] == 4)
    }

    @Test("rejects WIP limit lower than current task count in that column")
    func rejectsWIPLimitLowerThanCurrentCount() {
        let reviewTask1 = WorkTask(
            title: "Review A",
            details: "",
            requiredSkills: ["testing"],
            storyPoints: 1,
            status: .review,
            assignedAgentID: nil
        )
        let reviewTask2 = WorkTask(
            title: "Review B",
            details: "",
            requiredSkills: ["testing"],
            storyPoints: 1,
            status: .review,
            assignedAgentID: nil
        )
        let store = SpyBoardStore()
        let viewModel = KanbanBoardViewModel(
            tasks: [reviewTask1, reviewTask2],
            agents: [],
            wipLimits: [.review: 3],
            boardStore: store
        )

        let updated = viewModel.updateWIPLimit(for: .review, limit: 1)

        #expect(!updated)
        #expect(viewModel.wipLimit(for: .review) == 3)
        #expect(viewModel.lastBoardMessage == "Cannot set Review WIP below current count (2)")
        #expect(store.savedSnapshots.isEmpty)
    }

    @Test("updates multiple WIP limits atomically and persists once")
    func updatesMultipleWIPLimitsAtomically() {
        let inProgressTask = WorkTask(
            title: "In progress",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 2,
            status: .inProgress,
            assignedAgentID: nil
        )
        let reviewTask = WorkTask(
            title: "Review",
            details: "",
            requiredSkills: ["testing"],
            storyPoints: 1,
            status: .review,
            assignedAgentID: nil
        )
        let store = SpyBoardStore()
        let viewModel = KanbanBoardViewModel(
            tasks: [inProgressTask, reviewTask],
            agents: [],
            wipLimits: [.inProgress: 3, .review: 2],
            boardStore: store
        )

        let updated = viewModel.updateWIPLimits([.inProgress: 4, .review: 5])

        #expect(updated)
        #expect(viewModel.wipLimit(for: .inProgress) == 4)
        #expect(viewModel.wipLimit(for: .review) == 5)
        #expect(store.savedSnapshots.count == 1)
    }

    @Test("does not partially apply WIP changes when one update is invalid")
    func rejectsBatchWIPUpdateWithoutPartialMutation() {
        let reviewTask1 = WorkTask(
            title: "Review 1",
            details: "",
            requiredSkills: ["testing"],
            storyPoints: 1,
            status: .review,
            assignedAgentID: nil
        )
        let reviewTask2 = WorkTask(
            title: "Review 2",
            details: "",
            requiredSkills: ["testing"],
            storyPoints: 1,
            status: .review,
            assignedAgentID: nil
        )
        let store = SpyBoardStore()
        let viewModel = KanbanBoardViewModel(
            tasks: [reviewTask1, reviewTask2],
            agents: [],
            wipLimits: [.inProgress: 3, .review: 3],
            boardStore: store
        )

        let updated = viewModel.updateWIPLimits([.inProgress: 5, .review: 1])

        #expect(!updated)
        #expect(viewModel.wipLimit(for: .inProgress) == 3)
        #expect(viewModel.wipLimit(for: .review) == 3)
        #expect(viewModel.lastBoardMessage == "Cannot set Review WIP below current count (2)")
        #expect(store.savedSnapshots.isEmpty)
    }

    @Test("manually assigns triage task to a valid agent and persists")
    func manuallyAssignsTriageTaskAndPersists() {
        let task = WorkTask(
            title: "Unassigned task",
            details: "Need manual help",
            requiredSkills: ["swiftui"],
            storyPoints: 2,
            status: .todo,
            assignedAgentID: nil
        )
        let unmatchedAgent = AgentProfile(name: "Backend Agent", skills: ["api"], maxConcurrentTasks: 2)
        let triageAgent = AgentProfile(name: "UI Agent", skills: ["swiftui", "ui"], maxConcurrentTasks: 2)
        let store = SpyBoardStore()
        let viewModel = KanbanBoardViewModel(tasks: [task], agents: [unmatchedAgent], boardStore: store)

        viewModel.autoAssignTasks()
        #expect(viewModel.lastUnassignedTaskIDs.contains(task.id))

        viewModel.agents.append(triageAgent)
        let assigned = viewModel.manuallyAssignTask(task.id, to: triageAgent.id)

        #expect(assigned)
        #expect(viewModel.tasks.first?.assignedAgentID == triageAgent.id)
        #expect(!viewModel.lastUnassignedTaskIDs.contains(task.id))
        #expect(viewModel.assignmentReason(for: task.id)?.contains("manual[UI Agent]") == true)
        #expect(store.savedSnapshots.count == 2)
    }

    @Test("rejects manual triage when agent lacks required skills")
    func rejectsManualTriageForSkillMismatch() {
        let task = WorkTask(
            title: "ML task",
            details: "",
            requiredSkills: ["ml"],
            storyPoints: 3,
            status: .todo,
            assignedAgentID: nil
        )
        let agent = AgentProfile(name: "Frontend Agent", skills: ["swiftui"], maxConcurrentTasks: 2)
        let store = SpyBoardStore()
        let viewModel = KanbanBoardViewModel(tasks: [task], agents: [agent], boardStore: store)

        let assigned = viewModel.manuallyAssignTask(task.id, to: agent.id)

        #expect(!assigned)
        #expect(viewModel.tasks.first?.assignedAgentID == nil)
        #expect(viewModel.lastBoardMessage == "Agent Frontend Agent does not match required skills")
        #expect(store.savedSnapshots.isEmpty)
    }

    @Test("rejects manual triage when agent is already at max load")
    func rejectsManualTriageForOverloadedAgent() {
        let overloadedAgent = AgentProfile(name: "Busy Agent", skills: ["swiftui"], maxConcurrentTasks: 1)
        let activeTask = WorkTask(
            title: "Already active",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 2,
            status: .inProgress,
            assignedAgentID: overloadedAgent.id
        )
        let todoTask = WorkTask(
            title: "Need assignment",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 1,
            status: .todo,
            assignedAgentID: nil
        )
        let store = SpyBoardStore()
        let viewModel = KanbanBoardViewModel(
            tasks: [activeTask, todoTask],
            agents: [overloadedAgent],
            boardStore: store
        )

        let assigned = viewModel.manuallyAssignTask(todoTask.id, to: overloadedAgent.id)

        #expect(!assigned)
        #expect(viewModel.tasks.first(where: { $0.id == todoTask.id })?.assignedAgentID == nil)
        #expect(viewModel.lastBoardMessage == "Agent Busy Agent is at max load (1)")
        #expect(store.savedSnapshots.isEmpty)
    }

    @Test("triage candidates include todo tasks that remain unassigned without auto-assign")
    func triageCandidatesIncludePlainUnassignedTodoTasks() {
        let todoUnassigned = WorkTask(
            title: "Unassigned To Do",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 2,
            status: .todo,
            assignedAgentID: nil
        )
        let todoAssigned = WorkTask(
            title: "Assigned To Do",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 1,
            status: .todo,
            assignedAgentID: UUID()
        )
        let reviewUnassigned = WorkTask(
            title: "Review task",
            details: "",
            requiredSkills: ["testing"],
            storyPoints: 3,
            status: .review,
            assignedAgentID: nil
        )
        let viewModel = KanbanBoardViewModel(tasks: [todoUnassigned, todoAssigned, reviewUnassigned], agents: [])

        let candidates = viewModel.triageCandidates()

        #expect(candidates.count == 1)
        #expect(candidates.first?.id == todoUnassigned.id)
    }

    @Test("assignable agents for triage only include skill-matched agents with remaining capacity")
    func assignableAgentsFilterBySkillAndCapacity() {
        let task = WorkTask(
            title: "Triage target",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 2,
            status: .todo,
            assignedAgentID: nil
        )
        let qualifiedAgent = AgentProfile(name: "Qualified", skills: ["swiftui"], maxConcurrentTasks: 2)
        let overloadedAgent = AgentProfile(name: "Overloaded", skills: ["swiftui"], maxConcurrentTasks: 1)
        let skillMismatchAgent = AgentProfile(name: "Mismatch", skills: ["backend"], maxConcurrentTasks: 3)
        let activeTask = WorkTask(
            title: "Existing load",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 1,
            status: .inProgress,
            assignedAgentID: overloadedAgent.id
        )
        let viewModel = KanbanBoardViewModel(
            tasks: [task, activeTask],
            agents: [qualifiedAgent, overloadedAgent, skillMismatchAgent]
        )

        let eligible = viewModel.assignableAgents(for: task.id)

        #expect(eligible.count == 1)
        #expect(eligible.first?.id == qualifiedAgent.id)
    }

    @Test("resolves triage assignments by keeping valid selections and dropping stale task ids")
    func resolvesTriageAssignmentsKeepingValidSelections() {
        let firstTask = WorkTask(
            title: "Task A",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 2,
            status: .todo,
            assignedAgentID: nil
        )
        let secondTask = WorkTask(
            title: "Task B",
            details: "",
            requiredSkills: ["testing"],
            storyPoints: 1,
            status: .todo,
            assignedAgentID: nil
        )
        let uiAgent = AgentProfile(name: "UI Agent", skills: ["swiftui"], maxConcurrentTasks: 2)
        let qaAgent = AgentProfile(name: "QA Agent", skills: ["testing"], maxConcurrentTasks: 2)
        let viewModel = KanbanBoardViewModel(tasks: [firstTask, secondTask], agents: [uiAgent, qaAgent])

        let staleTaskID = UUID()
        let resolved = viewModel.resolvedTriageAssignments(existing: [
            firstTask.id: uiAgent.id,
            staleTaskID: qaAgent.id
        ])

        #expect(resolved[firstTask.id] == uiAgent.id)
        #expect(resolved[secondTask.id] == qaAgent.id)
        #expect(resolved[staleTaskID] == nil)
    }

    @Test("resolves triage assignments by replacing invalid selected agent with fallback")
    func resolvesTriageAssignmentsReplacingInvalidSelection() {
        let task = WorkTask(
            title: "Task A",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 2,
            status: .todo,
            assignedAgentID: nil
        )
        let uiAgent = AgentProfile(name: "UI Agent", skills: ["swiftui"], maxConcurrentTasks: 2)
        let backendAgent = AgentProfile(name: "Backend Agent", skills: ["backend"], maxConcurrentTasks: 2)
        let viewModel = KanbanBoardViewModel(tasks: [task], agents: [uiAgent, backendAgent])

        let resolved = viewModel.resolvedTriageAssignments(existing: [task.id: backendAgent.id])

        #expect(resolved[task.id] == uiAgent.id)
    }

    @Test("resolves triage assignments with capacity-aware fallback across multiple tasks")
    func resolvesTriageAssignmentsWithCapacityAwareFallback() {
        let highPriorityTask = WorkTask(
            title: "Task High",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 3,
            status: .todo,
            assignedAgentID: nil
        )
        let lowPriorityTask = WorkTask(
            title: "Task Low",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 1,
            status: .todo,
            assignedAgentID: nil
        )
        let alphaAgent = AgentProfile(name: "Alpha Agent", skills: ["swiftui"], maxConcurrentTasks: 1)
        let betaAgent = AgentProfile(name: "Beta Agent", skills: ["swiftui"], maxConcurrentTasks: 1)
        let viewModel = KanbanBoardViewModel(tasks: [highPriorityTask, lowPriorityTask], agents: [alphaAgent, betaAgent])

        let resolved = viewModel.resolvedTriageAssignments(existing: [
            highPriorityTask.id: alphaAgent.id,
            lowPriorityTask.id: alphaAgent.id
        ])

        #expect(resolved[highPriorityTask.id] == alphaAgent.id)
        #expect(resolved[lowPriorityTask.id] == betaAgent.id)
    }

    @Test("bulk triage assignable count follows capacity-aware selection planning")
    func bulkTriageAssignableCountFollowsCapacityAwarePlan() {
        let highPriorityTask = WorkTask(
            title: "Task High",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 3,
            status: .todo,
            assignedAgentID: nil
        )
        let lowPriorityTask = WorkTask(
            title: "Task Low",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 1,
            status: .todo,
            assignedAgentID: nil
        )
        let alphaAgent = AgentProfile(name: "Alpha Agent", skills: ["swiftui"], maxConcurrentTasks: 1)
        let betaAgent = AgentProfile(name: "Beta Agent", skills: ["swiftui"], maxConcurrentTasks: 1)
        let viewModel = KanbanBoardViewModel(tasks: [highPriorityTask, lowPriorityTask], agents: [alphaAgent, betaAgent])

        let count = viewModel.bulkAssignableTriageTaskCount(using: [
            highPriorityTask.id: alphaAgent.id,
            lowPriorityTask.id: alphaAgent.id
        ])

        #expect(count == 2)
    }

    @Test("bulk triage plan matches capacity-aware fallback decisions")
    func bulkTriagePlanMatchesCapacityAwareFallback() {
        let highPriorityTask = WorkTask(
            title: "Task High",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 3,
            status: .todo,
            assignedAgentID: nil
        )
        let lowPriorityTask = WorkTask(
            title: "Task Low",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 1,
            status: .todo,
            assignedAgentID: nil
        )
        let alphaAgent = AgentProfile(name: "Alpha Agent", skills: ["swiftui"], maxConcurrentTasks: 1)
        let betaAgent = AgentProfile(name: "Beta Agent", skills: ["swiftui"], maxConcurrentTasks: 1)
        let viewModel = KanbanBoardViewModel(tasks: [highPriorityTask, lowPriorityTask], agents: [alphaAgent, betaAgent])

        let plan = viewModel.bulkTriageAssignmentPlan(using: [
            highPriorityTask.id: alphaAgent.id,
            lowPriorityTask.id: alphaAgent.id
        ])

        #expect(plan[highPriorityTask.id] == alphaAgent.id)
        #expect(plan[lowPriorityTask.id] == betaAgent.id)
        #expect(plan.count == 2)
    }

    @Test("bulk triage assignable count matches executable assignment plan size")
    func bulkTriageAssignableCountMatchesPlanSize() {
        let firstTask = WorkTask(
            title: "Task A",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 2,
            status: .todo,
            assignedAgentID: nil
        )
        let secondTask = WorkTask(
            title: "Task B",
            details: "",
            requiredSkills: ["ml"],
            storyPoints: 1,
            status: .todo,
            assignedAgentID: nil
        )
        let uiAgent = AgentProfile(name: "UI Agent", skills: ["swiftui"], maxConcurrentTasks: 2)
        let viewModel = KanbanBoardViewModel(tasks: [firstTask, secondTask], agents: [uiAgent])

        let count = viewModel.bulkAssignableTriageTaskCount()
        let plan = viewModel.bulkTriageAssignmentPlan()

        #expect(count == plan.count)
        #expect(count == 1)
    }

    @Test("bulk triage unassignable count tracks tasks without current assignment plan")
    func bulkTriageUnassignableCountTracksPlanGap() {
        let firstTask = WorkTask(
            title: "Task A",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 2,
            status: .todo,
            assignedAgentID: nil
        )
        let secondTask = WorkTask(
            title: "Task B",
            details: "",
            requiredSkills: ["ml"],
            storyPoints: 1,
            status: .todo,
            assignedAgentID: nil
        )
        let uiAgent = AgentProfile(name: "UI Agent", skills: ["swiftui"], maxConcurrentTasks: 2)
        let viewModel = KanbanBoardViewModel(tasks: [firstTask, secondTask], agents: [uiAgent])

        let assignable = viewModel.bulkAssignableTriageTaskCount()
        let unassignable = viewModel.bulkUnassignableTriageTaskCount()

        #expect(assignable == 1)
        #expect(unassignable == 1)
        #expect(assignable + unassignable == viewModel.triageCandidates().count)
    }

    @Test("bulk triage assignable count is a read-only preview")
    func bulkTriageAssignableCountDoesNotMutateBoardState() {
        let task = WorkTask(
            title: "ML task",
            details: "",
            requiredSkills: ["ml"],
            storyPoints: 3,
            status: .todo,
            assignedAgentID: nil
        )
        let agent = AgentProfile(name: "UI Agent", skills: ["swiftui"], maxConcurrentTasks: 2)
        let viewModel = KanbanBoardViewModel(tasks: [task], agents: [agent])

        let count = viewModel.bulkAssignableTriageTaskCount()

        #expect(count == 0)
        #expect(viewModel.tasks.count == 1)
        #expect(viewModel.tasks.first?.id == task.id)
        #expect(viewModel.tasks.first?.assignedAgentID == nil)
    }

    @Test("bulk triage assigns all currently eligible unassigned todo tasks")
    func bulkTriageAssignsEligibleTasks() {
        let uiTask = WorkTask(
            title: "UI task",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 2,
            status: .todo,
            assignedAgentID: nil
        )
        let testingTask = WorkTask(
            title: "Testing task",
            details: "",
            requiredSkills: ["testing"],
            storyPoints: 1,
            status: .todo,
            assignedAgentID: nil
        )
        let uiAgent = AgentProfile(name: "UI Agent", skills: ["swiftui"], maxConcurrentTasks: 2)
        let store = SpyBoardStore()
        let viewModel = KanbanBoardViewModel(
            tasks: [uiTask, testingTask],
            agents: [uiAgent],
            boardStore: store
        )

        let assignedCount = viewModel.bulkAssignTriageTasks()

        #expect(assignedCount == 1)
        #expect(viewModel.tasks.first(where: { $0.id == uiTask.id })?.assignedAgentID == uiAgent.id)
        #expect(viewModel.tasks.first(where: { $0.id == testingTask.id })?.assignedAgentID == nil)
        #expect(viewModel.triageCandidates().count == 1)
        #expect(store.savedSnapshots.count == 1)
    }

    @Test("bulk triage reports partial assignment when some tasks still need manual triage")
    func bulkTriageReportsPartialAssignmentSummary() {
        let uiTask = WorkTask(
            title: "UI task",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 2,
            status: .todo,
            assignedAgentID: nil
        )
        let testingTask = WorkTask(
            title: "Testing task",
            details: "",
            requiredSkills: ["testing"],
            storyPoints: 1,
            status: .todo,
            assignedAgentID: nil
        )
        let uiAgent = AgentProfile(name: "UI Agent", skills: ["swiftui"], maxConcurrentTasks: 2)
        let viewModel = KanbanBoardViewModel(tasks: [uiTask, testingTask], agents: [uiAgent])

        let assignedCount = viewModel.bulkAssignTriageTasks()

        #expect(assignedCount == 1)
        #expect(viewModel.lastBoardMessage == "Assigned 1 triage task. 1 task still needs manual attention")
        #expect(viewModel.lastBoardMessageSeverity?.rawValue == "warning")
    }

    @Test("bulk triage clears summary message when all triage tasks are assigned")
    func bulkTriageClearsSummaryMessageWhenFullyAssigned() {
        let firstTask = WorkTask(
            title: "Task A",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 2,
            status: .todo,
            assignedAgentID: nil
        )
        let secondTask = WorkTask(
            title: "Task B",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 1,
            status: .todo,
            assignedAgentID: nil
        )
        let uiAgent = AgentProfile(name: "UI Agent", skills: ["swiftui"], maxConcurrentTasks: 2)
        let viewModel = KanbanBoardViewModel(tasks: [firstTask, secondTask], agents: [uiAgent])

        let assignedCount = viewModel.bulkAssignTriageTasks()

        #expect(assignedCount == 2)
        #expect(viewModel.lastBoardMessage == nil)
        #expect(viewModel.lastBoardMessageSeverity == nil)
    }

    @Test("bulk triage prefers selected agents from manual triage choices")
    func bulkTriagePrefersSelectedAgents() {
        let firstTask = WorkTask(
            title: "Task A",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 2,
            status: .todo,
            assignedAgentID: nil
        )
        let secondTask = WorkTask(
            title: "Task B",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 2,
            status: .todo,
            assignedAgentID: nil
        )
        let alphaAgent = AgentProfile(name: "Alpha Agent", skills: ["swiftui"], maxConcurrentTasks: 1)
        let betaAgent = AgentProfile(name: "Beta Agent", skills: ["swiftui"], maxConcurrentTasks: 1)
        let store = SpyBoardStore()
        let viewModel = KanbanBoardViewModel(
            tasks: [firstTask, secondTask],
            agents: [alphaAgent, betaAgent],
            boardStore: store
        )

        let assignedCount = viewModel.bulkAssignTriageTasks(using: [
            firstTask.id: betaAgent.id,
            secondTask.id: alphaAgent.id
        ])

        #expect(assignedCount == 2)
        #expect(viewModel.tasks.first(where: { $0.id == firstTask.id })?.assignedAgentID == betaAgent.id)
        #expect(viewModel.tasks.first(where: { $0.id == secondTask.id })?.assignedAgentID == alphaAgent.id)
        #expect(store.savedSnapshots.count == 1)
    }

    @Test("bulk triage falls back when selected agent is no longer eligible")
    func bulkTriageFallsBackWhenSelectionIsInvalid() {
        let firstTask = WorkTask(
            title: "Task A",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 3,
            status: .todo,
            assignedAgentID: nil
        )
        let secondTask = WorkTask(
            title: "Task B",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 1,
            status: .todo,
            assignedAgentID: nil
        )
        let alphaAgent = AgentProfile(name: "Alpha Agent", skills: ["swiftui"], maxConcurrentTasks: 1)
        let betaAgent = AgentProfile(name: "Beta Agent", skills: ["swiftui"], maxConcurrentTasks: 1)
        let store = SpyBoardStore()
        let viewModel = KanbanBoardViewModel(
            tasks: [firstTask, secondTask],
            agents: [alphaAgent, betaAgent],
            boardStore: store
        )

        let assignedCount = viewModel.bulkAssignTriageTasks(using: [
            firstTask.id: alphaAgent.id,
            secondTask.id: alphaAgent.id
        ])

        #expect(assignedCount == 2)
        #expect(viewModel.tasks.first(where: { $0.id == firstTask.id })?.assignedAgentID == alphaAgent.id)
        #expect(viewModel.tasks.first(where: { $0.id == secondTask.id })?.assignedAgentID == betaAgent.id)
        #expect(store.savedSnapshots.count == 1)
    }

    @Test("bulk triage reports when no eligible assignment can be made")
    func bulkTriageReportsNoEligibleAssignments() {
        let task = WorkTask(
            title: "ML task",
            details: "",
            requiredSkills: ["ml"],
            storyPoints: 3,
            status: .todo,
            assignedAgentID: nil
        )
        let agent = AgentProfile(name: "UI Agent", skills: ["swiftui"], maxConcurrentTasks: 2)
        let store = SpyBoardStore()
        let viewModel = KanbanBoardViewModel(tasks: [task], agents: [agent], boardStore: store)

        let assignedCount = viewModel.bulkAssignTriageTasks()

        #expect(assignedCount == 0)
        #expect(viewModel.lastBoardMessage == "No eligible agents available for pending triage tasks")
        #expect(viewModel.lastBoardMessageSeverity?.rawValue == "warning")
        #expect(store.savedSnapshots.isEmpty)
    }

    @Test("adds task with normalized skills and persists snapshot")
    func addsTaskAndPersists() {
        let store = SpyBoardStore()
        let viewModel = KanbanBoardViewModel(tasks: [], agents: [], boardStore: store)

        let added = viewModel.addTask(
            title: "Implement Search",
            details: "Add board filtering",
            requiredSkillsText: "swiftui, ui,  ",
            storyPoints: 3
        )

        #expect(added)
        #expect(viewModel.tasks.count == 1)
        #expect(viewModel.tasks[0].title == "Implement Search")
        #expect(viewModel.tasks[0].requiredSkills == Set(["swiftui", "ui"]))
        #expect(store.savedSnapshots.count == 1)
    }

    @Test("rejects adding task with empty title")
    func rejectsAddingTaskWithEmptyTitle() {
        let store = SpyBoardStore()
        let viewModel = KanbanBoardViewModel(tasks: [], agents: [], boardStore: store)

        let added = viewModel.addTask(
            title: "   ",
            details: "No title",
            requiredSkillsText: "swiftui",
            storyPoints: 2
        )

        #expect(!added)
        #expect(viewModel.tasks.isEmpty)
        #expect(viewModel.lastBoardMessage == "Task title is required")
        #expect(store.savedSnapshots.isEmpty)
    }

    @Test("updates task fields and persists snapshot")
    func updatesTaskAndPersists() {
        let task = WorkTask(
            title: "Build board",
            details: "Initial details",
            requiredSkills: ["swiftui"],
            storyPoints: 2,
            status: .todo,
            assignedAgentID: nil
        )
        let store = SpyBoardStore()
        let viewModel = KanbanBoardViewModel(tasks: [task], agents: [], boardStore: store)

        let updated = viewModel.updateTask(
            task.id,
            title: "Build kanban board",
            details: "Updated details",
            requiredSkillsText: "swiftui, ui",
            storyPoints: 5
        )

        #expect(updated)
        #expect(viewModel.tasks.count == 1)
        #expect(viewModel.tasks[0].title == "Build kanban board")
        #expect(viewModel.tasks[0].details == "Updated details")
        #expect(viewModel.tasks[0].requiredSkills == Set(["swiftui", "ui"]))
        #expect(viewModel.tasks[0].storyPoints == 5)
        #expect(store.savedSnapshots.count == 1)
    }

    @Test("rejects updating task with empty title")
    func rejectsUpdatingTaskWithEmptyTitle() {
        let task = WorkTask(
            title: "Build board",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 2,
            status: .todo,
            assignedAgentID: nil
        )
        let store = SpyBoardStore()
        let viewModel = KanbanBoardViewModel(tasks: [task], agents: [], boardStore: store)

        let updated = viewModel.updateTask(
            task.id,
            title: "   ",
            details: "",
            requiredSkillsText: "swiftui",
            storyPoints: 2
        )

        #expect(!updated)
        #expect(viewModel.tasks[0].title == "Build board")
        #expect(viewModel.lastBoardMessage == "Task title is required")
        #expect(store.savedSnapshots.isEmpty)
    }

    @Test("removes task and persists snapshot")
    func removesTaskAndPersists() {
        let task = WorkTask(
            title: "Build board",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 2,
            status: .todo,
            assignedAgentID: nil
        )
        let store = SpyBoardStore()
        let viewModel = KanbanBoardViewModel(tasks: [task], agents: [], boardStore: store)

        let removed = viewModel.removeTask(task.id)

        #expect(removed)
        #expect(viewModel.tasks.isEmpty)
        #expect(store.savedSnapshots.count == 1)
    }

    @Test("removing unknown task returns false and does not persist")
    func rejectsRemovingUnknownTask() {
        let task = WorkTask(
            title: "Build board",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 2,
            status: .todo,
            assignedAgentID: nil
        )
        let store = SpyBoardStore()
        let viewModel = KanbanBoardViewModel(tasks: [task], agents: [], boardStore: store)

        let removed = viewModel.removeTask(UUID())

        #expect(!removed)
        #expect(viewModel.tasks.count == 1)
        #expect(store.savedSnapshots.isEmpty)
    }

    @Test("unassigns task and persists snapshot")
    func unassignsTaskAndPersists() {
        let agent = AgentProfile(name: "UI Agent", skills: ["swiftui"], maxConcurrentTasks: 2)
        let task = WorkTask(
            title: "Build board",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 2,
            status: .todo,
            assignedAgentID: agent.id
        )
        let store = SpyBoardStore()
        let viewModel = KanbanBoardViewModel(tasks: [task], agents: [agent], boardStore: store)

        let unassigned = viewModel.unassignTask(task.id)

        #expect(unassigned)
        #expect(viewModel.tasks[0].assignedAgentID == nil)
        #expect(viewModel.assignmentReason(for: task.id) == nil)
        #expect(viewModel.triageCandidates().contains(where: { $0.id == task.id }))
        #expect(store.savedSnapshots.count == 1)
    }

    @Test("rejects unassigning task that is already unassigned")
    func rejectsUnassigningAlreadyUnassignedTask() {
        let task = WorkTask(
            title: "Build board",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 2,
            status: .todo,
            assignedAgentID: nil
        )
        let store = SpyBoardStore()
        let viewModel = KanbanBoardViewModel(tasks: [task], agents: [], boardStore: store)

        let unassigned = viewModel.unassignTask(task.id)

        #expect(!unassigned)
        #expect(viewModel.lastBoardMessage == "Task is already unassigned")
        #expect(store.savedSnapshots.isEmpty)
    }

    @Test("clears done tasks and persists snapshot once")
    func clearsDoneTasksAndPersists() {
        let doneA = WorkTask(
            title: "Ship v1",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 2,
            status: .done,
            assignedAgentID: nil
        )
        let doneB = WorkTask(
            title: "Close sprint",
            details: "",
            requiredSkills: ["testing"],
            storyPoints: 1,
            status: .done,
            assignedAgentID: nil
        )
        let todo = WorkTask(
            title: "Next task",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 3,
            status: .todo,
            assignedAgentID: nil
        )
        let store = SpyBoardStore()
        let viewModel = KanbanBoardViewModel(tasks: [doneA, todo, doneB], agents: [], boardStore: store)

        let removedCount = viewModel.clearDoneTasks()

        #expect(removedCount == 2)
        #expect(viewModel.tasks.count == 1)
        #expect(viewModel.tasks.first?.id == todo.id)
        #expect(store.savedSnapshots.count == 1)
    }

    @Test("clear done tasks reports when there is nothing to clear")
    func clearDoneTasksNoopWithoutDoneTasks() {
        let todo = WorkTask(
            title: "Next task",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 3,
            status: .todo,
            assignedAgentID: nil
        )
        let store = SpyBoardStore()
        let viewModel = KanbanBoardViewModel(tasks: [todo], agents: [], boardStore: store)

        let removedCount = viewModel.clearDoneTasks()

        #expect(removedCount == 0)
        #expect(viewModel.lastBoardMessage == "No done tasks to archive")
        #expect(viewModel.lastBoardMessageSeverity?.rawValue == "warning")
        #expect(store.savedSnapshots.isEmpty)
    }

    @Test("rebalances overloaded todo assignments and persists once")
    func rebalancesOverloadedTodoAssignments() {
        let overloaded = AgentProfile(name: "A Agent", skills: ["swiftui"], maxConcurrentTasks: 2)
        let available = AgentProfile(name: "B Agent", skills: ["swiftui"], maxConcurrentTasks: 3)
        let taskA = WorkTask(
            title: "Task A",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 2,
            status: .todo,
            assignedAgentID: overloaded.id
        )
        let taskB = WorkTask(
            title: "Task B",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 1,
            status: .todo,
            assignedAgentID: overloaded.id
        )
        let taskC = WorkTask(
            title: "Task C",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 3,
            status: .todo,
            assignedAgentID: overloaded.id
        )
        let store = SpyBoardStore()
        let viewModel = KanbanBoardViewModel(
            tasks: [taskA, taskB, taskC],
            agents: [overloaded, available],
            boardStore: store
        )

        let movedCount = viewModel.rebalanceTodoAssignments()

        #expect(movedCount == 1)
        #expect(viewModel.activeTaskCount(for: overloaded.id) == 2)
        #expect(viewModel.activeTaskCount(for: available.id) == 1)
        #expect(store.savedSnapshots.count == 1)
    }

    @Test("rebalance does not move in-progress assignments")
    func rebalanceDoesNotMoveInProgressAssignments() {
        let overloaded = AgentProfile(name: "A Agent", skills: ["swiftui"], maxConcurrentTasks: 1)
        let available = AgentProfile(name: "B Agent", skills: ["swiftui"], maxConcurrentTasks: 3)
        let inProgress = WorkTask(
            title: "In Progress",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 2,
            status: .inProgress,
            assignedAgentID: overloaded.id
        )
        let store = SpyBoardStore()
        let viewModel = KanbanBoardViewModel(
            tasks: [inProgress],
            agents: [overloaded, available],
            boardStore: store
        )

        let movedCount = viewModel.rebalanceTodoAssignments()

        #expect(movedCount == 0)
        #expect(viewModel.tasks.first?.assignedAgentID == overloaded.id)
        #expect(viewModel.lastBoardMessage == "No todo rebalancing needed")
        #expect(viewModel.lastBoardMessageSeverity?.rawValue == "warning")
        #expect(store.savedSnapshots.isEmpty)
    }

    @Test("unassigns all todo tasks for a specific agent")
    func unassignsAgentTodoTasks() {
        let agent = AgentProfile(name: "UI Agent", skills: ["swiftui"], maxConcurrentTasks: 3)
        let todoA = WorkTask(
            title: "Todo A",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 1,
            status: .todo,
            assignedAgentID: agent.id
        )
        let todoB = WorkTask(
            title: "Todo B",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 2,
            status: .todo,
            assignedAgentID: agent.id
        )
        let inProgress = WorkTask(
            title: "In Progress",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 3,
            status: .inProgress,
            assignedAgentID: agent.id
        )
        let store = SpyBoardStore()
        let viewModel = KanbanBoardViewModel(tasks: [todoA, todoB, inProgress], agents: [agent], boardStore: store)

        let count = viewModel.unassignTodoTasks(for: agent.id)

        #expect(count == 2)
        #expect(viewModel.tasks.first(where: { $0.id == todoA.id })?.assignedAgentID == nil)
        #expect(viewModel.tasks.first(where: { $0.id == todoB.id })?.assignedAgentID == nil)
        #expect(viewModel.tasks.first(where: { $0.id == inProgress.id })?.assignedAgentID == agent.id)
        #expect(store.savedSnapshots.count == 1)
    }

    @Test("unassign agent todo tasks reports when nothing can be unassigned")
    func unassignAgentTodoTasksNoop() {
        let agent = AgentProfile(name: "UI Agent", skills: ["swiftui"], maxConcurrentTasks: 3)
        let inProgress = WorkTask(
            title: "In Progress",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 3,
            status: .inProgress,
            assignedAgentID: agent.id
        )
        let store = SpyBoardStore()
        let viewModel = KanbanBoardViewModel(tasks: [inProgress], agents: [agent], boardStore: store)

        let count = viewModel.unassignTodoTasks(for: agent.id)

        #expect(count == 0)
        #expect(viewModel.lastBoardMessage == "No todo tasks assigned to selected agent")
        #expect(viewModel.lastBoardMessageSeverity?.rawValue == "warning")
        #expect(store.savedSnapshots.isEmpty)
    }

    @Test("updating task skills can unassign incompatible agent")
    func updateTaskUnassignsIncompatibleAgent() {
        let agent = AgentProfile(name: "UI Agent", skills: ["swiftui"], maxConcurrentTasks: 2)
        let task = WorkTask(
            title: "Build board",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 2,
            status: .todo,
            assignedAgentID: agent.id
        )
        let store = SpyBoardStore()
        let viewModel = KanbanBoardViewModel(tasks: [task], agents: [agent], boardStore: store)

        let updated = viewModel.updateTask(
            task.id,
            title: "Build board",
            details: "",
            requiredSkillsText: "backend",
            storyPoints: 2
        )

        #expect(updated)
        #expect(viewModel.tasks[0].assignedAgentID == nil)
        #expect(viewModel.assignmentReason(for: task.id) == nil)
        #expect(viewModel.triageCandidates().contains(where: { $0.id == task.id }))
        #expect(store.savedSnapshots.count == 1)
    }

    @Test("adds agent with parsed skills and persists board snapshot")
    func addsAgentAndPersists() {
        let store = SpyBoardStore()
        let viewModel = KanbanBoardViewModel(tasks: [], agents: [], boardStore: store)

        let added = viewModel.addAgent(
            name: "Platform Agent",
            skillsText: "api, db, swiftui",
            maxConcurrentTasks: 4
        )

        #expect(added)
        #expect(viewModel.agents.count == 1)
        #expect(viewModel.agents[0].name == "Platform Agent")
        #expect(viewModel.agents[0].skills == Set(["api", "db", "swiftui"]))
        #expect(viewModel.agents[0].maxConcurrentTasks == 4)
        #expect(store.savedSnapshots.count == 1)
        #expect(store.savedSnapshots.last?.agents.count == 1)
    }

    @Test("rejects adding agent with empty name")
    func rejectsAgentWithEmptyName() {
        let store = SpyBoardStore()
        let viewModel = KanbanBoardViewModel(tasks: [], agents: [], boardStore: store)

        let added = viewModel.addAgent(
            name: "   ",
            skillsText: "swiftui",
            maxConcurrentTasks: 2
        )

        #expect(!added)
        #expect(viewModel.agents.isEmpty)
        #expect(viewModel.lastBoardMessage == "Agent name is required")
        #expect(store.savedSnapshots.isEmpty)
    }

    @Test("updates agent profile and persists snapshot")
    func updatesAgentProfileAndPersists() {
        let agent = AgentProfile(name: "UI Agent", skills: ["swiftui"], maxConcurrentTasks: 2)
        let store = SpyBoardStore()
        let viewModel = KanbanBoardViewModel(tasks: [], agents: [agent], boardStore: store)

        let updated = viewModel.updateAgent(
            agent.id,
            name: "Platform Agent",
            skillsText: "api, db, swiftui",
            maxConcurrentTasks: 4
        )

        #expect(updated)
        #expect(viewModel.agents.count == 1)
        #expect(viewModel.agents[0].name == "Platform Agent")
        #expect(viewModel.agents[0].skills == Set(["api", "db", "swiftui"]))
        #expect(viewModel.agents[0].maxConcurrentTasks == 4)
        #expect(store.savedSnapshots.count == 1)
    }

    @Test("updating agent skills can unassign incompatible todo tasks")
    func updateAgentUnassignsIncompatibleTodoTasks() {
        let agent = AgentProfile(name: "UI Agent", skills: ["swiftui", "ui"], maxConcurrentTasks: 2)
        let task = WorkTask(
            title: "Build board",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 2,
            status: .todo,
            assignedAgentID: agent.id
        )
        let store = SpyBoardStore()
        let viewModel = KanbanBoardViewModel(tasks: [task], agents: [agent], boardStore: store)

        let updated = viewModel.updateAgent(
            agent.id,
            name: "UI Agent",
            skillsText: "backend",
            maxConcurrentTasks: 2
        )

        #expect(updated)
        #expect(viewModel.tasks[0].assignedAgentID == nil)
        #expect(viewModel.assignmentReason(for: task.id) == nil)
        #expect(viewModel.triageCandidates().contains(where: { $0.id == task.id }))
        #expect(store.savedSnapshots.count == 1)
    }

    @Test("rejects updating agent when name is empty")
    func rejectsUpdatingAgentWithEmptyName() {
        let agent = AgentProfile(name: "UI Agent", skills: ["swiftui"], maxConcurrentTasks: 2)
        let store = SpyBoardStore()
        let viewModel = KanbanBoardViewModel(tasks: [], agents: [agent], boardStore: store)

        let updated = viewModel.updateAgent(
            agent.id,
            name: "  ",
            skillsText: "swiftui",
            maxConcurrentTasks: 2
        )

        #expect(!updated)
        #expect(viewModel.agents[0].name == "UI Agent")
        #expect(viewModel.lastBoardMessage == "Agent name is required")
        #expect(store.savedSnapshots.isEmpty)
    }

    @Test("rejects reducing agent capacity below current active load")
    func rejectsReducingAgentCapacityBelowLoad() {
        let agent = AgentProfile(name: "UI Agent", skills: ["swiftui"], maxConcurrentTasks: 3)
        let activeA = WorkTask(
            title: "Task A",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 2,
            status: .inProgress,
            assignedAgentID: agent.id
        )
        let activeB = WorkTask(
            title: "Task B",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 1,
            status: .review,
            assignedAgentID: agent.id
        )
        let store = SpyBoardStore()
        let viewModel = KanbanBoardViewModel(tasks: [activeA, activeB], agents: [agent], boardStore: store)

        let updated = viewModel.updateAgent(
            agent.id,
            name: "UI Agent",
            skillsText: "swiftui",
            maxConcurrentTasks: 1
        )

        #expect(!updated)
        #expect(viewModel.agents[0].maxConcurrentTasks == 3)
        #expect(viewModel.lastBoardMessage == "Cannot set capacity below current load (2)")
        #expect(store.savedSnapshots.isEmpty)
    }

    @Test("newly added agent participates in auto assignment")
    func addedAgentCanReceiveAutoAssignedTask() {
        let task = WorkTask(
            title: "Build board",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 3,
            status: .todo,
            assignedAgentID: nil
        )
        let viewModel = KanbanBoardViewModel(tasks: [task], agents: [])
        _ = viewModel.addAgent(name: "UI Agent", skillsText: "swiftui, ui", maxConcurrentTasks: 2)

        viewModel.autoAssignTasks()

        #expect(viewModel.tasks.first?.assignedAgentID == viewModel.agents.first?.id)
    }

    @Test("removing agent unassigns their tasks and persists snapshot")
    func removesAgentUnassignsTasksAndPersists() {
        let agent = AgentProfile(name: "UI Agent", skills: ["swiftui"], maxConcurrentTasks: 2)
        let ownedTask = WorkTask(
            title: "Assigned work",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 2,
            status: .todo,
            assignedAgentID: agent.id
        )
        let store = SpyBoardStore()
        let viewModel = KanbanBoardViewModel(tasks: [ownedTask], agents: [agent], boardStore: store)

        let removed = viewModel.removeAgent(agent.id)

        #expect(removed)
        #expect(viewModel.agents.isEmpty)
        #expect(viewModel.tasks.first?.assignedAgentID == nil)
        #expect(viewModel.triageCandidates().count == 1)
        #expect(store.savedSnapshots.count == 1)
    }

    @Test("removing unknown agent returns false and does not persist")
    func rejectsRemovingUnknownAgent() {
        let agent = AgentProfile(name: "UI Agent", skills: ["swiftui"], maxConcurrentTasks: 2)
        let store = SpyBoardStore()
        let viewModel = KanbanBoardViewModel(tasks: [], agents: [agent], boardStore: store)

        let removed = viewModel.removeAgent(UUID())

        #expect(!removed)
        #expect(viewModel.agents.count == 1)
        #expect(store.savedSnapshots.isEmpty)
    }
}

private final class SpyBoardStore: KanbanBoardStore {
    private let loadSnapshot: KanbanBoardSnapshot?
    private(set) var savedSnapshots: [KanbanBoardSnapshot] = []

    init(loadSnapshot: KanbanBoardSnapshot? = nil) {
        self.loadSnapshot = loadSnapshot
    }

    func load() throws -> KanbanBoardSnapshot? {
        loadSnapshot
    }

    func save(_ snapshot: KanbanBoardSnapshot) throws {
        savedSnapshots.append(snapshot)
    }
}
