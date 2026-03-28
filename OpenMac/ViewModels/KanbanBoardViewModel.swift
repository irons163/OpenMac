import Combine
import Foundation

enum TaskAssigneeFilter: Equatable {
    case all
    case unassigned
    case assigned(UUID)
}

enum BoardHealthAction: Equatable {
    case autoAssignUnassignedTodo
    case openManualTriage
    case openNewAgent
    case rebalanceTodoLoad
    case increaseWIPLimit(KanbanStatus)
    case archiveDone

    var isAutoFixable: Bool {
        switch self {
        case .openManualTriage, .openNewAgent:
            return false
        case .autoAssignUnassignedTodo, .rebalanceTodoLoad, .increaseWIPLimit, .archiveDone:
            return true
        }
    }
}

enum BoardMessageSeverity: String, Equatable {
    case info
    case warning
    case error
}

enum WorkspaceImportStrategy: Equatable {
    case replace
    case merge
}

struct WorkspaceImportPreview: Equatable {
    let boardCount: Int
    let taskCount: Int
    let agentCount: Int
}

struct BoardHealthRecommendation: Identifiable, Equatable {
    let action: BoardHealthAction
    let title: String
    let detail: String

    var id: String {
        switch action {
        case .autoAssignUnassignedTodo:
            return "auto-assign-unassigned-todo"
        case .openManualTriage:
            return "open-manual-triage"
        case .openNewAgent:
            return "open-new-agent"
        case .rebalanceTodoLoad:
            return "rebalance-todo-load"
        case let .increaseWIPLimit(status):
            return "increase-wip-\(status.rawValue)"
        case .archiveDone:
            return "archive-done"
        }
    }
}

struct GlobalTaskSearchResult: Identifiable, Equatable {
    let taskID: UUID
    let taskTitle: String
    let taskDetails: String
    let status: KanbanStatus
    let boardID: UUID
    let boardName: String
    let assigneeName: String

    var id: String {
        "\(boardID.uuidString)-\(taskID.uuidString)"
    }
}

enum AgentTaskExecutionOutcome: Equatable {
    case success(summary: String)
    case failure(message: String)
}

protocol AgentTaskExecuting {
    func execute(task: WorkTask, agent: AgentProfile) -> AgentTaskExecutionOutcome
}

struct DefaultAgentTaskExecutor: AgentTaskExecuting {
    static let debugLogDelimiter = "\n\n--- debug ---\n"

    struct CodexBridgeRequest: Equatable {
        let prompt: String
        let model: String
        let profile: String?
    }

    var environmentProvider: () -> [String: String] = { ProcessInfo.processInfo.environment }
    var urlSession: URLSession = .shared
    var timeoutSeconds: TimeInterval = 30
    var codexBridgePreflight: () throws -> Void = {
        try Self.defaultCodexBridgePreflight()
    }
    var codexBridgeRunner: (CodexBridgeRequest) throws -> String = { request in
        try Self.defaultCodexBridgeRunner(request: request)
    }

    init(
        environmentProvider: @escaping () -> [String: String] = { ProcessInfo.processInfo.environment },
        urlSession: URLSession = .shared,
        timeoutSeconds: TimeInterval = 30,
        codexBridgePreflight: @escaping () throws -> Void = {
            try Self.defaultCodexBridgePreflight()
        },
        codexBridgeRunner: @escaping (CodexBridgeRequest) throws -> String = { request in
            try Self.defaultCodexBridgeRunner(request: request)
        }
    ) {
        self.environmentProvider = environmentProvider
        self.urlSession = urlSession
        self.timeoutSeconds = timeoutSeconds
        self.codexBridgePreflight = codexBridgePreflight
        self.codexBridgeRunner = codexBridgeRunner
    }

    init(
        environmentProvider: @escaping () -> [String: String],
        urlSession: URLSession,
        timeoutSeconds: TimeInterval
    ) {
        self.init(
            environmentProvider: environmentProvider,
            urlSession: urlSession,
            timeoutSeconds: timeoutSeconds,
            codexBridgePreflight: {
                try Self.defaultCodexBridgePreflight()
            },
            codexBridgeRunner: { request in
                try Self.defaultCodexBridgeRunner(request: request)
            }
        )
    }

    func execute(task: WorkTask, agent: AgentProfile) -> AgentTaskExecutionOutcome {
        let runtimeProfile = agent.runtimeProfile ?? AgentRuntimeProfile(provider: .localMock)
        let provider = runtimeProfile.provider
        switch provider {
        case .localMock:
            let summary = "Mock run completed by \(agent.name) for \"\(task.title)\""
            return .success(summary: summary)
        case .openAICompatible:
            return runOpenAICompatible(task: task, agent: agent, runtimeProfile: runtimeProfile)
        }
    }

    private func runOpenAICompatible(
        task: WorkTask,
        agent: AgentProfile,
        runtimeProfile: AgentRuntimeProfile
    ) -> AgentTaskExecutionOutcome {
        switch runtimeProfile.openAIAuthMode {
        case .apiKey:
            return runOpenAICompatibleWithAPIKey(task: task, agent: agent, runtimeProfile: runtimeProfile)
        case .codexBridge:
            return runOpenAICompatibleWithCodexBridge(task: task, agent: agent, runtimeProfile: runtimeProfile)
        }
    }

    private func runOpenAICompatibleWithAPIKey(
        task: WorkTask,
        agent: AgentProfile,
        runtimeProfile: AgentRuntimeProfile
    ) -> AgentTaskExecutionOutcome {
        let environment = environmentProvider()
        let apiKey = resolvedAPIKey(from: environment)
        guard let apiKey else {
            return .failure(message: "Missing OPENAI_API_KEY for OpenAI-compatible runtime")
        }

        let endpoint = resolvedEndpoint(
            configuredEndpoint: runtimeProfile.endpoint,
            environment: environment
        )
        guard let url = URL(string: endpoint) else {
            return .failure(message: "Invalid OpenAI-compatible endpoint")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = timeoutSeconds
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let payload = ChatCompletionRequest(
            model: runtimeProfile.model,
            messages: buildMessages(task: task, agent: agent)
        )

        do {
            request.httpBody = try JSONEncoder().encode(payload)
            let response = try send(request: request)
            let summary = response.choices.first?.message.content.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let summary, !summary.isEmpty else {
                return .failure(message: "OpenAI-compatible runtime returned empty output")
            }
            return .success(summary: summary)
        } catch {
            return .failure(message: "OpenAI-compatible run failed: \(error.localizedDescription)")
        }
    }

    private func runOpenAICompatibleWithCodexBridge(
        task: WorkTask,
        agent: AgentProfile,
        runtimeProfile: AgentRuntimeProfile
    ) -> AgentTaskExecutionOutcome {
        let prompt = buildCodexBridgePrompt(task: task, agent: agent)
        let request = CodexBridgeRequest(
            prompt: prompt,
            model: runtimeProfile.model,
            profile: runtimeProfile.codexProfile
        )
        let trimmedModel = runtimeProfile.model.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            try codexBridgePreflight()
            let summary = try codexBridgeRunner(request).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !summary.isEmpty else {
                return .failure(message: "Codex Bridge returned empty output")
            }
            return .success(summary: summary)
        } catch {
            let initialRawFailure = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)

            // ChatGPT account login with Codex may reject some API models (for example gpt-4.1-mini).
            // Retry once without --model so Codex profile default can be used automatically.
            if !trimmedModel.isEmpty,
               Self.isCodexChatGPTModelUnsupported(initialRawFailure) {
                let fallbackRequest = CodexBridgeRequest(
                    prompt: prompt,
                    model: "",
                    profile: runtimeProfile.codexProfile
                )
                do {
                    let fallbackSummary = try codexBridgeRunner(fallbackRequest)
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !fallbackSummary.isEmpty else {
                        return .failure(message: "Codex Bridge returned empty output")
                    }
                    return .success(summary: fallbackSummary)
                } catch {
                    let fallbackRawFailure = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
                    let rawFailure = """
                    Initial run rejected configured model "\(trimmedModel)".
                    \(initialRawFailure)

                    Fallback run without explicit model failed.
                    \(fallbackRawFailure)
                    """
                    return codexBridgeFailureOutcome(from: rawFailure)
                }
            }

            return codexBridgeFailureOutcome(from: initialRawFailure)
        }
    }

    private func codexBridgeFailureOutcome(from rawFailure: String) -> AgentTaskExecutionOutcome {
        let summary = Self.summarizeCodexBridgeFailure(rawFailure)
        if rawFailure.isEmpty || summary == rawFailure {
            return .failure(message: "Codex Bridge run failed: \(summary)")
        }
        return .failure(
            message: "Codex Bridge run failed: \(summary)\(Self.debugLogDelimiter)\(rawFailure)"
        )
    }

    private static func isCodexChatGPTModelUnsupported(_ rawFailure: String) -> Bool {
        let normalized = rawFailure.lowercased()
        return normalized.contains("model is not supported when using codex with a chatgpt account")
    }

    private static func summarizeCodexBridgeFailure(_ rawFailure: String) -> String {
        let trimmed = rawFailure.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return "Unknown Codex Bridge error"
        }

        let normalized = trimmed.lowercased()
        if isCodexChatGPTModelUnsupported(trimmed) {
            return "Configured model is not supported for Codex Bridge with ChatGPT login. Leave model blank to use Codex default, or switch to a Codex-supported model."
        }
        if normalized.contains("401 unauthorized") || normalized.contains("missing bearer or basic authentication") {
            let loginCommand = codexLoginCommandForCurrentProfile()
            return "Codex Bridge authentication missing. Run this once in Terminal: \(loginCommand)"
        }
        if normalized.contains("operation not permitted") {
            let loginCommand = codexLoginCommandForCurrentProfile()
            return "Permission denied while accessing Codex profile. Run this once in Terminal with the app container profile: \(loginCommand)"
        }
        if normalized.contains("failed to connect to websocket"),
           normalized.contains("lookup address information") || normalized.contains("nodename nor servname provided") {
            return "Network/DNS lookup failed while Codex Bridge contacted OpenAI. Check internet, DNS/proxy settings, and outgoing network permission."
        }
        if normalized.contains("failed to connect to websocket") {
            return "Codex Bridge could not connect to OpenAI. Check internet/proxy settings and retry."
        }
        if normalized.contains("codex login") || normalized.contains("not logged in") {
            let loginCommand = codexLoginCommandForCurrentProfile()
            return "Codex Bridge requires login. Run this once in Terminal: \(loginCommand)"
        }
        if normalized.contains("no such file or directory"), normalized.contains("codex") {
            return "Codex CLI not found. Install Codex CLI or set CODEX_CLI_PATH."
        }

        let candidateLine = trimmed
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { line in
                let lowered = line.lowercased()
                guard !line.isEmpty else { return false }
                if lowered.hasPrefix("openai codex v") { return false }
                if lowered == "-" || lowered.hasPrefix("------") { return false }
                if lowered.hasPrefix("workdir:") || lowered.hasPrefix("model:") || lowered.hasPrefix("provider:") {
                    return false
                }
                if lowered.hasPrefix("approval:") || lowered.hasPrefix("sandbox:") || lowered.hasPrefix("reasoning") {
                    return false
                }
                if lowered.hasPrefix("session id:") || lowered == "user" { return false }
                return true
            }

        if let candidateLine, !candidateLine.isEmpty {
            return candidateLine.count > 220
                ? "\(candidateLine.prefix(220))..."
                : candidateLine
        }

        return trimmed.count > 220
            ? "\(trimmed.prefix(220))..."
            : trimmed
    }

    private func resolvedAPIKey(from environment: [String: String]) -> String? {
        let keyCandidates = ["OPENAI_API_KEY", "OPENAI_COMPAT_API_KEY"]
        for key in keyCandidates {
            if let value = environment[key]?.trimmingCharacters(in: .whitespacesAndNewlines),
               !value.isEmpty {
                return value
            }
        }
        return nil
    }

    private func resolvedEndpoint(configuredEndpoint: String?, environment: [String: String]) -> String {
        let configured = configuredEndpoint?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !configured.isEmpty {
            if configured.contains("/chat/completions") {
                return configured
            }
            return configured.hasSuffix("/")
                ? "\(configured)v1/chat/completions"
                : "\(configured)/v1/chat/completions"
        }

        let baseFromEnv = environment["OPENAI_BASE_URL"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !baseFromEnv.isEmpty {
            if baseFromEnv.contains("/chat/completions") {
                return baseFromEnv
            }
            return baseFromEnv.hasSuffix("/")
                ? "\(baseFromEnv)v1/chat/completions"
                : "\(baseFromEnv)/v1/chat/completions"
        }

        return "https://api.openai.com/v1/chat/completions"
    }

    private func buildMessages(task: WorkTask, agent: AgentProfile) -> [ChatMessage] {
        let sortedSkills = task.requiredSkills.sorted().joined(separator: ", ")
        let skillsLine = sortedSkills.isEmpty ? "none" : sortedSkills
        let userPrompt = """
        Agent: \(agent.name)
        Task title: \(task.title)
        Task details: \(task.details)
        Required skills: \(skillsLine)
        Story points: \(task.storyPoints)

        Provide a concise execution summary and key outcomes.
        """
        return [
            ChatMessage(role: "system", content: "You are an autonomous software execution agent. Respond with concise plain text."),
            ChatMessage(role: "user", content: userPrompt)
        ]
    }

    private func buildCodexBridgePrompt(task: WorkTask, agent: AgentProfile) -> String {
        let sortedSkills = task.requiredSkills.sorted().joined(separator: ", ")
        let skillsLine = sortedSkills.isEmpty ? "none" : sortedSkills
        return """
        You are supporting an assigned AI agent in a kanban execution system.
        Agent: \(agent.name)
        Task title: \(task.title)
        Task details: \(task.details)
        Required skills: \(skillsLine)
        Story points: \(task.storyPoints)

        Return a concise plain-text execution summary and key outcomes.
        """
    }

    private func send(request: URLRequest) throws -> ChatCompletionResponse {
        let semaphore = DispatchSemaphore(value: 0)
        var responseData: Data?
        var urlResponse: URLResponse?
        var responseError: Error?

        let task = urlSession.dataTask(with: request) { data, response, error in
            responseData = data
            urlResponse = response
            responseError = error
            semaphore.signal()
        }
        task.resume()

        if semaphore.wait(timeout: .now() + timeoutSeconds) == .timedOut {
            task.cancel()
            throw ExecutorError.timeout
        }

        if let responseError {
            throw responseError
        }

        guard let httpResponse = urlResponse as? HTTPURLResponse else {
            throw ExecutorError.invalidResponse
        }
        guard let responseData else {
            throw ExecutorError.emptyResponse
        }

        guard (200 ... 299).contains(httpResponse.statusCode) else {
            let responseBody = String(data: responseData, encoding: .utf8) ?? "status \(httpResponse.statusCode)"
            throw ExecutorError.serverError(responseBody)
        }

        return try JSONDecoder().decode(ChatCompletionResponse.self, from: responseData)
    }

    private enum ExecutorError: LocalizedError {
        case timeout
        case invalidResponse
        case emptyResponse
        case serverError(String)
        case codexBridgeFailed(String)

        var errorDescription: String? {
            switch self {
            case .timeout:
                return "Request timed out"
            case .invalidResponse:
                return "Invalid response"
            case .emptyResponse:
                return "Empty response"
            case let .serverError(message):
                return message
            case let .codexBridgeFailed(message):
                return message
            }
        }
    }

    private struct ChatCompletionRequest: Encodable {
        let model: String
        let messages: [ChatMessage]
    }

    private struct ChatMessage: Codable {
        let role: String
        let content: String
    }

    private struct ChatCompletionResponse: Decodable {
        let choices: [Choice]

        struct Choice: Decodable {
            let message: ChatMessage
        }
    }

    private static func defaultCodexBridgeRunner(request: CodexBridgeRequest) throws -> String {
        guard let codexExecutable = resolvedCodexExecutableURL() else {
            throw ExecutorError.codexBridgeFailed(
                "Codex CLI not found. Install Codex CLI (or Codex app), then retry. You can also switch OpenAI Auth to API Key."
            )
        }

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("openmac-codex-bridge-\(UUID().uuidString).txt")
        defer {
            try? FileManager.default.removeItem(at: outputURL)
        }

        var arguments = [
            "exec",
            "--skip-git-repo-check",
            "--sandbox", "read-only",
            "--output-last-message", outputURL.path
        ]
        if !request.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            arguments.append(contentsOf: ["--model", request.model])
        }
        if let profile = request.profile?.trimmingCharacters(in: .whitespacesAndNewlines), !profile.isEmpty {
            arguments.append(contentsOf: ["--profile", profile])
        }
        arguments.append(request.prompt)

        let process = Process()
        process.executableURL = codexExecutable
        process.arguments = arguments
        process.environment = codexBridgeProcessEnvironment()

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = outputPipe

        try process.run()
        process.waitUntilExit()

        let rawOutputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let rawOutput = String(data: rawOutputData, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        guard process.terminationStatus == 0 else {
            let message = rawOutput.isEmpty ? "codex exited with code \(process.terminationStatus)" : rawOutput
            throw ExecutorError.codexBridgeFailed(message)
        }

        if let message = try? String(contentsOf: outputURL, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines),
           !message.isEmpty {
            return message
        }

        if !rawOutput.isEmpty {
            return rawOutput
        }

        throw ExecutorError.emptyResponse
    }

    private static func defaultCodexBridgePreflight() throws {
        guard resolvedCodexExecutableURL() != nil else {
            throw ExecutorError.codexBridgeFailed(
                "Codex CLI not found. Install Codex CLI (or Codex app), then retry. You can also switch OpenAI Auth to API Key."
            )
        }

        let loginStatus = try runCodex(arguments: ["login", "status"])
        let normalized = loginStatus.output.lowercased()
        guard loginStatus.code == 0, normalized.contains("logged in") else {
            let loginCommand = codexLoginCommandForCurrentProfile()
            throw ExecutorError.codexBridgeFailed(
                "Codex Bridge profile is not logged in. Run this once in Terminal: \(loginCommand)"
            )
        }
    }

    private static func runCodex(arguments: [String]) throws -> (code: Int32, output: String) {
        guard let executableURL = resolvedCodexExecutableURL() else {
            throw ExecutorError.codexBridgeFailed(
                "Codex CLI not found. Install Codex CLI (or Codex app), then retry. You can also switch OpenAI Auth to API Key."
            )
        }

        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        process.environment = codexBridgeProcessEnvironment()

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = outputPipe

        try process.run()
        process.waitUntilExit()

        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: outputData, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return (process.terminationStatus, output)
    }

    private static func resolvedCodexExecutableURL() -> URL? {
        let fileManager = FileManager.default

        if let explicitPath = ProcessInfo.processInfo.environment["CODEX_CLI_PATH"]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !explicitPath.isEmpty,
           fileManager.isExecutableFile(atPath: explicitPath) {
            return URL(fileURLWithPath: explicitPath)
        }

        let pathValue = ProcessInfo.processInfo.environment["PATH"] ?? ""
        let pathCandidates = pathValue
            .split(separator: ":")
            .map { String($0) }
            .filter { !$0.isEmpty }
            .map { directory in
                (directory as NSString).appendingPathComponent("codex")
            }

        let fallbackCandidates = [
            "/Applications/Codex.app/Contents/Resources/codex",
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex",
            (NSHomeDirectory() as NSString).appendingPathComponent(".local/bin/codex")
        ]

        for candidate in pathCandidates + fallbackCandidates where fileManager.isExecutableFile(atPath: candidate) {
            return URL(fileURLWithPath: candidate)
        }

        return nil
    }


    private static func codexBridgeProcessEnvironment() -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        if let codexHome = environment["CODEX_HOME"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           codexHome.isEmpty {
            environment["CODEX_HOME"] = nil
        }
        return environment
    }

    private static func codexLoginCommandForCurrentProfile() -> String {
        let home = ProcessInfo.processInfo.environment["HOME"] ?? NSHomeDirectory()
        let codexHome = ProcessInfo.processInfo.environment["CODEX_HOME"] ?? "\(home)/.codex"
        return "HOME=\"\(home)\" CODEX_HOME=\"\(codexHome)\" codex login --device-auth"
    }
}

final class KanbanBoardViewModel: ObservableObject {
    @Published private(set) var boards: [KanbanBoardRecord]
    @Published private(set) var selectedBoardID: UUID
    @Published private(set) var tasks: [WorkTask]
    @Published private(set) var lastUnassignedTaskIDs: Set<UUID> = []
    @Published private(set) var lastAssignmentReasons: [UUID: String] = [:]
    @Published private(set) var lastBoardMessage: String? {
        didSet {
            if lastBoardMessage == nil {
                lastBoardMessageSeverity = nil
            } else {
                lastBoardMessageSeverity = .error
            }
        }
    }
    @Published private(set) var lastBoardMessageSeverity: BoardMessageSeverity?
    @Published private(set) var lastExecutionDebugLog: String?
    @Published private(set) var lastCodexLoginCommand: String?
    @Published private(set) var wipLimits: [KanbanStatus: Int]
    @Published var agents: [AgentProfile]

    private let assignmentEngine: AutoAssignmentEngine
    private let taskExecutor: any AgentTaskExecuting
    private let boardStore: KanbanBoardStore?
    private static let defaultBoardName = "Default Board"

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
        if boardHealthScore >= 85 { return "Excellent" }
        if boardHealthScore >= 60 { return "Watch" }
        return "Critical"
    }
    var boardHealthBreakdownText: String {
        let penalties = boardHealthPenaltyItems()
        guard !penalties.isEmpty else { return "No active penalties" }
        let totalPenalty = penalties.reduce(0) { partialResult, item in
            partialResult + item.points
        }
        let lines = penalties
            .map { "\($0.label): -\($0.points)" }
        return (lines + [
            "Total Penalty: -\(totalPenalty)",
            "Health Score: \(boardHealthScore)"
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

    init(
        tasks: [WorkTask],
        agents: [AgentProfile],
        wipLimits: [KanbanStatus: Int] = [.inProgress: 3, .review: 2],
        assignmentEngine: AutoAssignmentEngine = AutoAssignmentEngine(),
        taskExecutor: any AgentTaskExecuting = DefaultAgentTaskExecutor(),
        boardStore: KanbanBoardStore? = nil
    ) {
        let normalizedLimits = wipLimits.reduce(into: [:]) { partialResult, pair in
            partialResult[pair.key] = max(1, pair.value)
        }
        let initialBoard = KanbanBoardRecord(
            name: Self.defaultBoardName,
            tasks: tasks,
            agents: agents,
            wipLimits: normalizedLimits
        )
        self.boards = [initialBoard]
        self.selectedBoardID = initialBoard.id
        self.tasks = tasks
        self.agents = agents
        self.wipLimits = normalizedLimits
        self.assignmentEngine = assignmentEngine
        self.taskExecutor = taskExecutor
        self.boardStore = boardStore
    }

    private init(
        boards: [KanbanBoardRecord],
        selectedBoardID: UUID,
        assignmentEngine: AutoAssignmentEngine = AutoAssignmentEngine(),
        taskExecutor: any AgentTaskExecuting = DefaultAgentTaskExecutor(),
        boardStore: KanbanBoardStore? = nil
    ) {
        let resolvedBoard: KanbanBoardRecord
        if let selected = boards.first(where: { $0.id == selectedBoardID }) {
            resolvedBoard = selected
        } else if let first = boards.first {
            resolvedBoard = first
        } else {
            resolvedBoard = KanbanBoardRecord(name: Self.defaultBoardName)
        }

        self.boards = boards.isEmpty ? [resolvedBoard] : boards
        self.selectedBoardID = resolvedBoard.id
        self.tasks = resolvedBoard.tasks
        self.agents = resolvedBoard.agents
        self.wipLimits = resolvedBoard.wipLimits
        self.assignmentEngine = assignmentEngine
        self.taskExecutor = taskExecutor
        self.boardStore = boardStore
    }

    @discardableResult
    func createBoard(name: String) -> Bool {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            lastBoardMessage = "Board name is required"
            return false
        }

        if boards.contains(where: { $0.name.localizedCaseInsensitiveCompare(trimmedName) == .orderedSame }) {
            lastBoardMessage = "Board name already exists"
            return false
        }

        syncCurrentBoardRecord()
        let board = KanbanBoardRecord(name: trimmedName)
        boards.append(board)
        loadBoard(board.id)
        persistBoardState()
        lastBoardMessage = nil
        return true
    }

    @discardableResult
    func switchBoard(to boardID: UUID) -> Bool {
        guard boards.contains(where: { $0.id == boardID }) else { return false }
        guard boardID != selectedBoardID else { return true }

        syncCurrentBoardRecord()
        loadBoard(boardID)
        persistBoardState()
        lastBoardMessage = nil
        return true
    }

    @discardableResult
    func renameBoard(_ boardID: UUID, to name: String) -> Bool {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            lastBoardMessage = "Board name is required"
            return false
        }

        guard let index = boards.firstIndex(where: { $0.id == boardID }) else {
            lastBoardMessage = "Board not found"
            return false
        }

        if boards.contains(where: {
            $0.id != boardID && $0.name.localizedCaseInsensitiveCompare(trimmedName) == .orderedSame
        }) {
            lastBoardMessage = "Board name already exists"
            return false
        }

        syncCurrentBoardRecord()
        boards[index].name = trimmedName
        persistBoardState()
        lastBoardMessage = nil
        return true
    }

    @discardableResult
    func removeBoard(_ boardID: UUID) -> Bool {
        guard boards.count > 1 else {
            lastBoardMessage = "At least one board is required"
            return false
        }

        guard let removeIndex = boards.firstIndex(where: { $0.id == boardID }) else {
            lastBoardMessage = "Board not found"
            return false
        }

        syncCurrentBoardRecord()
        let wasSelectedBoard = boards[removeIndex].id == selectedBoardID
        boards.remove(at: removeIndex)

        if wasSelectedBoard {
            let fallbackIndex = min(removeIndex, boards.count - 1)
            loadBoard(boards[fallbackIndex].id)
        }

        persistBoardState()
        lastBoardMessage = nil
        return true
    }

    @discardableResult
    func duplicateBoard(_ boardID: UUID, name: String? = nil) -> Bool {
        guard let sourceIndex = boards.firstIndex(where: { $0.id == boardID }) else {
            lastBoardMessage = "Board not found"
            return false
        }

        syncCurrentBoardRecord()
        let sourceBoard = boards[sourceIndex]

        let resolvedName: String
        if let name {
            let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedName.isEmpty else {
                lastBoardMessage = "Board name is required"
                return false
            }
            resolvedName = trimmedName
        } else {
            resolvedName = uniqueBoardCopyName(for: sourceBoard.name)
        }

        if boards.contains(where: { $0.name.localizedCaseInsensitiveCompare(resolvedName) == .orderedSame }) {
            lastBoardMessage = "Board name already exists"
            return false
        }

        let copiedBoard = KanbanBoardRecord(
            name: resolvedName,
            tasks: sourceBoard.tasks,
            agents: sourceBoard.agents,
            wipLimits: sourceBoard.wipLimits
        )
        boards.append(copiedBoard)
        loadBoard(copiedBoard.id)
        persistBoardState()
        lastBoardMessage = nil
        return true
    }

    func tasks(in status: KanbanStatus) -> [WorkTask] {
        tasks
            .filter { $0.status == status }
            .sorted {
                if $0.storyPoints != $1.storyPoints {
                    return $0.storyPoints > $1.storyPoints
                }
                return $0.createdAt < $1.createdAt
            }
    }

    func filteredTasks(in status: KanbanStatus, query: String, assigneeFilter: TaskAssigneeFilter) -> [WorkTask] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let queryTerms = normalizedQuery
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)

        return tasks(in: status).filter { task in
            let matchesQuery: Bool
            if queryTerms.isEmpty {
                matchesQuery = true
            } else {
                let searchableValues = [
                    task.title.lowercased(),
                    task.details.lowercased(),
                    agentName(for: task.assignedAgentID).lowercased()
                ] + task.requiredSkills.map { $0.lowercased() }

                matchesQuery = queryTerms.allSatisfy { term in
                    searchableValues.contains { value in
                        value.contains(term)
                    }
                }
            }

            let matchesAssignee: Bool
            switch assigneeFilter {
            case .all:
                matchesAssignee = true
            case .unassigned:
                matchesAssignee = task.assignedAgentID == nil
            case let .assigned(agentID):
                matchesAssignee = task.assignedAgentID == agentID
            }

            return matchesQuery && matchesAssignee
        }
    }

    func globalTaskSearchResults(query: String) -> [GlobalTaskSearchResult] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedQuery.isEmpty else { return [] }

        syncCurrentBoardRecord()
        let queryTerms = normalizedQuery
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)

        var results: [GlobalTaskSearchResult] = []
        for board in boards {
            let agentsByID = Dictionary(uniqueKeysWithValues: board.agents.map { ($0.id, $0.name) })
            let boardMatches: [GlobalTaskSearchResult] = board.tasks.compactMap { task -> GlobalTaskSearchResult? in
                let assigneeName: String
                if let assignedAgentID = task.assignedAgentID, let resolvedName = agentsByID[assignedAgentID] {
                    assigneeName = resolvedName
                } else {
                    assigneeName = "Unassigned"
                }
                let searchableValues = [
                    board.name.lowercased(),
                    task.title.lowercased(),
                    task.details.lowercased(),
                    assigneeName.lowercased()
                ] + task.requiredSkills.map { $0.lowercased() }

                let matches = queryTerms.allSatisfy { term in
                    searchableValues.contains { value in value.contains(term) }
                }
                guard matches else { return nil }

                return GlobalTaskSearchResult(
                    taskID: task.id,
                    taskTitle: task.title,
                    taskDetails: task.details,
                    status: task.status,
                    boardID: board.id,
                    boardName: board.name,
                    assigneeName: assigneeName
                )
            }
            results.append(contentsOf: boardMatches)
        }

        return results.sorted { lhs, rhs in
            if lhs.boardName.localizedCaseInsensitiveCompare(rhs.boardName) != .orderedSame {
                return lhs.boardName.localizedCaseInsensitiveCompare(rhs.boardName) == .orderedAscending
            }
            return lhs.taskTitle.localizedCaseInsensitiveCompare(rhs.taskTitle) == .orderedAscending
        }
    }

    @discardableResult
    func openTask(_ taskID: UUID, in boardID: UUID) -> Bool {
        syncCurrentBoardRecord()
        guard let boardIndex = boards.firstIndex(where: { $0.id == boardID }) else {
            lastBoardMessage = "Board not found"
            return false
        }

        guard boards[boardIndex].tasks.contains(where: { $0.id == taskID }) else {
            lastBoardMessage = "Task not found"
            return false
        }

        if boardID != selectedBoardID {
            loadBoard(boardID)
            persistBoardState()
        }
        lastBoardMessage = nil
        return true
    }

    func workspaceExportData() -> Data? {
        syncCurrentBoardRecord()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .secondsSince1970
        do {
            return try encoder.encode(
                KanbanBoardSnapshot(
                    tasks: tasks,
                    agents: agents,
                    wipLimits: wipLimits,
                    boards: boards,
                    selectedBoardID: selectedBoardID
                )
            )
        } catch {
            lastBoardMessage = "Failed to export workspace"
            return nil
        }
    }

    func selectedBoardExportData() -> Data? {
        syncCurrentBoardRecord()
        guard let selectedBoard = boards.first(where: { $0.id == selectedBoardID }) else {
            lastBoardMessage = "Board not found"
            return nil
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .secondsSince1970
        do {
            return try encoder.encode(
                KanbanBoardSnapshot(
                    tasks: selectedBoard.tasks,
                    agents: selectedBoard.agents,
                    wipLimits: selectedBoard.wipLimits,
                    boards: [selectedBoard],
                    selectedBoardID: selectedBoard.id
                )
            )
        } catch {
            lastBoardMessage = "Failed to export board"
            return nil
        }
    }

    func workspaceImportPreview(from data: Data) -> WorkspaceImportPreview? {
        guard let snapshot = decodeWorkspaceSnapshot(from: data) else {
            lastBoardMessage = "Invalid workspace JSON"
            return nil
        }

        let importedBoards: [KanbanBoardRecord]
        if let snapshotBoards = snapshot.boards, !snapshotBoards.isEmpty {
            importedBoards = normalizedImportedBoardRecords(snapshotBoards)
        } else {
            let fallbackBoard = KanbanBoardRecord(
                name: Self.defaultBoardName,
                tasks: snapshot.tasks,
                agents: snapshot.agents,
                wipLimits: snapshot.wipLimits
            )
            importedBoards = normalizedImportedBoardRecords([fallbackBoard])
        }

        let taskCount = importedBoards.reduce(0) { partialResult, board in
            partialResult + board.tasks.count
        }
        let agentCount = importedBoards.reduce(0) { partialResult, board in
            partialResult + board.agents.count
        }
        return WorkspaceImportPreview(
            boardCount: importedBoards.count,
            taskCount: taskCount,
            agentCount: agentCount
        )
    }

    func workspaceImportPreview(from url: URL) -> WorkspaceImportPreview? {
        guard let data = try? Data(contentsOf: url) else {
            lastBoardMessage = "Failed to read workspace file"
            return nil
        }
        return workspaceImportPreview(from: data)
    }

    @discardableResult
    func exportWorkspace(to url: URL) -> Bool {
        guard let data = workspaceExportData() else { return false }
        do {
            try data.write(to: url, options: .atomic)
            let fileName = url.lastPathComponent.isEmpty ? "workspace.json" : url.lastPathComponent
            lastBoardMessage = "Exported workspace to \(fileName)"
            lastBoardMessageSeverity = .info
            return true
        } catch {
            lastBoardMessage = "Failed to write workspace file"
            return false
        }
    }

    @discardableResult
    func exportSelectedBoard(to url: URL) -> Bool {
        guard let data = selectedBoardExportData() else { return false }
        do {
            try data.write(to: url, options: .atomic)
            let fileName = url.lastPathComponent.isEmpty ? "board.json" : url.lastPathComponent
            lastBoardMessage = "Exported board to \(fileName)"
            lastBoardMessageSeverity = .info
            return true
        } catch {
            lastBoardMessage = "Failed to write board file"
            return false
        }
    }

    @discardableResult
    func importWorkspaceData(_ data: Data, strategy: WorkspaceImportStrategy = .replace) -> Bool {
        guard let snapshot = decodeWorkspaceSnapshot(from: data) else {
            lastBoardMessage = "Invalid workspace JSON"
            return false
        }

        let importedBoards: [KanbanBoardRecord]
        let preferredSelectedBoardID: UUID?
        if let snapshotBoards = snapshot.boards, !snapshotBoards.isEmpty {
            importedBoards = normalizedImportedBoardRecords(snapshotBoards)
            preferredSelectedBoardID = snapshot.selectedBoardID
        } else {
            let fallbackBoard = KanbanBoardRecord(
                name: Self.defaultBoardName,
                tasks: snapshot.tasks,
                agents: snapshot.agents,
                wipLimits: snapshot.wipLimits
            )
            importedBoards = normalizedImportedBoardRecords([fallbackBoard])
            preferredSelectedBoardID = nil
        }

        guard !importedBoards.isEmpty else {
            lastBoardMessage = "Workspace has no boards"
            return false
        }

        let resolvedSelectedBoardID: UUID
        switch strategy {
        case .replace:
            boards = importedBoards
            resolvedSelectedBoardID = preferredSelectedBoardID.flatMap { candidate in
                importedBoards.contains(where: { $0.id == candidate }) ? candidate : nil
            } ?? importedBoards[0].id
            loadBoard(resolvedSelectedBoardID)
            persistBoardState()
            let boardLabel = boards.count == 1 ? "board" : "boards"
            lastBoardMessage = "Imported workspace (\(boards.count) \(boardLabel))"
        case .merge:
            syncCurrentBoardRecord()
            let currentSelectedBoardID = selectedBoardID
            boards = mergedBoardRecords(currentBoards: boards, importedBoards: importedBoards)
            resolvedSelectedBoardID = preferredSelectedBoardID.flatMap { candidate in
                importedBoards.contains(where: { $0.id == candidate }) ? candidate : nil
            } ?? currentSelectedBoardID
            loadBoard(resolvedSelectedBoardID)
            persistBoardState()
            let boardLabel = importedBoards.count == 1 ? "board" : "boards"
            lastBoardMessage = "Merged workspace (+\(importedBoards.count) \(boardLabel))"
        }
        lastBoardMessageSeverity = .info
        return true
    }

    @discardableResult
    func importWorkspace(from url: URL, strategy: WorkspaceImportStrategy = .replace) -> Bool {
        guard let data = try? Data(contentsOf: url) else {
            lastBoardMessage = "Failed to read workspace file"
            return false
        }

        return importWorkspaceData(data, strategy: strategy)
    }

    @discardableResult
    func moveTask(_ taskID: UUID, to status: KanbanStatus) -> Bool {
        guard let index = tasks.firstIndex(where: { $0.id == taskID }) else { return false }
        let sourceStatus = tasks[index].status

        guard sourceStatus != status else { return false }
        guard sourceStatus.canMove(to: status) else {
            lastBoardMessage = "Invalid move: \(sourceStatus.title) -> \(status.title)"
            return false
        }
        guard !isWIPLimitReached(for: status, excluding: taskID) else {
            let limit = wipLimits[status] ?? 0
            lastBoardMessage = "WIP limit reached for \(status.title) (\(limit))"
            return false
        }

        tasks[index].status = status

        if status == .done || status == .todo {
            tasks[index].assignedAgentID = nil
            lastAssignmentReasons[taskID] = nil
        }

        persistBoardState()
        lastBoardMessage = nil
        return true
    }

    @discardableResult
    func moveTask(_ taskID: UUID, toBoard targetBoardID: UUID) -> Bool {
        guard let sourceBoardIndex = selectedBoardIndex else { return false }
        guard let targetBoardIndex = boards.firstIndex(where: { $0.id == targetBoardID }) else {
            lastBoardMessage = "Board not found"
            return false
        }
        guard sourceBoardIndex != targetBoardIndex else {
            lastBoardMessage = "Select a different board"
            return false
        }

        syncCurrentBoardRecord()
        guard let taskIndex = boards[sourceBoardIndex].tasks.firstIndex(where: { $0.id == taskID }) else {
            lastBoardMessage = "Task not found"
            return false
        }

        var movedTask = boards[sourceBoardIndex].tasks.remove(at: taskIndex)
        if let assignedAgentID = movedTask.assignedAgentID,
           !boards[targetBoardIndex].agents.contains(where: { $0.id == assignedAgentID }) {
            movedTask.assignedAgentID = nil
        }
        boards[targetBoardIndex].tasks.append(movedTask)

        loadBoard(boards[sourceBoardIndex].id)
        persistBoardState()
        lastBoardMessage = nil
        return true
    }

    @discardableResult
    func copyTask(_ taskID: UUID, toBoard targetBoardID: UUID) -> Bool {
        guard let sourceBoardIndex = selectedBoardIndex else { return false }
        guard let targetBoardIndex = boards.firstIndex(where: { $0.id == targetBoardID }) else {
            lastBoardMessage = "Board not found"
            return false
        }
        guard sourceBoardIndex != targetBoardIndex else {
            lastBoardMessage = "Select a different board"
            return false
        }

        syncCurrentBoardRecord()
        guard let sourceTask = boards[sourceBoardIndex].tasks.first(where: { $0.id == taskID }) else {
            lastBoardMessage = "Task not found"
            return false
        }

        var copiedTask = WorkTask(
            title: sourceTask.title,
            details: sourceTask.details,
            requiredSkills: Array(sourceTask.requiredSkills),
            storyPoints: sourceTask.storyPoints,
            status: sourceTask.status,
            assignedAgentID: sourceTask.assignedAgentID
        )
        if let assignedAgentID = copiedTask.assignedAgentID,
           !boards[targetBoardIndex].agents.contains(where: { $0.id == assignedAgentID }) {
            copiedTask.assignedAgentID = nil
        }
        boards[targetBoardIndex].tasks.append(copiedTask)

        loadBoard(boards[sourceBoardIndex].id)
        persistBoardState()
        lastBoardMessage = nil
        return true
    }

    @discardableResult
    func handleDrop(_ taskID: UUID, to status: KanbanStatus) -> Bool {
        moveTask(taskID, to: status)
    }

    func autoAssignTasks() {
        let result = assignmentEngine.assign(tasks: tasks, agents: agents)
        tasks = result.tasks
        lastUnassignedTaskIDs = result.unassignedTaskIDs
        lastAssignmentReasons = result.decisions.reduce(into: [:]) { partialResult, pair in
            partialResult[pair.key] = pair.value.reason
        }
        persistBoardState()
        lastBoardMessage = nil
    }

    @discardableResult
    func autoAssignTask(_ taskID: UUID) -> Bool {
        guard let taskIndex = tasks.firstIndex(where: { $0.id == taskID }) else { return false }
        guard tasks[taskIndex].status == .todo else {
            lastBoardMessage = "Only To Do tasks can be auto-assigned"
            lastBoardMessageSeverity = .warning
            return false
        }
        guard tasks[taskIndex].assignedAgentID == nil else {
            lastBoardMessage = "Task already assigned"
            lastBoardMessageSeverity = .warning
            return false
        }

        guard let decision = assignmentEngine.bestAgent(
            for: tasks[taskIndex],
            among: tasks,
            agents: agents
        ) else {
            lastUnassignedTaskIDs.insert(taskID)
            lastBoardMessage = "No eligible agent for task"
            lastBoardMessageSeverity = .warning
            return false
        }

        tasks[taskIndex].assignedAgentID = decision.agentID
        lastAssignmentReasons[taskID] = decision.reason
        lastUnassignedTaskIDs.remove(taskID)
        persistBoardState()
        lastBoardMessage = nil
        return true
    }

    @discardableResult
    func addTask(
        title: String,
        details: String,
        requiredSkillsText: String,
        storyPoints: Int = 1,
        autoAssign: Bool = false
    ) -> Bool {
        let skills = requiredSkillsText
            .split(separator: ",")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else {
            lastBoardMessage = "Task title is required"
            return false
        }

        let task = WorkTask(
            title: trimmedTitle,
            details: details,
            requiredSkills: skills,
            storyPoints: storyPoints,
            status: .todo,
            assignedAgentID: nil
        )
        tasks.append(task)

        if autoAssign {
            if let decision = assignmentEngine.bestAgent(
                for: task,
                among: tasks,
                agents: agents
            ),
               let taskIndex = tasks.firstIndex(where: { $0.id == task.id }) {
                tasks[taskIndex].assignedAgentID = decision.agentID
                lastAssignmentReasons[task.id] = decision.reason
                lastUnassignedTaskIDs.remove(task.id)
            } else {
                lastUnassignedTaskIDs.insert(task.id)
            }
        }

        persistBoardState()
        lastBoardMessage = nil
        return true
    }

    @discardableResult
    func updateTask(
        _ taskID: UUID,
        title: String,
        details: String,
        requiredSkillsText: String,
        storyPoints: Int
    ) -> Bool {
        guard let taskIndex = tasks.firstIndex(where: { $0.id == taskID }) else { return false }

        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else {
            lastBoardMessage = "Task title is required"
            return false
        }

        let skills = requiredSkillsText
            .split(separator: ",")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        tasks[taskIndex].title = trimmedTitle
        tasks[taskIndex].details = details
        tasks[taskIndex].requiredSkills = Set(skills.map { $0.lowercased() })
        tasks[taskIndex].storyPoints = max(1, storyPoints)

        if let agentID = tasks[taskIndex].assignedAgentID {
            guard let agent = agents.first(where: { $0.id == agentID }) else {
                tasks[taskIndex].assignedAgentID = nil
                lastAssignmentReasons[taskID] = nil
                if tasks[taskIndex].status == .todo {
                    lastUnassignedTaskIDs.insert(taskID)
                }
                persistBoardState()
                lastBoardMessage = nil
                return true
            }

            if !agent.hasSkills(for: tasks[taskIndex]) {
                tasks[taskIndex].assignedAgentID = nil
                lastAssignmentReasons[taskID] = nil
                if tasks[taskIndex].status == .todo {
                    lastUnassignedTaskIDs.insert(taskID)
                }
            }
        } else if tasks[taskIndex].status == .todo {
            lastUnassignedTaskIDs.insert(taskID)
        }

        persistBoardState()
        lastBoardMessage = nil
        return true
    }

    @discardableResult
    func duplicateTask(_ taskID: UUID) -> Bool {
        guard let sourceTask = tasks.first(where: { $0.id == taskID }) else { return false }

        let duplicatedTask = WorkTask(
            title: uniqueTaskCopyTitle(for: sourceTask.title),
            details: sourceTask.details,
            requiredSkills: Array(sourceTask.requiredSkills),
            storyPoints: sourceTask.storyPoints,
            status: .todo,
            assignedAgentID: nil
        )
        tasks.append(duplicatedTask)
        persistBoardState()
        lastBoardMessage = nil
        return true
    }

    @discardableResult
    func removeTask(_ taskID: UUID) -> Bool {
        guard let taskIndex = tasks.firstIndex(where: { $0.id == taskID }) else { return false }
        tasks.remove(at: taskIndex)
        lastUnassignedTaskIDs.remove(taskID)
        lastAssignmentReasons[taskID] = nil
        persistBoardState()
        lastBoardMessage = nil
        return true
    }

    @discardableResult
    func unassignTask(_ taskID: UUID) -> Bool {
        guard let taskIndex = tasks.firstIndex(where: { $0.id == taskID }) else { return false }
        guard tasks[taskIndex].assignedAgentID != nil else {
            lastBoardMessage = "Task is already unassigned"
            return false
        }

        tasks[taskIndex].assignedAgentID = nil
        lastAssignmentReasons[taskID] = nil
        if tasks[taskIndex].status == .todo {
            lastUnassignedTaskIDs.insert(taskID)
        }
        persistBoardState()
        lastBoardMessage = nil
        return true
    }

    @discardableResult
    func unassignTodoTasks(for agentID: UUID) -> Int {
        var count = 0

        for index in tasks.indices where tasks[index].status == .todo && tasks[index].assignedAgentID == agentID {
            let taskID = tasks[index].id
            tasks[index].assignedAgentID = nil
            lastAssignmentReasons[taskID] = nil
            lastUnassignedTaskIDs.insert(taskID)
            count += 1
        }

        guard count > 0 else {
            lastBoardMessage = "No todo tasks assigned to selected agent"
            lastBoardMessageSeverity = .warning
            return 0
        }

        persistBoardState()
        lastBoardMessage = nil
        return count
    }

    @discardableResult
    func clearDoneTasks() -> Int {
        let doneTaskIDs = Set(tasks.filter { $0.status == .done }.map { $0.id })
        guard !doneTaskIDs.isEmpty else {
            lastBoardMessage = "No done tasks to archive"
            lastBoardMessageSeverity = .warning
            return 0
        }

        tasks.removeAll { $0.status == .done }
        for taskID in doneTaskIDs {
            lastUnassignedTaskIDs.remove(taskID)
            lastAssignmentReasons[taskID] = nil
        }

        persistBoardState()
        lastBoardMessage = nil
        return doneTaskIDs.count
    }

    @discardableResult
    func rebalanceTodoAssignments() -> Int {
        var loads = Dictionary(uniqueKeysWithValues: agents.map { ($0.id, activeTaskCount(for: $0.id)) })
        let agentsByID = Dictionary(uniqueKeysWithValues: agents.map { ($0.id, $0) })
        var movedCount = 0

        let candidateIndices = tasks.indices
            .filter { index in
                guard tasks[index].status == .todo, let assignedID = tasks[index].assignedAgentID else { return false }
                guard let agent = agentsByID[assignedID] else { return false }
                let currentLoad = loads[assignedID, default: 0]
                return currentLoad > agent.maxConcurrentTasks
            }
            .sorted { lhs, rhs in
                if tasks[lhs].storyPoints != tasks[rhs].storyPoints {
                    return tasks[lhs].storyPoints < tasks[rhs].storyPoints
                }
                return tasks[lhs].createdAt < tasks[rhs].createdAt
            }

        for index in candidateIndices {
            guard let currentAgentID = tasks[index].assignedAgentID,
                  let currentAgent = agentsByID[currentAgentID] else {
                continue
            }

            let currentLoad = loads[currentAgentID, default: 0]
            guard currentLoad > currentAgent.maxConcurrentTasks else { continue }

            let eligibleTargets = agents
                .filter { agent in
                    guard agent.id != currentAgentID else { return false }
                    guard agent.hasSkills(for: tasks[index]) else { return false }
                    return loads[agent.id, default: 0] < agent.maxConcurrentTasks
                }
                .sorted { lhs, rhs in
                    let leftLoad = loads[lhs.id, default: 0]
                    let rightLoad = loads[rhs.id, default: 0]
                    if leftLoad != rightLoad {
                        return leftLoad < rightLoad
                    }
                    return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
                }

            guard let target = eligibleTargets.first else { continue }

            tasks[index].assignedAgentID = target.id
            loads[currentAgentID, default: 0] -= 1
            loads[target.id, default: 0] += 1
            lastAssignmentReasons[tasks[index].id] = "rebalance[\(currentAgent.name)->\(target.name)] load[\(loads[target.id, default: 0])/\(target.maxConcurrentTasks)]"
            movedCount += 1
        }

        guard movedCount > 0 else {
            lastBoardMessage = "No todo rebalancing needed"
            lastBoardMessageSeverity = .warning
            return 0
        }

        persistBoardState()
        lastBoardMessage = nil
        return movedCount
    }

    func canRebalanceTodoAssignments() -> Bool {
        guard agents.count >= 2 else { return false }

        let loads = Dictionary(uniqueKeysWithValues: agents.map { ($0.id, activeTaskCount(for: $0.id)) })
        let agentsByID = Dictionary(uniqueKeysWithValues: agents.map { ($0.id, $0) })

        for task in tasks where task.status == .todo {
            guard let currentAgentID = task.assignedAgentID,
                  let currentAgent = agentsByID[currentAgentID] else {
                continue
            }

            let currentLoad = loads[currentAgentID, default: 0]
            guard currentLoad > currentAgent.maxConcurrentTasks else { continue }

            let hasTarget = agents.contains { agent in
                guard agent.id != currentAgentID else { return false }
                guard agent.hasSkills(for: task) else { return false }
                return loads[agent.id, default: 0] < agent.maxConcurrentTasks
            }
            if hasTarget {
                return true
            }
        }

        return false
    }

    @discardableResult
    func addAgent(
        name: String,
        skillsText: String,
        maxConcurrentTasks: Int = 3
    ) -> Bool {
        addAgent(
            name: name,
            skillsText: skillsText,
            maxConcurrentTasks: maxConcurrentTasks,
            runtimeProfile: nil
        )
    }

    @discardableResult
    func addAgent(
        name: String,
        skillsText: String,
        maxConcurrentTasks: Int = 3,
        runtimeProfile: AgentRuntimeProfile? = nil
    ) -> Bool {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            lastBoardMessage = "Agent name is required"
            return false
        }

        let skills = skillsText
            .split(separator: ",")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        agents.append(
            AgentProfile(
                name: trimmedName,
                skills: skills,
                maxConcurrentTasks: maxConcurrentTasks,
                runtimeProfile: runtimeProfile
            )
        )
        persistBoardState()
        lastBoardMessage = nil
        return true
    }

    @discardableResult
    func removeAgent(_ agentID: UUID) -> Bool {
        guard agents.contains(where: { $0.id == agentID }) else { return false }

        agents.removeAll { $0.id == agentID }

        for index in tasks.indices where tasks[index].assignedAgentID == agentID {
            tasks[index].assignedAgentID = nil
            lastAssignmentReasons[tasks[index].id] = nil

            if tasks[index].status == .todo {
                lastUnassignedTaskIDs.insert(tasks[index].id)
            }
        }

        persistBoardState()
        lastBoardMessage = nil
        return true
    }

    @discardableResult
    func updateAgent(
        _ agentID: UUID,
        name: String,
        skillsText: String,
        maxConcurrentTasks: Int
    ) -> Bool {
        updateAgent(
            agentID,
            name: name,
            skillsText: skillsText,
            maxConcurrentTasks: maxConcurrentTasks,
            runtimeProfile: nil
        )
    }

    @discardableResult
    func updateAgent(
        _ agentID: UUID,
        name: String,
        skillsText: String,
        maxConcurrentTasks: Int,
        runtimeProfile: AgentRuntimeProfile? = nil
    ) -> Bool {
        guard let agentIndex = agents.firstIndex(where: { $0.id == agentID }) else { return false }

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            lastBoardMessage = "Agent name is required"
            return false
        }

        let normalizedCapacity = max(1, maxConcurrentTasks)
        let currentLoad = activeTaskCount(for: agentID)
        guard normalizedCapacity >= currentLoad else {
            lastBoardMessage = "Cannot set capacity below current load (\(currentLoad))"
            return false
        }

        let skills = skillsText
            .split(separator: ",")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        agents[agentIndex] = AgentProfile(
            id: agentID,
            name: trimmedName,
            skills: skills,
            maxConcurrentTasks: normalizedCapacity,
            runtimeProfile: runtimeProfile
        )

        for index in tasks.indices where tasks[index].assignedAgentID == agentID && tasks[index].status == .todo {
            if !agents[agentIndex].hasSkills(for: tasks[index]) {
                tasks[index].assignedAgentID = nil
                lastAssignmentReasons[tasks[index].id] = nil
                lastUnassignedTaskIDs.insert(tasks[index].id)
            }
        }

        persistBoardState()
        lastBoardMessage = nil
        return true
    }

    func activeTaskCount(for agentID: UUID) -> Int {
        tasks.filter { $0.assignedAgentID == agentID && $0.status != .done }.count
    }

    func loadRatio(for agentID: UUID) -> Double {
        guard let agent = agents.first(where: { $0.id == agentID }) else { return 0 }
        let load = activeTaskCount(for: agentID)
        return Double(load) / Double(max(1, agent.maxConcurrentTasks))
    }

    func loadPercent(for agentID: UUID) -> Int {
        Int((loadRatio(for: agentID) * 100).rounded())
    }

    func isAgentOverloaded(_ agentID: UUID) -> Bool {
        loadRatio(for: agentID) > 1.0
    }

    func wipPressurePercent(for status: KanbanStatus) -> Int {
        guard let limit = wipLimit(for: status), limit > 0 else { return 0 }
        let currentCount = tasks.filter { $0.status == status }.count
        return Int((Double(currentCount) / Double(limit) * 100).rounded())
    }

    func healthRecommendations() -> [BoardHealthRecommendation] {
        var recommendations: [BoardHealthRecommendation] = []

        if unassignedTodoTaskCount > 0 {
            if !agents.isEmpty {
                recommendations.append(
                    BoardHealthRecommendation(
                        action: .autoAssignUnassignedTodo,
                        title: "Auto-Assign Unowned To Do",
                        detail: "\(unassignedTodoTaskCount) unassigned task(s) can be dispatched automatically"
                    )
                )

                recommendations.append(
                    BoardHealthRecommendation(
                        action: .openManualTriage,
                        title: "Run Manual Triage",
                        detail: "Open triage sheet to manually assign pending To Do tasks"
                    )
                )
            } else {
                recommendations.append(
                    BoardHealthRecommendation(
                        action: .openNewAgent,
                        title: "Create First Agent",
                        detail: "Add an agent profile so pending To Do tasks can be assigned"
                    )
                )
            }
        }

        if canRebalanceTodoAssignments() {
            recommendations.append(
                BoardHealthRecommendation(
                    action: .rebalanceTodoLoad,
                    title: "Rebalance Overloaded Agents",
                    detail: "Move eligible To Do tasks away from overloaded agents"
                )
            )
        }

        if wipPressurePercent(for: .inProgress) >= 100, wipLimit(for: .inProgress) != nil {
            recommendations.append(
                BoardHealthRecommendation(
                    action: .increaseWIPLimit(.inProgress),
                    title: "Increase In Progress WIP",
                    detail: "In Progress is at or above its WIP limit"
                )
            )
        }

        if wipPressurePercent(for: .review) >= 100, wipLimit(for: .review) != nil {
            recommendations.append(
                BoardHealthRecommendation(
                    action: .increaseWIPLimit(.review),
                    title: "Increase Review WIP",
                    detail: "Review is at or above its WIP limit"
                )
            )
        }

        if doneTaskCount > 0 {
            recommendations.append(
                BoardHealthRecommendation(
                    action: .archiveDone,
                    title: "Archive Done Tasks",
                    detail: "\(doneTaskCount) completed task(s) can be archived"
                )
            )
        }

        return recommendations
    }

    @discardableResult
    func applyHealthRecommendation(_ action: BoardHealthAction) -> Bool {
        switch action {
        case .autoAssignUnassignedTodo:
            let beforeTasks = tasks
            autoAssignTasks()
            return tasks != beforeTasks || hasPendingManualTriage

        case .rebalanceTodoLoad:
            return rebalanceTodoAssignments() > 0

        case .openManualTriage:
            return !triageCandidates().isEmpty

        case .openNewAgent:
            return agents.isEmpty

        case let .increaseWIPLimit(status):
            guard let currentLimit = wipLimit(for: status) else {
                lastBoardMessage = "\(status.title) has no configured WIP limit"
                return false
            }
            return updateWIPLimit(for: status, limit: currentLimit + 1)

        case .archiveDone:
            return clearDoneTasks() > 0
        }
    }

    @discardableResult
    func applyAllHealthRecommendations() -> Int {
        let actions = healthRecommendations().map(\.action)
        var appliedCount = 0

        for action in actions where action.isAutoFixable {
            if applyHealthRecommendation(action) {
                appliedCount += 1
            }
        }

        if appliedCount > 0 {
            lastBoardMessage = "Applied \(appliedCount) health recommendation(s)"
            lastBoardMessageSeverity = .info
        } else if !actions.isEmpty {
            lastBoardMessage = "No automatic fixes available for current recommendations"
            lastBoardMessageSeverity = .warning
        } else {
            lastBoardMessage = "Board health already stable"
            lastBoardMessageSeverity = .info
        }

        return appliedCount
    }

    func agentName(for id: UUID?) -> String {
        guard let id else { return "Unassigned" }
        return agents.first(where: { $0.id == id })?.name ?? "Unknown"
    }

    func wipLimit(for status: KanbanStatus) -> Int? {
        wipLimits[status]
    }

    @discardableResult
    func updateWIPLimit(for status: KanbanStatus, limit: Int?) -> Bool {
        updateWIPLimits([status: limit])
    }

    @discardableResult
    func updateWIPLimits(_ limits: [KanbanStatus: Int?]) -> Bool {
        var candidateLimits = wipLimits

        for (status, limit) in limits {
            if let limit {
                candidateLimits[status] = max(1, limit)
            } else {
                candidateLimits[status] = nil
            }
        }

        for (status, limit) in candidateLimits {
            let currentCount = tasks.filter { $0.status == status }.count
            guard limit >= currentCount else {
                lastBoardMessage = "Cannot set \(status.title) WIP below current count (\(currentCount))"
                return false
            }
        }

        wipLimits = candidateLimits
        persistBoardState()
        lastBoardMessage = nil
        return true
    }

    func assignmentReason(for taskID: UUID) -> String? {
        lastAssignmentReasons[taskID]
    }

    func executionRecord(for taskID: UUID) -> TaskExecutionRecord? {
        tasks.first(where: { $0.id == taskID })?.executionRecord
    }

    @discardableResult
    func runTaskExecution(_ taskID: UUID) -> Bool {
        guard let taskIndex = tasks.firstIndex(where: { $0.id == taskID }) else { return false }
        lastExecutionDebugLog = nil
        lastCodexLoginCommand = nil
        guard tasks[taskIndex].status != .done else {
            lastBoardMessage = "Done tasks cannot be executed"
            lastBoardMessageSeverity = .warning
            return false
        }
        guard let agentID = tasks[taskIndex].assignedAgentID,
              let agent = agents.first(where: { $0.id == agentID }) else {
            lastBoardMessage = "Assign an agent before running this task"
            lastBoardMessageSeverity = .warning
            return false
        }

        if tasks[taskIndex].status == .todo {
            guard !isWIPLimitReached(for: .inProgress, excluding: taskID) else {
                let limit = wipLimits[.inProgress] ?? 0
                lastBoardMessage = "WIP limit reached for In Progress (\(limit))"
                lastBoardMessageSeverity = .warning
                return false
            }
            tasks[taskIndex].status = .inProgress
        }

        var record = tasks[taskIndex].executionRecord ?? TaskExecutionRecord(status: .running)
        record.status = .running
        record.runCount = max(0, record.runCount) + 1
        record.lastStartedAt = Date()
        record.lastFinishedAt = nil
        record.lastOutputSummary = nil
        record.lastError = nil
        record.lastDebugOutput = nil
        record.lastAgentID = agent.id
        tasks[taskIndex].executionRecord = record

        let outcome = taskExecutor.execute(task: tasks[taskIndex], agent: agent)
        let finishedAt = Date()

        switch outcome {
        case let .success(summary):
            var finishedRecord = tasks[taskIndex].executionRecord ?? record
            finishedRecord.status = .succeeded
            finishedRecord.lastFinishedAt = finishedAt
            finishedRecord.lastOutputSummary = normalizeExecutionText(summary)
            finishedRecord.lastError = nil
            finishedRecord.lastDebugOutput = nil
            finishedRecord.lastAgentID = agent.id
            tasks[taskIndex].executionRecord = finishedRecord
            lastExecutionDebugLog = nil
            lastCodexLoginCommand = nil

            if tasks[taskIndex].status == .inProgress {
                if isWIPLimitReached(for: .review, excluding: taskID) {
                    let limit = wipLimits[.review] ?? 0
                    lastBoardMessage = "Execution completed, but Review WIP limit reached (\(limit))"
                    lastBoardMessageSeverity = .warning
                } else {
                    tasks[taskIndex].status = .review
                    lastBoardMessage = "Execution succeeded: \(tasks[taskIndex].title)"
                    lastBoardMessageSeverity = .info
                }
            } else {
                lastBoardMessage = "Execution succeeded: \(tasks[taskIndex].title)"
                lastBoardMessageSeverity = .info
            }

        case let .failure(message):
            var failedRecord = tasks[taskIndex].executionRecord ?? record
            let parsedFailure = parseExecutionFailure(message)
            failedRecord.status = .failed
            failedRecord.lastFinishedAt = finishedAt
            failedRecord.lastOutputSummary = nil
            failedRecord.lastError = normalizeExecutionText(parsedFailure.userMessage) ?? "Unknown execution error"
            failedRecord.lastDebugOutput = normalizeExecutionText(parsedFailure.debugLog)
            failedRecord.lastAgentID = agent.id
            tasks[taskIndex].executionRecord = failedRecord
            lastExecutionDebugLog = failedRecord.lastDebugOutput
            lastCodexLoginCommand = extractCodexLoginCommand(
                from: failedRecord.lastError,
                debugLog: failedRecord.lastDebugOutput
            )
            lastBoardMessage = "Execution failed: \(failedRecord.lastError ?? "Unknown execution error")"
            lastBoardMessageSeverity = .warning
        }

        persistBoardState()
        return true
    }

    @discardableResult
    func retryTaskExecution(_ taskID: UUID) -> Bool {
        guard let record = executionRecord(for: taskID), record.status == .failed else {
            lastBoardMessage = "Only failed executions can be retried"
            lastBoardMessageSeverity = .warning
            return false
        }
        return runTaskExecution(taskID)
    }

    func triageCandidates() -> [WorkTask] {
        tasks
            .filter { $0.status == .todo && $0.assignedAgentID == nil }
            .sorted {
                if $0.storyPoints != $1.storyPoints {
                    return $0.storyPoints > $1.storyPoints
                }
                return $0.createdAt < $1.createdAt
            }
    }

    func assignableAgents(for taskID: UUID) -> [AgentProfile] {
        guard let task = tasks.first(where: { $0.id == taskID }) else { return [] }
        guard task.status == .todo, task.assignedAgentID == nil else { return [] }

        return agents
            .filter { agent in
                agent.hasSkills(for: task) && activeTaskCount(for: agent.id) < agent.maxConcurrentTasks
            }
            .sorted { lhs, rhs in
                let leftLoad = activeTaskCount(for: lhs.id)
                let rightLoad = activeTaskCount(for: rhs.id)

                if leftLoad != rightLoad {
                    return leftLoad < rightLoad
                }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
    }

    func reassignableAgents(for taskID: UUID) -> [AgentProfile] {
        guard let task = tasks.first(where: { $0.id == taskID }) else { return [] }
        guard task.status == .todo, let currentAssigneeID = task.assignedAgentID else { return [] }

        return agents
            .filter { agent in
                guard agent.id != currentAssigneeID else { return false }
                return agent.hasSkills(for: task) && activeTaskCount(for: agent.id) < agent.maxConcurrentTasks
            }
            .sorted { lhs, rhs in
                let leftLoad = activeTaskCount(for: lhs.id)
                let rightLoad = activeTaskCount(for: rhs.id)

                if leftLoad != rightLoad {
                    return leftLoad < rightLoad
                }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
    }

    func resolvedTriageAssignments(existing: [UUID: UUID] = [:]) -> [UUID: UUID] {
        bulkTriageAssignmentPlan(using: existing)
    }

    func bulkAssignableTriageTaskCount(using preferredAssignments: [UUID: UUID] = [:]) -> Int {
        bulkTriageAssignmentPlan(using: preferredAssignments).count
    }

    func bulkUnassignableTriageTaskCount(using preferredAssignments: [UUID: UUID] = [:]) -> Int {
        let assignableCount = bulkAssignableTriageTaskCount(using: preferredAssignments)
        return max(0, triageCandidates().count - assignableCount)
    }

    func bulkTriageAssignmentPlan(using preferredAssignments: [UUID: UUID] = [:]) -> [UUID: UUID] {
        let agentsByID = Dictionary(uniqueKeysWithValues: agents.map { ($0.id, $0) })
        var loadsByAgentID = Dictionary(uniqueKeysWithValues: agents.map { ($0.id, activeTaskCount(for: $0.id)) })
        var plan: [UUID: UUID] = [:]

        for task in triageCandidates() {
            guard let selectedAgent = selectBulkTriageAgent(
                for: task,
                preferredAgentID: preferredAssignments[task.id],
                agentsByID: agentsByID,
                loadsByAgentID: loadsByAgentID
            ) else {
                continue
            }

            plan[task.id] = selectedAgent.id
            loadsByAgentID[selectedAgent.id, default: 0] += 1
        }

        return plan
    }

    @discardableResult
    func manuallyAssignTask(_ taskID: UUID, to agentID: UUID) -> Bool {
        guard let taskIndex = tasks.firstIndex(where: { $0.id == taskID }) else { return false }
        guard let agent = agents.first(where: { $0.id == agentID }) else { return false }

        guard tasks[taskIndex].status == .todo else {
            lastBoardMessage = "Only To Do tasks can be manually triaged"
            return false
        }
        guard tasks[taskIndex].assignedAgentID == nil else {
            lastBoardMessage = "Task is already assigned"
            return false
        }

        guard agent.hasSkills(for: tasks[taskIndex]) else {
            lastBoardMessage = "Agent \(agent.name) does not match required skills"
            return false
        }

        let currentLoad = activeTaskCount(for: agentID)
        guard currentLoad < agent.maxConcurrentTasks else {
            lastBoardMessage = "Agent \(agent.name) is at max load (\(agent.maxConcurrentTasks))"
            return false
        }

        tasks[taskIndex].assignedAgentID = agentID
        lastUnassignedTaskIDs.remove(taskID)
        lastAssignmentReasons[taskID] = "manual[\(agent.name)] load[\(currentLoad + 1)/\(agent.maxConcurrentTasks)]"
        persistBoardState()
        lastBoardMessage = nil
        return true
    }

    @discardableResult
    func reassignTask(_ taskID: UUID, to agentID: UUID) -> Bool {
        guard let taskIndex = tasks.firstIndex(where: { $0.id == taskID }) else { return false }
        guard let agent = agents.first(where: { $0.id == agentID }) else { return false }

        guard tasks[taskIndex].status == .todo else {
            lastBoardMessage = "Only To Do tasks can be reassigned"
            return false
        }
        guard let currentAgentID = tasks[taskIndex].assignedAgentID else {
            lastBoardMessage = "Task is unassigned"
            return false
        }
        guard currentAgentID != agentID else {
            lastBoardMessage = "Task already assigned to \(agent.name)"
            return false
        }

        guard agent.hasSkills(for: tasks[taskIndex]) else {
            lastBoardMessage = "Agent \(agent.name) does not match required skills"
            return false
        }

        let currentLoad = activeTaskCount(for: agentID)
        guard currentLoad < agent.maxConcurrentTasks else {
            lastBoardMessage = "Agent \(agent.name) is at max load (\(agent.maxConcurrentTasks))"
            return false
        }

        tasks[taskIndex].assignedAgentID = agentID
        lastUnassignedTaskIDs.remove(taskID)
        lastAssignmentReasons[taskID] = "manual[\(agent.name)] load[\(currentLoad + 1)/\(agent.maxConcurrentTasks)]"
        persistBoardState()
        lastBoardMessage = nil
        return true
    }

    @discardableResult
    func bulkAssignTriageTasks(using preferredAssignments: [UUID: UUID] = [:]) -> Int {
        let assignmentPlan = bulkTriageAssignmentPlan(using: preferredAssignments)
        let candidates = triageCandidates()
        var loadsByAgentID = Dictionary(uniqueKeysWithValues: agents.map { ($0.id, activeTaskCount(for: $0.id)) })
        var assignedCount = 0

        for task in candidates {
            guard let selectedAgentID = assignmentPlan[task.id] else { continue }
            guard let taskIndex = tasks.firstIndex(where: { $0.id == task.id }) else { continue }
            guard let selectedAgent = agents.first(where: { $0.id == selectedAgentID }) else { continue }

            let currentLoad = loadsByAgentID[selectedAgent.id, default: 0]
            tasks[taskIndex].assignedAgentID = selectedAgent.id
            loadsByAgentID[selectedAgent.id] = currentLoad + 1
            lastUnassignedTaskIDs.remove(task.id)
            lastAssignmentReasons[task.id] = "manual-bulk[\(selectedAgent.name)] load[\(currentLoad + 1)/\(selectedAgent.maxConcurrentTasks)]"
            assignedCount += 1
        }

        guard assignedCount > 0 else {
            if !candidates.isEmpty {
                lastBoardMessage = "No eligible agents available for pending triage tasks"
                lastBoardMessageSeverity = .warning
            }
            return 0
        }

        persistBoardState()
        let remainingTriageCount = triageCandidates().count
        let summaryMessage = remainingTriageCount > 0
            ? bulkTriageAssignmentSummary(assignedCount: assignedCount, remainingCount: remainingTriageCount)
            : nil
        lastBoardMessage = summaryMessage
        if summaryMessage != nil {
            lastBoardMessageSeverity = .warning
        }
        return assignedCount
    }

    private func selectBulkTriageAgent(
        for task: WorkTask,
        preferredAgentID: UUID?,
        agentsByID: [UUID: AgentProfile],
        loadsByAgentID: [UUID: Int]
    ) -> AgentProfile? {
        if let preferredAgentID,
           let preferredAgent = agentsByID[preferredAgentID],
           isEligibleForBulkTriage(preferredAgent, task: task, loadsByAgentID: loadsByAgentID) {
            return preferredAgent
        }

        return agents
            .filter { agent in
                isEligibleForBulkTriage(agent, task: task, loadsByAgentID: loadsByAgentID)
            }
            .sorted { lhs, rhs in
                let leftLoad = loadsByAgentID[lhs.id, default: 0]
                let rightLoad = loadsByAgentID[rhs.id, default: 0]

                if leftLoad != rightLoad {
                    return leftLoad < rightLoad
                }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
            .first
    }

    private func isEligibleForBulkTriage(
        _ agent: AgentProfile,
        task: WorkTask,
        loadsByAgentID: [UUID: Int]
    ) -> Bool {
        guard agent.hasSkills(for: task) else { return false }
        return loadsByAgentID[agent.id, default: 0] < agent.maxConcurrentTasks
    }

    private func bulkTriageAssignmentSummary(assignedCount: Int, remainingCount: Int) -> String {
        let assignedLabel = assignedCount == 1 ? "task" : "tasks"
        let remainingLabel = remainingCount == 1 ? "task still needs" : "tasks still need"
        return "Assigned \(assignedCount) triage \(assignedLabel). \(remainingCount) \(remainingLabel) manual attention"
    }

    private func normalizeExecutionText(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func parseExecutionFailure(_ value: String) -> (userMessage: String, debugLog: String?) {
        let delimiter = DefaultAgentTaskExecutor.debugLogDelimiter
        guard let range = value.range(of: delimiter) else {
            return (value, nil)
        }
        let userMessage = String(value[..<range.lowerBound])
        let debugLog = String(value[range.upperBound...])
        return (userMessage, debugLog)
    }

    private func extractCodexLoginCommand(from userMessage: String?, debugLog: String?) -> String? {
        [userMessage, debugLog]
            .compactMap { $0 }
            .compactMap { extractCodexLoginCommand(from: $0) }
            .first
    }

    private func extractCodexLoginCommand(from value: String) -> String? {
        value
            .split(whereSeparator: \.isNewline)
            .compactMap { line -> String? in
                let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard trimmedLine.localizedCaseInsensitiveContains("codex login") else {
                    return nil
                }

                let start: String.Index
                if let homeRange = trimmedLine.range(of: "HOME=") {
                    start = homeRange.lowerBound
                } else if let codexHomeRange = trimmedLine.range(of: "CODEX_HOME=") {
                    start = codexHomeRange.lowerBound
                } else if let codexRange = trimmedLine.range(of: "codex login", options: .caseInsensitive) {
                    start = codexRange.lowerBound
                } else {
                    start = trimmedLine.startIndex
                }

                var command = String(trimmedLine[start...])
                if command.hasPrefix("`"), command.hasSuffix("`"), command.count > 1 {
                    command.removeFirst()
                    command.removeLast()
                } else {
                    command = command.trimmingCharacters(in: CharacterSet(charactersIn: "`"))
                }
                command = command.trimmingCharacters(in: CharacterSet(charactersIn: " \t."))
                return command.isEmpty ? nil : command
            }
            .first
    }

    private func isWIPLimitReached(for destination: KanbanStatus, excluding taskID: UUID) -> Bool {
        guard let limit = wipLimits[destination] else { return false }
        let currentCount = tasks.filter { $0.status == destination && $0.id != taskID }.count
        return currentCount >= limit
    }

    private var selectedBoardIndex: Int? {
        boards.firstIndex(where: { $0.id == selectedBoardID })
    }

    private func syncCurrentBoardRecord() {
        guard let selectedBoardIndex else { return }
        boards[selectedBoardIndex].tasks = tasks
        boards[selectedBoardIndex].agents = agents
        boards[selectedBoardIndex].wipLimits = wipLimits
    }

    private func loadBoard(_ boardID: UUID) {
        guard let index = boards.firstIndex(where: { $0.id == boardID }) else { return }
        let board = boards[index]
        selectedBoardID = board.id
        tasks = board.tasks
        agents = board.agents
        wipLimits = board.wipLimits
        lastUnassignedTaskIDs = Set(tasks.filter { $0.status == .todo && $0.assignedAgentID == nil }.map(\.id))
        lastAssignmentReasons = [:]
        lastBoardMessage = nil
        lastBoardMessageSeverity = nil
        lastExecutionDebugLog = nil
        lastCodexLoginCommand = nil
    }

    private func uniqueBoardCopyName(for sourceName: String) -> String {
        let normalizedSourceName = sourceName.trimmingCharacters(in: .whitespacesAndNewlines)
        let baseName = normalizedSourceName.isEmpty ? Self.defaultBoardName : normalizedSourceName
        var candidate = "\(baseName) Copy"
        var suffix = 2
        while boards.contains(where: { $0.name.localizedCaseInsensitiveCompare(candidate) == .orderedSame }) {
            candidate = "\(baseName) Copy \(suffix)"
            suffix += 1
        }
        return candidate
    }

    private func uniqueTaskCopyTitle(for sourceTitle: String) -> String {
        let normalizedSourceTitle = sourceTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let baseTitle = normalizedSourceTitle.isEmpty ? "Task" : normalizedSourceTitle
        let baseCandidate = "\(baseTitle) Copy"
        let existingTitles = Set(tasks.map { $0.title.lowercased() })

        var candidate = baseCandidate
        var suffix = 2
        while existingTitles.contains(candidate.lowercased()) {
            candidate = "\(baseCandidate) \(suffix)"
            suffix += 1
        }
        return candidate
    }

    private func normalizedBoardRecord(_ board: KanbanBoardRecord) -> KanbanBoardRecord {
        let trimmedName = board.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedName = trimmedName.isEmpty ? Self.defaultBoardName : trimmedName
        let agentIDs = Set(board.agents.map(\.id))
        let resolvedTasks = board.tasks.map { task in
            var resolvedTask = task
            if let assignedAgentID = resolvedTask.assignedAgentID,
               !agentIDs.contains(assignedAgentID) {
                resolvedTask.assignedAgentID = nil
            }
            return resolvedTask
        }
        let resolvedWIPLimits = board.wipLimits.reduce(into: [:]) { partialResult, pair in
            partialResult[pair.key] = max(1, pair.value)
        }
        return KanbanBoardRecord(
            id: board.id,
            name: resolvedName,
            tasks: resolvedTasks,
            agents: board.agents,
            wipLimits: resolvedWIPLimits
        )
    }

    private func normalizedImportedBoardRecords(_ importedBoards: [KanbanBoardRecord]) -> [KanbanBoardRecord] {
        var usedNames: Set<String> = []
        return importedBoards.map { board in
            var normalizedBoard = normalizedBoardRecord(board)
            let baseName = normalizedBoard.name
            var candidateName = baseName
            var suffix = 2
            while usedNames.contains(candidateName.lowercased()) {
                candidateName = "\(baseName) (\(suffix))"
                suffix += 1
            }
            normalizedBoard.name = candidateName
            usedNames.insert(candidateName.lowercased())
            return normalizedBoard
        }
    }

    private func mergedBoardRecords(
        currentBoards: [KanbanBoardRecord],
        importedBoards: [KanbanBoardRecord]
    ) -> [KanbanBoardRecord] {
        var mergedBoards = currentBoards
        var usedNames = Set(currentBoards.map { $0.name.lowercased() })

        for board in importedBoards {
            var mergedBoard = board
            let baseName = mergedBoard.name
            var candidateName = baseName
            var suffix = 2
            while usedNames.contains(candidateName.lowercased()) {
                candidateName = "\(baseName) (\(suffix))"
                suffix += 1
            }
            mergedBoard.name = candidateName
            usedNames.insert(candidateName.lowercased())
            mergedBoards.append(mergedBoard)
        }

        return mergedBoards
    }

    private func decodeWorkspaceSnapshot(from data: Data) -> KanbanBoardSnapshot? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return try? decoder.decode(KanbanBoardSnapshot.self, from: data)
    }

    private func boardHealthPenaltyItems() -> [(label: String, points: Int)] {
        var items: [(label: String, points: Int)] = []

        let unassignedPenalty = min(30, unassignedTodoTaskCount * 10)
        if unassignedPenalty > 0 {
            items.append(("Unassigned To Do", unassignedPenalty))
        }

        let overloadedPenalty = min(30, overloadedAgentCount * 10)
        if overloadedPenalty > 0 {
            items.append(("Overloaded Agents", overloadedPenalty))
        }

        if wipPressurePercent(for: .inProgress) >= 100 {
            items.append(("In Progress WIP Pressure", 10))
        }

        if wipPressurePercent(for: .review) >= 100 {
            items.append(("Review WIP Pressure", 10))
        }

        if doneTaskCount > 0 {
            items.append(("Done Backlog", 5))
        }

        return items
    }

    private func persistBoardState() {
        guard let boardStore else { return }
        syncCurrentBoardRecord()
        let snapshot = KanbanBoardSnapshot(
            tasks: tasks,
            agents: agents,
            wipLimits: wipLimits,
            boards: boards,
            selectedBoardID: selectedBoardID
        )
        try? boardStore.save(snapshot)
    }
}

extension KanbanBoardViewModel {
    static func persistentBoard(boardStore: KanbanBoardStore = FileKanbanBoardStore()) -> KanbanBoardViewModel {
        if let snapshot = try? boardStore.load() {
            if let boards = snapshot.boards, !boards.isEmpty {
                let resolvedSelectedBoardID = snapshot.selectedBoardID ?? boards[0].id
                return KanbanBoardViewModel(
                    boards: boards,
                    selectedBoardID: resolvedSelectedBoardID,
                    boardStore: boardStore
                )
            }
            return KanbanBoardViewModel(
                tasks: snapshot.tasks,
                agents: snapshot.agents,
                wipLimits: snapshot.wipLimits,
                boardStore: boardStore
            )
        }
        return demoBoard(boardStore: boardStore)
    }

    static func demoBoard(boardStore: KanbanBoardStore? = nil) -> KanbanBoardViewModel {
        let demoData = demoSeedData()
        return KanbanBoardViewModel(
            tasks: demoData.tasks,
            agents: demoData.agents,
            boardStore: boardStore
        )
    }

    private static func demoSeedData() -> (tasks: [WorkTask], agents: [AgentProfile]) {
        let designAgent = AgentProfile(
            name: "Design Agent",
            skills: ["ui", "ux", "prototype"],
            maxConcurrentTasks: 2
        )
        let frontendAgent = AgentProfile(
            name: "Frontend Agent",
            skills: ["swiftui", "ui", "animation"],
            maxConcurrentTasks: 3
        )
        let qualityAgent = AgentProfile(
            name: "QA Agent",
            skills: ["testing", "tdd", "automation"],
            maxConcurrentTasks: 2
        )

        let demoTasks = [
            WorkTask(
                title: "Plan Sprint Backlog",
                details: "Break roadmap into kanban-ready stories",
                requiredSkills: ["ux"],
                storyPoints: 2,
                status: .todo,
                assignedAgentID: nil
            ),
            WorkTask(
                title: "Build Kanban Column UI",
                details: "Create responsive macOS board columns",
                requiredSkills: ["swiftui", "ui"],
                storyPoints: 5,
                status: .inProgress,
                assignedAgentID: frontendAgent.id
            ),
            WorkTask(
                title: "Write Assignment Tests",
                details: "Cover load balancing and skill matching",
                requiredSkills: ["testing", "tdd"],
                storyPoints: 3,
                status: .review,
                assignedAgentID: qualityAgent.id
            )
        ]

        return (demoTasks, [designAgent, frontendAgent, qualityAgent])
    }
}
