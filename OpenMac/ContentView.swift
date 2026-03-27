import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel: KanbanBoardViewModel

    @State private var isShowingNewTaskSheet = false
    @State private var isShowingWIPSettingsSheet = false
    @State private var newTaskTitle = ""
    @State private var newTaskDetails = ""
    @State private var newTaskSkills = ""
    @State private var newTaskPoints = 1
    @State private var inProgressWIPLimitDraft = 1
    @State private var reviewWIPLimitDraft = 1

    init(viewModel: KanbanBoardViewModel = .demoBoard()) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        NavigationSplitView {
            List(viewModel.agents) { agent in
                VStack(alignment: .leading, spacing: 4) {
                    Text(agent.name)
                        .font(.headline)
                    Text("Skills: \(agent.skills.sorted().joined(separator: ", "))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("Load: \(viewModel.activeTaskCount(for: agent.id))/\(agent.maxConcurrentTasks)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .padding(.vertical, 4)
            }
            .navigationTitle("AI Agents")
        } detail: {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("AI Agent Kanban Dispatch")
                        .font(.title2.weight(.semibold))
                    Spacer()
                    if !viewModel.lastUnassignedTaskIDs.isEmpty {
                        Text("\(viewModel.lastUnassignedTaskIDs.count) task(s) need manual triage")
                            .font(.callout)
                            .foregroundStyle(.orange)
                    }
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
                                tasks: viewModel.tasks(in: status),
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
                Button("WIP Limits") {
                    openWIPSettings()
                }
            }
        }
        .sheet(isPresented: $isShowingNewTaskSheet) {
            NewTaskSheet(
                title: $newTaskTitle,
                details: $newTaskDetails,
                skills: $newTaskSkills,
                storyPoints: $newTaskPoints,
                onCancel: resetDraftAndClose,
                onCreate: {
                    viewModel.addTask(
                        title: newTaskTitle,
                        details: newTaskDetails,
                        requiredSkillsText: newTaskSkills,
                        storyPoints: newTaskPoints
                    )
                    resetDraftAndClose()
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
    }

    private func resetDraftAndClose() {
        newTaskTitle = ""
        newTaskDetails = ""
        newTaskSkills = ""
        newTaskPoints = 1
        isShowingNewTaskSheet = false
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
}

private struct KanbanColumnView: View {
    let status: KanbanStatus
    let tasks: [WorkTask]
    let wipLimit: Int?
    let assigneeName: (WorkTask) -> String
    let assignmentReason: (WorkTask) -> String?
    let moveBackward: (WorkTask) -> Void
    let moveForward: (WorkTask) -> Void
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
        .draggable(task.id.uuidString)
    }
}

private struct NewTaskSheet: View {
    @Binding var title: String
    @Binding var details: String
    @Binding var skills: String
    @Binding var storyPoints: Int

    let onCancel: () -> Void
    let onCreate: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Create Task")
                .font(.title3.weight(.semibold))

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

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
