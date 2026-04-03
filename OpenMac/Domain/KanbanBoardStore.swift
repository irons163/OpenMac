import Foundation

struct KanbanBoardSnapshot: Codable, Equatable {
    var tasks: [WorkTask]
    var agents: [AgentProfile]
    var wipLimits: [KanbanStatus: Int]
    var boards: [KanbanBoardRecord]?
    var selectedBoardID: UUID?
    var taskTemplates: [TaskTemplate]?
    var executionAutoRetryConfiguration: ExecutionAutoRetryConfiguration?
    var executionCheckpoint: ExecutionCheckpoint?
    var executionApprovalPolicy: ExecutionApprovalPolicy?
    var taskExecutionApprovalsByTaskID: [UUID: TaskExecutionApproval]?
    var executionQuotaPolicy: ExecutionQuotaPolicy?
    var executionQuotaUsage: ExecutionQuotaUsage?
    var executionParallelizationPolicy: ExecutionParallelizationPolicy?
    var gitHubPRQualityGatePolicy: GitHubPRQualityGatePolicy?
    var dagExecutionPolicy: DAGExecutionPolicy?
    var executionQualitySafetyGatePolicy: ExecutionQualitySafetyGatePolicy?
    var executionRealArtifactVerificationPolicy: ExecutionRealArtifactVerificationPolicy?
    var mcpServerPolicy: MCPServerPolicy?
    var pmPlannerEngineMode: PMPlannerEngineMode?
    var pmPlanningPluginPolicy: PMPlanningPluginPolicy?

    init(
        tasks: [WorkTask],
        agents: [AgentProfile],
        wipLimits: [KanbanStatus: Int],
        boards: [KanbanBoardRecord]? = nil,
        selectedBoardID: UUID? = nil,
        taskTemplates: [TaskTemplate]? = nil,
        executionAutoRetryConfiguration: ExecutionAutoRetryConfiguration? = nil,
        executionCheckpoint: ExecutionCheckpoint? = nil,
        executionApprovalPolicy: ExecutionApprovalPolicy? = nil,
        taskExecutionApprovalsByTaskID: [UUID: TaskExecutionApproval]? = nil,
        executionQuotaPolicy: ExecutionQuotaPolicy? = nil,
        executionQuotaUsage: ExecutionQuotaUsage? = nil,
        executionParallelizationPolicy: ExecutionParallelizationPolicy? = nil,
        gitHubPRQualityGatePolicy: GitHubPRQualityGatePolicy? = nil,
        dagExecutionPolicy: DAGExecutionPolicy? = nil,
        executionQualitySafetyGatePolicy: ExecutionQualitySafetyGatePolicy? = nil,
        executionRealArtifactVerificationPolicy: ExecutionRealArtifactVerificationPolicy? = nil,
        mcpServerPolicy: MCPServerPolicy? = nil,
        pmPlannerEngineMode: PMPlannerEngineMode? = nil,
        pmPlanningPluginPolicy: PMPlanningPluginPolicy? = nil
    ) {
        self.tasks = tasks
        self.agents = agents
        self.wipLimits = wipLimits
        self.boards = boards
        self.selectedBoardID = selectedBoardID
        self.taskTemplates = taskTemplates
        self.executionAutoRetryConfiguration = executionAutoRetryConfiguration
        self.executionCheckpoint = executionCheckpoint
        self.executionApprovalPolicy = executionApprovalPolicy
        self.taskExecutionApprovalsByTaskID = taskExecutionApprovalsByTaskID
        self.executionQuotaPolicy = executionQuotaPolicy
        self.executionQuotaUsage = executionQuotaUsage
        self.executionParallelizationPolicy = executionParallelizationPolicy
        self.gitHubPRQualityGatePolicy = gitHubPRQualityGatePolicy
        self.dagExecutionPolicy = dagExecutionPolicy
        self.executionQualitySafetyGatePolicy = executionQualitySafetyGatePolicy
        self.executionRealArtifactVerificationPolicy = executionRealArtifactVerificationPolicy
        self.mcpServerPolicy = mcpServerPolicy
        self.pmPlannerEngineMode = pmPlannerEngineMode
        self.pmPlanningPluginPolicy = pmPlanningPluginPolicy
    }

    init(
        tasks: [WorkTask],
        agents: [AgentProfile],
        wipLimits: [KanbanStatus: Int]
    ) {
        self.init(
            tasks: tasks,
            agents: agents,
            wipLimits: wipLimits,
            boards: nil,
            selectedBoardID: nil,
            taskTemplates: nil,
            executionAutoRetryConfiguration: nil,
            executionCheckpoint: nil,
            executionApprovalPolicy: nil,
            taskExecutionApprovalsByTaskID: nil,
            executionQuotaPolicy: nil,
            executionQuotaUsage: nil,
            executionParallelizationPolicy: nil,
            gitHubPRQualityGatePolicy: nil,
            dagExecutionPolicy: nil,
            executionQualitySafetyGatePolicy: nil,
            executionRealArtifactVerificationPolicy: nil,
            mcpServerPolicy: nil,
            pmPlannerEngineMode: nil,
            pmPlanningPluginPolicy: nil
        )
    }
}

protocol KanbanBoardStore {
    func load() throws -> KanbanBoardSnapshot?
    func save(_ snapshot: KanbanBoardSnapshot) throws
}

struct FileKanbanBoardStore: KanbanBoardStore {
    let fileURL: URL

    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(fileURL: URL = FileKanbanBoardStore.defaultFileURL) {
        self.fileURL = fileURL

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .secondsSince1970
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        self.decoder = decoder
    }

    static var defaultFileURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return appSupport
            .appendingPathComponent("OpenMac", isDirectory: true)
            .appendingPathComponent("kanban-board.json")
    }

    func load() throws -> KanbanBoardSnapshot? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return nil
        }
        let data = try Data(contentsOf: fileURL)
        return try decoder.decode(KanbanBoardSnapshot.self, from: data)
    }

    func save(_ snapshot: KanbanBoardSnapshot) throws {
        let directoryURL = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let data = try encoder.encode(snapshot)
        try data.write(to: fileURL, options: .atomic)
    }
}
