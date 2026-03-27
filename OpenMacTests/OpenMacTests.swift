import Foundation
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
