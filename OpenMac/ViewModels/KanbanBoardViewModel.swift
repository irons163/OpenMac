import Combine
import Foundation

final class KanbanBoardViewModel: ObservableObject {
    typealias ExecutionDispatcher = (@escaping () -> Void) -> Void
    typealias GitCommandRunner = GitHubPRFlowUseCase.CommandRunner
    struct PMCreatedTaskDescriptor {
        let taskID: UUID
        let milestone: String
        let epic: String
    }

    struct PMExtensionHookWorkItem {
        let key: String
        let event: PMExtensionHookEvent
        let descriptor: PMExtensionCommandDescriptor
        let task: WorkTask?
        let extensionInputs: [String: String]
        let retryCount: Int
    }

    struct PMExtensionMutableStats {
        var pluginID: String
        var pluginName: String
        var totalRuns = 0
        var succeededRuns = 0
        var failedRuns = 0
        var runningCount = 0
        var totalDurationMS = 0
        var lastRunAt: Date?
        var lastError: String?
        var lastInputSummary = ""
        var lastOutputSummary = ""
    }

    struct ExecutionReportTaskEntry: Codable {
        let id: UUID
        let title: String
        let status: String
        let assignee: String
        let storyPoints: Int
        let runCount: Int
        let executionStatus: String?
        let lastStartedAt: Date?
        let lastFinishedAt: Date?
        let lastSummary: String?
        let lastError: String?
    }

    struct ExecutionReportDocument: Codable {
        let generatedAt: Date
        let boardID: UUID
        let boardName: String
        let totalTasks: Int
        let executedTasks: Int
        let succeededTasks: Int
        let failedTasks: Int
        let runningTasks: Int
        let notRunTasks: Int
        let tasks: [ExecutionReportTaskEntry]
    }

    @Published var boards: [KanbanBoardRecord]
    @Published var selectedBoardID: UUID
    @Published var tasks: [WorkTask]
    @Published var lastUnassignedTaskIDs: Set<UUID> = []
    @Published var lastAssignmentReasons: [UUID: String] = [:]
    @Published var lastBoardMessage: String? {
        didSet {
            if lastBoardMessage == nil {
                lastBoardMessageSeverity = nil
            } else {
                lastBoardMessageSeverity = .error
            }
        }
    }
    @Published var lastBoardMessageSeverity: BoardMessageSeverity?
    @Published var lastExecutionDebugLog: String?
    @Published var lastCodexLoginCommand: String?
    @Published var lastGitHubPRURL: String?
    @Published var lastGitHubPRLog: String?
    @Published var lastAutoCycleCreatedDependencyTaskCount = 0
    @Published var isBatchRunCancelRequested = false
    @Published var isAutoCycleCancelRequested = false
    @Published var wipLimits: [KanbanStatus: Int]
    @Published var agents: [AgentProfile]
    @Published var taskTemplates: [TaskTemplate]
    @Published var executionAutoRetryConfiguration: ExecutionAutoRetryConfiguration
    @Published var executionCheckpoint: ExecutionCheckpoint?
    @Published var executionApprovalPolicy: ExecutionApprovalPolicy
    @Published var taskExecutionApprovalsByTaskID: [UUID: TaskExecutionApproval]
    @Published var executionQuotaPolicy: ExecutionQuotaPolicy
    @Published var executionQuotaUsage: ExecutionQuotaUsage
    @Published var executionParallelizationPolicy: ExecutionParallelizationPolicy
    @Published var gitHubPRQualityGatePolicy: GitHubPRQualityGatePolicy
    @Published var dagExecutionPolicy: DAGExecutionPolicy
    @Published var executionQualitySafetyGatePolicy: ExecutionQualitySafetyGatePolicy
    @Published var executionRealArtifactVerificationDefaultPolicy: ExecutionRealArtifactVerificationPolicy
    @Published var selectedBoardUsesDefaultRealArtifactVerificationPolicy: Bool
    @Published var executionRealArtifactVerificationPolicy: ExecutionRealArtifactVerificationPolicy
    @Published var mcpServerPolicy: MCPServerPolicy
    @Published var pmPlannerEngineMode: PMPlannerEngineMode
    @Published var pmPlanningPluginPolicy: PMPlanningPluginPolicy
    @Published var pmExtensionActivityLog: [PMExtensionActivityLogEntry] = []
    @Published var pmExtensionObservability: [PMExtensionObservabilitySnapshot] = []
    @Published var pmExtensionLastAcceptanceReport: PMExtensionE2EAcceptanceReport?
    @Published var sharedAgentMemory: [SharedAgentMemoryEntry] = []
    @Published var pmBoardExtensionHookBindings: [PMBoardExtensionHookBinding] = []
    @Published var sharedAgentMemoryProviderMode: SharedAgentMemoryProviderMode
    @Published var sharedAgentMemoryPreferredProviderID: String?
    @Published var sharedAgentMemoryMutedProviderIDs: Set<String>
    @Published var agentExecutionEventsByAgentID: [UUID: [AgentExecutionEvent]] = [:]
    @Published var executionTimelineByTaskID: [UUID: [AgentExecutionEvent]] = [:]

    let assignmentEngine: AutoAssignmentEngine
    let projectPlanner: any ProjectPlanning
    let taskExecutor: any AgentTaskExecuting
    let projectsDirectoryPathProvider: () -> String
    let boardStore: KanbanBoardStore?
    let runOnBackground: ExecutionDispatcher
    let runOnMain: ExecutionDispatcher
    let gitCommandRunner: GitCommandRunner
    static let defaultBoardName = "Default Board"
    static let maxAgentExecutionEventsPerAgent = 120
    static let maxTaskTimelineEventsPerTask = 240
    static let maxExtensionActivityLogEntries = 200
    static let maxSharedAgentMemoryEntries = 160
    static let sharedAgentMemoryPromptLimit = 12
    static let sharedAgentMemoryPromptCharsLimit = 2800
    static let maxHookRetryCount = 2
    static let hookRetryBackoffBaseSeconds: Double = 1
    static let hookDedupWindowSeconds: Double = 6
    static let hookMaxConcurrentRuns = 2
    static let mcpRegistrySyncTTL: TimeInterval = 60 * 30
    var mcpReadinessCacheByServerName: [String: Bool] = [:]
    var pmExtensionStatsByPluginID: [String: PMExtensionMutableStats] = [:]
    var pmExtensionHookQueue: [PMExtensionHookWorkItem] = []
    var pmExtensionHookQueuedKeys: Set<String> = []
    var pmExtensionHookRunningKeys: Set<String> = []
    var pmExtensionHookDedupExpirations: [String: Date] = [:]
    var pmExtensionHookRunningCount = 0
    var pmExtensionInstallStack: Set<String> = []

    func message(_ key: String) -> String {
        L10n.string(key)
    }

    func message(_ key: String, _ arguments: CVarArg...) -> String {
        L10n.format(key, locale: nil, arguments: arguments)
    }

    nonisolated static func normalizedPlannedTicket(from ticket: PMPlannedTicket) -> PMPlannedTicket? {
        let normalized = PMPlannedTicket(
            title: ticket.title,
            details: ticket.details,
            requiredSkills: ticket.requiredSkills,
            storyPoints: ticket.storyPoints,
            epic: ticket.epic,
            milestone: ticket.milestone
        )
        guard !normalized.title.isEmpty else { return nil }
        return normalized
    }

    nonisolated static func planningMetadataAugmentedDetails(for ticket: PMPlannedTicket) -> String {
        let existingLines = ticket.details
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .filter { line in
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                return !trimmed.hasPrefix("milestone:") && !trimmed.hasPrefix("epic:")
            }

        var metadataLines: [String] = []
        let milestone = ticket.milestone.trimmingCharacters(in: .whitespacesAndNewlines)
        let epic = ticket.epic.trimmingCharacters(in: .whitespacesAndNewlines)
        if !milestone.isEmpty {
            metadataLines.append("Milestone: \(milestone)")
        }
        if !epic.isEmpty {
            metadataLines.append("Epic: \(epic)")
        }

        let body = existingLines
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !metadataLines.isEmpty else {
            return body
        }
        guard !body.isEmpty else {
            return metadataLines.joined(separator: "\n")
        }
        return metadataLines.joined(separator: "\n") + "\n" + body
    }

    nonisolated static func plannedTicketMilestoneCount(_ tickets: [PMPlannedTicket]) -> Int {
        Set(
            tickets.map { ticket in
                let milestone = ticket.milestone.trimmingCharacters(in: .whitespacesAndNewlines)
                return milestone.isEmpty ? "__unscheduled__" : milestone.lowercased()
            }
        ).count
    }

    nonisolated static func plannedTicketEpicCount(_ tickets: [PMPlannedTicket]) -> Int {
        Set(
            tickets
                .map { $0.epic.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                .filter { !$0.isEmpty }
        ).count
    }

    static func defaultTaskTemplates() -> [TaskTemplate] {
        [
            TaskTemplate(
                name: "SwiftUI Feature",
                title: "Build SwiftUI feature",
                details: """
                Implement the target UI flow and interaction states.
                Acceptance:
                - UI is responsive on common window sizes.
                - Empty/loading/error states are handled.
                - Includes basic accessibility checks.
                """,
                requiredSkills: ["swiftui", "ui"],
                storyPoints: 3
            ),
            TaskTemplate(
                name: "API Integration",
                title: "Integrate API endpoint",
                details: """
                Integrate backend API contract into the app workflow.
                Acceptance:
                - Request/response mapping is validated.
                - Failure paths and retries are handled.
                - Logs include actionable diagnostics.
                """,
                requiredSkills: ["api", "networking"],
                storyPoints: 5
            ),
            TaskTemplate(
                name: "Test Coverage",
                title: "Add regression coverage",
                details: """
                Expand automated coverage for the changed behavior.
                Acceptance:
                - Adds happy-path and failure-path tests.
                - Verifies edge cases found during implementation.
                - Keeps tests deterministic and fast.
                """,
                requiredSkills: ["testing", "tdd"],
                storyPoints: 2
            )
        ]
    }

    var totalTaskCount: Int { tasks.count }
    var todoTaskCount: Int { tasks.filter { $0.status == .todo }.count }
    var unassignedTodoTaskCount: Int { tasks.filter { $0.status == .todo && $0.assignedAgentID == nil }.count }
    var hasPendingManualTriage: Bool { !agents.isEmpty && unassignedTodoTaskCount > 0 }
    var doneTaskCount: Int { tasks.filter { $0.status == .done }.count }
    var overloadedAgentCount: Int { agents.filter { isAgentOverloaded($0.id) }.count }
    var boardHealthScore: Int {
        var penalty = 0
        penalty += min(30, unassignedTodoTaskCount * 10)
        penalty += min(30, overloadedAgentCount * 10)
        if wipPressurePercent(for: .inProgress) >= 100 { penalty += 10 }
        if wipPressurePercent(for: .review) >= 100 { penalty += 10 }
        if doneTaskCount > 0 { penalty += 5 }
        return max(0, 100 - penalty)
    }
    var boardHealthLabel: String {
        if boardHealthScore >= 85 { return message("Excellent") }
        if boardHealthScore >= 60 { return message("Watch") }
        return message("Critical")
    }
    var boardHealthBreakdownText: String {
        let penalties = boardHealthPenaltyItems()
        guard !penalties.isEmpty else { return message("No active penalties") }
        let totalPenalty = penalties.reduce(0) { partialResult, item in
            partialResult + item.points
        }
        let lines = penalties
            .map { message("%@: -%d", $0.label, $0.points) }
        return (lines + [
            message("Total Penalty: -%d", totalPenalty),
            message("Health Score: %d", boardHealthScore)
        ])
        .joined(separator: "\n")
    }
    var autoFixableHealthRecommendationCount: Int {
        healthRecommendations().filter { $0.action.isAutoFixable }.count
    }
    var hasAutoFixableHealthRecommendations: Bool {
        autoFixableHealthRecommendationCount > 0
    }
    var selectedBoardName: String {
        boards.first(where: { $0.id == selectedBoardID })?.name ?? Self.defaultBoardName
    }
    var hasExecutionCheckpointForSelectedBoard: Bool {
        ExecutionCheckpointUseCase.resumeAction(
            for: executionCheckpoint,
            selectedBoardID: selectedBoardID
        ) != nil
    }
    var pendingApprovalTaskCount: Int {
        tasks.filter { requiresHumanApproval(for: $0.id) && !isTaskApprovedForExecution($0.id) }.count
    }
    var selectedBoardDependencyInsights: DependencyGraphInsights {
        DependencyGraphInsightsUseCase.build(tasks: tasks)
    }

    init(
        tasks: [WorkTask],
        agents: [AgentProfile],
        wipLimits: [KanbanStatus: Int] = [.inProgress: 3, .review: 2],
        taskTemplates: [TaskTemplate]? = nil,
        executionAutoRetryConfiguration: ExecutionAutoRetryConfiguration = .init(),
        executionCheckpoint: ExecutionCheckpoint? = nil,
        executionApprovalPolicy: ExecutionApprovalPolicy = .init(),
        taskExecutionApprovalsByTaskID: [UUID: TaskExecutionApproval] = [:],
        executionQuotaPolicy: ExecutionQuotaPolicy = .init(),
        executionQuotaUsage: ExecutionQuotaUsage = .init(),
        executionParallelizationPolicy: ExecutionParallelizationPolicy = .init(),
        gitHubPRQualityGatePolicy: GitHubPRQualityGatePolicy = .init(),
        dagExecutionPolicy: DAGExecutionPolicy = .init(),
        executionQualitySafetyGatePolicy: ExecutionQualitySafetyGatePolicy = .init(),
        executionRealArtifactVerificationPolicy: ExecutionRealArtifactVerificationPolicy = .init(),
        mcpServerPolicy: MCPServerPolicy = .init(),
        pmPlannerEngineMode: PMPlannerEngineMode = .builtIn,
        pmPlanningPluginPolicy: PMPlanningPluginPolicy = .init(),
        sharedAgentMemory: [SharedAgentMemoryEntry] = [],
        pmBoardExtensionHookBindings: [PMBoardExtensionHookBinding] = [],
        sharedAgentMemoryProviderMode: SharedAgentMemoryProviderMode = .coreOnly,
        sharedAgentMemoryPreferredProviderID: String? = nil,
        sharedAgentMemoryMutedProviderIDs: Set<String> = [],
        projectsDirectoryPathProvider: @escaping () -> String = {
            CodexProjectsDirectorySettings.resolvedProjectsDirectoryPath()
        },
        assignmentEngine: AutoAssignmentEngine = AutoAssignmentEngine(),
        projectPlanner: any ProjectPlanning = ExtensibleProjectPlanner(),
        taskExecutor: any AgentTaskExecuting = DefaultAgentTaskExecutor(),
        boardStore: KanbanBoardStore? = nil,
        gitCommandRunner: @escaping GitCommandRunner = GitHubPRFlowUseCase.runSystemCommand,
        runOnBackground: @escaping ExecutionDispatcher = { work in
            DispatchQueue.global(qos: .userInitiated).async(execute: work)
        },
        runOnMain: @escaping ExecutionDispatcher = { work in
            DispatchQueue.main.async(execute: work)
        }
    ) {
        let normalizedLimits = wipLimits.reduce(into: [:]) { partialResult, pair in
            partialResult[pair.key] = max(1, pair.value)
        }
        let resolvedRealArtifactPolicy = executionRealArtifactVerificationPolicy
        let initialBoard = KanbanBoardRecord(
            name: Self.defaultBoardName,
            tasks: tasks,
            agents: agents,
            wipLimits: normalizedLimits,
            executionRealArtifactVerificationPolicy: nil,
            sharedAgentMemory: sharedAgentMemory,
            pmExtensionHookBindings: Self.normalizedBoardExtensionHookBindings(pmBoardExtensionHookBindings)
        )
        self.boards = [initialBoard]
        self.selectedBoardID = initialBoard.id
        self.tasks = tasks
        self.agents = agents
        self.wipLimits = normalizedLimits
        self.taskTemplates = taskTemplates ?? Self.defaultTaskTemplates()
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
        self.executionRealArtifactVerificationDefaultPolicy = resolvedRealArtifactPolicy
        self.selectedBoardUsesDefaultRealArtifactVerificationPolicy = true
        self.executionRealArtifactVerificationPolicy = resolvedRealArtifactPolicy
        self.mcpServerPolicy = mcpServerPolicy
        self.pmPlannerEngineMode = pmPlannerEngineMode
        self.pmPlanningPluginPolicy = pmPlanningPluginPolicy
        self.sharedAgentMemory = sharedAgentMemory
        self.pmBoardExtensionHookBindings = Self.normalizedBoardExtensionHookBindings(pmBoardExtensionHookBindings)
        self.sharedAgentMemoryProviderMode = sharedAgentMemoryProviderMode
        self.sharedAgentMemoryPreferredProviderID = Self.normalizedProviderDescriptorID(sharedAgentMemoryPreferredProviderID)
        self.sharedAgentMemoryMutedProviderIDs = Set(sharedAgentMemoryMutedProviderIDs.compactMap(Self.normalizedProviderDescriptorID))
        self.projectsDirectoryPathProvider = projectsDirectoryPathProvider
        self.assignmentEngine = assignmentEngine
        self.projectPlanner = projectPlanner
        self.taskExecutor = taskExecutor
        self.boardStore = boardStore
        self.gitCommandRunner = gitCommandRunner
        self.runOnBackground = runOnBackground
        self.runOnMain = runOnMain
        if syncSystemRealArtifactVerificationBoardHookBinding() {
            syncCurrentBoardRecord()
        }
        markRunningExecutionsAsInterruptedIfNeeded()
    }

    init(
        boards: [KanbanBoardRecord],
        selectedBoardID: UUID,
        taskTemplates: [TaskTemplate]? = nil,
        executionAutoRetryConfiguration: ExecutionAutoRetryConfiguration = .init(),
        executionCheckpoint: ExecutionCheckpoint? = nil,
        executionApprovalPolicy: ExecutionApprovalPolicy = .init(),
        taskExecutionApprovalsByTaskID: [UUID: TaskExecutionApproval] = [:],
        executionQuotaPolicy: ExecutionQuotaPolicy = .init(),
        executionQuotaUsage: ExecutionQuotaUsage = .init(),
        executionParallelizationPolicy: ExecutionParallelizationPolicy = .init(),
        gitHubPRQualityGatePolicy: GitHubPRQualityGatePolicy = .init(),
        dagExecutionPolicy: DAGExecutionPolicy = .init(),
        executionQualitySafetyGatePolicy: ExecutionQualitySafetyGatePolicy = .init(),
        executionRealArtifactVerificationPolicy: ExecutionRealArtifactVerificationPolicy = .init(),
        mcpServerPolicy: MCPServerPolicy = .init(),
        pmPlannerEngineMode: PMPlannerEngineMode = .builtIn,
        pmPlanningPluginPolicy: PMPlanningPluginPolicy = .init(),
        sharedAgentMemoryProviderMode: SharedAgentMemoryProviderMode = .coreOnly,
        sharedAgentMemoryPreferredProviderID: String? = nil,
        sharedAgentMemoryMutedProviderIDs: Set<String> = [],
        projectsDirectoryPathProvider: @escaping () -> String = {
            CodexProjectsDirectorySettings.resolvedProjectsDirectoryPath()
        },
        assignmentEngine: AutoAssignmentEngine = AutoAssignmentEngine(),
        projectPlanner: any ProjectPlanning = ExtensibleProjectPlanner(),
        taskExecutor: any AgentTaskExecuting = DefaultAgentTaskExecutor(),
        boardStore: KanbanBoardStore? = nil,
        gitCommandRunner: @escaping GitCommandRunner = GitHubPRFlowUseCase.runSystemCommand,
        runOnBackground: @escaping ExecutionDispatcher = { work in
            DispatchQueue.global(qos: .userInitiated).async(execute: work)
        },
        runOnMain: @escaping ExecutionDispatcher = { work in
            DispatchQueue.main.async(execute: work)
        }
    ) {
        let resolvedBoard: KanbanBoardRecord
        if let selected = boards.first(where: { $0.id == selectedBoardID }) {
            resolvedBoard = selected
        } else if let first = boards.first {
            resolvedBoard = first
        } else {
            resolvedBoard = KanbanBoardRecord(
                name: Self.defaultBoardName,
                executionRealArtifactVerificationPolicy: nil
            )
        }

        let resolvedDefaultRealArtifactPolicy = executionRealArtifactVerificationPolicy
        let selectedBoardUsesDefaultRealArtifactVerificationPolicy =
            resolvedBoard.executionRealArtifactVerificationPolicy == nil
        let resolvedSelectedBoardRealArtifactPolicy =
            resolvedBoard.executionRealArtifactVerificationPolicy ?? resolvedDefaultRealArtifactPolicy

        self.boards = boards.isEmpty ? [resolvedBoard] : boards
        self.selectedBoardID = resolvedBoard.id
        self.tasks = resolvedBoard.tasks
        self.agents = resolvedBoard.agents
        self.wipLimits = resolvedBoard.wipLimits
        self.taskTemplates = taskTemplates ?? Self.defaultTaskTemplates()
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
        self.executionRealArtifactVerificationDefaultPolicy = resolvedDefaultRealArtifactPolicy
        self.selectedBoardUsesDefaultRealArtifactVerificationPolicy = selectedBoardUsesDefaultRealArtifactVerificationPolicy
        self.executionRealArtifactVerificationPolicy = resolvedSelectedBoardRealArtifactPolicy
        self.mcpServerPolicy = mcpServerPolicy
        self.pmPlannerEngineMode = pmPlannerEngineMode
        self.pmPlanningPluginPolicy = pmPlanningPluginPolicy
        self.sharedAgentMemory = resolvedBoard.sharedAgentMemory ?? []
        self.pmBoardExtensionHookBindings = Self.normalizedBoardExtensionHookBindings(
            resolvedBoard.pmExtensionHookBindings ?? []
        )
        self.sharedAgentMemoryProviderMode = sharedAgentMemoryProviderMode
        self.sharedAgentMemoryPreferredProviderID = Self.normalizedProviderDescriptorID(sharedAgentMemoryPreferredProviderID)
        self.sharedAgentMemoryMutedProviderIDs = Set(sharedAgentMemoryMutedProviderIDs.compactMap(Self.normalizedProviderDescriptorID))
        self.projectsDirectoryPathProvider = projectsDirectoryPathProvider
        self.assignmentEngine = assignmentEngine
        self.projectPlanner = projectPlanner
        self.taskExecutor = taskExecutor
        self.boardStore = boardStore
        self.gitCommandRunner = gitCommandRunner
        self.runOnBackground = runOnBackground
        self.runOnMain = runOnMain
        if syncSystemRealArtifactVerificationBoardHookBinding() {
            syncCurrentBoardRecord()
        }
        markRunningExecutionsAsInterruptedIfNeeded()
    }

}
