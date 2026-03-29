import AppKit
import SwiftUI
import UniformTypeIdentifiers

private struct TaskDragPayload: Codable, Transferable {
    let taskID: UUID

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .openMACTaskDragPayload)
    }
}

private extension UTType {
    // Internal drag payload for in-app transfers; no exported UTI registration needed.
    static let openMACTaskDragPayload = UTType(importedAs: "com.irons.openmac.task-drag-payload")
}

struct ContentView: View {
    @Environment(\.colorScheme) private var systemColorScheme
    @AppStorage("appearanceMode") private var appearanceModeRawValue = AppAppearanceMode.system.rawValue
    @AppStorage(AppLanguageSettings.userDefaultsKey) private var appLanguageOverrideRawValue = AppLanguageSettings.systemValue
    @AppStorage("developerModeEnabled") private var developerModeEnabled = false
    @AppStorage(CodexProjectsDirectorySettings.userDefaultsKey) private var codexProjectsDirectoryPath = ""
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
    @State private var newAgentRuntimeEnabled = false
    @State private var newAgentRuntimeProvider: AgentRuntimeProvider = .localMock
    @State private var newAgentRuntimeModel = ""
    @State private var newAgentRuntimeEndpoint = ""
    @State private var newAgentRuntimeTools = ""
    @State private var newAgentOpenAIAuthMode: OpenAICompatibleAuthMode = .apiKey
    @State private var newAgentCodexProfile = ""
    @State private var editingAgentID: UUID?
    @State private var editAgentName = ""
    @State private var editAgentSkills = ""
    @State private var editAgentCapacity = 3
    @State private var editAgentRuntimeEnabled = false
    @State private var editAgentRuntimeProvider: AgentRuntimeProvider = .localMock
    @State private var editAgentRuntimeModel = ""
    @State private var editAgentRuntimeEndpoint = ""
    @State private var editAgentRuntimeTools = ""
    @State private var editAgentOpenAIAuthMode: OpenAICompatibleAuthMode = .apiKey
    @State private var editAgentCodexProfile = ""
    @State private var inProgressWIPLimitDraft = 1
    @State private var reviewWIPLimitDraft = 1
    @State private var triageSelectionByTaskID: [UUID: UUID] = [:]
    @State private var taskSearchQuery = ""
    @State private var globalTaskSearchQuery = ""
    @State private var selectedAssigneeFilterKey = "all"
    @State private var selectedExecutionDetails: ExecutionDetailsPresentation?
    @State private var isBatchRunning = false
    @State private var selectedAgentConsoleAgentID: UUID?

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
                        runtimeText: runtimeSummary(for: agent),
                        loadCount: viewModel.activeTaskCount(for: agent.id),
                        maxLoad: agent.maxConcurrentTasks,
                        loadPercent: viewModel.loadPercent(for: agent.id),
                        loadProgress: min(1.0, viewModel.loadRatio(for: agent.id)),
                        isOverloaded: viewModel.isAgentOverloaded(agent.id),
                        isRunning: viewModel.isAgentExecutionRunning(agent.id),
                        recentEventMessage: viewModel.executionEvents(for: agent.id, limit: 1).first?.message,
                        isSelected: selectedAgentConsoleAgentID == agent.id
                    )
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectedAgentConsoleAgentID = agent.id
                    }
                    .listRowBackground(
                        selectedAgentConsoleAgentID == agent.id
                            ? BoardSurfacePalette.supplementaryCardColor(for: effectiveColorScheme)
                            : Color.clear
                    )
                    .contextMenu {
                        Button(L10n.string("Edit Agent")) {
                            openEditAgent(agent)
                        }
                        Button(L10n.string("Unassign Todo Tasks")) {
                            unassignTodoTasks(for: agent.id)
                        }
                        .disabled(!hasAssignedTodoTasks(for: agent.id))
                        Button(L10n.string("Remove Agent"), role: .destructive) {
                            removeAgent(agent.id)
                        }
                    }
                }
                .onDelete(perform: deleteAgents)
            }
            .navigationTitle(L10n.string("AI Agents"))
        } detail: {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.string("AI Agent Kanban Dispatch"))
                            .font(.title2.weight(.semibold))
                        Text(L10n.format("Board: %@", viewModel.selectedBoardName))
                            .font(.caption)
                            .foregroundStyle(BoardNeutralTextPalette.color(for: .secondary, scheme: effectiveColorScheme))
                    }
                    Spacer()
                    if !viewModel.triageCandidates().isEmpty {
                        Text(L10n.format("%d task(s) need manual triage", viewModel.triageCandidates().count))
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
                    TextField(L10n.string("Search tasks"), text: $taskSearchQuery)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 300)

                    Picker(L10n.string("Assignee"), selection: $selectedAssigneeFilterKey) {
                        ForEach(assigneeFilterOptions, id: \.key) { option in
                            Text(option.label).tag(option.key)
                        }
                    }
                    .pickerStyle(.menu)

                    Text(L10n.format("Showing %d / %d", filteredTaskCount, viewModel.tasks.count))
                        .font(.caption)
                        .foregroundStyle(BoardNeutralTextPalette.color(for: .secondary, scheme: effectiveColorScheme))

                    Button(L10n.string("Reset Filters")) {
                        resetTaskFilters()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(taskSearchQuery.isEmpty && selectedAssigneeFilterKey == "all")

                    Spacer()
                }

                if let message = viewModel.lastBoardMessage {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(message)
                                .font(.callout)
                                .foregroundStyle(
                                    BoardMessageColorPalette.color(
                                        for: viewModel.lastBoardMessageSeverity,
                                        scheme: effectiveColorScheme
                                    )
                                )
                                .textSelection(.enabled)
                            if developerModeEnabled {
                                Spacer()
                                Button(L10n.string("Copy")) {
                                    copyToPasteboard(message)
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                        }

                        if developerModeEnabled,
                           let loginCommand = viewModel.lastCodexLoginCommand,
                           !loginCommand.isEmpty {
                           HStack {
                                Text(L10n.string("Codex Login Command"))
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(BoardNeutralTextPalette.color(for: .secondary, scheme: effectiveColorScheme))
                                Spacer()
                                Button(L10n.string("Copy Command")) {
                                    copyToPasteboard(loginCommand)
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }

                            Text(loginCommand)
                                .font(.caption.monospaced())
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(10)
                                .background(
                                    BoardSurfacePalette.supplementaryCardColor(for: effectiveColorScheme),
                                    in: RoundedRectangle(cornerRadius: 10)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(
                                            BoardChromePalette.supplementaryCardBorderColor(for: effectiveColorScheme),
                                            lineWidth: 1
                                        )
                                )
                        }

                        if developerModeEnabled,
                           let debugLog = viewModel.lastExecutionDebugLog,
                           !debugLog.isEmpty {
                           HStack {
                                Text(L10n.string("Execution Debug Log"))
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(BoardNeutralTextPalette.color(for: .secondary, scheme: effectiveColorScheme))
                                Spacer()
                                Button(L10n.string("Copy Log")) {
                                    copyToPasteboard(debugLog)
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }

                            ScrollView {
                                Text(debugLog)
                                    .font(.caption.monospaced())
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .frame(maxHeight: 190)
                            .padding(10)
                            .background(
                                BoardSurfacePalette.supplementaryCardColor(for: effectiveColorScheme),
                                in: RoundedRectangle(cornerRadius: 10)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(
                                        BoardChromePalette.supplementaryCardBorderColor(for: effectiveColorScheme),
                                        lineWidth: 1
                                    )
                            )
                        }
                    }
                }

                if let selectedAgent = selectedAgentForConsole {
                    AgentLiveConsoleView(
                        agentName: selectedAgent.name,
                        isRunning: viewModel.isAgentExecutionRunning(selectedAgent.id),
                        events: viewModel.executionEvents(for: selectedAgent.id),
                        onCopy: copyToPasteboard,
                        onClear: {
                            viewModel.clearExecutionEvents(for: selectedAgent.id)
                        }
                    )
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
                                onRunTaskExecution: runTaskExecution,
                                onRetryTaskExecution: retryTaskExecution,
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
                                onShowExecutionDetails: openExecutionDetails,
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
                Button(L10n.string("Auto Assign AI")) {
                    runAutoAssignFromToolbar()
                }
                .keyboardShortcut("a", modifiers: [.command, .shift])
                .help(L10n.string("Auto-assign all eligible To Do tasks (Shift-Command-A)"))
                .disabled(!canAutoAssignFromToolbar)
                Button(isBatchRunning ? L10n.string("Running...") : L10n.string("Run Assigned")) {
                    runAssignedExecutionsFromToolbar()
                }
                .keyboardShortcut("g", modifiers: [.command, .shift])
                .help(L10n.string("Batch-run assigned To Do/In Progress tasks (Shift-Command-G)"))
                .disabled(!canBatchRunAssignedTasks)
                Button(L10n.string("New Task")) {
                    isShowingNewTaskSheet = true
                }
                .keyboardShortcut("n", modifiers: [.command])
                .help(L10n.string("Create a new task (Command-N)"))
                Button(L10n.string("New Agent")) {
                    isShowingNewAgentSheet = true
                }
                .keyboardShortcut("n", modifiers: [.command, .option])
                .help(L10n.string("Create a new agent profile (Option-Command-N)"))
                Button(L10n.string("Find Task")) {
                    openGlobalTaskFinder()
                }
                .keyboardShortcut("f", modifiers: [.command])
                .help(L10n.string("Search tasks across boards (Command-F)"))
                Menu(L10n.format("Board: %@", viewModel.selectedBoardName)) {
                    Button(L10n.string("New Board")) {
                        openNewBoardSheet()
                    }
                    .keyboardShortcut("b", modifiers: [.command, .option])

                    Button(L10n.string("Rename Current Board")) {
                        openRenameBoardSheet()
                    }
                    .disabled(viewModel.boards.isEmpty)

                    Button(L10n.string("Delete Current Board")) {
                        isShowingDeleteBoardAlert = true
                    }
                    .disabled(viewModel.boards.count <= 1)

                    Button(L10n.string("Duplicate Current Board")) {
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
                .help(L10n.string("Create a board or switch board context"))
                Menu(L10n.string("Board Actions")) {
                    Section(L10n.string("Health")) {
                        if viewModel.hasAutoFixableHealthRecommendations {
                            Button(L10n.format("Apply Health Fixes (%d)", viewModel.autoFixableHealthRecommendationCount)) {
                                applyAllHealthRecommendations()
                            }
                            .keyboardShortcut("h", modifiers: [.command, .shift])
                        } else {
                            Text(L10n.string("No health fixes available"))
                        }
                    }

                    Section(L10n.string("Board")) {
                        Button(isBatchRunning ? L10n.string("Running Assigned Tasks...") : L10n.string("Run Assigned Tasks")) {
                            runAssignedExecutionsFromToolbar()
                        }
                        .disabled(!canBatchRunAssignedTasks)

                        Divider()

                        Button(L10n.string("Archive Done")) {
                            archiveDoneTasks()
                        }
                        .keyboardShortcut("d", modifiers: [.command, .shift])
                        .disabled(viewModel.tasks(in: .done).isEmpty)

                        Button(L10n.string("Rebalance Load")) {
                            rebalanceTodoAssignments()
                        }
                        .keyboardShortcut("r", modifiers: [.command, .shift])
                        .disabled(!viewModel.canRebalanceTodoAssignments())

                        Button(L10n.string("WIP Limits")) {
                            openWIPSettings()
                        }
                        .keyboardShortcut("l", modifiers: [.command, .shift])

                        Button(L10n.string("Manual Triage")) {
                            openManualTriage()
                        }
                        .keyboardShortcut("t", modifiers: [.command, .shift])
                        .disabled(viewModel.triageCandidates().isEmpty)

                        Divider()

                        Button(L10n.string("Export Current Board JSON...")) {
                            exportSelectedBoardFromToolbar()
                        }
                        .keyboardShortcut("e", modifiers: [.command, .shift, .option])

                        Button(L10n.string("Export Workspace JSON...")) {
                            exportWorkspaceFromToolbar()
                        }
                        .keyboardShortcut("e", modifiers: [.command, .shift])

                        Button(L10n.string("Import Workspace JSON...")) {
                            importWorkspaceFromToolbar()
                        }
                        .keyboardShortcut("i", modifiers: [.command, .shift])

                        Divider()

                        Button(L10n.string("Rename Board")) {
                            openRenameBoardSheet()
                        }
                        .disabled(viewModel.boards.isEmpty)

                        Button(L10n.string("Delete Board")) {
                            isShowingDeleteBoardAlert = true
                        }
                        .disabled(viewModel.boards.count <= 1)

                        Button(L10n.string("Duplicate Board")) {
                            duplicateSelectedBoard()
                        }
                        .disabled(viewModel.boards.isEmpty)
                    }
                }
                .help(L10n.string("Archive, rebalance, WIP settings, and manual triage actions"))
                Menu(L10n.format("Appearance: %@", selectedAppearanceMode.title)) {
                    Button(L10n.string("Cycle Appearance")) {
                        cycleAppearanceMode()
                    }
                    .keyboardShortcut("`", modifiers: [.command, .option])

                    Divider()

                    ForEach(AppAppearanceMode.allCases) { mode in
                        appearanceMenuButton(for: mode)
                    }
                }
                .help(L10n.string("Switch between system, light, and dark appearance (Option-Command-`/0/L/D)"))
                Menu(L10n.format("Language: %@", selectedLanguageLabel)) {
                    languageSelectionButton(for: nil)

                    Divider()

                    ForEach(AppLanguage.allCases, id: \.rawValue) { language in
                        languageSelectionButton(for: language)
                    }
                }
                .help(L10n.string("Switch app language or follow system default"))
                Menu(L10n.string("Developer")) {
                    Toggle(L10n.string("Developer Mode"), isOn: $developerModeEnabled)
                    Divider()
                    Text(L10n.string("Projects Folder"))
                    Text(resolvedCodexProjectsDirectoryPath)
                        .font(.caption2.monospaced())
                    Button(L10n.string("Choose Projects Folder...")) {
                        chooseCodexProjectsDirectory()
                    }
                    Button(L10n.string("Use Default Projects Folder")) {
                        useDefaultCodexProjectsDirectory()
                    }
                    .disabled(isUsingDefaultCodexProjectsDirectory)
                    Button(L10n.string("Open Projects Folder in Finder")) {
                        openCodexProjectsDirectoryInFinder()
                    }
                    Button(L10n.string("Copy Projects Folder Path")) {
                        copyToPasteboard(resolvedCodexProjectsDirectoryPath)
                    }
                    if let message = viewModel.lastBoardMessage, !message.isEmpty {
                        Button(L10n.string("Copy Board Message")) {
                            copyToPasteboard(message)
                        }
                    }
                    if let debugLog = viewModel.lastExecutionDebugLog, !debugLog.isEmpty {
                        Button(L10n.string("Copy Last Debug Log")) {
                            copyToPasteboard(debugLog)
                        }
                    }
                    if let loginCommand = viewModel.lastCodexLoginCommand, !loginCommand.isEmpty {
                        Button(L10n.string("Copy Codex Login Command")) {
                            copyToPasteboard(loginCommand)
                        }
                    }
                }
                .help(L10n.string("Enable developer diagnostics and quick-copy execution logs"))
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
                runtimeEnabled: $newAgentRuntimeEnabled,
                runtimeProvider: $newAgentRuntimeProvider,
                runtimeModel: $newAgentRuntimeModel,
                runtimeEndpoint: $newAgentRuntimeEndpoint,
                runtimeTools: $newAgentRuntimeTools,
                openAIAuthMode: $newAgentOpenAIAuthMode,
                codexProfile: $newAgentCodexProfile,
                boardMessage: viewModel.lastBoardMessage,
                boardMessageSeverity: viewModel.lastBoardMessageSeverity,
                onCancel: resetAgentDraftAndClose,
                onCreate: {
                    let added = viewModel.addAgent(
                        name: newAgentName,
                        skillsText: newAgentSkills,
                        maxConcurrentTasks: newAgentCapacity,
                        runtimeProfile: buildRuntimeProfile(
                            isEnabled: newAgentRuntimeEnabled,
                            provider: newAgentRuntimeProvider,
                            model: newAgentRuntimeModel,
                            endpoint: newAgentRuntimeEndpoint,
                            toolsText: newAgentRuntimeTools,
                            openAIAuthMode: newAgentOpenAIAuthMode,
                            codexProfile: newAgentCodexProfile
                        )
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
                runtimeEnabled: $editAgentRuntimeEnabled,
                runtimeProvider: $editAgentRuntimeProvider,
                runtimeModel: $editAgentRuntimeModel,
                runtimeEndpoint: $editAgentRuntimeEndpoint,
                runtimeTools: $editAgentRuntimeTools,
                openAIAuthMode: $editAgentOpenAIAuthMode,
                codexProfile: $editAgentCodexProfile,
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
        .sheet(item: $selectedExecutionDetails) { details in
            ExecutionDetailsSheet(
                details: details,
                onCopy: copyToPasteboard,
                onClose: { selectedExecutionDetails = nil }
            )
        }
        .onAppear {
            L10n.setRuntimeLocale(
                AppLanguageResolver.resolvedLocale(overrideRawValue: appLanguageOverrideRawValue)
            )
            syncSelectedAgentConsoleSelection()
            ensureCodexProjectsDirectoryExists()
        }
        .onChange(of: appLanguageOverrideRawValue) { _, newValue in
            L10n.setRuntimeLocale(
                AppLanguageResolver.resolvedLocale(overrideRawValue: newValue)
            )
        }
        .onChange(of: viewModel.agents) { _, _ in
            normalizeAssigneeFilterSelection()
            syncSelectedAgentConsoleSelection()
        }
        .onChange(of: viewModel.selectedBoardID) { _, _ in
            handleBoardContextChanged()
        }
        .alert(L10n.string("Delete Board?"), isPresented: $isShowingDeleteBoardAlert) {
            Button(L10n.string("Cancel"), role: .cancel) {}
            Button(L10n.string("Delete"), role: .destructive) {
                removeSelectedBoard()
            }
        } message: {
            Text(L10n.format("Delete \"%@\" and all tasks/agents in it? This cannot be undone.", viewModel.selectedBoardName))
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

    private func copyToPasteboard(_ value: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(value, forType: .string)
    }

    private func openExecutionDetails(_ task: WorkTask) {
        guard let executionRecord = task.executionRecord else { return }
        selectedExecutionDetails = ExecutionDetailsPresentation(
            taskTitle: task.title,
            assigneeName: viewModel.agentName(for: task.assignedAgentID),
            executionRecord: executionRecord
        )
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
        newAgentRuntimeEnabled = false
        newAgentRuntimeProvider = .localMock
        newAgentRuntimeModel = ""
        newAgentRuntimeEndpoint = ""
        newAgentRuntimeTools = ""
        newAgentOpenAIAuthMode = .apiKey
        newAgentCodexProfile = ""
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
        syncSelectedAgentConsoleSelection()
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

    private func runAssignedExecutionsFromToolbar() {
        guard !isBatchRunning else { return }
        isBatchRunning = true
        viewModel.runAssignedTaskExecutionsInBackground { startedCount in
            isBatchRunning = false
            if startedCount > 0 {
                refreshTriageSelections()
            }
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
        panel.title = L10n.string("Export Workspace")
        panel.message = L10n.string("Save boards, tasks, and agents as workspace JSON.")

        guard panel.runModal() == .OK, let url = panel.url else { return }
        _ = viewModel.exportWorkspace(to: url)
    }

    private func exportSelectedBoardFromToolbar() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType.json]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.nameFieldStringValue = selectedBoardExportFileName()
        panel.title = L10n.string("Export Current Board")
        panel.message = L10n.string("Save only the current board as JSON.")

        guard panel.runModal() == .OK, let url = panel.url else { return }
        _ = viewModel.exportSelectedBoard(to: url)
    }

    private func importWorkspaceFromToolbar() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.title = L10n.string("Import Workspace")
        panel.message = L10n.string("Select workspace JSON to import.")

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
        alert.messageText = L10n.string("Import Workspace")
        alert.informativeText = L10n.format(
            """
            Boards: %d
            Tasks: %d
            Agents: %d

            Merge keeps current boards and appends imported boards.
            Replace overwrites current workspace with imported boards.
            """,
            preview.boardCount,
            preview.taskCount,
            preview.agentCount
        )
        alert.addButton(withTitle: L10n.string("Merge"))
        alert.addButton(withTitle: L10n.string("Replace"))
        alert.addButton(withTitle: L10n.string("Cancel"))

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

    private func runTaskExecution(_ taskID: UUID) {
        viewModel.runTaskExecutionInBackground(taskID) { executed in
            if executed {
                refreshTriageSelections()
            }
        }
    }

    private func retryTaskExecution(_ taskID: UUID) {
        viewModel.retryTaskExecutionInBackground(taskID) { retried in
            if retried {
                refreshTriageSelections()
            }
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
        editAgentRuntimeEnabled = agent.runtimeProfile != nil
        editAgentRuntimeProvider = agent.runtimeProfile?.provider ?? .localMock
        editAgentRuntimeModel = agent.runtimeProfile?.model ?? ""
        editAgentRuntimeEndpoint = agent.runtimeProfile?.endpoint ?? ""
        editAgentRuntimeTools = agent.runtimeProfile?.tools.sorted().joined(separator: ", ") ?? ""
        editAgentOpenAIAuthMode = agent.runtimeProfile?.openAIAuthMode ?? .apiKey
        editAgentCodexProfile = agent.runtimeProfile?.codexProfile ?? ""
        isShowingEditAgentSheet = true
    }

    private func closeEditAgentSheet() {
        editingAgentID = nil
        editAgentName = ""
        editAgentSkills = ""
        editAgentCapacity = 3
        editAgentRuntimeEnabled = false
        editAgentRuntimeProvider = .localMock
        editAgentRuntimeModel = ""
        editAgentRuntimeEndpoint = ""
        editAgentRuntimeTools = ""
        editAgentOpenAIAuthMode = .apiKey
        editAgentCodexProfile = ""
        isShowingEditAgentSheet = false
    }

    private func applyAgentEdits() {
        guard let editingAgentID else { return }

        let updated = viewModel.updateAgent(
            editingAgentID,
            name: editAgentName,
            skillsText: editAgentSkills,
            maxConcurrentTasks: editAgentCapacity,
            runtimeProfile: buildRuntimeProfile(
                isEnabled: editAgentRuntimeEnabled,
                provider: editAgentRuntimeProvider,
                model: editAgentRuntimeModel,
                endpoint: editAgentRuntimeEndpoint,
                toolsText: editAgentRuntimeTools,
                openAIAuthMode: editAgentOpenAIAuthMode,
                codexProfile: editAgentCodexProfile
            )
        )

        if updated {
            refreshTriageSelections()
            closeEditAgentSheet()
        }
    }

    private var assigneeFilterOptions: [(key: String, label: String)] {
        let base = [
            (key: "all", label: L10n.string("All Assignees")),
            (key: "unassigned", label: L10n.string("Unassigned"))
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

    private var selectedAgentForConsole: AgentProfile? {
        guard let selectedAgentConsoleAgentID else {
            return viewModel.agents.first
        }
        return viewModel.agents.first(where: { $0.id == selectedAgentConsoleAgentID }) ?? viewModel.agents.first
    }

    private var resolvedCodexProjectsDirectoryPath: String {
        CodexProjectsDirectorySettings.resolvedProjectsDirectoryPath()
    }

    private var isUsingDefaultCodexProjectsDirectory: Bool {
        codexProjectsDirectoryPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var globalTaskSearchResults: [GlobalTaskSearchResult] {
        viewModel.globalTaskSearchResults(query: globalTaskSearchQuery)
    }

    private func resetTaskFilters() {
        taskSearchQuery = ""
        selectedAssigneeFilterKey = "all"
    }

    private func chooseCodexProjectsDirectory() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.title = L10n.string("Choose Projects Folder")
        panel.message = L10n.string("Select a default working folder for agent project execution.")
        panel.prompt = L10n.string("Use Folder")
        panel.directoryURL = URL(fileURLWithPath: resolvedCodexProjectsDirectoryPath, isDirectory: true)

        guard panel.runModal() == .OK, let url = panel.url else { return }
        codexProjectsDirectoryPath = url.path
        ensureCodexProjectsDirectoryExists()
    }

    private func useDefaultCodexProjectsDirectory() {
        codexProjectsDirectoryPath = ""
        ensureCodexProjectsDirectoryExists()
    }

    private func openCodexProjectsDirectoryInFinder() {
        do {
            let url = try CodexProjectsDirectorySettings.ensureProjectsDirectoryExists(
                at: resolvedCodexProjectsDirectoryPath
            )
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } catch {
            presentCodexProjectsDirectoryError(error, attemptedPath: resolvedCodexProjectsDirectoryPath)
        }
    }

    private func ensureCodexProjectsDirectoryExists() {
        do {
            _ = try CodexProjectsDirectorySettings.ensureProjectsDirectoryExists(
                at: resolvedCodexProjectsDirectoryPath
            )
        } catch {
            presentCodexProjectsDirectoryError(error, attemptedPath: resolvedCodexProjectsDirectoryPath)
        }
    }

    private func presentCodexProjectsDirectoryError(_ error: Error, attemptedPath: String) {
        let alert = NSAlert()
        alert.messageText = L10n.string("Projects Folder Error")
        alert.informativeText = L10n.format(
            "Could not use folder:\n%@\n\n%@",
            attemptedPath,
            error.localizedDescription
        )
        alert.alertStyle = .warning
        alert.addButton(withTitle: L10n.string("OK"))
        alert.runModal()
    }

    private func syncSelectedAgentConsoleSelection() {
        guard !viewModel.agents.isEmpty else {
            selectedAgentConsoleAgentID = nil
            return
        }

        if let selectedAgentConsoleAgentID,
           viewModel.agents.contains(where: { $0.id == selectedAgentConsoleAgentID }) {
            return
        }

        selectedAgentConsoleAgentID = viewModel.agents.first?.id
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

    private var canBatchRunAssignedTasks: Bool {
        guard !isBatchRunning else { return false }
        return viewModel.tasks.contains { task in
            guard (task.status == .todo || task.status == .inProgress),
                  task.assignedAgentID != nil else {
                return false
            }
            return !task.details.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private func runtimeSummary(for agent: AgentProfile) -> String {
        guard let runtimeProfile = agent.runtimeProfile else {
            return L10n.string("Runtime: Disabled")
        }
        if runtimeProfile.provider == .openAICompatible {
            return L10n.format(
                "Runtime: %@ / %@ / %@",
                runtimeProfile.provider.displayName,
                runtimeProfile.model,
                runtimeProfile.openAIAuthMode.displayName
            )
        }
        return L10n.format(
            "Runtime: %@ / %@",
            runtimeProfile.provider.displayName,
            runtimeProfile.model
        )
    }

    private func buildRuntimeProfile(
        isEnabled: Bool,
        provider: AgentRuntimeProvider,
        model: String,
        endpoint: String,
        toolsText: String,
        openAIAuthMode: OpenAICompatibleAuthMode,
        codexProfile: String
    ) -> AgentRuntimeProfile? {
        guard isEnabled else { return nil }
        let resolvedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        let parsedTools = toolsText
            .split(separator: ",")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let resolvedOpenAIAuthMode: OpenAICompatibleAuthMode = provider == .openAICompatible ? openAIAuthMode : .apiKey
        let resolvedEndpoint = provider == .openAICompatible && resolvedOpenAIAuthMode == .apiKey ? endpoint : ""
        let resolvedCodexProfile = provider == .openAICompatible && resolvedOpenAIAuthMode == .codexBridge ? codexProfile : ""
        return AgentRuntimeProfile(
            provider: provider,
            model: resolvedModel.isEmpty ? provider.defaultModel : resolvedModel,
            endpoint: resolvedEndpoint,
            tools: parsedTools,
            openAIAuthMode: resolvedOpenAIAuthMode,
            codexProfile: resolvedCodexProfile
        )
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

    private var selectedLanguagePreference: AppLanguagePreference {
        AppLanguagePreference(rawValue: appLanguageOverrideRawValue)
    }

    private var selectedLanguageLabel: String {
        switch selectedLanguagePreference {
        case .system:
            return L10n.string("System Default")
        case let .language(language):
            return L10n.string(language.displayNameKey)
        }
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

    private func languageSelectionButton(for language: AppLanguage?) -> some View {
        Button {
            appLanguageOverrideRawValue = language?.rawValue ?? AppLanguageSettings.systemValue
        } label: {
            if isSelectedLanguage(language) {
                Label(languageLabel(for: language), systemImage: "checkmark")
            } else {
                Text(languageLabel(for: language))
            }
        }
    }

    private func isSelectedLanguage(_ language: AppLanguage?) -> Bool {
        switch (selectedLanguagePreference, language) {
        case (.system, nil):
            return true
        case let (.language(selectedLanguage), .some(language)):
            return selectedLanguage == language
        default:
            return false
        }
    }

    private func languageLabel(for language: AppLanguage?) -> String {
        guard let language else {
            return L10n.string("System Default")
        }
        return L10n.string(language.displayNameKey)
    }
}

private struct AgentRowView: View {
    @Environment(\.colorScheme) private var colorScheme
    let name: String
    let skillsText: String
    let runtimeText: String
    let loadCount: Int
    let maxLoad: Int
    let loadPercent: Int
    let loadProgress: Double
    let isOverloaded: Bool
    let isRunning: Bool
    let recentEventMessage: String?
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(name)
                .font(.headline)
            Text(L10n.format("Skills: %@", skillsText))
                .font(.caption)
                .foregroundStyle(BoardNeutralTextPalette.color(for: .secondary, scheme: colorScheme))
            Text(runtimeText)
                .font(.caption2)
                .foregroundStyle(BoardNeutralTextPalette.color(for: .secondary, scheme: colorScheme))
            HStack(spacing: 8) {
                ProgressView(value: loadProgress, total: 1.0)
                    .progressViewStyle(.linear)
                Text(L10n.format("%d%%", loadPercent))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(BoardNeutralTextPalette.color(for: .secondary, scheme: colorScheme))
            }
            Text(L10n.format("Load: %d/%d", loadCount, maxLoad))
                .font(.caption2)
                .foregroundStyle(
                    isOverloaded
                        ? BoardSemanticTextPalette.color(for: .error, scheme: colorScheme)
                        : BoardNeutralTextPalette.color(for: .secondary, scheme: colorScheme)
                )
            if isOverloaded {
                Text(L10n.string("Overloaded"))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(BoardSemanticTextPalette.color(for: .error, scheme: colorScheme))
            }
            if isRunning {
                Text(L10n.string("Live: Running"))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(BoardSemanticTextPalette.color(for: .warning, scheme: colorScheme))
            } else if let recentEventMessage, !recentEventMessage.isEmpty {
                Text(L10n.format("Last: %@", recentEventMessage))
                    .font(.caption2)
                    .foregroundStyle(BoardNeutralTextPalette.color(for: .secondary, scheme: colorScheme))
                    .lineLimit(1)
            }
        }
        .padding(8)
        .background(
            isSelected ? BoardSurfacePalette.supplementaryCardColor(for: colorScheme) : Color.clear,
            in: RoundedRectangle(cornerRadius: 10)
        )
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
                SummaryBadge(title: L10n.string("Total"), value: "\(totalTasks)", accent: .blue)
                SummaryBadge(title: L10n.string("To Do"), value: "\(todoTasks)", accent: .indigo)
                SummaryBadge(title: L10n.string("Unassigned"), value: "\(unassignedTodoTasks)", accent: .amber)
                SummaryBadge(title: L10n.string("Overloaded"), value: "\(overloadedAgents)", accent: overloadedAgents > 0 ? .red : .green)
                SummaryBadge(
                    title: L10n.string("Health"),
                    value: L10n.format("%d %@", healthScore, L10n.string(healthLabel)),
                    accent: healthScoreAccent,
                    helpText: healthBreakdownText
                )
                SummaryBadge(title: L10n.string("In Progress WIP"), value: "\(inProgressPressure)%", accent: inProgressPressure >= 100 ? .red : .teal)
                SummaryBadge(title: L10n.string("Review WIP"), value: "\(reviewPressure)%", accent: reviewPressure >= 100 ? .red : .mint)
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
                Text(L10n.string("Board health looks stable. No immediate actions recommended."))
                    .font(.caption)
                    .foregroundStyle(BoardSemanticTextPalette.color(for: .success, scheme: colorScheme))
            } else {
                HStack {
                    Text(L10n.string("Suggested Actions"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(BoardNeutralTextPalette.color(for: .secondary, scheme: colorScheme))
                    Spacer()
                    if autoFixRecommendationCount > 0 {
                        Button(L10n.format("Apply All (%d)", autoFixRecommendationCount)) {
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
    let onRunTaskExecution: (UUID) -> Void
    let onRetryTaskExecution: (UUID) -> Void
    let assignableAgents: (WorkTask) -> [AgentProfile]
    let reassignableAgents: (WorkTask) -> [AgentProfile]
    let onManualAssignTask: (UUID, UUID) -> Void
    let onReassignTask: (UUID, UUID) -> Void
    let moveToBoardTargets: [KanbanBoardRecord]
    let onMoveTaskToBoard: (UUID, UUID) -> Void
    let onCopyTaskToBoard: (UUID, UUID) -> Void
    let onShowExecutionDetails: (WorkTask) -> Void
    let onDropTask: (UUID) -> Bool

    @State private var isDropTarget = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(L10n.string(status.title))
                    .font(.headline)
                Spacer()
                if let wipLimit {
                    Text(L10n.format("%d/%d", tasks.count, wipLimit))
                        .font(.caption)
                        .foregroundStyle(tasks.count >= wipLimit ? BoardSemanticTextPalette.color(for: .error, scheme: colorScheme) : .primary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(counterBackground, in: Capsule())
                } else {
                    Text(String(tasks.count))
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(counterBackground, in: Capsule())
                }
            }

            if tasks.isEmpty {
                Text(L10n.string("No tasks"))
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
                        canRunAgent: task.assignedAgentID != nil && task.status != .done,
                        canRetryAgent: task.assignedAgentID != nil && task.executionRecord?.status == .failed && task.status != .done,
                        executionRecord: task.executionRecord,
                        manualAssignableAgents: assignableAgents(task),
                        reassignableAgents: reassignableAgents(task),
                        moveToBoardTargets: moveToBoardTargets,
                        onEdit: { onEditTask(task) },
                        onAutoAssign: { onAutoAssignTask(task.id) },
                        onRunAgent: { onRunTaskExecution(task.id) },
                        onRetryAgent: { onRetryTaskExecution(task.id) },
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
                        onShowExecutionDetails: {
                            onShowExecutionDetails(task)
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
        .dropDestination(for: TaskDragPayload.self) { items, _ in
            guard let payload = items.first else { return false }
            return onDropTask(payload.taskID)
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
    let canRunAgent: Bool
    let canRetryAgent: Bool
    let executionRecord: TaskExecutionRecord?
    let manualAssignableAgents: [AgentProfile]
    let reassignableAgents: [AgentProfile]
    let moveToBoardTargets: [KanbanBoardRecord]
    let onEdit: () -> Void
    let onAutoAssign: () -> Void
    let onRunAgent: () -> Void
    let onRetryAgent: () -> Void
    let onManualAssign: (UUID) -> Void
    let onReassign: (UUID) -> Void
    let onUnassign: () -> Void
    let onDuplicate: () -> Void
    let onDelete: () -> Void
    let onMoveToBoard: (UUID) -> Void
    let onCopyToBoard: (UUID) -> Void
    let onShowExecutionDetails: () -> Void
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
                Text(L10n.format("Skills: %@", task.requiredSkills.sorted().joined(separator: ", ")))
                    .font(.caption)
                    .foregroundStyle(BoardNeutralTextPalette.color(for: .secondary, scheme: colorScheme))
            }

            HStack {
                Text(L10n.format("SP: %d", task.storyPoints))
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
                Text(L10n.format("Dispatch: %@", assignmentReason))
                    .font(.caption2)
                    .foregroundStyle(BoardNeutralTextPalette.color(for: .secondary, scheme: colorScheme))
                    .lineLimit(3)
            }

            if let executionRecord {
                HStack(spacing: 8) {
                    Text(L10n.format("Runs: %d", executionRecord.runCount))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(BoardNeutralTextPalette.color(for: .secondary, scheme: colorScheme))
                    Text(executionStatusLabel(for: executionRecord.status))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(executionStatusColor(for: executionRecord.status))
                    Spacer(minLength: 0)
                    if executionRecord.lastOutputSummary != nil || executionRecord.lastError != nil {
                        Button(L10n.string("Details")) {
                            onShowExecutionDetails()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                    }
                }

                if let output = executionRecord.lastOutputSummary, executionRecord.status == .succeeded {
                    Text(L10n.format("Output: %@", normalizedExecutionSummaryForDisplay(output)))
                        .font(.caption2)
                        .foregroundStyle(BoardSemanticTextPalette.color(for: .success, scheme: colorScheme))
                        .lineLimit(3)
                        .textSelection(.enabled)
                } else if let lastError = executionRecord.lastError, executionRecord.status == .failed {
                    Text(L10n.format("Error: %@", lastError))
                        .font(.caption2)
                        .foregroundStyle(BoardSemanticTextPalette.color(for: .error, scheme: colorScheme))
                        .lineLimit(3)
                        .textSelection(.enabled)
                }
            }

            HStack(spacing: 8) {
                if canMoveBackward {
                    Button {
                        onMoveBackward()
                    } label: {
                        Label(L10n.string("Back"), systemImage: "arrow.left")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                if canMoveForward {
                    Button {
                        onMoveForward()
                    } label: {
                        Label(L10n.string("Next"), systemImage: "arrow.right")
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
            Button(L10n.string("Edit Task"), action: onEdit)
            if canAutoAssign {
                Button(L10n.string("Auto Assign This Task"), action: onAutoAssign)
            }
            if canRunAgent {
                Button(L10n.string("Run Agent"), action: onRunAgent)
            }
            if canRetryAgent {
                Button(L10n.string("Retry Last Run"), action: onRetryAgent)
            }
            if executionRecord?.lastOutputSummary != nil || executionRecord?.lastError != nil {
                Button(L10n.string("View Execution Details"), action: onShowExecutionDetails)
            }
            if !manualAssignableAgents.isEmpty {
                Menu(L10n.string("Assign To Agent")) {
                    ForEach(manualAssignableAgents) { agent in
                        Button(agent.name) {
                            onManualAssign(agent.id)
                        }
                    }
                }
            }
            if !reassignableAgents.isEmpty {
                Menu(L10n.string("Reassign To Agent")) {
                    ForEach(reassignableAgents) { agent in
                        Button(agent.name) {
                            onReassign(agent.id)
                        }
                    }
                }
            }
            if canUnassign {
                Button(L10n.string("Unassign Task"), action: onUnassign)
            }
            if !moveToBoardTargets.isEmpty {
                Menu(L10n.string("Move To Board")) {
                    ForEach(moveToBoardTargets) { board in
                        Button(board.name) {
                            onMoveToBoard(board.id)
                        }
                    }
                }
                Menu(L10n.string("Copy To Board")) {
                    ForEach(moveToBoardTargets) { board in
                        Button(board.name) {
                            onCopyToBoard(board.id)
                        }
                    }
                }
            }
            Button(L10n.string("Duplicate Task"), action: onDuplicate)
            Button(L10n.string("Delete Task"), role: .destructive, action: onDelete)
        }
        .draggable(TaskDragPayload(taskID: task.id))
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

    private func executionStatusLabel(for status: TaskExecutionStatus) -> String {
        switch status {
        case .running:
            return L10n.string("Running")
        case .succeeded:
            return L10n.string("Succeeded")
        case .failed:
            return L10n.string("Failed")
        }
    }

    private func executionStatusColor(for status: TaskExecutionStatus) -> Color {
        switch status {
        case .running:
            return BoardNeutralTextPalette.color(for: .secondary, scheme: colorScheme)
        case .succeeded:
            return BoardSemanticTextPalette.color(for: .success, scheme: colorScheme)
        case .failed:
            return BoardSemanticTextPalette.color(for: .error, scheme: colorScheme)
        }
    }
}

private struct ExecutionDetailsPresentation: Identifiable {
    let id = UUID()
    let taskTitle: String
    let assigneeName: String
    let executionRecord: TaskExecutionRecord
}

private struct ExecutionDetailsSheet: View {
    @Environment(\.colorScheme) private var colorScheme
    let details: ExecutionDetailsPresentation
    let onCopy: (String) -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.string("Execution Details"))
                .font(.title3.weight(.semibold))

            Group {
                Text(L10n.format("Task: %@", details.taskTitle))
                Text(L10n.format("Assignee: %@", details.assigneeName))
                Text(L10n.format("Status: %@", statusLabel))
                Text(L10n.format("Runs: %d", details.executionRecord.runCount))
                if let startedAt = details.executionRecord.lastStartedAt {
                    Text(L10n.format("Started: %@", Self.dateFormatter.string(from: startedAt)))
                }
                if let finishedAt = details.executionRecord.lastFinishedAt {
                    Text(L10n.format("Finished: %@", Self.dateFormatter.string(from: finishedAt)))
                }
            }
            .font(.caption)
            .foregroundStyle(BoardNeutralTextPalette.color(for: .secondary, scheme: colorScheme))

            if let output = details.executionRecord.lastOutputSummary, !output.isEmpty {
                executionTextSection(
                    title: L10n.string("Output"),
                    value: normalizedExecutionSummaryForDisplay(output),
                    tint: BoardSemanticTextPalette.color(for: .success, scheme: colorScheme),
                    copyButtonTitle: L10n.string("Copy Output")
                )
            }

            if let error = details.executionRecord.lastError, !error.isEmpty {
                executionTextSection(
                    title: L10n.string("Error"),
                    value: error,
                    tint: BoardSemanticTextPalette.color(for: .error, scheme: colorScheme),
                    copyButtonTitle: L10n.string("Copy Error")
                )
            }

            if let debug = details.executionRecord.lastDebugOutput, !debug.isEmpty {
                executionTextSection(
                    title: L10n.string("Debug Log"),
                    value: debug,
                    tint: BoardNeutralTextPalette.color(for: .secondary, scheme: colorScheme),
                    copyButtonTitle: L10n.string("Copy Debug Log")
                )
            }

            HStack {
                Spacer()
                Button(L10n.string("Close"), action: onClose)
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(18)
        .frame(width: 680, height: 520)
    }

    @ViewBuilder
    private func executionTextSection(title: String, value: String, tint: Color, copyButtonTitle: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(tint)
                Spacer()
                Button(copyButtonTitle) {
                    onCopy(value)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            ScrollView {
                Text(value)
                    .font(.caption.monospaced())
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 150)
            .padding(10)
            .background(BoardSurfacePalette.supplementaryCardColor(for: colorScheme), in: RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(BoardChromePalette.supplementaryCardBorderColor(for: colorScheme), lineWidth: 1)
            )
        }
    }

    private var statusLabel: String {
        switch details.executionRecord.status {
        case .running:
            return L10n.string("Running")
        case .succeeded:
            return L10n.string("Succeeded")
        case .failed:
            return L10n.string("Failed")
        }
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        return formatter
    }()
}

private func normalizedExecutionSummaryForDisplay(_ summary: String) -> String {
    let trimmed = summary.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return summary }

    let headingTokens = ["summary", "摘要", "resumen", "resume", "要約", "요약"]
    let firstLine = trimmed
        .split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
        .first
        .map(String.init)?
        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

    let normalizedFirstLine = firstLine
        .replacingOccurrences(of: "：", with: ":")
        .trimmingCharacters(in: .whitespacesAndNewlines)
    let lowercaseFirstLine = normalizedFirstLine.lowercased()

    if let token = headingTokens.first(where: { lowercaseFirstLine.hasPrefix("\($0):") }) {
        let index = normalizedFirstLine.index(normalizedFirstLine.startIndex, offsetBy: token.count + 1)
        let inlineContent = String(normalizedFirstLine[index...]).trimmingCharacters(in: .whitespacesAndNewlines)
        if !inlineContent.isEmpty {
            return inlineContent
        }

        let lines = trimmed.split(separator: "\n", omittingEmptySubsequences: false)
        guard lines.count > 1 else { return trimmed }
        let remainder = lines.dropFirst().joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return remainder.isEmpty ? trimmed : remainder
    }

    return trimmed
}

private struct AgentLiveConsoleView: View {
    @Environment(\.colorScheme) private var colorScheme
    let agentName: String
    let isRunning: Bool
    let events: [AgentExecutionEvent]
    let onCopy: (String) -> Void
    let onClear: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(L10n.format("Agent Live Console · %@", agentName))
                    .font(.headline)
                Spacer()
                Text(isRunning ? L10n.string("Running") : L10n.string("Idle"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(
                        isRunning
                            ? BoardSemanticTextPalette.color(for: .warning, scheme: colorScheme)
                            : BoardNeutralTextPalette.color(for: .secondary, scheme: colorScheme)
                    )
                if !events.isEmpty {
                    Button(L10n.string("Clear"), action: onClear)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
            }

            if events.isEmpty {
                Text(L10n.string("No execution events yet. Run a task to see live updates for this agent."))
                    .font(.caption)
                    .foregroundStyle(BoardNeutralTextPalette.color(for: .secondary, scheme: colorScheme))
                    .padding(.vertical, 10)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(events) { event in
                            AgentExecutionEventRow(event: event, onCopy: onCopy)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(minHeight: 120, maxHeight: 220)
                .padding(10)
                .background(
                    BoardSurfacePalette.supplementaryCardColor(for: colorScheme),
                    in: RoundedRectangle(cornerRadius: 12)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(
                            BoardChromePalette.supplementaryCardBorderColor(for: colorScheme),
                            lineWidth: 1
                        )
                )
            }
        }
    }
}

private struct AgentExecutionEventRow: View {
    @Environment(\.colorScheme) private var colorScheme
    let event: AgentExecutionEvent
    let onCopy: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(statusLabel)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(statusColor)
                Text(Self.dateFormatter.string(from: event.timestamp))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(BoardNeutralTextPalette.color(for: .secondary, scheme: colorScheme))
                Text(event.taskTitle)
                    .font(.caption2.weight(.semibold))
                    .lineLimit(1)
                Spacer(minLength: 0)
                Button(L10n.string("Copy")) {
                    onCopy(copyText)
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
            }

            Text(event.message)
                .font(.caption)
                .foregroundStyle(.primary)
                .textSelection(.enabled)

            if let details = event.details, !details.isEmpty {
                Text(details)
                    .font(.caption2.monospaced())
                    .foregroundStyle(BoardNeutralTextPalette.color(for: .secondary, scheme: colorScheme))
                    .textSelection(.enabled)
            }
        }
        .padding(8)
        .background(BoardSurfacePalette.taskCardColor(for: colorScheme), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(BoardChromePalette.taskCardBorderColor(for: colorScheme), lineWidth: 1)
        )
    }

    private var statusLabel: String {
        switch event.status {
        case .running:
            return L10n.string("Running")
        case .succeeded:
            return L10n.string("Succeeded")
        case .failed:
            return L10n.string("Failed")
        }
    }

    private var statusColor: Color {
        switch event.status {
        case .running:
            return BoardSemanticTextPalette.color(for: .warning, scheme: colorScheme)
        case .succeeded:
            return BoardSemanticTextPalette.color(for: .success, scheme: colorScheme)
        case .failed:
            return BoardSemanticTextPalette.color(for: .error, scheme: colorScheme)
        }
    }

    private var copyText: String {
        [
            "[\(statusLabel)] \(event.taskTitle)",
            event.message,
            event.details
        ]
        .compactMap { $0 }
        .joined(separator: "\n")
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .medium
        return formatter
    }()
}

private struct GlobalTaskSearchSheet: View {
    @Binding var query: String
    let results: [GlobalTaskSearchResult]
    let onOpenResult: (GlobalTaskSearchResult) -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.string("Find Task"))
                .font(.title3.weight(.semibold))

            TextField(L10n.string("Search title, details, skills, assignee, board"), text: $query)
                .textFieldStyle(.roundedBorder)

            if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(L10n.string("Type to search all boards."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if results.isEmpty {
                Text(L10n.string("No matching tasks found."))
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
                Button(L10n.string("Close"), action: onClose)
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
            Text(L10n.string("New Board"))
                .font(.title3.weight(.semibold))

            TextField(L10n.string("Board Name"), text: $name)
                .textFieldStyle(.roundedBorder)

            if let boardMessage, !boardMessage.isEmpty {
                BoardMessageBanner(message: boardMessage, severity: boardMessageSeverity)
            }

            HStack {
                Spacer()
                Button(L10n.string("Cancel"), action: onCancel)
                Button(L10n.string("Create"), action: onCreate)
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
            Text(L10n.string("Rename Board"))
                .font(.title3.weight(.semibold))

            TextField(L10n.string("Board Name"), text: $name)
                .textFieldStyle(.roundedBorder)

            if let boardMessage, !boardMessage.isEmpty {
                BoardMessageBanner(message: boardMessage, severity: boardMessageSeverity)
            }

            HStack {
                Spacer()
                Button(L10n.string("Cancel"), action: onCancel)
                Button(L10n.string("Rename"), action: onRename)
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
            Text(L10n.string("Create Task"))
                .font(.title3.weight(.semibold))

            if let boardMessage, !boardMessage.isEmpty {
                BoardMessageBanner(message: boardMessage, severity: boardMessageSeverity)
            }

            TextField(L10n.string("Title"), text: $title)
            TextField(L10n.string("Details"), text: $details)
            TextField(L10n.string("Skills (comma separated)"), text: $skills)

            Stepper(L10n.format("Story Points: %d", storyPoints), value: $storyPoints, in: 1 ... 13)

            HStack {
                Spacer()
                Button(L10n.string("Cancel"), action: onCancel)
                Button(L10n.string("Create"), action: onCreate)
                    .keyboardShortcut(.defaultAction)
                Button(L10n.string("Create + Auto Assign"), action: onCreateAutoAssign)
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
            Text(L10n.string("Edit Task"))
                .font(.title3.weight(.semibold))

            if let boardMessage, !boardMessage.isEmpty {
                BoardMessageBanner(message: boardMessage, severity: boardMessageSeverity)
            }

            TextField(L10n.string("Title"), text: $title)
            TextField(L10n.string("Details"), text: $details)
            TextField(L10n.string("Skills (comma separated)"), text: $skills)
            Stepper(L10n.format("Story Points: %d", storyPoints), value: $storyPoints, in: 1 ... 13)

            HStack {
                Spacer()
                Button(L10n.string("Cancel"), action: onCancel)
                Button(L10n.string("Save"), action: onSave)
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
            Text(L10n.string("Edit WIP Limits"))
                .font(.title3.weight(.semibold))

            Stepper(L10n.format("In Progress: %d", inProgressLimit), value: $inProgressLimit, in: 1 ... 20)
            Stepper(L10n.format("Review: %d", reviewLimit), value: $reviewLimit, in: 1 ... 20)

            Text(L10n.string("Tip: limit cannot be smaller than the number of tasks currently in that column."))
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Spacer()
                Button(L10n.string("Cancel"), action: onCancel)
                Button(L10n.string("Apply"), action: onApply)
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
    @Binding var runtimeEnabled: Bool
    @Binding var runtimeProvider: AgentRuntimeProvider
    @Binding var runtimeModel: String
    @Binding var runtimeEndpoint: String
    @Binding var runtimeTools: String
    @Binding var openAIAuthMode: OpenAICompatibleAuthMode
    @Binding var codexProfile: String
    let boardMessage: String?
    let boardMessageSeverity: BoardMessageSeverity?

    let onCancel: () -> Void
    let onCreate: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.string("Create Agent"))
                .font(.title3.weight(.semibold))

            if let boardMessage, !boardMessage.isEmpty {
                BoardMessageBanner(message: boardMessage, severity: boardMessageSeverity)
            }

            TextField(L10n.string("Name"), text: $name)
            TextField(L10n.string("Skills (comma separated)"), text: $skills)
            Stepper(L10n.format("Max Concurrent Tasks: %d", maxConcurrentTasks), value: $maxConcurrentTasks, in: 1 ... 20)
            Toggle(L10n.string("Configure Runtime Profile"), isOn: $runtimeEnabled)
            if runtimeEnabled {
                Picker(L10n.string("Runtime Provider"), selection: $runtimeProvider) {
                    ForEach(AgentRuntimeProvider.allCases) { provider in
                        Text(provider.displayName).tag(provider)
                    }
                }
                TextField(L10n.string("Model"), text: $runtimeModel, prompt: Text(runtimeProvider.defaultModel))
                if runtimeProvider == .openAICompatible {
                    Picker(L10n.string("OpenAI Auth"), selection: $openAIAuthMode) {
                        ForEach(OpenAICompatibleAuthMode.allCases) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }

                    switch openAIAuthMode {
                    case .apiKey:
                        TextField(L10n.string("Endpoint (optional)"), text: $runtimeEndpoint)
                        Text(L10n.string("Reads `OPENAI_API_KEY` (or `OPENAI_COMPAT_API_KEY`) from environment."))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    case .codexBridge:
                        TextField(L10n.string("Codex Profile (optional)"), text: $codexProfile)
                        Text(L10n.string("Uses local `codex login` session via Codex CLI. If the configured model is not supported for ChatGPT login, OpenMac retries with Codex default model."))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                TextField(L10n.string("Tools (comma separated)"), text: $runtimeTools)
            }

            HStack {
                Spacer()
                Button(L10n.string("Cancel"), action: onCancel)
                Button(L10n.string("Create"), action: onCreate)
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
    @Binding var runtimeEnabled: Bool
    @Binding var runtimeProvider: AgentRuntimeProvider
    @Binding var runtimeModel: String
    @Binding var runtimeEndpoint: String
    @Binding var runtimeTools: String
    @Binding var openAIAuthMode: OpenAICompatibleAuthMode
    @Binding var codexProfile: String
    let boardMessage: String?
    let boardMessageSeverity: BoardMessageSeverity?

    let onCancel: () -> Void
    let onSave: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.string("Edit Agent"))
                .font(.title3.weight(.semibold))

            if let boardMessage, !boardMessage.isEmpty {
                BoardMessageBanner(message: boardMessage, severity: boardMessageSeverity)
            }

            TextField(L10n.string("Name"), text: $name)
            TextField(L10n.string("Skills (comma separated)"), text: $skills)
            Stepper(L10n.format("Max Concurrent Tasks: %d", maxConcurrentTasks), value: $maxConcurrentTasks, in: 1 ... 20)
            Toggle(L10n.string("Configure Runtime Profile"), isOn: $runtimeEnabled)
            if runtimeEnabled {
                Picker(L10n.string("Runtime Provider"), selection: $runtimeProvider) {
                    ForEach(AgentRuntimeProvider.allCases) { provider in
                        Text(provider.displayName).tag(provider)
                    }
                }
                TextField(L10n.string("Model"), text: $runtimeModel, prompt: Text(runtimeProvider.defaultModel))
                if runtimeProvider == .openAICompatible {
                    Picker(L10n.string("OpenAI Auth"), selection: $openAIAuthMode) {
                        ForEach(OpenAICompatibleAuthMode.allCases) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }

                    switch openAIAuthMode {
                    case .apiKey:
                        TextField(L10n.string("Endpoint (optional)"), text: $runtimeEndpoint)
                        Text(L10n.string("Reads `OPENAI_API_KEY` (or `OPENAI_COMPAT_API_KEY`) from environment."))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    case .codexBridge:
                        TextField(L10n.string("Codex Profile (optional)"), text: $codexProfile)
                        Text(L10n.string("Uses local `codex login` session via Codex CLI. If the configured model is not supported for ChatGPT login, OpenMac retries with Codex default model."))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                TextField(L10n.string("Tools (comma separated)"), text: $runtimeTools)
            }

            HStack {
                Spacer()
                Button(L10n.string("Cancel"), action: onCancel)
                Button(L10n.string("Save"), action: onSave)
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
            Text(L10n.string("Manual Triage"))
                .font(.title3.weight(.semibold))

            if let boardMessage, !boardMessage.isEmpty {
                BoardMessageBanner(message: boardMessage, severity: boardMessageSeverity)
            }

            HStack {
                Spacer()
                Button(L10n.format("Assign All Eligible (%d)", assignAllEligibleCount), action: onAssignAll)
                    .buttonStyle(.bordered)
                    .disabled(assignAllEligibleCount == 0)
            }

            if unassignableTaskCount > 0 {
                Text(L10n.format("%d task(s) currently have no eligible agent and will be skipped.", unassignableTaskCount))
                    .font(.caption)
                    .foregroundStyle(BoardMessageColorPalette.color(for: .warning, scheme: colorScheme))
            }

            if tasks.isEmpty {
                Text(L10n.string("No tasks waiting for manual triage."))
                    .font(.callout)
                    .foregroundStyle(BoardNeutralTextPalette.color(for: .secondary, scheme: colorScheme))
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(tasks) { task in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(task.title)
                                    .font(.headline)
                                Text(L10n.format("Skills: %@", task.requiredSkills.sorted().joined(separator: ", ")))
                                    .font(.caption)
                                    .foregroundStyle(BoardNeutralTextPalette.color(for: .secondary, scheme: colorScheme))

                                let eligibleAgents = assignableAgents(task)

                                if eligibleAgents.isEmpty {
                                    Text(L10n.string("No eligible agents currently available."))
                                        .font(.caption)
                                        .foregroundStyle(BoardSemanticTextPalette.color(for: .error, scheme: colorScheme))
                                } else {
                                    Picker(L10n.string("Assign To"), selection: selectionBinding(for: task.id, fallback: eligibleAgents[0].id)) {
                                        ForEach(eligibleAgents) { agent in
                                            Text(L10n.format("%@ (%@)", agent.name, loadText(agent)))
                                                .tag(agent.id)
                                        }
                                    }

                                    Button(L10n.string("Assign")) {
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
                Button(L10n.string("Close"), action: onClose)
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
