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

    var displayName: String {
        switch self {
        case .localMock:
            return L10n.string("Local Mock")
        case .openAICompatible:
            return L10n.string("OpenAI Compatible")
        }
    }

    var defaultModel: String {
        switch self {
        case .localMock:
            return "mock-dispatch-v1"
        case .openAICompatible:
            return "gpt-4.1-mini"
        }
    }
}

enum OpenAICompatibleAuthMode: String, CaseIterable, Codable, Identifiable {
    case apiKey
    case codexBridge

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .apiKey:
            return L10n.string("API Key")
        case .codexBridge:
            return L10n.string("Codex Bridge")
        }
    }
}

struct AgentRuntimeProfile: Equatable, Codable {
    var provider: AgentRuntimeProvider
    var model: String
    var endpoint: String?
    var tools: Set<String>
    var openAIAuthMode: OpenAICompatibleAuthMode
    var codexProfile: String?

    init(
        provider: AgentRuntimeProvider = .localMock,
        model: String? = nil,
        endpoint: String? = nil,
        tools: [String] = [],
        openAIAuthMode: OpenAICompatibleAuthMode = .apiKey,
        codexProfile: String? = nil
    ) {
        self.provider = provider
        let trimmedModel = (model ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        self.model = trimmedModel.isEmpty ? provider.defaultModel : trimmedModel
        self.endpoint = Self.normalizeOptional(endpoint)
        self.tools = Set(tools.map(Self.normalizeTool))
        self.openAIAuthMode = openAIAuthMode
        self.codexProfile = Self.normalizeOptional(codexProfile)
    }

    init(
        provider: AgentRuntimeProvider = .localMock,
        model: String? = nil,
        endpoint: String? = nil,
        tools: [String] = []
    ) {
        self.init(
            provider: provider,
            model: model,
            endpoint: endpoint,
            tools: tools,
            openAIAuthMode: .apiKey,
            codexProfile: nil
        )
    }

    enum CodingKeys: String, CodingKey {
        case provider
        case model
        case endpoint
        case tools
        case openAIAuthMode
        case codexProfile
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let provider = try container.decode(AgentRuntimeProvider.self, forKey: .provider)
        let model = try container.decodeIfPresent(String.self, forKey: .model)
        let endpoint = try container.decodeIfPresent(String.self, forKey: .endpoint)
        let tools = try container.decodeIfPresent([String].self, forKey: .tools) ?? []
        let openAIAuthMode = try container.decodeIfPresent(OpenAICompatibleAuthMode.self, forKey: .openAIAuthMode) ?? .apiKey
        let codexProfile = try container.decodeIfPresent(String.self, forKey: .codexProfile)

        self.init(
            provider: provider,
            model: model,
            endpoint: endpoint,
            tools: tools,
            openAIAuthMode: openAIAuthMode,
            codexProfile: codexProfile
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(provider, forKey: .provider)
        try container.encode(model, forKey: .model)
        try container.encodeIfPresent(endpoint, forKey: .endpoint)
        try container.encode(Array(tools).sorted(), forKey: .tools)
        try container.encode(openAIAuthMode, forKey: .openAIAuthMode)
        try container.encodeIfPresent(codexProfile, forKey: .codexProfile)
    }

    nonisolated private static func normalizeTool(_ rawValue: String) -> String {
        rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    nonisolated private static func normalizeOptional(_ rawValue: String?) -> String? {
        guard let rawValue else { return nil }
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

enum TaskExecutionStatus: String, Codable, Equatable {
    case running
    case succeeded
    case failed
}

enum ExecutionCheckpointMode: String, Codable, Equatable {
    case assignedBatch
    case autoCycle
}

struct ExecutionCheckpoint: Equatable, Codable {
    var boardID: UUID
    var mode: ExecutionCheckpointMode
    var startedAt: Date
    var maxAutoCyclePasses: Int
    var autoCreateMissingDependencies: Bool
    var autoAssignBeforeRun: Bool

    init(
        boardID: UUID,
        mode: ExecutionCheckpointMode,
        startedAt: Date = Date(),
        maxAutoCyclePasses: Int = 1,
        autoCreateMissingDependencies: Bool = false,
        autoAssignBeforeRun: Bool = true
    ) {
        self.boardID = boardID
        self.mode = mode
        self.startedAt = startedAt
        self.maxAutoCyclePasses = max(1, maxAutoCyclePasses)
        self.autoCreateMissingDependencies = autoCreateMissingDependencies
        self.autoAssignBeforeRun = autoAssignBeforeRun
    }
}

enum RetryableExecutionErrorType: String, CaseIterable, Codable, Identifiable {
    case network
    case rateLimit
    case server

    var id: String { rawValue }
}

struct TaskExecutionApproval: Equatable, Codable {
    var approvedAt: Date
    var approvedBy: String

    init(approvedAt: Date = Date(), approvedBy: String = "Human") {
        self.approvedAt = approvedAt
        self.approvedBy = approvedBy.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "Human"
            : approvedBy.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct ExecutionApprovalPolicy: Equatable, Codable {
    var isEnabled: Bool
    var minimumStoryPoints: Int

    init(
        isEnabled: Bool = false,
        minimumStoryPoints: Int = 3
    ) {
        self.isEnabled = isEnabled
        self.minimumStoryPoints = max(1, minimumStoryPoints)
    }
}

struct ExecutionAutoRetryConfiguration: Equatable, Codable {
    var isEnabled: Bool
    var maxRetryCount: Int
    var backoffSeconds: Double
    var retryableErrorTypes: Set<RetryableExecutionErrorType>

    init(
        isEnabled: Bool = true,
        maxRetryCount: Int = 2,
        backoffSeconds: Double = 1.0,
        retryableErrorTypes: Set<RetryableExecutionErrorType> = Set(RetryableExecutionErrorType.allCases)
    ) {
        self.isEnabled = isEnabled
        self.maxRetryCount = max(0, maxRetryCount)
        self.backoffSeconds = max(0, backoffSeconds)
        self.retryableErrorTypes = retryableErrorTypes
    }
}

struct ExecutionQuotaPolicy: Equatable, Codable {
    var isEnabled: Bool
    var maxEstimatedTokens: Int
    var maxEstimatedCostUSD: Double
    var costPer1KTokensUSD: Double

    init(
        isEnabled: Bool = false,
        maxEstimatedTokens: Int = 12000,
        maxEstimatedCostUSD: Double = 0.60,
        costPer1KTokensUSD: Double = 0.05
    ) {
        self.isEnabled = isEnabled
        self.maxEstimatedTokens = max(1, maxEstimatedTokens)
        self.maxEstimatedCostUSD = max(0, maxEstimatedCostUSD)
        self.costPer1KTokensUSD = max(0.0001, costPer1KTokensUSD)
    }
}

struct ExecutionQuotaUsage: Equatable, Codable {
    var consumedRuns: Int
    var estimatedTokensUsed: Int
    var estimatedCostUSD: Double
    var lastUpdatedAt: Date?

    init(
        consumedRuns: Int = 0,
        estimatedTokensUsed: Int = 0,
        estimatedCostUSD: Double = 0,
        lastUpdatedAt: Date? = nil
    ) {
        self.consumedRuns = max(0, consumedRuns)
        self.estimatedTokensUsed = max(0, estimatedTokensUsed)
        self.estimatedCostUSD = max(0, estimatedCostUSD)
        self.lastUpdatedAt = lastUpdatedAt
    }
}

struct TaskTemplate: Identifiable, Equatable, Codable {
    let id: UUID
    var name: String
    var title: String
    var details: String
    var requiredSkills: [String]
    var storyPoints: Int
    let createdAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        title: String,
        details: String,
        requiredSkills: [String],
        storyPoints: Int,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        self.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        self.details = details.trimmingCharacters(in: .whitespacesAndNewlines)
        self.requiredSkills = Array(
            Set(
                requiredSkills
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                    .filter { !$0.isEmpty }
            )
        ).sorted()
        self.storyPoints = max(1, min(13, storyPoints))
        self.createdAt = createdAt
    }

    var requiredSkillsText: String {
        requiredSkills.joined(separator: ", ")
    }
}

struct TaskExecutionRecord: Equatable, Codable {
    var status: TaskExecutionStatus
    var runCount: Int
    var lastStartedAt: Date?
    var lastFinishedAt: Date?
    var lastOutputSummary: String?
    var lastError: String?
    var lastDebugOutput: String?
    var lastAgentID: UUID?

    init(
        status: TaskExecutionStatus,
        runCount: Int = 0,
        lastStartedAt: Date? = nil,
        lastFinishedAt: Date? = nil,
        lastOutputSummary: String? = nil,
        lastError: String? = nil,
        lastDebugOutput: String? = nil,
        lastAgentID: UUID? = nil
    ) {
        self.status = status
        self.runCount = max(0, runCount)
        self.lastStartedAt = lastStartedAt
        self.lastFinishedAt = lastFinishedAt
        self.lastOutputSummary = lastOutputSummary
        self.lastError = lastError
        self.lastDebugOutput = lastDebugOutput
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
