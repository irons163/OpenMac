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

private struct PMBriefTemplateOption: Identifiable, Equatable {
    let id: String
    let title: String
}

private struct PMBriefTemplateDefinition: Equatable {
    let id: String
    let optionTitleKey: String
    let defaultProjectNameKey: String
    let briefKey: String
}

struct ContentView: View {
    @Environment(\.colorScheme) private var systemColorScheme
    @AppStorage("appearanceMode") private var appearanceModeRawValue = AppAppearanceMode.system.rawValue
    @AppStorage(AppLanguageSettings.userDefaultsKey) private var appLanguageOverrideRawValue = AppLanguageSettings.systemValue
    @AppStorage("developerModeEnabled") private var developerModeEnabled = false
    @AppStorage("autoCycleMaxPasses") private var autoCycleMaxPasses = 3
    @AppStorage("autoCycleAutoCreateMissingDependencies") private var autoCycleAutoCreateMissingDependencies = true
    @AppStorage(CodexProjectsDirectorySettings.userDefaultsKey) private var codexProjectsDirectoryPath = ""
    @AppStorage("githubRepositoryPath") private var githubRepositoryPath = ""
    @AppStorage("githubBaseBranch") private var githubBaseBranch = "main"
    @AppStorage("githubRemoteName") private var githubRemoteName = "origin"
    @AppStorage("githubBranchPrefix") private var githubBranchPrefix = "openmac"
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
    @State private var isShowingPMPlannerSheet = false
    @State private var isShowingDeleteBoardAlert = false
    @State private var newBoardName = ""
    @State private var renameBoardName = ""
    @State private var newTaskTitle = ""
    @State private var newTaskDetails = ""
    @State private var newTaskSkills = ""
    @State private var newTaskPoints = 1
    @State private var selectedTaskTemplateID: UUID?
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
    @State private var isAutoCycleRunning = false
    @State private var selectedAgentConsoleAgentID: UUID?
    @State private var pmProjectName = ""
    @State private var pmProjectBrief = ""
    @State private var pmAutoAssignAfterCreate = true
    @State private var pmCreateNewBoardForPlan = true
    @State private var pmPlanSummary = ""
    @State private var pmPlannedTickets: [PMPlannedTicket] = []
    @State private var pmSelectedTemplateID = "custom"
    @State private var pmBlueprintVision = ""
    @State private var pmBlueprintTargetUsers = ""
    @State private var pmBlueprintCoreFeatures = ""
    @State private var pmBlueprintTechScope = ""
    @State private var pmBlueprintConstraints = ""
    @State private var pmBlueprintQualityBar = ""
    @State private var pmTestPlanText = ""
    @State private var autoRetryEnabled = true
    @State private var autoRetryMaxRetries = 2
    @State private var autoRetryBackoffSeconds = 1.0
    @State private var autoRetryRetryNetwork = true
    @State private var autoRetryRetryRateLimit = true
    @State private var autoRetryRetryServer = true
    @State private var approvalGateEnabled = false
    @State private var approvalGateMinStoryPoints = 3
    @State private var quotaGovernanceEnabled = false
    @State private var quotaMaxEstimatedTokens = 12000
    @State private var quotaMaxEstimatedCostUSD = 0.60
    @State private var quotaCostPer1KTokensUSD = 0.05
    @State private var parallelSchedulerEnabled = false
    @State private var parallelSchedulerMaxAgents = 2
    @State private var prQualityGateEnabled = false
    @State private var dagSchedulerEnabled = true
    @State private var dagSchedulerAutoAssignBeforeRun = true
    @State private var dagSchedulerAutoCreateDependencies = true
    @State private var dagSchedulerMaxPasses = 6
    @State private var qualitySafetyGateEnabled = false
    @State private var qualitySafetyRequireAcceptance = true
    @State private var qualitySafetyRequireCoverageIntent = true
    @State private var qualitySafetyRequireSecurityPrivacyNotes = true
    @State private var isGitHubFlowRunning = false
    fileprivate static var savePanelResultProvider: (NSSavePanel) -> (NSApplication.ModalResponse, URL?) = { panel in
        (panel.runModal(), panel.url)
    }
    fileprivate static var openPanelResultProvider: (NSOpenPanel) -> (NSApplication.ModalResponse, URL?) = { panel in
        (panel.runModal(), panel.url)
    }
    fileprivate static var alertRunner: (NSAlert) -> NSApplication.ModalResponse = { alert in
        alert.runModal()
    }
    fileprivate static var workspaceActivator: ([URL]) -> Void = { urls in
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }
    fileprivate static var codexDirectoryEnsurer: (String) throws -> URL = { path in
        try CodexProjectsDirectorySettings.ensureProjectsDirectoryExists(at: path)
    }

    init(viewModel: KanbanBoardViewModel = .demoBoard()) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        NavigationSplitView {
            List {
                ForEach(viewModel.agents) { agent in
                    agentSidebarRow(for: agent)
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
                    if viewModel.pendingApprovalTaskCount > 0 {
                        Text(L10n.format("Pending approvals: %d", viewModel.pendingApprovalTaskCount))
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
                    reviewPressure: viewModel.wipPressurePercent(for: .review),
                    blockedTasks: selectedBoardDependencyInsights.blockedTaskCount,
                    criticalPathStoryPoints: selectedBoardDependencyInsights.criticalPathStoryPoints
                )

                BoardHealthRecommendationsView(
                    recommendations: viewModel.healthRecommendations(),
                    onAction: applyHealthRecommendation,
                    onApplyAll: applyAllHealthRecommendations
                )

                BoardDependencyInsightsView(insights: selectedBoardDependencyInsights)

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
                    boardMessageSection(message)
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
                            kanbanColumn(for: status)
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
                Button(isBatchRunning ? L10n.string("Cancel") : L10n.string("Run Assigned")) {
                    if isBatchRunning {
                        cancelAssignedExecutionsFromToolbar()
                    } else {
                        runAssignedExecutionsFromToolbar()
                    }
                }
                .keyboardShortcut("g", modifiers: [.command, .shift])
                .help(L10n.string("Batch-run assigned To Do/In Progress tasks (Shift-Command-G)"))
                .disabled(isBatchRunning ? viewModel.isBatchRunCancelRequested : !canBatchRunAssignedTasks)
                Button(isAutoCycleRunning ? L10n.string("Cancel") : L10n.string("Run Auto Cycle")) {
                    if isAutoCycleRunning {
                        cancelAutoCycleFromToolbar()
                    } else {
                        runAutoCycleFromToolbar()
                    }
                }
                .help(L10n.string("Auto-assign then batch-run in repeated passes until queue is stable"))
                .disabled(isAutoCycleRunning ? viewModel.isAutoCycleCancelRequested : !canRunAutoCycle)
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
                        Button(L10n.string("PM Plan Project")) {
                            openPMPlannerSheet()
                        }
                        .keyboardShortcut("p", modifiers: [.command, .shift])

                        Button(L10n.string("Autopilot Create + Run")) {
                            runPMOneClickFromToolbar()
                        }

                        Button(L10n.string("Approve Pending Runs")) {
                            approveAllPendingRunsFromToolbar()
                        }
                        .disabled(viewModel.pendingApprovalTaskCount == 0)

                        Divider()

                        Button(isBatchRunning ? L10n.string("Cancel") : L10n.string("Run Assigned Tasks")) {
                            if isBatchRunning {
                                cancelAssignedExecutionsFromToolbar()
                            } else {
                                runAssignedExecutionsFromToolbar()
                            }
                        }
                        .disabled(isBatchRunning ? viewModel.isBatchRunCancelRequested : !canBatchRunAssignedTasks)

                        Button(isAutoCycleRunning ? L10n.string("Cancel") : L10n.string("Run Auto Cycle")) {
                            if isAutoCycleRunning {
                                cancelAutoCycleFromToolbar()
                            } else {
                                runAutoCycleFromToolbar()
                            }
                        }
                        .disabled(isAutoCycleRunning ? viewModel.isAutoCycleCancelRequested : !canRunAutoCycle)

                        Button(L10n.string("Run DAG Autopilot")) {
                            runDAGAutopilotFromToolbar()
                        }
                        .disabled(isAutoCycleRunning || isBatchRunning)

                        Toggle(
                            L10n.string("Auto Create Missing Dependencies During Cycle"),
                            isOn: $autoCycleAutoCreateMissingDependencies
                        )

                        Button(L10n.string("Resume Interrupted Run")) {
                            resumeInterruptedExecutionFromToolbar()
                        }
                        .disabled(!viewModel.hasExecutionCheckpointForSelectedBoard || isBatchRunning || isAutoCycleRunning)

                        Button(L10n.string("Clear Interrupted Run Checkpoint")) {
                            clearExecutionCheckpointFromToolbar()
                        }
                        .disabled(!viewModel.hasExecutionCheckpointForSelectedBoard)

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

                        Button(L10n.string("Create Acceptance E2E Tasks")) {
                            createAcceptanceE2ETasksFromToolbar()
                        }

                        Divider()

                        Button(L10n.string("Export Current Board JSON...")) {
                            exportSelectedBoardFromToolbar()
                        }
                        .keyboardShortcut("e", modifiers: [.command, .shift, .option])

                        Button(L10n.string("Export Workspace JSON...")) {
                            exportWorkspaceFromToolbar()
                        }
                        .keyboardShortcut("e", modifiers: [.command, .shift])

                        Button(L10n.string("Export Execution Report JSON...")) {
                            exportExecutionReportJSONFromToolbar()
                        }

                        Button(L10n.string("Export Execution Report Markdown...")) {
                            exportExecutionReportMarkdownFromToolbar()
                        }

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
                    Text(L10n.string("Execution Auto Retry"))
                    Toggle(L10n.string("Enabled"), isOn: $autoRetryEnabled)
                    Stepper(L10n.format("Max Retries: %d", autoRetryMaxRetries), value: $autoRetryMaxRetries, in: 0 ... 5)
                    Stepper(
                        L10n.format("Backoff Seconds: %.1f", autoRetryBackoffSeconds),
                        value: $autoRetryBackoffSeconds,
                        in: 0 ... 10,
                        step: 0.5
                    )
                    Toggle(L10n.string("Retry Network Errors"), isOn: $autoRetryRetryNetwork)
                    Toggle(L10n.string("Retry Rate Limit Errors"), isOn: $autoRetryRetryRateLimit)
                    Toggle(L10n.string("Retry Server Errors"), isOn: $autoRetryRetryServer)
                    Button(L10n.string("Apply Auto-Retry Settings")) {
                        applyAutoRetrySettings()
                    }
                    Divider()
                    Text(L10n.string("Human Approval Gate"))
                    Toggle(L10n.string("Enable approval before execution for higher-impact tasks"), isOn: $approvalGateEnabled)
                    Stepper(
                        L10n.format("Require approval for SP >= %d", approvalGateMinStoryPoints),
                        value: $approvalGateMinStoryPoints,
                        in: 1 ... 13
                    )
                    Button(L10n.string("Apply Approval Settings")) {
                        applyApprovalGateSettings()
                    }
                    Button(L10n.string("Approve Pending Runs")) {
                        approveAllPendingRunsFromToolbar()
                    }
                    .disabled(viewModel.pendingApprovalTaskCount == 0)
                    Divider()
                    Text(L10n.string("Cost & Quota Governance"))
                    Toggle(L10n.string("Enable execution quota limits (tokens/cost)"), isOn: $quotaGovernanceEnabled)
                    Stepper(
                        L10n.format("Max Estimated Tokens: %d", quotaMaxEstimatedTokens),
                        value: $quotaMaxEstimatedTokens,
                        in: 500 ... 500_000,
                        step: 500
                    )
                    Stepper(
                        L10n.format("Max Estimated Cost (USD): %.2f", quotaMaxEstimatedCostUSD),
                        value: $quotaMaxEstimatedCostUSD,
                        in: 0.05 ... 500,
                        step: 0.05
                    )
                    Stepper(
                        L10n.format("Cost per 1K tokens (USD): %.3f", quotaCostPer1KTokensUSD),
                        value: $quotaCostPer1KTokensUSD,
                        in: 0.001 ... 5,
                        step: 0.001
                    )
                    Button(L10n.string("Apply Quota Settings")) {
                        applyQuotaGovernanceSettings()
                    }
                    Text(viewModel.executionQuotaUsageSummaryText())
                        .font(.caption2.monospaced())
                    Button(L10n.string("Reset Quota Usage")) {
                        viewModel.resetExecutionQuotaUsage()
                    }
                    Divider()
                    Text(L10n.string("Parallel Scheduler"))
                    Toggle(L10n.string("Enable multi-agent parallel background execution"), isOn: $parallelSchedulerEnabled)
                    Stepper(
                        L10n.format("Max Parallel Agents: %d", parallelSchedulerMaxAgents),
                        value: $parallelSchedulerMaxAgents,
                        in: 1 ... 12
                    )
                    Button(L10n.string("Apply Scheduler Settings")) {
                        applyParallelSchedulerSettings()
                    }
                    Divider()
                    Text(L10n.string("PR Quality Gate"))
                    Toggle(L10n.string("Enable quality gate before GitHub PR flow"), isOn: $prQualityGateEnabled)
                    Text(viewModel.gitHubPRQualityGateSummaryText())
                        .font(.caption2.monospaced())
                    Button(L10n.string("Apply PR Quality Gate Settings")) {
                        applyPRQualityGateSettings()
                    }
                    Divider()
                    Text(L10n.string("DAG Scheduler"))
                    Toggle(L10n.string("Enable dependency DAG scheduler"), isOn: $dagSchedulerEnabled)
                    Toggle(L10n.string("Auto-assign before DAG run"), isOn: $dagSchedulerAutoAssignBeforeRun)
                    Toggle(L10n.string("Auto-create missing dependencies during DAG run"), isOn: $dagSchedulerAutoCreateDependencies)
                    Stepper(
                        L10n.format("DAG Max Passes: %d", dagSchedulerMaxPasses),
                        value: $dagSchedulerMaxPasses,
                        in: 1 ... 24
                    )
                    Button(L10n.string("Apply DAG Settings")) {
                        applyDAGSchedulerSettings()
                    }
                    Divider()
                    Text(L10n.string("Quality & Safety Gate"))
                    Toggle(L10n.string("Enable quality/safety checks before execution"), isOn: $qualitySafetyGateEnabled)
                    Toggle(L10n.string("Require acceptance criteria in task details"), isOn: $qualitySafetyRequireAcceptance)
                    Toggle(L10n.string("Require test/coverage intent in task details"), isOn: $qualitySafetyRequireCoverageIntent)
                    Toggle(L10n.string("Require security/privacy note for sensitive tasks"), isOn: $qualitySafetyRequireSecurityPrivacyNotes)
                    Text(viewModel.executionQualitySafetyGateSummaryText())
                        .font(.caption2.monospaced())
                    Button(L10n.string("Apply Quality & Safety Settings")) {
                        applyQualitySafetyGateSettings()
                    }
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
                    Divider()
                    Text(L10n.string("GitHub PR Flow"))
                    Text(resolvedGitHubRepositoryPath)
                        .font(.caption2.monospaced())
                    Button(L10n.string("Choose GitHub Repository...")) {
                        chooseGitHubRepositoryDirectory()
                    }
                    Button(L10n.string("Use Projects Folder as GitHub Repository")) {
                        githubRepositoryPath = resolvedCodexProjectsDirectoryPath
                    }
                    Button(L10n.string("Open GitHub Repository in Finder")) {
                        openGitHubRepositoryInFinder()
                    }
                    Button(L10n.string("Copy GitHub Repository Path")) {
                        copyToPasteboard(resolvedGitHubRepositoryPath)
                    }
                    Button(isGitHubFlowRunning ? L10n.string("GitHub PR Flow Running...") : L10n.string("Run GitHub PR Flow")) {
                        runGitHubPRFlowFromToolbar()
                    }
                    .disabled(isGitHubFlowRunning)
                    if let lastGitHubPRURL = viewModel.lastGitHubPRURL, !lastGitHubPRURL.isEmpty {
                        Button(L10n.string("Copy Last PR URL")) {
                            copyToPasteboard(lastGitHubPRURL)
                        }
                    }
                    if let lastGitHubPRLog = viewModel.lastGitHubPRLog, !lastGitHubPRLog.isEmpty {
                        Button(L10n.string("Copy Last GitHub PR Log")) {
                            copyToPasteboard(lastGitHubPRLog)
                        }
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
        .sheet(isPresented: $isShowingPMPlannerSheet) {
            PMPlannerSheet(
                projectName: $pmProjectName,
                projectBrief: $pmProjectBrief,
                autoAssignAfterCreate: $pmAutoAssignAfterCreate,
                createNewBoardForPlan: $pmCreateNewBoardForPlan,
                autopilotMaxPasses: $autoCycleMaxPasses,
                autoCreateMissingDependenciesDuringCycle: $autoCycleAutoCreateMissingDependencies,
                planSummary: pmPlanSummary,
                plannedTickets: $pmPlannedTickets,
                selectedTemplateID: $pmSelectedTemplateID,
                templateOptions: pmTemplateOptions,
                blueprintVision: $pmBlueprintVision,
                blueprintTargetUsers: $pmBlueprintTargetUsers,
                blueprintCoreFeatures: $pmBlueprintCoreFeatures,
                blueprintTechScope: $pmBlueprintTechScope,
                blueprintConstraints: $pmBlueprintConstraints,
                blueprintQualityBar: $pmBlueprintQualityBar,
                testPlanText: pmTestPlanText,
                boardMessage: viewModel.lastBoardMessage,
                boardMessageSeverity: viewModel.lastBoardMessageSeverity,
                onCancel: closePMPlannerSheet,
                onApplyTemplate: applyPMTemplateFromSheet,
                onApplyTemplateAndGenerate: applyAndGeneratePMTemplateFromSheet,
                onApplyBlueprint: applyPMBlueprintFromSheet,
                onApplyBlueprintAndGenerate: applyAndGeneratePMBlueprintFromSheet,
                onGeneratePlan: generatePMPlanFromSheet,
                onGenerateTestPlan: generatePMTestPlanFromSheet,
                onCreateMissingAgents: createMissingAgentsFromPMPlanFromSheet,
                onChainDependencies: applyPMDependencyChainFromSheet,
                onAutoACForAllTickets: applyPMAutoAcceptanceCriteriaForAllTickets,
                onAutoACTicket: applyPMAutoAcceptanceCriteriaForTicket,
                onCreateTickets: createPMTicketsFromSheet,
                onCreateAndRun: createAndRunPMTicketsFromSheet,
                onRunAutopilot: runPMOneClickFlowFromSheet,
                onCopyPlan: copyPMPlanFromSheet,
                onCopyTestPlan: copyPMTestPlanFromSheet,
                onCopyBlueprint: copyPMBlueprintFromSheet
            )
        }
        .sheet(isPresented: $isShowingNewTaskSheet) {
            NewTaskSheet(
                title: $newTaskTitle,
                details: $newTaskDetails,
                skills: $newTaskSkills,
                storyPoints: $newTaskPoints,
                selectedTemplateID: $selectedTaskTemplateID,
                templates: viewModel.taskTemplates,
                boardMessage: viewModel.lastBoardMessage,
                boardMessageSeverity: viewModel.lastBoardMessageSeverity,
                onCancel: resetDraftAndClose,
                onApplyTemplate: applySelectedTaskTemplateFromSheet,
                onSaveAsTemplate: saveCurrentTaskAsTemplateFromSheet,
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
            syncAutoRetryDraftFromViewModel()
            syncApprovalGateDraftFromViewModel()
            syncQuotaGovernanceDraftFromViewModel()
            syncParallelSchedulerDraftFromViewModel()
            syncPRQualityGateDraftFromViewModel()
            syncDAGSchedulerDraftFromViewModel()
            syncQualitySafetyGateDraftFromViewModel()
            ensureCodexProjectsDirectoryExists()
        }
        .onChange(of: appLanguageOverrideRawValue) { _, newValue in
            L10n.setRuntimeLocale(
                AppLanguageResolver.resolvedLocale(overrideRawValue: newValue)
            )
            viewModel.clearLocalizedTransientBoardMessage()
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
        .preferredColorScheme(selectedAppearanceMode.preferredColorScheme)
    }

    private func resetDraftAndClose() {
        newTaskTitle = ""
        newTaskDetails = ""
        newTaskSkills = ""
        newTaskPoints = 1
        selectedTaskTemplateID = nil
        isShowingNewTaskSheet = false
    }

    private func applySelectedTaskTemplateFromSheet() {
        guard let templateID = selectedTaskTemplateID,
              let template = viewModel.taskTemplate(templateID) else {
            return
        }
        newTaskTitle = template.title
        newTaskDetails = template.details
        newTaskSkills = template.requiredSkillsText
        newTaskPoints = template.storyPoints
    }

    private func saveCurrentTaskAsTemplateFromSheet() {
        let proposedName = newTaskTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let templateName = proposedName.isEmpty ? L10n.string("Task Template") : proposedName
        let added = viewModel.addTaskTemplate(
            name: templateName,
            title: newTaskTitle,
            details: newTaskDetails,
            requiredSkillsText: newTaskSkills,
            storyPoints: newTaskPoints
        )
        guard added else { return }
        selectedTaskTemplateID = viewModel.taskTemplates.first(where: { $0.name == templateName })?.id
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
            executionRecord: executionRecord,
            timelineText: viewModel.replayExecutionTimeline(for: task.id)
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
        _ = Self.handleBoolResult(
            viewModel.createBoard(name: newBoardName),
            onChanged: closeNewBoardSheetAndHandleContext
        )
    }

    private func renameBoardFromSheet() {
        _ = Self.handleBoolResult(
            viewModel.renameBoard(viewModel.selectedBoardID, to: renameBoardName),
            onChanged: closeRenameBoardSheet
        )
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

    private func openPMPlannerSheet() {
        pmProjectName = viewModel.selectedBoardName
        pmProjectBrief = ""
        pmAutoAssignAfterCreate = true
        pmCreateNewBoardForPlan = true
        pmSelectedTemplateID = Self.pmCustomTemplateID
        pmBlueprintVision = ""
        pmBlueprintTargetUsers = ""
        pmBlueprintCoreFeatures = ""
        pmBlueprintTechScope = ""
        pmBlueprintConstraints = ""
        pmBlueprintQualityBar = ""
        pmPlanSummary = ""
        pmPlannedTickets = []
        pmTestPlanText = ""
        isShowingPMPlannerSheet = true
    }

    private func closePMPlannerSheet() {
        pmSelectedTemplateID = Self.pmCustomTemplateID
        pmBlueprintVision = ""
        pmBlueprintTargetUsers = ""
        pmBlueprintCoreFeatures = ""
        pmBlueprintTechScope = ""
        pmBlueprintConstraints = ""
        pmBlueprintQualityBar = ""
        pmPlanSummary = ""
        pmPlannedTickets = []
        pmTestPlanText = ""
        isShowingPMPlannerSheet = false
    }

    private func applyPMTemplateFromSheet() {
        _ = Self.applyPMTemplateAndReset(
            selectedTemplateID: pmSelectedTemplateID,
            projectName: &pmProjectName,
            projectBrief: &pmProjectBrief,
            planSummary: &pmPlanSummary,
            plannedTickets: &pmPlannedTickets
        )
        pmTestPlanText = ""
    }

    private func applyAndGeneratePMTemplateFromSheet() {
        applyPMTemplateFromSheet()
        generatePMPlanFromSheet()
    }

    private func applyPMBlueprintFromSheet() {
        let applied = Self.applyPMBlueprint(
            vision: pmBlueprintVision,
            targetUsers: pmBlueprintTargetUsers,
            coreFeatures: pmBlueprintCoreFeatures,
            techScope: pmBlueprintTechScope,
            constraints: pmBlueprintConstraints,
            qualityBar: pmBlueprintQualityBar,
            projectName: &pmProjectName,
            projectBrief: &pmProjectBrief
        )
        guard applied else { return }
        pmPlanSummary = ""
        pmPlannedTickets = []
        pmTestPlanText = ""
    }

    private func applyAndGeneratePMBlueprintFromSheet() {
        applyPMBlueprintFromSheet()
        generatePMPlanFromSheet()
    }

    private func generatePMPlanFromSheet() {
        guard let plan = viewModel.previewProjectPlan(
            projectName: pmProjectName,
            projectBrief: pmProjectBrief
        ) else {
            pmPlanSummary = ""
            pmPlannedTickets = []
            return
        }

        pmProjectName = plan.projectName
        pmPlanSummary = plan.summary
        pmPlannedTickets = plan.tickets
        pmTestPlanText = Self.pmTestPlanText(
            projectName: pmProjectName,
            projectBrief: pmProjectBrief,
            tickets: pmPlannedTickets
        )
    }

    private func generatePMTestPlanFromSheet() {
        pmTestPlanText = Self.pmTestPlanText(
            projectName: pmProjectName,
            projectBrief: pmProjectBrief,
            tickets: pmPlannedTickets
        )
    }

    private func applyPMAutoAcceptanceCriteriaForAllTickets() {
        guard !pmPlannedTickets.isEmpty else { return }
        pmPlannedTickets = pmPlannedTickets.map { ticket in
            Self.applyingAutoAcceptanceCriteria(to: ticket)
        }
    }

    private func applyPMAutoAcceptanceCriteriaForTicket(_ ticketIndex: Int) {
        guard pmPlannedTickets.indices.contains(ticketIndex) else { return }
        pmPlannedTickets[ticketIndex] = Self.applyingAutoAcceptanceCriteria(to: pmPlannedTickets[ticketIndex])
    }

    private func createMissingAgentsFromPMPlanFromSheet() {
        let createdCount = viewModel.createMissingAgentsForPlannedTickets(pmPlannedTickets)
        if createdCount > 0 {
            refreshTriageSelections()
        }
    }

    private func applyPMDependencyChainFromSheet() {
        pmPlannedTickets = Self.applyingDependencyChain(to: pmPlannedTickets)
    }

    private func createPMTicketsFromSheet() {
        if pmCreateNewBoardForPlan {
            let resolvedBoardName = Self.uniquePMBoardName(
                baseName: pmProjectName,
                existingNames: viewModel.boards.map(\.name)
            )
            guard viewModel.createBoard(name: resolvedBoardName) else { return }
            pmProjectName = resolvedBoardName
            handleBoardContextChanged()
        }

        let createdCount = viewModel.addPlannedTickets(pmPlannedTickets, autoAssign: pmAutoAssignAfterCreate)
        guard createdCount > 0 else { return }
        refreshTriageSelections()
        closePMPlannerSheet()
    }

    private func createAndRunPMTicketsFromSheet() {
        createPMTicketsFromSheet()
        runAssignedExecutionsFromToolbar()
    }

    private func runPMOneClickFromToolbar() {
        _ = PMOneClickFlowUseCase.run(
            plannedTicketsCount: pmPlannedTickets.count,
            projectBrief: pmProjectBrief,
            runAutopilot: {
                runPMOneClickFlowFromSheet()
            },
            openPlanner: {
                openPMPlannerSheet()
            }
        )
    }

    private func runPMOneClickFlowFromSheet() {
        let preparation = PMAutopilotSheetUseCase.prepareForRun(
            isAutoCycleRunning: isAutoCycleRunning,
            isBatchRunning: isBatchRunning,
            plannedTickets: pmPlannedTickets,
            testPlanText: pmTestPlanText,
            projectName: pmProjectName,
            shouldCreateNewBoard: pmCreateNewBoardForPlan,
            existingBoardNames: viewModel.boards.map(\.name),
            generatePlan: {
                guard let plan = viewModel.previewProjectPlan(
                    projectName: pmProjectName,
                    projectBrief: pmProjectBrief
                ) else {
                    return nil
                }
                return PMGeneratedPlan(
                    projectName: plan.projectName,
                    summary: plan.summary,
                    tickets: plan.tickets
                )
            },
            applyAutoAcceptanceCriteria: { tickets in
                tickets.map { ticket in
                    Self.applyingAutoAcceptanceCriteria(to: ticket)
                }
            },
            generateTestPlan: { resolvedProjectName, resolvedTickets in
                Self.pmTestPlanText(
                    projectName: resolvedProjectName,
                    projectBrief: pmProjectBrief,
                    tickets: resolvedTickets
                )
            },
            uniqueBoardName: { baseName, existingNames in
                Self.uniquePMBoardName(baseName: baseName, existingNames: existingNames)
            },
            createBoard: { boardName in
                viewModel.createBoard(name: boardName)
            }
        )

        guard preparation.shouldStart else {
            if let summary = preparation.generatedPlanSummary {
                pmPlanSummary = summary
                pmPlannedTickets = preparation.plannedTickets
            } else if preparation.status == .missingTickets {
                pmPlanSummary = ""
                pmPlannedTickets = []
            }
            return
        }

        pmProjectName = preparation.projectName
        pmPlannedTickets = preparation.plannedTickets
        pmTestPlanText = preparation.testPlanText
        if let summary = preparation.generatedPlanSummary {
            pmPlanSummary = summary
        }
        if preparation.didSwitchBoardContext {
            handleBoardContextChanged()
        }

        isAutoCycleRunning = true
        viewModel.runPMAutopilotInBackground(
            plannedTickets: pmPlannedTickets,
            autoAssign: pmAutoAssignAfterCreate,
            autoCreateMissingDependenciesDuringCycle: autoCycleAutoCreateMissingDependencies,
            maxAutoCyclePasses: autoCycleMaxPasses
        ) { _, createdTickets, _, _ in
            isAutoCycleRunning = false
            if createdTickets > 0 {
                refreshTriageSelections()
                closePMPlannerSheet()
            }
        }
    }

    private func runPMAutopilotFromSheet() {
        runPMOneClickFlowFromSheet()
    }

    private func copyPMPlanFromSheet() {
        copyToPasteboard(
            Self.pmPlanCopyText(
                projectName: pmProjectName,
                summary: pmPlanSummary,
                tickets: pmPlannedTickets,
                testPlan: pmTestPlanText
            )
        )
    }

    private func copyPMTestPlanFromSheet() {
        copyToPasteboard(pmTestPlanText)
    }

    private func copyPMBlueprintFromSheet() {
        guard let data = viewModel.projectBlueprintExportData(
            projectName: pmProjectName,
            projectBrief: pmProjectBrief
        ),
            let text = String(data: data, encoding: .utf8) else {
            return
        }
        copyToPasteboard(text)
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
        if let inProgressLimit = viewModel.wipLimit(for: .inProgress) {
            inProgressWIPLimitDraft = inProgressLimit
        } else {
            inProgressWIPLimitDraft = 1
        }
        if let reviewLimit = viewModel.wipLimit(for: .review) {
            reviewWIPLimitDraft = reviewLimit
        } else {
            reviewWIPLimitDraft = 1
        }
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
        _ = Self.handleBoolResult(
            Self.applyTaskEdits(
                viewModel: viewModel,
                editingTaskID: editingTaskID,
                title: editTaskTitle,
                details: editTaskDetails,
                requiredSkillsText: editTaskSkills,
                storyPoints: editTaskPoints
            ),
            onChanged: refreshAndCloseEditTaskSheet
        )
    }

    private func createTaskFromSheet(autoAssign: Bool) {
        _ = Self.handleBoolResult(
            viewModel.addTask(
                title: newTaskTitle,
                details: newTaskDetails,
                requiredSkillsText: newTaskSkills,
                storyPoints: newTaskPoints,
                autoAssign: autoAssign
            ),
            onChanged: refreshAndResetTaskDraft
        )
    }

    private func archiveDoneTasks() {
        if viewModel.clearDoneTasks() > 0 {
            refreshTriageSelections()
        }
    }

    private func approveAllPendingRunsFromToolbar() {
        _ = Self.handlePositiveCountResult(
            viewModel.approveAllPendingTaskExecutions(),
            onPositive: refreshTriageSelections
        )
    }

    private func rebalanceTodoAssignments() {
        _ = Self.handlePositiveCountResult(
            viewModel.rebalanceTodoAssignments(),
            onPositive: refreshTriageSelections
        )
    }

    private func createAcceptanceE2ETasksFromToolbar() {
        _ = Self.handlePositiveCountResult(
            viewModel.createAcceptanceE2ETasks(autoAssign: true),
            onPositive: refreshTriageSelections
        )
    }

    private func runAutoAssignFromToolbar() {
        viewModel.autoAssignTasks()
        Self.postAutoAssign(
            hasPendingManualTriage: viewModel.hasPendingManualTriage,
            refresh: refreshTriageSelections,
            openManualTriage: openManualTriage
        )
    }

    private func runAssignedExecutionsFromToolbar() {
        _ = ExecutionToolbarUseCase.runAssignedExecutions(
            isBatchRunning: isBatchRunning,
            isAutoCycleRunning: isAutoCycleRunning,
            setBatchRunning: { isBatchRunning = $0 },
            runAssignedExecutionsInBackground: { completion in
                viewModel.runAssignedTaskExecutionsInBackground(completion: completion)
            },
            refresh: refreshTriageSelections
        )
    }

    private func cancelAssignedExecutionsFromToolbar() {
        _ = ExecutionToolbarUseCase.cancelAssignedExecutions(
            isBatchRunning: isBatchRunning,
            requestCancelAssignedTaskExecutions: {
                viewModel.requestCancelAssignedTaskExecutions()
            }
        )
    }

    private func runAutoCycleFromToolbar() {
        _ = ExecutionToolbarUseCase.runAutoCycle(
            isAutoCycleRunning: isAutoCycleRunning,
            isBatchRunning: isBatchRunning,
            setAutoCycleRunning: { isAutoCycleRunning = $0 },
            runAutoDispatchCycleInBackground: { completion in
                viewModel.runAutoDispatchCycleInBackground(
                    maxPasses: autoCycleMaxPasses,
                    autoCreateMissingDependencies: autoCycleAutoCreateMissingDependencies
                ) { startedCount, _ in
                    completion(startedCount)
                }
            },
            refresh: refreshTriageSelections
        )
    }

    private func runDAGAutopilotFromToolbar() {
        _ = ExecutionToolbarUseCase.runAutoCycle(
            isAutoCycleRunning: isAutoCycleRunning,
            isBatchRunning: isBatchRunning,
            setAutoCycleRunning: { isAutoCycleRunning = $0 },
            runAutoDispatchCycleInBackground: { completion in
                viewModel.runDAGAutopilotInBackground { startedCount, _ in
                    completion(startedCount)
                }
            },
            refresh: refreshTriageSelections
        )
    }

    private func cancelAutoCycleFromToolbar() {
        _ = ExecutionToolbarUseCase.cancelAutoCycle(
            isAutoCycleRunning: isAutoCycleRunning,
            requestCancelAutoDispatchCycle: {
                viewModel.requestCancelAutoDispatchCycle()
            }
        )
    }

    private func resumeInterruptedExecutionFromToolbar() {
        guard !isBatchRunning, !isAutoCycleRunning else { return }

        if let action = ExecutionCheckpointUseCase.resumeAction(
            for: viewModel.executionCheckpoint,
            selectedBoardID: viewModel.selectedBoardID
        ) {
            switch action {
            case .assignedBatch:
                isBatchRunning = true
            case .autoCycle:
                isAutoCycleRunning = true
            }
        }

        viewModel.resumeExecutionFromCheckpointInBackground { resumed in
            if !resumed {
                self.isBatchRunning = false
                self.isAutoCycleRunning = false
                return
            }
            self.refreshTriageSelections()
            self.isBatchRunning = false
            self.isAutoCycleRunning = false
        }
    }

    private func clearExecutionCheckpointFromToolbar() {
        _ = viewModel.clearExecutionCheckpoint()
    }

    private func runGitHubPRFlowFromToolbar() {
        guard !isGitHubFlowRunning else { return }
        isGitHubFlowRunning = true
        viewModel.runGitHubPRFlowForSelectedBoardInBackground(
            repositoryPath: resolvedGitHubRepositoryPath,
            baseBranch: githubBaseBranch,
            remoteName: githubRemoteName,
            branchPrefix: githubBranchPrefix
        ) { _ in
            self.isGitHubFlowRunning = false
        }
    }

    private func syncAutoRetryDraftFromViewModel() {
        let config = viewModel.executionAutoRetryConfiguration
        autoRetryEnabled = config.isEnabled
        autoRetryMaxRetries = config.maxRetryCount
        autoRetryBackoffSeconds = config.backoffSeconds
        autoRetryRetryNetwork = config.retryableErrorTypes.contains(.network)
        autoRetryRetryRateLimit = config.retryableErrorTypes.contains(.rateLimit)
        autoRetryRetryServer = config.retryableErrorTypes.contains(.server)
    }

    private func syncApprovalGateDraftFromViewModel() {
        approvalGateEnabled = viewModel.executionApprovalPolicy.isEnabled
        approvalGateMinStoryPoints = viewModel.executionApprovalPolicy.minimumStoryPoints
    }

    private func applyApprovalGateSettings() {
        viewModel.updateExecutionApprovalPolicy(
            isEnabled: approvalGateEnabled,
            minimumStoryPoints: approvalGateMinStoryPoints
        )
    }

    private func syncQuotaGovernanceDraftFromViewModel() {
        quotaGovernanceEnabled = viewModel.executionQuotaPolicy.isEnabled
        quotaMaxEstimatedTokens = viewModel.executionQuotaPolicy.maxEstimatedTokens
        quotaMaxEstimatedCostUSD = viewModel.executionQuotaPolicy.maxEstimatedCostUSD
        quotaCostPer1KTokensUSD = viewModel.executionQuotaPolicy.costPer1KTokensUSD
    }

    private func applyQuotaGovernanceSettings() {
        viewModel.updateExecutionQuotaPolicy(
            isEnabled: quotaGovernanceEnabled,
            maxEstimatedTokens: quotaMaxEstimatedTokens,
            maxEstimatedCostUSD: quotaMaxEstimatedCostUSD,
            costPer1KTokensUSD: quotaCostPer1KTokensUSD
        )
    }

    private func syncParallelSchedulerDraftFromViewModel() {
        parallelSchedulerEnabled = viewModel.executionParallelizationPolicy.isEnabled
        parallelSchedulerMaxAgents = viewModel.executionParallelizationPolicy.maxConcurrentAgents
    }

    private func applyParallelSchedulerSettings() {
        viewModel.updateExecutionParallelizationPolicy(
            isEnabled: parallelSchedulerEnabled,
            maxConcurrentAgents: parallelSchedulerMaxAgents
        )
    }

    private func syncPRQualityGateDraftFromViewModel() {
        prQualityGateEnabled = viewModel.gitHubPRQualityGatePolicy.isEnabled
    }

    private func applyPRQualityGateSettings() {
        viewModel.updateGitHubPRQualityGatePolicy(isEnabled: prQualityGateEnabled)
    }

    private func syncDAGSchedulerDraftFromViewModel() {
        dagSchedulerEnabled = viewModel.dagExecutionPolicy.isEnabled
        dagSchedulerAutoAssignBeforeRun = viewModel.dagExecutionPolicy.autoAssignBeforeRun
        dagSchedulerAutoCreateDependencies = viewModel.dagExecutionPolicy.autoCreateMissingDependenciesDuringRun
        dagSchedulerMaxPasses = viewModel.dagExecutionPolicy.maxPasses
    }

    private func applyDAGSchedulerSettings() {
        viewModel.updateDAGExecutionPolicy(
            isEnabled: dagSchedulerEnabled,
            autoAssignBeforeRun: dagSchedulerAutoAssignBeforeRun,
            autoCreateMissingDependenciesDuringRun: dagSchedulerAutoCreateDependencies,
            maxPasses: dagSchedulerMaxPasses
        )
    }

    private func syncQualitySafetyGateDraftFromViewModel() {
        qualitySafetyGateEnabled = viewModel.executionQualitySafetyGatePolicy.isEnabled
        qualitySafetyRequireAcceptance = viewModel.executionQualitySafetyGatePolicy.requireAcceptanceCriteria
        qualitySafetyRequireCoverageIntent = viewModel.executionQualitySafetyGatePolicy.requireTestCoverageIntent
        qualitySafetyRequireSecurityPrivacyNotes = viewModel.executionQualitySafetyGatePolicy.requireSecurityPrivacyForSensitiveTasks
    }

    private func applyQualitySafetyGateSettings() {
        viewModel.updateExecutionQualitySafetyGatePolicy(
            isEnabled: qualitySafetyGateEnabled,
            requireAcceptanceCriteria: qualitySafetyRequireAcceptance,
            requireTestCoverageIntent: qualitySafetyRequireCoverageIntent,
            requireSecurityPrivacyForSensitiveTasks: qualitySafetyRequireSecurityPrivacyNotes
        )
    }

    private func applyAutoRetrySettings() {
        viewModel.updateExecutionAutoRetryConfiguration(
            isEnabled: autoRetryEnabled,
            maxRetryCount: autoRetryMaxRetries,
            backoffSeconds: autoRetryBackoffSeconds,
            retryableErrorTypes: ExecutionToolbarUseCase.selectedRetryableErrorTypes(
                retryNetwork: autoRetryRetryNetwork,
                retryRateLimit: autoRetryRetryRateLimit,
                retryServer: autoRetryRetryServer
            )
        )
    }

    private func applyHealthRecommendation(_ action: BoardHealthAction) {
        let applied = viewModel.applyHealthRecommendation(action)
        Self.postHealthRecommendation(
            action: action,
            applied: applied,
            hasPendingManualTriage: viewModel.hasPendingManualTriage,
            refresh: refreshTriageSelections,
            openManualTriage: openManualTriage,
            openNewAgent: openNewAgentSheet
        )
    }

    private func applyAllHealthRecommendations() {
        Self.postApplyAllHealthRecommendations(
            appliedCount: viewModel.applyAllHealthRecommendations(),
            hasPendingManualTriage: viewModel.hasPendingManualTriage,
            refresh: refreshTriageSelections,
            openManualTriage: openManualTriage
        )
    }

    private func openManualTriage() {
        refreshTriageSelections()
        isShowingManualTriageSheet = true
    }

    private func exportWorkspaceFromToolbar() {
        let panel = Self.configuredWorkspaceExportPanel()
        let (modalResponse, url) = Self.savePanelResultProvider(panel)

        _ = Self.handleSavePanelResult(
            modalResponse: modalResponse,
            url: url
        ) { url in
            viewModel.exportWorkspace(to: url)
        }
    }

    private func exportSelectedBoardFromToolbar() {
        let panel = Self.configuredSelectedBoardExportPanel(defaultFileName: selectedBoardExportFileName())
        let (modalResponse, url) = Self.savePanelResultProvider(panel)

        _ = Self.handleSavePanelResult(
            modalResponse: modalResponse,
            url: url
        ) { url in
            viewModel.exportSelectedBoard(to: url)
        }
    }

    private func exportExecutionReportJSONFromToolbar() {
        let panel = Self.configuredExecutionReportJSONPanel(defaultFileName: selectedBoardExecutionReportJSONFileName())
        let (modalResponse, url) = Self.savePanelResultProvider(panel)

        _ = Self.handleSavePanelResult(
            modalResponse: modalResponse,
            url: url
        ) { url in
            viewModel.exportExecutionReportJSONForSelectedBoard(to: url)
        }
    }

    private func exportExecutionReportMarkdownFromToolbar() {
        let panel = Self.configuredExecutionReportMarkdownPanel(defaultFileName: selectedBoardExecutionReportMarkdownFileName())
        let (modalResponse, url) = Self.savePanelResultProvider(panel)

        _ = Self.handleSavePanelResult(
            modalResponse: modalResponse,
            url: url
        ) { url in
            viewModel.exportExecutionReportMarkdownForSelectedBoard(to: url)
        }
    }

    private func importWorkspaceFromToolbar() {
        let panel = Self.configuredWorkspaceImportPanel()
        let (modalResponse, url) = Self.openPanelResultProvider(panel)

        _ = Self.handleWorkspaceImport(
            modalResponse: modalResponse,
            url: url,
            previewProvider: { url in
                viewModel.workspaceImportPreview(from: url)
            },
            strategyChooser: { preview in
                chooseWorkspaceImportStrategy(preview: preview)
            },
            importer: { url, strategy in
                viewModel.importWorkspace(from: url, strategy: strategy)
            },
            onImported: {
                handleBoardContextChanged()
            }
        )
    }

    fileprivate static func configuredWorkspaceExportPanel() -> NSSavePanel {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType.json]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.nameFieldStringValue = "openmac-workspace.json"
        panel.title = L10n.string("Export Workspace")
        panel.message = L10n.string("Save boards, tasks, and agents as workspace JSON.")
        return panel
    }

    fileprivate static func configuredSelectedBoardExportPanel(defaultFileName: String) -> NSSavePanel {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType.json]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.nameFieldStringValue = defaultFileName
        panel.title = L10n.string("Export Current Board")
        panel.message = L10n.string("Save only the current board as JSON.")
        return panel
    }

    fileprivate static func configuredExecutionReportJSONPanel(defaultFileName: String) -> NSSavePanel {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType.json]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.nameFieldStringValue = defaultFileName
        panel.title = L10n.string("Export Execution Report (JSON)")
        panel.message = L10n.string("Save execution report for current board as JSON.")
        return panel
    }

    fileprivate static func configuredExecutionReportMarkdownPanel(defaultFileName: String) -> NSSavePanel {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType.plainText]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.nameFieldStringValue = defaultFileName
        panel.title = L10n.string("Export Execution Report (Markdown)")
        panel.message = L10n.string("Save execution report for current board as Markdown.")
        return panel
    }

    fileprivate static func configuredWorkspaceImportPanel() -> NSOpenPanel {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.title = L10n.string("Import Workspace")
        panel.message = L10n.string("Select workspace JSON to import.")
        return panel
    }

    fileprivate static func workspaceImportInformativeText(preview: WorkspaceImportPreview) -> String {
        L10n.format(
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
    }

    fileprivate static func configuredWorkspaceImportAlert(preview: WorkspaceImportPreview) -> NSAlert {
        let alert = NSAlert()
        alert.messageText = L10n.string("Import Workspace")
        alert.informativeText = workspaceImportInformativeText(preview: preview)
        alert.addButton(withTitle: L10n.string("Merge"))
        alert.addButton(withTitle: L10n.string("Replace"))
        alert.addButton(withTitle: L10n.string("Cancel"))
        return alert
    }

    fileprivate static func workspaceImportStrategy(for modalResponse: NSApplication.ModalResponse) -> WorkspaceImportStrategy? {
        switch modalResponse {
        case .alertFirstButtonReturn:
            return .merge
        case .alertSecondButtonReturn:
            return .replace
        default:
            return nil
        }
    }

    private func chooseWorkspaceImportStrategy(preview: WorkspaceImportPreview) -> WorkspaceImportStrategy? {
        let alert = Self.configuredWorkspaceImportAlert(preview: preview)
        return Self.workspaceImportStrategy(for: Self.alertRunner(alert))
    }

    fileprivate func selectedBoardExportFileName() -> String {
        let rawTokens = viewModel.selectedBoardName
            .lowercased()
            .split { character in
                !(character.isLetter || character.isNumber)
            }
        let slug = rawTokens.joined(separator: "-")
        let resolvedSlug = slug.isEmpty ? "board" : slug
        return "openmac-\(resolvedSlug)-board.json"
    }

    fileprivate func selectedBoardExecutionReportJSONFileName() -> String {
        let rawTokens = viewModel.selectedBoardName
            .lowercased()
            .split { character in
                !(character.isLetter || character.isNumber)
            }
        let slug = rawTokens.joined(separator: "-")
        let resolvedSlug = slug.isEmpty ? "board" : slug
        return "openmac-\(resolvedSlug)-execution-report.json"
    }

    fileprivate func selectedBoardExecutionReportMarkdownFileName() -> String {
        let rawTokens = viewModel.selectedBoardName
            .lowercased()
            .split { character in
                !(character.isLetter || character.isNumber)
            }
        let slug = rawTokens.joined(separator: "-")
        let resolvedSlug = slug.isEmpty ? "board" : slug
        return "openmac-\(resolvedSlug)-execution-report.md"
    }

    fileprivate static func uniquePMBoardName(baseName: String, existingNames: [String]) -> String {
        let normalizedExisting = Set(existingNames.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() })
        let trimmedBase = baseName.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedBase = trimmedBase.isEmpty ? L10n.string("PM Project") : trimmedBase
        let normalizedBase = resolvedBase.lowercased()
        if !normalizedExisting.contains(normalizedBase) {
            return resolvedBase
        }

        var suffix = 2
        while true {
            let candidate = "\(resolvedBase) (\(suffix))"
            if !normalizedExisting.contains(candidate.lowercased()) {
                return candidate
            }
            suffix += 1
        }
    }

    fileprivate static let pmCustomTemplateID = "custom"

    fileprivate static func pmBriefTemplateOptions() -> [PMBriefTemplateOption] {
        let options = pmBriefTemplateDefinitions().map { definition in
            PMBriefTemplateOption(id: definition.id, title: L10n.string(definition.optionTitleKey))
        }
        return [PMBriefTemplateOption(id: pmCustomTemplateID, title: L10n.string("Custom Brief"))] + options
    }

    fileprivate static func applyPMTemplate(
        selectedTemplateID: String,
        projectName: inout String,
        projectBrief: inout String
    ) -> Bool {
        guard let definition = pmBriefTemplateDefinitions().first(where: { $0.id == selectedTemplateID }) else {
            return false
        }

        if projectName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            projectName = L10n.string(definition.defaultProjectNameKey)
        }
        projectBrief = L10n.string(definition.briefKey)
        return true
    }

    fileprivate static func applyPMTemplateAndReset(
        selectedTemplateID: String,
        projectName: inout String,
        projectBrief: inout String,
        planSummary: inout String,
        plannedTickets: inout [PMPlannedTicket]
    ) -> Bool {
        let applied = applyPMTemplate(
            selectedTemplateID: selectedTemplateID,
            projectName: &projectName,
            projectBrief: &projectBrief
        )
        guard applied else { return false }
        planSummary = ""
        plannedTickets = []
        return true
    }

    fileprivate static func applyPMBlueprint(
        vision: String,
        targetUsers: String,
        coreFeatures: String,
        techScope: String,
        constraints: String,
        qualityBar: String,
        projectName: inout String,
        projectBrief: inout String
    ) -> Bool {
        let composedBrief = pmBlueprintBriefText(
            vision: vision,
            targetUsers: targetUsers,
            coreFeatures: coreFeatures,
            techScope: techScope,
            constraints: constraints,
            qualityBar: qualityBar
        )
        guard !composedBrief.isEmpty else { return false }

        if projectName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let trimmedVision = vision.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedVision.isEmpty {
                projectName = trimmedVision
            }
        }
        projectBrief = composedBrief
        return true
    }

    fileprivate static func pmBlueprintBriefText(
        vision: String,
        targetUsers: String,
        coreFeatures: String,
        techScope: String,
        constraints: String,
        qualityBar: String
    ) -> String {
        let sections: [(String, String)] = [
            (L10n.string("Product Vision"), vision),
            (L10n.string("Target Users"), targetUsers),
            (L10n.string("Core Features"), coreFeatures),
            (L10n.string("Tech Scope"), techScope),
            (L10n.string("Constraints"), constraints),
            (L10n.string("Quality Bar"), qualityBar)
        ]

        let renderedSections = sections.compactMap { heading, value -> String? in
            let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedValue.isEmpty else { return nil }
            return "\(heading):\n\(trimmedValue)"
        }

        return renderedSections.joined(separator: "\n\n")
    }

    private static func pmBriefTemplateDefinitions() -> [PMBriefTemplateDefinition] {
        [
            PMBriefTemplateDefinition(
                id: "saas",
                optionTitleKey: "SaaS Product",
                defaultProjectNameKey: "SaaS MVP",
                briefKey: "PM Template Brief SaaS"
            ),
            PMBriefTemplateDefinition(
                id: "app",
                optionTitleKey: "Desktop App",
                defaultProjectNameKey: "Desktop App MVP",
                briefKey: "PM Template Brief App"
            ),
            PMBriefTemplateDefinition(
                id: "api",
                optionTitleKey: "Developer API",
                defaultProjectNameKey: "API Platform MVP",
                briefKey: "PM Template Brief API"
            )
        ]
    }

    fileprivate static func normalizedSkillList(from rawValue: String) -> [String] {
        Array(
            Set(
                rawValue
                    .split(separator: ",")
                    .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                    .filter { !$0.isEmpty }
            )
        )
        .sorted()
    }

    fileprivate static func pmPlanCopyText(
        projectName: String,
        summary: String,
        tickets: [PMPlannedTicket],
        testPlan: String = ""
    ) -> String {
        let trimmedProjectName = projectName.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedProjectName = trimmedProjectName.isEmpty ? L10n.string("PM Project") : trimmedProjectName
        let trimmedSummary = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedTestPlan = testPlan.trimmingCharacters(in: .whitespacesAndNewlines)

        var lines: [String] = [
            "# \(resolvedProjectName)",
            ""
        ]

        if !trimmedSummary.isEmpty {
            lines.append(trimmedSummary)
            lines.append("")
        }

        lines.append(L10n.format("Total Tickets: %d", tickets.count))
        let totalStoryPoints = tickets.reduce(0) { partialResult, ticket in
            partialResult + max(1, ticket.storyPoints)
        }
        lines.append(L10n.format("Total Story Points: %d", totalStoryPoints))
        lines.append(L10n.format("Total Milestones: %d", pmUniqueMilestoneCount(in: tickets)))
        lines.append(L10n.format("Total Epics: %d", pmUniqueEpicCount(in: tickets)))
        lines.append("")

        let roadmapText = pmRoadmapText(projectName: resolvedProjectName, tickets: tickets)
        if !roadmapText.isEmpty {
            lines.append("## \(L10n.string("Roadmap"))")
            lines.append(roadmapText)
            lines.append("")
        }

        if tickets.isEmpty {
            lines.append(L10n.string("No generated tickets yet. Click Generate Plan."))
        } else {
            for (index, ticket) in tickets.enumerated() {
                let trimmedTitle = ticket.title.trimmingCharacters(in: .whitespacesAndNewlines)
                let resolvedTitle = trimmedTitle.isEmpty ? L10n.string("New Task") : trimmedTitle
                lines.append("\(index + 1). \(resolvedTitle) (\(L10n.format("SP: %d", max(1, ticket.storyPoints))))")

                if !ticket.requiredSkills.isEmpty {
                    lines.append("   \(L10n.format("Skills: %@", ticket.requiredSkills.joined(separator: ", ")))")
                }
                let milestone = ticket.milestone.trimmingCharacters(in: .whitespacesAndNewlines)
                if !milestone.isEmpty {
                    lines.append("   \(L10n.format("Milestone: %@", milestone))")
                }
                let epic = ticket.epic.trimmingCharacters(in: .whitespacesAndNewlines)
                if !epic.isEmpty {
                    lines.append("   \(L10n.format("Epic: %@", epic))")
                }

                let trimmedDetails = ticket.details.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmedDetails.isEmpty {
                    lines.append("   \(trimmedDetails)")
                }
                lines.append("")
            }
        }

        if !trimmedTestPlan.isEmpty {
            lines.append("## \(L10n.string("Test Plan"))")
            lines.append(trimmedTestPlan)
        }

        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    fileprivate static func pmTestPlanText(
        projectName: String,
        projectBrief: String,
        tickets: [PMPlannedTicket]
    ) -> String {
        let trimmedProjectName = projectName.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedProjectName = trimmedProjectName.isEmpty ? L10n.string("PM Project") : trimmedProjectName
        let briefSnippet = projectBrief
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: " ")

        let totalStoryPoints = tickets.reduce(0) { partialResult, ticket in
            partialResult + max(1, ticket.storyPoints)
        }
        let criticalFlowTickets = tickets.filter { ticket in
            ticket.storyPoints >= 5 || ticket.title.lowercased().contains("core")
        }

        var lines: [String] = [
            "# \(L10n.string("Test Plan")) · \(resolvedProjectName)",
            "",
            L10n.format("Total Tickets: %d", tickets.count),
            L10n.format("Total Story Points: %d", totalStoryPoints),
            ""
        ]

        if !briefSnippet.isEmpty {
            lines.append("\(L10n.string("Project Brief")): \(briefSnippet)")
            lines.append("")
        }

        lines.append("1. \(L10n.string("Unit Test Coverage"))")
        if tickets.isEmpty {
            lines.append("- \(L10n.string("No generated tickets yet. Click Generate Plan."))")
        } else {
            for ticket in tickets.prefix(5) {
                lines.append("- \(ticket.title)")
            }
        }
        lines.append("")

        lines.append("2. \(L10n.string("Integration Test Flows"))")
        lines.append("- \(L10n.string("Validate cross-module contracts and data flow consistency."))")
        lines.append("- \(L10n.string("Verify assignment, state transitions, and persisted workspace behavior."))")
        lines.append("")

        lines.append("3. \(L10n.string("End-to-End Scenarios"))")
        if criticalFlowTickets.isEmpty {
            lines.append("- \(L10n.string("Run an end-to-end happy path from To Do to Done with review handoff."))")
        } else {
            for ticket in criticalFlowTickets.prefix(3) {
                lines.append("- \(L10n.format("Critical path: %@", ticket.title))")
            }
        }
        lines.append("")

        lines.append("4. \(L10n.string("Quality Gates"))")
        lines.append("- \(L10n.string("No blocker defects in critical paths."))")
        lines.append("- \(L10n.string("All acceptance criteria are covered by automated or manual checks."))")
        lines.append("")

        lines.append("5. \(L10n.string("Roadmap"))")
        if tickets.isEmpty {
            lines.append("- \(L10n.string("No generated tickets yet. Click Generate Plan."))")
        } else {
            let groupedByMilestone = Dictionary(grouping: tickets) { ticket in
                let milestone = ticket.milestone.trimmingCharacters(in: .whitespacesAndNewlines)
                return milestone.isEmpty ? L10n.string("Unscheduled") : milestone
            }
            let sortedMilestones = groupedByMilestone.keys.sorted {
                $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
            }

            for milestone in sortedMilestones {
                let milestoneTickets = (groupedByMilestone[milestone] ?? []).sorted {
                    $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
                }
                let milestoneStoryPoints = milestoneTickets.reduce(0) { partialResult, ticket in
                    partialResult + max(1, ticket.storyPoints)
                }
                let uniqueEpics = Set(
                    milestoneTickets
                        .map { $0.epic.trimmingCharacters(in: .whitespacesAndNewlines) }
                        .filter { !$0.isEmpty }
                )
                lines.append("- \(L10n.format("Milestone: %@", milestone))")
                lines.append(
                    "  \(L10n.format("Total Tickets: %d", milestoneTickets.count)), \(L10n.format("Total Story Points: %d", milestoneStoryPoints)), \(L10n.format("Total Epics: %d", uniqueEpics.count))"
                )
                for ticket in milestoneTickets.prefix(3) {
                    let title = ticket.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ? L10n.string("New Task")
                        : ticket.title.trimmingCharacters(in: .whitespacesAndNewlines)
                    let epic = ticket.epic.trimmingCharacters(in: .whitespacesAndNewlines)
                    if epic.isEmpty {
                        lines.append("  - \(title)")
                    } else {
                        lines.append("  - [\(epic)] \(title)")
                    }
                }
            }
        }

        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    fileprivate static func pmRoadmapText(
        projectName: String,
        tickets: [PMPlannedTicket]
    ) -> String {
        guard !tickets.isEmpty else { return "" }

        let grouped = Dictionary(grouping: tickets) { ticket -> String in
            let milestone = ticket.milestone.trimmingCharacters(in: .whitespacesAndNewlines)
            return milestone.isEmpty ? L10n.string("Unscheduled") : milestone
        }

        let sortedMilestones = grouped.keys.sorted { lhs, rhs in
            lhs.localizedCaseInsensitiveCompare(rhs) == .orderedAscending
        }

        var lines: [String] = []
        lines.append(L10n.format("Project: %@", projectName))
        lines.append(L10n.format("Total Milestones: %d", pmUniqueMilestoneCount(in: tickets)))
        lines.append(L10n.format("Total Epics: %d", pmUniqueEpicCount(in: tickets)))
        lines.append("")

        for milestone in sortedMilestones {
            let milestoneTickets = grouped[milestone] ?? []
            let uniqueEpics = Set(
                milestoneTickets
                    .map { $0.epic.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
            )
            lines.append(
                "- \(L10n.format("Milestone: %@", milestone)) · \(L10n.format("Total Tickets: %d", milestoneTickets.count)) · \(L10n.format("Total Epics: %d", uniqueEpics.count))"
            )
            for ticket in milestoneTickets {
                let title = ticket.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? L10n.string("New Task")
                    : ticket.title.trimmingCharacters(in: .whitespacesAndNewlines)
                let epic = ticket.epic.trimmingCharacters(in: .whitespacesAndNewlines)
                if epic.isEmpty {
                    lines.append("  - \(title) (\(L10n.format("SP: %d", max(1, ticket.storyPoints))))")
                } else {
                    lines.append("  - [\(epic)] \(title) (\(L10n.format("SP: %d", max(1, ticket.storyPoints))))")
                }
            }
        }

        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func pmUniqueMilestoneCount(in tickets: [PMPlannedTicket]) -> Int {
        Set(
            tickets
                .map { $0.milestone.trimmingCharacters(in: .whitespacesAndNewlines) }
                .map { $0.isEmpty ? L10n.string("Unscheduled") : $0 }
        ).count
    }

    private static func pmUniqueEpicCount(in tickets: [PMPlannedTicket]) -> Int {
        Set(
            tickets
                .map { $0.epic.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        ).count
    }

    fileprivate static func applyingDependencyChain(to tickets: [PMPlannedTicket]) -> [PMPlannedTicket] {
        guard !tickets.isEmpty else { return tickets }

        var chainedTickets: [PMPlannedTicket] = []
        chainedTickets.reserveCapacity(tickets.count)

        for index in tickets.indices {
            let ticket = tickets[index]
            let dependencyTitle: String
            if index == 0 {
                dependencyTitle = "none"
            } else {
                let previousTitle = tickets[index - 1].title.trimmingCharacters(in: .whitespacesAndNewlines)
                dependencyTitle = previousTitle.isEmpty ? L10n.string("New Task") : previousTitle
            }

            let dependencyLine = "Depends on: \(dependencyTitle)"
            let details = applyingDependencyLine(dependencyLine, to: ticket.details)
            chainedTickets.append(
                PMPlannedTicket(
                    title: ticket.title,
                    details: details,
                    requiredSkills: ticket.requiredSkills,
                    storyPoints: ticket.storyPoints,
                    epic: ticket.epic,
                    milestone: ticket.milestone
                )
            )
        }

        return chainedTickets
    }

    private static func applyingDependencyLine(_ dependencyLine: String, to details: String) -> String {
        let lines = details.components(separatedBy: .newlines)
        let retainedLines = lines.filter { !isDependencyLine($0) }
        let retainedBody = retainedLines
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if retainedBody.isEmpty {
            return dependencyLine
        }
        return "\(dependencyLine)\n\(retainedBody)"
    }

    private static func isDependencyLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let separatorIndex = trimmed.firstIndex(where: { $0 == ":" || $0 == "：" }) else {
            return false
        }

        let prefix = trimmed[..<separatorIndex]
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return
            prefix == "depends on" ||
            prefix == "dependency" ||
            prefix == "dependencies" ||
            prefix == "依賴" ||
            prefix == "依赖"
    }

    fileprivate static func applyingAutoAcceptanceCriteria(to ticket: PMPlannedTicket) -> PMPlannedTicket {
        let existingDetails = ticket.details.trimmingCharacters(in: .whitespacesAndNewlines)
        if existingDetails.localizedCaseInsensitiveContains("Acceptance Criteria:") ||
            existingDetails.localizedCaseInsensitiveContains("Acceptance:") {
            return ticket
        }

        let criteriaLines = pmAutoAcceptanceCriteriaLines(for: ticket)
        guard !criteriaLines.isEmpty else { return ticket }

        let criteriaBlock = ([L10n.string("Acceptance Criteria:")] + criteriaLines.map { "- \($0)" })
            .joined(separator: "\n")
        let combinedDetails = existingDetails.isEmpty
            ? criteriaBlock
            : "\(existingDetails)\n\n\(criteriaBlock)"

        return PMPlannedTicket(
            title: ticket.title,
            details: combinedDetails,
            requiredSkills: ticket.requiredSkills,
            storyPoints: ticket.storyPoints,
            epic: ticket.epic,
            milestone: ticket.milestone
        )
    }

    private static func pmAutoAcceptanceCriteriaLines(for ticket: PMPlannedTicket) -> [String] {
        let resolvedTitle = ticket.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? L10n.string("New Task")
            : ticket.title.trimmingCharacters(in: .whitespacesAndNewlines)
        var lines = [
            L10n.format("Implement and verify the scope for \"%@\".", resolvedTitle),
            L10n.string("Primary happy path and key edge cases are validated."),
            L10n.string("Automated tests are added or updated for critical behavior.")
        ]

        if !ticket.requiredSkills.isEmpty {
            lines.append(L10n.format("Required skills integration is verified: %@.", ticket.requiredSkills.joined(separator: ", ")))
        }
        if ticket.storyPoints >= 5 {
            lines.append(L10n.string("Performance and reliability checks pass for MVP load expectations."))
        }
        lines.append(L10n.string("Handoff notes include known limits, risks, and next actions."))
        return lines
    }

    private func assignManually(taskID: UUID) {
        let assigned = Self.manualAssignTask(
            taskID: taskID,
            selectedAgentID: triageSelectionByTaskID[taskID],
            assigner: viewModel.manuallyAssignTask
        )
        _ = Self.postManualAssignment(
            assigned: assigned,
            taskID: taskID,
            triageSelectionByTaskID: &triageSelectionByTaskID,
            refresh: refreshTriageSelections,
            hasRemainingCandidates: hasManualTriageCandidates,
            closeManualTriage: closeManualTriageSheet
        )
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
        _ = Self.handlePositiveCountResult(
            viewModel.unassignTodoTasks(for: agentID),
            onPositive: refreshTriageSelections
        )
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
        _ = Self.handleBoolResult(
            viewModel.autoAssignTask(taskID),
            onChanged: refreshTriageSelections
        )
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
            _ = Self.handleBoolResult(retried, onChanged: refreshTriageSelections)
        }
    }

    private func copyTaskExecutionTimeline(_ taskID: UUID) {
        guard let timeline = viewModel.replayExecutionTimeline(for: taskID) else { return }
        copyToPasteboard(timeline)
    }

    private func assignTaskToAgent(_ taskID: UUID, _ agentID: UUID) {
        _ = Self.handleBoolResult(
            viewModel.manuallyAssignTask(taskID, to: agentID),
            onChanged: refreshTriageSelections
        )
    }

    private func reassignTaskToAgent(_ taskID: UUID, _ agentID: UUID) {
        _ = Self.handleBoolResult(
            viewModel.reassignTask(taskID, to: agentID),
            onChanged: refreshTriageSelections
        )
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
        let runtimeProfile = buildRuntimeProfile(
            isEnabled: editAgentRuntimeEnabled,
            provider: editAgentRuntimeProvider,
            model: editAgentRuntimeModel,
            endpoint: editAgentRuntimeEndpoint,
            toolsText: editAgentRuntimeTools,
            openAIAuthMode: editAgentOpenAIAuthMode,
            codexProfile: editAgentCodexProfile
        )

        _ = Self.handleBoolResult(
            Self.applyAgentEdits(
                viewModel: viewModel,
                editingAgentID: editingAgentID,
                name: editAgentName,
                skillsText: editAgentSkills,
                maxConcurrentTasks: editAgentCapacity,
                runtimeProfile: runtimeProfile
            ),
            onChanged: refreshAndCloseEditAgentSheet
        )
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
        Self.resolveSelectedAssigneeFilter(
            selectedKey: selectedAssigneeFilterKey,
            agents: viewModel.agents
        )
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
        Self.resolveSelectedAgentForConsole(
            selectedAgentID: selectedAgentConsoleAgentID,
            agents: viewModel.agents
        )
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

    private var pmTemplateOptions: [PMBriefTemplateOption] {
        Self.pmBriefTemplateOptions()
    }

    private var selectedBoardDependencyInsights: DependencyGraphInsights {
        viewModel.selectedBoardDependencyInsights
    }

    private var resolvedGitHubRepositoryPath: String {
        let trimmed = githubRepositoryPath.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? resolvedCodexProjectsDirectoryPath : trimmed
    }

    private func resetTaskFilters() {
        taskSearchQuery = ""
        selectedAssigneeFilterKey = "all"
    }

    private func hasManualTriageCandidates() -> Bool {
        !viewModel.triageCandidates().isEmpty
    }

    private func closeManualTriageSheet() {
        isShowingManualTriageSheet = false
    }

    private func closeNewBoardSheetAndHandleContext() {
        closeNewBoardSheet()
        handleBoardContextChanged()
    }

    private func refreshAndCloseEditTaskSheet() {
        refreshTriageSelections()
        closeEditTaskSheet()
    }

    private func refreshAndResetTaskDraft() {
        refreshTriageSelections()
        resetDraftAndClose()
    }

    private func openNewAgentSheet() {
        isShowingNewAgentSheet = true
    }

    private func refreshAndCloseEditAgentSheet() {
        refreshTriageSelections()
        closeEditAgentSheet()
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

        let (modalResponse, url) = Self.openPanelResultProvider(panel)
        guard modalResponse == .OK, let url else { return }
        codexProjectsDirectoryPath = url.path
        ensureCodexProjectsDirectoryExists()
    }

    private func chooseGitHubRepositoryDirectory() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = false
        panel.title = L10n.string("Choose GitHub Repository")
        panel.message = L10n.string("Select the git repository folder used for branch/PR automation.")
        panel.prompt = L10n.string("Use Folder")
        panel.directoryURL = URL(fileURLWithPath: resolvedGitHubRepositoryPath, isDirectory: true)

        let (modalResponse, url) = Self.openPanelResultProvider(panel)
        guard modalResponse == .OK, let url else { return }
        githubRepositoryPath = url.path
    }

    private func useDefaultCodexProjectsDirectory() {
        codexProjectsDirectoryPath = ""
        ensureCodexProjectsDirectoryExists()
    }

    private func openCodexProjectsDirectoryInFinder() {
        do {
            let url = try Self.codexDirectoryEnsurer(resolvedCodexProjectsDirectoryPath)
            Self.workspaceActivator([url])
        } catch {
            presentCodexProjectsDirectoryError(error, attemptedPath: resolvedCodexProjectsDirectoryPath)
        }
    }

    private func openGitHubRepositoryInFinder() {
        let path = resolvedGitHubRepositoryPath
        let expanded = (path as NSString).expandingTildeInPath
        let url = URL(fileURLWithPath: expanded, isDirectory: true)
        Self.workspaceActivator([url])
    }

    private func ensureCodexProjectsDirectoryExists() {
        do {
            _ = try Self.codexDirectoryEnsurer(resolvedCodexProjectsDirectoryPath)
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
        _ = Self.alertRunner(alert)
    }

    private func syncSelectedAgentConsoleSelection() {
        selectedAgentConsoleAgentID = Self.syncedSelectedAgentConsoleAgentID(
            currentID: selectedAgentConsoleAgentID,
            agents: viewModel.agents
        )
    }

    private func normalizeAssigneeFilterSelection() {
        var validKeys: Set<String> = []
        for option in assigneeFilterOptions {
            validKeys.insert(option.key)
        }
        selectedAssigneeFilterKey = Self.normalizedAssigneeFilterKey(
            currentKey: selectedAssigneeFilterKey,
            validKeys: validKeys
        )
    }

    private var canAutoAssignFromToolbar: Bool {
        Self.canAutoAssignFromToolbar(
            unassignedTodoTaskCount: viewModel.unassignedTodoTaskCount,
            hasAgents: !viewModel.agents.isEmpty
        )
    }

    private var canBatchRunAssignedTasks: Bool {
        Self.canBatchRunAssignedTasks(
            tasks: viewModel.tasks,
            isBatchRunning: isBatchRunning,
            isAutoCycleRunning: isAutoCycleRunning
        )
    }

    private var canRunAutoCycle: Bool {
        Self.canRunAutoCycle(
            tasks: viewModel.tasks,
            isBatchRunning: isBatchRunning,
            isAutoCycleRunning: isAutoCycleRunning
        )
    }

    @ViewBuilder
    private func boardMessageSection(_ message: String) -> some View {
        let messageColor = BoardMessageColorPalette.color(
            for: viewModel.lastBoardMessageSeverity,
            scheme: effectiveColorScheme
        )
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(messageColor)
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

    @ViewBuilder
    private func agentSidebarRow(for agent: AgentProfile) -> some View {
        let isSelected = selectedAgentConsoleAgentID == agent.id
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
            isSelected: isSelected
        )
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture {
            selectedAgentConsoleAgentID = agent.id
        }
        .listRowBackground(
            isSelected
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

    @ViewBuilder
    private func kanbanColumn(for status: KanbanStatus) -> some View {
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
            dependencyBlockedReason: { task in
                viewModel.dependencyBlockReason(for: task.id)
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
            hasExecutionTimeline: { task in
                viewModel.hasExecutionTimeline(for: task.id)
            },
            onCopyExecutionTimeline: copyTaskExecutionTimeline,
            onDropTask: { taskID in
                viewModel.handleDrop(taskID, to: status)
            }
        )
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

    private static func resolveSelectedAssigneeFilter(
        selectedKey: String,
        agents: [AgentProfile]
    ) -> TaskAssigneeFilter {
        if selectedKey == "all" {
            return .all
        }
        if selectedKey == "unassigned" {
            return .unassigned
        }
        guard let id = UUID(uuidString: selectedKey),
              agents.contains(where: { $0.id == id }) else {
            return .all
        }
        return .assigned(id)
    }

    private static func canAutoAssignFromToolbar(
        unassignedTodoTaskCount: Int,
        hasAgents: Bool
    ) -> Bool {
        unassignedTodoTaskCount > 0 && hasAgents
    }

    private static func canBatchRunAssignedTasks(
        tasks: [WorkTask],
        isBatchRunning: Bool,
        isAutoCycleRunning: Bool
    ) -> Bool {
        guard !isBatchRunning, !isAutoCycleRunning else { return false }
        return tasks.contains { task in
            guard (task.status == .todo || task.status == .inProgress),
                  task.assignedAgentID != nil else {
                return false
            }
            return !task.details.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private static func canRunAutoCycle(
        tasks: [WorkTask],
        isBatchRunning: Bool,
        isAutoCycleRunning: Bool
    ) -> Bool {
        guard !isBatchRunning, !isAutoCycleRunning else { return false }
        return tasks.contains { task in
            task.status == .todo || task.status == .inProgress
        }
    }

    private static func containsAgent(id: UUID, in agents: [AgentProfile]) -> Bool {
        for agent in agents where agent.id == id {
            return true
        }
        return false
    }

    fileprivate static func resolveSelectedAgentForConsole(
        selectedAgentID: UUID?,
        agents: [AgentProfile]
    ) -> AgentProfile? {
        guard let selectedAgentID else { return agents.first }
        return agents.first(where: { $0.id == selectedAgentID }) ?? agents.first
    }

    fileprivate static func syncedSelectedAgentConsoleAgentID(
        currentID: UUID?,
        agents: [AgentProfile]
    ) -> UUID? {
        guard !agents.isEmpty else { return nil }
        if let currentID, containsAgent(id: currentID, in: agents) {
            return currentID
        }
        return agents.first?.id
    }

    fileprivate static func normalizedAssigneeFilterKey(
        currentKey: String,
        validKeys: Set<String>
    ) -> String {
        validKeys.contains(currentKey) ? currentKey : "all"
    }

    fileprivate static func handleBoolResult(
        _ changed: Bool,
        onChanged: () -> Void
    ) -> Bool {
        guard changed else { return false }
        onChanged()
        return true
    }

    fileprivate static func handlePositiveCountResult(
        _ count: Int,
        onPositive: () -> Void
    ) -> Int {
        guard count > 0 else { return 0 }
        onPositive()
        return count
    }

    fileprivate static func applyEditableChange<ID>(
        editingID: ID?,
        apply: (ID) -> Bool,
        onApplied: () -> Void
    ) -> Bool {
        guard let editingID else { return false }
        return handleBoolResult(apply(editingID), onChanged: onApplied)
    }

    fileprivate static func manualAssignTask(
        taskID: UUID,
        selectedAgentID: UUID?,
        assigner: (UUID, UUID) -> Bool
    ) -> Bool {
        guard let selectedAgentID else { return false }
        return assigner(taskID, selectedAgentID)
    }

    fileprivate static func postManualAssignment(
        assigned: Bool,
        taskID: UUID,
        triageSelectionByTaskID: inout [UUID: UUID],
        refresh: () -> Void,
        hasRemainingCandidates: () -> Bool,
        closeManualTriage: () -> Void
    ) -> Bool {
        guard assigned else { return false }

        triageSelectionByTaskID.removeValue(forKey: taskID)
        refresh()
        if !hasRemainingCandidates() {
            closeManualTriage()
        }
        return true
    }

    fileprivate static func applyTaskEdits(
        viewModel: KanbanBoardViewModel,
        editingTaskID: UUID?,
        title: String,
        details: String,
        requiredSkillsText: String,
        storyPoints: Int
    ) -> Bool {
        guard let editingTaskID else { return false }
        return applyTaskEdits(
            viewModel: viewModel,
            taskID: editingTaskID,
            title: title,
            details: details,
            requiredSkillsText: requiredSkillsText,
            storyPoints: storyPoints
        )
    }

    fileprivate static func applyAgentEdits(
        viewModel: KanbanBoardViewModel,
        editingAgentID: UUID?,
        name: String,
        skillsText: String,
        maxConcurrentTasks: Int,
        runtimeProfile: AgentRuntimeProfile?
    ) -> Bool {
        guard let editingAgentID else { return false }
        return applyAgentEdits(
            viewModel: viewModel,
            agentID: editingAgentID,
            name: name,
            skillsText: skillsText,
            maxConcurrentTasks: maxConcurrentTasks,
            runtimeProfile: runtimeProfile
        )
    }

    fileprivate static func postAutoAssign(
        hasPendingManualTriage: Bool,
        refresh: () -> Void,
        openManualTriage: () -> Void
    ) {
        refresh()
        if hasPendingManualTriage {
            openManualTriage()
        }
    }

    fileprivate static func postHealthRecommendation(
        action: BoardHealthAction,
        applied: Bool,
        hasPendingManualTriage: Bool,
        refresh: () -> Void,
        openManualTriage: () -> Void,
        openNewAgent: () -> Void
    ) {
        guard applied else { return }

        switch action {
        case .autoAssignUnassignedTodo:
            refresh()
            if hasPendingManualTriage {
                openManualTriage()
            }
        case .createMissingDependencyTasks, .rebalanceTodoLoad, .archiveDone:
            refresh()
        case .openManualTriage:
            refresh()
            openManualTriage()
        case .openNewAgent:
            openNewAgent()
        case .increaseWIPLimit(_):
            break
        }
    }

    fileprivate static func postApplyAllHealthRecommendations(
        appliedCount: Int,
        hasPendingManualTriage: Bool,
        refresh: () -> Void,
        openManualTriage: () -> Void
    ) {
        guard appliedCount > 0 else { return }

        refresh()
        if hasPendingManualTriage {
            openManualTriage()
        }
    }

    fileprivate static func handleSavePanelResult(
        modalResponse: NSApplication.ModalResponse,
        url: URL?,
        exporter: (URL) -> Bool
    ) -> Bool {
        guard modalResponse == .OK, let url else { return false }
        return exporter(url)
    }

    fileprivate static func handleWorkspaceImport(
        modalResponse: NSApplication.ModalResponse,
        url: URL?,
        previewProvider: (URL) -> WorkspaceImportPreview?,
        strategyChooser: (WorkspaceImportPreview) -> WorkspaceImportStrategy?,
        importer: (URL, WorkspaceImportStrategy) -> Bool,
        onImported: () -> Void
    ) -> Bool {
        guard modalResponse == .OK, let url else { return false }
        guard let preview = previewProvider(url) else { return false }
        guard let strategy = strategyChooser(preview) else { return false }
        let imported = importer(url, strategy)
        if imported {
            onImported()
        }
        return imported
    }

    fileprivate static func applyTaskEdits(
        viewModel: KanbanBoardViewModel,
        taskID: UUID,
        title: String,
        details: String,
        requiredSkillsText: String,
        storyPoints: Int
    ) -> Bool {
        viewModel.updateTask(
            taskID,
            title: title,
            details: details,
            requiredSkillsText: requiredSkillsText,
            storyPoints: storyPoints
        )
    }

    fileprivate static func applyAgentEdits(
        viewModel: KanbanBoardViewModel,
        agentID: UUID,
        name: String,
        skillsText: String,
        maxConcurrentTasks: Int,
        runtimeProfile: AgentRuntimeProfile?
    ) -> Bool {
        viewModel.updateAgent(
            agentID,
            name: name,
            skillsText: skillsText,
            maxConcurrentTasks: maxConcurrentTasks,
            runtimeProfile: runtimeProfile
        )
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
    let blockedTasks: Int
    let criticalPathStoryPoints: Int

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
                SummaryBadge(title: L10n.string("Blocked"), value: "\(blockedTasks)", accent: blockedTasks > 0 ? .red : .green)
                SummaryBadge(
                    title: L10n.string("Critical Path"),
                    value: L10n.format("%d SP", criticalPathStoryPoints),
                    accent: criticalPathStoryPoints > 0 ? .amber : .blue
                )
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

private struct BoardDependencyInsightsView: View {
    @Environment(\.colorScheme) private var colorScheme
    let insights: DependencyGraphInsights

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Text(L10n.string("Dependency Graph"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(BoardNeutralTextPalette.color(for: .secondary, scheme: colorScheme))
                Text(
                    L10n.format(
                        "Blocked %d · Dependencies %d",
                        insights.blockedTaskCount,
                        insights.totalTaskDependencies
                    )
                )
                .font(.caption2)
                .foregroundStyle(BoardNeutralTextPalette.color(for: .secondary, scheme: colorScheme))
            }

            if !insights.criticalPathTaskTitles.isEmpty {
                Text(
                    L10n.format(
                        "Critical Path (%d SP): %@",
                        insights.criticalPathStoryPoints,
                        insights.criticalPathTaskTitles.joined(separator: " -> ")
                    )
                )
                .font(.caption)
                .foregroundStyle(BoardSemanticTextPalette.color(for: .warning, scheme: colorScheme))
                .lineLimit(2)
            }

            if !insights.cycleTaskTitles.isEmpty {
                Text(L10n.format("Cycle detected: %@", insights.cycleTaskTitles.joined(separator: ", ")))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(BoardSemanticTextPalette.color(for: .error, scheme: colorScheme))
                    .lineLimit(2)
            }
        }
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
    let dependencyBlockedReason: (WorkTask) -> String?
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
    let hasExecutionTimeline: (WorkTask) -> Bool
    let onCopyExecutionTimeline: (UUID) -> Void
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
                    taskCard(for: task)
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

    private func taskCard(for task: WorkTask) -> some View {
        let blockedReason = dependencyBlockedReason(task)
        return TaskCardView(
            task: task,
            assigneeName: assigneeName(task),
            assignmentReason: assignmentReason(task),
            dependencyBlockedReason: blockedReason,
            canMoveBackward: status.previous != nil,
            canMoveForward: status.next != nil,
            canUnassign: task.assignedAgentID != nil && task.status != .done,
            canAutoAssign: task.status == .todo && task.assignedAgentID == nil,
            canRunAgent: task.assignedAgentID != nil && task.status != .done && blockedReason == nil,
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
            hasExecutionTimeline: hasExecutionTimeline(task),
            onCopyExecutionTimeline: {
                onCopyExecutionTimeline(task.id)
            },
            onMoveBackward: { moveBackward(task) },
            onMoveForward: { moveForward(task) }
        )
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
    let dependencyBlockedReason: String?
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
    let hasExecutionTimeline: Bool
    let onCopyExecutionTimeline: () -> Void
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

            if let dependencyBlockedReason {
                HStack(spacing: 6) {
                    Text(L10n.string("Blocked"))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(BoardSemanticTextPalette.color(for: .error, scheme: colorScheme))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            BoardSemanticTextPalette.color(for: .error, scheme: colorScheme).opacity(0.14),
                            in: Capsule()
                        )
                    Text(dependencyBlockedReason)
                        .font(.caption2)
                        .foregroundStyle(BoardSemanticTextPalette.color(for: .error, scheme: colorScheme))
                        .lineLimit(2)
                }
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
            if hasExecutionTimeline {
                Button(L10n.string("Copy Execution Timeline"), action: onCopyExecutionTimeline)
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
    let timelineText: String?
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

            if let timeline = details.timelineText, !timeline.isEmpty {
                executionTextSection(
                    title: L10n.string("Execution Timeline"),
                    value: timeline,
                    tint: BoardNeutralTextPalette.color(for: .secondary, scheme: colorScheme),
                    copyButtonTitle: L10n.string("Copy Timeline")
                )
            } else {
                Text(L10n.string("No execution timeline yet."))
                    .font(.caption)
                    .foregroundStyle(BoardNeutralTextPalette.color(for: .secondary, scheme: colorScheme))
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
                    Button(L10n.string("Copy All")) {
                        onCopy(allEventsText)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
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

    private var allEventsText: String {
        events.map { event in
            let header = "[\(statusLabel(for: event))] \(Self.eventDateFormatter.string(from: event.timestamp)) \(event.taskTitle)"
            return [header, event.message, event.details]
                .compactMap { value in
                    guard let value else { return nil }
                    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                    return trimmed.isEmpty ? nil : trimmed
                }
                .joined(separator: "\n")
        }
        .joined(separator: "\n\n")
    }

    private func statusLabel(for event: AgentExecutionEvent) -> String {
        switch event.status {
        case .running:
            return L10n.string("Running")
        case .succeeded:
            return L10n.string("Succeeded")
        case .failed:
            return L10n.string("Failed")
        }
    }

    private static let eventDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .medium
        return formatter
    }()
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

private struct PMPlannerSheet: View {
    @Binding var projectName: String
    @Binding var projectBrief: String
    @Binding var autoAssignAfterCreate: Bool
    @Binding var createNewBoardForPlan: Bool
    @Binding var autopilotMaxPasses: Int
    @Binding var autoCreateMissingDependenciesDuringCycle: Bool
    let planSummary: String
    @Binding var plannedTickets: [PMPlannedTicket]
    @Binding var selectedTemplateID: String
    let templateOptions: [PMBriefTemplateOption]
    @Binding var blueprintVision: String
    @Binding var blueprintTargetUsers: String
    @Binding var blueprintCoreFeatures: String
    @Binding var blueprintTechScope: String
    @Binding var blueprintConstraints: String
    @Binding var blueprintQualityBar: String
    let testPlanText: String
    let boardMessage: String?
    let boardMessageSeverity: BoardMessageSeverity?
    let onCancel: () -> Void
    let onApplyTemplate: () -> Void
    let onApplyTemplateAndGenerate: () -> Void
    let onApplyBlueprint: () -> Void
    let onApplyBlueprintAndGenerate: () -> Void
    let onGeneratePlan: () -> Void
    let onGenerateTestPlan: () -> Void
    let onCreateMissingAgents: () -> Void
    let onChainDependencies: () -> Void
    let onAutoACForAllTickets: () -> Void
    let onAutoACTicket: (Int) -> Void
    let onCreateTickets: () -> Void
    let onCreateAndRun: () -> Void
    let onRunAutopilot: () -> Void
    let onCopyPlan: () -> Void
    let onCopyTestPlan: () -> Void
    let onCopyBlueprint: () -> Void

    private var totalStoryPoints: Int {
        plannedTickets.reduce(0) { $0 + max(1, $1.storyPoints) }
    }

    private var totalMilestones: Int {
        Set(
            plannedTickets
                .map { $0.milestone.trimmingCharacters(in: .whitespacesAndNewlines) }
                .map { $0.isEmpty ? L10n.string("Unscheduled") : $0 }
        ).count
    }

    private var totalEpics: Int {
        Set(
            plannedTickets
                .map { $0.epic.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        ).count
    }

    private var roadmapText: String {
        ContentView.pmRoadmapText(projectName: projectName, tickets: plannedTickets)
    }

    private var hasPlannedSkills: Bool {
        plannedTickets.contains { ticket in
            !ticket.requiredSkills.isEmpty
        }
    }

    private var hasAutopilotInput: Bool {
        !plannedTickets.isEmpty || !projectBrief.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var hasBlueprintInput: Bool {
        let fields = [
            blueprintVision,
            blueprintTargetUsers,
            blueprintCoreFeatures,
            blueprintTechScope,
            blueprintConstraints,
            blueprintQualityBar
        ]
        return fields.contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.string("PM Plan Project"))
                .font(.title3.weight(.semibold))

            if let boardMessage, !boardMessage.isEmpty {
                BoardMessageBanner(message: boardMessage, severity: boardMessageSeverity)
            }

            TextField(L10n.string("Project Name (optional)"), text: $projectName)
                .textFieldStyle(.roundedBorder)

            HStack(spacing: 10) {
                Picker(L10n.string("PM Template"), selection: $selectedTemplateID) {
                    ForEach(templateOptions) { option in
                        Text(option.title).tag(option.id)
                    }
                }
                .pickerStyle(.menu)

                Button(L10n.string("Apply Template"), action: onApplyTemplate)
                    .disabled(selectedTemplateID == ContentView.pmCustomTemplateID)

                Button(L10n.string("Apply + Generate"), action: onApplyTemplateAndGenerate)
                    .disabled(selectedTemplateID == ContentView.pmCustomTemplateID)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(L10n.string("Blueprint Wizard"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                TextField(L10n.string("Product Vision"), text: $blueprintVision)
                TextField(L10n.string("Target Users"), text: $blueprintTargetUsers)
                TextField(L10n.string("Core Features"), text: $blueprintCoreFeatures)
                TextField(L10n.string("Tech Scope"), text: $blueprintTechScope)
                TextField(L10n.string("Constraints"), text: $blueprintConstraints)
                TextField(L10n.string("Quality Bar"), text: $blueprintQualityBar)

                HStack {
                    Button(L10n.string("Build Brief from Blueprint"), action: onApplyBlueprint)
                        .disabled(!hasBlueprintInput)
                    Button(L10n.string("Build + Generate"), action: onApplyBlueprintAndGenerate)
                        .disabled(!hasBlueprintInput)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(10)
            .background(.quinary, in: RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.string("Project Brief"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                TextEditor(text: $projectBrief)
                    .font(.body)
                    .frame(minHeight: 96, maxHeight: 120)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.secondary.opacity(0.35), lineWidth: 1)
                    )
            }

            Text(L10n.string("Describe your goal, scope, and constraints. PM planner will turn this into executable tickets."))
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(L10n.string("PM templates prefill the project brief so you can generate tickets faster."))
                .font(.caption2)
                .foregroundStyle(.secondary)

            Toggle(L10n.string("Auto Assign After Create"), isOn: $autoAssignAfterCreate)
            Toggle(L10n.string("Create New Board for Plan"), isOn: $createNewBoardForPlan)
            Toggle(
                L10n.string("Auto Create Missing Dependencies During Cycle"),
                isOn: $autoCreateMissingDependenciesDuringCycle
            )
            Stepper(
                L10n.format("Autopilot Max Passes: %d", max(1, min(12, autopilotMaxPasses))),
                value: $autopilotMaxPasses,
                in: 1 ... 12
            )

            if !planSummary.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.string("Plan Summary"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(planSummary)
                        .font(.caption)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .padding(10)
                .background(.quinary, in: RoundedRectangle(cornerRadius: 10))
            }

            if !plannedTickets.isEmpty {
                HStack(spacing: 12) {
                    Text(L10n.format("Total Tickets: %d", plannedTickets.count))
                        .font(.caption.weight(.semibold))
                    Text(L10n.format("Total Story Points: %d", totalStoryPoints))
                        .font(.caption.weight(.semibold))
                    Text(L10n.format("Total Milestones: %d", totalMilestones))
                        .font(.caption.weight(.semibold))
                    Text(L10n.format("Total Epics: %d", totalEpics))
                        .font(.caption.weight(.semibold))
                    Spacer()
                    Button(L10n.string("Create Missing Agents"), action: onCreateMissingAgents)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(!hasPlannedSkills)
                    Button(L10n.string("Chain Dependencies"), action: onChainDependencies)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(plannedTickets.count < 2)
                    Button(L10n.string("Auto AC for All Tickets"), action: onAutoACForAllTickets)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    Button(L10n.string("Generate Test Plan"), action: onGenerateTestPlan)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
                .foregroundStyle(.secondary)
            }

            if !roadmapText.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n.string("Roadmap"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    ScrollView {
                        Text(roadmapText)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 120)
                    .padding(8)
                    .background(.quinary, in: RoundedRectangle(cornerRadius: 10))
                }
            }

            if plannedTickets.isEmpty {
                Text(L10n.string("No generated tickets yet. Click Generate Plan."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 8)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(plannedTickets.indices, id: \.self) { index in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(alignment: .top) {
                                    Text("#\(index + 1)")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    Text(L10n.format("SP: %d", max(1, plannedTickets[index].storyPoints)))
                                        .font(.caption.weight(.semibold))
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 3)
                                        .background(.quaternary, in: Capsule())
                                }

                                TextField(
                                    L10n.string("Title"),
                                    text: Binding(
                                        get: { plannedTickets[index].title },
                                        set: { plannedTickets[index].title = $0 }
                                    )
                                )

                                TextField(
                                    L10n.string("Skills (comma separated)"),
                                    text: Binding(
                                        get: { plannedTickets[index].requiredSkills.joined(separator: ", ") },
                                        set: { plannedTickets[index].requiredSkills = ContentView.normalizedSkillList(from: $0) }
                                    )
                                )
                                .font(.caption)

                                HStack(spacing: 8) {
                                    TextField(
                                        L10n.string("Milestone"),
                                        text: Binding(
                                            get: { plannedTickets[index].milestone },
                                            set: { plannedTickets[index].milestone = $0 }
                                        )
                                    )
                                    .font(.caption)

                                    TextField(
                                        L10n.string("Epic"),
                                        text: Binding(
                                            get: { plannedTickets[index].epic },
                                            set: { plannedTickets[index].epic = $0 }
                                        )
                                    )
                                    .font(.caption)
                                }

                                Stepper(
                                    L10n.format("Story Points: %d", max(1, plannedTickets[index].storyPoints)),
                                    value: Binding(
                                        get: { max(1, plannedTickets[index].storyPoints) },
                                        set: { plannedTickets[index].storyPoints = max(1, min(13, $0)) }
                                    ),
                                    in: 1 ... 13
                                )
                                .font(.caption)

                                TextEditor(
                                    text: Binding(
                                        get: { plannedTickets[index].details },
                                        set: { plannedTickets[index].details = $0 }
                                    )
                                )
                                .font(.caption)
                                .frame(minHeight: 72, maxHeight: 92)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                                )

                                HStack {
                                    Button(L10n.string("Auto AC")) {
                                        onAutoACTicket(index)
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                    Spacer()
                                    Button(L10n.string("Remove Ticket")) {
                                        plannedTickets.remove(at: index)
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                }
                            }
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(.quinary, in: RoundedRectangle(cornerRadius: 10))
                        }

                        HStack {
                            Spacer()
                            Button(L10n.string("Add Ticket")) {
                                plannedTickets.append(
                                    PMPlannedTicket(
                                        title: L10n.string("New Task"),
                                        details: "",
                                        requiredSkills: [],
                                        storyPoints: 1,
                                        epic: "",
                                        milestone: ""
                                    )
                                )
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .frame(maxHeight: 280)
            }

            if !testPlanText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(L10n.string("Test Plan"))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button(L10n.string("Copy Test Plan"), action: onCopyTestPlan)
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }

                    ScrollView {
                        Text(testPlanText)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 130)
                    .padding(8)
                    .background(.quinary, in: RoundedRectangle(cornerRadius: 10))
                }
            }

            HStack {
                Spacer()
                Button(L10n.string("Copy"), action: onCopyPlan)
                    .disabled(
                        plannedTickets.isEmpty &&
                            planSummary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                            testPlanText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    )
                Button(L10n.string("Copy Blueprint JSON"), action: onCopyBlueprint)
                    .disabled(projectBrief.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Button(L10n.string("Cancel"), action: onCancel)
                Button(L10n.string("Generate Plan"), action: onGeneratePlan)
                    .keyboardShortcut(.defaultAction)
                Button(L10n.format("Create Tickets (%d)", plannedTickets.count), action: onCreateTickets)
                    .disabled(plannedTickets.isEmpty)
                Button(L10n.string("Create + Run Assigned"), action: onCreateAndRun)
                    .disabled(plannedTickets.isEmpty)
                Button(L10n.string("Autopilot Create + Run"), action: onRunAutopilot)
                    .disabled(!hasAutopilotInput)
            }
        }
        .padding(18)
        .frame(width: 680, height: 820)
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
    @Binding var selectedTemplateID: UUID?
    let templates: [TaskTemplate]
    let boardMessage: String?
    let boardMessageSeverity: BoardMessageSeverity?

    let onCancel: () -> Void
    let onApplyTemplate: () -> Void
    let onSaveAsTemplate: () -> Void
    let onCreate: () -> Void
    let onCreateAutoAssign: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.string("Create Task"))
                .font(.title3.weight(.semibold))

            if let boardMessage, !boardMessage.isEmpty {
                BoardMessageBanner(message: boardMessage, severity: boardMessageSeverity)
            }

            Picker(L10n.string("Task Template"), selection: $selectedTemplateID) {
                Text(L10n.string("No Template")).tag(UUID?.none)
                ForEach(templates) { template in
                    Text(template.name).tag(Optional(template.id))
                }
            }
            .pickerStyle(.menu)
            .onChange(of: selectedTemplateID) { _, _ in
                onApplyTemplate()
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
                Button(L10n.string("Save as Template"), action: onSaveAsTemplate)
                Button(L10n.string("Create + Auto Assign"), action: onCreateAutoAssign)
            }
        }
        .padding(18)
        .frame(width: 460)
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
        if scheme == .dark {
            switch resolvedSeverity {
            case .info:
                return BoardMessageColorToken(red: 0.42, green: 0.87, blue: 0.96, opacity: 1.0)
            case .warning:
                return BoardMessageColorToken(red: 0.94, green: 0.67, blue: 0.22, opacity: 1.0)
            case .error:
                return BoardMessageColorToken(red: 1.0, green: 0.64, blue: 0.59, opacity: 1.0)
            }
        } else {
            switch resolvedSeverity {
            case .info:
                return BoardMessageColorToken(red: 0.00, green: 0.42, blue: 0.56, opacity: 1.0)
            case .warning:
                return BoardMessageColorToken(red: 0.69, green: 0.35, blue: 0.00, opacity: 1.0)
            case .error:
                return BoardMessageColorToken(red: 0.74, green: 0.08, blue: 0.08, opacity: 1.0)
            }
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
        scheme == .dark
            ? [darkBoardBackgroundStart, darkBoardBackgroundEnd]
            : [lightBoardBackgroundStart, lightBoardBackgroundEnd]
    }

    static func columnToken(for status: KanbanStatus, scheme: ColorScheme) -> BoardMessageColorToken {
        if scheme == .dark {
            switch status {
            case .todo:
                return BoardMessageColorToken(red: 0.18, green: 0.27, blue: 0.36, opacity: 1.0)
            case .inProgress:
                return BoardMessageColorToken(red: 0.15, green: 0.31, blue: 0.24, opacity: 1.0)
            case .review:
                return BoardMessageColorToken(red: 0.34, green: 0.27, blue: 0.17, opacity: 1.0)
            case .done:
                return BoardMessageColorToken(red: 0.24, green: 0.25, blue: 0.31, opacity: 1.0)
            }
        } else {
            switch status {
            case .todo:
                return BoardMessageColorToken(red: 0.82, green: 0.9, blue: 0.98, opacity: 1.0)
            case .inProgress:
                return BoardMessageColorToken(red: 0.81, green: 0.94, blue: 0.87, opacity: 1.0)
            case .review:
                return BoardMessageColorToken(red: 0.99, green: 0.92, blue: 0.77, opacity: 1.0)
            case .done:
                return BoardMessageColorToken(red: 0.89, green: 0.89, blue: 0.92, opacity: 1.0)
            }
        }
    }

    static func taskCardToken(for scheme: ColorScheme) -> BoardMessageColorToken {
        scheme == .dark
            ? BoardMessageColorToken(red: 0.11, green: 0.14, blue: 0.19, opacity: 1.0)
            : BoardMessageColorToken(red: 1.0, green: 1.0, blue: 1.0, opacity: 1.0)
    }

    static func supplementaryCardToken(for scheme: ColorScheme) -> BoardMessageColorToken {
        scheme == .dark
            ? BoardMessageColorToken(red: 0.17, green: 0.20, blue: 0.27, opacity: 1.0)
            : BoardMessageColorToken(red: 1.0, green: 1.0, blue: 1.0, opacity: 0.92)
    }

    static func emptyStateToken(for scheme: ColorScheme) -> BoardMessageColorToken {
        scheme == .dark
            ? BoardMessageColorToken(red: 0.19, green: 0.23, blue: 0.30, opacity: 1.0)
            : BoardMessageColorToken(red: 1.0, green: 1.0, blue: 1.0, opacity: 0.68)
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
        scheme == .dark
            ? BoardMessageColorToken(red: 0.24, green: 0.29, blue: 0.37, opacity: 1.0)
            : BoardMessageColorToken(red: 0.96, green: 0.97, blue: 0.99, opacity: 1.0)
    }

    static func storyPointToken(for scheme: ColorScheme) -> BoardMessageColorToken {
        scheme == .dark
            ? BoardMessageColorToken(red: 0.20, green: 0.24, blue: 0.31, opacity: 1.0)
            : BoardMessageColorToken(red: 0.90, green: 0.92, blue: 0.95, opacity: 1.0)
    }

    static func columnBorderToken(for scheme: ColorScheme) -> BoardMessageColorToken {
        scheme == .dark
            ? BoardMessageColorToken(red: 0.31, green: 0.36, blue: 0.46, opacity: 1.0)
            : BoardMessageColorToken(red: 0.72, green: 0.77, blue: 0.84, opacity: 1.0)
    }

    static func taskCardBorderToken(for scheme: ColorScheme) -> BoardMessageColorToken {
        scheme == .dark
            ? BoardMessageColorToken(red: 0.30, green: 0.35, blue: 0.44, opacity: 1.0)
            : BoardMessageColorToken(red: 0.72, green: 0.77, blue: 0.84, opacity: 1.0)
    }

    static func supplementaryCardBorderToken(for scheme: ColorScheme) -> BoardMessageColorToken {
        scheme == .dark
            ? BoardMessageColorToken(red: 0.30, green: 0.35, blue: 0.45, opacity: 1.0)
            : BoardMessageColorToken(red: 0.71, green: 0.76, blue: 0.83, opacity: 1.0)
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
        if scheme == .dark {
            switch accent {
            case .blue:
                return BoardMessageColorToken(red: 0.19, green: 0.31, blue: 0.47, opacity: 1.0)
            case .indigo:
                return BoardMessageColorToken(red: 0.24, green: 0.26, blue: 0.48, opacity: 1.0)
            case .amber:
                return BoardMessageColorToken(red: 0.43, green: 0.30, blue: 0.12, opacity: 1.0)
            case .red:
                return BoardMessageColorToken(red: 0.48, green: 0.20, blue: 0.20, opacity: 1.0)
            case .green:
                return BoardMessageColorToken(red: 0.20, green: 0.39, blue: 0.28, opacity: 1.0)
            case .teal:
                return BoardMessageColorToken(red: 0.16, green: 0.36, blue: 0.36, opacity: 1.0)
            case .mint:
                return BoardMessageColorToken(red: 0.15, green: 0.34, blue: 0.29, opacity: 1.0)
            }
        } else {
            switch accent {
            case .blue:
                return BoardMessageColorToken(red: 0.84, green: 0.92, blue: 0.99, opacity: 1.0)
            case .indigo:
                return BoardMessageColorToken(red: 0.87, green: 0.89, blue: 0.98, opacity: 1.0)
            case .amber:
                return BoardMessageColorToken(red: 0.99, green: 0.92, blue: 0.80, opacity: 1.0)
            case .red:
                return BoardMessageColorToken(red: 0.98, green: 0.86, blue: 0.86, opacity: 1.0)
            case .green:
                return BoardMessageColorToken(red: 0.86, green: 0.95, blue: 0.89, opacity: 1.0)
            case .teal:
                return BoardMessageColorToken(red: 0.84, green: 0.95, blue: 0.95, opacity: 1.0)
            case .mint:
                return BoardMessageColorToken(red: 0.86, green: 0.96, blue: 0.92, opacity: 1.0)
            }
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
        if scheme == .dark {
            switch role {
            case .success:
                return BoardMessageColorToken(red: 0.45, green: 0.92, blue: 0.59, opacity: 1.0)
            case .warning:
                return BoardMessageColorToken(red: 0.94, green: 0.67, blue: 0.22, opacity: 1.0)
            case .error:
                return BoardMessageColorToken(red: 1.0, green: 0.64, blue: 0.59, opacity: 1.0)
            }
        } else {
            switch role {
            case .success:
                return BoardMessageColorToken(red: 0.06, green: 0.45, blue: 0.18, opacity: 1.0)
            case .warning:
                return BoardMessageColorToken(red: 0.69, green: 0.35, blue: 0.00, opacity: 1.0)
            case .error:
                return BoardMessageColorToken(red: 0.74, green: 0.08, blue: 0.08, opacity: 1.0)
            }
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
        if scheme == .dark, role == .secondary {
            return BoardMessageColorToken(red: 0.82, green: 0.86, blue: 0.92, opacity: 1.0)
        }
        return BoardMessageColorToken(red: 0.28, green: 0.33, blue: 0.42, opacity: 1.0)
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

#if DEBUG
private extension ExecutionDetailsSheet {
    var testStatusLabel: String { statusLabel }
}

private extension AgentLiveConsoleView {
    func testStatusLabel(for event: AgentExecutionEvent) -> String {
        statusLabel(for: event)
    }

    var testAllEventsText: String { allEventsText }
}

private extension AgentExecutionEventRow {
    var testStatusLabel: String { statusLabel }
    var testStatusColor: Color { statusColor }
    var testCopyText: String { copyText }
}

private extension TaskCardView {
    func testExecutionStatusLabel(for status: TaskExecutionStatus) -> String {
        executionStatusLabel(for: status)
    }

    func testExecutionStatusColor(for status: TaskExecutionStatus) -> Color {
        executionStatusColor(for: status)
    }
}

private extension BoardHealthSummaryView {
    var testHealthScoreAccent: SummaryBadgeAccent { healthScoreAccent }
}

private extension BoardHealthRecommendationsView {
    var testAutoFixRecommendationCount: Int { autoFixRecommendationCount }
    var testRecommendationCardBackground: Color { recommendationCardBackground }
    var testRecommendationCardBorder: Color { recommendationCardBorder }
}

private extension ManualTriageSheet {
    func testSelectionBinding(for taskID: UUID, fallback: UUID) -> Binding<UUID> {
        selectionBinding(for: taskID, fallback: fallback)
    }

    var testTriageCardBackground: Color { triageCardBackground }
}

private extension ContentView {
    func testRuntimeSummary(for agent: AgentProfile) -> String {
        runtimeSummary(for: agent)
    }

    func testBuildRuntimeProfile(
        isEnabled: Bool,
        provider: AgentRuntimeProvider,
        model: String,
        endpoint: String,
        toolsText: String,
        openAIAuthMode: OpenAICompatibleAuthMode,
        codexProfile: String
    ) -> AgentRuntimeProfile? {
        buildRuntimeProfile(
            isEnabled: isEnabled,
            provider: provider,
            model: model,
            endpoint: endpoint,
            toolsText: toolsText,
            openAIAuthMode: openAIAuthMode,
            codexProfile: codexProfile
        )
    }

    private static func openFirstGlobalSearchResultIfAny(
        _ view: ContentView,
        results: [GlobalTaskSearchResult]? = nil
    ) {
        let resolvedResults = results ?? view.globalTaskSearchResults
        if let result = resolvedResults.first {
            view.openGlobalTaskSearchResult(result)
        }
    }

    private static func assignFirstManualCandidateIfAny(view: ContentView, viewModel: KanbanBoardViewModel) {
        let candidates = viewModel.triageCandidates()
        if let candidate = candidates.first,
           let targetAgent = viewModel.assignableAgents(for: candidate.id).first {
            view.triageSelectionByTaskID[candidate.id] = targetAgent.id
            view.assignManually(taskID: candidate.id)
        }
    }

    @MainActor
    static func testExerciseActionHandlersForCoverage() -> Int {
        let now = Date(timeIntervalSince1970: 1_735_000_000)
        let successRecord = TaskExecutionRecord(
            status: .succeeded,
            runCount: 1,
            lastStartedAt: now,
            lastFinishedAt: now.addingTimeInterval(10),
            lastOutputSummary: "Summary: done"
        )
        let failedRecord = TaskExecutionRecord(
            status: .failed,
            runCount: 1,
            lastStartedAt: now,
            lastFinishedAt: now.addingTimeInterval(10),
            lastError: "failed"
        )

        let agentA = AgentProfile(name: "Coverage A", skills: ["swiftui"], maxConcurrentTasks: 3)
        let agentB = AgentProfile(name: "Coverage B", skills: ["swiftui"], maxConcurrentTasks: 3)
        let todoAssigned = WorkTask(
            title: "Assigned Task",
            details: "Implement feature",
            requiredSkills: ["swiftui"],
            storyPoints: 2,
            status: .todo,
            assignedAgentID: agentA.id,
            executionRecord: successRecord
        )
        let todoUnassigned = WorkTask(
            title: "Unassigned Task",
            details: "Needs triage",
            requiredSkills: [],
            storyPoints: 1,
            status: .todo,
            assignedAgentID: nil
        )
        let doneTask = WorkTask(
            title: "Done Task",
            details: "Finished",
            requiredSkills: [],
            storyPoints: 1,
            status: .done,
            assignedAgentID: agentA.id,
            executionRecord: failedRecord
        )
        let failedInProgressTask = WorkTask(
            title: "Retry Task",
            details: "Can retry",
            requiredSkills: [],
            storyPoints: 1,
            status: .inProgress,
            assignedAgentID: agentA.id,
            executionRecord: failedRecord
        )

        let viewModel = KanbanBoardViewModel(
            tasks: [todoAssigned, todoUnassigned, doneTask, failedInProgressTask],
            agents: [agentA, agentB],
            runOnBackground: { work in work() },
            runOnMain: { work in work() }
        )
        let initialBoardID = viewModel.selectedBoardID
        _ = viewModel.createBoard(name: "Coverage Secondary")
        let secondaryBoardID = viewModel.selectedBoardID
        _ = viewModel.switchBoard(to: initialBoardID)

        let view = ContentView(viewModel: viewModel)
        let fallbackWIPView = ContentView(
            viewModel: KanbanBoardViewModel(tasks: [], agents: [], wipLimits: [:])
        )
        let fileManager = FileManager.default
        let workspaceImportURL = fileManager.temporaryDirectory.appendingPathComponent(
            "openmac-coverage-import-\(UUID().uuidString).json"
        )
        let workspaceExportURL = fileManager.temporaryDirectory.appendingPathComponent(
            "openmac-coverage-export-\(UUID().uuidString).json"
        )
        let projectsDirectoryURL = fileManager.temporaryDirectory.appendingPathComponent(
            "openmac-coverage-projects-\(UUID().uuidString)",
            isDirectory: true
        )
        _ = viewModel.exportWorkspace(to: workspaceImportURL)
        try? fileManager.createDirectory(at: projectsDirectoryURL, withIntermediateDirectories: true)

        let savedSavePanelResultProvider = Self.savePanelResultProvider
        let savedOpenPanelResultProvider = Self.openPanelResultProvider
        let savedAlertRunner = Self.alertRunner
        let savedWorkspaceActivator = Self.workspaceActivator
        let savedCodexDirectoryEnsurer = Self.codexDirectoryEnsurer
        var shouldFailCodexDirectoryEnsurer = false
        Self.savePanelResultProvider = { _ in
            (.OK, workspaceExportURL)
        }
        Self.openPanelResultProvider = { panel in
            if panel.canChooseDirectories {
                return (.OK, projectsDirectoryURL)
            }
            return (.OK, workspaceImportURL)
        }
        Self.alertRunner = { _ in
            .alertFirstButtonReturn
        }
        Self.workspaceActivator = { _ in }
        Self.codexDirectoryEnsurer = { path in
            if shouldFailCodexDirectoryEnsurer {
                throw NSError(
                    domain: "Coverage",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "coverage failure"]
                )
            }
            let url = URL(fileURLWithPath: path, isDirectory: true)
            try? fileManager.createDirectory(at: url, withIntermediateDirectories: true)
            return url
        }
        defer {
            Self.savePanelResultProvider = savedSavePanelResultProvider
            Self.openPanelResultProvider = savedOpenPanelResultProvider
            Self.alertRunner = savedAlertRunner
            Self.workspaceActivator = savedWorkspaceActivator
            Self.codexDirectoryEnsurer = savedCodexDirectoryEnsurer

            try? fileManager.removeItem(at: workspaceImportURL)
            try? fileManager.removeItem(at: workspaceExportURL)
            try? fileManager.removeItem(at: projectsDirectoryURL)
        }

        var exercised = 0

        func hit(_ action: () -> Void) {
            action()
            exercised += 1
        }

        hit { view.cycleAppearanceMode() }
        hit { view.resetDraftAndClose() }
        hit { view.copyToPasteboard("coverage") }
        hit { view.openExecutionDetails(todoAssigned) }
        hit { view.applyTaskEdits() }
        hit {
            view.openEditTask(todoAssigned)
            view.editingTaskID = todoAssigned.id
        }
        hit {
            view.editTaskTitle = " "
            view.applyTaskEdits()
        }
        hit {
            view.editTaskTitle = "Assigned Task Updated"
            view.editTaskDetails = "Updated details"
            view.editTaskSkills = "swiftui"
            view.editTaskPoints = 3
            view.applyTaskEdits()
        }
        hit { view.closeEditTaskSheet() }
        hit { view.resetAgentDraftAndClose() }

        hit { view.openNewBoardSheet() }
        hit { view.closeNewBoardSheet() }
        hit {
            view.newBoardName = "Coverage Board"
            view.createBoardFromSheet()
        }
        hit {
            view.newBoardName = "Coverage Board"
            view.createBoardFromSheet()
        }
        hit { view.openRenameBoardSheet() }
        hit { view.closeRenameBoardSheet() }
        hit { view.createBoardFromSheet() }
        hit { view.closeNewBoardSheetAndHandleContext() }
        hit {
            view.renameBoardName = "Coverage Board Renamed"
            view.renameBoardFromSheet()
        }
        hit {
            view.renameBoardName = viewModel.selectedBoardName
            view.renameBoardFromSheet()
        }
        hit { view.renameBoardFromSheet() }
        hit { view.duplicateSelectedBoard() }
        hit { view.removeSelectedBoard() }

        hit { view.openGlobalTaskFinder() }
        hit {
            let validResult = GlobalTaskSearchResult(
                taskID: todoAssigned.id,
                taskTitle: todoAssigned.title,
                taskDetails: todoAssigned.details,
                status: todoAssigned.status,
                boardID: initialBoardID,
                boardName: "Board 1",
                assigneeName: "Coverage A"
            )
            view.openGlobalTaskSearchResult(validResult)
        }
        hit {
            let invalidResult = GlobalTaskSearchResult(
                taskID: UUID(),
                taskTitle: "Missing",
                taskDetails: "",
                status: .todo,
                boardID: initialBoardID,
                boardName: "Board 1",
                assigneeName: "Unassigned"
            )
            view.openGlobalTaskSearchResult(invalidResult)
        }
        hit {
            view.globalTaskSearchQuery = "Assigned"
            Self.openFirstGlobalSearchResultIfAny(view)
        }
        hit {
            view.globalTaskSearchQuery = "NoMatchCoverageQuery"
            Self.openFirstGlobalSearchResultIfAny(view)
        }
        hit { view.closeGlobalTaskFinder() }

        hit {
            view.switchBoard(viewModel.boards[0].id)
        }
        hit { view.handleBoardContextChanged() }
        hit {
            if let firstAgent = viewModel.agents.first {
                view.selectedAgentConsoleAgentID = firstAgent.id
                view.syncSelectedAgentConsoleSelection()
            }
        }
        hit {
            if let firstAgent = viewModel.agents.first {
                view.selectedAssigneeFilterKey = firstAgent.id.uuidString
                view.normalizeAssigneeFilterSelection()
            }
        }
        hit {
            view.selectedAgentConsoleAgentID = UUID()
            _ = view.selectedAgentForConsole
        }
        hit { view.openWIPSettings() }
        hit { fallbackWIPView.openWIPSettings() }
        hit { view.applyWIPSettings() }
        hit { _ = view.pmTemplateOptions.count }
        hit {
            view.developerModeEnabled = false
            _ = view.boardMessageSection("Coverage board message")
        }
        hit {
            view.developerModeEnabled = true
            _ = view.boardMessageSection("Coverage board message")
        }

        hit { view.openPMPlannerSheet() }
        hit {
            view.pmProjectName = "Coverage PM Project"
            view.pmProjectBrief = "Create an execution-ready PM plan for coverage validation."
            view.generatePMPlanFromSheet()
        }
        hit {
            view.pmPlannedTickets = [
                PMPlannedTicket(
                    title: "Coverage Acceptance Ticket",
                    details: "Acceptance:\n- keep coverage green",
                    requiredSkills: ["swiftui"],
                    storyPoints: 1,
                    epic: "Coverage",
                    milestone: "M1"
                )
            ]
            view.applyPMAutoAcceptanceCriteriaForAllTickets()
        }
        hit { view.generatePMTestPlanFromSheet() }
        hit { view.applyPMAutoAcceptanceCriteriaForTicket(0) }
        hit { view.applyPMAutoAcceptanceCriteriaForTicket(999) }
        hit { view.applyPMDependencyChainFromSheet() }
        hit { view.copyPMPlanFromSheet() }
        hit { view.copyPMTestPlanFromSheet() }
        hit { view.createMissingAgentsFromPMPlanFromSheet() }
        hit {
            view.pmCreateNewBoardForPlan = false
            view.pmAutoAssignAfterCreate = false
            view.createPMTicketsFromSheet()
        }
        hit { view.openPMPlannerSheet() }
        hit {
            view.pmSelectedTemplateID = view.pmTemplateOptions.first(where: { $0.id != Self.pmCustomTemplateID })?.id
                ?? Self.pmCustomTemplateID
            view.applyPMTemplateFromSheet()
        }
        hit { view.applyAndGeneratePMTemplateFromSheet() }
        hit { view.applyPMBlueprintFromSheet() }
        hit {
            view.pmBlueprintVision = "Ship a reliable kanban automation workspace."
            view.pmBlueprintTargetUsers = "macOS solo builders"
            view.pmBlueprintCoreFeatures = "Planner, execution logs, automation"
            view.pmBlueprintTechScope = "SwiftUI + tests"
            view.pmBlueprintConstraints = "No regressions"
            view.pmBlueprintQualityBar = "Strong unit coverage"
            view.applyAndGeneratePMBlueprintFromSheet()
        }
        hit {
            view.pmCreateNewBoardForPlan = false
            view.createAndRunPMTicketsFromSheet()
        }
        hit { view.closePMPlannerSheet() }
        hit {
            view.openPMPlannerSheet()
            view.isBatchRunning = false
            view.isAutoCycleRunning = false
            view.pmProjectName = "Coverage PM Autopilot"
            view.pmProjectBrief = "Plan and execute a compact PM flow."
            view.pmCreateNewBoardForPlan = false
            view.pmPlannedTickets = [
                PMPlannedTicket(
                    title: "Coverage PM Autopilot Ticket",
                    details: "Execute an autopilot-compatible coverage task.",
                    requiredSkills: ["swiftui"],
                    storyPoints: 1,
                    epic: "Coverage",
                    milestone: "M1"
                )
            ]
            view.pmTestPlanText = ""
            view.runPMAutopilotFromSheet()
        }
        hit {
            view.isAutoCycleRunning = true
            view.runPMAutopilotFromSheet()
            view.isAutoCycleRunning = false
        }
        hit {
            view.isBatchRunning = true
            view.runPMAutopilotFromSheet()
            view.isBatchRunning = false
        }

        hit {
            view.newTaskTitle = "Created by coverage hook"
            view.newTaskDetails = "details"
            view.newTaskSkills = ""
            view.newTaskPoints = 1
            view.createTaskFromSheet(autoAssign: false)
        }
        hit {
            view.newTaskTitle = " "
            view.createTaskFromSheet(autoAssign: false)
        }
        hit { view.archiveDoneTasks() }
        hit { view.rebalanceTodoAssignments() }
        hit { view.runAutoAssignFromToolbar() }
        hit { view.runAssignedExecutionsFromToolbar() }
        hit { view.cancelAssignedExecutionsFromToolbar() }
        hit {
            view.isBatchRunning = true
            view.cancelAssignedExecutionsFromToolbar()
            view.isBatchRunning = false
        }
        hit { view.runAutoCycleFromToolbar() }
        hit {
            view.isAutoCycleRunning = true
            view.cancelAutoCycleFromToolbar()
            view.isAutoCycleRunning = false
        }
        hit {
            view.isBatchRunning = true
            view.runAutoCycleFromToolbar()
            view.isBatchRunning = false
        }
        hit {
            view.autoRetryEnabled = true
            view.autoRetryMaxRetries = 3
            view.autoRetryBackoffSeconds = 2.0
            view.autoRetryRetryNetwork = true
            view.autoRetryRetryRateLimit = false
            view.autoRetryRetryServer = true
            view.applyAutoRetrySettings()
        }
        hit { view.applyHealthRecommendation(.openManualTriage) }
        hit { view.applyHealthRecommendation(.autoAssignUnassignedTodo) }
        hit { view.applyHealthRecommendation(.createMissingDependencyTasks) }
        hit { view.applyHealthRecommendation(.rebalanceTodoLoad) }
        hit { view.applyHealthRecommendation(.archiveDone) }
        hit { view.applyHealthRecommendation(.openNewAgent) }
        hit { view.applyHealthRecommendation(.increaseWIPLimit(.review)) }
        hit { view.applyAllHealthRecommendations() }
        hit { view.openNewAgentSheet() }
        hit { view.exportWorkspaceFromToolbar() }
        hit { view.exportSelectedBoardFromToolbar() }
        hit { view.exportExecutionReportJSONFromToolbar() }
        hit { view.exportExecutionReportMarkdownFromToolbar() }
        hit { view.importWorkspaceFromToolbar() }
        hit { view.chooseCodexProjectsDirectory() }
        hit { view.openCodexProjectsDirectoryInFinder() }
        hit { view.chooseGitHubRepositoryDirectory() }
        hit { view.openGitHubRepositoryInFinder() }
        hit { view.runGitHubPRFlowFromToolbar() }
        hit { view.clearExecutionCheckpointFromToolbar() }
        hit { view.resumeInterruptedExecutionFromToolbar() }
        hit {
            shouldFailCodexDirectoryEnsurer = true
            view.openCodexProjectsDirectoryInFinder()
            shouldFailCodexDirectoryEnsurer = false
        }
        hit { view.openManualTriage() }
        hit { _ = view.hasManualTriageCandidates() }
        hit { view.closeManualTriageSheet() }
        hit { view.assignManually(taskID: UUID()) }
        hit { Self.assignFirstManualCandidateIfAny(view: view, viewModel: viewModel) }
        hit {
            if let assignedTaskID = viewModel.tasks.first(where: { $0.assignedAgentID != nil })?.id {
                view.assignManually(taskID: assignedTaskID)
            }
        }
        hit { view.assignAllManually() }
        hit { Self.assignFirstManualCandidateIfAny(view: view, viewModel: viewModel) }
        hit { view.refreshTriageSelections() }

        hit {
            if viewModel.agents.count > 1 {
                view.deleteAgents(at: IndexSet(integer: 1))
            }
        }
        hit {
            if let firstAgent = viewModel.agents.first {
                view.unassignTodoTasks(for: firstAgent.id)
            }
        }
        hit {
            if let firstAgent = viewModel.agents.first {
                view.unassignTodoTasks(for: firstAgent.id)
            }
        }

        hit {
            if let task = viewModel.tasks.first {
                view.duplicateTask(task.id)
                view.autoAssignTask(task.id)
                view.unassignTask(task.id)
                view.autoAssignTask(task.id)
                view.autoAssignTask(task.id)
            }
        }
        hit {
            if let task = viewModel.tasks.first,
               secondaryBoardID != viewModel.selectedBoardID {
                view.copyTaskToBoard(task.id, secondaryBoardID)
                view.moveTaskToBoard(task.id, secondaryBoardID)
            }
        }
        hit {
            if let movedTask = viewModel.tasks.first {
                _ = viewModel.switchBoard(to: initialBoardID)
                view.moveTaskToBoard(movedTask.id, secondaryBoardID)
            }
        }
        hit {
            if let task = viewModel.tasks.first,
               let firstAgent = viewModel.agents.first {
                _ = viewModel.addAgent(
                    name: "Coverage Reassign",
                    skillsText: "swiftui",
                    maxConcurrentTasks: 3,
                    runtimeProfile: nil
                )
                view.assignTaskToAgent(task.id, firstAgent.id)
                view.reassignTaskToAgent(task.id, firstAgent.id)
                if let otherAgent = viewModel.agents.first(where: { $0.id != firstAgent.id }) {
                    view.reassignTaskToAgent(task.id, otherAgent.id)
                }
                view.assignTaskToAgent(UUID(), firstAgent.id)
                view.reassignTaskToAgent(UUID(), firstAgent.id)
                view.runTaskExecution(task.id)
                view.retryTaskExecution(task.id)
                view.removeTask(task.id)
            }
        }
        hit { view.retryTaskExecution(failedInProgressTask.id) }
        hit { view.applyAgentEdits() }
        hit {
            if let firstAgent = viewModel.agents.first {
                view.openEditAgent(firstAgent)
                view.editingAgentID = firstAgent.id
                view.editAgentName = " "
                view.applyAgentEdits()
                view.editAgentName = "\(firstAgent.name) Updated"
                view.editAgentSkills = "swiftui"
                view.editAgentCapacity = firstAgent.maxConcurrentTasks
                view.applyAgentEdits()
                view.closeEditAgentSheet()
                view.removeAgent(firstAgent.id)
            }
        }

        hit { _ = view.selectedBoardExportFileName() }
        hit { view.refreshAndCloseEditTaskSheet() }
        hit { view.refreshAndResetTaskDraft() }
        hit { view.refreshAndCloseEditAgentSheet() }
        hit { view.resetTaskFilters() }
        hit { view.useDefaultCodexProjectsDirectory() }
        hit { view.ensureCodexProjectsDirectoryExists() }
        hit {
            shouldFailCodexDirectoryEnsurer = true
            view.ensureCodexProjectsDirectoryExists()
            shouldFailCodexDirectoryEnsurer = false
        }
        hit { view.syncSelectedAgentConsoleSelection() }
        hit { view.normalizeAssigneeFilterSelection() }
        hit {
            view.selectedAgentConsoleAgentID = UUID()
            view.syncSelectedAgentConsoleSelection()
        }
        hit {
            view.selectedAssigneeFilterKey = "invalid"
            view.normalizeAssigneeFilterSelection()
        }
        hit {
            view.appLanguageOverrideRawValue = AppLanguageSettings.systemValue
            _ = view.selectedLanguageLabel
            _ = view.isSelectedLanguage(nil)
        }
        hit {
            view.appLanguageOverrideRawValue = AppLanguage.japanese.rawValue
            _ = view.selectedLanguageLabel
            _ = view.isSelectedLanguage(.japanese)
        }
        hit { _ = view.hasAssignedTodoTasks(for: agentA.id) }
        hit { _ = view.hasAssignedTodoTasks(for: UUID()) }
        hit { _ = view.selectedAgentForConsole }

        return exercised
    }

    @MainActor
    static func testExerciseTargetedHelperBranchesForCoverage() -> Int {
        var exercised = 0

        func hit(_ action: () -> Void) {
            action()
            exercised += 1
        }

        let searchAgent = AgentProfile(name: "Search Agent", skills: ["swiftui"], maxConcurrentTasks: 2)
        let searchTask = WorkTask(
            title: "Searchable Coverage Task",
            details: "Search details",
            requiredSkills: [],
            storyPoints: 1,
            status: .todo,
            assignedAgentID: nil
        )
        let searchViewModel = KanbanBoardViewModel(tasks: [searchTask], agents: [searchAgent])
        let searchView = ContentView(viewModel: searchViewModel)
        let injectedSearchResult = GlobalTaskSearchResult(
            taskID: searchTask.id,
            taskTitle: searchTask.title,
            taskDetails: searchTask.details,
            status: searchTask.status,
            boardID: searchViewModel.selectedBoardID,
            boardName: searchViewModel.selectedBoardName,
            assigneeName: L10n.string("Unassigned")
        )
        hit {
            Self.openFirstGlobalSearchResultIfAny(searchView, results: [injectedSearchResult])
        }
        hit {
            Self.openFirstGlobalSearchResultIfAny(searchView, results: [])
        }

        let assignableAgent = AgentProfile(name: "Assignable Agent", skills: ["swiftui"], maxConcurrentTasks: 2)
        let assignableTask = WorkTask(
            title: "Assignable Coverage Task",
            details: "Assignable details",
            requiredSkills: ["swiftui"],
            storyPoints: 1,
            status: .todo,
            assignedAgentID: nil
        )
        let assignableViewModel = KanbanBoardViewModel(tasks: [assignableTask], agents: [assignableAgent])
        let assignableView = ContentView(viewModel: assignableViewModel)
        hit {
            Self.assignFirstManualCandidateIfAny(view: assignableView, viewModel: assignableViewModel)
        }
        hit {
            Self.assignFirstManualCandidateIfAny(view: assignableView, viewModel: assignableViewModel)
        }

        let mismatchAgent = AgentProfile(name: "Mismatch Agent", skills: ["ios"], maxConcurrentTasks: 1)
        let mismatchTask = WorkTask(
            title: "Mismatch Coverage Task",
            details: "Mismatch details",
            requiredSkills: ["qa"],
            storyPoints: 1,
            status: .todo,
            assignedAgentID: nil
        )
        let mismatchViewModel = KanbanBoardViewModel(tasks: [mismatchTask], agents: [mismatchAgent])
        let mismatchView = ContentView(viewModel: mismatchViewModel)
        hit {
            Self.assignFirstManualCandidateIfAny(view: mismatchView, viewModel: mismatchViewModel)
        }

        return exercised
    }

    @MainActor
    static func testExerciseRecommendationAndTriageHelpersForCoverage() -> Int {
        var exercised = 0

        func hit(_ action: () -> Void) {
            action()
            exercised += 1
        }

        let recommendationView = BoardHealthRecommendationsView(
            recommendations: [
                BoardHealthRecommendation(
                    action: .openManualTriage,
                    title: "Manual triage",
                    detail: "Review queued tasks"
                )
            ],
            onAction: { _ in },
            onApplyAll: {}
        )
        hit { _ = recommendationView.testRecommendationCardBackground }
        hit { _ = recommendationView.testRecommendationCardBorder }

        let taskID = UUID()
        let fallbackAgentID = UUID()
        let selectedAgentID = UUID()
        var selectedByTask: [UUID: UUID] = [:]
        let manualTriageSheet = ManualTriageSheet(
            tasks: [
                WorkTask(
                    id: taskID,
                    title: "Triage task",
                    details: "Needs assignment",
                    requiredSkills: [],
                    storyPoints: 1,
                    status: .todo,
                    assignedAgentID: nil
                )
            ],
            boardMessage: nil,
            boardMessageSeverity: nil,
            selectedAgentByTaskID: Binding(get: { selectedByTask }, set: { selectedByTask = $0 }),
            assignAllEligibleCount: 0,
            unassignableTaskCount: 0,
            assignableAgents: { _ in [] },
            loadText: { _ in "0/1" },
            onAssign: { _ in },
            onAssignAll: {},
            onClose: {}
        )
        hit { _ = manualTriageSheet.testTriageCardBackground }

        let selection = manualTriageSheet.testSelectionBinding(for: taskID, fallback: fallbackAgentID)
        hit { _ = selection.wrappedValue }
        hit { selection.wrappedValue = selectedAgentID }
        if selectedByTask[taskID] == selectedAgentID {
            exercised += 1
        }

        return exercised
    }

    static func testResolveSelectedAssigneeFilter(
        selectedKey: String,
        agents: [AgentProfile]
    ) -> TaskAssigneeFilter {
        resolveSelectedAssigneeFilter(selectedKey: selectedKey, agents: agents)
    }

    static func testCanAutoAssignFromToolbar(tasks: [WorkTask], agents: [AgentProfile]) -> Bool {
        let unassignedTodoTaskCount = tasks.filter { $0.status == .todo && $0.assignedAgentID == nil }.count
        return canAutoAssignFromToolbar(
            unassignedTodoTaskCount: unassignedTodoTaskCount,
            hasAgents: !agents.isEmpty
        )
    }

    static func testCanBatchRunAssignedTasks(
        tasks: [WorkTask],
        isBatchRunning: Bool,
        isAutoCycleRunning: Bool
    ) -> Bool {
        canBatchRunAssignedTasks(
            tasks: tasks,
            isBatchRunning: isBatchRunning,
            isAutoCycleRunning: isAutoCycleRunning
        )
    }

    static func testCanRunAutoCycle(
        tasks: [WorkTask],
        isBatchRunning: Bool,
        isAutoCycleRunning: Bool
    ) -> Bool {
        canRunAutoCycle(
            tasks: tasks,
            isBatchRunning: isBatchRunning,
            isAutoCycleRunning: isAutoCycleRunning
        )
    }
}

enum ContentViewTestHooks {
    static func normalizedExecutionSummary(_ summary: String) -> String {
        normalizedExecutionSummaryForDisplay(summary)
    }

    static func executionDetailsStatusLabel(for status: TaskExecutionStatus) -> String {
        let details = ExecutionDetailsPresentation(
            taskTitle: "Task",
            assigneeName: "Agent",
            executionRecord: TaskExecutionRecord(status: status),
            timelineText: nil
        )
        let sheet = ExecutionDetailsSheet(details: details, onCopy: { _ in }, onClose: {})
        return sheet.testStatusLabel
    }

    static func agentLiveConsoleStatusLabel(for status: TaskExecutionStatus) -> String {
        let event = AgentExecutionEvent(
            agentID: UUID(),
            taskID: UUID(),
            taskTitle: "Task",
            status: status,
            message: "Message"
        )
        let view = AgentLiveConsoleView(
            agentName: "Agent",
            isRunning: false,
            events: [event],
            onCopy: { _ in },
            onClear: {}
        )
        return view.testStatusLabel(for: event)
    }

    static func agentLiveConsoleAllEventsText(_ events: [AgentExecutionEvent]) -> String {
        let view = AgentLiveConsoleView(
            agentName: "Agent",
            isRunning: false,
            events: events,
            onCopy: { _ in },
            onClear: {}
        )
        return view.testAllEventsText
    }

    static func agentExecutionEventRowStatusLabel(for status: TaskExecutionStatus) -> String {
        let event = AgentExecutionEvent(
            agentID: UUID(),
            taskID: UUID(),
            taskTitle: "Task",
            status: status,
            message: "Message"
        )
        let row = AgentExecutionEventRow(event: event, onCopy: { _ in })
        return row.testStatusLabel
    }

    static func agentExecutionEventRowCopyText(
        status: TaskExecutionStatus,
        message: String,
        details: String?
    ) -> String {
        let event = AgentExecutionEvent(
            agentID: UUID(),
            taskID: UUID(),
            taskTitle: "Task",
            status: status,
            message: message,
            details: details
        )
        let row = AgentExecutionEventRow(event: event, onCopy: { _ in })
        return row.testCopyText
    }

    static func taskCardExecutionStatusLabel(for status: TaskExecutionStatus) -> String {
        let task = WorkTask(
            title: "Task",
            details: "Details",
            requiredSkills: [],
            storyPoints: 1,
            status: .todo,
            assignedAgentID: nil
        )
        let card = TaskCardView(
            task: task,
            assigneeName: "Agent",
            assignmentReason: nil,
            dependencyBlockedReason: nil,
            canMoveBackward: false,
            canMoveForward: true,
            canUnassign: false,
            canAutoAssign: true,
            canRunAgent: false,
            canRetryAgent: false,
            executionRecord: nil,
            manualAssignableAgents: [],
            reassignableAgents: [],
            moveToBoardTargets: [],
            onEdit: {},
            onAutoAssign: {},
            onRunAgent: {},
            onRetryAgent: {},
            onManualAssign: { _ in },
            onReassign: { _ in },
            onUnassign: {},
            onDuplicate: {},
            onDelete: {},
            onMoveToBoard: { _ in },
            onCopyToBoard: { _ in },
            onShowExecutionDetails: {},
            hasExecutionTimeline: false,
            onCopyExecutionTimeline: {},
            onMoveBackward: {},
            onMoveForward: {}
        )
        return card.testExecutionStatusLabel(for: status)
    }

    static func exerciseStatusColorCoverage() -> Int {
        let statuses: [TaskExecutionStatus] = [.running, .succeeded, .failed]
        var exercised = 0

        let task = WorkTask(
            title: "Task",
            details: "Details",
            requiredSkills: [],
            storyPoints: 1,
            status: .todo,
            assignedAgentID: nil
        )
        let card = TaskCardView(
            task: task,
            assigneeName: "Agent",
            assignmentReason: nil,
            dependencyBlockedReason: nil,
            canMoveBackward: false,
            canMoveForward: true,
            canUnassign: false,
            canAutoAssign: true,
            canRunAgent: false,
            canRetryAgent: false,
            executionRecord: nil,
            manualAssignableAgents: [],
            reassignableAgents: [],
            moveToBoardTargets: [],
            onEdit: {},
            onAutoAssign: {},
            onRunAgent: {},
            onRetryAgent: {},
            onManualAssign: { _ in },
            onReassign: { _ in },
            onUnassign: {},
            onDuplicate: {},
            onDelete: {},
            onMoveToBoard: { _ in },
            onCopyToBoard: { _ in },
            onShowExecutionDetails: {},
            hasExecutionTimeline: false,
            onCopyExecutionTimeline: {},
            onMoveBackward: {},
            onMoveForward: {}
        )

        for status in statuses {
            _ = card.testExecutionStatusColor(for: status)
            exercised += 1
        }

        for status in statuses {
            let event = AgentExecutionEvent(
                agentID: UUID(),
                taskID: UUID(),
                taskTitle: "Task",
                status: status,
                message: "Message"
            )
            let row = AgentExecutionEventRow(event: event, onCopy: { _ in })
            _ = row.testStatusColor
            exercised += 1
        }

        return exercised
    }

    static func exercisePaletteTokenCoverage() -> Int {
        let schemes: [ColorScheme] = [.light, .dark]
        let severities: [BoardMessageSeverity?] = [nil, .info, .warning, .error]
        let accents = SummaryBadgeAccent.allCases
        let semanticRoles: [BoardSemanticTextRole] = [.success, .warning, .error]
        let neutralRoles: [BoardNeutralTextRole] = [.secondary]
        var exercised = 0

        for scheme in schemes {
            _ = BoardSurfacePalette.detailGradientTokens(for: scheme)
            _ = BoardSurfacePalette.taskCardToken(for: scheme)
            _ = BoardSurfacePalette.supplementaryCardToken(for: scheme)
            _ = BoardSurfacePalette.emptyStateToken(for: scheme)
            _ = BoardChromePalette.counterToken(for: scheme)
            _ = BoardChromePalette.storyPointToken(for: scheme)
            _ = BoardChromePalette.columnBorderToken(for: scheme)
            _ = BoardChromePalette.taskCardBorderToken(for: scheme)
            _ = BoardChromePalette.supplementaryCardBorderToken(for: scheme)
            exercised += 9

            for status in KanbanStatus.allCases {
                _ = BoardSurfacePalette.columnToken(for: status, scheme: scheme)
                exercised += 1
            }

            for severity in severities {
                _ = BoardMessageColorPalette.token(for: severity, scheme: scheme)
                exercised += 1
            }

            for accent in accents {
                _ = SummaryBadgePalette.token(for: accent, scheme: scheme)
                exercised += 1
            }

            for role in semanticRoles {
                _ = BoardSemanticTextPalette.token(for: role, scheme: scheme)
                exercised += 1
            }

            for role in neutralRoles {
                _ = BoardNeutralTextPalette.token(for: role, scheme: scheme)
                exercised += 1
            }
        }

        return exercised
    }

    static func healthScoreAccent(for score: Int) -> SummaryBadgeAccent {
        let summary = BoardHealthSummaryView(
            totalTasks: 1,
            todoTasks: 1,
            unassignedTodoTasks: 0,
            overloadedAgents: 0,
            healthScore: score,
            healthLabel: "Excellent",
            healthBreakdownText: "",
            inProgressPressure: 0,
            reviewPressure: 0,
            blockedTasks: 0,
            criticalPathStoryPoints: 0
        )
        return summary.testHealthScoreAccent
    }

    static func autoFixRecommendationCount(for recommendations: [BoardHealthRecommendation]) -> Int {
        let view = BoardHealthRecommendationsView(
            recommendations: recommendations,
            onAction: { _ in },
            onApplyAll: {}
        )
        return view.testAutoFixRecommendationCount
    }

    static func runtimeSummary(runtimeProfile: AgentRuntimeProfile?) -> String {
        let agent = AgentProfile(
            name: "Agent",
            skills: [],
            maxConcurrentTasks: 1,
            runtimeProfile: runtimeProfile
        )
        let view = ContentView(viewModel: KanbanBoardViewModel(tasks: [], agents: [agent]))
        return view.testRuntimeSummary(for: agent)
    }

    static func buildRuntimeProfile(
        isEnabled: Bool,
        provider: AgentRuntimeProvider,
        model: String,
        endpoint: String,
        toolsText: String,
        openAIAuthMode: OpenAICompatibleAuthMode,
        codexProfile: String
    ) -> AgentRuntimeProfile? {
        let view = ContentView(viewModel: KanbanBoardViewModel(tasks: [], agents: []))
        return view.testBuildRuntimeProfile(
            isEnabled: isEnabled,
            provider: provider,
            model: model,
            endpoint: endpoint,
            toolsText: toolsText,
            openAIAuthMode: openAIAuthMode,
            codexProfile: codexProfile
        )
    }

    static func selectedAssigneeFilter(
        selectedKey: String,
        agents: [AgentProfile]
    ) -> TaskAssigneeFilter {
        ContentView.testResolveSelectedAssigneeFilter(selectedKey: selectedKey, agents: agents)
    }

    static func selectedAgentForConsoleID(
        selectedAgentID: UUID?,
        agents: [AgentProfile]
    ) -> UUID? {
        ContentView.resolveSelectedAgentForConsole(
            selectedAgentID: selectedAgentID,
            agents: agents
        )?.id
    }

    static func syncedSelectedAgentConsoleAgentID(
        currentID: UUID?,
        agents: [AgentProfile]
    ) -> UUID? {
        ContentView.syncedSelectedAgentConsoleAgentID(currentID: currentID, agents: agents)
    }

    static func normalizedAssigneeFilterKey(
        currentKey: String,
        validKeys: Set<String>
    ) -> String {
        ContentView.normalizedAssigneeFilterKey(currentKey: currentKey, validKeys: validKeys)
    }

    static func canAutoAssignFromToolbar(tasks: [WorkTask], agents: [AgentProfile]) -> Bool {
        ContentView.testCanAutoAssignFromToolbar(tasks: tasks, agents: agents)
    }

    static func canBatchRunAssignedTasks(
        tasks: [WorkTask],
        isBatchRunning: Bool,
        isAutoCycleRunning: Bool
    ) -> Bool {
        return ContentView.testCanBatchRunAssignedTasks(
            tasks: tasks,
            isBatchRunning: isBatchRunning,
            isAutoCycleRunning: isAutoCycleRunning
        )
    }

    static func canRunAutoCycle(
        tasks: [WorkTask],
        isBatchRunning: Bool,
        isAutoCycleRunning: Bool
    ) -> Bool {
        return ContentView.testCanRunAutoCycle(
            tasks: tasks,
            isBatchRunning: isBatchRunning,
            isAutoCycleRunning: isAutoCycleRunning
        )
    }

    static func handleBoolResult(_ changed: Bool, onChanged: () -> Void) -> Bool {
        ContentView.handleBoolResult(changed, onChanged: onChanged)
    }

    static func handlePositiveCountResult(_ count: Int, onPositive: () -> Void) -> Int {
        ContentView.handlePositiveCountResult(count, onPositive: onPositive)
    }

    static func applyEditableChange<ID>(
        editingID: ID?,
        apply: (ID) -> Bool,
        onApplied: () -> Void
    ) -> Bool {
        ContentView.applyEditableChange(editingID: editingID, apply: apply, onApplied: onApplied)
    }

    static func manualAssignTask(
        taskID: UUID,
        selectedAgentID: UUID?,
        assigner: (UUID, UUID) -> Bool
    ) -> Bool {
        ContentView.manualAssignTask(taskID: taskID, selectedAgentID: selectedAgentID, assigner: assigner)
    }

    static func postManualAssignment(
        assigned: Bool,
        taskID: UUID,
        triageSelectionByTaskID: inout [UUID: UUID],
        refresh: () -> Void,
        hasRemainingCandidates: () -> Bool,
        closeManualTriage: () -> Void
    ) -> Bool {
        ContentView.postManualAssignment(
            assigned: assigned,
            taskID: taskID,
            triageSelectionByTaskID: &triageSelectionByTaskID,
            refresh: refresh,
            hasRemainingCandidates: hasRemainingCandidates,
            closeManualTriage: closeManualTriage
        )
    }

    static func postAutoAssign(
        hasPendingManualTriage: Bool,
        refresh: () -> Void,
        openManualTriage: () -> Void
    ) {
        ContentView.postAutoAssign(
            hasPendingManualTriage: hasPendingManualTriage,
            refresh: refresh,
            openManualTriage: openManualTriage
        )
    }

    static func postHealthRecommendation(
        action: BoardHealthAction,
        applied: Bool,
        hasPendingManualTriage: Bool,
        refresh: () -> Void,
        openManualTriage: () -> Void,
        openNewAgent: () -> Void
    ) {
        ContentView.postHealthRecommendation(
            action: action,
            applied: applied,
            hasPendingManualTriage: hasPendingManualTriage,
            refresh: refresh,
            openManualTriage: openManualTriage,
            openNewAgent: openNewAgent
        )
    }

    static func postApplyAllHealthRecommendations(
        appliedCount: Int,
        hasPendingManualTriage: Bool,
        refresh: () -> Void,
        openManualTriage: () -> Void
    ) {
        ContentView.postApplyAllHealthRecommendations(
            appliedCount: appliedCount,
            hasPendingManualTriage: hasPendingManualTriage,
            refresh: refresh,
            openManualTriage: openManualTriage
        )
    }

    static func handleSavePanelResult(
        modalResponse: NSApplication.ModalResponse,
        url: URL?,
        exporter: (URL) -> Bool
    ) -> Bool {
        ContentView.handleSavePanelResult(
            modalResponse: modalResponse,
            url: url,
            exporter: exporter
        )
    }

    static func handleWorkspaceImport(
        modalResponse: NSApplication.ModalResponse,
        url: URL?,
        previewProvider: (URL) -> WorkspaceImportPreview?,
        strategyChooser: (WorkspaceImportPreview) -> WorkspaceImportStrategy?,
        importer: (URL, WorkspaceImportStrategy) -> Bool,
        onImported: () -> Void
    ) -> Bool {
        ContentView.handleWorkspaceImport(
            modalResponse: modalResponse,
            url: url,
            previewProvider: previewProvider,
            strategyChooser: strategyChooser,
            importer: importer,
            onImported: onImported
        )
    }

    static func workspaceImportInformativeText(preview: WorkspaceImportPreview) -> String {
        ContentView.workspaceImportInformativeText(preview: preview)
    }

    static func configuredWorkspaceExportPanel() -> NSSavePanel {
        ContentView.configuredWorkspaceExportPanel()
    }

    static func configuredSelectedBoardExportPanel(defaultFileName: String) -> NSSavePanel {
        ContentView.configuredSelectedBoardExportPanel(defaultFileName: defaultFileName)
    }

    static func configuredExecutionReportJSONPanel(defaultFileName: String) -> NSSavePanel {
        ContentView.configuredExecutionReportJSONPanel(defaultFileName: defaultFileName)
    }

    static func configuredExecutionReportMarkdownPanel(defaultFileName: String) -> NSSavePanel {
        ContentView.configuredExecutionReportMarkdownPanel(defaultFileName: defaultFileName)
    }

    static func selectedBoardExportAndExecutionReportFileNames(boardName: String) -> (boardExport: String, reportJSON: String, reportMarkdown: String) {
        let viewModel = KanbanBoardViewModel(tasks: [], agents: [])
        _ = viewModel.createBoard(name: boardName)
        let view = ContentView(viewModel: viewModel)
        return (
            boardExport: view.selectedBoardExportFileName(),
            reportJSON: view.selectedBoardExecutionReportJSONFileName(),
            reportMarkdown: view.selectedBoardExecutionReportMarkdownFileName()
        )
    }

    static func configuredWorkspaceImportPanel() -> NSOpenPanel {
        ContentView.configuredWorkspaceImportPanel()
    }

    static func configuredWorkspaceImportAlert(preview: WorkspaceImportPreview) -> NSAlert {
        ContentView.configuredWorkspaceImportAlert(preview: preview)
    }

    static func workspaceImportStrategy(for modalResponse: NSApplication.ModalResponse) -> WorkspaceImportStrategy? {
        ContentView.workspaceImportStrategy(for: modalResponse)
    }

    static func uniquePMBoardName(baseName: String, existingNames: [String]) -> String {
        ContentView.uniquePMBoardName(baseName: baseName, existingNames: existingNames)
    }

    static func normalizedSkillList(from rawValue: String) -> [String] {
        ContentView.normalizedSkillList(from: rawValue)
    }

    static func pmBriefTemplateOptionIDs() -> [String] {
        ContentView.pmBriefTemplateOptions().map(\.id)
    }

    static func applyPMTemplate(
        selectedTemplateID: String,
        projectName: inout String,
        projectBrief: inout String
    ) -> Bool {
        ContentView.applyPMTemplate(
            selectedTemplateID: selectedTemplateID,
            projectName: &projectName,
            projectBrief: &projectBrief
        )
    }

    static func applyPMTemplateAndReset(
        selectedTemplateID: String,
        projectName: inout String,
        projectBrief: inout String,
        planSummary: inout String,
        plannedTickets: inout [PMPlannedTicket]
    ) -> Bool {
        ContentView.applyPMTemplateAndReset(
            selectedTemplateID: selectedTemplateID,
            projectName: &projectName,
            projectBrief: &projectBrief,
            planSummary: &planSummary,
            plannedTickets: &plannedTickets
        )
    }

    static func pmBlueprintBriefText(
        vision: String,
        targetUsers: String,
        coreFeatures: String,
        techScope: String,
        constraints: String,
        qualityBar: String
    ) -> String {
        ContentView.pmBlueprintBriefText(
            vision: vision,
            targetUsers: targetUsers,
            coreFeatures: coreFeatures,
            techScope: techScope,
            constraints: constraints,
            qualityBar: qualityBar
        )
    }

    static func applyPMBlueprint(
        vision: String,
        targetUsers: String,
        coreFeatures: String,
        techScope: String,
        constraints: String,
        qualityBar: String,
        projectName: inout String,
        projectBrief: inout String
    ) -> Bool {
        ContentView.applyPMBlueprint(
            vision: vision,
            targetUsers: targetUsers,
            coreFeatures: coreFeatures,
            techScope: techScope,
            constraints: constraints,
            qualityBar: qualityBar,
            projectName: &projectName,
            projectBrief: &projectBrief
        )
    }

    static func pmTestPlanText(
        projectName: String,
        projectBrief: String,
        tickets: [PMPlannedTicket]
    ) -> String {
        ContentView.pmTestPlanText(
            projectName: projectName,
            projectBrief: projectBrief,
            tickets: tickets
        )
    }

    static func applyingAutoAcceptanceCriteria(to ticket: PMPlannedTicket) -> PMPlannedTicket {
        ContentView.applyingAutoAcceptanceCriteria(to: ticket)
    }

    static func applyingDependencyChain(to tickets: [PMPlannedTicket]) -> [PMPlannedTicket] {
        ContentView.applyingDependencyChain(to: tickets)
    }

    static func pmPlanCopyText(
        projectName: String,
        summary: String,
        tickets: [PMPlannedTicket]
    ) -> String {
        ContentView.pmPlanCopyText(projectName: projectName, summary: summary, tickets: tickets)
    }

    static func pmPlanCopyText(
        projectName: String,
        summary: String,
        tickets: [PMPlannedTicket],
        testPlan: String
    ) -> String {
        ContentView.pmPlanCopyText(
            projectName: projectName,
            summary: summary,
            tickets: tickets,
            testPlan: testPlan
        )
    }

    static func pmRoadmapText(
        projectName: String,
        tickets: [PMPlannedTicket]
    ) -> String {
        ContentView.pmRoadmapText(projectName: projectName, tickets: tickets)
    }

    static func applyTaskEdits(
        viewModel: KanbanBoardViewModel,
        taskID: UUID,
        title: String,
        details: String,
        requiredSkillsText: String,
        storyPoints: Int
    ) -> Bool {
        ContentView.applyTaskEdits(
            viewModel: viewModel,
            taskID: taskID,
            title: title,
            details: details,
            requiredSkillsText: requiredSkillsText,
            storyPoints: storyPoints
        )
    }

    static func applyTaskEdits(
        viewModel: KanbanBoardViewModel,
        editingTaskID: UUID?,
        title: String,
        details: String,
        requiredSkillsText: String,
        storyPoints: Int
    ) -> Bool {
        ContentView.applyTaskEdits(
            viewModel: viewModel,
            editingTaskID: editingTaskID,
            title: title,
            details: details,
            requiredSkillsText: requiredSkillsText,
            storyPoints: storyPoints
        )
    }

    static func applyAgentEdits(
        viewModel: KanbanBoardViewModel,
        agentID: UUID,
        name: String,
        skillsText: String,
        maxConcurrentTasks: Int,
        runtimeProfile: AgentRuntimeProfile?
    ) -> Bool {
        ContentView.applyAgentEdits(
            viewModel: viewModel,
            agentID: agentID,
            name: name,
            skillsText: skillsText,
            maxConcurrentTasks: maxConcurrentTasks,
            runtimeProfile: runtimeProfile
        )
    }

    static func applyAgentEdits(
        viewModel: KanbanBoardViewModel,
        editingAgentID: UUID?,
        name: String,
        skillsText: String,
        maxConcurrentTasks: Int,
        runtimeProfile: AgentRuntimeProfile?
    ) -> Bool {
        ContentView.applyAgentEdits(
            viewModel: viewModel,
            editingAgentID: editingAgentID,
            name: name,
            skillsText: skillsText,
            maxConcurrentTasks: maxConcurrentTasks,
            runtimeProfile: runtimeProfile
        )
    }

    @MainActor
    static func renderSubviewBodiesForCoverage() -> Int {
        var rendered = 0

        func render<V: View>(_ view: V) {
            _ = view.body
            rendered += 1
        }

        let agentA = AgentProfile(name: "A", skills: ["swiftui"], maxConcurrentTasks: 3)
        let agentB = AgentProfile(name: "B", skills: ["swift", "qa"], maxConcurrentTasks: 2)

        let successRecord = TaskExecutionRecord(
            status: .succeeded,
            runCount: 1,
            lastStartedAt: Date(timeIntervalSince1970: 1_735_000_000),
            lastFinishedAt: Date(timeIntervalSince1970: 1_735_000_030),
            lastOutputSummary: "Summary: Completed successfully"
        )
        let failedRecord = TaskExecutionRecord(
            status: .failed,
            runCount: 2,
            lastStartedAt: Date(timeIntervalSince1970: 1_735_000_060),
            lastFinishedAt: Date(timeIntervalSince1970: 1_735_000_090),
            lastError: "Execution failed",
            lastDebugOutput: "stderr output"
        )

        let todoTask = WorkTask(
            title: "Todo",
            details: "Task details",
            requiredSkills: ["swiftui"],
            storyPoints: 3,
            status: .todo,
            assignedAgentID: agentA.id,
            executionRecord: successRecord
        )
        let reviewTask = WorkTask(
            title: "Review",
            details: "Review details",
            requiredSkills: [],
            storyPoints: 2,
            status: .review,
            assignedAgentID: agentB.id,
            executionRecord: failedRecord
        )

        let boardTarget = KanbanBoardRecord(name: "Target Board")
        let searchResult = GlobalTaskSearchResult(
            taskID: todoTask.id,
            taskTitle: todoTask.title,
            taskDetails: todoTask.details,
            status: todoTask.status,
            boardID: boardTarget.id,
            boardName: boardTarget.name,
            assigneeName: "A"
        )

        let event = AgentExecutionEvent(
            timestamp: Date(timeIntervalSince1970: 1_735_000_100),
            agentID: agentA.id,
            taskID: todoTask.id,
            taskTitle: todoTask.title,
            status: .running,
            message: "Running command",
            details: "Step 1/3"
        )

        render(AgentRowView(
            name: "A",
            skillsText: "swiftui",
            runtimeText: "Runtime",
            loadCount: 2,
            maxLoad: 3,
            loadPercent: 67,
            loadProgress: 0.67,
            isOverloaded: false,
            isRunning: false,
            recentEventMessage: "Last update",
            isSelected: false
        ))
        render(AgentRowView(
            name: "B",
            skillsText: "qa",
            runtimeText: "Runtime",
            loadCount: 3,
            maxLoad: 2,
            loadPercent: 150,
            loadProgress: 1.0,
            isOverloaded: true,
            isRunning: true,
            recentEventMessage: nil,
            isSelected: true
        ))

        render(BoardHealthSummaryView(
            totalTasks: 2,
            todoTasks: 1,
            unassignedTodoTasks: 0,
            overloadedAgents: 1,
            healthScore: 72,
            healthLabel: "Watch",
            healthBreakdownText: "Needs attention",
            inProgressPressure: 50,
            reviewPressure: 100,
            blockedTasks: 1,
            criticalPathStoryPoints: 8
        ))
        render(BoardDependencyInsightsView(
            insights: DependencyGraphInsights(
                totalTaskDependencies: 2,
                externalDependencyCount: 1,
                blockedTaskCount: 1,
                criticalPathStoryPoints: 8,
                criticalPathTaskIDs: [UUID()],
                criticalPathTaskTitles: ["Spec", "Build"],
                cycleTaskTitles: []
            )
        ))
        render(BoardHealthRecommendationsView(
            recommendations: [],
            onAction: { _ in },
            onApplyAll: {}
        ))
        render(BoardHealthRecommendationsView(
            recommendations: [
                BoardHealthRecommendation(action: .autoAssignUnassignedTodo, title: "Auto Assign", detail: "Assign todo"),
                BoardHealthRecommendation(action: .openManualTriage, title: "Manual Triage", detail: "Review assignments")
            ],
            onAction: { _ in },
            onApplyAll: {}
        ))

        render(SummaryBadge(title: "Total", value: "2", accent: .blue, helpText: nil))
        render(SummaryBadge(title: "Health", value: "72", accent: .amber, helpText: "Needs attention"))

        render(KanbanColumnView(
            status: .todo,
            tasks: [],
            wipLimit: nil,
            assigneeName: { _ in "Unassigned" },
            assignmentReason: { _ in nil },
            dependencyBlockedReason: { _ in nil },
            moveBackward: { _ in },
            moveForward: { _ in },
            onEditTask: { _ in },
            onDeleteTask: { _ in },
            onDuplicateTask: { _ in },
            onUnassignTask: { _ in },
            onAutoAssignTask: { _ in },
            onRunTaskExecution: { _ in },
            onRetryTaskExecution: { _ in },
            assignableAgents: { _ in [agentA] },
            reassignableAgents: { _ in [agentB] },
            onManualAssignTask: { _, _ in },
            onReassignTask: { _, _ in },
            moveToBoardTargets: [boardTarget],
            onMoveTaskToBoard: { _, _ in },
            onCopyTaskToBoard: { _, _ in },
            onShowExecutionDetails: { _ in },
            hasExecutionTimeline: { _ in false },
            onCopyExecutionTimeline: { _ in },
            onDropTask: { _ in true }
        ))
        render(KanbanColumnView(
            status: .review,
            tasks: [reviewTask],
            wipLimit: 2,
            assigneeName: { _ in "B" },
            assignmentReason: { _ in "skills[qa]" },
            dependencyBlockedReason: { _ in nil },
            moveBackward: { _ in },
            moveForward: { _ in },
            onEditTask: { _ in },
            onDeleteTask: { _ in },
            onDuplicateTask: { _ in },
            onUnassignTask: { _ in },
            onAutoAssignTask: { _ in },
            onRunTaskExecution: { _ in },
            onRetryTaskExecution: { _ in },
            assignableAgents: { _ in [agentA] },
            reassignableAgents: { _ in [agentA] },
            onManualAssignTask: { _, _ in },
            onReassignTask: { _, _ in },
            moveToBoardTargets: [boardTarget],
            onMoveTaskToBoard: { _, _ in },
            onCopyTaskToBoard: { _, _ in },
            onShowExecutionDetails: { _ in },
            hasExecutionTimeline: { _ in true },
            onCopyExecutionTimeline: { _ in },
            onDropTask: { _ in true }
        ))

        render(TaskCardView(
            task: todoTask,
            assigneeName: "A",
            assignmentReason: "skills[swiftui]",
            dependencyBlockedReason: nil,
            canMoveBackward: false,
            canMoveForward: true,
            canUnassign: true,
            canAutoAssign: false,
            canRunAgent: true,
            canRetryAgent: false,
            executionRecord: successRecord,
            manualAssignableAgents: [agentB],
            reassignableAgents: [agentB],
            moveToBoardTargets: [boardTarget],
            onEdit: {},
            onAutoAssign: {},
            onRunAgent: {},
            onRetryAgent: {},
            onManualAssign: { _ in },
            onReassign: { _ in },
            onUnassign: {},
            onDuplicate: {},
            onDelete: {},
            onMoveToBoard: { _ in },
            onCopyToBoard: { _ in },
            onShowExecutionDetails: {},
            hasExecutionTimeline: true,
            onCopyExecutionTimeline: {},
            onMoveBackward: {},
            onMoveForward: {}
        ))
        render(TaskCardView(
            task: reviewTask,
            assigneeName: "B",
            assignmentReason: nil,
            dependencyBlockedReason: nil,
            canMoveBackward: true,
            canMoveForward: true,
            canUnassign: true,
            canAutoAssign: false,
            canRunAgent: true,
            canRetryAgent: true,
            executionRecord: failedRecord,
            manualAssignableAgents: [agentA],
            reassignableAgents: [agentA],
            moveToBoardTargets: [boardTarget],
            onEdit: {},
            onAutoAssign: {},
            onRunAgent: {},
            onRetryAgent: {},
            onManualAssign: { _ in },
            onReassign: { _ in },
            onUnassign: {},
            onDuplicate: {},
            onDelete: {},
            onMoveToBoard: { _ in },
            onCopyToBoard: { _ in },
            onShowExecutionDetails: {},
            hasExecutionTimeline: true,
            onCopyExecutionTimeline: {},
            onMoveBackward: {},
            onMoveForward: {}
        ))

        var emptyQuery = ""
        var filledQuery = "todo"
        render(GlobalTaskSearchSheet(
            query: Binding(get: { emptyQuery }, set: { emptyQuery = $0 }),
            results: [],
            onOpenResult: { _ in },
            onClose: {}
        ))
        render(GlobalTaskSearchSheet(
            query: Binding(get: { filledQuery }, set: { filledQuery = $0 }),
            results: [searchResult],
            onOpenResult: { _ in },
            onClose: {}
        ))

        var boardName = "New Board"
        render(NewBoardSheet(
            name: Binding(get: { boardName }, set: { boardName = $0 }),
            boardMessage: "Board created",
            boardMessageSeverity: .info,
            onCancel: {},
            onCreate: {}
        ))
        render(RenameBoardSheet(
            name: Binding(get: { boardName }, set: { boardName = $0 }),
            boardMessage: nil,
            boardMessageSeverity: nil,
            onCancel: {},
            onRename: {}
        ))

        var taskTitle = "Task"
        var taskDetails = "Details"
        var taskSkills = "swiftui"
        var taskPoints = 3
        var selectedTemplateID: UUID? = nil
        let previewTemplates = [
            TaskTemplate(
                name: "UI Task",
                title: "Build Kanban UI",
                details: "Implement reusable board/task UI components.",
                requiredSkills: ["swiftui", "ui"],
                storyPoints: 3
            )
        ]
        render(NewTaskSheet(
            title: Binding(get: { taskTitle }, set: { taskTitle = $0 }),
            details: Binding(get: { taskDetails }, set: { taskDetails = $0 }),
            skills: Binding(get: { taskSkills }, set: { taskSkills = $0 }),
            storyPoints: Binding(get: { taskPoints }, set: { taskPoints = $0 }),
            selectedTemplateID: Binding(get: { selectedTemplateID }, set: { selectedTemplateID = $0 }),
            templates: previewTemplates,
            boardMessage: nil,
            boardMessageSeverity: nil,
            onCancel: {},
            onApplyTemplate: {},
            onSaveAsTemplate: {},
            onCreate: {},
            onCreateAutoAssign: {}
        ))
        render(EditTaskSheet(
            title: Binding(get: { taskTitle }, set: { taskTitle = $0 }),
            details: Binding(get: { taskDetails }, set: { taskDetails = $0 }),
            skills: Binding(get: { taskSkills }, set: { taskSkills = $0 }),
            storyPoints: Binding(get: { taskPoints }, set: { taskPoints = $0 }),
            boardMessage: "Saved",
            boardMessageSeverity: .info,
            onCancel: {},
            onSave: {}
        ))

        var inProgressLimit = 3
        var reviewLimit = 2
        render(WIPSettingsSheet(
            inProgressLimit: Binding(get: { inProgressLimit }, set: { inProgressLimit = $0 }),
            reviewLimit: Binding(get: { reviewLimit }, set: { reviewLimit = $0 }),
            onCancel: {},
            onApply: {}
        ))

        var runtimeEnabled = true
        var runtimeProvider: AgentRuntimeProvider = .openAICompatible
        var runtimeModel = "gpt-5"
        var runtimeEndpoint = "https://api.openai.com/v1"
        var runtimeTools = "shell,git"
        var authMode: OpenAICompatibleAuthMode = .apiKey
        var codexProfile = "default"
        var agentName = "Agent"
        var agentSkills = "swiftui"
        var agentCapacity = 3
        render(NewAgentSheet(
            name: Binding(get: { agentName }, set: { agentName = $0 }),
            skills: Binding(get: { agentSkills }, set: { agentSkills = $0 }),
            maxConcurrentTasks: Binding(get: { agentCapacity }, set: { agentCapacity = $0 }),
            runtimeEnabled: Binding(get: { runtimeEnabled }, set: { runtimeEnabled = $0 }),
            runtimeProvider: Binding(get: { runtimeProvider }, set: { runtimeProvider = $0 }),
            runtimeModel: Binding(get: { runtimeModel }, set: { runtimeModel = $0 }),
            runtimeEndpoint: Binding(get: { runtimeEndpoint }, set: { runtimeEndpoint = $0 }),
            runtimeTools: Binding(get: { runtimeTools }, set: { runtimeTools = $0 }),
            openAIAuthMode: Binding(get: { authMode }, set: { authMode = $0 }),
            codexProfile: Binding(get: { codexProfile }, set: { codexProfile = $0 }),
            boardMessage: nil,
            boardMessageSeverity: nil,
            onCancel: {},
            onCreate: {}
        ))
        authMode = .codexBridge
        render(EditAgentSheet(
            name: Binding(get: { agentName }, set: { agentName = $0 }),
            skills: Binding(get: { agentSkills }, set: { agentSkills = $0 }),
            maxConcurrentTasks: Binding(get: { agentCapacity }, set: { agentCapacity = $0 }),
            runtimeEnabled: Binding(get: { runtimeEnabled }, set: { runtimeEnabled = $0 }),
            runtimeProvider: Binding(get: { runtimeProvider }, set: { runtimeProvider = $0 }),
            runtimeModel: Binding(get: { runtimeModel }, set: { runtimeModel = $0 }),
            runtimeEndpoint: Binding(get: { runtimeEndpoint }, set: { runtimeEndpoint = $0 }),
            runtimeTools: Binding(get: { runtimeTools }, set: { runtimeTools = $0 }),
            openAIAuthMode: Binding(get: { authMode }, set: { authMode = $0 }),
            codexProfile: Binding(get: { codexProfile }, set: { codexProfile = $0 }),
            boardMessage: "Updated",
            boardMessageSeverity: .info,
            onCancel: {},
            onSave: {}
        ))

        var triageSelections: [UUID: UUID] = [todoTask.id: agentA.id]
        render(ManualTriageSheet(
            tasks: [todoTask],
            boardMessage: nil,
            boardMessageSeverity: nil,
            selectedAgentByTaskID: Binding(get: { triageSelections }, set: { triageSelections = $0 }),
            assignAllEligibleCount: 1,
            unassignableTaskCount: 0,
            assignableAgents: { _ in [agentA, agentB] },
            loadText: { _ in "1/3" },
            onAssign: { _ in },
            onAssignAll: {},
            onClose: {}
        ))

        let detailsPresentation = ExecutionDetailsPresentation(
            taskTitle: "Task",
            assigneeName: "A",
            executionRecord: failedRecord,
            timelineText: nil
        )
        render(ExecutionDetailsSheet(
            details: detailsPresentation,
            onCopy: { _ in },
            onClose: {}
        ))

        render(AgentLiveConsoleView(
            agentName: "A",
            isRunning: false,
            events: [],
            onCopy: { _ in },
            onClear: {}
        ))
        render(AgentLiveConsoleView(
            agentName: "A",
            isRunning: true,
            events: [event],
            onCopy: { _ in },
            onClear: {}
        ))
        render(AgentExecutionEventRow(event: event, onCopy: { _ in }))
        render(BoardMessageBanner(message: "Info message", severity: .info))

        return rendered
    }

    @MainActor
    static func exerciseActionHandlersForCoverage() -> Int {
        ContentView.testExerciseActionHandlersForCoverage()
    }

    @MainActor
    static func exerciseTargetedHelperBranchesForCoverage() -> Int {
        ContentView.testExerciseTargetedHelperBranchesForCoverage()
    }

    @MainActor
    static func exerciseRecommendationAndTriageHelpersForCoverage() -> Int {
        ContentView.testExerciseRecommendationAndTriageHelpersForCoverage()
    }
}
#endif

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
