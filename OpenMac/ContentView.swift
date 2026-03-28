import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Environment(\.colorScheme) private var systemColorScheme
    @AppStorage("appearanceMode") private var appearanceModeRawValue = AppAppearanceMode.system.rawValue
    @StateObject private var viewModel: KanbanBoardViewModel

    @State private var isShowingNewTaskSheet = false
    @State private var isShowingEditTaskSheet = false
    @State private var isShowingNewAgentSheet = false
    @State private var isShowingEditAgentSheet = false
    @State private var isShowingNewBoardSheet = false
    @State private var isShowingRenameBoardSheet = false
    @State private var isShowingGlobalTaskFinder = false
    @State private var isShowingWIPSettingsSheet = false
    @State private var isShowingManualTriageSheet = false
    @State private var isShowingDeleteBoardAlert = false
    @State private var newBoardName = ""
    @State private var renameBoardName = ""
    @State private var newTaskTitle = ""
    @State private var newTaskDetails = ""
    @State private var newTaskSkills = ""
    @State private var newTaskPoints = 1
    @State private var editingTaskID: UUID?
    @State private var editTaskTitle = ""
    @State private var editTaskDetails = ""
    @State private var editTaskSkills = ""
    @State private var editTaskPoints = 1
    @State private var newAgentName = ""
    @State private var newAgentSkills = ""
    @State private var newAgentCapacity = 3
    @State private var editingAgentID: UUID?
    @State private var editAgentName = ""
    @State private var editAgentSkills = ""
    @State private var editAgentCapacity = 3
    @State private var inProgressWIPLimitDraft = 1
    @State private var reviewWIPLimitDraft = 1
    @State private var triageSelectionByTaskID: [UUID: UUID] = [:]
    @State private var taskSearchQuery = ""
    @State private var globalTaskSearchQuery = ""
    @State private var selectedAssigneeFilterKey = "all"

    init(viewModel: KanbanBoardViewModel = .demoBoard()) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        NavigationSplitView {
            List {
                ForEach(viewModel.agents) { agent in
                    AgentRowView(
                        name: agent.name,
                        skillsText: agent.skills.sorted().joined(separator: ", "),
                        loadCount: viewModel.activeTaskCount(for: agent.id),
                        maxLoad: agent.maxConcurrentTasks,
                        loadPercent: viewModel.loadPercent(for: agent.id),
                        loadProgress: min(1.0, viewModel.loadRatio(for: agent.id)),
                        isOverloaded: viewModel.isAgentOverloaded(agent.id)
                    )
                    .padding(.vertical, 4)
                    .contextMenu {
                        Button("Edit Agent") {
                            openEditAgent(agent)
                        }
                        Button("Unassign Todo Tasks") {
                            unassignTodoTasks(for: agent.id)
                        }
                        .disabled(!hasAssignedTodoTasks(for: agent.id))
                        Button("Remove Agent", role: .destructive) {
                            removeAgent(agent.id)
                        }
                    }
                }
                .onDelete(perform: deleteAgents)
            }
            .navigationTitle("AI Agents")
        } detail: {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("AI Agent Kanban Dispatch")
                            .font(.title2.weight(.semibold))
                        Text("Board: \(viewModel.selectedBoardName)")
                            .font(.caption)
                            .foregroundStyle(BoardNeutralTextPalette.color(for: .secondary, scheme: effectiveColorScheme))
                    }
                    Spacer()
                    if !viewModel.triageCandidates().isEmpty {
                        Text("\(viewModel.triageCandidates().count) task(s) need manual triage")
                            .font(.callout)
                            .foregroundStyle(BoardSemanticTextPalette.color(for: .warning, scheme: effectiveColorScheme))
                    }
                }

                BoardHealthSummaryView(
                    totalTasks: viewModel.totalTaskCount,
                    todoTasks: viewModel.todoTaskCount,
                    unassignedTodoTasks: viewModel.unassignedTodoTaskCount,
                    overloadedAgents: viewModel.overloadedAgentCount,
                    healthScore: viewModel.boardHealthScore,
                    healthLabel: viewModel.boardHealthLabel,
                    healthBreakdownText: viewModel.boardHealthBreakdownText,
                    inProgressPressure: viewModel.wipPressurePercent(for: .inProgress),
                    reviewPressure: viewModel.wipPressurePercent(for: .review)
                )

                BoardHealthRecommendationsView(
                    recommendations: viewModel.healthRecommendations(),
                    onAction: applyHealthRecommendation,
                    onApplyAll: applyAllHealthRecommendations
                )

                HStack(spacing: 12) {
                    TextField("Search tasks", text: $taskSearchQuery)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 300)

                    Picker("Assignee", selection: $selectedAssigneeFilterKey) {
                        ForEach(assigneeFilterOptions, id: \.key) { option in
                            Text(option.label).tag(option.key)
                        }
                    }
                    .pickerStyle(.menu)

                    Text("Showing \(filteredTaskCount) / \(viewModel.tasks.count)")
                        .font(.caption)
                        .foregroundStyle(BoardNeutralTextPalette.color(for: .secondary, scheme: effectiveColorScheme))

                    Button("Reset Filters") {
                        resetTaskFilters()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(taskSearchQuery.isEmpty && selectedAssigneeFilterKey == "all")

                    Spacer()
                }

                if let message = viewModel.lastBoardMessage {
                    Text(message)
                        .font(.callout)
                        .foregroundStyle(BoardMessageColorPalette.color(for: viewModel.lastBoardMessageSeverity, scheme: effectiveColorScheme))
                }

                ScrollView(.horizontal) {
                    HStack(alignment: .top, spacing: 14) {
                        ForEach(KanbanStatus.allCases) { status in
                            KanbanColumnView(
                                status: status,
                                tasks: filteredBoardTasks(in: status),
                                wipLimit: viewModel.wipLimit(for: status),
                                assigneeName: { task in
                                    viewModel.agentName(for: task.assignedAgentID)
                                },
                                assignmentReason: { task in
                                    viewModel.assignmentReason(for: task.id)
                                },
                                moveBackward: { task in
                                    guard let previous = status.previous else { return }
                                    viewModel.moveTask(task.id, to: previous)
                                },
                                moveForward: { task in
                                    guard let next = status.next else { return }
                                    viewModel.moveTask(task.id, to: next)
                                },
                                onEditTask: openEditTask,
                                onDeleteTask: removeTask,
                                onDuplicateTask: duplicateTask,
                                onUnassignTask: unassignTask,
                                onAutoAssignTask: autoAssignTask,
                                assignableAgents: { task in
                                    viewModel.assignableAgents(for: task.id)
                                },
                                reassignableAgents: { task in
                                    viewModel.reassignableAgents(for: task.id)
                                },
                                onManualAssignTask: assignTaskToAgent,
                                onReassignTask: reassignTaskToAgent,
                                moveToBoardTargets: moveTaskBoardTargets,
                                onMoveTaskToBoard: moveTaskToBoard,
                                onCopyTaskToBoard: copyTaskToBoard,
                                onDropTask: { taskID in
                                    viewModel.handleDrop(taskID, to: status)
                                }
                            )
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .padding(20)
            .background(
                LinearGradient(
                    colors: detailBackgroundColors,
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        }
        .toolbar {
            ToolbarItemGroup {
                Button("Auto Assign AI") {
                    runAutoAssignFromToolbar()
                }
                .keyboardShortcut("a", modifiers: [.command, .shift])
                .help("Auto-assign all eligible To Do tasks (Shift-Command-A)")
                .disabled(!canAutoAssignFromToolbar)
                Button("New Task") {
                    isShowingNewTaskSheet = true
                }
                .keyboardShortcut("n", modifiers: [.command])
                .help("Create a new task (Command-N)")
                Button("New Agent") {
                    isShowingNewAgentSheet = true
                }
                .keyboardShortcut("n", modifiers: [.command, .option])
                .help("Create a new agent profile (Option-Command-N)")
                Button("Find Task") {
                    openGlobalTaskFinder()
                }
                .keyboardShortcut("f", modifiers: [.command])
                .help("Search tasks across boards (Command-F)")
                Menu("Board: \(viewModel.selectedBoardName)") {
                    Button("New Board") {
                        openNewBoardSheet()
                    }
                    .keyboardShortcut("b", modifiers: [.command, .option])

                    Button("Rename Current Board") {
                        openRenameBoardSheet()
                    }
                    .disabled(viewModel.boards.isEmpty)

                    Button("Delete Current Board") {
                        isShowingDeleteBoardAlert = true
                    }
                    .disabled(viewModel.boards.count <= 1)

                    Button("Duplicate Current Board") {
                        duplicateSelectedBoard()
                    }
                    .disabled(viewModel.boards.isEmpty)

                    Divider()

                    ForEach(viewModel.boards) { board in
                        Button {
                            switchBoard(board.id)
                        } label: {
                            if viewModel.selectedBoardID == board.id {
                                Label(board.name, systemImage: "checkmark")
                            } else {
                                Text(board.name)
                            }
                        }
                    }
                }
                .help("Create a board or switch board context")
                Menu("Board Actions") {
                    Section("Health") {
                        if viewModel.hasAutoFixableHealthRecommendations {
                            Button("Apply Health Fixes (\(viewModel.autoFixableHealthRecommendationCount))") {
                                applyAllHealthRecommendations()
                            }
                            .keyboardShortcut("h", modifiers: [.command, .shift])
                        } else {
                            Text("No health fixes available")
                        }
                    }

                    Section("Board") {
                        Button("Archive Done") {
                            archiveDoneTasks()
                        }
                        .keyboardShortcut("d", modifiers: [.command, .shift])
                        .disabled(viewModel.tasks(in: .done).isEmpty)

                        Button("Rebalance Load") {
                            rebalanceTodoAssignments()
                        }
                        .keyboardShortcut("r", modifiers: [.command, .shift])
                        .disabled(!viewModel.canRebalanceTodoAssignments())

                        Button("WIP Limits") {
                            openWIPSettings()
                        }
                        .keyboardShortcut("l", modifiers: [.command, .shift])

                        Button("Manual Triage") {
                            openManualTriage()
                        }
                        .keyboardShortcut("t", modifiers: [.command, .shift])
                        .disabled(viewModel.triageCandidates().isEmpty)

                        Divider()

                        Button("Export Current Board JSON...") {
                            exportSelectedBoardFromToolbar()
                        }
                        .keyboardShortcut("e", modifiers: [.command, .shift, .option])

                        Button("Export Workspace JSON...") {
                            exportWorkspaceFromToolbar()
                        }
                        .keyboardShortcut("e", modifiers: [.command, .shift])

                        Button("Import Workspace JSON...") {
                            importWorkspaceFromToolbar()
                        }
                        .keyboardShortcut("i", modifiers: [.command, .shift])

                        Divider()

                        Button("Rename Board") {
                            openRenameBoardSheet()
                        }
                        .disabled(viewModel.boards.isEmpty)

                        Button("Delete Board") {
                            isShowingDeleteBoardAlert = true
                        }
                        .disabled(viewModel.boards.count <= 1)

                        Button("Duplicate Board") {
                            duplicateSelectedBoard()
                        }
                        .disabled(viewModel.boards.isEmpty)
                    }
                }
                .help("Archive, rebalance, WIP settings, and manual triage actions")
                Menu("Appearance: \(selectedAppearanceMode.title)") {
                    Button("Cycle Appearance") {
                        cycleAppearanceMode()
                    }
                    .keyboardShortcut("`", modifiers: [.command, .option])

                    Divider()

                    ForEach(AppAppearanceMode.allCases) { mode in
                        appearanceMenuButton(for: mode)
                    }
                }
                .help("Switch between system, light, and dark appearance (Option-Command-`/0/L/D)")
            }
        }
        .sheet(isPresented: $isShowingNewBoardSheet) {
            NewBoardSheet(
                name: $newBoardName,
                boardMessage: viewModel.lastBoardMessage,
                boardMessageSeverity: viewModel.lastBoardMessageSeverity,
                onCancel: closeNewBoardSheet,
                onCreate: createBoardFromSheet
            )
        }
        .sheet(isPresented: $isShowingRenameBoardSheet) {
            RenameBoardSheet(
                name: $renameBoardName,
                boardMessage: viewModel.lastBoardMessage,
                boardMessageSeverity: viewModel.lastBoardMessageSeverity,
                onCancel: closeRenameBoardSheet,
                onRename: renameBoardFromSheet
            )
        }
        .sheet(isPresented: $isShowingGlobalTaskFinder) {
            GlobalTaskSearchSheet(
                query: $globalTaskSearchQuery,
                results: globalTaskSearchResults,
                onOpenResult: openGlobalTaskSearchResult,
                onClose: closeGlobalTaskFinder
            )
        }
        .sheet(isPresented: $isShowingNewTaskSheet) {
            NewTaskSheet(
                title: $newTaskTitle,
                details: $newTaskDetails,
                skills: $newTaskSkills,
                storyPoints: $newTaskPoints,
                boardMessage: viewModel.lastBoardMessage,
                boardMessageSeverity: viewModel.lastBoardMessageSeverity,
                onCancel: resetDraftAndClose,
                onCreate: { createTaskFromSheet(autoAssign: false) },
                onCreateAutoAssign: { createTaskFromSheet(autoAssign: true) }
            )
        }
        .sheet(isPresented: $isShowingWIPSettingsSheet) {
            WIPSettingsSheet(
                inProgressLimit: $inProgressWIPLimitDraft,
                reviewLimit: $reviewWIPLimitDraft,
                onCancel: { isShowingWIPSettingsSheet = false },
                onApply: applyWIPSettings
            )
        }
        .sheet(isPresented: $isShowingEditTaskSheet) {
            EditTaskSheet(
                title: $editTaskTitle,
                details: $editTaskDetails,
                skills: $editTaskSkills,
                storyPoints: $editTaskPoints,
                boardMessage: viewModel.lastBoardMessage,
                boardMessageSeverity: viewModel.lastBoardMessageSeverity,
                onCancel: closeEditTaskSheet,
                onSave: applyTaskEdits
            )
        }
        .sheet(isPresented: $isShowingNewAgentSheet) {
            NewAgentSheet(
                name: $newAgentName,
                skills: $newAgentSkills,
                maxConcurrentTasks: $newAgentCapacity,
                boardMessage: viewModel.lastBoardMessage,
                boardMessageSeverity: viewModel.lastBoardMessageSeverity,
                onCancel: resetAgentDraftAndClose,
                onCreate: {
                    let added = viewModel.addAgent(
                        name: newAgentName,
                        skillsText: newAgentSkills,
                        maxConcurrentTasks: newAgentCapacity
                    )
                    if added {
                        resetAgentDraftAndClose()
                    }
                }
            )
        }
        .sheet(isPresented: $isShowingEditAgentSheet) {
            EditAgentSheet(
                name: $editAgentName,
                skills: $editAgentSkills,
                maxConcurrentTasks: $editAgentCapacity,
                boardMessage: viewModel.lastBoardMessage,
                boardMessageSeverity: viewModel.lastBoardMessageSeverity,
                onCancel: closeEditAgentSheet,
                onSave: applyAgentEdits
            )
        }
        .sheet(isPresented: $isShowingManualTriageSheet) {
            ManualTriageSheet(
                tasks: viewModel.triageCandidates(),
                boardMessage: viewModel.lastBoardMessage,
                boardMessageSeverity: viewModel.lastBoardMessageSeverity,
                selectedAgentByTaskID: $triageSelectionByTaskID,
                assignAllEligibleCount: viewModel.bulkAssignableTriageTaskCount(using: triageSelectionByTaskID),
                unassignableTaskCount: viewModel.bulkUnassignableTriageTaskCount(using: triageSelectionByTaskID),
                assignableAgents: { task in
                    viewModel.assignableAgents(for: task.id)
                },
                loadText: { agent in "\(viewModel.activeTaskCount(for: agent.id))/\(agent.maxConcurrentTasks)" },
                onAssign: assignManually,
                onAssignAll: assignAllManually,
                onClose: { isShowingManualTriageSheet = false }
            )
        }
        .onChange(of: viewModel.agents) { _, _ in
            normalizeAssigneeFilterSelection()
        }
        .onChange(of: viewModel.selectedBoardID) { _, _ in
            handleBoardContextChanged()
        }
        .alert("Delete Board?", isPresented: $isShowingDeleteBoardAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                removeSelectedBoard()
            }
        } message: {
            Text("Delete \"\(viewModel.selectedBoardName)\" and all tasks/agents in it? This cannot be undone.")
        }
        .environment(\.colorScheme, effectiveColorScheme)
        .preferredColorScheme(selectedAppearanceMode.preferredColorScheme)
    }

    private func resetDraftAndClose() {
        newTaskTitle = ""
        newTaskDetails = ""
        newTaskSkills = ""
        newTaskPoints = 1
        isShowingNewTaskSheet = false
    }

    private func openEditTask(_ task: WorkTask) {
        editingTaskID = task.id
        editTaskTitle = task.title
        editTaskDetails = task.details
        editTaskSkills = task.requiredSkills.sorted().joined(separator: ", ")
        editTaskPoints = task.storyPoints
        isShowingEditTaskSheet = true
    }

    private func closeEditTaskSheet() {
        editingTaskID = nil
        editTaskTitle = ""
        editTaskDetails = ""
        editTaskSkills = ""
        editTaskPoints = 1
        isShowingEditTaskSheet = false
    }

    private func resetAgentDraftAndClose() {
        newAgentName = ""
        newAgentSkills = ""
        newAgentCapacity = 3
        isShowingNewAgentSheet = false
    }

    private func openNewBoardSheet() {
        newBoardName = ""
        isShowingNewBoardSheet = true
    }

    private func closeNewBoardSheet() {
        newBoardName = ""
        isShowingNewBoardSheet = false
    }

    private func openRenameBoardSheet() {
        renameBoardName = viewModel.selectedBoardName
        isShowingRenameBoardSheet = true
    }

    private func closeRenameBoardSheet() {
        renameBoardName = ""
        isShowingRenameBoardSheet = false
    }

    private func createBoardFromSheet() {
        let created = viewModel.createBoard(name: newBoardName)
        if created {
            closeNewBoardSheet()
            handleBoardContextChanged()
        }
    }

    private func renameBoardFromSheet() {
        let renamed = viewModel.renameBoard(viewModel.selectedBoardID, to: renameBoardName)
        if renamed {
            closeRenameBoardSheet()
        }
    }

    private func removeSelectedBoard() {
        let removed = viewModel.removeBoard(viewModel.selectedBoardID)
        if removed {
            handleBoardContextChanged()
        }
    }

    private func duplicateSelectedBoard() {
        let duplicated = viewModel.duplicateBoard(viewModel.selectedBoardID)
        if duplicated {
            handleBoardContextChanged()
        }
    }

    private func openGlobalTaskFinder() {
        globalTaskSearchQuery = taskSearchQuery
        isShowingGlobalTaskFinder = true
    }

    private func closeGlobalTaskFinder() {
        globalTaskSearchQuery = ""
        isShowingGlobalTaskFinder = false
    }

    private func openGlobalTaskSearchResult(_ result: GlobalTaskSearchResult) {
        let opened = viewModel.openTask(result.taskID, in: result.boardID)
        if opened {
            closeGlobalTaskFinder()
            handleBoardContextChanged()
            taskSearchQuery = result.taskTitle
        }
    }

    private func switchBoard(_ boardID: UUID) {
        let switched = viewModel.switchBoard(to: boardID)
        if switched {
            handleBoardContextChanged()
        }
    }

    private func handleBoardContextChanged() {
        taskSearchQuery = ""
        selectedAssigneeFilterKey = "all"
        triageSelectionByTaskID = [:]
        isShowingManualTriageSheet = false
        closeEditTaskSheet()
        closeEditAgentSheet()
        normalizeAssigneeFilterSelection()
    }

    private func openWIPSettings() {
        inProgressWIPLimitDraft = viewModel.wipLimit(for: .inProgress) ?? 1
        reviewWIPLimitDraft = viewModel.wipLimit(for: .review) ?? 1
        isShowingWIPSettingsSheet = true
    }

    private func applyWIPSettings() {
        let updated = viewModel.updateWIPLimits([
            .inProgress: inProgressWIPLimitDraft,
            .review: reviewWIPLimitDraft
        ])
        if updated {
            isShowingWIPSettingsSheet = false
        }
    }

    private func applyTaskEdits() {
        guard let editingTaskID else { return }

        let updated = viewModel.updateTask(
            editingTaskID,
            title: editTaskTitle,
            details: editTaskDetails,
            requiredSkillsText: editTaskSkills,
            storyPoints: editTaskPoints
        )

        if updated {
            refreshTriageSelections()
            closeEditTaskSheet()
        }
    }

    private func createTaskFromSheet(autoAssign: Bool) {
        let added = viewModel.addTask(
            title: newTaskTitle,
            details: newTaskDetails,
            requiredSkillsText: newTaskSkills,
            storyPoints: newTaskPoints,
            autoAssign: autoAssign
        )
        if added {
            refreshTriageSelections()
            resetDraftAndClose()
        }
    }

    private func archiveDoneTasks() {
        let removedCount = viewModel.clearDoneTasks()
        if removedCount > 0 {
            refreshTriageSelections()
        }
    }

    private func rebalanceTodoAssignments() {
        let movedCount = viewModel.rebalanceTodoAssignments()
        if movedCount > 0 {
            refreshTriageSelections()
        }
    }

    private func runAutoAssignFromToolbar() {
        viewModel.autoAssignTasks()
        refreshTriageSelections()
        if viewModel.hasPendingManualTriage {
            openManualTriage()
        }
    }

    private func applyHealthRecommendation(_ action: BoardHealthAction) {
        let applied = viewModel.applyHealthRecommendation(action)
        guard applied else { return }

        switch action {
        case .autoAssignUnassignedTodo:
            refreshTriageSelections()
            if viewModel.hasPendingManualTriage {
                openManualTriage()
            }
        case .rebalanceTodoLoad, .archiveDone:
            refreshTriageSelections()
        case .openManualTriage:
            refreshTriageSelections()
            openManualTriage()
        case .openNewAgent:
            isShowingNewAgentSheet = true
        case .increaseWIPLimit(_):
            break
        }
    }

    private func applyAllHealthRecommendations() {
        let appliedCount = viewModel.applyAllHealthRecommendations()
        guard appliedCount > 0 else { return }

        refreshTriageSelections()
        if viewModel.hasPendingManualTriage {
            openManualTriage()
        }
    }

    private func openManualTriage() {
        refreshTriageSelections()
        isShowingManualTriageSheet = true
    }

    private func exportWorkspaceFromToolbar() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType.json]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.nameFieldStringValue = "openmac-workspace.json"
        panel.title = "Export Workspace"
        panel.message = "Save boards, tasks, and agents as workspace JSON."

        guard panel.runModal() == .OK, let url = panel.url else { return }
        _ = viewModel.exportWorkspace(to: url)
    }

    private func exportSelectedBoardFromToolbar() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType.json]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.nameFieldStringValue = selectedBoardExportFileName()
        panel.title = "Export Current Board"
        panel.message = "Save only the current board as JSON."

        guard panel.runModal() == .OK, let url = panel.url else { return }
        _ = viewModel.exportSelectedBoard(to: url)
    }

    private func importWorkspaceFromToolbar() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.title = "Import Workspace"
        panel.message = "Select workspace JSON to import."

        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let preview = viewModel.workspaceImportPreview(from: url) else { return }
        guard let strategy = chooseWorkspaceImportStrategy(preview: preview) else { return }
        let imported = viewModel.importWorkspace(from: url, strategy: strategy)
        if imported {
            handleBoardContextChanged()
        }
    }

    private func chooseWorkspaceImportStrategy(preview: WorkspaceImportPreview) -> WorkspaceImportStrategy? {
        let alert = NSAlert()
        alert.messageText = "Import Workspace"
        alert.informativeText = """
        Boards: \(preview.boardCount)
        Tasks: \(preview.taskCount)
        Agents: \(preview.agentCount)

        Merge keeps current boards and appends imported boards.
        Replace overwrites current workspace with imported boards.
        """
        alert.addButton(withTitle: "Merge")
        alert.addButton(withTitle: "Replace")
        alert.addButton(withTitle: "Cancel")

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            return .merge
        case .alertSecondButtonReturn:
            return .replace
        default:
            return nil
        }
    }

    private func selectedBoardExportFileName() -> String {
        let rawTokens = viewModel.selectedBoardName
            .lowercased()
            .split { character in
                !(character.isLetter || character.isNumber)
            }
        let slug = rawTokens.joined(separator: "-")
        let resolvedSlug = slug.isEmpty ? "board" : slug
        return "openmac-\(resolvedSlug)-board.json"
    }

    private func assignManually(taskID: UUID) {
        guard let selectedAgentID = triageSelectionByTaskID[taskID] else { return }
        let assigned = viewModel.manuallyAssignTask(taskID, to: selectedAgentID)
        if assigned {
            triageSelectionByTaskID.removeValue(forKey: taskID)
            refreshTriageSelections()
            if viewModel.triageCandidates().isEmpty {
                isShowingManualTriageSheet = false
            }
        }
    }

    private func assignAllManually() {
        _ = viewModel.bulkAssignTriageTasks(using: triageSelectionByTaskID)
        refreshTriageSelections()
        if viewModel.triageCandidates().isEmpty {
            isShowingManualTriageSheet = false
        }
    }

    private func refreshTriageSelections() {
        triageSelectionByTaskID = viewModel.resolvedTriageAssignments(existing: triageSelectionByTaskID)
    }

    private func deleteAgents(at offsets: IndexSet) {
        let ids: [UUID] = offsets.map { viewModel.agents[$0].id }

        for id in ids {
            removeAgent(id)
        }
    }

    private func removeAgent(_ agentID: UUID) {
        let removed = viewModel.removeAgent(agentID)
        if removed {
            refreshTriageSelections()
        }
    }

    private func unassignTodoTasks(for agentID: UUID) {
        let count = viewModel.unassignTodoTasks(for: agentID)
        if count > 0 {
            refreshTriageSelections()
        }
    }

    private func removeTask(_ taskID: UUID) {
        let removed = viewModel.removeTask(taskID)
        if removed {
            refreshTriageSelections()
        }
    }

    private func duplicateTask(_ taskID: UUID) {
        let duplicated = viewModel.duplicateTask(taskID)
        if duplicated {
            refreshTriageSelections()
        }
    }

    private func unassignTask(_ taskID: UUID) {
        let unassigned = viewModel.unassignTask(taskID)
        if unassigned {
            refreshTriageSelections()
        }
    }

    private func moveTaskToBoard(_ taskID: UUID, _ boardID: UUID) {
        let moved = viewModel.moveTask(taskID, toBoard: boardID)
        if moved {
            refreshTriageSelections()
        }
    }

    private func copyTaskToBoard(_ taskID: UUID, _ boardID: UUID) {
        let copied = viewModel.copyTask(taskID, toBoard: boardID)
        if copied {
            refreshTriageSelections()
        }
    }

    private func autoAssignTask(_ taskID: UUID) {
        let assigned = viewModel.autoAssignTask(taskID)
        if assigned {
            refreshTriageSelections()
        }
    }

    private func assignTaskToAgent(_ taskID: UUID, _ agentID: UUID) {
        let assigned = viewModel.manuallyAssignTask(taskID, to: agentID)
        if assigned {
            refreshTriageSelections()
        }
    }

    private func reassignTaskToAgent(_ taskID: UUID, _ agentID: UUID) {
        let reassigned = viewModel.reassignTask(taskID, to: agentID)
        if reassigned {
            refreshTriageSelections()
        }
    }

    private func openEditAgent(_ agent: AgentProfile) {
        editingAgentID = agent.id
        editAgentName = agent.name
        editAgentSkills = agent.skills.sorted().joined(separator: ", ")
        editAgentCapacity = agent.maxConcurrentTasks
        isShowingEditAgentSheet = true
    }

    private func closeEditAgentSheet() {
        editingAgentID = nil
        editAgentName = ""
        editAgentSkills = ""
        editAgentCapacity = 3
        isShowingEditAgentSheet = false
    }

    private func applyAgentEdits() {
        guard let editingAgentID else { return }

        let updated = viewModel.updateAgent(
            editingAgentID,
            name: editAgentName,
            skillsText: editAgentSkills,
            maxConcurrentTasks: editAgentCapacity
        )

        if updated {
            refreshTriageSelections()
            closeEditAgentSheet()
        }
    }

    private var assigneeFilterOptions: [(key: String, label: String)] {
        let base = [
            (key: "all", label: "All Assignees"),
            (key: "unassigned", label: "Unassigned")
        ]
        let agentOptions = viewModel.agents
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            .map { agent in
                (key: agent.id.uuidString, label: agent.name)
            }
        return base + agentOptions
    }

    private func hasAssignedTodoTasks(for agentID: UUID) -> Bool {
        viewModel.tasks(in: .todo).contains(where: { $0.assignedAgentID == agentID })
    }

    private var selectedAssigneeFilter: TaskAssigneeFilter {
        if selectedAssigneeFilterKey == "all" {
            return .all
        }
        if selectedAssigneeFilterKey == "unassigned" {
            return .unassigned
        }
        guard let id = UUID(uuidString: selectedAssigneeFilterKey),
              viewModel.agents.contains(where: { $0.id == id }) else {
            return .all
        }
        return .assigned(id)
    }

    private func filteredBoardTasks(in status: KanbanStatus) -> [WorkTask] {
        viewModel.filteredTasks(in: status, query: taskSearchQuery, assigneeFilter: selectedAssigneeFilter)
    }

    private var filteredTaskCount: Int {
        KanbanStatus.allCases.reduce(0) { partialResult, status in
            partialResult + filteredBoardTasks(in: status).count
        }
    }

    private var moveTaskBoardTargets: [KanbanBoardRecord] {
        viewModel.boards.filter { $0.id != viewModel.selectedBoardID }
    }

    private var globalTaskSearchResults: [GlobalTaskSearchResult] {
        viewModel.globalTaskSearchResults(query: globalTaskSearchQuery)
    }

    private func resetTaskFilters() {
        taskSearchQuery = ""
        selectedAssigneeFilterKey = "all"
    }

    private func normalizeAssigneeFilterSelection() {
        let validKeys = Set(assigneeFilterOptions.map { $0.key })
        if !validKeys.contains(selectedAssigneeFilterKey) {
            selectedAssigneeFilterKey = "all"
        }
    }

    private var canAutoAssignFromToolbar: Bool {
        viewModel.unassignedTodoTaskCount > 0 && !viewModel.agents.isEmpty
    }

    private var detailBackgroundColors: [Color] {
        BoardSurfacePalette.detailGradientTokens(for: effectiveColorScheme).map(\.color)
    }

    private var effectiveColorScheme: ColorScheme {
        AppearanceSchemeResolver.resolve(systemScheme: systemColorScheme, appearanceMode: selectedAppearanceMode)
    }

    private var selectedAppearanceMode: AppAppearanceMode {
        AppAppearanceMode.resolve(rawValue: appearanceModeRawValue)
    }

    @ViewBuilder
    private func appearanceMenuButton(for mode: AppAppearanceMode) -> some View {
        switch mode {
        case .system:
            appearanceSelectionButton(for: mode)
                .keyboardShortcut("0", modifiers: [.command, .option])
        case .light:
            appearanceSelectionButton(for: mode)
                .keyboardShortcut("l", modifiers: [.command, .option])
        case .dark:
            appearanceSelectionButton(for: mode)
                .keyboardShortcut("d", modifiers: [.command, .option])
        }
    }

    private func appearanceSelectionButton(for mode: AppAppearanceMode) -> some View {
        Button {
            appearanceModeRawValue = mode.rawValue
        } label: {
            if selectedAppearanceMode == mode {
                Label(mode.title, systemImage: "checkmark")
            } else {
                Text(mode.title)
            }
        }
    }

    private func cycleAppearanceMode() {
        appearanceModeRawValue = selectedAppearanceMode.next().rawValue
    }
}

private struct AgentRowView: View {
    @Environment(\.colorScheme) private var colorScheme
    let name: String
    let skillsText: String
    let loadCount: Int
    let maxLoad: Int
    let loadPercent: Int
    let loadProgress: Double
    let isOverloaded: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(name)
                .font(.headline)
            Text("Skills: \(skillsText)")
                .font(.caption)
                .foregroundStyle(BoardNeutralTextPalette.color(for: .secondary, scheme: colorScheme))
            HStack(spacing: 8) {
                ProgressView(value: loadProgress, total: 1.0)
                    .progressViewStyle(.linear)
                Text("\(loadPercent)%")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(BoardNeutralTextPalette.color(for: .secondary, scheme: colorScheme))
            }
            Text("Load: \(loadCount)/\(maxLoad)")
                .font(.caption2)
                .foregroundStyle(
                    isOverloaded
                        ? BoardSemanticTextPalette.color(for: .error, scheme: colorScheme)
                        : BoardNeutralTextPalette.color(for: .secondary, scheme: colorScheme)
                )
            if isOverloaded {
                Text("Overloaded")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(BoardSemanticTextPalette.color(for: .error, scheme: colorScheme))
            }
        }
    }
}

private struct BoardHealthSummaryView: View {
    let totalTasks: Int
    let todoTasks: Int
    let unassignedTodoTasks: Int
    let overloadedAgents: Int
    let healthScore: Int
    let healthLabel: String
    let healthBreakdownText: String
    let inProgressPressure: Int
    let reviewPressure: Int

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                SummaryBadge(title: "Total", value: "\(totalTasks)", accent: .blue)
                SummaryBadge(title: "To Do", value: "\(todoTasks)", accent: .indigo)
                SummaryBadge(title: "Unassigned", value: "\(unassignedTodoTasks)", accent: .amber)
                SummaryBadge(title: "Overloaded", value: "\(overloadedAgents)", accent: overloadedAgents > 0 ? .red : .green)
                SummaryBadge(
                    title: "Health",
                    value: "\(healthScore) \(healthLabel)",
                    accent: healthScoreAccent,
                    helpText: healthBreakdownText
                )
                SummaryBadge(title: "InProg WIP", value: "\(inProgressPressure)%", accent: inProgressPressure >= 100 ? .red : .teal)
                SummaryBadge(title: "Review WIP", value: "\(reviewPressure)%", accent: reviewPressure >= 100 ? .red : .mint)
                Spacer(minLength: 0)
            }
        }
    }

    private var healthScoreAccent: SummaryBadgeAccent {
        if healthScore >= 85 {
            return .green
        }
        if healthScore >= 60 {
            return .amber
        }
        return .red
    }
}

private struct BoardHealthRecommendationsView: View {
    @Environment(\.colorScheme) private var colorScheme
    let recommendations: [BoardHealthRecommendation]
    let onAction: (BoardHealthAction) -> Void
    let onApplyAll: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if recommendations.isEmpty {
                Text("Board health looks stable. No immediate actions recommended.")
                    .font(.caption)
                    .foregroundStyle(BoardSemanticTextPalette.color(for: .success, scheme: colorScheme))
            } else {
                HStack {
                    Text("Suggested Actions")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(BoardNeutralTextPalette.color(for: .secondary, scheme: colorScheme))
                    Spacer()
                    if autoFixRecommendationCount > 0 {
                        Button("Apply All (\(autoFixRecommendationCount))") {
                            onApplyAll()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(recommendations) { recommendation in
                            Button {
                                onAction(recommendation.action)
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(recommendation.title)
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.primary)
                                    Text(recommendation.detail)
                                        .font(.caption2)
                                        .foregroundStyle(BoardNeutralTextPalette.color(for: .secondary, scheme: colorScheme))
                                        .multilineTextAlignment(.leading)
                                        .lineLimit(2)
                                }
                                .frame(width: 220, alignment: .leading)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                                .background(recommendationCardBackground, in: RoundedRectangle(cornerRadius: 10))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(recommendationCardBorder, lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    private var recommendationCardBackground: Color {
        BoardSurfacePalette.supplementaryCardColor(for: colorScheme)
    }

    private var recommendationCardBorder: Color {
        BoardChromePalette.supplementaryCardBorderColor(for: colorScheme)
    }

    private var autoFixRecommendationCount: Int {
        recommendations.filter { $0.action.isAutoFixable }.count
    }
}

private struct SummaryBadge: View {
    @Environment(\.colorScheme) private var colorScheme
    let title: String
    let value: String
    let accent: SummaryBadgeAccent
    var helpText: String?

    var body: some View {
        let badgeContent = VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(BoardNeutralTextPalette.color(for: .secondary, scheme: colorScheme))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(value)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(minWidth: 78, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(SummaryBadgePalette.color(for: accent, scheme: colorScheme), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(BoardChromePalette.summaryBadgeBorderColor(for: colorScheme), lineWidth: 1)
        )

        if let helpText, !helpText.isEmpty {
            badgeContent.help(helpText)
        } else {
            badgeContent
        }
    }
}

private struct KanbanColumnView: View {
    @Environment(\.colorScheme) private var colorScheme
    let status: KanbanStatus
    let tasks: [WorkTask]
    let wipLimit: Int?
    let assigneeName: (WorkTask) -> String
    let assignmentReason: (WorkTask) -> String?
    let moveBackward: (WorkTask) -> Void
    let moveForward: (WorkTask) -> Void
    let onEditTask: (WorkTask) -> Void
    let onDeleteTask: (UUID) -> Void
    let onDuplicateTask: (UUID) -> Void
    let onUnassignTask: (UUID) -> Void
    let onAutoAssignTask: (UUID) -> Void
    let assignableAgents: (WorkTask) -> [AgentProfile]
    let reassignableAgents: (WorkTask) -> [AgentProfile]
    let onManualAssignTask: (UUID, UUID) -> Void
    let onReassignTask: (UUID, UUID) -> Void
    let moveToBoardTargets: [KanbanBoardRecord]
    let onMoveTaskToBoard: (UUID, UUID) -> Void
    let onCopyTaskToBoard: (UUID, UUID) -> Void
    let onDropTask: (UUID) -> Bool

    @State private var isDropTarget = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(status.title)
                    .font(.headline)
                Spacer()
                if let wipLimit {
                    Text("\(tasks.count)/\(wipLimit)")
                        .font(.caption)
                        .foregroundStyle(tasks.count >= wipLimit ? BoardSemanticTextPalette.color(for: .error, scheme: colorScheme) : .primary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(counterBackground, in: Capsule())
                } else {
                    Text("\(tasks.count)")
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(counterBackground, in: Capsule())
                }
            }

            if tasks.isEmpty {
                Text("No tasks")
                    .font(.caption)
                    .foregroundStyle(BoardNeutralTextPalette.color(for: .secondary, scheme: colorScheme))
                    .frame(maxWidth: .infinity, minHeight: 120)
                    .background(emptyStateBackground, in: RoundedRectangle(cornerRadius: 12))
            } else {
                ForEach(tasks) { task in
                    TaskCardView(
                        task: task,
                        assigneeName: assigneeName(task),
                        assignmentReason: assignmentReason(task),
                        canMoveBackward: status.previous != nil,
                        canMoveForward: status.next != nil,
                        canUnassign: task.assignedAgentID != nil && task.status != .done,
                        canAutoAssign: task.status == .todo && task.assignedAgentID == nil,
                        manualAssignableAgents: assignableAgents(task),
                        reassignableAgents: reassignableAgents(task),
                        moveToBoardTargets: moveToBoardTargets,
                        onEdit: { onEditTask(task) },
                        onAutoAssign: { onAutoAssignTask(task.id) },
                        onManualAssign: { agentID in
                            onManualAssignTask(task.id, agentID)
                        },
                        onReassign: { agentID in
                            onReassignTask(task.id, agentID)
                        },
                        onUnassign: { onUnassignTask(task.id) },
                        onDuplicate: { onDuplicateTask(task.id) },
                        onDelete: { onDeleteTask(task.id) },
                        onMoveToBoard: { boardID in
                            onMoveTaskToBoard(task.id, boardID)
                        },
                        onCopyToBoard: { boardID in
                            onCopyTaskToBoard(task.id, boardID)
                        },
                        onMoveBackward: { moveBackward(task) },
                        onMoveForward: { moveForward(task) }
                    )
                }
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(width: 300)
        .frame(minHeight: 540, alignment: .top)
        .background(columnColor, in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(columnBorderColor, lineWidth: 1)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(isDropTarget ? Color.accentColor : .clear, lineWidth: 3)
        )
        .dropDestination(for: String.self) { items, _ in
            guard let raw = items.first, let taskID = UUID(uuidString: raw) else { return false }
            return onDropTask(taskID)
        } isTargeted: { isTargeted in
            isDropTarget = isTargeted
        }
    }

    private var columnColor: Color {
        BoardSurfacePalette.color(for: status, scheme: colorScheme)
    }

    private var counterBackground: Color {
        BoardChromePalette.counterColor(for: colorScheme)
    }

    private var emptyStateBackground: Color {
        BoardSurfacePalette.emptyStateColor(for: colorScheme)
    }

    private var columnBorderColor: Color {
        BoardChromePalette.columnBorderColor(for: colorScheme)
    }
}

private struct TaskCardView: View {
    @Environment(\.colorScheme) private var colorScheme
    let task: WorkTask
    let assigneeName: String
    let assignmentReason: String?
    let canMoveBackward: Bool
    let canMoveForward: Bool
    let canUnassign: Bool
    let canAutoAssign: Bool
    let manualAssignableAgents: [AgentProfile]
    let reassignableAgents: [AgentProfile]
    let moveToBoardTargets: [KanbanBoardRecord]
    let onEdit: () -> Void
    let onAutoAssign: () -> Void
    let onManualAssign: (UUID) -> Void
    let onReassign: (UUID) -> Void
    let onUnassign: () -> Void
    let onDuplicate: () -> Void
    let onDelete: () -> Void
    let onMoveToBoard: (UUID) -> Void
    let onCopyToBoard: (UUID) -> Void
    let onMoveBackward: () -> Void
    let onMoveForward: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(task.title)
                .font(.headline)
            if !task.details.isEmpty {
                Text(task.details)
                    .font(.subheadline)
                    .foregroundStyle(BoardNeutralTextPalette.color(for: .secondary, scheme: colorScheme))
            }

            if !task.requiredSkills.isEmpty {
                Text("Skills: \(task.requiredSkills.sorted().joined(separator: ", "))")
                    .font(.caption)
                    .foregroundStyle(BoardNeutralTextPalette.color(for: .secondary, scheme: colorScheme))
            }

            HStack {
                Text("SP: \(task.storyPoints)")
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(storyPointBackground, in: Capsule())

                Spacer()

                Text(assigneeName)
                    .font(.caption)
                    .foregroundStyle(BoardNeutralTextPalette.color(for: .secondary, scheme: colorScheme))
            }

            if let assignmentReason, task.assignedAgentID != nil {
                Text("Dispatch: \(assignmentReason)")
                    .font(.caption2)
                    .foregroundStyle(BoardNeutralTextPalette.color(for: .secondary, scheme: colorScheme))
                    .lineLimit(3)
            }

            HStack(spacing: 8) {
                if canMoveBackward {
                    Button {
                        onMoveBackward()
                    } label: {
                        Label("Back", systemImage: "arrow.left")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                if canMoveForward {
                    Button {
                        onMoveForward()
                    } label: {
                        Label("Next", systemImage: "arrow.right")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            }
        }
        .padding(12)
        .background(taskCardBackground, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(taskCardBorder, lineWidth: 1)
        )
        .contextMenu {
            Button("Edit Task", action: onEdit)
            if canAutoAssign {
                Button("Auto Assign This Task", action: onAutoAssign)
            }
            if !manualAssignableAgents.isEmpty {
                Menu("Assign To Agent") {
                    ForEach(manualAssignableAgents) { agent in
                        Button(agent.name) {
                            onManualAssign(agent.id)
                        }
                    }
                }
            }
            if !reassignableAgents.isEmpty {
                Menu("Reassign To Agent") {
                    ForEach(reassignableAgents) { agent in
                        Button(agent.name) {
                            onReassign(agent.id)
                        }
                    }
                }
            }
            if canUnassign {
                Button("Unassign Task", action: onUnassign)
            }
            if !moveToBoardTargets.isEmpty {
                Menu("Move To Board") {
                    ForEach(moveToBoardTargets) { board in
                        Button(board.name) {
                            onMoveToBoard(board.id)
                        }
                    }
                }
                Menu("Copy To Board") {
                    ForEach(moveToBoardTargets) { board in
                        Button(board.name) {
                            onCopyToBoard(board.id)
                        }
                    }
                }
            }
            Button("Duplicate Task", action: onDuplicate)
            Button("Delete Task", role: .destructive, action: onDelete)
        }
        .draggable(task.id.uuidString)
    }

    private var storyPointBackground: Color {
        BoardChromePalette.storyPointColor(for: colorScheme)
    }

    private var taskCardBackground: Color {
        BoardSurfacePalette.taskCardColor(for: colorScheme)
    }

    private var taskCardBorder: Color {
        BoardChromePalette.taskCardBorderColor(for: colorScheme)
    }
}

private struct GlobalTaskSearchSheet: View {
    @Binding var query: String
    let results: [GlobalTaskSearchResult]
    let onOpenResult: (GlobalTaskSearchResult) -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Find Task")
                .font(.title3.weight(.semibold))

            TextField("Search title, details, skills, assignee, board", text: $query)
                .textFieldStyle(.roundedBorder)

            if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text("Type to search all boards.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if results.isEmpty {
                Text("No matching tasks found.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                List(results) { result in
                    Button {
                        onOpenResult(result)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(result.taskTitle)
                                .font(.headline)
                                .foregroundStyle(.primary)
                            HStack(spacing: 8) {
                                Text(result.boardName)
                                    .font(.caption)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 2)
                                    .background(.quaternary, in: Capsule())
                                Text(result.status.title)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(result.assigneeName)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
                .listStyle(.inset)
            }

            HStack {
                Spacer()
                Button("Close", action: onClose)
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(18)
        .frame(width: 560, height: 420)
    }
}

private struct NewBoardSheet: View {
    @Binding var name: String
    let boardMessage: String?
    let boardMessageSeverity: BoardMessageSeverity?
    let onCancel: () -> Void
    let onCreate: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("New Board")
                .font(.title3.weight(.semibold))

            TextField("Board Name", text: $name)
                .textFieldStyle(.roundedBorder)

            if let boardMessage, !boardMessage.isEmpty {
                BoardMessageBanner(message: boardMessage, severity: boardMessageSeverity)
            }

            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                Button("Create", action: onCreate)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(18)
        .frame(width: 360)
    }
}

private struct RenameBoardSheet: View {
    @Binding var name: String
    let boardMessage: String?
    let boardMessageSeverity: BoardMessageSeverity?
    let onCancel: () -> Void
    let onRename: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Rename Board")
                .font(.title3.weight(.semibold))

            TextField("Board Name", text: $name)
                .textFieldStyle(.roundedBorder)

            if let boardMessage, !boardMessage.isEmpty {
                BoardMessageBanner(message: boardMessage, severity: boardMessageSeverity)
            }

            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                Button("Rename", action: onRename)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(18)
        .frame(width: 360)
    }
}

private struct NewTaskSheet: View {
    @Binding var title: String
    @Binding var details: String
    @Binding var skills: String
    @Binding var storyPoints: Int
    let boardMessage: String?
    let boardMessageSeverity: BoardMessageSeverity?

    let onCancel: () -> Void
    let onCreate: () -> Void
    let onCreateAutoAssign: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Create Task")
                .font(.title3.weight(.semibold))

            if let boardMessage, !boardMessage.isEmpty {
                BoardMessageBanner(message: boardMessage, severity: boardMessageSeverity)
            }

            TextField("Title", text: $title)
            TextField("Details", text: $details)
            TextField("Skills (comma separated)", text: $skills)

            Stepper("Story Points: \(storyPoints)", value: $storyPoints, in: 1 ... 13)

            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                Button("Create", action: onCreate)
                    .keyboardShortcut(.defaultAction)
                Button("Create + Auto Assign", action: onCreateAutoAssign)
            }
        }
        .padding(18)
        .frame(width: 420)
    }
}

private struct EditTaskSheet: View {
    @Binding var title: String
    @Binding var details: String
    @Binding var skills: String
    @Binding var storyPoints: Int
    let boardMessage: String?
    let boardMessageSeverity: BoardMessageSeverity?

    let onCancel: () -> Void
    let onSave: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Edit Task")
                .font(.title3.weight(.semibold))

            if let boardMessage, !boardMessage.isEmpty {
                BoardMessageBanner(message: boardMessage, severity: boardMessageSeverity)
            }

            TextField("Title", text: $title)
            TextField("Details", text: $details)
            TextField("Skills (comma separated)", text: $skills)
            Stepper("Story Points: \(storyPoints)", value: $storyPoints, in: 1 ... 13)

            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                Button("Save", action: onSave)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(18)
        .frame(width: 420)
    }
}

private struct WIPSettingsSheet: View {
    @Binding var inProgressLimit: Int
    @Binding var reviewLimit: Int

    let onCancel: () -> Void
    let onApply: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Edit WIP Limits")
                .font(.title3.weight(.semibold))

            Stepper("In Progress: \(inProgressLimit)", value: $inProgressLimit, in: 1 ... 20)
            Stepper("Review: \(reviewLimit)", value: $reviewLimit, in: 1 ... 20)

            Text("Tip: limit cannot be smaller than the number of tasks currently in that column.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                Button("Apply", action: onApply)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(18)
        .frame(width: 360)
    }
}

private struct NewAgentSheet: View {
    @Binding var name: String
    @Binding var skills: String
    @Binding var maxConcurrentTasks: Int
    let boardMessage: String?
    let boardMessageSeverity: BoardMessageSeverity?

    let onCancel: () -> Void
    let onCreate: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Create Agent")
                .font(.title3.weight(.semibold))

            if let boardMessage, !boardMessage.isEmpty {
                BoardMessageBanner(message: boardMessage, severity: boardMessageSeverity)
            }

            TextField("Name", text: $name)
            TextField("Skills (comma separated)", text: $skills)
            Stepper("Max Concurrent Tasks: \(maxConcurrentTasks)", value: $maxConcurrentTasks, in: 1 ... 20)

            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                Button("Create", action: onCreate)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(18)
        .frame(width: 420)
    }
}

private struct EditAgentSheet: View {
    @Binding var name: String
    @Binding var skills: String
    @Binding var maxConcurrentTasks: Int
    let boardMessage: String?
    let boardMessageSeverity: BoardMessageSeverity?

    let onCancel: () -> Void
    let onSave: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Edit Agent")
                .font(.title3.weight(.semibold))

            if let boardMessage, !boardMessage.isEmpty {
                BoardMessageBanner(message: boardMessage, severity: boardMessageSeverity)
            }

            TextField("Name", text: $name)
            TextField("Skills (comma separated)", text: $skills)
            Stepper("Max Concurrent Tasks: \(maxConcurrentTasks)", value: $maxConcurrentTasks, in: 1 ... 20)

            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                Button("Save", action: onSave)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(18)
        .frame(width: 420)
    }
}

private struct ManualTriageSheet: View {
    @Environment(\.colorScheme) private var colorScheme
    let tasks: [WorkTask]
    let boardMessage: String?
    let boardMessageSeverity: BoardMessageSeverity?
    @Binding var selectedAgentByTaskID: [UUID: UUID]
    let assignAllEligibleCount: Int
    let unassignableTaskCount: Int
    let assignableAgents: (WorkTask) -> [AgentProfile]
    let loadText: (AgentProfile) -> String
    let onAssign: (UUID) -> Void
    let onAssignAll: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Manual Triage")
                .font(.title3.weight(.semibold))

            if let boardMessage, !boardMessage.isEmpty {
                BoardMessageBanner(message: boardMessage, severity: boardMessageSeverity)
            }

            HStack {
                Spacer()
                Button("Assign All Eligible (\(assignAllEligibleCount))", action: onAssignAll)
                    .buttonStyle(.bordered)
                    .disabled(assignAllEligibleCount == 0)
            }

            if unassignableTaskCount > 0 {
                Text("\(unassignableTaskCount) task(s) currently have no eligible agent and will be skipped.")
                    .font(.caption)
                    .foregroundStyle(BoardMessageColorPalette.color(for: .warning, scheme: colorScheme))
            }

            if tasks.isEmpty {
                Text("No tasks waiting for manual triage.")
                    .font(.callout)
                    .foregroundStyle(BoardNeutralTextPalette.color(for: .secondary, scheme: colorScheme))
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(tasks) { task in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(task.title)
                                    .font(.headline)
                                Text("Skills: \(task.requiredSkills.sorted().joined(separator: ", "))")
                                    .font(.caption)
                                    .foregroundStyle(BoardNeutralTextPalette.color(for: .secondary, scheme: colorScheme))

                                let eligibleAgents = assignableAgents(task)

                                if eligibleAgents.isEmpty {
                                    Text("No eligible agents currently available.")
                                        .font(.caption)
                                        .foregroundStyle(BoardSemanticTextPalette.color(for: .error, scheme: colorScheme))
                                } else {
                                    Picker("Assign To", selection: selectionBinding(for: task.id, fallback: eligibleAgents[0].id)) {
                                        ForEach(eligibleAgents) { agent in
                                            Text("\(agent.name) (\(loadText(agent)))")
                                                .tag(agent.id)
                                        }
                                    }

                                    Button("Assign") {
                                        onAssign(task.id)
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .controlSize(.small)
                                }
                            }
                            .padding(10)
                            .background(triageCardBackground, in: RoundedRectangle(cornerRadius: 10))
                        }
                    }
                    .padding(.vertical, 2)
                }
            }

            HStack {
                Spacer()
                Button("Close", action: onClose)
            }
        }
        .padding(18)
        .frame(width: 460, height: 440)
    }

    private func selectionBinding(for taskID: UUID, fallback: UUID) -> Binding<UUID> {
        Binding(
            get: { selectedAgentByTaskID[taskID] ?? fallback },
            set: { selectedAgentByTaskID[taskID] = $0 }
        )
    }

    private var triageCardBackground: Color {
        BoardSurfacePalette.supplementaryCardColor(for: colorScheme)
    }
}

struct BoardMessageColorToken: Equatable {
    let red: Double
    let green: Double
    let blue: Double
    let opacity: Double

    var color: Color {
        Color(red: red, green: green, blue: blue).opacity(opacity)
    }

    var relativeLuminance: Double {
        let linearRed = linearizedComponent(red)
        let linearGreen = linearizedComponent(green)
        let linearBlue = linearizedComponent(blue)
        return (0.2126 * linearRed) + (0.7152 * linearGreen) + (0.0722 * linearBlue)
    }

    func contrastRatio(against other: BoardMessageColorToken) -> Double {
        let lighter = max(relativeLuminance, other.relativeLuminance)
        let darker = min(relativeLuminance, other.relativeLuminance)
        return (lighter + 0.05) / (darker + 0.05)
    }

    private func linearizedComponent(_ value: Double) -> Double {
        if value <= 0.03928 {
            return value / 12.92
        }
        return pow((value + 0.055) / 1.055, 2.4)
    }
}

enum BoardMessageColorPalette {
    static let darkBoardBackground = BoardMessageColorToken(red: 0.10, green: 0.12, blue: 0.16, opacity: 1.0)
    static let lightBoardBackground = BoardMessageColorToken(red: 0.96, green: 0.98, blue: 1.0, opacity: 1.0)

    static func token(for severity: BoardMessageSeverity?, scheme: ColorScheme) -> BoardMessageColorToken {
        let resolvedSeverity = severity ?? .error
        switch (scheme, resolvedSeverity) {
        case (.dark, .info):
            return BoardMessageColorToken(red: 0.42, green: 0.87, blue: 0.96, opacity: 1.0)
        case (.dark, .warning):
            return BoardMessageColorToken(red: 0.94, green: 0.67, blue: 0.22, opacity: 1.0)
        case (.dark, .error):
            return BoardMessageColorToken(red: 1.0, green: 0.64, blue: 0.59, opacity: 1.0)
        case (.light, .info):
            return BoardMessageColorToken(red: 0.00, green: 0.42, blue: 0.56, opacity: 1.0)
        case (.light, .warning):
            return BoardMessageColorToken(red: 0.69, green: 0.35, blue: 0.00, opacity: 1.0)
        case (.light, .error):
            return BoardMessageColorToken(red: 0.74, green: 0.08, blue: 0.08, opacity: 1.0)
        @unknown default:
            return BoardMessageColorToken(red: 0.74, green: 0.08, blue: 0.08, opacity: 1.0)
        }
    }

    static func color(for severity: BoardMessageSeverity?, scheme: ColorScheme) -> Color {
        token(for: severity, scheme: scheme).color
    }
}

enum BoardSurfacePalette {
    static let darkBoardBackgroundStart = BoardMessageColorToken(red: 0.07, green: 0.09, blue: 0.13, opacity: 1.0)
    static let darkBoardBackgroundEnd = BoardMessageColorToken(red: 0.10, green: 0.12, blue: 0.16, opacity: 1.0)
    static let lightBoardBackgroundStart = BoardMessageColorToken(red: 0.96, green: 0.98, blue: 1.0, opacity: 1.0)
    static let lightBoardBackgroundEnd = BoardMessageColorToken(red: 0.93, green: 0.96, blue: 0.99, opacity: 1.0)

    static func detailGradientTokens(for scheme: ColorScheme) -> [BoardMessageColorToken] {
        switch scheme {
        case .dark:
            return [darkBoardBackgroundStart, darkBoardBackgroundEnd]
        case .light:
            return [lightBoardBackgroundStart, lightBoardBackgroundEnd]
        @unknown default:
            return [darkBoardBackgroundStart, darkBoardBackgroundEnd]
        }
    }

    static func columnToken(for status: KanbanStatus, scheme: ColorScheme) -> BoardMessageColorToken {
        switch (scheme, status) {
        case (.dark, .todo):
            return BoardMessageColorToken(red: 0.18, green: 0.27, blue: 0.36, opacity: 1.0)
        case (.dark, .inProgress):
            return BoardMessageColorToken(red: 0.15, green: 0.31, blue: 0.24, opacity: 1.0)
        case (.dark, .review):
            return BoardMessageColorToken(red: 0.34, green: 0.27, blue: 0.17, opacity: 1.0)
        case (.dark, .done):
            return BoardMessageColorToken(red: 0.24, green: 0.25, blue: 0.31, opacity: 1.0)
        case (.light, .todo):
            return BoardMessageColorToken(red: 0.82, green: 0.9, blue: 0.98, opacity: 1.0)
        case (.light, .inProgress):
            return BoardMessageColorToken(red: 0.81, green: 0.94, blue: 0.87, opacity: 1.0)
        case (.light, .review):
            return BoardMessageColorToken(red: 0.99, green: 0.92, blue: 0.77, opacity: 1.0)
        case (.light, .done):
            return BoardMessageColorToken(red: 0.89, green: 0.89, blue: 0.92, opacity: 1.0)
        @unknown default:
            return BoardMessageColorToken(red: 0.24, green: 0.25, blue: 0.31, opacity: 1.0)
        }
    }

    static func taskCardToken(for scheme: ColorScheme) -> BoardMessageColorToken {
        switch scheme {
        case .dark:
            return BoardMessageColorToken(red: 0.11, green: 0.14, blue: 0.19, opacity: 1.0)
        case .light:
            return BoardMessageColorToken(red: 1.0, green: 1.0, blue: 1.0, opacity: 1.0)
        @unknown default:
            return BoardMessageColorToken(red: 0.11, green: 0.14, blue: 0.19, opacity: 1.0)
        }
    }

    static func supplementaryCardToken(for scheme: ColorScheme) -> BoardMessageColorToken {
        switch scheme {
        case .dark:
            return BoardMessageColorToken(red: 0.17, green: 0.20, blue: 0.27, opacity: 1.0)
        case .light:
            return BoardMessageColorToken(red: 1.0, green: 1.0, blue: 1.0, opacity: 0.92)
        @unknown default:
            return BoardMessageColorToken(red: 0.17, green: 0.20, blue: 0.27, opacity: 1.0)
        }
    }

    static func emptyStateToken(for scheme: ColorScheme) -> BoardMessageColorToken {
        switch scheme {
        case .dark:
            return BoardMessageColorToken(red: 0.19, green: 0.23, blue: 0.30, opacity: 1.0)
        case .light:
            return BoardMessageColorToken(red: 1.0, green: 1.0, blue: 1.0, opacity: 0.68)
        @unknown default:
            return BoardMessageColorToken(red: 0.19, green: 0.23, blue: 0.30, opacity: 1.0)
        }
    }

    static func color(for status: KanbanStatus, scheme: ColorScheme) -> Color {
        columnToken(for: status, scheme: scheme).color
    }

    static func taskCardColor(for scheme: ColorScheme) -> Color {
        taskCardToken(for: scheme).color
    }

    static func supplementaryCardColor(for scheme: ColorScheme) -> Color {
        supplementaryCardToken(for: scheme).color
    }

    static func emptyStateColor(for scheme: ColorScheme) -> Color {
        emptyStateToken(for: scheme).color
    }
}

enum BoardChromePalette {
    static func counterToken(for scheme: ColorScheme) -> BoardMessageColorToken {
        switch scheme {
        case .dark:
            return BoardMessageColorToken(red: 0.24, green: 0.29, blue: 0.37, opacity: 1.0)
        case .light:
            return BoardMessageColorToken(red: 0.96, green: 0.97, blue: 0.99, opacity: 1.0)
        @unknown default:
            return BoardMessageColorToken(red: 0.24, green: 0.29, blue: 0.37, opacity: 1.0)
        }
    }

    static func storyPointToken(for scheme: ColorScheme) -> BoardMessageColorToken {
        switch scheme {
        case .dark:
            return BoardMessageColorToken(red: 0.20, green: 0.24, blue: 0.31, opacity: 1.0)
        case .light:
            return BoardMessageColorToken(red: 0.90, green: 0.92, blue: 0.95, opacity: 1.0)
        @unknown default:
            return BoardMessageColorToken(red: 0.20, green: 0.24, blue: 0.31, opacity: 1.0)
        }
    }

    static func columnBorderToken(for scheme: ColorScheme) -> BoardMessageColorToken {
        switch scheme {
        case .dark:
            return BoardMessageColorToken(red: 0.31, green: 0.36, blue: 0.46, opacity: 1.0)
        case .light:
            return BoardMessageColorToken(red: 0.72, green: 0.77, blue: 0.84, opacity: 1.0)
        @unknown default:
            return BoardMessageColorToken(red: 0.31, green: 0.36, blue: 0.46, opacity: 1.0)
        }
    }

    static func taskCardBorderToken(for scheme: ColorScheme) -> BoardMessageColorToken {
        switch scheme {
        case .dark:
            return BoardMessageColorToken(red: 0.30, green: 0.35, blue: 0.44, opacity: 1.0)
        case .light:
            return BoardMessageColorToken(red: 0.72, green: 0.77, blue: 0.84, opacity: 1.0)
        @unknown default:
            return BoardMessageColorToken(red: 0.30, green: 0.35, blue: 0.44, opacity: 1.0)
        }
    }

    static func supplementaryCardBorderToken(for scheme: ColorScheme) -> BoardMessageColorToken {
        switch scheme {
        case .dark:
            return BoardMessageColorToken(red: 0.30, green: 0.35, blue: 0.45, opacity: 1.0)
        case .light:
            return BoardMessageColorToken(red: 0.71, green: 0.76, blue: 0.83, opacity: 1.0)
        @unknown default:
            return BoardMessageColorToken(red: 0.30, green: 0.35, blue: 0.45, opacity: 1.0)
        }
    }

    static func summaryBadgeBorderToken(for scheme: ColorScheme) -> BoardMessageColorToken {
        columnBorderToken(for: scheme)
    }

    static func counterColor(for scheme: ColorScheme) -> Color {
        counterToken(for: scheme).color
    }

    static func storyPointColor(for scheme: ColorScheme) -> Color {
        storyPointToken(for: scheme).color
    }

    static func columnBorderColor(for scheme: ColorScheme) -> Color {
        columnBorderToken(for: scheme).color
    }

    static func taskCardBorderColor(for scheme: ColorScheme) -> Color {
        taskCardBorderToken(for: scheme).color
    }

    static func supplementaryCardBorderColor(for scheme: ColorScheme) -> Color {
        supplementaryCardBorderToken(for: scheme).color
    }

    static func summaryBadgeBorderColor(for scheme: ColorScheme) -> Color {
        summaryBadgeBorderToken(for: scheme).color
    }
}

enum SummaryBadgeAccent: CaseIterable {
    case blue
    case indigo
    case amber
    case red
    case green
    case teal
    case mint
}

enum SummaryBadgePalette {
    static func token(for accent: SummaryBadgeAccent, scheme: ColorScheme) -> BoardMessageColorToken {
        switch (scheme, accent) {
        case (.dark, .blue):
            return BoardMessageColorToken(red: 0.19, green: 0.31, blue: 0.47, opacity: 1.0)
        case (.dark, .indigo):
            return BoardMessageColorToken(red: 0.24, green: 0.26, blue: 0.48, opacity: 1.0)
        case (.dark, .amber):
            return BoardMessageColorToken(red: 0.43, green: 0.30, blue: 0.12, opacity: 1.0)
        case (.dark, .red):
            return BoardMessageColorToken(red: 0.48, green: 0.20, blue: 0.20, opacity: 1.0)
        case (.dark, .green):
            return BoardMessageColorToken(red: 0.20, green: 0.39, blue: 0.28, opacity: 1.0)
        case (.dark, .teal):
            return BoardMessageColorToken(red: 0.16, green: 0.36, blue: 0.36, opacity: 1.0)
        case (.dark, .mint):
            return BoardMessageColorToken(red: 0.15, green: 0.34, blue: 0.29, opacity: 1.0)
        case (.light, .blue):
            return BoardMessageColorToken(red: 0.84, green: 0.92, blue: 0.99, opacity: 1.0)
        case (.light, .indigo):
            return BoardMessageColorToken(red: 0.87, green: 0.89, blue: 0.98, opacity: 1.0)
        case (.light, .amber):
            return BoardMessageColorToken(red: 0.99, green: 0.92, blue: 0.80, opacity: 1.0)
        case (.light, .red):
            return BoardMessageColorToken(red: 0.98, green: 0.86, blue: 0.86, opacity: 1.0)
        case (.light, .green):
            return BoardMessageColorToken(red: 0.86, green: 0.95, blue: 0.89, opacity: 1.0)
        case (.light, .teal):
            return BoardMessageColorToken(red: 0.84, green: 0.95, blue: 0.95, opacity: 1.0)
        case (.light, .mint):
            return BoardMessageColorToken(red: 0.86, green: 0.96, blue: 0.92, opacity: 1.0)
        @unknown default:
            return BoardMessageColorToken(red: 0.19, green: 0.31, blue: 0.47, opacity: 1.0)
        }
    }

    static func color(for accent: SummaryBadgeAccent, scheme: ColorScheme) -> Color {
        token(for: accent, scheme: scheme).color
    }
}

enum BoardSemanticTextRole {
    case success
    case warning
    case error
}

enum BoardSemanticTextPalette {
    static func token(for role: BoardSemanticTextRole, scheme: ColorScheme) -> BoardMessageColorToken {
        switch (scheme, role) {
        case (.dark, .success):
            return BoardMessageColorToken(red: 0.45, green: 0.92, blue: 0.59, opacity: 1.0)
        case (.dark, .warning):
            return BoardMessageColorToken(red: 0.94, green: 0.67, blue: 0.22, opacity: 1.0)
        case (.dark, .error):
            return BoardMessageColorToken(red: 1.0, green: 0.64, blue: 0.59, opacity: 1.0)
        case (.light, .success):
            return BoardMessageColorToken(red: 0.06, green: 0.45, blue: 0.18, opacity: 1.0)
        case (.light, .warning):
            return BoardMessageColorToken(red: 0.69, green: 0.35, blue: 0.00, opacity: 1.0)
        case (.light, .error):
            return BoardMessageColorToken(red: 0.74, green: 0.08, blue: 0.08, opacity: 1.0)
        @unknown default:
            return BoardMessageColorToken(red: 0.74, green: 0.08, blue: 0.08, opacity: 1.0)
        }
    }

    static func color(for role: BoardSemanticTextRole, scheme: ColorScheme) -> Color {
        token(for: role, scheme: scheme).color
    }
}

enum BoardNeutralTextRole {
    case secondary
}

enum BoardNeutralTextPalette {
    static func token(for role: BoardNeutralTextRole, scheme: ColorScheme) -> BoardMessageColorToken {
        switch (scheme, role) {
        case (.dark, .secondary):
            return BoardMessageColorToken(red: 0.82, green: 0.86, blue: 0.92, opacity: 1.0)
        case (.light, .secondary):
            return BoardMessageColorToken(red: 0.28, green: 0.33, blue: 0.42, opacity: 1.0)
        @unknown default:
            return BoardMessageColorToken(red: 0.28, green: 0.33, blue: 0.42, opacity: 1.0)
        }
    }

    static func color(for role: BoardNeutralTextRole, scheme: ColorScheme) -> Color {
        token(for: role, scheme: scheme).color
    }
}

private struct BoardMessageBanner: View {
    @Environment(\.colorScheme) private var colorScheme
    let message: String
    let severity: BoardMessageSeverity?

    var body: some View {
        Text(message)
            .font(.caption)
            .foregroundStyle(BoardMessageColorPalette.color(for: severity, scheme: colorScheme))
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
