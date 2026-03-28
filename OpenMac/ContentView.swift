import SwiftUI

struct ContentView: View {
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("appearanceMode") private var appearanceModeRawValue = AppAppearanceMode.system.rawValue
    @StateObject private var viewModel: KanbanBoardViewModel

    @State private var isShowingNewTaskSheet = false
    @State private var isShowingEditTaskSheet = false
    @State private var isShowingNewAgentSheet = false
    @State private var isShowingEditAgentSheet = false
    @State private var isShowingWIPSettingsSheet = false
    @State private var isShowingManualTriageSheet = false
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
                    Text("AI Agent Kanban Dispatch")
                        .font(.title2.weight(.semibold))
                    Spacer()
                    if !viewModel.triageCandidates().isEmpty {
                        Text("\(viewModel.triageCandidates().count) task(s) need manual triage")
                            .font(.callout)
                            .foregroundStyle(.orange)
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
                        .foregroundStyle(.secondary)

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
                        .foregroundStyle(.red)
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
                                onUnassignTask: unassignTask,
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
        .sheet(isPresented: $isShowingNewTaskSheet) {
            NewTaskSheet(
                title: $newTaskTitle,
                details: $newTaskDetails,
                skills: $newTaskSkills,
                storyPoints: $newTaskPoints,
                boardMessage: viewModel.lastBoardMessage,
                onCancel: resetDraftAndClose,
                onCreate: {
                    let added = viewModel.addTask(
                        title: newTaskTitle,
                        details: newTaskDetails,
                        requiredSkillsText: newTaskSkills,
                        storyPoints: newTaskPoints
                    )
                    if added {
                        resetDraftAndClose()
                    }
                }
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
                onCancel: closeEditAgentSheet,
                onSave: applyAgentEdits
            )
        }
        .sheet(isPresented: $isShowingManualTriageSheet) {
            ManualTriageSheet(
                tasks: viewModel.triageCandidates(),
                boardMessage: viewModel.lastBoardMessage,
                selectedAgentByTaskID: $triageSelectionByTaskID,
                assignAllEligibleCount: viewModel.bulkAssignableTriageTaskCount(using: triageSelectionByTaskID),
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

    private func unassignTask(_ taskID: UUID) {
        let unassigned = viewModel.unassignTask(taskID)
        if unassigned {
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
        if colorScheme == .dark {
            return [
                Color(red: 0.12, green: 0.14, blue: 0.18),
                Color(red: 0.10, green: 0.12, blue: 0.16)
            ]
        }
        return [
            Color(red: 0.96, green: 0.98, blue: 1.0),
            Color(red: 0.93, green: 0.96, blue: 0.99)
        ]
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
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                ProgressView(value: loadProgress, total: 1.0)
                    .progressViewStyle(.linear)
                Text("\(loadPercent)%")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Text("Load: \(loadCount)/\(maxLoad)")
                .font(.caption2)
                .foregroundStyle(isOverloaded ? .red : .secondary)
            if isOverloaded {
                Text("Overloaded")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.red)
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
                SummaryBadge(title: "Total", value: "\(totalTasks)", color: .blue)
                SummaryBadge(title: "To Do", value: "\(todoTasks)", color: .indigo)
                SummaryBadge(title: "Unassigned", value: "\(unassignedTodoTasks)", color: .orange)
                SummaryBadge(title: "Overloaded", value: "\(overloadedAgents)", color: overloadedAgents > 0 ? .red : .green)
                SummaryBadge(
                    title: "Health",
                    value: "\(healthScore) \(healthLabel)",
                    color: healthScoreColor,
                    helpText: healthBreakdownText
                )
                SummaryBadge(title: "InProg WIP", value: "\(inProgressPressure)%", color: inProgressPressure >= 100 ? .red : .teal)
                SummaryBadge(title: "Review WIP", value: "\(reviewPressure)%", color: reviewPressure >= 100 ? .red : .mint)
                Spacer(minLength: 0)
            }
        }
    }

    private var healthScoreColor: Color {
        if healthScore >= 85 {
            return .green
        }
        if healthScore >= 60 {
            return .orange
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
                    .foregroundStyle(.green)
            } else {
                HStack {
                    Text("Suggested Actions")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
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
                                        .foregroundStyle(.secondary)
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
        colorScheme == .dark ? Color.white.opacity(0.12) : Color.white.opacity(0.92)
    }

    private var recommendationCardBorder: Color {
        colorScheme == .dark ? Color.white.opacity(0.20) : Color.black.opacity(0.12)
    }

    private var autoFixRecommendationCount: Int {
        recommendations.filter { $0.action.isAutoFixable }.count
    }
}

private struct SummaryBadge: View {
    @Environment(\.colorScheme) private var colorScheme
    let title: String
    let value: String
    let color: Color
    var helpText: String?

    var body: some View {
        let badgeContent = VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
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
        .background(color.opacity(colorScheme == .dark ? 0.32 : 0.2), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(colorScheme == .dark ? Color.white.opacity(0.2) : Color.black.opacity(0.1), lineWidth: 1)
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
    let onUnassignTask: (UUID) -> Void
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
                        .foregroundStyle(tasks.count >= wipLimit ? .red : .primary)
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
                    .foregroundStyle(.secondary)
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
                        onEdit: { onEditTask(task) },
                        onUnassign: { onUnassignTask(task.id) },
                        onDelete: { onDeleteTask(task.id) },
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
        if colorScheme == .dark {
            switch status {
            case .todo:
                return Color(red: 0.16, green: 0.23, blue: 0.31)
            case .inProgress:
                return Color(red: 0.15, green: 0.27, blue: 0.21)
            case .review:
                return Color(red: 0.30, green: 0.25, blue: 0.16)
            case .done:
                return Color(red: 0.21, green: 0.22, blue: 0.27)
            }
        }
        switch status {
        case .todo:
            return Color(red: 0.82, green: 0.9, blue: 0.98)
        case .inProgress:
            return Color(red: 0.81, green: 0.94, blue: 0.87)
        case .review:
            return Color(red: 0.99, green: 0.92, blue: 0.77)
        case .done:
            return Color(red: 0.89, green: 0.89, blue: 0.92)
        }
    }

    private var counterBackground: Color {
        colorScheme == .dark ? Color.white.opacity(0.2) : Color.white.opacity(0.82)
    }

    private var emptyStateBackground: Color {
        colorScheme == .dark ? Color.white.opacity(0.12) : Color.white.opacity(0.68)
    }

    private var columnBorderColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.24) : Color.white.opacity(0.8)
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
    let onEdit: () -> Void
    let onUnassign: () -> Void
    let onDelete: () -> Void
    let onMoveBackward: () -> Void
    let onMoveForward: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(task.title)
                .font(.headline)
            if !task.details.isEmpty {
                Text(task.details)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if !task.requiredSkills.isEmpty {
                Text("Skills: \(task.requiredSkills.sorted().joined(separator: ", "))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
                    .foregroundStyle(.secondary)
            }

            if let assignmentReason, task.assignedAgentID != nil {
                Text("Dispatch: \(assignmentReason)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
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
            if canUnassign {
                Button("Unassign Task", action: onUnassign)
            }
            Button("Delete Task", role: .destructive, action: onDelete)
        }
        .draggable(task.id.uuidString)
    }

    private var storyPointBackground: Color {
        colorScheme == .dark ? Color.white.opacity(0.14) : Color.black.opacity(0.08)
    }

    private var taskCardBackground: Color {
        colorScheme == .dark ? Color(red: 0.19, green: 0.2, blue: 0.24) : Color.white
    }

    private var taskCardBorder: Color {
        colorScheme == .dark ? Color.white.opacity(0.18) : Color.black.opacity(0.08)
    }
}

private struct NewTaskSheet: View {
    @Binding var title: String
    @Binding var details: String
    @Binding var skills: String
    @Binding var storyPoints: Int
    let boardMessage: String?

    let onCancel: () -> Void
    let onCreate: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Create Task")
                .font(.title3.weight(.semibold))

            if let boardMessage, !boardMessage.isEmpty {
                Text(boardMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
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

    let onCancel: () -> Void
    let onSave: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Edit Task")
                .font(.title3.weight(.semibold))

            if let boardMessage, !boardMessage.isEmpty {
                Text(boardMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
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

    let onCancel: () -> Void
    let onCreate: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Create Agent")
                .font(.title3.weight(.semibold))

            if let boardMessage, !boardMessage.isEmpty {
                Text(boardMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
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

    let onCancel: () -> Void
    let onSave: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Edit Agent")
                .font(.title3.weight(.semibold))

            if let boardMessage, !boardMessage.isEmpty {
                Text(boardMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
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
    @Binding var selectedAgentByTaskID: [UUID: UUID]
    let assignAllEligibleCount: Int
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
                Text(boardMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button("Assign All Eligible (\(assignAllEligibleCount))", action: onAssignAll)
                    .buttonStyle(.bordered)
                    .disabled(assignAllEligibleCount == 0)
            }

            if tasks.isEmpty {
                Text("No tasks waiting for manual triage.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(tasks) { task in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(task.title)
                                    .font(.headline)
                                Text("Skills: \(task.requiredSkills.sorted().joined(separator: ", "))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)

                                let eligibleAgents = assignableAgents(task)

                                if eligibleAgents.isEmpty {
                                    Text("No eligible agents currently available.")
                                        .font(.caption)
                                        .foregroundStyle(.red)
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
        colorScheme == .dark ? Color.white.opacity(0.12) : Color.white.opacity(0.94)
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
