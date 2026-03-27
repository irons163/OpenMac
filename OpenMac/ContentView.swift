import SwiftUI

struct ContentView: View {
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
                    colors: [Color(red: 0.96, green: 0.98, blue: 1.0), Color(red: 0.93, green: 0.96, blue: 0.99)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        }
        .toolbar {
            ToolbarItemGroup {
                Button("Auto Assign AI") {
                    viewModel.autoAssignTasks()
                }
                Button("New Task") {
                    isShowingNewTaskSheet = true
                }
                Button("New Agent") {
                    isShowingNewAgentSheet = true
                }
                Button("Archive Done") {
                    archiveDoneTasks()
                }
                .disabled(viewModel.tasks(in: .done).isEmpty)
                Button("Rebalance Load") {
                    rebalanceTodoAssignments()
                }
                .disabled(!viewModel.canRebalanceTodoAssignments())
                Button("WIP Limits") {
                    openWIPSettings()
                }
                Button("Manual Triage") {
                    openManualTriage()
                }
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
                assignableAgents: { task in
                    viewModel.assignableAgents(for: task.id)
                },
                loadText: { agent in "\(viewModel.activeTaskCount(for: agent.id))/\(agent.maxConcurrentTasks)" },
                onAssign: assignManually,
                onAssignAll: assignAllManually,
                onClose: { isShowingManualTriageSheet = false }
            )
        }
        .onChange(of: viewModel.agents) { _ in
            normalizeAssigneeFilterSelection()
        }
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
        _ = viewModel.bulkAssignTriageTasks()
        refreshTriageSelections()
        if viewModel.triageCandidates().isEmpty {
            isShowingManualTriageSheet = false
        }
    }

    private func refreshTriageSelections() {
        let candidates = viewModel.triageCandidates()
        var refreshed: [UUID: UUID] = [:]

        for task in candidates {
            if let existing = triageSelectionByTaskID[task.id] {
                refreshed[task.id] = existing
            } else if let fallback = defaultTriageAgentID(for: task) {
                refreshed[task.id] = fallback
            }
        }

        triageSelectionByTaskID = refreshed
    }

    private func defaultTriageAgentID(for task: WorkTask) -> UUID? {
        viewModel.assignableAgents(for: task.id).first?.id
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

private struct KanbanColumnView: View {
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
                        .background(Color.white.opacity(0.7), in: Capsule())
                } else {
                    Text("\(tasks.count)")
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color.white.opacity(0.7), in: Capsule())
                }
            }

            if tasks.isEmpty {
                Text("No tasks")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 120)
                    .background(Color.white.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
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
                .stroke(Color.white.opacity(0.65), lineWidth: 1)
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
        switch status {
        case .todo:
            return Color(red: 0.84, green: 0.92, blue: 1.0)
        case .inProgress:
            return Color(red: 0.82, green: 0.95, blue: 0.88)
        case .review:
            return Color(red: 1.0, green: 0.93, blue: 0.79)
        case .done:
            return Color(red: 0.90, green: 0.90, blue: 0.93)
        }
    }
}

private struct TaskCardView: View {
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
                    .background(Color.black.opacity(0.08), in: Capsule())

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
        .background(Color.white, in: RoundedRectangle(cornerRadius: 12))
        .contextMenu {
            Button("Edit Task", action: onEdit)
            if canUnassign {
                Button("Unassign Task", action: onUnassign)
            }
            Button("Delete Task", role: .destructive, action: onDelete)
        }
        .draggable(task.id.uuidString)
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
    let tasks: [WorkTask]
    let boardMessage: String?
    @Binding var selectedAgentByTaskID: [UUID: UUID]
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
                Button("Assign All Eligible", action: onAssignAll)
                    .buttonStyle(.bordered)
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
                            .background(Color.white.opacity(0.85), in: RoundedRectangle(cornerRadius: 10))
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
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
