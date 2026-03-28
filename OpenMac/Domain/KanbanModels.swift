import Foundation

enum KanbanStatus: String, CaseIterable, Codable, Identifiable {
    case todo = "To Do"
    case inProgress = "In Progress"
    case review = "Review"
    case done = "Done"

    var id: String { rawValue }
    var title: String { rawValue }

    private var order: Int {
        switch self {
        case .todo: return 0
        case .inProgress: return 1
        case .review: return 2
        case .done: return 3
        }
    }

    var previous: KanbanStatus? {
        switch self {
        case .todo: return nil
        case .inProgress: return .todo
        case .review: return .inProgress
        case .done: return .review
        }
    }

    var next: KanbanStatus? {
        switch self {
        case .todo: return .inProgress
        case .inProgress: return .review
        case .review: return .done
        case .done: return nil
        }
    }

    func canMove(to status: KanbanStatus) -> Bool {
        abs(order - status.order) == 1
    }
}

enum AgentRuntimeProvider: String, CaseIterable, Codable, Identifiable {
    case localMock
    case openAICompatible

    var id: String { rawValue }
}

struct AgentRuntimeProfile: Equatable, Codable {
    var provider: AgentRuntimeProvider
    var model: String
    var endpoint: String?
    var tools: Set<String>

    init(
        provider: AgentRuntimeProvider = .localMock,
        model: String = "mock-dispatch-v1",
        endpoint: String? = nil,
        tools: [String] = []
    ) {
        self.provider = provider
        self.model = model.trimmingCharacters(in: .whitespacesAndNewlines)
        self.endpoint = endpoint?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.tools = Set(tools.map(Self.normalizeTool))
    }

    nonisolated private static func normalizeTool(_ rawValue: String) -> String {
        rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

enum TaskExecutionStatus: String, Codable, Equatable {
    case running
    case succeeded
    case failed
}

struct TaskExecutionRecord: Equatable, Codable {
    var status: TaskExecutionStatus
    var runCount: Int
    var lastStartedAt: Date?
    var lastFinishedAt: Date?
    var lastOutputSummary: String?
    var lastError: String?
    var lastAgentID: UUID?

    init(
        status: TaskExecutionStatus,
        runCount: Int = 0,
        lastStartedAt: Date? = nil,
        lastFinishedAt: Date? = nil,
        lastOutputSummary: String? = nil,
        lastError: String? = nil,
        lastAgentID: UUID? = nil
    ) {
        self.status = status
        self.runCount = max(0, runCount)
        self.lastStartedAt = lastStartedAt
        self.lastFinishedAt = lastFinishedAt
        self.lastOutputSummary = lastOutputSummary
        self.lastError = lastError
        self.lastAgentID = lastAgentID
    }
}

struct AgentProfile: Identifiable, Equatable, Codable {
    let id: UUID
    var name: String
    var skills: Set<String>
    var maxConcurrentTasks: Int
    var runtimeProfile: AgentRuntimeProfile?

    init(
        id: UUID = UUID(),
        name: String,
        skills: [String],
        maxConcurrentTasks: Int = 3,
        runtimeProfile: AgentRuntimeProfile? = nil
    ) {
        self.id = id
        self.name = name
        self.skills = Set(skills.map(Self.normalizeSkill))
        self.maxConcurrentTasks = max(1, maxConcurrentTasks)
        self.runtimeProfile = runtimeProfile
    }

    func hasSkills(for task: WorkTask) -> Bool {
        task.requiredSkills.isSubset(of: skills)
    }

    nonisolated private static func normalizeSkill(_ rawValue: String) -> String {
        rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

struct WorkTask: Identifiable, Equatable, Codable {
    let id: UUID
    var title: String
    var details: String
    var requiredSkills: Set<String>
    var storyPoints: Int
    var status: KanbanStatus
    var assignedAgentID: UUID?
    var executionRecord: TaskExecutionRecord?
    let createdAt: Date

    init(
        id: UUID = UUID(),
        title: String,
        details: String,
        requiredSkills: [String],
        storyPoints: Int,
        status: KanbanStatus,
        assignedAgentID: UUID?,
        executionRecord: TaskExecutionRecord? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.details = details
        self.requiredSkills = Set(requiredSkills.map(Self.normalizeSkill))
        self.storyPoints = max(1, storyPoints)
        self.status = status
        self.assignedAgentID = assignedAgentID
        self.executionRecord = executionRecord
        self.createdAt = createdAt
    }

    var isAssignable: Bool {
        status == .todo && assignedAgentID == nil
    }

    nonisolated private static func normalizeSkill(_ rawValue: String) -> String {
        rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

struct KanbanBoardRecord: Identifiable, Equatable, Codable {
    let id: UUID
    var name: String
    var tasks: [WorkTask]
    var agents: [AgentProfile]
    var wipLimits: [KanbanStatus: Int]

    init(
        id: UUID = UUID(),
        name: String,
        tasks: [WorkTask] = [],
        agents: [AgentProfile] = [],
        wipLimits: [KanbanStatus: Int] = [.inProgress: 3, .review: 2]
    ) {
        self.id = id
        self.name = name
        self.tasks = tasks
        self.agents = agents
        self.wipLimits = wipLimits.reduce(into: [:]) { partialResult, pair in
            partialResult[pair.key] = max(1, pair.value)
        }
    }
}
