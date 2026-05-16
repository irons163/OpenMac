import Combine
import Foundation

enum TaskAssigneeFilter: Equatable {
    case all
    case unassigned
    case assigned(UUID)
}

enum BoardHealthAction: Equatable {
    case autoAssignUnassignedTodo
    case createMissingDependencyTasks
    case openManualTriage
    case openNewAgent
    case rebalanceTodoLoad
    case increaseWIPLimit(KanbanStatus)
    case archiveDone

    var isAutoFixable: Bool {
        switch self {
        case .openManualTriage, .openNewAgent:
            return false
        case .autoAssignUnassignedTodo, .createMissingDependencyTasks, .rebalanceTodoLoad, .increaseWIPLimit, .archiveDone:
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

enum CodexProjectsDirectorySettings {
    static let userDefaultsKey = "codexProjectsDirectoryPath"
    static let environmentOverrideKey = "OPENMAC_PROJECTS_DIR"
    private static let defaultRelativePath = "Library/Application Support/OpenMac/Projects"

    static func defaultProjectsDirectoryURL(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        homeDirectory.appendingPathComponent(defaultRelativePath, isDirectory: true)
    }

    static func resolvedProjectsDirectoryPath(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        userDefaults: UserDefaults = .standard
    ) -> String {
        if let override = environment[environmentOverrideKey]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !override.isEmpty {
            return (override as NSString).expandingTildeInPath
        }

        if let stored = userDefaults.string(forKey: userDefaultsKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !stored.isEmpty {
            return (stored as NSString).expandingTildeInPath
        }

        return defaultProjectsDirectoryURL().path
    }

    @discardableResult
    static func ensureProjectsDirectoryExists(
        at path: String,
        fileManager: FileManager = .default
    ) throws -> URL {
        let expandedPath = (path as NSString).expandingTildeInPath
        let url = URL(fileURLWithPath: expandedPath, isDirectory: true)
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func boardScopedProjectsDirectoryPath(
        baseDirectoryPath: String,
        boardName: String
    ) -> String {
        let expandedBasePath = (baseDirectoryPath as NSString).expandingTildeInPath
        let baseURL = URL(fileURLWithPath: expandedBasePath, isDirectory: true)
        let folderName = normalizedBoardDirectoryName(boardName)
        return baseURL.appendingPathComponent(folderName, isDirectory: true).path
    }

    private static func normalizedBoardDirectoryName(_ boardName: String) -> String {
        let trimmed = boardName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "board" }

        let allowedCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        var scalars: [UnicodeScalar] = []
        var previousWasSeparator = false

        for scalar in trimmed.unicodeScalars {
            if allowedCharacters.contains(scalar) {
                scalars.append(scalar)
                previousWasSeparator = false
            } else if !previousWasSeparator {
                scalars.append("-")
                previousWasSeparator = true
            }
        }

        let collapsed = String(String.UnicodeScalarView(scalars))
            .trimmingCharacters(in: CharacterSet(charactersIn: "-_"))
        return collapsed.isEmpty ? "board" : collapsed
    }
}

enum WorktreeExecutionSettings {
    static let enabledUserDefaultsKey = "worktreeExecutionEnabled"
    static let repositoryPathUserDefaultsKey = "worktreeRepositoryPath"
    static let branchPrefixUserDefaultsKey = "worktreeBranchPrefix"
    private static let fallbackRepositoryPathUserDefaultsKey = "githubRepositoryPath"
    private static let fallbackBranchPrefixUserDefaultsKey = "githubBranchPrefix"

    static func isEnabled(userDefaults: UserDefaults = .standard) -> Bool {
        userDefaults.bool(forKey: enabledUserDefaultsKey)
    }

    static func resolvedRepositoryPath(userDefaults: UserDefaults = .standard) -> String {
        let explicitPath = userDefaults.string(forKey: repositoryPathUserDefaultsKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !explicitPath.isEmpty {
            return (explicitPath as NSString).expandingTildeInPath
        }
        let fallbackPath = userDefaults.string(forKey: fallbackRepositoryPathUserDefaultsKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return (fallbackPath as NSString).expandingTildeInPath
    }

    static func resolvedBranchPrefix(userDefaults: UserDefaults = .standard) -> String {
        let explicitPrefix = userDefaults.string(forKey: branchPrefixUserDefaultsKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !explicitPrefix.isEmpty {
            return normalizedBranchPrefix(explicitPrefix)
        }
        let fallbackPrefix = userDefaults.string(forKey: fallbackBranchPrefixUserDefaultsKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return normalizedBranchPrefix(fallbackPrefix)
    }

    static func normalizedBranchPrefix(_ rawValue: String) -> String {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "openmac" }
        return trimmed
            .split(separator: "/")
            .map { segment in
                segment.lowercased().replacingOccurrences(of: " ", with: "-")
            }
            .joined(separator: "/")
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }
}

struct BoardHealthRecommendation: Identifiable, Equatable {
    let action: BoardHealthAction
    let title: String
    let detail: String

    var id: String {
        switch action {
        case .autoAssignUnassignedTodo:
            return "auto-assign-unassigned-todo"
        case .createMissingDependencyTasks:
            return "create-missing-dependency-tasks"
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
    func execute(
        task: WorkTask,
        agent: AgentProfile,
        onProgress: @escaping (_ update: String) -> Void
    ) -> AgentTaskExecutionOutcome
    func requestCancellation(taskID: UUID)
    func requestCancellation(taskIDs: [UUID])
    func clearCancellation(taskID: UUID)
}

extension AgentTaskExecuting {
    func execute(
        task: WorkTask,
        agent: AgentProfile,
        onProgress: @escaping (_ update: String) -> Void
    ) -> AgentTaskExecutionOutcome {
        execute(task: task, agent: agent)
    }

    func requestCancellation(taskID: UUID) {
        _ = taskID
    }

    func requestCancellation(taskIDs: [UUID]) {
        let uniqueTaskIDs = Set(taskIDs)
        for taskID in uniqueTaskIDs {
            requestCancellation(taskID: taskID)
        }
    }

    func clearCancellation(taskID: UUID) {
        _ = taskID
    }
}

struct DefaultAgentTaskExecutor: AgentTaskExecuting {
    static let debugLogDelimiter = "\n\n--- debug ---\n"

    private final class CancellationRegistry {
        private let lock = NSLock()
        private var runningProcessByTaskID: [UUID: Process] = [:]
        private var cancelledTaskIDs: Set<UUID> = []

        func register(process: Process, for taskID: UUID) {
            let shouldTerminate: Bool
            lock.lock()
            runningProcessByTaskID[taskID] = process
            shouldTerminate = cancelledTaskIDs.contains(taskID)
            lock.unlock()

            guard shouldTerminate else { return }
            terminate(process)
        }

        func unregister(taskID: UUID, process: Process) {
            lock.lock()
            if let running = runningProcessByTaskID[taskID], running === process {
                runningProcessByTaskID.removeValue(forKey: taskID)
            }
            lock.unlock()
        }

        func requestCancellation(for taskID: UUID) {
            let process: Process?
            lock.lock()
            cancelledTaskIDs.insert(taskID)
            process = runningProcessByTaskID[taskID]
            lock.unlock()

            guard let process else { return }
            terminate(process)
        }

        func clearCancellation(for taskID: UUID) {
            lock.lock()
            cancelledTaskIDs.remove(taskID)
            lock.unlock()
        }

        func isCancellationRequested(for taskID: UUID) -> Bool {
            lock.lock()
            let isRequested = cancelledTaskIDs.contains(taskID)
            lock.unlock()
            return isRequested
        }

        private func terminate(_ process: Process) {
            guard process.isRunning else { return }
            process.interrupt()
            process.terminate()
        }
    }

    private static let cancellationRegistry = CancellationRegistry()

    struct CodexBridgeRequest: Equatable {
        let taskID: UUID
        let prompt: String
        let model: String
        let reasoningEffort: String?
        let profile: String?
        let workingDirectoryPath: String?

        init(
            taskID: UUID,
            prompt: String,
            model: String,
            reasoningEffort: String? = nil,
            profile: String?,
            workingDirectoryPath: String?
        ) {
            self.taskID = taskID
            self.prompt = prompt
            self.model = model
            self.reasoningEffort = reasoningEffort
            self.profile = profile
            self.workingDirectoryPath = workingDirectoryPath
        }
    }

    var environmentProvider: () -> [String: String] = { ProcessInfo.processInfo.environment }
    var urlSession: URLSession = .shared
    var timeoutSeconds: TimeInterval = 30
    var appLanguageOverrideProvider: () -> String? = {
        UserDefaults.standard.string(forKey: AppLanguageSettings.userDefaultsKey)
    }
    var codexBridgePreflight: () throws -> Void = {
        try Self.defaultCodexBridgePreflight()
    }
    var codexBridgeRunner: (CodexBridgeRequest, @escaping (_ update: String) -> Void) throws -> String = { request, onProgress in
        try Self.defaultCodexBridgeRunner(request: request, onProgress: onProgress)
    }
    var codexBridgeRecovery: (_ reason: String, _ onProgress: @escaping (_ update: String) -> Void) throws -> Void = { reason, onProgress in
        try Self.defaultCodexBridgeRecovery(reason: reason, onProgress: onProgress)
    }

    init(
        environmentProvider: @escaping () -> [String: String] = { ProcessInfo.processInfo.environment },
        urlSession: URLSession = .shared,
        timeoutSeconds: TimeInterval = 30,
        appLanguageOverrideProvider: @escaping () -> String? = {
            UserDefaults.standard.string(forKey: AppLanguageSettings.userDefaultsKey)
        },
        codexBridgePreflight: @escaping () throws -> Void = {
            try Self.defaultCodexBridgePreflight()
        },
        codexBridgeRunner: @escaping (CodexBridgeRequest, @escaping (_ update: String) -> Void) throws -> String = { request, onProgress in
            try Self.defaultCodexBridgeRunner(request: request, onProgress: onProgress)
        },
        codexBridgeRecovery: @escaping (_ reason: String, _ onProgress: @escaping (_ update: String) -> Void) throws -> Void = { reason, onProgress in
            try Self.defaultCodexBridgeRecovery(reason: reason, onProgress: onProgress)
        }
    ) {
        self.environmentProvider = environmentProvider
        self.urlSession = urlSession
        self.timeoutSeconds = timeoutSeconds
        self.appLanguageOverrideProvider = appLanguageOverrideProvider
        self.codexBridgePreflight = codexBridgePreflight
        self.codexBridgeRunner = codexBridgeRunner
        self.codexBridgeRecovery = codexBridgeRecovery
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
            appLanguageOverrideProvider: {
                UserDefaults.standard.string(forKey: AppLanguageSettings.userDefaultsKey)
            },
            codexBridgePreflight: {
                try Self.defaultCodexBridgePreflight()
            },
            codexBridgeRunner: { request, onProgress in
                try Self.defaultCodexBridgeRunner(request: request, onProgress: onProgress)
            },
            codexBridgeRecovery: { reason, onProgress in
                try Self.defaultCodexBridgeRecovery(reason: reason, onProgress: onProgress)
            }
        )
    }

    func execute(task: WorkTask, agent: AgentProfile) -> AgentTaskExecutionOutcome {
        execute(task: task, agent: agent) { _ in }
    }

    func execute(
        task: WorkTask,
        agent: AgentProfile,
        onProgress: @escaping (_ update: String) -> Void
    ) -> AgentTaskExecutionOutcome {
        if Self.cancellationRegistry.isCancellationRequested(for: task.id) {
            return .failure(message: L10n.string("Execution cancelled by user"))
        }
        let runtimeProfile = agent.runtimeProfile ?? .defaultCodexBridge
        let provider = runtimeProfile.provider
        switch provider {
        case .localMock:
            let summary = L10n.format("Mock run completed by %@ for \"%@\"", agent.name, task.title)
            return .success(summary: summary)
        case .openAICompatible:
            return runOpenAICompatible(
                task: task,
                agent: agent,
                runtimeProfile: runtimeProfile,
                onProgress: onProgress
            )
        }
    }

    func requestCancellation(taskID: UUID) {
        Self.cancellationRegistry.requestCancellation(for: taskID)
    }

    func requestCancellation(taskIDs: [UUID]) {
        let uniqueTaskIDs = Set(taskIDs)
        for taskID in uniqueTaskIDs {
            Self.cancellationRegistry.requestCancellation(for: taskID)
        }
    }

    func clearCancellation(taskID: UUID) {
        Self.cancellationRegistry.clearCancellation(for: taskID)
    }

    private func runOpenAICompatible(
        task: WorkTask,
        agent: AgentProfile,
        runtimeProfile: AgentRuntimeProfile,
        onProgress: @escaping (_ update: String) -> Void
    ) -> AgentTaskExecutionOutcome {
        switch runtimeProfile.openAIAuthMode {
        case .apiKey:
            return runOpenAICompatibleWithAPIKey(
                task: task,
                agent: agent,
                runtimeProfile: runtimeProfile,
                onProgress: onProgress
            )
        case .codexBridge:
            return runOpenAICompatibleWithCodexBridge(
                task: task,
                agent: agent,
                runtimeProfile: runtimeProfile,
                onProgress: onProgress
            )
        }
    }

    private func runOpenAICompatibleWithAPIKey(
        task: WorkTask,
        agent: AgentProfile,
        runtimeProfile: AgentRuntimeProfile,
        onProgress: @escaping (_ update: String) -> Void
    ) -> AgentTaskExecutionOutcome {
        onProgress(L10n.format("OpenAI request started for \"%@\"", task.title))
        let environment = environmentProvider()
        let apiKey = resolvedAPIKey(from: environment)
        guard let apiKey else {
            return .failure(message: L10n.string("Missing OPENAI_API_KEY for OpenAI-compatible runtime"))
        }

        let endpoint = resolvedEndpoint(
            configuredEndpoint: runtimeProfile.endpoint,
            environment: environment
        )
        guard let url = URL(string: endpoint) else {
            return .failure(message: L10n.string("Invalid OpenAI-compatible endpoint"))
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
                return .failure(message: L10n.string("OpenAI-compatible runtime returned empty output"))
            }
            onProgress(L10n.string("OpenAI response received"))
            return .success(summary: summary)
        } catch {
            return .failure(message: L10n.format("OpenAI-compatible run failed: %@", error.localizedDescription))
        }
    }

    private func runOpenAICompatibleWithCodexBridge(
        task: WorkTask,
        agent: AgentProfile,
        runtimeProfile: AgentRuntimeProfile,
        onProgress: @escaping (_ update: String) -> Void
    ) -> AgentTaskExecutionOutcome {
        onProgress(L10n.format("Codex Bridge started for \"%@\"", task.title))
        let environment = environmentProvider()
        let prompt = buildCodexBridgePrompt(task: task, agent: agent, environment: environment)
        let workingDirectoryPath = CodexProjectsDirectorySettings.resolvedProjectsDirectoryPath(
            environment: environment
        )
        let request = CodexBridgeRequest(
            taskID: task.id,
            prompt: prompt,
            model: runtimeProfile.model,
            reasoningEffort: runtimeProfile.codexReasoningEffort.cliValue,
            profile: runtimeProfile.codexProfile,
            workingDirectoryPath: workingDirectoryPath
        )
        let trimmedModel = runtimeProfile.model.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedReasoningEffort = runtimeProfile.codexReasoningEffort.cliValue?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        do {
            try codexBridgePreflight()
            let summary = try codexBridgeRunner(request, onProgress).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !summary.isEmpty else {
                return .failure(message: L10n.string("Codex Bridge returned empty output"))
            }
            return .success(summary: summary)
        } catch {
            let initialRawFailure = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)

            if Self.isCodexUsageLimitError(initialRawFailure) {
                do {
                    try codexBridgeRecovery(initialRawFailure, onProgress)
                    onProgress(L10n.string("Codex app restarted. Retrying interrupted run..."))
                    let recoveredSummary = try codexBridgeRunner(request, onProgress)
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !recoveredSummary.isEmpty else {
                        return .failure(message: L10n.string("Codex Bridge returned empty output"))
                    }
                    return .success(summary: recoveredSummary)
                } catch {
                    let recoveryRawFailure = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
                    let rawFailure = """
                    Initial run failed due to Codex usage limit or quota.
                    \(initialRawFailure)

                    Automatic Codex app restart retry failed.
                    \(recoveryRawFailure)
                    """
                    return codexBridgeFailureOutcome(from: rawFailure)
                }
            }

            // Older Codex CLIs do not support --reasoning-effort.
            // Retry once without this flag to preserve compatibility.
            if !trimmedReasoningEffort.isEmpty,
               Self.isCodexReasoningEffortUnsupported(initialRawFailure) {
                let fallbackRequest = CodexBridgeRequest(
                    taskID: task.id,
                    prompt: prompt,
                    model: runtimeProfile.model,
                    reasoningEffort: nil,
                    profile: runtimeProfile.codexProfile,
                    workingDirectoryPath: workingDirectoryPath
                )
                do {
                    onProgress(L10n.string("Codex CLI does not support reasoning effort flag. Retrying without explicit reasoning effort."))
                    let fallbackSummary = try codexBridgeRunner(fallbackRequest, onProgress)
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !fallbackSummary.isEmpty else {
                        return .failure(message: L10n.string("Codex Bridge returned empty output"))
                    }
                    return .success(summary: fallbackSummary)
                } catch {
                    let fallbackRawFailure = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)

                    if !trimmedModel.isEmpty,
                       Self.isCodexChatGPTModelUnsupported(fallbackRawFailure) {
                        let modelFallbackRequest = CodexBridgeRequest(
                            taskID: task.id,
                            prompt: prompt,
                            model: "",
                            reasoningEffort: nil,
                            profile: runtimeProfile.codexProfile,
                            workingDirectoryPath: workingDirectoryPath
                        )
                        do {
                            onProgress(L10n.string("Configured model rejected by Codex account. Retrying without explicit model."))
                            let modelFallbackSummary = try codexBridgeRunner(modelFallbackRequest, onProgress)
                                .trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !modelFallbackSummary.isEmpty else {
                                return .failure(message: L10n.string("Codex Bridge returned empty output"))
                            }
                            return .success(summary: modelFallbackSummary)
                        } catch {
                            let modelFallbackRawFailure = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
                            let rawFailure = """
                            Initial run failed because current Codex CLI does not support --reasoning-effort.
                            \(initialRawFailure)

                            Retry without reasoning effort failed due to configured model.
                            \(fallbackRawFailure)

                            Retry without reasoning effort and without explicit model also failed.
                            \(modelFallbackRawFailure)
                            """
                            return codexBridgeFailureOutcome(from: rawFailure)
                        }
                    }

                    let rawFailure = """
                    Initial run failed because current Codex CLI does not support --reasoning-effort.
                    \(initialRawFailure)

                    Fallback run without reasoning effort failed.
                    \(fallbackRawFailure)
                    """
                    return codexBridgeFailureOutcome(from: rawFailure)
                }
            }

            // ChatGPT account login with Codex may reject some API models (for example gpt-4.1-mini).
            // Retry once without --model so Codex profile default can be used automatically.
            if !trimmedModel.isEmpty,
               Self.isCodexChatGPTModelUnsupported(initialRawFailure) {
                let fallbackRequest = CodexBridgeRequest(
                    taskID: task.id,
                    prompt: prompt,
                    model: "",
                    reasoningEffort: runtimeProfile.codexReasoningEffort.cliValue,
                    profile: runtimeProfile.codexProfile,
                    workingDirectoryPath: workingDirectoryPath
                )
                do {
                    onProgress(L10n.string("Configured model rejected by Codex account. Retrying without explicit model."))
                    let fallbackSummary = try codexBridgeRunner(fallbackRequest, onProgress)
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !fallbackSummary.isEmpty else {
                        return .failure(message: L10n.string("Codex Bridge returned empty output"))
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
            return .failure(message: L10n.format("Codex Bridge run failed: %@", summary))
        }
        return .failure(
            message: L10n.format("Codex Bridge run failed: %@", summary) + "\(Self.debugLogDelimiter)\(rawFailure)"
        )
    }

    private static func isCodexChatGPTModelUnsupported(_ rawFailure: String) -> Bool {
        let normalized = rawFailure.lowercased()
        return normalized.contains("model is not supported when using codex with a chatgpt account")
    }

    private static func isCodexReasoningEffortUnsupported(_ rawFailure: String) -> Bool {
        let normalized = rawFailure.lowercased()
        if normalized.contains("unexpected argument '--reasoning-effort'") { return true }
        if normalized.contains("unknown option '--reasoning-effort'") { return true }
        if normalized.contains("unrecognized option '--reasoning-effort'") { return true }
        return false
    }

    private static func isCodexUsageLimitError(_ rawFailure: String) -> Bool {
        let normalized = rawFailure.lowercased()
        if normalized.contains("insufficient_quota") { return true }
        if normalized.contains("quota exceeded") { return true }
        if normalized.contains("usage limit") { return true }
        if normalized.contains("rate limit exceeded") { return true }
        if normalized.contains("remaining usage") && normalized.contains("insufficient") { return true }
        if normalized.contains("insufficient") && normalized.contains("credit") { return true }
        if normalized.contains("billing hard limit") { return true }
        return false
    }

    private static func summarizeCodexBridgeFailure(_ rawFailure: String) -> String {
        let trimmed = rawFailure.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return L10n.string("Unknown Codex Bridge error")
        }

        let normalized = trimmed.lowercased()
        if isCodexChatGPTModelUnsupported(trimmed) {
            return L10n.string("Configured model is not supported for Codex Bridge with ChatGPT login. Leave model blank to use Codex default, or switch to a Codex-supported model.")
        }
        if isCodexReasoningEffortUnsupported(trimmed) {
            return L10n.string("Current Codex CLI does not support reasoning effort flag. Update Codex CLI or set reasoning effort to Automatic.")
        }
        if isCodexUsageLimitError(trimmed) {
            return L10n.string("Codex usage limit/quota appears exhausted. OpenMac attempted a Codex app restart and retry once. Please wait for quota reset or top up usage, then retry.")
        }
        if normalized.contains("401 unauthorized") || normalized.contains("missing bearer or basic authentication") {
            let loginCommand = codexLoginCommandForCurrentProfile()
            return L10n.format("Codex Bridge authentication missing. Run this once in Terminal: %@", loginCommand)
        }
        if normalized.contains("operation not permitted") {
            let loginCommand = codexLoginCommandForCurrentProfile()
            return L10n.format("Permission denied while accessing Codex profile. Run this once in Terminal with the app container profile: %@", loginCommand)
        }
        if normalized.contains("failed to connect to websocket"),
           normalized.contains("lookup address information") || normalized.contains("nodename nor servname provided") {
            return L10n.string("Network/DNS lookup failed while Codex Bridge contacted OpenAI. Check internet, DNS/proxy settings, and outgoing network permission.")
        }
        if normalized.contains("failed to connect to websocket") {
            return L10n.string("Codex Bridge could not connect to OpenAI. Check internet/proxy settings and retry.")
        }
        if normalized.contains("codex login") || normalized.contains("not logged in") {
            let loginCommand = codexLoginCommandForCurrentProfile()
            return L10n.format("Codex Bridge requires login. Run this once in Terminal: %@", loginCommand)
        }
        if normalized.contains("no such file or directory"), normalized.contains("codex") {
            return L10n.string("Codex CLI not found. Install Codex CLI or set CODEX_CLI_PATH.")
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
        let template = executionPromptTemplate()
        let userPrompt = executionPrompt(
            task: task,
            agent: agent,
            template: template,
            environment: environmentProvider()
        )
        return [
            ChatMessage(role: "system", content: template.systemPrompt),
            ChatMessage(role: "user", content: userPrompt)
        ]
    }

    private func buildCodexBridgePrompt(
        task: WorkTask,
        agent: AgentProfile,
        environment: [String: String]
    ) -> String {
        let template = executionPromptTemplate()
        return executionPrompt(task: task, agent: agent, template: template, environment: environment)
    }

    private func executionPrompt(
        task: WorkTask,
        agent: AgentProfile,
        template: ExecutionPromptTemplate,
        environment: [String: String]
    ) -> String {
        let sortedSkills = task.requiredSkills.sorted().joined(separator: ", ")
        let skillsLine = sortedSkills.isEmpty ? template.noneSkillsText : sortedSkills
        let deliveryContract = task.resolvedDeliveryContract
        let expectedEvidence = deliveryContract.requiredArtifactsText.isEmpty
            ? "none"
            : deliveryContract.requiredArtifactsText
        let codexSkillSection = codexSkillPromptSection(task: task, agent: agent, environment: environment)
        let codexSkillSectionBlock = codexSkillSection.isEmpty ? "" : "\n\n\(codexSkillSection)"
        return """
        \(template.preamble)
        \(template.agentLabel): \(agent.name)
        \(template.taskTitleLabel): \(task.title)
        \(template.taskDetailsLabel): \(task.details)
        \(template.requiredSkillsLabel): \(skillsLine)
        \(template.storyPointsLabel): \(task.storyPoints)
        Delivery output type: \(deliveryContract.outputType.title)
        Completion gate: \(deliveryContract.gateMode.title) / \(deliveryContract.artifactRule.title)
        Expected evidence: \(expectedEvidence)
        \(template.filesystemGuardrailsSection)
        \(codexSkillSectionBlock)

        \(template.sectionsInstruction)
        \(template.languageInstruction)
        \(template.summarySection)
        \(template.actionsSection)
        \(template.evidenceSection)
        \(template.risksSection)
        """
    }

    private func codexSkillPromptSection(
        task: WorkTask,
        agent: AgentProfile,
        environment: [String: String]
    ) -> String {
        guard let runtimeProfile = agent.runtimeProfile else { return "" }
        let requestedSkills = codexSkillNames(from: runtimeProfile)
        guard !requestedSkills.isEmpty else { return "" }

        let resolvedSkills = resolvedCodexSkillReferences(skillNames: requestedSkills, environment: environment)
        let allReferences = resolvedSkills.map { reference in
            if let path = reference.path {
                return "- [$\(reference.name)](\(path))"
            }
            return "- $\(reference.name)"
        }.joined(separator: "\n")

        let taskSkillsHint = task.requiredSkills.sorted().joined(separator: ", ")
        let requiredSkillsHint = taskSkillsHint.isEmpty ? "none" : taskSkillsHint
        return """
        Codex skills for this run (enabled via `skill:<name>` in agent tools):
        \(allReferences)
        Use these skills as operating instructions when relevant to the task.
        If a skill is missing/unavailable, continue execution and mention it in Risks or blockers.
        Task required skills hint: \(requiredSkillsHint)
        """
    }

    private func codexSkillNames(from runtimeProfile: AgentRuntimeProfile) -> [String] {
        let prefix = "skill:"
        var seen = Set<String>()
        var names: [String] = []
        for tool in runtimeProfile.tools.sorted() {
            guard tool.hasPrefix(prefix) else { continue }
            let name = String(tool.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { continue }
            guard !seen.contains(name) else { continue }
            seen.insert(name)
            names.append(name)
        }
        return names
    }

    private func resolvedCodexSkillReferences(
        skillNames: [String],
        environment: [String: String]
    ) -> [(name: String, path: String?)] {
        let candidateRoots = codexSkillRootDescriptors(environment: environment)
        let fileManager = FileManager.default
        return skillNames.map { name in
            if let path = CodexSkillCatalog.resolveSkillPath(
                skillName: name,
                rootDescriptors: candidateRoots,
                fileManager: fileManager
            ) {
                return (name: name, path: path)
            }
            return (name: name, path: nil)
        }
    }

    private func codexSkillRootDescriptors(environment: [String: String]) -> [CodexSkillRootDescriptor] {
        CodexSkillCatalog.rootDescriptors(
            environment: environment,
            fallbackHomeDirectoryPath: NSHomeDirectory()
        )
    }

    private func executionPromptTemplate() -> ExecutionPromptTemplate {
        switch AppLanguageResolver.resolvedLanguage(overrideRawValue: appLanguageOverrideProvider()) {
        case .english:
            return ExecutionPromptTemplate(
                systemPrompt: "You are an autonomous software execution agent. Respond with concise plain text in English.",
                preamble: "You are supporting an assigned AI agent in a kanban execution system.",
                agentLabel: "Agent",
                taskTitleLabel: "Task title",
                taskDetailsLabel: "Task details",
                requiredSkillsLabel: "Required skills",
                storyPointsLabel: "Story points",
                sectionsInstruction: "Return plain text using these sections:",
                languageInstruction: "Use English for all section titles and narrative text. Do not mix multiple natural languages unless quoting user-provided text.",
                filesystemGuardrailsSection: """
                Filesystem guardrails:
                - Treat the current working directory as the only project root.
                - Use relative paths only (`./...`); never create paths that start with `/Users/`, `/Volumes/`, `/private/`, `/tmp/`, or a drive root like `C:\\`.
                - If task text includes absolute paths, treat them as reference only and write outputs into the current working directory.
                - Strip accidental surrounding quotes from filenames (for example `AppState.swift"`).
                """,
                summarySection: "Summary:",
                actionsSection: "Actions taken:",
                evidenceSection: "Evidence (files/commands/results):",
                risksSection: "Risks or blockers:",
                noneSkillsText: "none"
            )
        case .traditionalChinese:
            return ExecutionPromptTemplate(
                systemPrompt: "You are an autonomous software execution agent. Respond with concise plain text in Traditional Chinese.",
                preamble: "你正在看板執行系統中支援一位已指派的 AI 代理。",
                agentLabel: "代理",
                taskTitleLabel: "任務標題",
                taskDetailsLabel: "任務細節",
                requiredSkillsLabel: "所需技能",
                storyPointsLabel: "故事點數",
                sectionsInstruction: "請用純文字並使用以下段落：",
                languageInstruction: "請使用繁體中文撰寫所有段落標題與敘述內容，除非是引用使用者原文或程式碼，否則不要混用英文。",
                filesystemGuardrailsSection: """
                檔案系統規則：
                - 目前工作目錄是唯一專案根目錄。
                - 只可使用相對路徑（`./...`）；不要建立以 `/Users/`、`/Volumes/`、`/private/`、`/tmp/` 或 Windows 磁碟根（如 `C:\\`）開頭的路徑。
                - 若任務文字含絕對路徑，只視為參考，實際輸出請寫在目前工作目錄內。
                - 檔名若出現誤帶引號（例如 `AppState.swift"`），請先去除引號再建立檔案。
                """,
                summarySection: "摘要：",
                actionsSection: "已執行動作：",
                evidenceSection: "證據（檔案／指令／結果）：",
                risksSection: "風險或阻塞：",
                noneSkillsText: "無"
            )
        case .simplifiedChinese:
            return ExecutionPromptTemplate(
                systemPrompt: "You are an autonomous software execution agent. Respond with concise plain text in Simplified Chinese.",
                preamble: "你正在看板执行系统中支持一位已分配的 AI 代理。",
                agentLabel: "代理",
                taskTitleLabel: "任务标题",
                taskDetailsLabel: "任务细节",
                requiredSkillsLabel: "所需技能",
                storyPointsLabel: "故事点数",
                sectionsInstruction: "请用纯文本并使用以下段落：",
                languageInstruction: "请使用简体中文撰写所有段落标题与叙述内容，除非是引用用户原文或代码，否则不要混用英文。",
                filesystemGuardrailsSection: """
                文件系统规则：
                - 当前工作目录是唯一项目根目录。
                - 仅使用相对路径（`./...`）；不要创建以 `/Users/`、`/Volumes/`、`/private/`、`/tmp/` 或 Windows 盘符根（如 `C:\\`）开头的路径。
                - 若任务文本包含绝对路径，只作为参考，实际输出写入当前工作目录。
                - 文件名若误带引号（例如 `AppState.swift"`），请先去掉引号再创建文件。
                """,
                summarySection: "摘要：",
                actionsSection: "已执行动作：",
                evidenceSection: "证据（文件/命令/结果）：",
                risksSection: "风险或阻塞：",
                noneSkillsText: "无"
            )
        case .french:
            return ExecutionPromptTemplate(
                systemPrompt: "You are an autonomous software execution agent. Respond with concise plain text in French.",
                preamble: "Vous assistez un agent IA assigne dans un systeme d'execution kanban.",
                agentLabel: "Agent",
                taskTitleLabel: "Titre de la tache",
                taskDetailsLabel: "Details de la tache",
                requiredSkillsLabel: "Competences requises",
                storyPointsLabel: "Points d'histoire",
                sectionsInstruction: "Repondez en texte brut avec les sections suivantes :",
                languageInstruction: "Utilisez le francais pour tous les titres et le texte narratif. N'utilisez pas plusieurs langues sauf citation explicite du contenu utilisateur.",
                filesystemGuardrailsSection: """
                Regles de systeme de fichiers :
                - Traitez le repertoire de travail courant comme unique racine du projet.
                - Utilisez uniquement des chemins relatifs (`./...`) ; ne creez jamais de chemins commencant par `/Users/`, `/Volumes/`, `/private/`, `/tmp/` ou une racine de lecteur comme `C:\\`.
                - Si la tache contient des chemins absolus, utilisez-les seulement comme reference et ecrivez les sorties dans le repertoire courant.
                - Supprimez les guillemets accidentels autour des noms de fichiers (par exemple `AppState.swift"`).
                """,
                summarySection: "Resume :",
                actionsSection: "Actions realisees :",
                evidenceSection: "Preuves (fichiers/commandes/resultats) :",
                risksSection: "Risques ou blocages :",
                noneSkillsText: "aucune"
            )
        case .spanish:
            return ExecutionPromptTemplate(
                systemPrompt: "You are an autonomous software execution agent. Respond with concise plain text in Spanish.",
                preamble: "Estas apoyando a un agente de IA asignado en un sistema kanban de ejecucion.",
                agentLabel: "Agente",
                taskTitleLabel: "Titulo de la tarea",
                taskDetailsLabel: "Detalles de la tarea",
                requiredSkillsLabel: "Habilidades requeridas",
                storyPointsLabel: "Puntos de historia",
                sectionsInstruction: "Devuelve texto plano con estas secciones:",
                languageInstruction: "Usa espanol en todos los titulos de seccion y en la narrativa. No mezcles idiomas salvo para citas textuales del contenido del usuario.",
                filesystemGuardrailsSection: """
                Reglas del sistema de archivos:
                - Usa el directorio de trabajo actual como unica raiz del proyecto.
                - Usa solo rutas relativas (`./...`); no crees rutas que empiecen por `/Users/`, `/Volumes/`, `/private/`, `/tmp/` o una raiz de unidad como `C:\\`.
                - Si la tarea incluye rutas absolutas, tomalas solo como referencia y escribe la salida dentro del directorio actual.
                - Quita comillas accidentales en nombres de archivo (por ejemplo `AppState.swift"`).
                """,
                summarySection: "Resumen:",
                actionsSection: "Acciones realizadas:",
                evidenceSection: "Evidencia (archivos/comandos/resultados):",
                risksSection: "Riesgos o bloqueos:",
                noneSkillsText: "ninguna"
            )
        case .japanese:
            return ExecutionPromptTemplate(
                systemPrompt: "You are an autonomous software execution agent. Respond with concise plain text in Japanese.",
                preamble: "あなたはカンバン実行システムで割り当て済みの AI エージェントを支援しています。",
                agentLabel: "エージェント",
                taskTitleLabel: "タスクタイトル",
                taskDetailsLabel: "タスク詳細",
                requiredSkillsLabel: "必要スキル",
                storyPointsLabel: "ストーリーポイント",
                sectionsInstruction: "次の見出しで簡潔なプレーンテキストを返してください:",
                languageInstruction: "見出しと本文は日本語で統一してください。ユーザー原文やコードの引用以外で英語を混在させないでください。",
                filesystemGuardrailsSection: """
                ファイルシステム規則:
                - 現在の作業ディレクトリのみをプロジェクトルートとして扱ってください。
                - 相対パス（`./...`）のみを使用し、`/Users/`、`/Volumes/`、`/private/`、`/tmp/`、または `C:\\` のようなドライブルートから始まるパスを作成しないでください。
                - タスク本文に絶対パスがあっても参照情報として扱い、出力は現在の作業ディレクトリ配下に書き込んでください。
                - ファイル名の誤った引用符（例: `AppState.swift"`）は除去してから作成してください。
                """,
                summarySection: "要約:",
                actionsSection: "実施した内容:",
                evidenceSection: "証拠（ファイル/コマンド/結果）:",
                risksSection: "リスクまたはブロッカー:",
                noneSkillsText: "なし"
            )
        case .korean:
            return ExecutionPromptTemplate(
                systemPrompt: "You are an autonomous software execution agent. Respond with concise plain text in Korean.",
                preamble: "당신은 칸반 실행 시스템에서 할당된 AI 에이전트를 지원하고 있습니다.",
                agentLabel: "에이전트",
                taskTitleLabel: "작업 제목",
                taskDetailsLabel: "작업 세부사항",
                requiredSkillsLabel: "필수 스킬",
                storyPointsLabel: "스토리 포인트",
                sectionsInstruction: "다음 섹션으로 간결한 일반 텍스트를 반환하세요:",
                languageInstruction: "모든 섹션 제목과 본문은 한국어로 작성하세요. 사용자 원문이나 코드 인용을 제외하고 다른 언어를 섞지 마세요.",
                filesystemGuardrailsSection: """
                파일 시스템 규칙:
                - 현재 작업 디렉터리만 프로젝트 루트로 사용하세요.
                - 상대 경로(`./...`)만 사용하고, `/Users/`, `/Volumes/`, `/private/`, `/tmp/` 또는 `C:\\` 같은 드라이브 루트로 시작하는 경로를 만들지 마세요.
                - 작업 설명에 절대 경로가 있어도 참고 정보로만 사용하고, 실제 출력은 현재 작업 디렉터리 안에 작성하세요.
                - 파일명에 잘못 붙은 따옴표(예: `AppState.swift"`)는 제거한 뒤 파일을 생성하세요.
                """,
                summarySection: "요약:",
                actionsSection: "수행한 작업:",
                evidenceSection: "근거 (파일/명령/결과):",
                risksSection: "위험 또는 차단 요인:",
                noneSkillsText: "없음"
            )
        }
    }

    private struct ExecutionPromptTemplate {
        let systemPrompt: String
        let preamble: String
        let agentLabel: String
        let taskTitleLabel: String
        let taskDetailsLabel: String
        let requiredSkillsLabel: String
        let storyPointsLabel: String
        let sectionsInstruction: String
        let languageInstruction: String
        let filesystemGuardrailsSection: String
        let summarySection: String
        let actionsSection: String
        let evidenceSection: String
        let risksSection: String
        let noneSkillsText: String
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
                return L10n.string("Request timed out")
            case .invalidResponse:
                return L10n.string("Invalid response")
            case .emptyResponse:
                return L10n.string("Empty response")
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

    private static func defaultCodexBridgeRunner(
        request: CodexBridgeRequest,
        onProgress: @escaping (_ update: String) -> Void,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> String {
        if cancellationRegistry.isCancellationRequested(for: request.taskID) {
            throw ExecutorError.codexBridgeFailed(L10n.string("Execution cancelled by user"))
        }
        guard let codexExecutable = resolvedCodexExecutableURL(environment: environment) else {
            throw ExecutorError.codexBridgeFailed(
                L10n.string("Codex CLI not found. Install Codex CLI (or Codex app), then retry. You can also switch OpenAI Auth to API Key.")
            )
        }

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("openmac-codex-bridge-\(UUID().uuidString).txt")
        defer {
            try? FileManager.default.removeItem(at: outputURL)
        }

        let sandboxMode = resolvedCodexBridgeSandboxMode(environment: environment)
        var arguments = [
            "exec",
            "--skip-git-repo-check",
            "--json",
            "--output-last-message", outputURL.path
        ]
        if let sandboxMode {
            arguments.append(contentsOf: ["--sandbox", sandboxMode])
        }
        if !request.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            arguments.append(contentsOf: ["--model", request.model])
        }
        if let reasoningEffort = request.reasoningEffort?.trimmingCharacters(in: .whitespacesAndNewlines),
           !reasoningEffort.isEmpty {
            arguments.append(contentsOf: ["--reasoning-effort", reasoningEffort])
        }
        if let profile = request.profile?.trimmingCharacters(in: .whitespacesAndNewlines), !profile.isEmpty {
            arguments.append(contentsOf: ["--profile", profile])
        }
        arguments.append(request.prompt)

        let process = Process()
        process.executableURL = codexExecutable
        process.arguments = arguments
        process.environment = codexBridgeProcessEnvironment(environment: environment)
        let configuredWorkdirPath = request.workingDirectoryPath
            ?? CodexProjectsDirectorySettings.resolvedProjectsDirectoryPath()
        let workingDirectoryURL: URL
        do {
            workingDirectoryURL = try CodexProjectsDirectorySettings.ensureProjectsDirectoryExists(
                at: configuredWorkdirPath
            )
        } catch {
            throw ExecutorError.codexBridgeFailed(
                L10n.format("Unable to prepare projects folder at %@: %@", configuredWorkdirPath, error.localizedDescription)
            )
        }
        process.currentDirectoryURL = workingDirectoryURL
        onProgress(L10n.format("Codex workdir: %@", workingDirectoryURL.path))

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = outputPipe
        let outputHandle = outputPipe.fileHandleForReading
        let streamStateQueue = DispatchQueue(label: "openmac.codex.stream-state")
        let heartbeatQueue = DispatchQueue(label: "openmac.codex.heartbeat")
        var bufferedOutput = ""
        var rawOutputLines: [String] = []
        var lastProgressDate = Date()

        func appendStreamChunk(_ chunk: String) {
            guard !chunk.isEmpty else { return }

            var completedLines: [String] = []
            streamStateQueue.sync {
                bufferedOutput += chunk
                while let newlineRange = bufferedOutput.range(of: "\n") {
                    let line = String(bufferedOutput[..<newlineRange.lowerBound])
                    completedLines.append(line)
                    bufferedOutput.removeSubrange(bufferedOutput.startIndex ... newlineRange.lowerBound)
                }
            }

            for line in completedLines {
                handleStreamLine(line)
            }
        }

        func handleStreamLine(_ line: String) {
            let normalized = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalized.isEmpty else { return }

            streamStateQueue.sync {
                rawOutputLines.append(normalized)
            }

            if let progressUpdate = codexProgressUpdate(from: normalized) {
                onProgress(progressUpdate)
                streamStateQueue.sync {
                    lastProgressDate = Date()
                }
            }
        }

        let heartbeatInterval: TimeInterval = 8
        let heartbeatTimer = DispatchSource.makeTimerSource(queue: heartbeatQueue)
        heartbeatTimer.schedule(
            deadline: .now() + heartbeatInterval,
            repeating: heartbeatInterval
        )
        heartbeatTimer.setEventHandler {
            let elapsedSeconds: Int = streamStateQueue.sync {
                Int(Date().timeIntervalSince(lastProgressDate).rounded())
            }
            guard elapsedSeconds >= Int(heartbeatInterval) else { return }
            onProgress("Codex still running... (\(elapsedSeconds)s)")
            streamStateQueue.sync {
                lastProgressDate = Date()
            }
        }
        heartbeatTimer.resume()
        defer {
            heartbeatTimer.cancel()
        }

        outputHandle.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            guard let chunk = String(data: data, encoding: .utf8) else { return }
            appendStreamChunk(chunk)
        }

        try process.run()
        cancellationRegistry.register(process: process, for: request.taskID)
        defer {
            cancellationRegistry.unregister(taskID: request.taskID, process: process)
        }
        process.waitUntilExit()
        outputHandle.readabilityHandler = nil

        let trailingOutputData = outputHandle.readDataToEndOfFile()
        if let trailingOutput = String(data: trailingOutputData, encoding: .utf8), !trailingOutput.isEmpty {
            appendStreamChunk(trailingOutput)
        }

        let bufferedRemainder = streamStateQueue.sync { () -> String in
            let remainder = bufferedOutput
            bufferedOutput = ""
            return remainder
        }
        if !bufferedRemainder.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            handleStreamLine(bufferedRemainder)
        }

        let rawOutput = streamStateQueue.sync {
            rawOutputLines.joined(separator: "\n")
        }
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if cancellationRegistry.isCancellationRequested(for: request.taskID) {
            throw ExecutorError.codexBridgeFailed(L10n.string("Execution cancelled by user"))
        }

        guard process.terminationStatus == 0 else {
            let message = rawOutput.isEmpty ? L10n.format("codex exited with code %d", process.terminationStatus) : rawOutput
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

    static func codexProgressUpdate(from rawLine: String) -> String? {
        let normalized = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return nil }

        guard normalized.first == "{",
              let data = normalized.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String else {
            return normalized
        }

        if let item = json["item"] as? [String: Any],
           let event = progressUpdateFromItemEvent(type: type, item: item) {
            return event
        }

        if let errorObject = json["error"] as? [String: Any],
           let message = nonEmptyString(in: errorObject, keys: ["message", "detail", "error"]) {
            return "Codex error: \(message)"
        }

        if let errorMessage = nonEmptyString(in: json, keys: ["error_message", "error", "message", "detail", "text"]) {
            return type.lowercased().contains("error") ? "Codex error: \(errorMessage)" : errorMessage
        }

        return nil
    }

    private static func progressUpdateFromItemEvent(type: String, item: [String: Any]) -> String? {
        guard let itemType = item["type"] as? String else { return nil }

        switch type {
        case "item.started":
            if itemType == "command_execution",
               let command = nonEmptyString(in: item, keys: ["command"]) {
                return "Running command: \(command)"
            }
            return nil

        case "item.updated", "item.delta":
            if itemType == "agent_message",
               let text = nonEmptyString(in: item, keys: ["text", "delta", "content"]) {
                return text
            }
            if itemType == "command_execution",
               let output = nonEmptyString(in: item, keys: ["output_delta", "stdout", "stderr", "output"]) {
                return summarizeCommandOutputForConsole(output, maxLines: 4, maxCharacters: 400)
            }
            return nil

        case "item.completed":
            if itemType == "agent_message",
               let text = nonEmptyString(in: item, keys: ["text", "content"]) {
                return text
            }

            if itemType == "command_execution" {
                var progressParts: [String] = []
                if let command = nonEmptyString(in: item, keys: ["command"]) {
                    progressParts.append("Command completed: \(command)")
                }
                if let output = nonEmptyString(in: item, keys: ["aggregated_output", "output", "stdout", "stderr"]) {
                    progressParts.append(summarizeCommandOutputForConsole(output))
                }
                return progressParts.isEmpty ? nil : progressParts.joined(separator: "\n")
            }
            return nil

        default:
            return nil
        }
    }

    private static func nonEmptyString(in object: [String: Any], keys: [String]) -> String? {
        for key in keys {
            if let value = object[key] as? String {
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    return trimmed
                }
            }
        }
        return nil
    }

    static func summarizeCommandOutputForConsole(
        _ output: String,
        maxLines: Int = 8,
        maxCharacters: Int = 1200
    ) -> String {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        let lines = trimmed
            .split(whereSeparator: \.isNewline)
            .map(String.init)
        let limitedLines = Array(lines.prefix(maxLines))
        var summarized = limitedLines.joined(separator: "\n")

        if lines.count > maxLines {
            summarized += "\n..."
        }

        if summarized.count > maxCharacters {
            let endIndex = summarized.index(summarized.startIndex, offsetBy: maxCharacters)
            summarized = String(summarized[..<endIndex]) + "..."
        }

        return summarized
    }

    private static func defaultCodexBridgePreflight(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws {
        guard resolvedCodexExecutableURL(environment: environment) != nil else {
            throw ExecutorError.codexBridgeFailed(
                L10n.string("Codex CLI not found. Install Codex CLI (or Codex app), then retry. You can also switch OpenAI Auth to API Key.")
            )
        }

        let loginStatus = try runCodex(arguments: ["login", "status"], environment: environment)
        let normalized = loginStatus.output.lowercased()
        guard loginStatus.code == 0, normalized.contains("logged in") else {
            let loginCommand = codexLoginCommandForCurrentProfile(environment: environment)
            throw ExecutorError.codexBridgeFailed(
                L10n.format("Codex Bridge profile is not logged in. Run this once in Terminal: %@", loginCommand)
            )
        }
    }

    private static func defaultCodexBridgeRecovery(
        reason: String,
        onProgress: @escaping (_ update: String) -> Void,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        commandRunner: (
            _ executablePath: String,
            _ arguments: [String],
            _ environment: [String: String]
        ) throws -> (code: Int32, output: String) = { executablePath, arguments, environment in
            try runSystemCommand(
                executablePath: executablePath,
                arguments: arguments,
                environment: environment
            )
        },
        sleeper: (_ seconds: TimeInterval) -> Void = { Thread.sleep(forTimeInterval: $0) }
    ) throws {
        onProgress(L10n.string("Codex usage limit detected. Restarting Codex app..."))

        _ = try? commandRunner(
            "/usr/bin/osascript",
            ["-e", "tell application \"Codex\" to quit"],
            environment
        )

        sleeper(1.0)

        let launch = try commandRunner(
            "/usr/bin/open",
            ["-a", "Codex"],
            environment
        )
        guard launch.code == 0 else {
            let output = launch.output.isEmpty ? L10n.format("open exited with code %d", launch.code) : launch.output
            throw ExecutorError.codexBridgeFailed(L10n.format("Codex app restart failed: %@", output))
        }

        sleeper(1.5)
        onProgress(L10n.string("Codex app restart complete. Resuming task..."))
    }

    private static func runCodex(
        arguments: [String],
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> (code: Int32, output: String) {
        guard let executableURL = resolvedCodexExecutableURL(environment: environment) else {
            throw ExecutorError.codexBridgeFailed(
                L10n.string("Codex CLI not found. Install Codex CLI (or Codex app), then retry. You can also switch OpenAI Auth to API Key.")
            )
        }

        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        process.environment = codexBridgeProcessEnvironment(environment: environment)

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

    private static func runSystemCommand(
        executablePath: String,
        arguments: [String],
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> (code: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        process.environment = codexBridgeProcessEnvironment(environment: environment)

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

    private static func resolvedCodexExecutableURL(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fallbackCandidates: [String]? = nil,
        fileManager: FileManager = .default,
        homeDirectoryPath: String = NSHomeDirectory()
    ) -> URL? {
        if let explicitPath = environment["CODEX_CLI_PATH"]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !explicitPath.isEmpty,
           fileManager.isExecutableFile(atPath: explicitPath) {
            return URL(fileURLWithPath: explicitPath)
        }

        let pathValue = environment["PATH"] ?? ""
        let pathCandidates = pathValue
            .split(separator: ":")
            .map { String($0) }
            .filter { !$0.isEmpty }
            .map { directory in
                (directory as NSString).appendingPathComponent("codex")
            }

        let resolvedFallbackCandidates = fallbackCandidates ?? [
            "/Applications/Codex.app/Contents/Resources/codex",
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex",
            (homeDirectoryPath as NSString).appendingPathComponent(".local/bin/codex")
        ]

        for candidate in pathCandidates + resolvedFallbackCandidates where fileManager.isExecutableFile(atPath: candidate) {
            return URL(fileURLWithPath: candidate)
        }

        return nil
    }

    private static func resolvedCodexBridgeSandboxMode(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> String? {
        let rawOverride = environment["OPENMAC_CODEX_SANDBOX"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""

        if rawOverride.isEmpty {
            return "danger-full-access"
        }

        let normalized = rawOverride.replacingOccurrences(of: "_", with: "-")
        switch normalized {
        case "danger-full-access", "workspace-write", "read-only":
            return normalized
        case "none", "off", "disable", "disabled":
            return nil
        default:
            return "danger-full-access"
        }
    }


    private static func codexBridgeProcessEnvironment(
        environment sourceEnvironment: [String: String] = ProcessInfo.processInfo.environment
    ) -> [String: String] {
        var environment = sourceEnvironment
        if let codexHome = environment["CODEX_HOME"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           codexHome.isEmpty {
            environment["CODEX_HOME"] = nil
        }
        let homePath = environment["HOME"] ?? NSHomeDirectory()
        let additionalPathDirectories = [
            resolvedCodexExecutableURL(environment: environment, homeDirectoryPath: homePath)?
                .deletingLastPathComponent().path,
            "\(homePath)/.codex/bin",
            "/opt/homebrew/bin",
            "/usr/local/bin"
        ]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if let mergedPath = mergedPATH(
            prependingDirectories: additionalPathDirectories,
            existingPath: environment["PATH"]
        ) {
            environment["PATH"] = mergedPath
        }
        return environment
    }

    private static func mergedPATH(
        prependingDirectories directories: [String],
        existingPath: String?,
        fileManager: FileManager = .default
    ) -> String? {
        var orderedPaths: [String] = []
        var seen = Set<String>()

        for directory in directories {
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: directory, isDirectory: &isDirectory),
                  isDirectory.boolValue else {
                continue
            }
            guard seen.insert(directory).inserted else { continue }
            orderedPaths.append(directory)
        }

        let existingSegments = (existingPath ?? "")
            .split(separator: ":")
            .map { String($0) }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        for segment in existingSegments where seen.insert(segment).inserted {
            orderedPaths.append(segment)
        }

        guard !orderedPaths.isEmpty else { return nil }
        return orderedPaths.joined(separator: ":")
    }

    private static func codexLoginCommandForCurrentProfile(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectoryPath: String = NSHomeDirectory()
    ) -> String {
        let home = environment["HOME"] ?? homeDirectoryPath
        let codexHome = environment["CODEX_HOME"] ?? "\(home)/.codex"
        return "HOME=\"\(home)\" CODEX_HOME=\"\(codexHome)\" codex login --device-auth"
    }
}

struct AgentExecutionEvent: Identifiable, Equatable {
    let id: UUID
    let timestamp: Date
    let agentID: UUID
    let taskID: UUID
    let taskTitle: String
    let status: TaskExecutionStatus
    let phase: ExecutionEventPhase
    let message: String
    let details: String?

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        agentID: UUID,
        taskID: UUID,
        taskTitle: String,
        status: TaskExecutionStatus,
        phase: ExecutionEventPhase = .progress,
        message: String,
        details: String? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.agentID = agentID
        self.taskID = taskID
        self.taskTitle = taskTitle
        self.status = status
        self.phase = phase
        self.message = message
        self.details = details
    }
}

enum ExecutionEventPhase: String, CaseIterable, Equatable {
    case lifecycle
    case progress
    case result
    case governance
    case system
}

final class KanbanBoardViewModel: ObservableObject {
    typealias ExecutionDispatcher = (@escaping () -> Void) -> Void
    typealias GitCommandRunner = GitHubPRFlowUseCase.CommandRunner
    private struct PMCreatedTaskDescriptor {
        let taskID: UUID
        let milestone: String
        let epic: String
    }

    private struct PMExtensionHookWorkItem {
        let key: String
        let event: PMExtensionHookEvent
        let descriptor: PMExtensionCommandDescriptor
        let task: WorkTask?
        let extensionInputs: [String: String]
        let retryCount: Int
    }

    private struct PMExtensionMutableStats {
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

    private struct ExecutionReportTaskEntry: Codable {
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

    private struct ExecutionReportDocument: Codable {
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
    @Published private(set) var lastGitHubPRURL: String?
    @Published private(set) var lastGitHubPRLog: String?
    @Published private(set) var lastAutoCycleCreatedDependencyTaskCount = 0
    @Published private(set) var isBatchRunCancelRequested = false
    @Published private(set) var isAutoCycleCancelRequested = false
    @Published private(set) var wipLimits: [KanbanStatus: Int]
    @Published var agents: [AgentProfile]
    @Published private(set) var taskTemplates: [TaskTemplate]
    @Published private(set) var executionAutoRetryConfiguration: ExecutionAutoRetryConfiguration
    @Published private(set) var executionCheckpoint: ExecutionCheckpoint?
    @Published private(set) var executionApprovalPolicy: ExecutionApprovalPolicy
    @Published private(set) var taskExecutionApprovalsByTaskID: [UUID: TaskExecutionApproval]
    @Published private(set) var executionQuotaPolicy: ExecutionQuotaPolicy
    @Published private(set) var executionQuotaUsage: ExecutionQuotaUsage
    @Published private(set) var executionParallelizationPolicy: ExecutionParallelizationPolicy
    @Published private(set) var gitHubPRQualityGatePolicy: GitHubPRQualityGatePolicy
    @Published private(set) var dagExecutionPolicy: DAGExecutionPolicy
    @Published private(set) var executionQualitySafetyGatePolicy: ExecutionQualitySafetyGatePolicy
    @Published private(set) var executionRealArtifactVerificationDefaultPolicy: ExecutionRealArtifactVerificationPolicy
    @Published private(set) var selectedBoardUsesDefaultRealArtifactVerificationPolicy: Bool
    @Published private(set) var executionRealArtifactVerificationPolicy: ExecutionRealArtifactVerificationPolicy
    @Published private(set) var mcpServerPolicy: MCPServerPolicy
    @Published private(set) var pmPlannerEngineMode: PMPlannerEngineMode
    @Published private(set) var pmPlanningPluginPolicy: PMPlanningPluginPolicy
    @Published private(set) var pmExtensionActivityLog: [PMExtensionActivityLogEntry] = []
    @Published private(set) var pmExtensionObservability: [PMExtensionObservabilitySnapshot] = []
    @Published private(set) var pmExtensionLastAcceptanceReport: PMExtensionE2EAcceptanceReport?
    @Published private(set) var sharedAgentMemory: [SharedAgentMemoryEntry] = []
    @Published private(set) var pmBoardExtensionHookBindings: [PMBoardExtensionHookBinding] = []
    @Published private(set) var sharedAgentMemoryProviderMode: SharedAgentMemoryProviderMode
    @Published private(set) var sharedAgentMemoryPreferredProviderID: String?
    @Published private(set) var sharedAgentMemoryMutedProviderIDs: Set<String>
    @Published private(set) var agentExecutionEventsByAgentID: [UUID: [AgentExecutionEvent]] = [:]
    @Published private(set) var executionTimelineByTaskID: [UUID: [AgentExecutionEvent]] = [:]

    private let assignmentEngine: AutoAssignmentEngine
    private let projectPlanner: any ProjectPlanning
    private let taskExecutor: any AgentTaskExecuting
    private let projectsDirectoryPathProvider: () -> String
    private let boardStore: KanbanBoardStore?
    private let runOnBackground: ExecutionDispatcher
    private let runOnMain: ExecutionDispatcher
    private let gitCommandRunner: GitCommandRunner
    private static let defaultBoardName = "Default Board"
    private static let maxAgentExecutionEventsPerAgent = 120
    private static let maxTaskTimelineEventsPerTask = 240
    private static let maxExtensionActivityLogEntries = 200
    private static let maxSharedAgentMemoryEntries = 160
    private static let sharedAgentMemoryPromptLimit = 12
    private static let sharedAgentMemoryPromptCharsLimit = 2800
    private static let maxHookRetryCount = 2
    private static let hookRetryBackoffBaseSeconds: Double = 1
    private static let hookDedupWindowSeconds: Double = 6
    private static let hookMaxConcurrentRuns = 2
    private static let mcpRegistrySyncTTL: TimeInterval = 60 * 30
    private var mcpReadinessCacheByServerName: [String: Bool] = [:]
    private var pmExtensionStatsByPluginID: [String: PMExtensionMutableStats] = [:]
    private var pmExtensionHookQueue: [PMExtensionHookWorkItem] = []
    private var pmExtensionHookQueuedKeys: Set<String> = []
    private var pmExtensionHookRunningKeys: Set<String> = []
    private var pmExtensionHookDedupExpirations: [String: Date] = [:]
    private var pmExtensionHookRunningCount = 0
    private var pmExtensionInstallStack: Set<String> = []

    private func message(_ key: String) -> String {
        L10n.string(key)
    }

    private func message(_ key: String, _ arguments: CVarArg...) -> String {
        L10n.format(key, locale: nil, arguments: arguments)
    }

    nonisolated private static func normalizedPlannedTicket(from ticket: PMPlannedTicket) -> PMPlannedTicket? {
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

    nonisolated private static func planningMetadataAugmentedDetails(for ticket: PMPlannedTicket) -> String {
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

    nonisolated private static func plannedTicketMilestoneCount(_ tickets: [PMPlannedTicket]) -> Int {
        Set(
            tickets.map { ticket in
                let milestone = ticket.milestone.trimmingCharacters(in: .whitespacesAndNewlines)
                return milestone.isEmpty ? "__unscheduled__" : milestone.lowercased()
            }
        ).count
    }

    nonisolated private static func plannedTicketEpicCount(_ tickets: [PMPlannedTicket]) -> Int {
        Set(
            tickets
                .map { $0.epic.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                .filter { !$0.isEmpty }
        ).count
    }

    private static func defaultTaskTemplates() -> [TaskTemplate] {
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

    private init(
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

    @discardableResult
    func createBoard(name: String) -> Bool {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            lastBoardMessage = message("Board name is required")
            return false
        }

        if boards.contains(where: { $0.name.localizedCaseInsensitiveCompare(trimmedName) == .orderedSame }) {
            lastBoardMessage = message("Board name already exists")
            return false
        }

        syncCurrentBoardRecord()
        let board = KanbanBoardRecord(
            name: trimmedName,
            executionRealArtifactVerificationPolicy: nil
        )
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
            lastBoardMessage = message("Board name is required")
            return false
        }

        guard let index = boards.firstIndex(where: { $0.id == boardID }) else {
            lastBoardMessage = message("Board not found")
            return false
        }

        if boards.contains(where: {
            $0.id != boardID && $0.name.localizedCaseInsensitiveCompare(trimmedName) == .orderedSame
        }) {
            lastBoardMessage = message("Board name already exists")
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
            lastBoardMessage = message("At least one board is required")
            return false
        }

        guard let removeIndex = boards.firstIndex(where: { $0.id == boardID }) else {
            lastBoardMessage = message("Board not found")
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
            lastBoardMessage = message("Board not found")
            return false
        }

        syncCurrentBoardRecord()
        let sourceBoard = boards[sourceIndex]

        let resolvedName: String
        if let name {
            let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedName.isEmpty else {
                lastBoardMessage = message("Board name is required")
                return false
            }
            resolvedName = trimmedName
        } else {
            resolvedName = uniqueBoardCopyName(for: sourceBoard.name)
        }

        if boards.contains(where: { $0.name.localizedCaseInsensitiveCompare(resolvedName) == .orderedSame }) {
            lastBoardMessage = message("Board name already exists")
            return false
        }

        let copiedBoard = KanbanBoardRecord(
            name: resolvedName,
            tasks: sourceBoard.tasks,
            agents: sourceBoard.agents,
            wipLimits: sourceBoard.wipLimits,
            executionRealArtifactVerificationPolicy: sourceBoard.executionRealArtifactVerificationPolicy
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
                    assigneeName = message("Unassigned")
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
            lastBoardMessage = message("Board not found")
            return false
        }

        guard boards[boardIndex].tasks.contains(where: { $0.id == taskID }) else {
            lastBoardMessage = message("Task not found")
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
                    selectedBoardID: selectedBoardID,
                    taskTemplates: taskTemplates,
                    executionAutoRetryConfiguration: executionAutoRetryConfiguration,
                    executionCheckpoint: executionCheckpoint,
                    executionApprovalPolicy: executionApprovalPolicy,
                    taskExecutionApprovalsByTaskID: taskExecutionApprovalsByTaskID,
                    executionQuotaPolicy: executionQuotaPolicy,
                    executionQuotaUsage: executionQuotaUsage,
                    executionParallelizationPolicy: executionParallelizationPolicy,
                    gitHubPRQualityGatePolicy: gitHubPRQualityGatePolicy,
                    dagExecutionPolicy: dagExecutionPolicy,
                    executionQualitySafetyGatePolicy: executionQualitySafetyGatePolicy,
                    executionRealArtifactVerificationPolicy: executionRealArtifactVerificationDefaultPolicy,
                    mcpServerPolicy: mcpServerPolicy,
                    pmPlannerEngineMode: pmPlannerEngineMode,
                    pmPlanningPluginPolicy: pmPlanningPluginPolicy
                )
            )
        } catch {
            lastBoardMessage = message("Failed to export workspace")
            return nil
        }
    }

    func selectedBoardExportData() -> Data? {
        syncCurrentBoardRecord()
        guard let selectedBoard = boards.first(where: { $0.id == selectedBoardID }) else {
            lastBoardMessage = message("Board not found")
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
                    selectedBoardID: selectedBoard.id,
                    taskTemplates: taskTemplates,
                    executionAutoRetryConfiguration: executionAutoRetryConfiguration,
                    executionCheckpoint: executionCheckpoint?.boardID == selectedBoard.id ? executionCheckpoint : nil,
                    executionApprovalPolicy: executionApprovalPolicy,
                    taskExecutionApprovalsByTaskID: taskExecutionApprovalsByTaskID.filter { approvalEntry in
                        selectedBoard.tasks.contains(where: { $0.id == approvalEntry.key })
                    },
                    executionQuotaPolicy: executionQuotaPolicy,
                    executionQuotaUsage: executionQuotaUsage,
                    executionParallelizationPolicy: executionParallelizationPolicy,
                    gitHubPRQualityGatePolicy: gitHubPRQualityGatePolicy,
                    dagExecutionPolicy: dagExecutionPolicy,
                    executionQualitySafetyGatePolicy: executionQualitySafetyGatePolicy,
                    executionRealArtifactVerificationPolicy: executionRealArtifactVerificationDefaultPolicy,
                    mcpServerPolicy: mcpServerPolicy,
                    pmPlannerEngineMode: pmPlannerEngineMode,
                    pmPlanningPluginPolicy: pmPlanningPluginPolicy
                )
            )
        } catch {
            lastBoardMessage = message("Failed to export board")
            return nil
        }
    }

    private func executionReportDocumentForSelectedBoard() -> ExecutionReportDocument? {
        syncCurrentBoardRecord()
        guard let selectedBoard = boards.first(where: { $0.id == selectedBoardID }) else {
            lastBoardMessage = message("Board not found")
            lastBoardMessageSeverity = .warning
            return nil
        }

        let agentsByID = Dictionary(uniqueKeysWithValues: selectedBoard.agents.map { ($0.id, $0.name) })
        let entries = selectedBoard.tasks.map { task in
            let assignee: String
            if let assignedAgentID = task.assignedAgentID,
               let resolvedName = agentsByID[assignedAgentID] {
                assignee = resolvedName
            } else {
                assignee = message("Unassigned")
            }

            return ExecutionReportTaskEntry(
                id: task.id,
                title: task.title,
                status: task.status.rawValue,
                assignee: assignee,
                storyPoints: task.storyPoints,
                runCount: task.executionRecord?.runCount ?? 0,
                executionStatus: task.executionRecord?.status.rawValue,
                lastStartedAt: task.executionRecord?.lastStartedAt,
                lastFinishedAt: task.executionRecord?.lastFinishedAt,
                lastSummary: task.executionRecord?.lastOutputSummary,
                lastError: task.executionRecord?.lastError
            )
        }

        let executedTasks = entries.filter { $0.executionStatus != nil }.count
        let succeededTasks = entries.filter { $0.executionStatus == TaskExecutionStatus.succeeded.rawValue }.count
        let failedTasks = entries.filter { $0.executionStatus == TaskExecutionStatus.failed.rawValue }.count
        let runningTasks = entries.filter { $0.executionStatus == TaskExecutionStatus.running.rawValue }.count
        let notRunTasks = max(0, entries.count - executedTasks)

        return ExecutionReportDocument(
            generatedAt: Date(),
            boardID: selectedBoard.id,
            boardName: selectedBoard.name,
            totalTasks: entries.count,
            executedTasks: executedTasks,
            succeededTasks: succeededTasks,
            failedTasks: failedTasks,
            runningTasks: runningTasks,
            notRunTasks: notRunTasks,
            tasks: entries
        )
    }

    func executionReportJSONDataForSelectedBoard() -> Data? {
        guard let report = executionReportDocumentForSelectedBoard() else { return nil }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .secondsSince1970
        return try? encoder.encode(report)
    }

    func executionReportMarkdownForSelectedBoard() -> String? {
        guard let report = executionReportDocumentForSelectedBoard() else { return nil }

        var lines: [String] = []
        lines.append("# Execution Report")
        lines.append("")
        lines.append("- Generated At: \(ISO8601DateFormatter().string(from: report.generatedAt))")
        lines.append("- Board: \(report.boardName)")
        lines.append("- Total Tasks: \(report.totalTasks)")
        lines.append("- Executed: \(report.executedTasks)")
        lines.append("- Succeeded: \(report.succeededTasks)")
        lines.append("- Failed: \(report.failedTasks)")
        lines.append("- Running: \(report.runningTasks)")
        lines.append("- Not Run: \(report.notRunTasks)")
        lines.append("")
        lines.append("| Task | Status | Assignee | SP | Runs | Execution |")
        lines.append("| --- | --- | --- | ---: | ---: | --- |")
        for task in report.tasks {
            let execution = task.executionStatus ?? "not-run"
            lines.append(
                "| \(task.title.replacingOccurrences(of: "|", with: "\\|")) | \(task.status) | \(task.assignee.replacingOccurrences(of: "|", with: "\\|")) | \(task.storyPoints) | \(task.runCount) | \(execution) |"
            )
        }

        return lines.joined(separator: "\n")
    }

    private func githubPRBody(
        boardName: String,
        executionReportMarkdown: String,
        dependencyInsights: DependencyGraphInsights
    ) -> String {
        var lines: [String] = []
        lines.append("## OpenMac Board Summary")
        lines.append("")
        lines.append("- Board: \(boardName)")
        lines.append("- Blocked Tasks: \(dependencyInsights.blockedTaskCount)")
        lines.append("- Dependencies: \(dependencyInsights.totalTaskDependencies) (external: \(dependencyInsights.externalDependencyCount))")
        lines.append("- Critical Path: \(dependencyInsights.criticalPathStoryPoints) SP")
        if !dependencyInsights.criticalPathTaskTitles.isEmpty {
            lines.append("- Critical Path Tasks: \(dependencyInsights.criticalPathTaskTitles.joined(separator: " -> "))")
        }
        if !dependencyInsights.cycleTaskTitles.isEmpty {
            lines.append("- Dependency Cycles: \(dependencyInsights.cycleTaskTitles.joined(separator: ", "))")
        }
        lines.append("")
        lines.append("## Execution Report")
        lines.append("")
        lines.append(executionReportMarkdown)
        return lines.joined(separator: "\n")
    }

    @discardableResult
    func exportExecutionReportJSONForSelectedBoard(to url: URL) -> Bool {
        guard let data = executionReportJSONDataForSelectedBoard() else {
            lastBoardMessage = message("Failed to export execution report")
            lastBoardMessageSeverity = .warning
            return false
        }
        do {
            try data.write(to: url, options: .atomic)
            let fileName = url.lastPathComponent.isEmpty ? "execution-report.json" : url.lastPathComponent
            lastBoardMessage = message("Exported execution report to %@", fileName)
            lastBoardMessageSeverity = .info
            return true
        } catch {
            lastBoardMessage = message("Failed to export execution report")
            lastBoardMessageSeverity = .warning
            return false
        }
    }

    @discardableResult
    func exportExecutionReportMarkdownForSelectedBoard(to url: URL) -> Bool {
        guard let markdown = executionReportMarkdownForSelectedBoard() else {
            lastBoardMessage = message("Failed to export execution report")
            lastBoardMessageSeverity = .warning
            return false
        }
        do {
            guard let data = markdown.data(using: .utf8) else {
                lastBoardMessage = message("Failed to export execution report")
                lastBoardMessageSeverity = .warning
                return false
            }
            try data.write(to: url, options: .atomic)
            let fileName = url.lastPathComponent.isEmpty ? "execution-report.md" : url.lastPathComponent
            lastBoardMessage = message("Exported execution report to %@", fileName)
            lastBoardMessageSeverity = .info
            return true
        } catch {
            lastBoardMessage = message("Failed to export execution report")
            lastBoardMessageSeverity = .warning
            return false
        }
    }

    func workspaceImportPreview(from data: Data) -> WorkspaceImportPreview? {
        guard let snapshot = decodeWorkspaceSnapshot(from: data) else {
            lastBoardMessage = message("Invalid workspace JSON")
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
                wipLimits: snapshot.wipLimits,
                executionRealArtifactVerificationPolicy: nil,
                sharedAgentMemory: snapshot.sharedAgentMemory
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
            lastBoardMessage = message("Failed to read workspace file")
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
            lastBoardMessage = message("Exported workspace to %@", fileName)
            lastBoardMessageSeverity = .info
            return true
        } catch {
            lastBoardMessage = message("Failed to write workspace file")
            return false
        }
    }

    @discardableResult
    func exportSelectedBoard(to url: URL) -> Bool {
        guard let data = selectedBoardExportData() else { return false }
        do {
            try data.write(to: url, options: .atomic)
            let fileName = url.lastPathComponent.isEmpty ? "board.json" : url.lastPathComponent
            lastBoardMessage = message("Exported board to %@", fileName)
            lastBoardMessageSeverity = .info
            return true
        } catch {
            lastBoardMessage = message("Failed to write board file")
            return false
        }
    }

    @discardableResult
    func importWorkspaceData(_ data: Data, strategy: WorkspaceImportStrategy = .replace) -> Bool {
        guard let snapshot = decodeWorkspaceSnapshot(from: data) else {
            lastBoardMessage = message("Invalid workspace JSON")
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
                wipLimits: snapshot.wipLimits,
                executionRealArtifactVerificationPolicy: nil,
                sharedAgentMemory: snapshot.sharedAgentMemory
            )
            importedBoards = normalizedImportedBoardRecords([fallbackBoard])
            preferredSelectedBoardID = nil
        }

        guard !importedBoards.isEmpty else {
            lastBoardMessage = message("Workspace has no boards")
            return false
        }

        let resolvedSelectedBoardID: UUID
        switch strategy {
        case .replace:
            boards = importedBoards
            if let importedTemplates = snapshot.taskTemplates, !importedTemplates.isEmpty {
                taskTemplates = importedTemplates
            }
            if let importedRetryConfiguration = snapshot.executionAutoRetryConfiguration {
                executionAutoRetryConfiguration = importedRetryConfiguration
            }
            executionCheckpoint = snapshot.executionCheckpoint
            executionApprovalPolicy = snapshot.executionApprovalPolicy ?? .init()
            executionQuotaPolicy = snapshot.executionQuotaPolicy ?? .init()
            executionQuotaUsage = snapshot.executionQuotaUsage ?? .init()
            executionParallelizationPolicy = snapshot.executionParallelizationPolicy ?? .init()
            gitHubPRQualityGatePolicy = snapshot.gitHubPRQualityGatePolicy ?? .init()
            dagExecutionPolicy = snapshot.dagExecutionPolicy ?? .init()
            executionQualitySafetyGatePolicy = snapshot.executionQualitySafetyGatePolicy ?? .init()
            executionRealArtifactVerificationDefaultPolicy = snapshot.executionRealArtifactVerificationPolicy ?? .init()
            mcpServerPolicy = snapshot.mcpServerPolicy ?? .init()
            pmPlannerEngineMode = snapshot.pmPlannerEngineMode ?? .builtIn
            pmPlanningPluginPolicy = snapshot.pmPlanningPluginPolicy ?? .init()
            sharedAgentMemoryProviderMode = snapshot.sharedAgentMemoryProviderMode ?? .coreOnly
            sharedAgentMemoryPreferredProviderID = Self.normalizedProviderDescriptorID(snapshot.sharedAgentMemoryPreferredProviderID)
            sharedAgentMemoryMutedProviderIDs = Set((snapshot.sharedAgentMemoryMutedProviderIDs ?? []).compactMap(Self.normalizedProviderDescriptorID))
            mcpReadinessCacheByServerName = [:]
            taskExecutionApprovalsByTaskID = (snapshot.taskExecutionApprovalsByTaskID ?? [:]).filter { approvalEntry in
                importedBoards.contains { board in
                    board.tasks.contains(where: { $0.id == approvalEntry.key })
                }
            }
            resolvedSelectedBoardID = preferredSelectedBoardID.flatMap { candidate in
                importedBoards.contains(where: { $0.id == candidate }) ? candidate : nil
            } ?? importedBoards[0].id
            loadBoard(resolvedSelectedBoardID)
            persistBoardState()
            let boardLabel = boards.count == 1 ? message("board") : message("boards")
            lastBoardMessage = message("Imported workspace (%d %@)", boards.count, boardLabel)
        case .merge:
            syncCurrentBoardRecord()
            let currentSelectedBoardID = selectedBoardID
            boards = mergedBoardRecords(currentBoards: boards, importedBoards: importedBoards)
            if let importedTemplates = snapshot.taskTemplates, !importedTemplates.isEmpty {
                taskTemplates = mergedTaskTemplates(current: taskTemplates, imported: importedTemplates)
            }
            if let importedRetryConfiguration = snapshot.executionAutoRetryConfiguration {
                executionAutoRetryConfiguration = importedRetryConfiguration
            }
            if let importedApprovalPolicy = snapshot.executionApprovalPolicy {
                executionApprovalPolicy = importedApprovalPolicy
            }
            if let importedQuotaPolicy = snapshot.executionQuotaPolicy {
                executionQuotaPolicy = importedQuotaPolicy
            }
            if let importedQuotaUsage = snapshot.executionQuotaUsage {
                executionQuotaUsage = importedQuotaUsage
            }
            if let importedParallelizationPolicy = snapshot.executionParallelizationPolicy {
                executionParallelizationPolicy = importedParallelizationPolicy
            }
            if let importedQualityGatePolicy = snapshot.gitHubPRQualityGatePolicy {
                gitHubPRQualityGatePolicy = importedQualityGatePolicy
            }
            if let importedDAGPolicy = snapshot.dagExecutionPolicy {
                dagExecutionPolicy = importedDAGPolicy
            }
            if let importedQualitySafetyPolicy = snapshot.executionQualitySafetyGatePolicy {
                executionQualitySafetyGatePolicy = importedQualitySafetyPolicy
            }
            if let importedRealArtifactPolicy = snapshot.executionRealArtifactVerificationPolicy {
                executionRealArtifactVerificationDefaultPolicy = importedRealArtifactPolicy
            }
            if let importedMCPPolicy = snapshot.mcpServerPolicy {
                mcpServerPolicy = importedMCPPolicy
                mcpReadinessCacheByServerName = [:]
            }
            if let importedPlannerMode = snapshot.pmPlannerEngineMode {
                pmPlannerEngineMode = importedPlannerMode
            }
            if let importedPluginPolicy = snapshot.pmPlanningPluginPolicy {
                pmPlanningPluginPolicy = importedPluginPolicy
            }
            if let importedSharedMemoryProviderMode = snapshot.sharedAgentMemoryProviderMode {
                sharedAgentMemoryProviderMode = importedSharedMemoryProviderMode
            }
            if let importedPreferredProviderID = snapshot.sharedAgentMemoryPreferredProviderID {
                sharedAgentMemoryPreferredProviderID = Self.normalizedProviderDescriptorID(importedPreferredProviderID)
            }
            if let importedMutedProviderIDs = snapshot.sharedAgentMemoryMutedProviderIDs {
                sharedAgentMemoryMutedProviderIDs = Set(importedMutedProviderIDs.compactMap(Self.normalizedProviderDescriptorID))
            }
            if let importedApprovals = snapshot.taskExecutionApprovalsByTaskID {
                taskExecutionApprovalsByTaskID.merge(importedApprovals) { _, new in new }
            }
            resolvedSelectedBoardID = preferredSelectedBoardID.flatMap { candidate in
                importedBoards.contains(where: { $0.id == candidate }) ? candidate : nil
            } ?? currentSelectedBoardID
            loadBoard(resolvedSelectedBoardID)
            persistBoardState()
            let boardLabel = importedBoards.count == 1 ? message("board") : message("boards")
            lastBoardMessage = message("Merged workspace (+%d %@)", importedBoards.count, boardLabel)
        }
        lastBoardMessageSeverity = .info
        return true
    }

    @discardableResult
    func importWorkspace(from url: URL, strategy: WorkspaceImportStrategy = .replace) -> Bool {
        guard let data = try? Data(contentsOf: url) else {
            lastBoardMessage = message("Failed to read workspace file")
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
            lastBoardMessage = message("Invalid move: %@ -> %@", message(sourceStatus.title), message(status.title))
            return false
        }
        guard !isWIPLimitReached(for: status, excluding: taskID) else {
            let limit = wipLimits[status] ?? 0
            lastBoardMessage = message("WIP limit reached for %@ (%d)", message(status.title), limit)
            return false
        }

        tasks[index].status = status
        if sourceStatus.previous == status,
           tasks[index].executionRecord?.status == .succeeded {
            tasks[index].executionRecord = nil
        }

        if status == .done || status == .todo {
            tasks[index].assignedAgentID = nil
            lastAssignmentReasons[taskID] = nil
        }

        if status == .review {
            triggerPMExtensionHooks(event: .reviewEntered, task: tasks[index])
        }

        persistBoardState()
        lastBoardMessage = nil
        return true
    }

    @discardableResult
    func moveTask(_ taskID: UUID, toBoard targetBoardID: UUID) -> Bool {
        guard let sourceBoardIndex = selectedBoardIndex else { return false }
        guard let targetBoardIndex = boards.firstIndex(where: { $0.id == targetBoardID }) else {
            lastBoardMessage = message("Board not found")
            return false
        }
        guard sourceBoardIndex != targetBoardIndex else {
            lastBoardMessage = message("Select a different board")
            return false
        }

        syncCurrentBoardRecord()
        guard let taskIndex = boards[sourceBoardIndex].tasks.firstIndex(where: { $0.id == taskID }) else {
            lastBoardMessage = message("Task not found")
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
            lastBoardMessage = message("Board not found")
            return false
        }
        guard sourceBoardIndex != targetBoardIndex else {
            lastBoardMessage = message("Select a different board")
            return false
        }

        syncCurrentBoardRecord()
        guard let sourceTask = boards[sourceBoardIndex].tasks.first(where: { $0.id == taskID }) else {
            lastBoardMessage = message("Task not found")
            return false
        }

        var copiedTask = WorkTask(
            title: sourceTask.title,
            details: sourceTask.details,
            requiredSkills: Array(sourceTask.requiredSkills),
            storyPoints: sourceTask.storyPoints,
            status: sourceTask.status,
            assignedAgentID: sourceTask.assignedAgentID,
            deliveryContract: sourceTask.deliveryContract
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

    func autoAssignTasks(allowFallbackWithoutSkillMatch: Bool = false) {
        let result = assignmentEngine.assign(
            tasks: tasks,
            agents: agents,
            allowFallbackWithoutSkillMatch: allowFallbackWithoutSkillMatch
        )
        tasks = result.tasks
        lastUnassignedTaskIDs = result.unassignedTaskIDs
        lastAssignmentReasons = result.decisions.reduce(into: [:]) { partialResult, pair in
            partialResult[pair.key] = pair.value.reason
        }
        persistBoardState()
        lastBoardMessage = nil
    }

    @discardableResult
    func autoAssignTask(
        _ taskID: UUID,
        allowFallbackWithoutSkillMatch: Bool = false
    ) -> Bool {
        guard let taskIndex = tasks.firstIndex(where: { $0.id == taskID }) else { return false }
        guard tasks[taskIndex].status == .todo else {
            lastBoardMessage = message("Only To Do tasks can be auto-assigned")
            lastBoardMessageSeverity = .warning
            return false
        }
        guard tasks[taskIndex].assignedAgentID == nil else {
            lastBoardMessage = message("Task already assigned")
            lastBoardMessageSeverity = .warning
            return false
        }

        guard let decision = assignmentEngine.bestAgent(
            for: tasks[taskIndex],
            among: tasks,
            agents: agents,
            allowFallbackWithoutSkillMatch: allowFallbackWithoutSkillMatch
        ) else {
            lastUnassignedTaskIDs.insert(taskID)
            lastBoardMessage = message("No eligible agent for task")
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
        deliveryContract: TaskDeliveryContract? = nil,
        autoAssign: Bool = false
    ) -> Bool {
        let skills = requiredSkillsText
            .split(separator: ",")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else {
            lastBoardMessage = message("Task title is required")
            return false
        }

        let task = WorkTask(
            title: trimmedTitle,
            details: details,
            requiredSkills: skills,
            storyPoints: storyPoints,
            status: .todo,
            assignedAgentID: nil,
            deliveryContract: (deliveryContract ?? Self.inferredDeliveryContract(
                title: trimmedTitle,
                details: details,
                requiredSkills: skills
            )).normalized
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
        triggerPMExtensionHooks(event: .ticketCreated, task: task)
        return true
    }

    func taskTemplate(_ templateID: UUID) -> TaskTemplate? {
        taskTemplates.first(where: { $0.id == templateID })
    }

    private static func inferredDeliveryContract(
        title: String,
        details: String,
        requiredSkills: [String]
    ) -> TaskDeliveryContract {
        let outputType = inferredDeliveryOutputType(title: title, details: details, requiredSkills: requiredSkills)
        let gateMode: TaskDeliveryGateMode
        switch outputType {
        case .app, .codeModule, .data:
            gateMode = .strict
        case .document, .image, .mixed:
            gateMode = .flexible
        }
        return TaskDeliveryContract(outputType: outputType, gateMode: gateMode)
    }

    private static func inferredDeliveryOutputType(
        title: String,
        details: String,
        requiredSkills: [String]
    ) -> TaskDeliveryOutputType {
        let skillTokens = requiredSkills.joined(separator: " ")
        let lowered = "\(title) \(details) \(skillTokens)".lowercased()
        if lowered.contains("screenshot") ||
            lowered.contains("image") ||
            lowered.contains("圖") ||
            lowered.contains("圖片") ||
            lowered.contains(".png") ||
            lowered.contains(".jpg") {
            return .image
        }
        if lowered.contains("document") ||
            lowered.contains("readme") ||
            lowered.contains("spec") ||
            lowered.contains("proposal") ||
            lowered.contains("report") ||
            lowered.contains("文件") ||
            lowered.contains("說明") {
            return .document
        }
        if lowered.contains("dataset") ||
            lowered.contains("csv") ||
            lowered.contains("json") ||
            lowered.contains("etl") ||
            lowered.contains("analytics") ||
            lowered.contains("資料集") ||
            lowered.contains("數據") {
            return .data
        }
        if lowered.contains("app") ||
            lowered.contains("ios") ||
            lowered.contains("android") ||
            lowered.contains("macos") ||
            lowered.contains("swiftui") ||
            lowered.contains("uikit") ||
            lowered.contains("frontend") ||
            lowered.contains("backend") ||
            lowered.contains("api") ||
            lowered.contains("web") ||
            lowered.contains("產品") {
            return .app
        }
        if lowered.contains("module") ||
            lowered.contains("library") ||
            lowered.contains("package") ||
            lowered.contains("sdk") ||
            lowered.contains("函式庫") {
            return .codeModule
        }
        return .mixed
    }

    @discardableResult
    func addTaskTemplate(
        name: String,
        title: String,
        details: String,
        requiredSkillsText: String,
        storyPoints: Int
    ) -> Bool {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            lastBoardMessage = message("Task template name is required")
            lastBoardMessageSeverity = .warning
            return false
        }

        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else {
            lastBoardMessage = message("Task template title is required")
            lastBoardMessageSeverity = .warning
            return false
        }

        let skills = requiredSkillsText
            .split(separator: ",")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let template = TaskTemplate(
            name: trimmedName,
            title: trimmedTitle,
            details: details,
            requiredSkills: skills,
            storyPoints: storyPoints
        )
        taskTemplates.append(template)
        taskTemplates.sort { lhs, rhs in
            lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
        persistBoardState()
        lastBoardMessage = message("Added task template: %@", template.name)
        lastBoardMessageSeverity = .info
        return true
    }

    @discardableResult
    func updateTaskTemplate(
        _ templateID: UUID,
        name: String,
        title: String,
        details: String,
        requiredSkillsText: String,
        storyPoints: Int
    ) -> Bool {
        guard let index = taskTemplates.firstIndex(where: { $0.id == templateID }) else {
            lastBoardMessage = message("Task template not found")
            lastBoardMessageSeverity = .warning
            return false
        }

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            lastBoardMessage = message("Task template name is required")
            lastBoardMessageSeverity = .warning
            return false
        }
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else {
            lastBoardMessage = message("Task template title is required")
            lastBoardMessageSeverity = .warning
            return false
        }

        let skills = requiredSkillsText
            .split(separator: ",")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        taskTemplates[index].name = trimmedName
        taskTemplates[index].title = trimmedTitle
        taskTemplates[index].details = details.trimmingCharacters(in: .whitespacesAndNewlines)
        taskTemplates[index].requiredSkills = Array(Set(skills.map { $0.lowercased() })).sorted()
        taskTemplates[index].storyPoints = max(1, min(13, storyPoints))
        taskTemplates.sort { lhs, rhs in
            lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
        persistBoardState()
        lastBoardMessage = message("Updated task template: %@", trimmedName)
        lastBoardMessageSeverity = .info
        return true
    }

    @discardableResult
    func removeTaskTemplate(_ templateID: UUID) -> Bool {
        guard let index = taskTemplates.firstIndex(where: { $0.id == templateID }) else {
            lastBoardMessage = message("Task template not found")
            lastBoardMessageSeverity = .warning
            return false
        }
        let removedName = taskTemplates[index].name
        taskTemplates.remove(at: index)
        persistBoardState()
        lastBoardMessage = message("Deleted task template: %@", removedName)
        lastBoardMessageSeverity = .info
        return true
    }

    @discardableResult
    func createTask(
        fromTemplate templateID: UUID,
        autoAssign: Bool = false
    ) -> Bool {
        guard let template = taskTemplate(templateID) else {
            lastBoardMessage = message("Task template not found")
            lastBoardMessageSeverity = .warning
            return false
        }
        return addTask(
            title: template.title,
            details: template.details,
            requiredSkillsText: template.requiredSkillsText,
            storyPoints: template.storyPoints,
            autoAssign: autoAssign
        )
    }

    func updateExecutionAutoRetryConfiguration(
        isEnabled: Bool,
        maxRetryCount: Int,
        backoffSeconds: Double,
        retryableErrorTypes: Set<RetryableExecutionErrorType>
    ) {
        executionAutoRetryConfiguration = ExecutionAutoRetryConfiguration(
            isEnabled: isEnabled,
            maxRetryCount: maxRetryCount,
            backoffSeconds: backoffSeconds,
            retryableErrorTypes: retryableErrorTypes
        )
        persistBoardState()
        lastBoardMessage = message("Updated execution auto-retry settings")
        lastBoardMessageSeverity = .info
    }

    func previewProjectPlan(
        projectName: String,
        projectBrief: String
    ) -> PMProjectPlan? {
        let trimmedBrief = projectBrief.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedBrief.isEmpty else {
            lastBoardMessage = message("Project brief is required")
            lastBoardMessageSeverity = .warning
            return nil
        }

        let generatedPlan: PMProjectPlan?
        if let configurablePlanner = projectPlanner as? any ConfigurableProjectPlanning {
            generatedPlan = configurablePlanner.generatePlan(
                projectName: projectName,
                projectBrief: trimmedBrief,
                availableAgents: agents,
                mode: pmPlannerEngineMode,
                pluginPolicy: pmPlanningPluginPolicy
            )
        } else {
            generatedPlan = projectPlanner.generatePlan(
                projectName: projectName,
                projectBrief: trimmedBrief,
                availableAgents: agents
            )
        }

        guard let plan = generatedPlan,
            !plan.tickets.isEmpty else {
            lastBoardMessage = message("PM planner could not generate actionable tickets")
            lastBoardMessageSeverity = .warning
            return nil
        }

        lastBoardMessage = nil
        return plan
    }

    func runPMBrainstormRoundInBackground(
        projectName: String,
        projectBrief: String,
        focus: String,
        previousTranscript: String,
        onProgress: @escaping (_ update: String) -> Void,
        completion: @escaping (_ output: String?, _ errorMessage: String?) -> Void
    ) {
        let trimmedBrief = projectBrief.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedBrief.isEmpty else {
            lastBoardMessage = message("Project brief is required")
            lastBoardMessageSeverity = .warning
            completion(nil, message("PM brainstorm requires a non-empty project brief"))
            return
        }

        let resolvedProjectName = {
            let trimmedName = projectName.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmedName.isEmpty ? selectedBoardName : trimmedName
        }()
        let agent = preferredPMBrainstormAgent()
        let brainstormTask = pmBrainstormTask(
            projectName: resolvedProjectName,
            projectBrief: trimmedBrief,
            focus: focus,
            previousTranscript: previousTranscript,
            agent: agent
        )

        runOnBackground {
            let outcome = self.executeTaskWithBoardScopedProjectsDirectory(
                task: brainstormTask,
                agent: agent
            ) { update in
                self.runOnMain {
                    onProgress(update)
                }
            }

            self.runOnMain {
                switch outcome {
                case let .success(summary):
                    self.lastBoardMessage = self.message("PM brainstorm completed with %@", agent.name)
                    self.lastBoardMessageSeverity = .info
                    completion(summary, nil)
                case let .failure(errorMessage):
                    self.lastBoardMessage = self.message("PM brainstorm failed: %@", errorMessage)
                    self.lastBoardMessageSeverity = .warning
                    completion(nil, errorMessage)
                }
            }
        }
    }

    func previewProjectBlueprint(
        projectName: String,
        projectBrief: String
    ) -> PMProjectBlueprint? {
        let trimmedBrief = projectBrief.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedBrief.isEmpty else {
            lastBoardMessage = message("Project brief is required")
            lastBoardMessageSeverity = .warning
            return nil
        }

        let generatedBlueprint: PMProjectBlueprint?
        if let configurablePlanner = projectPlanner as? any ConfigurableProjectPlanning {
            generatedBlueprint = configurablePlanner.generateBlueprint(
                projectName: projectName,
                projectBrief: trimmedBrief,
                availableAgents: agents,
                mode: pmPlannerEngineMode,
                pluginPolicy: pmPlanningPluginPolicy
            )
        } else if let blueprintPlanner = projectPlanner as? any ProjectBlueprintPlanning {
            generatedBlueprint = blueprintPlanner.generateBlueprint(
                projectName: projectName,
                projectBrief: trimmedBrief,
                availableAgents: agents
            )
        } else {
            generatedBlueprint = nil
        }

        guard let blueprint = generatedBlueprint,
              !blueprint.tickets.isEmpty else {
            lastBoardMessage = message("PM planner could not generate actionable tickets")
            lastBoardMessageSeverity = .warning
            return nil
        }

        lastBoardMessage = nil
        return blueprint
    }

    private func preferredPMBrainstormAgent() -> AgentProfile {
        let prioritizedSkills: Set<String> = ["planning", "research", "product", "architecture", "analysis", "pm"]
        let runtimeAgents = agents.filter { resolvedPMBrainstormRuntimeProfile(for: $0).provider == .openAICompatible }

        if let prioritizedAgent = runtimeAgents.first(where: { !$0.skills.isDisjoint(with: prioritizedSkills) }) {
            return resolvingPMBrainstormRuntime(for: prioritizedAgent)
        }
        if let runtimeAgent = runtimeAgents.first {
            return resolvingPMBrainstormRuntime(for: runtimeAgent)
        }
        if let firstAgent = agents.first {
            return resolvingPMBrainstormRuntime(for: firstAgent)
        }
        return AgentProfile(
            name: message("PM Brainstorm Agent"),
            skills: ["planning", "research"],
            maxConcurrentTasks: 1,
            runtimeProfile: .defaultCodexBridge
        )
    }

    private func resolvingPMBrainstormRuntime(for agent: AgentProfile) -> AgentProfile {
        AgentProfile(
            id: agent.id,
            name: agent.name,
            skills: Array(agent.skills),
            maxConcurrentTasks: agent.maxConcurrentTasks,
            runtimeProfile: resolvedPMBrainstormRuntimeProfile(for: agent)
        )
    }

    private func resolvedPMBrainstormRuntimeProfile(for agent: AgentProfile) -> AgentRuntimeProfile {
        agent.runtimeProfile ?? .defaultCodexBridge
    }

    private func pmBrainstormTask(
        projectName: String,
        projectBrief: String,
        focus: String,
        previousTranscript: String,
        agent: AgentProfile
    ) -> WorkTask {
        let trimmedFocus = focus.trimmingCharacters(in: .whitespacesAndNewlines)
        let recentTranscript = previousTranscript
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .suffix(4_000)
        let details = """
        You are OpenMac's built-in brainstorm extension.
        Help refine this product brief into an execution-ready PM input.

        Project: \(projectName)
        Current brief:
        \(projectBrief)

        Focus:
        \(trimmedFocus.isEmpty ? "General product + delivery brainstorming." : trimmedFocus)

        Prior brainstorm transcript (latest context):
        \(recentTranscript.isEmpty ? "(none)" : recentTranscript)

        Return plain text using EXACT tags:
        [UPDATED_BRIEF]
        ...
        [/UPDATED_BRIEF]
        [DECISIONS]
        - ...
        [/DECISIONS]
        [OPEN_QUESTIONS]
        - ...
        [/OPEN_QUESTIONS]
        [NEXT_EXPERIMENTS]
        - ...
        [/NEXT_EXPERIMENTS]

        Rules:
        - Keep UPDATED_BRIEF concise and directly actionable.
        - Preserve user intent and avoid unnecessary scope expansion.
        - Output only those tagged sections.
        """

        return WorkTask(
            title: message("PM Brainstorm: %@", projectName),
            details: details,
            requiredSkills: ["planning", "research"],
            storyPoints: 1,
            status: .todo,
            assignedAgentID: agent.id
        )
    }

    func projectBlueprintExportData(
        projectName: String,
        projectBrief: String
    ) -> Data? {
        guard let blueprint = previewProjectBlueprint(
            projectName: projectName,
            projectBrief: projectBrief
        ) else {
            return nil
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .secondsSince1970
        do {
            return try encoder.encode(blueprint)
        } catch {
            lastBoardMessage = message("Failed to export blueprint")
            lastBoardMessageSeverity = .warning
            return nil
        }
    }

    @discardableResult
    func addPlannedTickets(
        _ plannedTickets: [PMPlannedTicket],
        autoAssign: Bool,
        deliveryContract: TaskDeliveryContract = .defaultContract,
        generateAcceptanceE2ETasks: Bool = false
    ) -> Int {
        let normalizedTickets = plannedTickets.compactMap(Self.normalizedPlannedTicket(from:))
        guard !normalizedTickets.isEmpty else {
            lastBoardMessage = message("PM planner could not generate actionable tickets")
            lastBoardMessageSeverity = .warning
            return 0
        }
        let createdTaskDescriptors = addNormalizedPlannedTickets(
            normalizedTickets,
            autoAssign: autoAssign,
            deliveryContract: deliveryContract
        )
        if generateAcceptanceE2ETasks {
            let sourceTaskIDs = Set(createdTaskDescriptors.map(\.taskID))
            let createdAcceptanceTasks = createAcceptanceE2ETasks(
                autoAssign: autoAssign,
                sourceTaskIDs: sourceTaskIDs,
                updateBoardMessage: false
            )
            lastBoardMessage = message(
                "PM planner created %d ticket(s) + %d acceptance E2E task(s)",
                createdTaskDescriptors.count,
                createdAcceptanceTasks
            )
            lastBoardMessageSeverity = .info
        }
        return createdTaskDescriptors.count
    }

    private func addNormalizedPlannedTickets(
        _ normalizedTickets: [PMPlannedTicket],
        autoAssign: Bool,
        deliveryContract: TaskDeliveryContract = .defaultContract
    ) -> [PMCreatedTaskDescriptor] {
        var createdTasks: [PMCreatedTaskDescriptor] = []
        createdTasks.reserveCapacity(normalizedTickets.count)
        let resolvedDeliveryContract = deliveryContract.normalized

        for plannedTicket in normalizedTickets {
            let task = WorkTask(
                title: plannedTicket.title,
                details: Self.planningMetadataAugmentedDetails(for: plannedTicket),
                requiredSkills: plannedTicket.requiredSkills,
                storyPoints: plannedTicket.storyPoints,
                status: .todo,
                assignedAgentID: nil,
                deliveryContract: resolvedDeliveryContract
            )
            tasks.append(task)
            let milestone = plannedTicket.milestone.trimmingCharacters(in: .whitespacesAndNewlines)
            let resolvedMilestone = milestone.isEmpty ? message("Unscheduled") : milestone
            let epic = plannedTicket.epic.trimmingCharacters(in: .whitespacesAndNewlines)
            createdTasks.append(
                PMCreatedTaskDescriptor(
                    taskID: task.id,
                    milestone: resolvedMilestone,
                    epic: epic
                )
            )
            lastUnassignedTaskIDs.insert(task.id)
            lastAssignmentReasons[task.id] = nil
        }

        if autoAssign {
            for createdTask in createdTasks {
                let taskID = createdTask.taskID
                guard let taskIndex = tasks.firstIndex(where: { $0.id == taskID }) else {
                    continue
                }
                guard tasks[taskIndex].assignedAgentID == nil else {
                    continue
                }

                if let decision = assignmentEngine.bestAgent(
                    for: tasks[taskIndex],
                    among: tasks,
                    agents: agents
                ) {
                    tasks[taskIndex].assignedAgentID = decision.agentID
                    lastAssignmentReasons[taskID] = decision.reason
                    lastUnassignedTaskIDs.remove(taskID)
                }
            }
        }

        for createdTask in createdTasks {
            if let task = tasks.first(where: { $0.id == createdTask.taskID }) {
                triggerPMExtensionHooks(event: .ticketCreated, task: task)
            }
        }

        persistBoardState()
        lastBoardMessage = message("PM planner created %d ticket(s)", createdTasks.count)
        lastBoardMessageSeverity = .info
        return createdTasks
    }

    @discardableResult
    func createAcceptanceE2ETasks(
        autoAssign: Bool = true,
        sourceTaskIDs: Set<UUID>? = nil,
        updateBoardMessage: Bool = true
    ) -> Int {
        let normalizedExistingTitles = Set(tasks.map { $0.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() })
        var generatedTasks: [WorkTask] = []
        generatedTasks.reserveCapacity(tasks.count)

        for sourceTask in tasks {
            if let sourceTaskIDs, !sourceTaskIDs.contains(sourceTask.id) {
                continue
            }

            let sourceTitle = sourceTask.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !sourceTitle.isEmpty else { continue }
            guard !sourceTitle.localizedCaseInsensitiveContains("e2e verify ·") else { continue }

            let acceptanceCriteria = Self.acceptanceCriteriaLines(from: sourceTask.details)
            guard !acceptanceCriteria.isEmpty else { continue }

            let generatedTitle = "E2E Verify · \(sourceTitle)"
            guard !normalizedExistingTitles.contains(generatedTitle.lowercased()) else { continue }
            guard !generatedTasks.contains(where: { $0.title.localizedCaseInsensitiveCompare(generatedTitle) == .orderedSame }) else {
                continue
            }

            let generatedDetails = Self.acceptanceE2EDetails(
                sourceTitle: sourceTitle,
                acceptanceCriteria: acceptanceCriteria
            )
            let qaBaselineSkills: Set<String> = ["qa", "testing"]
            let requiredSkills = qaBaselineSkills.union(sourceTask.requiredSkills.intersection(qaBaselineSkills))
            let generatedTask = WorkTask(
                title: generatedTitle,
                details: generatedDetails,
                requiredSkills: requiredSkills.sorted(),
                storyPoints: max(1, min(5, max(1, sourceTask.storyPoints / 2))),
                status: .todo,
                assignedAgentID: nil,
                deliveryContract: TaskDeliveryContract(
                    outputType: .codeModule,
                    gateMode: .strict
                )
            )
            generatedTasks.append(generatedTask)
        }

        guard !generatedTasks.isEmpty else {
            if updateBoardMessage {
                lastBoardMessage = message("No acceptance criteria found for E2E task generation")
                lastBoardMessageSeverity = .warning
            }
            return 0
        }

        for generatedTask in generatedTasks {
            tasks.append(generatedTask)
            lastUnassignedTaskIDs.insert(generatedTask.id)
            lastAssignmentReasons[generatedTask.id] = nil
        }

        if autoAssign {
            for generatedTask in generatedTasks {
                guard let taskIndex = tasks.firstIndex(where: { $0.id == generatedTask.id }) else { continue }
                if let decision = assignmentEngine.bestAgent(
                    for: tasks[taskIndex],
                    among: tasks,
                    agents: agents
                ) {
                    tasks[taskIndex].assignedAgentID = decision.agentID
                    lastAssignmentReasons[generatedTask.id] = decision.reason
                    lastUnassignedTaskIDs.remove(generatedTask.id)
                }
            }
        }

        persistBoardState()
        if updateBoardMessage {
            lastBoardMessage = message("Created %d acceptance E2E task(s)", generatedTasks.count)
            lastBoardMessageSeverity = .info
        }
        return generatedTasks.count
    }

    @discardableResult
    func createMissingAgentsForPlannedTickets(
        _ plannedTickets: [PMPlannedTicket],
        maxSkillsPerAgent: Int = 3,
        defaultMaxConcurrentTasks: Int = 3,
        availableCodexSkillNames: [String]? = nil
    ) -> Int {
        let requiredSkills = Set(
            plannedTickets
                .flatMap(\.requiredSkills)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                .filter { !$0.isEmpty }
        )

        guard !requiredSkills.isEmpty else {
            lastBoardMessage = message("No required skills found in PM tickets")
            lastBoardMessageSeverity = .warning
            return 0
        }

        let coveredSkills = Set(agents.flatMap(\.skills))
        let missingSkills = requiredSkills.subtracting(coveredSkills).sorted()

        guard !missingSkills.isEmpty else {
            lastBoardMessage = message("All required PM skills are already covered by existing agents")
            lastBoardMessageSeverity = .info
            return 0
        }

        let chunkSize = max(1, maxSkillsPerAgent)
        let maxTasks = max(1, defaultMaxConcurrentTasks)
        let discoveredCodexSkillNames = (availableCodexSkillNames ?? Self.discoverLocalCodexSkillNamesForPMBootstrap())
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        var createdCount = 0
        var existingAgentNames = Set(agents.map { $0.name.lowercased() })
        var nextAutoIndex = 1

        for start in stride(from: 0, to: missingSkills.count, by: chunkSize) {
            let end = min(missingSkills.count, start + chunkSize)
            let skillsChunk = Array(missingSkills[start..<end])
            let agentName = Self.uniqueAutoAgentName(
                existingLowercasedNames: &existingAgentNames,
                nextIndex: &nextAutoIndex
            ) { index in
                self.message("Auto Agent %d", index)
            }

            let codexToolTokens = Self.recommendedCodexSkillToolTokens(
                forRequiredSkills: skillsChunk,
                availableCodexSkillNames: discoveredCodexSkillNames
            )
            var runtimeProfile = AgentRuntimeProfile.defaultCodexBridge
            if !codexToolTokens.isEmpty {
                runtimeProfile.tools = Set(codexToolTokens)
            }

            let created = addAgent(
                name: agentName,
                skillsText: skillsChunk.joined(separator: ", "),
                maxConcurrentTasks: maxTasks,
                runtimeProfile: runtimeProfile
            )
            if created {
                createdCount += 1
            }
        }

        if createdCount > 0 {
            lastBoardMessage = message("Created %d PM bootstrap agent(s) for missing skills", createdCount)
            lastBoardMessageSeverity = .info
        } else {
            lastBoardMessage = message("No required skills found in PM tickets")
            lastBoardMessageSeverity = .warning
        }

        return createdCount
    }

    private static func uniqueAutoAgentName(
        existingLowercasedNames: inout Set<String>,
        nextIndex: inout Int,
        localizedName: (Int) -> String
    ) -> String {
        while true {
            let currentIndex = nextIndex
            nextIndex += 1
            let rawCandidate = localizedName(currentIndex).trimmingCharacters(in: .whitespacesAndNewlines)
            let candidate = rawCandidate.isEmpty ? "Auto Agent \(currentIndex)" : rawCandidate
            let normalizedCandidate = candidate.lowercased()
            if !existingLowercasedNames.contains(normalizedCandidate) {
                existingLowercasedNames.insert(normalizedCandidate)
                return candidate
            }
        }
    }

    private static func discoverLocalCodexSkillNamesForPMBootstrap(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> [String] {
        CodexSkillCatalog.discoverSkillNames(
            environment: environment,
            fallbackHomeDirectoryPath: NSHomeDirectory()
        )
    }

    private static func recommendedCodexSkillToolTokens(
        forRequiredSkills requiredSkills: [String],
        availableCodexSkillNames: [String]
    ) -> [String] {
        guard !requiredSkills.isEmpty else { return [] }
        guard !availableCodexSkillNames.isEmpty else { return [] }

        let indexed = availableCodexSkillNames.map { name in
            (
                name: name,
                normalizedName: name.lowercased(),
                tokens: codexSkillSearchTokens(for: name)
            )
        }

        var selected = Set<String>()
        for rawSkill in requiredSkills {
            let normalizedRequired = rawSkill
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            guard !normalizedRequired.isEmpty else { continue }

            if let exactMatch = indexed.first(where: { $0.tokens.contains(normalizedRequired) }) {
                selected.insert(exactMatch.normalizedName)
                continue
            }

            let keywordHints = codexSkillKeywordHints(for: normalizedRequired)
            guard !keywordHints.isEmpty else { continue }

            if let fuzzyMatch = indexed.first(where: { !$0.tokens.isDisjoint(with: keywordHints) }) {
                selected.insert(fuzzyMatch.normalizedName)
            }
        }

        return selected.sorted().map { "skill:\($0)" }
    }

    private static func codexSkillSearchTokens(for rawSkillName: String) -> Set<String> {
        let normalized = rawSkillName
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !normalized.isEmpty else { return [] }

        var tokens = Set<String>()
        tokens.insert(normalized)

        for token in normalized.split(whereSeparator: { !$0.isLetter && !$0.isNumber }) {
            let fragment = String(token).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !fragment.isEmpty else { continue }
            tokens.insert(fragment)
        }

        if let separator = normalized.firstIndex(of: ":") {
            let trailing = String(normalized[normalized.index(after: separator)...])
            for token in trailing.split(whereSeparator: { !$0.isLetter && !$0.isNumber }) {
                let fragment = String(token).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !fragment.isEmpty else { continue }
                tokens.insert(fragment)
            }
        }

        return tokens
    }

    private static func codexSkillKeywordHints(for requiredSkill: String) -> Set<String> {
        let builtInHints = pmRequiredSkillToCodexHintMap[requiredSkill] ?? []
        let merged = Set(builtInHints + [requiredSkill])
        return Set(merged.filter { !$0.isEmpty })
    }

    private static let pmRequiredSkillToCodexHintMap: [String: [String]] = [
        "android": ["android", "mobile"],
        "api": ["api", "backend", "integration", "network"],
        "app": ["app", "ios", "swiftui"],
        "architecture": ["architecture", "refactor", "plan", "planning"],
        "backend": ["backend", "api", "integration", "database"],
        "build": ["build", "xcode", "ios"],
        "database": ["database", "data", "storage"],
        "design": ["design", "ui", "ux", "stitch"],
        "documentation": ["docs", "documentation", "readme"],
        "i18n": ["i18n", "localization", "l10n"],
        "integration": ["integration", "api", "backend"],
        "ios": ["ios", "xcode", "swiftui"],
        "macos": ["macos", "swiftui", "xcode"],
        "planning": ["planning", "plan", "brainstorm"],
        "qa": ["qa", "testing", "test", "audit"],
        "release": ["release", "deploy", "build"],
        "security": ["security", "compliance"],
        "swift": ["swift", "ios", "swiftui"],
        "swiftui": ["swiftui", "ui", "ios"],
        "tdd": ["tdd", "testing", "test"],
        "test": ["test", "testing", "qa", "audit"],
        "testing": ["testing", "test", "qa", "audit"],
        "ui": ["ui", "ux", "swiftui", "stitch"],
        "ux": ["ux", "ui", "design", "stitch"],
        "xcode": ["xcode", "ios", "build"]
    ]

    @discardableResult
    func updateTask(
        _ taskID: UUID,
        title: String,
        details: String,
        requiredSkillsText: String,
        storyPoints: Int,
        deliveryContract: TaskDeliveryContract? = nil
    ) -> Bool {
        guard let taskIndex = tasks.firstIndex(where: { $0.id == taskID }) else { return false }

        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else {
            lastBoardMessage = message("Task title is required")
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
        if let deliveryContract {
            tasks[taskIndex].deliveryContract = deliveryContract.normalized
        } else if tasks[taskIndex].deliveryContract == nil {
            tasks[taskIndex].deliveryContract = Self.inferredDeliveryContract(
                title: trimmedTitle,
                details: details,
                requiredSkills: skills
            )
        }
        taskExecutionApprovalsByTaskID[taskID] = nil

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
            assignedAgentID: nil,
            deliveryContract: sourceTask.deliveryContract
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
        taskExecutionApprovalsByTaskID[taskID] = nil
        executionTimelineByTaskID[taskID] = nil
        persistBoardState()
        lastBoardMessage = nil
        return true
    }

    @discardableResult
    func unassignTask(_ taskID: UUID) -> Bool {
        guard let taskIndex = tasks.firstIndex(where: { $0.id == taskID }) else { return false }
        guard tasks[taskIndex].assignedAgentID != nil else {
            lastBoardMessage = message("Task is already unassigned")
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
            lastBoardMessage = message("No todo tasks assigned to selected agent")
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
            lastBoardMessage = message("No done tasks to archive")
            lastBoardMessageSeverity = .warning
            return 0
        }

        tasks.removeAll { $0.status == .done }
        for taskID in doneTaskIDs {
            lastUnassignedTaskIDs.remove(taskID)
            lastAssignmentReasons[taskID] = nil
            taskExecutionApprovalsByTaskID[taskID] = nil
            executionTimelineByTaskID[taskID] = nil
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
            lastBoardMessage = message("No todo rebalancing needed")
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
            runtimeProfile: .defaultCodexBridge
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
            lastBoardMessage = message("Agent name is required")
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
        agentExecutionEventsByAgentID[agentID] = nil

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
            lastBoardMessage = message("Agent name is required")
            return false
        }

        let normalizedCapacity = max(1, maxConcurrentTasks)
        let currentLoad = activeTaskCount(for: agentID)
        guard normalizedCapacity >= currentLoad else {
            lastBoardMessage = message("Cannot set capacity below current load (%d)", currentLoad)
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

        let missingDependencyReferences = missingDependencyReferences()
        if !missingDependencyReferences.isEmpty {
            recommendations.append(
                BoardHealthRecommendation(
                    action: .createMissingDependencyTasks,
                    title: message("Create Missing Dependency Tasks"),
                    detail: message(
                        "%d missing dependency task(s) can be generated from blockers",
                        missingDependencyReferences.count
                    )
                )
            )
        }

        if unassignedTodoTaskCount > 0 {
            if !agents.isEmpty {
                recommendations.append(
                    BoardHealthRecommendation(
                        action: .autoAssignUnassignedTodo,
                        title: message("Auto-Assign Unowned To Do"),
                        detail: message("%d unassigned task(s) can be dispatched automatically", unassignedTodoTaskCount)
                    )
                )

                recommendations.append(
                    BoardHealthRecommendation(
                        action: .openManualTriage,
                        title: message("Run Manual Triage"),
                        detail: message("Open triage sheet to manually assign pending To Do tasks")
                    )
                )
            } else {
                recommendations.append(
                    BoardHealthRecommendation(
                        action: .openNewAgent,
                        title: message("Create First Agent"),
                        detail: message("Add an agent profile so pending To Do tasks can be assigned")
                    )
                )
            }
        }

        if canRebalanceTodoAssignments() {
            recommendations.append(
                BoardHealthRecommendation(
                    action: .rebalanceTodoLoad,
                    title: message("Rebalance Overloaded Agents"),
                    detail: message("Move eligible To Do tasks away from overloaded agents")
                )
            )
        }

        if wipPressurePercent(for: .inProgress) >= 100, wipLimit(for: .inProgress) != nil {
            recommendations.append(
                BoardHealthRecommendation(
                    action: .increaseWIPLimit(.inProgress),
                    title: message("Increase In Progress WIP"),
                    detail: message("In Progress is at or above its WIP limit")
                )
            )
        }

        if wipPressurePercent(for: .review) >= 100, wipLimit(for: .review) != nil {
            recommendations.append(
                BoardHealthRecommendation(
                    action: .increaseWIPLimit(.review),
                    title: message("Increase Review WIP"),
                    detail: message("Review is at or above its WIP limit")
                )
            )
        }

        if doneTaskCount > 0 {
            recommendations.append(
                BoardHealthRecommendation(
                    action: .archiveDone,
                    title: message("Archive Done Tasks"),
                    detail: message("%d completed task(s) can be archived", doneTaskCount)
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

        case .createMissingDependencyTasks:
            return createMissingDependencyTasks() > 0

        case .rebalanceTodoLoad:
            return rebalanceTodoAssignments() > 0

        case .openManualTriage:
            return !triageCandidates().isEmpty

        case .openNewAgent:
            return agents.isEmpty

        case let .increaseWIPLimit(status):
            guard let currentLimit = wipLimit(for: status) else {
                lastBoardMessage = message("%@ has no configured WIP limit", message(status.title))
                return false
            }
            return updateWIPLimit(for: status, limit: currentLimit + 1)

        case .archiveDone:
            return clearDoneTasks() > 0
        }
    }

    @discardableResult
    func createMissingDependencyTasks(storyPoints: Int = 1) -> Int {
        let missingDependencies = missingDependencyDescriptors()
        guard !missingDependencies.isEmpty else {
            lastBoardMessage = message("No missing dependency tasks were found")
            lastBoardMessageSeverity = .warning
            return 0
        }

        let normalizedStoryPoints = max(1, storyPoints)
        var createdTaskIDs: [UUID] = []
        createdTaskIDs.reserveCapacity(missingDependencies.count)

        for dependency in missingDependencies {
            var detailLines = [
                message(
                    "Auto-generated dependency task. Created because other tasks reference this dependency: %@",
                    dependency.reference.displayTitle
                )
            ]
            if !dependency.dependentTaskTitles.isEmpty {
                detailLines.append(
                    message("Referenced by tasks: %@", dependency.dependentTaskTitles.joined(separator: ", "))
                )
            }
            if !dependency.inferredSkills.isEmpty {
                detailLines.append(
                    message("Inferred required skills: %@", dependency.inferredSkills.joined(separator: ", "))
                )
            }

            let task = WorkTask(
                title: dependency.reference.displayTitle,
                details: detailLines.joined(separator: "\n"),
                requiredSkills: dependency.inferredSkills,
                storyPoints: normalizedStoryPoints,
                status: .todo,
                assignedAgentID: nil
            )
            tasks.append(task)
            createdTaskIDs.append(task.id)
            lastUnassignedTaskIDs.insert(task.id)
            lastAssignmentReasons[task.id] = nil
        }

        persistBoardState()
        lastBoardMessage = message("Created %d dependency placeholder task(s)", createdTaskIDs.count)
        lastBoardMessageSeverity = .info
        return createdTaskIDs.count
    }

    @discardableResult
    func applyAllHealthRecommendations() -> Int {
        var appliedCount = 0
        let maxPassCount = 5
        var pass = 0

        while pass < maxPassCount {
            pass += 1
            let actions = healthRecommendations().map(\.action).filter(\.isAutoFixable)
            guard !actions.isEmpty else { break }

            var advancedThisPass = false
            for action in actions {
                let before = HealthAutoFixSnapshot(
                    tasks: tasks,
                    agents: agents,
                    wipLimits: wipLimits,
                    unassignedTaskIDs: lastUnassignedTaskIDs,
                    assignmentReasons: lastAssignmentReasons
                )
                let applied = applyHealthRecommendation(action)
                let after = HealthAutoFixSnapshot(
                    tasks: tasks,
                    agents: agents,
                    wipLimits: wipLimits,
                    unassignedTaskIDs: lastUnassignedTaskIDs,
                    assignmentReasons: lastAssignmentReasons
                )
                let changed = before != after
                if applied && changed {
                    appliedCount += 1
                    advancedThisPass = true
                }
            }

            if !advancedThisPass {
                break
            }
        }

        if appliedCount > 0 {
            lastBoardMessage = message("Applied %d health recommendation(s)", appliedCount)
            lastBoardMessageSeverity = .info
        } else if !healthRecommendations().isEmpty {
            lastBoardMessage = message("No automatic fixes available for current recommendations")
            lastBoardMessageSeverity = .warning
        } else {
            lastBoardMessage = message("Board health already stable")
            lastBoardMessageSeverity = .info
        }

        return appliedCount
    }

    func agentName(for id: UUID?) -> String {
        guard let id else { return message("Unassigned") }
        return agents.first(where: { $0.id == id })?.name ?? message("Unknown")
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
                lastBoardMessage = message(
                    "Cannot set %@ WIP below current count (%d)",
                    message(status.title),
                    currentCount
                )
                return false
            }
        }

        wipLimits = candidateLimits
        persistBoardState()
        lastBoardMessage = nil
        return true
    }

    @discardableResult
    private func autoRelaxWIPLimitsForAutoCycle() -> Int {
        var limitUpdates: [KanbanStatus: Int?] = [:]

        if let inProgressLimit = wipLimit(for: .inProgress),
           wipPressurePercent(for: .inProgress) >= 100,
           hasRunnableTodoBlockedByInProgressWIP() {
            limitUpdates[.inProgress] = inProgressLimit + 1
        }

        if let reviewLimit = wipLimit(for: .review),
           wipPressurePercent(for: .review) >= 100,
           tasks.contains(where: { $0.status == .inProgress }) {
            limitUpdates[.review] = reviewLimit + 1
        }

        guard !limitUpdates.isEmpty else { return 0 }
        guard updateWIPLimits(limitUpdates) else { return 0 }
        lastBoardMessage = message("Auto-relaxed WIP limits this pass: +%d", limitUpdates.count)
        lastBoardMessageSeverity = .info
        return limitUpdates.count
    }

    private func hasRunnableTodoBlockedByInProgressWIP() -> Bool {
        tasks.contains { task in
            guard task.status == .todo else { return false }
            guard task.assignedAgentID != nil else { return false }
            guard !task.details.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
            guard unresolvedDependencies(for: task.id).isEmpty else { return false }
            guard !(requiresHumanApproval(for: task.id) && !isTaskApprovedForExecution(task.id)) else { return false }
            guard quotaCheckMessage(for: task) == nil else { return false }
            guard qualitySafetyGateBlockReason(for: task) == nil else { return false }
            return true
        }
    }

    func assignmentReason(for taskID: UUID) -> String? {
        lastAssignmentReasons[taskID]
    }

    func executionRecord(for taskID: UUID) -> TaskExecutionRecord? {
        tasks.first(where: { $0.id == taskID })?.executionRecord
    }

    func executionEvents(for agentID: UUID, limit: Int = 80) -> [AgentExecutionEvent] {
        let events = agentExecutionEventsByAgentID[agentID] ?? []
        guard limit > 0, events.count > limit else {
            return events.reversed()
        }
        return events.suffix(limit).reversed()
    }

    func executionTimeline(for taskID: UUID, limit: Int = 200) -> [AgentExecutionEvent] {
        let events = executionTimelineByTaskID[taskID] ?? []
        guard limit > 0, events.count > limit else {
            return events
        }
        return Array(events.suffix(limit))
    }

    func replayExecutionTimeline(for taskID: UUID, limit: Int = 200) -> String? {
        let events = executionTimeline(for: taskID, limit: limit)
        guard !events.isEmpty else { return nil }

        let formatter = ISO8601DateFormatter()
        return events.map { event in
            var lines: [String] = []
            lines.append(
                "[\(formatter.string(from: event.timestamp))] [\(event.phase.rawValue)] [\(event.status.rawValue)] \(event.message)"
            )
            if let details = normalizeExecutionText(event.details) {
                lines.append(details)
            }
            return lines.joined(separator: "\n")
        }
        .joined(separator: "\n\n")
    }

    func hasExecutionTimeline(for taskID: UUID) -> Bool {
        !(executionTimelineByTaskID[taskID] ?? []).isEmpty
    }

    func clearExecutionEvents(for agentID: UUID) {
        guard let removedEvents = agentExecutionEventsByAgentID[agentID], !removedEvents.isEmpty else {
            agentExecutionEventsByAgentID[agentID] = []
            return
        }
        agentExecutionEventsByAgentID[agentID] = []

        let removedEventIDs = Set(removedEvents.map(\.id))
        for (taskID, timelineEvents) in executionTimelineByTaskID {
            let filtered = timelineEvents.filter { !removedEventIDs.contains($0.id) }
            executionTimelineByTaskID[taskID] = filtered
        }
        executionTimelineByTaskID = executionTimelineByTaskID.filter { !$0.value.isEmpty }
    }

    func clearExecutionTimeline(for taskID: UUID) {
        executionTimelineByTaskID[taskID] = []
    }

    func addSharedAgentMemoryNote(_ note: String) -> Bool {
        let normalizedNote = normalizeExecutionText(note)
        guard let normalizedNote else {
            lastBoardMessage = message("Shared memory note is empty")
            lastBoardMessageSeverity = .warning
            return false
        }
        appendSharedAgentMemoryEntry(
            SharedAgentMemoryEntry(
                source: .manual,
                agentID: nil,
                agentName: message("Human"),
                taskID: nil,
                taskTitle: message("Manual note"),
                summary: normalizedNote
            )
        )
        persistBoardState()
        lastBoardMessage = message("Shared memory note added")
        lastBoardMessageSeverity = .info
        return true
    }

    func removeSharedAgentMemoryEntry(_ entryID: UUID) {
        sharedAgentMemory.removeAll { $0.id == entryID }
        persistBoardState()
    }

    func clearSharedAgentMemory() {
        sharedAgentMemory = []
        persistBoardState()
        lastBoardMessage = message("Cleared shared memory")
        lastBoardMessageSeverity = .warning
    }

    func updateSharedAgentMemoryProviderMode(_ mode: SharedAgentMemoryProviderMode) {
        guard sharedAgentMemoryProviderMode != mode else { return }
        sharedAgentMemoryProviderMode = mode
        persistBoardState()
        lastBoardMessage = message("Updated shared memory mode: %@", mode.title)
        lastBoardMessageSeverity = .info
    }

    func updateSharedAgentMemoryPreferredProviderID(_ providerID: String?) {
        let normalized = Self.normalizedProviderDescriptorID(providerID)
        guard sharedAgentMemoryPreferredProviderID != normalized else { return }
        sharedAgentMemoryPreferredProviderID = normalized
        persistBoardState()
        if let normalized {
            lastBoardMessage = message("Preferred shared memory provider: %@", normalized)
        } else {
            lastBoardMessage = message("Preferred shared memory provider: Auto")
        }
        lastBoardMessageSeverity = .info
    }

    func updateSharedAgentMemoryProviderEnabled(_ providerID: String, isEnabled: Bool) {
        guard let normalized = Self.normalizedProviderDescriptorID(providerID) else { return }
        let changed: Bool
        if isEnabled {
            changed = sharedAgentMemoryMutedProviderIDs.remove(normalized) != nil
        } else {
            let (inserted, _) = sharedAgentMemoryMutedProviderIDs.insert(normalized)
            changed = inserted
            if sharedAgentMemoryPreferredProviderID == normalized {
                sharedAgentMemoryPreferredProviderID = nil
            }
        }
        guard changed else { return }
        persistBoardState()
        lastBoardMessage = isEnabled
            ? message("Enabled shared memory provider: %@", normalized)
            : message("Disabled shared memory provider: %@", normalized)
        lastBoardMessageSeverity = .info
    }

    func sharedMemoryProviders() -> [SharedAgentMemoryProviderDescriptor] {
        detectedLocalPMPlannerPluginRecords(in: pmPlanningPluginPolicy.pluginsDirectoryPath)
            .flatMap { record -> [SharedAgentMemoryProviderDescriptor] in
                let pluginID = (record.manifest.id ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                guard !pluginID.isEmpty else { return [] }
                guard !pmPlanningPluginPolicy.disabledPluginIDs.contains(pluginID.lowercased()) else { return [] }
                let pluginName = {
                    let trimmed = (record.manifest.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    return trimmed.isEmpty ? record.directoryURL.lastPathComponent : trimmed
                }()
                let commandIDs = Set(
                    (record.manifest.commands ?? [])
                        .filter { $0.enabled ?? true }
                        .compactMap { ($0.id ?? "").trimmingCharacters(in: .whitespacesAndNewlines) }
                )
                return (record.manifest.memoryProviders ?? []).compactMap { provider in
                    guard provider.enabled ?? true else { return nil }
                    let providerID = (provider.id ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    let commandID = (provider.commandID ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !providerID.isEmpty, !commandID.isEmpty else { return nil }
                    guard commandIDs.contains(commandID) else { return nil }
                    let title = {
                        let trimmed = (provider.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                        return trimmed.isEmpty ? providerID : trimmed
                    }()
                    let strategy = {
                        let trimmed = (provider.strategy ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                        return trimmed.isEmpty ? "context.injector" : trimmed
                    }()
                    return SharedAgentMemoryProviderDescriptor(
                        id: "\(pluginID).\(providerID)",
                        pluginID: pluginID,
                        pluginName: pluginName,
                        providerID: providerID,
                        title: title,
                        commandID: commandID,
                        strategy: strategy,
                        priority: provider.priority ?? 0
                    )
                }
            }
            .sorted { lhs, rhs in
                if lhs.priority == rhs.priority {
                    if lhs.pluginName.localizedCaseInsensitiveCompare(rhs.pluginName) == .orderedSame {
                        return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
                    }
                    return lhs.pluginName.localizedCaseInsensitiveCompare(rhs.pluginName) == .orderedAscending
                }
                return lhs.priority > rhs.priority
            }
    }

    func sharedMemoryExecutionProviders() -> [SharedAgentMemoryProviderDescriptor] {
        let available = sharedMemoryProviders().filter { descriptor in
            !sharedAgentMemoryMutedProviderIDs.contains(descriptor.id)
        }
        guard !available.isEmpty else { return [] }
        guard let preferredID = sharedAgentMemoryPreferredProviderID,
              let preferred = available.first(where: { $0.id == preferredID }) else {
            return available
        }
        let remaining = available.filter { $0.id != preferred.id }
        return [preferred] + remaining
    }

    func sharedAgentMemoryText(limit: Int = 80) -> String {
        let entries = sharedAgentMemoryEntries(limit: limit)
        guard !entries.isEmpty else { return "-" }
        return entries
            .map { entry in
                let timestamp = Self.iso8601Formatter.string(from: entry.createdAt)
                return "[\(timestamp)] \(entry.source.rawValue) \(entry.agentName) · \(entry.taskTitle): \(entry.summary)"
            }
            .joined(separator: "\n")
    }

    func clearLocalizedTransientBoardMessage() {
        lastBoardMessage = nil
        lastBoardMessageSeverity = nil
    }

    func showXcodeDeveloperDirectoryWarningIfNeeded(
        activeDeveloperDirectoryPath: String? = nil,
        installedXcodeDeveloperDirectoryPath: String? = nil,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) {
        let activePath = activeDeveloperDirectoryPath
            ?? Self.activeDeveloperDirectoryPath(environment: environment)
        let xcodeDeveloperPath = installedXcodeDeveloperDirectoryPath
            ?? Self.installedXcodeDeveloperDirectoryPath(fileManager: fileManager)
        guard let command = Self.xcodeSelectRepairCommandIfNeeded(
            activeDeveloperDirectoryPath: activePath,
            installedXcodeDeveloperDirectoryPath: xcodeDeveloperPath
        ) else {
            return
        }

        if let existingMessage = lastBoardMessage,
           !existingMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return
        }

        lastBoardMessage = message(
            "Xcode is installed, but active developer directory is CommandLineTools. Switch to full Xcode for app build/test: %@",
            command
        )
        lastBoardMessageSeverity = .warning
    }

    func isAgentExecutionRunning(_ agentID: UUID) -> Bool {
        tasks.contains { task in
            guard task.executionRecord?.status == .running else { return false }
            return task.executionRecord?.lastAgentID == agentID || task.assignedAgentID == agentID
        }
    }

    func requiresHumanApproval(for taskID: UUID) -> Bool {
        guard executionApprovalPolicy.isEnabled,
              let task = tasks.first(where: { $0.id == taskID }) else {
            return false
        }
        guard task.status == .todo || task.status == .inProgress else { return false }
        return task.storyPoints >= executionApprovalPolicy.minimumStoryPoints
    }

    func isTaskApprovedForExecution(_ taskID: UUID) -> Bool {
        taskExecutionApprovalsByTaskID[taskID] != nil
    }

    @discardableResult
    func approveTaskExecution(_ taskID: UUID, approvedBy: String = "Human") -> Bool {
        guard requiresHumanApproval(for: taskID) else { return false }
        taskExecutionApprovalsByTaskID[taskID] = TaskExecutionApproval(approvedBy: approvedBy)
        persistBoardState()
        if let task = tasks.first(where: { $0.id == taskID }) {
            lastBoardMessage = message("Approved run for %@", task.title)
            lastBoardMessageSeverity = .info
        }
        return true
    }

    @discardableResult
    func revokeTaskExecutionApproval(_ taskID: UUID) -> Bool {
        guard taskExecutionApprovalsByTaskID[taskID] != nil else { return false }
        taskExecutionApprovalsByTaskID[taskID] = nil
        persistBoardState()
        if let task = tasks.first(where: { $0.id == taskID }) {
            lastBoardMessage = message("Revoked run approval for %@", task.title)
            lastBoardMessageSeverity = .warning
        }
        return true
    }

    @discardableResult
    func approveAllPendingTaskExecutions(approvedBy: String = "Human") -> Int {
        let pendingTaskIDs = tasks
            .filter { requiresHumanApproval(for: $0.id) && !isTaskApprovedForExecution($0.id) }
            .map(\.id)
        guard !pendingTaskIDs.isEmpty else { return 0 }

        let approval = TaskExecutionApproval(approvedBy: approvedBy)
        for taskID in pendingTaskIDs {
            taskExecutionApprovalsByTaskID[taskID] = approval
        }
        persistBoardState()
        lastBoardMessage = message("Approved %d pending run(s)", pendingTaskIDs.count)
        lastBoardMessageSeverity = .info
        return pendingTaskIDs.count
    }

    func updateExecutionApprovalPolicy(
        isEnabled: Bool,
        minimumStoryPoints: Int
    ) {
        executionApprovalPolicy = ExecutionApprovalPolicy(
            isEnabled: isEnabled,
            minimumStoryPoints: minimumStoryPoints
        )
        if !executionApprovalPolicy.isEnabled {
            taskExecutionApprovalsByTaskID = [:]
        } else {
            taskExecutionApprovalsByTaskID = taskExecutionApprovalsByTaskID.filter { requiresHumanApproval(for: $0.key) }
        }
        persistBoardState()
        lastBoardMessage = message("Updated approval gate settings")
        lastBoardMessageSeverity = .info
    }

    func updateExecutionQuotaPolicy(
        isEnabled: Bool,
        maxEstimatedTokens: Int,
        maxEstimatedCostUSD: Double,
        costPer1KTokensUSD: Double
    ) {
        executionQuotaPolicy = ExecutionQuotaPolicy(
            isEnabled: isEnabled,
            maxEstimatedTokens: maxEstimatedTokens,
            maxEstimatedCostUSD: maxEstimatedCostUSD,
            costPer1KTokensUSD: costPer1KTokensUSD
        )
        persistBoardState()
        lastBoardMessage = message("Updated quota governance settings")
        lastBoardMessageSeverity = .info
    }

    func updateExecutionParallelizationPolicy(
        isEnabled: Bool,
        maxConcurrentAgents: Int
    ) {
        executionParallelizationPolicy = ExecutionParallelizationPolicy(
            isEnabled: isEnabled,
            maxConcurrentAgents: maxConcurrentAgents
        )
        persistBoardState()
        lastBoardMessage = message("Updated parallel scheduler settings")
        lastBoardMessageSeverity = .info
    }

    func updateGitHubPRQualityGatePolicy(
        isEnabled: Bool,
        commands: [String]? = nil
    ) {
        let resolvedCommands = commands ?? gitHubPRQualityGatePolicy.commands
        gitHubPRQualityGatePolicy = GitHubPRQualityGatePolicy(
            isEnabled: isEnabled,
            commands: resolvedCommands
        )
        persistBoardState()
        lastBoardMessage = message("Updated PR quality gate settings")
        lastBoardMessageSeverity = .info
    }

    func gitHubPRQualityGateSummaryText() -> String {
        message("PR quality gate commands: %d", gitHubPRQualityGatePolicy.commands.count)
    }

    func updateDAGExecutionPolicy(
        isEnabled: Bool,
        autoAssignBeforeRun: Bool,
        autoAssignFallbackWithoutSkillMatch: Bool,
        autoRelaxWIPLimitsDuringRun: Bool = true,
        autoCreateMissingDependenciesDuringRun: Bool,
        maxPasses: Int
    ) {
        dagExecutionPolicy = DAGExecutionPolicy(
            isEnabled: isEnabled,
            autoAssignBeforeRun: autoAssignBeforeRun,
            autoAssignFallbackWithoutSkillMatch: autoAssignFallbackWithoutSkillMatch,
            autoRelaxWIPLimitsDuringRun: autoRelaxWIPLimitsDuringRun,
            autoCreateMissingDependenciesDuringRun: autoCreateMissingDependenciesDuringRun,
            maxPasses: maxPasses
        )
        persistBoardState()
        lastBoardMessage = message("Updated DAG scheduler settings")
        lastBoardMessageSeverity = .info
    }

    func updateExecutionQualitySafetyGatePolicy(
        isEnabled: Bool,
        requireAcceptanceCriteria: Bool,
        requireTestCoverageIntent: Bool,
        requireSecurityPrivacyForSensitiveTasks: Bool
    ) {
        executionQualitySafetyGatePolicy = ExecutionQualitySafetyGatePolicy(
            isEnabled: isEnabled,
            requireAcceptanceCriteria: requireAcceptanceCriteria,
            requireTestCoverageIntent: requireTestCoverageIntent,
            requireSecurityPrivacyForSensitiveTasks: requireSecurityPrivacyForSensitiveTasks,
            sensitiveKeywords: executionQualitySafetyGatePolicy.sensitiveKeywords
        )
        persistBoardState()
        lastBoardMessage = message("Updated quality & safety gate settings")
        lastBoardMessageSeverity = .info
    }

    func executionQualitySafetyGateSummaryText() -> String {
        guard executionQualitySafetyGatePolicy.isEnabled else {
            return message("Quality/safety gate is off")
        }
        return message("Quality/safety gate is on")
    }

    func updateExecutionRealArtifactVerificationPolicy(
        isEnabled: Bool,
        requireInfoPlistExecutableKey: Bool,
        requireXcodeBuild: Bool
    ) {
        let updatedPolicy = ExecutionRealArtifactVerificationPolicy(
            isEnabled: isEnabled,
            requireInfoPlistExecutableKey: requireInfoPlistExecutableKey,
            requireXcodeBuild: requireXcodeBuild
        )
        executionRealArtifactVerificationDefaultPolicy = updatedPolicy
        if selectedBoardUsesDefaultRealArtifactVerificationPolicy {
            executionRealArtifactVerificationPolicy = updatedPolicy
        }
        _ = syncSystemRealArtifactVerificationBoardHookBinding()
        syncCurrentBoardRecord()
        persistBoardState()
        lastBoardMessage = message("Updated real artifact verification defaults")
        lastBoardMessageSeverity = .info
    }

    func updateSelectedBoardExecutionRealArtifactVerificationPolicy(
        isEnabled: Bool,
        requireInfoPlistExecutableKey: Bool,
        requireXcodeBuild: Bool,
        announce: Bool = true
    ) {
        updateSelectedBoardExecutionRealArtifactVerificationPolicy(
            ExecutionRealArtifactVerificationPolicy(
                isEnabled: isEnabled,
                requireInfoPlistExecutableKey: requireInfoPlistExecutableKey,
                requireXcodeBuild: requireXcodeBuild
            ),
            announce: announce
        )
    }

    func updateSelectedBoardExecutionRealArtifactVerificationPolicy(
        _ policy: ExecutionRealArtifactVerificationPolicy,
        announce: Bool = true
    ) {
        selectedBoardUsesDefaultRealArtifactVerificationPolicy = false
        executionRealArtifactVerificationPolicy = policy
        _ = syncSystemRealArtifactVerificationBoardHookBinding()
        syncCurrentBoardRecord()
        persistBoardState()
        guard announce else { return }
        lastBoardMessage = message("Updated board real artifact verification settings")
        lastBoardMessageSeverity = .info
    }

    func useDefaultRealArtifactVerificationPolicyForSelectedBoard(
        announce: Bool = true
    ) {
        selectedBoardUsesDefaultRealArtifactVerificationPolicy = true
        executionRealArtifactVerificationPolicy = executionRealArtifactVerificationDefaultPolicy
        _ = syncSystemRealArtifactVerificationBoardHookBinding()
        syncCurrentBoardRecord()
        persistBoardState()
        guard announce else { return }
        lastBoardMessage = message("Using developer default real artifact verification for this board")
        lastBoardMessageSeverity = .info
    }

    func executionRealArtifactVerificationSummaryText() -> String {
        guard executionRealArtifactVerificationPolicy.isEnabled else {
            return message("Real artifact verification is off")
        }
        let executionMode = executionRealArtifactVerificationPolicy.runVerificationOnlyOnTerminalTask
            ? message("Final task only")
            : message("Any strict app task")
        return message(
            "Real artifact verification is on (Info.plist: %@, xcodebuild: %@, mode: %@)",
            executionRealArtifactVerificationPolicy.requireInfoPlistExecutableKey ? message("On") : message("Off"),
            executionRealArtifactVerificationPolicy.requireXcodeBuild ? message("On") : message("Off"),
            executionMode
        )
    }

    func executionRealArtifactVerificationDefaultSummaryText() -> String {
        guard executionRealArtifactVerificationDefaultPolicy.isEnabled else {
            return message("Real artifact verification is off")
        }
        let executionMode = executionRealArtifactVerificationDefaultPolicy.runVerificationOnlyOnTerminalTask
            ? message("Final task only")
            : message("Any strict app task")
        return message(
            "Real artifact verification is on (Info.plist: %@, xcodebuild: %@, mode: %@)",
            executionRealArtifactVerificationDefaultPolicy.requireInfoPlistExecutableKey ? message("On") : message("Off"),
            executionRealArtifactVerificationDefaultPolicy.requireXcodeBuild ? message("On") : message("Off"),
            executionMode
        )
    }

    func updatePMPlannerEngineMode(_ mode: PMPlannerEngineMode, announce: Bool = true) {
        pmPlannerEngineMode = mode
        persistBoardState()
        guard announce else { return }
        lastBoardMessage = message("Updated PM planning engine mode")
        lastBoardMessageSeverity = .info
    }

    private func updatePMPlanningPolicyState(
        autoDiscoverLocalPlugins: Bool? = nil,
        pluginsDirectoryPath: String? = nil,
        disabledPluginIDs: Set<String>? = nil,
        marketplaceSources: [PMExtensionMarketplaceSource]? = nil,
        preferredMarketplaceChannel: PMExtensionUpdateChannel? = nil,
        lockedPluginVersions: [String: String]? = nil
    ) {
        pmPlanningPluginPolicy = PMPlanningPluginPolicy(
            autoDiscoverLocalPlugins: autoDiscoverLocalPlugins ?? pmPlanningPluginPolicy.autoDiscoverLocalPlugins,
            pluginsDirectoryPath: pluginsDirectoryPath ?? pmPlanningPluginPolicy.pluginsDirectoryPath,
            disabledPluginIDs: disabledPluginIDs ?? pmPlanningPluginPolicy.disabledPluginIDs,
            marketplaceSources: marketplaceSources ?? pmPlanningPluginPolicy.marketplaceSources,
            preferredMarketplaceChannel: preferredMarketplaceChannel ?? pmPlanningPluginPolicy.preferredMarketplaceChannel,
            lockedPluginVersions: lockedPluginVersions ?? pmPlanningPluginPolicy.lockedPluginVersions
        )
    }

    func updatePMPlanningPluginPolicy(
        autoDiscoverLocalPlugins: Bool,
        pluginsDirectoryPath: String,
        announce: Bool = true
    ) {
        updatePMPlanningPolicyState(
            autoDiscoverLocalPlugins: autoDiscoverLocalPlugins,
            pluginsDirectoryPath: pluginsDirectoryPath
        )
        persistBoardState()
        guard announce else { return }
        lastBoardMessage = message("Updated PM plugin settings")
        lastBoardMessageSeverity = .info
    }

    func pmPlanningPluginStatusSummaryText() -> String {
        let localPluginCount = detectedLocalPMPlanningPlugins(in: pmPlanningPluginPolicy.pluginsDirectoryPath).count
        let modeTitle = pmPlannerEngineMode.title
        let discoveryText = pmPlanningPluginPolicy.autoDiscoverLocalPlugins ? message("On") : message("Off")
        return message(
            "PM plugins: mode=%@ · discovery=%@ · local=%d",
            modeTitle,
            discoveryText,
            localPluginCount
        )
    }

    func pmPlanningLocalPluginCount() -> Int {
        detectedLocalPMPlanningPlugins(in: pmPlanningPluginPolicy.pluginsDirectoryPath).count
    }

    func pmPlanningLocalPluginNames() -> [String] {
        detectedLocalPMPlanningPlugins(in: pmPlanningPluginPolicy.pluginsDirectoryPath)
    }

    func pmExtensionMarketplaceSources() -> [PMExtensionMarketplaceSource] {
        pmPlanningPluginPolicy.marketplaceSources
    }

    @discardableResult
    func addPMExtensionMarketplaceSource(name: String, source: String) -> Bool {
        let trimmedSource = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSource.isEmpty else {
            lastBoardMessage = message("Marketplace source is required")
            lastBoardMessageSeverity = .warning
            return false
        }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedName = trimmedName.isEmpty ? trimmedSource : trimmedName
        let duplicate = pmPlanningPluginPolicy.marketplaceSources.contains {
            $0.source.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == trimmedSource.lowercased()
        }
        guard !duplicate else {
            lastBoardMessage = message("Marketplace source already exists")
            lastBoardMessageSeverity = .warning
            return false
        }

        var sources = pmPlanningPluginPolicy.marketplaceSources
        sources.append(PMExtensionMarketplaceSource(name: resolvedName, source: trimmedSource))
        updatePMPlanningPolicyState(marketplaceSources: sources)
        persistBoardState()
        lastBoardMessage = message("Added marketplace source: %@", resolvedName)
        lastBoardMessageSeverity = .info
        return true
    }

    @discardableResult
    func removePMExtensionMarketplaceSource(id: UUID) -> Bool {
        let original = pmPlanningPluginPolicy.marketplaceSources
        let filtered = original.filter { $0.id != id }
        guard filtered.count != original.count else { return false }
        updatePMPlanningPolicyState(marketplaceSources: filtered)
        persistBoardState()
        lastBoardMessage = message("Removed marketplace source")
        lastBoardMessageSeverity = .info
        return true
    }

    @discardableResult
    func installPMExtensionFromMarketplaceSource(id: UUID) -> Bool {
        guard let source = pmPlanningPluginPolicy.marketplaceSources.first(where: { $0.id == id }) else { return false }
        return installPMExtensionFromRemote(source.source)
    }

    @discardableResult
    func installPMExtensionByID(_ pluginID: String) -> Bool {
        let normalizedTarget = pluginID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedTarget.isEmpty else {
            lastBoardMessage = message("Extension id is required")
            lastBoardMessageSeverity = .warning
            return false
        }

        let candidates = pmExtensionSourceCandidates(for: normalizedTarget)
        guard let candidate = candidates.first else {
            lastBoardMessage = message("Extension not found in configured marketplace sources: %@", pluginID)
            lastBoardMessageSeverity = .warning
            return false
        }
        return installPMExtensionFromDirectory(candidate.path)
    }

    @discardableResult
    func updateAllPMExtensionsFromMarketplaceSources() -> (succeeded: Int, failed: Int) {
        var succeeded = 0
        var failed = 0
        for source in pmPlanningPluginPolicy.marketplaceSources {
            if installPMExtensionFromRemote(source.source) {
                succeeded += 1
            } else {
                failed += 1
            }
        }
        if pmPlanningPluginPolicy.marketplaceSources.isEmpty {
            lastBoardMessage = message("No marketplace sources configured")
            lastBoardMessageSeverity = .warning
        } else if failed == 0 {
            lastBoardMessage = message("Update all completed: %d source(s) succeeded", succeeded)
            lastBoardMessageSeverity = .info
        } else {
            lastBoardMessage = message("Update all completed: %d succeeded, %d failed", succeeded, failed)
            lastBoardMessageSeverity = .warning
        }
        return (succeeded, failed)
    }

    @discardableResult
    func setPMExtensionEnabled(pluginID: String, enabled: Bool) -> Bool {
        let normalizedPluginID = pluginID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedPluginID.isEmpty else { return false }

        var disabled = pmPlanningPluginPolicy.disabledPluginIDs
        let changed: Bool
        if enabled {
            changed = disabled.remove(normalizedPluginID) != nil
        } else {
            let countBefore = disabled.count
            disabled.insert(normalizedPluginID)
            changed = disabled.count != countBefore
        }
        guard changed else { return false }

        updatePMPlanningPolicyState(disabledPluginIDs: disabled)
        persistBoardState()
        lastBoardMessage = enabled
            ? message("Enabled extension: %@", pluginID)
            : message("Disabled extension: %@", pluginID)
        lastBoardMessageSeverity = .info
        return true
    }

    func pmPreferredExtensionChannel() -> PMExtensionUpdateChannel {
        pmPlanningPluginPolicy.preferredMarketplaceChannel
    }

    func updatePMPreferredExtensionChannel(_ channel: PMExtensionUpdateChannel) {
        guard channel != pmPlanningPluginPolicy.preferredMarketplaceChannel else { return }
        updatePMPlanningPolicyState(preferredMarketplaceChannel: channel)
        persistBoardState()
        lastBoardMessage = message("Updated extension update channel: %@", channel.title)
        lastBoardMessageSeverity = .info
    }

    func pmLockedExtensionVersions() -> [String: String] {
        pmPlanningPluginPolicy.lockedPluginVersions
    }

    @discardableResult
    func lockPMExtensionToInstalledVersion(pluginID: String) -> Bool {
        let normalizedPluginID = pluginID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedPluginID.isEmpty else { return false }
        guard let installed = pmInstalledExtensions().first(where: { $0.pluginID.lowercased() == normalizedPluginID }) else {
            return false
        }
        var locks = pmPlanningPluginPolicy.lockedPluginVersions
        locks[normalizedPluginID] = installed.version
        updatePMPlanningPolicyState(lockedPluginVersions: locks)
        persistBoardState()
        lastBoardMessage = message("Locked extension %@ to version %@", installed.name, installed.version)
        lastBoardMessageSeverity = .info
        return true
    }

    @discardableResult
    func unlockPMExtensionVersion(pluginID: String) -> Bool {
        let normalizedPluginID = pluginID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedPluginID.isEmpty else { return false }
        var locks = pmPlanningPluginPolicy.lockedPluginVersions
        guard locks.removeValue(forKey: normalizedPluginID) != nil else { return false }
        updatePMPlanningPolicyState(lockedPluginVersions: locks)
        persistBoardState()
        lastBoardMessage = message("Unlocked extension version: %@", pluginID)
        lastBoardMessageSeverity = .info
        return true
    }

    func pmInstalledExtensions() -> [PMInstalledExtensionDescriptor] {
        detectedLocalPMPlannerPluginRecords(in: pmPlanningPluginPolicy.pluginsDirectoryPath)
            .map { record in
                let pluginID = (record.manifest.id ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                let name = {
                    let trimmed = (record.manifest.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    return trimmed.isEmpty ? record.directoryURL.lastPathComponent : trimmed
                }()
                let version = (record.manifest.version ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                let summary = (record.manifest.summary ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                let capabilities = record.manifest.capabilities ?? []
                let commands = (record.manifest.commands ?? []).filter { $0.enabled ?? true }
                let uiExtensions = (record.manifest.uiExtensions ?? []).filter { $0.enabled ?? true }
                let normalizedPluginID = pluginID.isEmpty ? name.lowercased() : pluginID.lowercased()
                let isEnabled = !pmPlanningPluginPolicy.disabledPluginIDs.contains(normalizedPluginID)
                let compatibilitySummary = Self.pmExtensionCompatibilitySummary(
                    minVersion: record.manifest.minOpenMacVersion,
                    maxVersion: record.manifest.maxOpenMacVersion
                )
                let channel = Self.normalizedPMExtensionUpdateChannel(record.manifest.channel)
                let lockedVersion = pmPlanningPluginPolicy.lockedPluginVersions[normalizedPluginID]
                return PMInstalledExtensionDescriptor(
                    id: pluginID.isEmpty ? name.lowercased() : pluginID,
                    pluginID: pluginID.isEmpty ? name.lowercased() : pluginID,
                    name: name,
                    version: version.isEmpty ? "0.0.0" : version,
                    summary: summary,
                    directoryPath: record.directoryURL.path,
                    capabilityCount: capabilities.count,
                    uiExtensionCount: uiExtensions.count,
                    commandCount: commands.count,
                    isEnabled: isEnabled,
                    compatibilitySummary: compatibilitySummary,
                    channel: channel,
                    lockedVersion: lockedVersion
                )
            }
            .sorted { lhs, rhs in
                lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
    }

    func pmExtensionCommands(slot: String? = nil) -> [PMExtensionCommandDescriptor] {
        let normalizedFilter = slot.map { Self.normalizedExtensionCommandSlot($0) } ?? ""

        let pluginCommands = detectedLocalPMPlannerPluginRecords(in: pmPlanningPluginPolicy.pluginsDirectoryPath)
            .flatMap { record -> [PMExtensionCommandDescriptor] in
                let pluginID = (record.manifest.id ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                guard !pluginID.isEmpty else { return [] }
                guard !pmPlanningPluginPolicy.disabledPluginIDs.contains(pluginID.lowercased()) else { return [] }
                let pluginName = {
                    let trimmed = (record.manifest.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    return trimmed.isEmpty ? record.directoryURL.lastPathComponent : trimmed
                }()
                return (record.manifest.commands ?? []).compactMap { command in
                    guard command.enabled ?? true else { return nil }
                    let commandID = (command.id ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !commandID.isEmpty else { return nil }
                    let commandSlots = Self.normalizedExtensionCommandSlots(command.slots, singleSlot: command.slot)
                    if !normalizedFilter.isEmpty, !commandSlots.contains(normalizedFilter) {
                        return nil
                    }
                    let title = {
                        let trimmed = (command.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                        return trimmed.isEmpty ? commandID : trimmed
                    }()
                    let subtitle = (command.subtitle ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    let permissions = Self.normalizedExtensionPermissions(command.permissions ?? record.manifest.permissions ?? [])
                    return PMExtensionCommandDescriptor(
                        id: "\(pluginID).\(commandID)",
                        pluginID: pluginID,
                        pluginName: pluginName,
                        commandID: commandID,
                        title: title,
                        subtitle: subtitle,
                        slots: commandSlots,
                        permissions: permissions,
                        timeoutSeconds: Self.resolvedExtensionCommandTimeout(command.timeoutSeconds),
                        entrypoint: (command.entrypoint ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    )
                }
            }
        let allCommands = pluginCommands + systemPMExtensionCommands(slot: normalizedFilter)
        return allCommands
            .sorted { lhs, rhs in
                if lhs.pluginName.caseInsensitiveCompare(rhs.pluginName) == .orderedSame {
                    return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
                }
                return lhs.pluginName.localizedCaseInsensitiveCompare(rhs.pluginName) == .orderedAscending
            }
    }

    private func systemPMExtensionCommands(slot normalizedFilter: String) -> [PMExtensionCommandDescriptor] {
        let commands: [PMExtensionCommandDescriptor] = [
            PMExtensionCommandDescriptor(
                id: "\(Self.systemExtensionPluginID).\(Self.systemRealArtifactVerifyCommandID)",
                pluginID: Self.systemExtensionPluginID,
                pluginName: Self.systemExtensionPluginName,
                commandID: Self.systemRealArtifactVerifyCommandID,
                title: "Real Artifact Verify (System)",
                subtitle: "Run built-in install verification checks",
                slots: [Self.extensionCommandMarketplacePanelSlot],
                permissions: [],
                timeoutSeconds: nil,
                entrypoint: nil
            ),
            PMExtensionCommandDescriptor(
                id: "\(Self.systemExtensionPluginID).\(Self.systemGoogleStitchGenerateCommandID)",
                pluginID: Self.systemExtensionPluginID,
                pluginName: Self.systemExtensionPluginName,
                commandID: Self.systemGoogleStitchGenerateCommandID,
                title: "Generate Stitch UI Prompt",
                subtitle: "Create a polished UI direction and Stitch-ready prompt",
                slots: [Self.extensionCommandPlannerPanelSlot],
                permissions: [],
                timeoutSeconds: nil,
                entrypoint: nil
            )
        ]
        if normalizedFilter.isEmpty {
            return commands
        }
        return commands.filter { $0.slots.contains(normalizedFilter) }
    }

    func pmToolbarExtensionCommands() -> [PMExtensionCommandDescriptor] {
        pmExtensionCommands(slot: Self.extensionCommandDefaultSlot)
    }

    func pmTaskCardExtensionCommands() -> [PMExtensionCommandDescriptor] {
        pmExtensionCommands(slot: Self.extensionCommandTaskCardSlot)
    }

    func pmPlannerPanelExtensionCommands() -> [PMExtensionCommandDescriptor] {
        pmExtensionCommands(slot: Self.extensionCommandPlannerPanelSlot)
    }

    func pmKanbanToolbarExtensionCommands() -> [PMExtensionCommandDescriptor] {
        pmExtensionCommands(slot: Self.extensionCommandKanbanToolbarSlot)
    }

    func pmKanbanSidebarExtensionCommands() -> [PMExtensionCommandDescriptor] {
        pmExtensionCommands(slot: Self.extensionCommandKanbanSidebarSlot)
    }

    func pmMarketplacePanelExtensionCommands() -> [PMExtensionCommandDescriptor] {
        pmExtensionCommands(slot: Self.extensionCommandMarketplacePanelSlot)
    }

    func pmBoardExtensionHookDescriptors() -> [PMBoardExtensionHookDescriptor] {
        let commands = pmExtensionCommands()
        let installedByPluginID = Dictionary(
            uniqueKeysWithValues: pmInstalledExtensions().map { ($0.pluginID.lowercased(), $0.name) }
        )
        return pmBoardExtensionHookBindings.map { binding in
            let matchingCommand = commands.first(where: {
                $0.pluginID.caseInsensitiveCompare(binding.pluginID) == .orderedSame &&
                    $0.commandID.caseInsensitiveCompare(binding.commandID) == .orderedSame
            })
            let pluginName = matchingCommand?.pluginName
                ?? installedByPluginID[binding.pluginID.lowercased()]
                ?? binding.pluginID
            let commandTitle = matchingCommand?.title ?? binding.commandID
            return PMBoardExtensionHookDescriptor(
                id: binding.id,
                event: binding.event,
                pluginID: binding.pluginID,
                pluginName: pluginName,
                commandID: binding.commandID,
                commandTitle: commandTitle,
                isEnabled: binding.isEnabled
            )
        }
    }

    @discardableResult
    func addPMBoardExtensionHook(
        eventRawValue: String,
        commandDescriptorID: String
    ) -> Bool {
        let normalizedEvent = Self.normalizedPMExtensionHookEvent(eventRawValue)
        guard let event = PMExtensionHookEvent(rawValue: normalizedEvent) else {
            lastBoardMessage = message("Hook save failed: unsupported event")
            lastBoardMessageSeverity = .warning
            return false
        }

        let descriptorID = commandDescriptorID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !descriptorID.isEmpty,
              let descriptor = pmExtensionCommands().first(where: { $0.id == descriptorID }) else {
            lastBoardMessage = message("Hook save failed: extension command not found")
            lastBoardMessageSeverity = .warning
            return false
        }

        let isDuplicate = pmBoardExtensionHookBindings.contains(where: { binding in
            binding.event == event &&
                binding.pluginID.caseInsensitiveCompare(descriptor.pluginID) == .orderedSame &&
                binding.commandID.caseInsensitiveCompare(descriptor.commandID) == .orderedSame
        })
        guard !isDuplicate else {
            lastBoardMessage = message("Hook already configured for this event and command")
            lastBoardMessageSeverity = .info
            return false
        }

        pmBoardExtensionHookBindings.append(
            PMBoardExtensionHookBinding(
                event: event,
                pluginID: descriptor.pluginID,
                commandID: descriptor.commandID
            )
        )
        pmBoardExtensionHookBindings = Self.normalizedBoardExtensionHookBindings(pmBoardExtensionHookBindings)
        persistBoardState()
        lastBoardMessage = message("Saved board hook: %@ -> %@", event.rawValue, descriptor.title)
        lastBoardMessageSeverity = .info
        return true
    }

    @discardableResult
    func setPMBoardExtensionHookEnabled(
        hookID: UUID,
        isEnabled: Bool
    ) -> Bool {
        guard let index = pmBoardExtensionHookBindings.firstIndex(where: { $0.id == hookID }) else {
            return false
        }
        guard pmBoardExtensionHookBindings[index].isEnabled != isEnabled else {
            return false
        }
        pmBoardExtensionHookBindings[index].isEnabled = isEnabled
        persistBoardState()
        lastBoardMessage = isEnabled
            ? message("Enabled board hook")
            : message("Disabled board hook")
        lastBoardMessageSeverity = .info
        return true
    }

    @discardableResult
    func removePMBoardExtensionHook(hookID: UUID) -> Bool {
        guard let index = pmBoardExtensionHookBindings.firstIndex(where: { $0.id == hookID }) else {
            return false
        }
        pmBoardExtensionHookBindings.remove(at: index)
        persistBoardState()
        lastBoardMessage = message("Removed board hook")
        lastBoardMessageSeverity = .info
        return true
    }

    private struct PreparedPMExtensionCommandExecution {
        let descriptor: PMExtensionCommandDescriptor
        let workingDirectoryPath: String
        let shellCommand: String
        let payloadJSON: String
        let timeoutSeconds: Int
        let startedAt: Date
    }

    private struct PMExtensionCommandExecutionOutcome {
        let succeeded: Bool
        let responseMessage: String?
        let detail: String
        let outputSummary: String
        let error: String?
    }

    @discardableResult
    func runPMExtensionCommand(
        _ descriptor: PMExtensionCommandDescriptor,
        task: WorkTask? = nil,
        extensionInputs: [String: String] = [:]
    ) -> Bool {
        if isSystemPMExtensionCommand(descriptor) {
            return runSystemPMExtensionCommand(
                descriptor,
                task: task,
                extensionInputs: extensionInputs
            )
        }
        guard let prepared = preparePMExtensionCommandExecution(
            descriptor,
            task: task,
            extensionInputs: extensionInputs
        ) else {
            return false
        }
        let outcome = Self.executePMExtensionCommand(prepared)
        return finishPMExtensionCommandExecution(prepared, outcome: outcome)
    }

    func runPMExtensionCommandInBackground(
        _ descriptor: PMExtensionCommandDescriptor,
        task: WorkTask? = nil,
        extensionInputs: [String: String] = [:],
        completion: @escaping (Bool) -> Void
    ) {
        if isSystemPMExtensionCommand(descriptor) {
            runSystemPMExtensionCommandInBackground(
                descriptor,
                task: task,
                extensionInputs: extensionInputs,
                completion: completion
            )
            return
        }
        guard let prepared = preparePMExtensionCommandExecution(
            descriptor,
            task: task,
            extensionInputs: extensionInputs
        ) else {
            completion(false)
            return
        }
        runOnBackground { [weak self] in
            let outcome = Self.executePMExtensionCommand(prepared)
            self?.runOnMain { [weak self] in
                guard let self else {
                    completion(false)
                    return
                }
                let succeeded = self.finishPMExtensionCommandExecution(prepared, outcome: outcome)
                completion(succeeded)
            }
        }
    }

    private func isSystemPMExtensionCommand(_ descriptor: PMExtensionCommandDescriptor) -> Bool {
        descriptor.pluginID.caseInsensitiveCompare(Self.systemExtensionPluginID) == .orderedSame
    }

    @discardableResult
    private func runSystemPMExtensionCommand(
        _ descriptor: PMExtensionCommandDescriptor,
        task: WorkTask?,
        extensionInputs: [String: String]
    ) -> Bool {
        let startedAt = Date()
        lastBoardMessage = message("Running extension command: %@", descriptor.title)
        lastBoardMessageSeverity = .info
        markPMExtensionRunStarted(
            pluginID: descriptor.pluginID,
            pluginName: descriptor.pluginName,
            inputSummary: Self.summarizedExtensionInputs(extensionInputs)
        )
        appendPMExtensionActivity(
            pluginID: descriptor.pluginID,
            pluginName: descriptor.pluginName,
            commandID: descriptor.commandID,
            commandTitle: descriptor.title,
            outcome: .running,
            detail: "Started"
        )
        let outcome = executeSystemPMExtensionCommand(
            descriptor,
            task: task,
            extensionInputs: extensionInputs
        )
        return finishPMExtensionCommandExecution(
            descriptor: descriptor,
            startedAt: startedAt,
            timeoutSeconds: nil,
            outcome: outcome
        )
    }

    private func runSystemPMExtensionCommandInBackground(
        _ descriptor: PMExtensionCommandDescriptor,
        task: WorkTask?,
        extensionInputs: [String: String],
        completion: @escaping (Bool) -> Void
    ) {
        let startedAt = Date()
        lastBoardMessage = message("Running extension command: %@", descriptor.title)
        lastBoardMessageSeverity = .info
        markPMExtensionRunStarted(
            pluginID: descriptor.pluginID,
            pluginName: descriptor.pluginName,
            inputSummary: Self.summarizedExtensionInputs(extensionInputs)
        )
        appendPMExtensionActivity(
            pluginID: descriptor.pluginID,
            pluginName: descriptor.pluginName,
            commandID: descriptor.commandID,
            commandTitle: descriptor.title,
            outcome: .running,
            detail: "Started"
        )
        runOnBackground { [weak self] in
            guard let self else {
                completion(false)
                return
            }
            let outcome = self.executeSystemPMExtensionCommand(
                descriptor,
                task: task,
                extensionInputs: extensionInputs
            )
            self.runOnMain { [weak self] in
                guard let self else {
                    completion(false)
                    return
                }
                let succeeded = self.finishPMExtensionCommandExecution(
                    descriptor: descriptor,
                    startedAt: startedAt,
                    timeoutSeconds: nil,
                    outcome: outcome
                )
                completion(succeeded)
            }
        }
    }

    private func executeSystemPMExtensionCommand(
        _ descriptor: PMExtensionCommandDescriptor,
        task: WorkTask?,
        extensionInputs: [String: String]
    ) -> PMExtensionCommandExecutionOutcome {
        switch descriptor.commandID.lowercased() {
        case Self.systemRealArtifactVerifyCommandID:
            if let deferredVerification = runDeferredRealArtifactVerificationIfNeeded() {
                if deferredVerification.status == "failed" {
                    let detail = deferredVerification.detail
                    return PMExtensionCommandExecutionOutcome(
                        succeeded: false,
                        responseMessage: nil,
                        detail: detail,
                        outputSummary: Self.summarizedExtensionOutput(detail),
                        error: detail
                    )
                }
                let detail = deferredVerification.detail
                return PMExtensionCommandExecutionOutcome(
                    succeeded: true,
                    responseMessage: detail,
                    detail: detail,
                    outputSummary: Self.summarizedExtensionOutput(detail),
                    error: nil
                )
            }

            let contract = task?.resolvedDeliveryContract
            let policy = executionRealArtifactVerificationPolicy
            let detail: String
            if !policy.isEnabled || (!policy.requireInfoPlistExecutableKey && !policy.requireXcodeBuild) {
                detail = "Skipped: real install verification policy is disabled"
            } else if let contract,
                      contract.gateMode != .strict || contract.outputType != .app {
                detail = "Skipped: selected task is not strict app delivery"
            } else {
                detail = "Skipped: no succeeded strict app task eligible for deferred verification"
            }
            return PMExtensionCommandExecutionOutcome(
                succeeded: true,
                responseMessage: detail,
                detail: detail,
                outputSummary: Self.summarizedExtensionOutput(detail),
                error: nil
            )
        case Self.systemGoogleStitchGenerateCommandID:
            let output = Self.generateGoogleStitchPrompt(from: extensionInputs)
            let integration = Self.runGoogleStitchExternalCommandIfConfigured(
                output: output,
                environment: ProcessInfo.processInfo.environment
            )
            let detail = integration?.message ?? output.prompt
            return PMExtensionCommandExecutionOutcome(
                succeeded: integration?.succeeded ?? true,
                responseMessage: detail,
                detail: detail,
                outputSummary: Self.summarizedExtensionOutput(detail),
                error: integration?.succeeded == false ? detail : nil
            )
        default:
            let detail = "Unsupported system command: \(descriptor.commandID)"
            return PMExtensionCommandExecutionOutcome(
                succeeded: false,
                responseMessage: nil,
                detail: detail,
                outputSummary: Self.summarizedExtensionOutput(detail),
                error: detail
            )
        }
    }

    private func preparePMExtensionCommandExecution(
        _ descriptor: PMExtensionCommandDescriptor,
        task: WorkTask?,
        extensionInputs: [String: String]
    ) -> PreparedPMExtensionCommandExecution? {
        if pmPlanningPluginPolicy.disabledPluginIDs.contains(descriptor.pluginID.lowercased()) {
            lastBoardMessage = message("Extension command failed: plugin is disabled")
            lastBoardMessageSeverity = .warning
            appendPMExtensionActivity(
                pluginID: descriptor.pluginID,
                pluginName: descriptor.pluginName,
                commandID: descriptor.commandID,
                commandTitle: descriptor.title,
                outcome: .failed,
                detail: "Plugin is disabled"
            )
            return nil
        }
        let records = detectedLocalPMPlannerPluginRecords(in: pmPlanningPluginPolicy.pluginsDirectoryPath)
        guard let record = records.first(where: {
            (($0.manifest.id ?? "").trimmingCharacters(in: .whitespacesAndNewlines)) == descriptor.pluginID
        }) else {
            lastBoardMessage = message("Extension command failed: plugin not found")
            lastBoardMessageSeverity = .warning
            appendPMExtensionActivity(
                pluginID: descriptor.pluginID,
                pluginName: descriptor.pluginName,
                commandID: descriptor.commandID,
                commandTitle: descriptor.title,
                outcome: .failed,
                detail: "Plugin not found"
            )
            return nil
        }

        let entrypoint = {
            let commandEntrypoint = (descriptor.entrypoint ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !commandEntrypoint.isEmpty {
                return commandEntrypoint
            }
            return (record.manifest.entrypoint ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        }()
        guard !entrypoint.isEmpty else {
            lastBoardMessage = message("Extension command failed: plugin entrypoint is missing")
            lastBoardMessageSeverity = .warning
            appendPMExtensionActivity(
                pluginID: descriptor.pluginID,
                pluginName: descriptor.pluginName,
                commandID: descriptor.commandID,
                commandTitle: descriptor.title,
                outcome: .failed,
                detail: "Entrypoint is missing"
            )
            return nil
        }

        let declaredPermissions = Set(Self.normalizedExtensionPermissions(descriptor.permissions))
        if !declaredPermissions.isEmpty,
           !declaredPermissions.contains(Self.extensionCommandRequiredPermission) {
            lastBoardMessage = message(
                "Extension command blocked: missing %@ permission",
                Self.extensionCommandRequiredPermission
            )
            lastBoardMessageSeverity = .warning
            appendPMExtensionActivity(
                pluginID: descriptor.pluginID,
                pluginName: descriptor.pluginName,
                commandID: descriptor.commandID,
                commandTitle: descriptor.title,
                outcome: .failed,
                detail: "Missing permission: \(Self.extensionCommandRequiredPermission)"
            )
            return nil
        }
        if declaredPermissions.isEmpty {
            appendPMExtensionActivity(
                pluginID: descriptor.pluginID,
                pluginName: descriptor.pluginName,
                commandID: descriptor.commandID,
                commandTitle: descriptor.title,
                outcome: .info,
                detail: "No permissions declared; proceeding in compatibility mode"
            )
        }

        let resolvedEntrypointPath: String
        if entrypoint.hasPrefix("/") || entrypoint.hasPrefix("~") {
            resolvedEntrypointPath = (entrypoint as NSString).expandingTildeInPath
        } else {
            resolvedEntrypointPath = record.directoryURL.appendingPathComponent(entrypoint).path
        }

        let payload = PMExtensionCommandRequest(
            type: "command",
            commandID: descriptor.commandID,
            slots: descriptor.slots,
            boardName: selectedBoardName,
            projectName: selectedBoardName,
            projectBrief: "",
            extensionInputs: extensionInputs,
            selectedTask: task.map { selectedTask in
                PMExtensionCommandTaskDescriptor(
                    id: selectedTask.id,
                    title: selectedTask.title,
                    details: selectedTask.details,
                    status: selectedTask.status.rawValue,
                    storyPoints: selectedTask.storyPoints,
                    requiredSkills: selectedTask.requiredSkills.sorted(),
                    assignedAgent: agentName(for: selectedTask.assignedAgentID)
                )
            },
            availableAgents: agents.map { agent in
                PMExtensionCommandAgentDescriptor(
                    name: agent.name,
                    skills: Array(agent.skills).sorted(),
                    maxConcurrentTasks: agent.maxConcurrentTasks
                )
            }
        )
        guard let payloadData = try? JSONEncoder().encode(payload),
              let payloadJSON = String(data: payloadData, encoding: .utf8) else {
            lastBoardMessage = message("Extension command failed: could not build payload")
            lastBoardMessageSeverity = .warning
            appendPMExtensionActivity(
                pluginID: descriptor.pluginID,
                pluginName: descriptor.pluginName,
                commandID: descriptor.commandID,
                commandTitle: descriptor.title,
                outcome: .failed,
                detail: "Could not build command payload"
            )
            return nil
        }

        let startedAt = Date()
        lastBoardMessage = message("Running extension command: %@", descriptor.title)
        lastBoardMessageSeverity = .info
        markPMExtensionRunStarted(
            pluginID: descriptor.pluginID,
            pluginName: descriptor.pluginName,
            inputSummary: Self.summarizedExtensionInputs(extensionInputs)
        )
        appendPMExtensionActivity(
            pluginID: descriptor.pluginID,
            pluginName: descriptor.pluginName,
            commandID: descriptor.commandID,
            commandTitle: descriptor.title,
            outcome: .running,
            detail: "Started"
        )

        return PreparedPMExtensionCommandExecution(
            descriptor: descriptor,
            workingDirectoryPath: record.directoryURL.path,
            shellCommand: Self.shellQuoted(resolvedEntrypointPath),
            payloadJSON: payloadJSON,
            timeoutSeconds: descriptor.timeoutSeconds ?? Self.extensionCommandDefaultTimeoutSeconds,
            startedAt: startedAt
        )
    }

    private static func executePMExtensionCommand(
        _ prepared: PreparedPMExtensionCommandExecution
    ) -> PMExtensionCommandExecutionOutcome {
        do {
            let result = try runShellCommand(
                prepared.shellCommand,
                workingDirectoryPath: prepared.workingDirectoryPath,
                stdin: prepared.payloadJSON,
                timeoutSeconds: prepared.timeoutSeconds,
                environment: ProcessInfo.processInfo.environment
            )

            if result.timedOut {
                let detail = "Timed out in \(prepared.timeoutSeconds)s"
                return PMExtensionCommandExecutionOutcome(
                    succeeded: false,
                    responseMessage: nil,
                    detail: detail,
                    outputSummary: detail,
                    error: detail
                )
            }

            if result.code != 0 {
                let stderr = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                let details = stderr.isEmpty ? result.stdout : stderr
                let detail = details.isEmpty ? "exit \(result.code)" : details
                return PMExtensionCommandExecutionOutcome(
                    succeeded: false,
                    responseMessage: nil,
                    detail: detail,
                    outputSummary: summarizedExtensionOutput(detail),
                    error: detail
                )
            }

            let stdout = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            let responseMessage = decodedPMExtensionCommandResponseMessage(from: stdout)
            let detail = responseMessage ?? "Completed"
            return PMExtensionCommandExecutionOutcome(
                succeeded: true,
                responseMessage: responseMessage,
                detail: detail,
                outputSummary: summarizedExtensionOutput(responseMessage ?? stdout),
                error: nil
            )
        } catch {
            let detail = error.localizedDescription
            return PMExtensionCommandExecutionOutcome(
                succeeded: false,
                responseMessage: nil,
                detail: detail,
                outputSummary: summarizedExtensionOutput(detail),
                error: detail
            )
        }
    }

    @discardableResult
    private func finishPMExtensionCommandExecution(
        _ prepared: PreparedPMExtensionCommandExecution,
        outcome: PMExtensionCommandExecutionOutcome
    ) -> Bool {
        finishPMExtensionCommandExecution(
            descriptor: prepared.descriptor,
            startedAt: prepared.startedAt,
            timeoutSeconds: prepared.timeoutSeconds,
            outcome: outcome
        )
    }

    @discardableResult
    private func finishPMExtensionCommandExecution(
        descriptor: PMExtensionCommandDescriptor,
        startedAt: Date,
        timeoutSeconds: Int?,
        outcome: PMExtensionCommandExecutionOutcome
    ) -> Bool {
        if outcome.succeeded {
            if let responseMessage = outcome.responseMessage, !responseMessage.isEmpty {
                lastBoardMessage = message("Extension command completed: %@", responseMessage)
            } else {
                lastBoardMessage = message("Extension command completed: %@", descriptor.title)
            }
            lastBoardMessageSeverity = .info
            appendPMExtensionActivity(
                pluginID: descriptor.pluginID,
                pluginName: descriptor.pluginName,
                commandID: descriptor.commandID,
                commandTitle: descriptor.title,
                outcome: .succeeded,
                detail: outcome.detail
            )
        } else {
            if let timeoutSeconds, outcome.detail == "Timed out in \(timeoutSeconds)s" {
                lastBoardMessage = message("Extension command failed: timed out in %d seconds", timeoutSeconds)
            } else {
                lastBoardMessage = message("Extension command failed: %@", outcome.detail)
            }
            lastBoardMessageSeverity = .warning
            appendPMExtensionActivity(
                pluginID: descriptor.pluginID,
                pluginName: descriptor.pluginName,
                commandID: descriptor.commandID,
                commandTitle: descriptor.title,
                outcome: .failed,
                detail: outcome.detail
            )
        }

        markPMExtensionRunFinished(
            pluginID: descriptor.pluginID,
            pluginName: descriptor.pluginName,
            startedAt: startedAt,
            succeeded: outcome.succeeded,
            outputSummary: outcome.outputSummary,
            error: outcome.error
        )
        return outcome.succeeded
    }

    func triggerPMExtensionHooks(
        event: PMExtensionHookEvent,
        task: WorkTask?,
        additionalInputs: [String: String] = [:]
    ) {
        let eventKey = event.rawValue
        expireStalePMExtensionHookDedupKeys()
        let knownCommandDescriptors = pmExtensionCommands()
        let installedByPluginID = Dictionary(
            uniqueKeysWithValues: pmInstalledExtensions().map { ($0.pluginID.lowercased(), $0.name) }
        )

        func enqueueHookDescriptor(
            _ descriptor: PMExtensionCommandDescriptor,
            hookSource: String,
            hookBindingID: UUID? = nil
        ) {
            var mergedInputs = additionalInputs
            mergedInputs["hookEvent"] = eventKey
            mergedInputs["hookSource"] = hookSource
            if let hookBindingID {
                mergedInputs["hookBindingID"] = hookBindingID.uuidString
            }
            if let task {
                mergedInputs["taskID"] = task.id.uuidString
                mergedInputs["taskTitle"] = task.title
                mergedInputs["taskStatus"] = task.status.rawValue
            }
            let dedupTaskID = task?.id.uuidString ?? "none"
            let key = "\(eventKey)|\(descriptor.pluginID.lowercased())|\(descriptor.commandID.lowercased())|\(dedupTaskID)"
            enqueuePMExtensionHookWorkItem(
                PMExtensionHookWorkItem(
                    key: key,
                    event: event,
                    descriptor: descriptor,
                    task: task,
                    extensionInputs: mergedInputs,
                    retryCount: 0
                )
            )
        }

        let records = detectedLocalPMPlannerPluginRecords(in: pmPlanningPluginPolicy.pluginsDirectoryPath)
        for record in records {
            let pluginID = (record.manifest.id ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !pluginID.isEmpty else { continue }
            guard !pmPlanningPluginPolicy.disabledPluginIDs.contains(pluginID.lowercased()) else { continue }

            let pluginName = {
                let trimmed = (record.manifest.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? record.directoryURL.lastPathComponent : trimmed
            }()
            let commands = (record.manifest.commands ?? []).filter { $0.enabled ?? true }
            let hooks = (record.manifest.eventHooks ?? []).filter { $0.enabled ?? true }

            func enqueueHookCommand(
                commandID: String,
                hookSource: String,
                hookBindingID: UUID? = nil
            ) {
                guard let commandManifest = commands.first(where: {
                    (($0.id ?? "").trimmingCharacters(in: .whitespacesAndNewlines))
                        .caseInsensitiveCompare(commandID) == .orderedSame
                }) else {
                    appendPMExtensionActivity(
                        pluginID: pluginID,
                        pluginName: pluginName,
                        commandID: commandID,
                        commandTitle: commandID,
                        outcome: .info,
                        detail: "Hook skipped: command not found (\(hookSource))"
                    )
                    return
                }

                let resolvedCommandID = (commandManifest.id ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                guard !resolvedCommandID.isEmpty else { return }

                let title = {
                    let trimmed = (commandManifest.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    return trimmed.isEmpty ? resolvedCommandID : trimmed
                }()
                let subtitle = (commandManifest.subtitle ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                let permissions = Self.normalizedExtensionPermissions(commandManifest.permissions ?? record.manifest.permissions ?? [])
                let descriptor = PMExtensionCommandDescriptor(
                    id: "\(pluginID).\(resolvedCommandID)",
                    pluginID: pluginID,
                    pluginName: pluginName,
                    commandID: resolvedCommandID,
                    title: title,
                    subtitle: subtitle,
                    slots: Self.normalizedExtensionCommandSlots(commandManifest.slots, singleSlot: commandManifest.slot),
                    permissions: permissions,
                    timeoutSeconds: Self.resolvedExtensionCommandTimeout(commandManifest.timeoutSeconds),
                    entrypoint: (commandManifest.entrypoint ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                )
                enqueueHookDescriptor(
                    descriptor,
                    hookSource: hookSource,
                    hookBindingID: hookBindingID
                )
            }

            for hook in hooks {
                let hookEvent = Self.normalizedPMExtensionHookEvent(hook.event ?? "")
                guard hookEvent == eventKey else { continue }
                let commandID = (hook.commandID ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                guard !commandID.isEmpty else { continue }
                enqueueHookCommand(commandID: commandID, hookSource: "manifest")
            }
        }

        let boardHooks = pmBoardExtensionHookBindings.filter { binding in
            binding.isEnabled && binding.event.rawValue == eventKey
        }
        for binding in boardHooks {
            guard let descriptor = knownCommandDescriptors.first(where: { candidate in
                candidate.pluginID.caseInsensitiveCompare(binding.pluginID) == .orderedSame &&
                    candidate.commandID.caseInsensitiveCompare(binding.commandID) == .orderedSame
            }) else {
                let pluginName = installedByPluginID[binding.pluginID.lowercased()] ?? binding.pluginID
                appendPMExtensionActivity(
                    pluginID: binding.pluginID,
                    pluginName: pluginName,
                    commandID: binding.commandID,
                    commandTitle: binding.commandID,
                    outcome: .info,
                    detail: "Hook skipped: command not found (board)"
                )
                continue
            }
            enqueueHookDescriptor(
                descriptor,
                hookSource: "board",
                hookBindingID: binding.id
            )
        }
        drainPMExtensionHookQueueIfNeeded()
    }

    @discardableResult
    func installPMExtensionFromDirectory(_ sourceDirectoryPath: String) -> Bool {
        let trimmedSourcePath = sourceDirectoryPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSourcePath.isEmpty else {
            lastBoardMessage = message("Extension install failed: source folder is empty")
            lastBoardMessageSeverity = .warning
            appendPMExtensionActivity(
                pluginID: "unknown",
                pluginName: "Unknown",
                commandID: nil,
                commandTitle: nil,
                outcome: .failed,
                detail: "Install failed: source folder is empty"
            )
            return false
        }

        let sourceURL = URL(fileURLWithPath: (trimmedSourcePath as NSString).expandingTildeInPath, isDirectory: true)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: sourceURL.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            lastBoardMessage = message("Extension install failed: source folder not found")
            lastBoardMessageSeverity = .warning
            appendPMExtensionActivity(
                pluginID: "unknown",
                pluginName: "Unknown",
                commandID: nil,
                commandTitle: nil,
                outcome: .failed,
                detail: "Install failed: source folder not found"
            )
            return false
        }

        guard let record = localPMPlanningPluginRecord(at: sourceURL) else {
            lastBoardMessage = message("Extension install failed: plugin.json/manifest.json is missing or invalid")
            lastBoardMessageSeverity = .warning
            appendPMExtensionActivity(
                pluginID: "unknown",
                pluginName: sourceURL.lastPathComponent,
                commandID: nil,
                commandTitle: nil,
                outcome: .failed,
                detail: "Install failed: plugin manifest is missing or invalid"
            )
            return false
        }

        let pluginID = (record.manifest.id ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !pluginID.isEmpty else {
            lastBoardMessage = message("Extension install failed: plugin id is required")
            lastBoardMessageSeverity = .warning
            appendPMExtensionActivity(
                pluginID: "unknown",
                pluginName: sourceURL.lastPathComponent,
                commandID: nil,
                commandTitle: nil,
                outcome: .failed,
                detail: "Install failed: plugin id is required"
            )
            return false
        }

        let pluginName = {
            let trimmed = (record.manifest.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? sourceURL.lastPathComponent : trimmed
        }()
        let normalizedPluginID = pluginID.lowercased()
        if pmExtensionInstallStack.contains(normalizedPluginID) {
            lastBoardMessage = message("Extension install blocked: cyclic dependency detected for %@", pluginID)
            lastBoardMessageSeverity = .warning
            appendPMExtensionActivity(
                pluginID: pluginID,
                pluginName: pluginName,
                commandID: nil,
                commandTitle: nil,
                outcome: .failed,
                detail: "Install blocked: cyclic dependency detected"
            )
            return false
        }
        pmExtensionInstallStack.insert(normalizedPluginID)
        defer { pmExtensionInstallStack.remove(normalizedPluginID) }
        if let violation = Self.pmExtensionCompatibilityViolation(
            minVersion: record.manifest.minOpenMacVersion,
            maxVersion: record.manifest.maxOpenMacVersion
        ) {
            lastBoardMessage = message("Extension install blocked: %@", violation)
            lastBoardMessageSeverity = .warning
            appendPMExtensionActivity(
                pluginID: pluginID,
                pluginName: pluginName,
                commandID: nil,
                commandTitle: nil,
                outcome: .failed,
                detail: "Install blocked: \(violation)"
            )
            return false
        }
        let pluginVersion = (record.manifest.version ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let pluginChannel = Self.normalizedPMExtensionUpdateChannel(record.manifest.channel)
        if !Self.isAllowedPMExtensionUpdateChannel(
            pluginChannel,
            preferred: pmPlanningPluginPolicy.preferredMarketplaceChannel
        ) {
            lastBoardMessage = message(
                "Extension install blocked: %@ channel is not allowed by %@ policy",
                pluginChannel.title,
                pmPlanningPluginPolicy.preferredMarketplaceChannel.title
            )
            lastBoardMessageSeverity = .warning
            appendPMExtensionActivity(
                pluginID: pluginID,
                pluginName: pluginName,
                commandID: nil,
                commandTitle: nil,
                outcome: .failed,
                detail: "Install blocked: channel \(pluginChannel.rawValue) not allowed"
            )
            return false
        }
        if let lockedVersion = pmPlanningPluginPolicy.lockedPluginVersions[normalizedPluginID],
           !pluginVersion.isEmpty,
           pluginVersion != lockedVersion {
            lastBoardMessage = message(
                "Extension install blocked: %@ is version-locked to %@",
                pluginID,
                lockedVersion
            )
            lastBoardMessageSeverity = .warning
            appendPMExtensionActivity(
                pluginID: pluginID,
                pluginName: pluginName,
                commandID: nil,
                commandTitle: nil,
                outcome: .failed,
                detail: "Install blocked: locked to \(lockedVersion), incoming \(pluginVersion)"
            )
            return false
        }

        let installedPluginIDs = Set(pmInstalledExtensions().map { $0.pluginID.lowercased() })
        let dependencyIDs = Set((record.manifest.dependencies ?? []).map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        }).subtracting(["", normalizedPluginID])
        for dependencyID in dependencyIDs.sorted() where !installedPluginIDs.contains(dependencyID) {
            appendPMExtensionActivity(
                pluginID: pluginID,
                pluginName: pluginName,
                commandID: nil,
                commandTitle: nil,
                outcome: .info,
                detail: "Auto-installing dependency: \(dependencyID)"
            )
            guard installPMExtensionByID(dependencyID) else {
                lastBoardMessage = message("Extension install blocked: missing dependency %@", dependencyID)
                lastBoardMessageSeverity = .warning
                appendPMExtensionActivity(
                    pluginID: pluginID,
                    pluginName: pluginName,
                    commandID: nil,
                    commandTitle: nil,
                    outcome: .failed,
                    detail: "Install blocked: missing dependency \(dependencyID)"
                )
                return false
            }
        }
        appendPMExtensionActivity(
            pluginID: pluginID,
            pluginName: pluginName,
            commandID: nil,
            commandTitle: nil,
            outcome: .running,
            detail: "Installing from folder: \(sourceURL.path)"
        )

        let destinationRootPath = (pmPlanningPluginPolicy.pluginsDirectoryPath as NSString).expandingTildeInPath
        let destinationRootURL = URL(fileURLWithPath: destinationRootPath, isDirectory: true)

        do {
            try FileManager.default.createDirectory(at: destinationRootURL, withIntermediateDirectories: true)
        } catch {
            lastBoardMessage = message("Extension install failed: %@", error.localizedDescription)
            lastBoardMessageSeverity = .warning
            appendPMExtensionActivity(
                pluginID: pluginID,
                pluginName: pluginName,
                commandID: nil,
                commandTitle: nil,
                outcome: .failed,
                detail: "Install failed: \(error.localizedDescription)"
            )
            return false
        }

        let baseFolderName = Self.sanitizedExtensionDirectoryName(pluginID, fallback: sourceURL.lastPathComponent)
        let sourceCanonicalPath = sourceURL.standardizedFileURL.path
        let existingPluginRecords = detectedLocalPMPlannerPluginRecords(in: destinationRootURL.path)
        let activePluginIDs = Set(
            existingPluginRecords.compactMap { item -> String? in
                let installedID = (item.manifest.id ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                guard !installedID.isEmpty else { return nil }
                guard !pmPlanningPluginPolicy.disabledPluginIDs.contains(installedID) else { return nil }
                return installedID
            }
        )
        let newPluginConflicts = Set((record.manifest.conflictsWith ?? []).map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        }).subtracting(["", normalizedPluginID])
        if let conflictingID = newPluginConflicts.first(where: { activePluginIDs.contains($0) }) {
            lastBoardMessage = message("Extension install blocked: conflicts with installed plugin %@", conflictingID)
            lastBoardMessageSeverity = .warning
            appendPMExtensionActivity(
                pluginID: pluginID,
                pluginName: pluginName,
                commandID: nil,
                commandTitle: nil,
                outcome: .failed,
                detail: "Install blocked: conflicts with \(conflictingID)"
            )
            return false
        }
        if let reverseConflict = existingPluginRecords.first(where: { item in
            let installedID = (item.manifest.id ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !installedID.isEmpty, installedID != normalizedPluginID else { return false }
            guard !pmPlanningPluginPolicy.disabledPluginIDs.contains(installedID) else { return false }
            let conflicts = Set((item.manifest.conflictsWith ?? []).map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            })
            return conflicts.contains(normalizedPluginID)
        }) {
            let reverseID = (reverseConflict.manifest.id ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            lastBoardMessage = message("Extension install blocked: installed plugin %@ conflicts with %@", reverseID, pluginID)
            lastBoardMessageSeverity = .warning
            appendPMExtensionActivity(
                pluginID: pluginID,
                pluginName: pluginName,
                commandID: nil,
                commandTitle: nil,
                outcome: .failed,
                detail: "Install blocked: reverse conflict from \(reverseID)"
            )
            return false
        }

        let existingPluginRecord = existingPluginRecords.first {
            (($0.manifest.id ?? "").trimmingCharacters(in: .whitespacesAndNewlines)) == pluginID
        }
        var destinationURL = destinationRootURL.appendingPathComponent(baseFolderName, isDirectory: true)
        if let existingPluginRecord {
            destinationURL = existingPluginRecord.directoryURL
        } else {
            var index = 2
            while FileManager.default.fileExists(atPath: destinationURL.path),
                  destinationURL.standardizedFileURL.path != sourceCanonicalPath {
                destinationURL = destinationRootURL.appendingPathComponent("\(baseFolderName)-\(index)", isDirectory: true)
                index += 1
            }
        }

        if destinationURL.standardizedFileURL.path == sourceCanonicalPath {
            lastBoardMessage = message("Extension already installed: %@", pluginName)
            lastBoardMessageSeverity = .info
            appendPMExtensionActivity(
                pluginID: pluginID,
                pluginName: pluginName,
                commandID: nil,
                commandTitle: nil,
                outcome: .info,
                detail: "Install skipped: already installed"
            )
            return true
        }

        if let existingPluginRecord {
            let installedVersion = (existingPluginRecord.manifest.version ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !pluginVersion.isEmpty, installedVersion == pluginVersion {
                lastBoardMessage = message("Extension already up to date: %@ (v%@)", pluginName, pluginVersion)
                lastBoardMessageSeverity = .info
                appendPMExtensionActivity(
                    pluginID: pluginID,
                    pluginName: pluginName,
                    commandID: nil,
                    commandTitle: nil,
                    outcome: .info,
                    detail: "Already up to date (v\(pluginVersion))"
                )
                return true
            }
        }

        let previousVersion = (existingPluginRecord?.manifest.version ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let backupRootURL = destinationRootURL.appendingPathComponent(".openmac-extension-backups", isDirectory: true)
        let backupURL = backupRootURL.appendingPathComponent("\(baseFolderName)-\(UUID().uuidString)", isDirectory: true)
        var movedToBackup = false

        do {
            try FileManager.default.createDirectory(at: backupRootURL, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try FileManager.default.moveItem(at: destinationURL, to: backupURL)
                movedToBackup = true
            }
            try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
            if movedToBackup {
                try? FileManager.default.removeItem(at: backupURL)
            }
            let isUpdate = existingPluginRecord != nil
            let transition = Self.pmExtensionVersionTransitionLabel(
                previousVersion: previousVersion,
                incomingVersion: pluginVersion
            )
            lastBoardMessage = isUpdate
                ? message("Updated PM extension: %@", pluginName)
                : message("Installed PM extension: %@", pluginName)
            lastBoardMessageSeverity = .info
            appendPMExtensionActivity(
                pluginID: pluginID,
                pluginName: pluginName,
                commandID: nil,
                commandTitle: nil,
                outcome: .succeeded,
                detail: transition
            )
            return true
        } catch {
            if movedToBackup {
                try? FileManager.default.removeItem(at: destinationURL)
                if FileManager.default.fileExists(atPath: backupURL.path) {
                    try? FileManager.default.moveItem(at: backupURL, to: destinationURL)
                }
            }
            lastBoardMessage = message("Extension install failed: %@", error.localizedDescription)
            lastBoardMessageSeverity = .warning
            appendPMExtensionActivity(
                pluginID: pluginID,
                pluginName: pluginName,
                commandID: nil,
                commandTitle: nil,
                outcome: .failed,
                detail: movedToBackup
                    ? "Install failed and rolled back: \(error.localizedDescription)"
                    : "Install failed: \(error.localizedDescription)"
            )
            return false
        }
    }

    @discardableResult
    func uninstallPMExtension(pluginID: String) -> Bool {
        let trimmedPluginID = pluginID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPluginID.isEmpty else {
            lastBoardMessage = message("Extension remove failed: plugin id is required")
            lastBoardMessageSeverity = .warning
            return false
        }

        let records = detectedLocalPMPlannerPluginRecords(in: pmPlanningPluginPolicy.pluginsDirectoryPath)
        guard let record = records.first(where: {
            (($0.manifest.id ?? "").trimmingCharacters(in: .whitespacesAndNewlines)) == trimmedPluginID
        }) else {
            lastBoardMessage = message("Extension remove failed: plugin not found")
            lastBoardMessageSeverity = .warning
            appendPMExtensionActivity(
                pluginID: trimmedPluginID,
                pluginName: trimmedPluginID,
                commandID: nil,
                commandTitle: nil,
                outcome: .failed,
                detail: "Remove failed: plugin not found"
            )
            return false
        }

        do {
            try FileManager.default.removeItem(at: record.directoryURL)
            let pluginName = (record.manifest.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            var disabled = pmPlanningPluginPolicy.disabledPluginIDs
            disabled.remove(trimmedPluginID.lowercased())
            var locks = pmPlanningPluginPolicy.lockedPluginVersions
            locks.removeValue(forKey: trimmedPluginID.lowercased())
            updatePMPlanningPolicyState(disabledPluginIDs: disabled, lockedPluginVersions: locks)
            persistBoardState()
            lastBoardMessage = message(
                "Removed PM extension: %@",
                pluginName.isEmpty ? trimmedPluginID : pluginName
            )
            lastBoardMessageSeverity = .info
            appendPMExtensionActivity(
                pluginID: trimmedPluginID,
                pluginName: pluginName.isEmpty ? trimmedPluginID : pluginName,
                commandID: nil,
                commandTitle: nil,
                outcome: .succeeded,
                detail: "Removed"
            )
            return true
        } catch {
            lastBoardMessage = message("Extension remove failed: %@", error.localizedDescription)
            lastBoardMessageSeverity = .warning
            appendPMExtensionActivity(
                pluginID: trimmedPluginID,
                pluginName: trimmedPluginID,
                commandID: nil,
                commandTitle: nil,
                outcome: .failed,
                detail: "Remove failed: \(error.localizedDescription)"
            )
            return false
        }
    }

    @discardableResult
    func installPMExtensionFromRemote(_ remoteSource: String) -> Bool {
        let trimmedSource = remoteSource.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSource.isEmpty else {
            lastBoardMessage = message("Extension install failed: remote source is empty")
            lastBoardMessageSeverity = .warning
            return false
        }

        let fileManager = FileManager.default
        let tempRootURL = fileManager.temporaryDirectory.appendingPathComponent("openmac-extension-\(UUID().uuidString)", isDirectory: true)
        let extractionRootURL = tempRootURL.appendingPathComponent("payload", isDirectory: true)
        defer { try? fileManager.removeItem(at: tempRootURL) }
        do {
            try fileManager.createDirectory(at: extractionRootURL, withIntermediateDirectories: true)
        } catch {
            lastBoardMessage = message("Extension install failed: %@", error.localizedDescription)
            lastBoardMessageSeverity = .warning
            return false
        }

        appendPMExtensionActivity(
            pluginID: "remote",
            pluginName: "Remote Source",
            commandID: nil,
            commandTitle: nil,
            outcome: .running,
            detail: "Fetching extension source: \(trimmedSource)"
        )

        let expandedSourcePath = (trimmedSource as NSString).expandingTildeInPath
        let localSourceExists = fileManager.fileExists(atPath: expandedSourcePath)

        var candidateRootURL: URL?

        if localSourceExists {
            var isDirectory: ObjCBool = false
            if fileManager.fileExists(atPath: expandedSourcePath, isDirectory: &isDirectory), isDirectory.boolValue {
                candidateRootURL = URL(fileURLWithPath: expandedSourcePath, isDirectory: true)
            } else if Self.isLikelyZipSource(expandedSourcePath) {
                let unzipCommand = "/usr/bin/unzip -q \(Self.shellQuoted(expandedSourcePath)) -d \(Self.shellQuoted(extractionRootURL.path))"
                let unzipResult = try? Self.runShellCommand(unzipCommand)
                guard let unzipResult, unzipResult.code == 0 else {
                    let details = unzipResult?.output.trimmingCharacters(in: .whitespacesAndNewlines)
                    let failure = details?.isEmpty == false ? details! : "unzip failed"
                    lastBoardMessage = message("Extension install failed: %@", failure)
                    lastBoardMessageSeverity = .warning
                    appendPMExtensionActivity(
                        pluginID: "remote",
                        pluginName: "Remote Source",
                        commandID: nil,
                        commandTitle: nil,
                        outcome: .failed,
                        detail: "Unzip failed: \(failure)"
                    )
                    return false
                }
                candidateRootURL = extractionRootURL
            }
        } else if Self.isLikelyGitRemoteSource(trimmedSource) {
            let cloneURL = extractionRootURL.appendingPathComponent("repo", isDirectory: true)
            let cloneCommand = "/usr/bin/git clone --depth 1 \(Self.shellQuoted(trimmedSource)) \(Self.shellQuoted(cloneURL.path))"
            let cloneResult = try? Self.runShellCommand(cloneCommand)
            guard let cloneResult, cloneResult.code == 0 else {
                let details = cloneResult?.output.trimmingCharacters(in: .whitespacesAndNewlines)
                let failure = details?.isEmpty == false ? details! : "git clone failed"
                lastBoardMessage = message("Extension install failed: %@", failure)
                lastBoardMessageSeverity = .warning
                appendPMExtensionActivity(
                    pluginID: "remote",
                    pluginName: "Remote Source",
                    commandID: nil,
                    commandTitle: nil,
                    outcome: .failed,
                    detail: "Git clone failed: \(failure)"
                )
                return false
            }
            candidateRootURL = cloneURL
        } else if Self.isLikelyHTTPRemoteSource(trimmedSource) {
            let archiveURL = tempRootURL.appendingPathComponent("plugin.zip")
            let downloadCommand = "/usr/bin/curl -L --fail \(Self.shellQuoted(trimmedSource)) -o \(Self.shellQuoted(archiveURL.path))"
            let downloadResult = try? Self.runShellCommand(downloadCommand)
            guard let downloadResult, downloadResult.code == 0 else {
                let details = downloadResult?.output.trimmingCharacters(in: .whitespacesAndNewlines)
                let failure = details?.isEmpty == false ? details! : "download failed"
                lastBoardMessage = message("Extension install failed: %@", failure)
                lastBoardMessageSeverity = .warning
                appendPMExtensionActivity(
                    pluginID: "remote",
                    pluginName: "Remote Source",
                    commandID: nil,
                    commandTitle: nil,
                    outcome: .failed,
                    detail: "Remote download failed: \(failure)"
                )
                return false
            }
            let unzipCommand = "/usr/bin/unzip -q \(Self.shellQuoted(archiveURL.path)) -d \(Self.shellQuoted(extractionRootURL.path))"
            let unzipResult = try? Self.runShellCommand(unzipCommand)
            guard let unzipResult, unzipResult.code == 0 else {
                let details = unzipResult?.output.trimmingCharacters(in: .whitespacesAndNewlines)
                let failure = details?.isEmpty == false ? details! : "unzip failed"
                lastBoardMessage = message("Extension install failed: %@", failure)
                lastBoardMessageSeverity = .warning
                appendPMExtensionActivity(
                    pluginID: "remote",
                    pluginName: "Remote Source",
                    commandID: nil,
                    commandTitle: nil,
                    outcome: .failed,
                    detail: "Remote unzip failed: \(failure)"
                )
                return false
            }
            candidateRootURL = extractionRootURL
        }

        guard let candidateRootURL else {
            lastBoardMessage = message("Extension install failed: unsupported source")
            lastBoardMessageSeverity = .warning
            appendPMExtensionActivity(
                pluginID: "remote",
                pluginName: "Remote Source",
                commandID: nil,
                commandTitle: nil,
                outcome: .failed,
                detail: "Unsupported source"
            )
            return false
        }

        let pluginRootURL = firstPMExtensionDirectoryCandidate(in: candidateRootURL) ?? candidateRootURL
        let installed = installPMExtensionFromDirectory(pluginRootURL.path)
        if installed {
            appendPMExtensionActivity(
                pluginID: "remote",
                pluginName: "Remote Source",
                commandID: nil,
                commandTitle: nil,
                outcome: .succeeded,
                detail: "Installed from remote source"
            )
        }
        return installed
    }

    func clearPMExtensionActivityLog() {
        pmExtensionActivityLog = []
        objectWillChange.send()
    }

    func pmExtensionActivityLogText() -> String {
        pmExtensionActivityLog.map { entry in
            let timestamp = Self.iso8601Formatter.string(from: entry.timestamp)
            let commandText = (entry.commandID ?? "").isEmpty ? "-" : (entry.commandID ?? "-")
            return "[\(timestamp)] \(entry.outcome.rawValue.uppercased()) \(entry.pluginID) \(commandText) \(entry.detail)"
        }.joined(separator: "\n")
    }

    func pmExtensionObservabilityText() -> String {
        pmExtensionObservability.map { snapshot in
            let timestamp = snapshot.lastRunAt.map { Self.iso8601Formatter.string(from: $0) } ?? "-"
            let errorText = snapshot.lastError ?? "-"
            return "\(snapshot.pluginID) runs=\(snapshot.totalRuns) ok=\(snapshot.succeededRuns) fail=\(snapshot.failedRuns) success=\(snapshot.successRatePercent)% avg=\(snapshot.avgDurationMS)ms running=\(snapshot.runningCount) last=\(timestamp) input=\(snapshot.lastInputSummary) output=\(snapshot.lastOutputSummary) error=\(errorText)"
        }.joined(separator: "\n")
    }

    @discardableResult
    func runPMExtensionE2EAcceptance() -> PMExtensionE2EAcceptanceReport {
        let runToken = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        let shortToken = String(runToken.prefix(8))
        let pluginID = "com.openmac.e2e.acceptance.\(shortToken)"
        let pluginName = "OpenMac E2E Acceptance Probe \(shortToken.uppercased())"
        var steps: [PMExtensionE2EAcceptanceStep] = []

        func addStep(_ title: String, _ status: PMExtensionE2EAcceptanceStep.Status, _ detail: String) {
            let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
            let normalizedDetail = detail.trimmingCharacters(in: .whitespacesAndNewlines)
            steps.append(
                PMExtensionE2EAcceptanceStep(
                    id: normalizedTitle.isEmpty ? UUID().uuidString : normalizedTitle,
                    title: normalizedTitle.isEmpty ? "Step \(steps.count + 1)" : normalizedTitle,
                    status: status,
                    detail: normalizedDetail.isEmpty ? "-" : normalizedDetail
                )
            )
        }

        let fileManager = FileManager.default
        let tempRootURL = fileManager.temporaryDirectory
            .appendingPathComponent("openmac-extension-e2e-\(UUID().uuidString)", isDirectory: true)
        let pluginRootURL = tempRootURL.appendingPathComponent("probe", isDirectory: true)
        defer { try? fileManager.removeItem(at: tempRootURL) }

        do {
            guard let manifestData = Self.pmExtensionE2EProbeManifest(pluginID: pluginID, pluginName: pluginName).data(using: .utf8),
                  let scriptData = Self.pmExtensionE2EProbeScript.data(using: .utf8) else {
                throw NSError(
                    domain: "OpenMac.PMExtensionE2EAcceptance",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "Failed to encode probe plugin files"]
                )
            }
            try fileManager.createDirectory(at: pluginRootURL, withIntermediateDirectories: true)
            try manifestData.write(to: pluginRootURL.appendingPathComponent("plugin.json"))
            try scriptData.write(to: pluginRootURL.appendingPathComponent("run.sh"))
            try fileManager.setAttributes(
                [.posixPermissions: 0o755],
                ofItemAtPath: pluginRootURL.appendingPathComponent("run.sh").path
            )
            addStep("Create Probe Plugin", .passed, pluginRootURL.path)
        } catch {
            addStep("Create Probe Plugin", .failed, error.localizedDescription)
            let report = PMExtensionE2EAcceptanceReport(
                generatedAt: Date(),
                pluginID: pluginID,
                pluginName: pluginName,
                succeeded: false,
                steps: steps
            )
            pmExtensionLastAcceptanceReport = report
            lastBoardMessage = message("Extension E2E acceptance failed: %@", error.localizedDescription)
            lastBoardMessageSeverity = .warning
            return report
        }

        let installed = installPMExtensionFromDirectory(pluginRootURL.path)
        addStep(
            "Install Extension",
            installed ? .passed : .failed,
            installed ? "Installed \(pluginID)" : (lastBoardMessage ?? "Install failed")
        )

        if installed {
            let disableApplied = setPMExtensionEnabled(pluginID: pluginID, enabled: false)
            let hiddenWhileDisabled = !pmExtensionCommands().contains(where: { $0.pluginID == pluginID })
            let enableApplied = setPMExtensionEnabled(pluginID: pluginID, enabled: true)
            let visibleWhenEnabled = pmExtensionCommands().contains(where: { $0.pluginID == pluginID })
            let enablePassed = disableApplied && hiddenWhileDisabled && enableApplied && visibleWhenEnabled
            addStep(
                "Enable Toggle",
                enablePassed ? .passed : .failed,
                enablePassed
                    ? "Disable/enable flow validated"
                    : "disableApplied=\(disableApplied) hidden=\(hiddenWhileDisabled) enableApplied=\(enableApplied) visible=\(visibleWhenEnabled)"
            )
        } else {
            addStep("Enable Toggle", .skipped, "Skipped because install failed")
        }

        let slotChecks: [(String, String, Bool)] = [
            ("app.toolbar", Self.extensionE2EToolbarCommandID, pmToolbarExtensionCommands().contains(where: { $0.pluginID == pluginID && $0.commandID == Self.extensionE2EToolbarCommandID })),
            ("kanban.toolbar", Self.extensionE2EKanbanToolbarCommandID, pmKanbanToolbarExtensionCommands().contains(where: { $0.pluginID == pluginID && $0.commandID == Self.extensionE2EKanbanToolbarCommandID })),
            ("kanban.sidebar", Self.extensionE2EKanbanSidebarCommandID, pmKanbanSidebarExtensionCommands().contains(where: { $0.pluginID == pluginID && $0.commandID == Self.extensionE2EKanbanSidebarCommandID })),
            ("marketplace.panel", Self.extensionE2EMarketplacePanelCommandID, pmMarketplacePanelExtensionCommands().contains(where: { $0.pluginID == pluginID && $0.commandID == Self.extensionE2EMarketplacePanelCommandID })),
            ("task.card", Self.extensionE2EHookCommandID, pmTaskCardExtensionCommands().contains(where: { $0.pluginID == pluginID && $0.commandID == Self.extensionE2EHookCommandID }))
        ]
        let missingSlots = slotChecks
            .filter { !$0.2 }
            .map { "\($0.0)=\($0.1)" }
        addStep(
            "Slot Contributions",
            missingSlots.isEmpty ? .passed : .failed,
            missingSlots.isEmpty ? "All expected slots are discoverable" : "Missing: \(missingSlots.joined(separator: ", "))"
        )

        var toolbarMessage = ""
        if let toolbarCommand = pmToolbarExtensionCommands().first(where: {
            $0.pluginID == pluginID && $0.commandID == Self.extensionE2EToolbarCommandID
        }) {
            let commandSucceeded = runPMExtensionCommand(
                toolbarCommand,
                extensionInputs: ["e2e": "acceptance", "source": "marketplace"]
            )
            toolbarMessage = lastBoardMessage ?? ""
            addStep(
                "Run Command",
                commandSucceeded ? .passed : .failed,
                commandSucceeded ? "\(Self.extensionE2EToolbarCommandID) executed" : (lastBoardMessage ?? "Run command failed")
            )
        } else {
            addStep("Run Command", .failed, "\(Self.extensionE2EToolbarCommandID) command not found")
        }

        let hookProbeTask = WorkTask(
            title: "E2E Hook Probe",
            details: "Generated by extension acceptance harness",
            requiredSkills: [],
            storyPoints: 1,
            status: .todo,
            assignedAgentID: nil
        )
        triggerPMExtensionHooks(
            event: .ticketCreated,
            task: hookProbeTask,
            additionalInputs: ["e2e": "hook"]
        )
        let hookSucceeded = Self.waitForPMExtensionCondition(timeoutSeconds: 6) { [weak self] in
            guard let self else { return false }
            return self.pmExtensionActivityLog.contains(where: {
                $0.pluginID == pluginID &&
                    $0.commandID == Self.extensionE2EHookCommandID &&
                    $0.outcome == .succeeded
            })
        }
        addStep(
            "Hook Execution",
            hookSucceeded ? .passed : .failed,
            hookSucceeded
                ? "ticket.created hook triggered \(Self.extensionE2EHookCommandID)"
                : "No succeeded \(Self.extensionE2EHookCommandID) entry within timeout"
        )

        let expectedWritebackMessage = "e2e-ok:\(Self.extensionE2EToolbarCommandID)"
        let writebackFromMessage = toolbarMessage.contains(expectedWritebackMessage)
        let writebackFromActivity = pmExtensionActivityLog.contains(where: {
            $0.pluginID == pluginID &&
                $0.commandID == Self.extensionE2EToolbarCommandID &&
                $0.outcome == .succeeded &&
                $0.detail.contains(expectedWritebackMessage)
        })
        let writebackFromObservability = pmExtensionObservability.contains(where: {
            $0.pluginID == pluginID &&
                $0.lastInputSummary.contains("e2e=acceptance") &&
                $0.lastOutputSummary.contains("e2e-ok")
        })
        let writebackPassed = writebackFromMessage || writebackFromActivity || writebackFromObservability
        addStep(
            "Output Writeback",
            writebackPassed ? .passed : .failed,
            writebackPassed
                ? "Response message propagated to OpenMac state"
                : "No writeback signal found in board message/activity/observability"
        )

        if installed {
            let removed = uninstallPMExtension(pluginID: pluginID)
            addStep(
                "Cleanup",
                removed ? .passed : .failed,
                removed ? "Removed probe extension" : (lastBoardMessage ?? "Cleanup failed")
            )
        } else {
            addStep("Cleanup", .skipped, "Skipped because install failed")
        }

        let failedCount = steps.filter { $0.status == .failed }.count
        let succeeded = failedCount == 0
        let report = PMExtensionE2EAcceptanceReport(
            generatedAt: Date(),
            pluginID: pluginID,
            pluginName: pluginName,
            succeeded: succeeded,
            steps: steps
        )
        pmExtensionLastAcceptanceReport = report
        if succeeded {
            lastBoardMessage = message("Extension E2E acceptance passed (%d steps)", steps.count)
            lastBoardMessageSeverity = .info
        } else {
            lastBoardMessage = message("Extension E2E acceptance failed (%d steps failed)", failedCount)
            lastBoardMessageSeverity = .warning
        }
        return report
    }

    func pmExtensionAcceptanceReportText() -> String {
        guard let report = pmExtensionLastAcceptanceReport else {
            return "No extension E2E acceptance report yet."
        }
        var lines: [String] = []
        lines.append("# Extension E2E Acceptance Report")
        lines.append("Generated at: \(Self.iso8601Formatter.string(from: report.generatedAt))")
        lines.append("Plugin: \(report.pluginName) (\(report.pluginID))")
        lines.append("Result: \(report.succeeded ? "PASS" : "FAIL")")
        lines.append("")
        lines.append("## Steps")
        for step in report.steps {
            let status = step.status.rawValue.uppercased()
            lines.append("- [\(status)] \(step.title): \(step.detail)")
        }
        return lines.joined(separator: "\n")
    }

    func pmPlannerExtensions(slot: String = KanbanBoardViewModel.pmPlannerExtensionSlot) -> [PMPlannerUIExtensionDescriptor] {
        let localExtensions = pmPlanningPluginPolicy.autoDiscoverLocalPlugins
            ? detectedLocalPMPlannerExtensions(
                in: pmPlanningPluginPolicy.pluginsDirectoryPath,
                slot: slot
            )
            : []

        let hasBrainstormComponent = localExtensions.contains {
            Self.normalizedPMPlannerComponentType($0.componentType) == Self.pmPlannerBrainstormComponent
        }
        let hasStitchComponent = localExtensions.contains {
            Self.normalizedPMPlannerComponentType($0.componentType) == Self.pmPlannerStitchComponent
        }

        var combined = localExtensions
        if !hasBrainstormComponent {
            combined.append(Self.builtInBrainstormPMPlannerExtension(slot: slot))
        }
        if !hasStitchComponent {
            combined.append(Self.builtInGoogleStitchPMPlannerExtension(slot: slot))
        }

        return combined.sorted {
            if $0.priority == $1.priority {
                return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
            }
            return $0.priority > $1.priority
        }
    }

    func refreshPMPlanningPluginDiagnostics(announce: Bool = true) {
        let names = pmPlanningLocalPluginNames()
        objectWillChange.send()
        guard announce else { return }
        if names.isEmpty {
            lastBoardMessage = message("Rescanned PM plugins: none detected")
            lastBoardMessageSeverity = .warning
            return
        }
        lastBoardMessage = message(
            "Rescanned PM plugins: %d detected (%@)",
            names.count,
            Self.pmPluginNamesPreview(names)
        )
        lastBoardMessageSeverity = .info
    }

    func updateMCPServerPolicy(
        autoFetchEnabled: Bool,
        registryURL: String
    ) {
        mcpServerPolicy = MCPServerPolicy(
            autoFetchEnabled: autoFetchEnabled,
            registryURL: registryURL,
            autoFetchedServers: mcpServerPolicy.autoFetchedServers,
            manualServers: mcpServerPolicy.manualServers,
            lastSyncedAt: mcpServerPolicy.lastSyncedAt,
            lastSyncError: mcpServerPolicy.lastSyncError
        )
        mcpReadinessCacheByServerName = [:]
        persistBoardState()
        lastBoardMessage = message("Updated MCP server settings")
        lastBoardMessageSeverity = .info
    }

    @discardableResult
    func addManualMCPServer(
        name: String,
        bootstrapCommand: String,
        keywordHintsText: String
    ) -> Bool {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            lastBoardMessage = message("MCP server name is required")
            lastBoardMessageSeverity = .warning
            return false
        }

        let trimmedBootstrapCommand = bootstrapCommand.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedBootstrapCommand.isEmpty else {
            lastBoardMessage = message("MCP bootstrap command is required")
            lastBoardMessageSeverity = .warning
            return false
        }

        let keywordHints = keywordHintsText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let descriptor = MCPServerDescriptor(
            name: trimmedName,
            remoteURL: nil,
            bootstrapCommand: trimmedBootstrapCommand,
            verificationCommand: "codex mcp get \(Self.shellQuoted(MCPServerDescriptor.cliSafeServerName(trimmedName))) --json",
            keywordHints: keywordHints,
            isEnabled: true,
            source: .manual,
            notes: nil
        )

        let existingIndex = mcpServerPolicy.manualServers.firstIndex(where: {
            $0.normalizedName == descriptor.normalizedName
        })
        if let existingIndex {
            mcpServerPolicy.manualServers[existingIndex] = descriptor
        } else {
            mcpServerPolicy.manualServers.append(descriptor)
        }

        mcpReadinessCacheByServerName[descriptor.normalizedName] = nil
        persistBoardState()
        lastBoardMessage = message("Saved MCP server: %@", descriptor.name)
        lastBoardMessageSeverity = .info
        return true
    }

    @discardableResult
    func removeManualMCPServer(named name: String) -> Bool {
        let normalizedName = MCPServerDescriptor.normalizedServerName(name)
        let beforeCount = mcpServerPolicy.manualServers.count
        mcpServerPolicy.manualServers.removeAll { descriptor in
            descriptor.normalizedName == normalizedName
        }

        guard mcpServerPolicy.manualServers.count != beforeCount else {
            return false
        }
        mcpReadinessCacheByServerName[normalizedName] = nil
        persistBoardState()
        lastBoardMessage = message("Removed MCP server: %@", name)
        lastBoardMessageSeverity = .info
        return true
    }

    func setManualMCPServerEnabled(name: String, isEnabled: Bool) {
        let normalizedName = MCPServerDescriptor.normalizedServerName(name)
        guard let index = mcpServerPolicy.manualServers.firstIndex(where: {
            $0.normalizedName == normalizedName
        }) else { return }

        mcpServerPolicy.manualServers[index].isEnabled = isEnabled
        mcpReadinessCacheByServerName[normalizedName] = nil
        persistBoardState()
    }

    func syncMCPServerRegistryInBackgroundIfNeeded() {
        guard mcpServerPolicy.autoFetchEnabled else { return }
        guard shouldSyncMCPRegistry(lastSyncedAt: mcpServerPolicy.lastSyncedAt) else { return }
        syncMCPServerRegistryInBackground(force: false, announceResult: false)
    }

    func syncMCPServerRegistryInBackground(
        force: Bool,
        announceResult: Bool,
        completion: (() -> Void)? = nil
    ) {
        guard mcpServerPolicy.autoFetchEnabled else {
            completion?()
            return
        }
        if !force,
           !shouldSyncMCPRegistry(lastSyncedAt: mcpServerPolicy.lastSyncedAt) {
            completion?()
            return
        }

        let registryURL = mcpServerPolicy.registryURL
        runOnBackground {
            let fetchResult = Self.fetchMCPServersFromRegistry(registryURL: registryURL)
            self.runOnMain {
                if let servers = fetchResult.servers {
                    self.mcpServerPolicy.autoFetchedServers = servers
                    self.mcpServerPolicy.lastSyncedAt = Date()
                    self.mcpServerPolicy.lastSyncError = nil
                    self.persistBoardState()
                    if announceResult {
                        self.lastBoardMessage = self.message("MCP registry synced: %d server(s)", servers.count)
                        self.lastBoardMessageSeverity = .info
                    }
                    completion?()
                } else {
                    let errorMessage = fetchResult.error ?? "unknown error"
                    self.mcpServerPolicy.lastSyncedAt = Date()
                    self.mcpServerPolicy.lastSyncError = errorMessage
                    self.persistBoardState()
                    if announceResult {
                        self.lastBoardMessage = self.message("MCP registry sync failed: %@", errorMessage)
                        self.lastBoardMessageSeverity = .warning
                    }
                    completion?()
                }
            }
        }
    }

    func mcpServerStatusSummaryText() -> String {
        let effectiveCount = mcpServerPolicy.effectiveServers.filter(\.isEnabled).count
        let manualCount = mcpServerPolicy.manualServers.count
        if let error = mcpServerPolicy.lastSyncError, !error.isEmpty {
            return message("MCP: %d active · %d manual · last sync error", effectiveCount, manualCount)
        }
        return message("MCP: %d active · %d manual", effectiveCount, manualCount)
    }

    func resetExecutionQuotaUsage() {
        executionQuotaUsage = ExecutionQuotaUsage()
        persistBoardState()
        lastBoardMessage = message("Reset execution quota usage")
        lastBoardMessageSeverity = .info
    }

    func executionQuotaUsageSummaryText() -> String {
        message(
            "Quota Usage: %d runs · %d tokens · $%.2f",
            executionQuotaUsage.consumedRuns,
            executionQuotaUsage.estimatedTokensUsed,
            executionQuotaUsage.estimatedCostUSD
        )
    }

    private func qualitySafetyGateBlockReason(for task: WorkTask) -> String? {
        let policy = executionQualitySafetyGatePolicy
        guard policy.isEnabled else { return nil }

        let details = task.details.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedContext = "\(task.title)\n\(details)".lowercased()

        if policy.requireAcceptanceCriteria,
           Self.acceptanceCriteriaLines(from: details).isEmpty {
            return message("Missing acceptance criteria required by quality/safety gate")
        }

        if policy.requireTestCoverageIntent {
            let qualityTokens = ["test", "tests", "testing", "qa", "coverage", "e2e", "tdd", "驗證", "測試"]
            let hasQualityIntent = qualityTokens.contains { normalizedContext.contains($0) }
            if !hasQualityIntent {
                return message("Missing test or coverage intent required by quality/safety gate")
            }
        }

        if policy.requireSecurityPrivacyForSensitiveTasks {
            let isSensitive = policy.sensitiveKeywords.contains { normalizedContext.contains($0) }
            if isSensitive {
                let hasSecurityNotes = normalizedContext.contains("security")
                    || normalizedContext.contains("privacy")
                    || normalizedContext.contains("安全")
                    || normalizedContext.contains("隱私")
                if !hasSecurityNotes {
                    return message("Sensitive task requires security/privacy notes by quality/safety gate")
                }
            }
        }

        return nil
    }

    private func estimatedTokenUsage(for task: WorkTask) -> Int {
        let detailLength = task.details.count
        let skillsWeight = task.requiredSkills.count * 30
        return max(120, task.storyPoints * 260 + detailLength / 2 + skillsWeight)
    }

    private func estimatedCostUSD(for tokens: Int) -> Double {
        (Double(tokens) / 1000.0) * executionQuotaPolicy.costPer1KTokensUSD
    }

    private func quotaCheckMessage(for task: WorkTask) -> String? {
        guard executionQuotaPolicy.isEnabled else { return nil }

        let estimatedTokens = estimatedTokenUsage(for: task)
        let projectedTokens = executionQuotaUsage.estimatedTokensUsed + estimatedTokens
        let projectedCost = executionQuotaUsage.estimatedCostUSD + estimatedCostUSD(for: estimatedTokens)

        if projectedTokens > executionQuotaPolicy.maxEstimatedTokens ||
            projectedCost > executionQuotaPolicy.maxEstimatedCostUSD {
            let details = message(
                "Estimated quota after run: %d tokens / $%.2f",
                projectedTokens,
                projectedCost
            )
            return message("Execution blocked by quota limit. %@", details)
        }

        return nil
    }

    private func consumeExecutionQuota(for task: WorkTask) {
        guard executionQuotaPolicy.isEnabled else { return }
        let estimatedTokens = estimatedTokenUsage(for: task)
        executionQuotaUsage.consumedRuns += 1
        executionQuotaUsage.estimatedTokensUsed += estimatedTokens
        executionQuotaUsage.estimatedCostUSD += estimatedCostUSD(for: estimatedTokens)
        executionQuotaUsage.lastUpdatedAt = Date()
    }

    private func retryableErrorType(for message: String) -> RetryableExecutionErrorType? {
        let normalized = message.lowercased()

        let networkSignals = [
            "network", "dns", "connection timed out", "network timeout",
            "failed to connect", "connection reset",
            "connection refused", "websocket", "lookup address information"
        ]
        if networkSignals.contains(where: { normalized.contains($0) }) {
            return .network
        }

        let rateLimitSignals = [
            "rate limit", "too many requests", "quota",
            "insufficient_quota", "usage limit"
        ]
        if rateLimitSignals.contains(where: { normalized.contains($0) }) {
            return .rateLimit
        }

        let serverSignals = [
            "500", "502", "503", "504",
            "internal server error", "service unavailable", "bad gateway"
        ]
        if serverSignals.contains(where: { normalized.contains($0) }) {
            return .server
        }

        return nil
    }

    private func ensureMCPServersReadyForExecution(
        task: WorkTask,
        agent: AgentProfile,
        onProgress: @escaping (_ update: String) -> Void
    ) -> String? {
        let runtimeProfile = agent.runtimeProfile ?? .defaultCodexBridge
        guard runtimeProfile.provider == .openAICompatible,
              runtimeProfile.openAIAuthMode == .codexBridge else {
            return nil
        }

        let requiredServers = requiredMCPServers(for: task, agent: agent)
        guard !requiredServers.isEmpty else { return nil }

        onProgress(message("MCP preflight: checking %d server(s)", requiredServers.count))
        for server in requiredServers {
            if let provisioningError = ensureMCPServerReady(server, onProgress: onProgress) {
                return provisioningError
            }
        }
        return nil
    }

    private func requiredMCPServers(for task: WorkTask, agent: AgentProfile) -> [MCPServerDescriptor] {
        let normalizedContext = (
            [task.title, task.details]
                + Array(task.requiredSkills)
                + Array(agent.skills)
        )
        .joined(separator: " ")
        .lowercased()

        return mcpServerPolicy.effectiveServers.filter { descriptor in
            guard descriptor.isEnabled else { return false }
            if descriptor.keywordHints.isEmpty { return true }
            return descriptor.keywordHints.contains { normalizedContext.contains($0) }
        }
    }

    private func ensureMCPServerReady(
        _ server: MCPServerDescriptor,
        onProgress: @escaping (_ update: String) -> Void
    ) -> String? {
        let cacheKey = server.normalizedName
        if mcpReadinessCacheByServerName[cacheKey] == true {
            onProgress(message("MCP ready: %@", server.name))
            return nil
        }

        if isMCPServerRegisteredAndEnabled(server) {
            mcpReadinessCacheByServerName[cacheKey] = true
            onProgress(message("MCP ready: %@", server.name))
            return nil
        }

        onProgress(message("MCP missing: %@. Provisioning...", server.name))
        let provisionResult = provisionMCPServer(server, onProgress: onProgress)
        if !provisionResult.success {
            mcpReadinessCacheByServerName[cacheKey] = false
            return provisionResult.details
        }
        if !provisionResult.details.isEmpty {
            onProgress(provisionResult.details)
        }

        guard isMCPServerRegisteredAndEnabled(server) else {
            mcpReadinessCacheByServerName[cacheKey] = false
            return message(
                "MCP server \"%@\" is still unavailable after auto-provisioning. Add it manually in Developer > MCP Servers.",
                server.name
            )
        }

        mcpReadinessCacheByServerName[cacheKey] = true
        onProgress(message("MCP provisioned: %@", server.name))
        return nil
    }

    private func isMCPServerRegisteredAndEnabled(_ server: MCPServerDescriptor) -> Bool {
        let computedCommand = "codex mcp get \(Self.shellQuoted(server.cliServerName)) --json"
        let fallbackCommand = server.verificationCommand?.trimmingCharacters(in: .whitespacesAndNewlines)
        let commands = [computedCommand, fallbackCommand]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .reduce(into: [String]()) { partialResult, command in
                if !partialResult.contains(command) {
                    partialResult.append(command)
                }
            }

        for verificationCommand in commands {
            guard let result = try? Self.runShellCommand(verificationCommand),
                  result.code == 0 else {
                continue
            }

            guard let outputData = result.output.data(using: .utf8),
                  let jsonObject = try? JSONSerialization.jsonObject(with: outputData) as? [String: Any] else {
                return true
            }

            if let enabled = jsonObject["enabled"] as? Bool {
                return enabled
            }
            return true
        }

        return false
    }

    private func provisionMCPServer(
        _ server: MCPServerDescriptor,
        onProgress: @escaping (_ update: String) -> Void
    ) -> (success: Bool, details: String) {
        if server.normalizedName == "xcode" {
            return provisionBuiltinXcodeMCPServer()
        }

        guard let bootstrapCommand = server.bootstrapCommand,
              !bootstrapCommand.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return (
                false,
                message(
                    "MCP server \"%@\" has no bootstrap command. Add one in Developer > MCP Servers.",
                    server.name
                )
            )
        }

        let resolvedBootstrapCommand = repairedMCPBootstrapCommandIfNeeded(
            rawCommand: bootstrapCommand,
            preferredServerName: server.cliServerName
        )

        guard let result = try? Self.runShellCommand(resolvedBootstrapCommand) else {
            return (false, message("MCP bootstrap command failed to launch for %@", server.name))
        }
        guard result.code == 0 else {
            let reason = result.output.isEmpty ? "exit \(result.code)" : result.output
            return (false, message("MCP bootstrap failed for %@: %@", server.name, reason))
        }
        onProgress(message("MCP bootstrap completed: %@", server.name))
        return (true, result.output)
    }

    private func repairedMCPBootstrapCommandIfNeeded(
        rawCommand: String,
        preferredServerName: String
    ) -> String {
        let trimmed = rawCommand.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return rawCommand }

        let lowercased = trimmed.lowercased()
        guard lowercased.hasPrefix("codex mcp add ") else { return rawCommand }

        guard let urlRange = trimmed.range(of: " --url ") else {
            return rawCommand
        }
        let urlArgument = trimmed[urlRange.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !urlArgument.isEmpty else { return rawCommand }

        return "codex mcp add \(Self.shellQuoted(preferredServerName)) --url \(urlArgument)"
    }

    private func provisionBuiltinXcodeMCPServer() -> (success: Bool, details: String) {
        let environment = ProcessInfo.processInfo.environment
        let homePath = environment["HOME"] ?? NSHomeDirectory()
        let fileManager = FileManager.default
        let explicitCandidate = environment["OPENMAC_XCODE_MCP_COMMAND"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let candidates = [
            explicitCandidate,
            "\(homePath)/.codex/bin/xcode-mcpbridge.sh",
            "/opt/homebrew/bin/xcode-mcpbridge.sh",
            "/usr/local/bin/xcode-mcpbridge.sh",
            "/opt/homebrew/bin/xcode-mcpbridge",
            "/usr/local/bin/xcode-mcpbridge"
        ]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        var lastFailureDetails = ""

        for candidate in candidates {
            guard fileManager.isExecutableFile(atPath: candidate) else {
                continue
            }
            let addCommand = "codex mcp add xcode -- \(Self.shellQuoted(candidate))"
            guard let result = try? Self.runShellCommand(addCommand, environment: environment) else {
                lastFailureDetails = "failed to run: \(addCommand)"
                continue
            }
            if result.code == 0 {
                return (true, result.output)
            }

            let normalizedOutput = result.output.lowercased()
            if normalizedOutput.contains("already exists") {
                let verifyCommand = "codex mcp get xcode --json"
                if let verify = try? Self.runShellCommand(verifyCommand, environment: environment),
                   verify.code == 0 {
                    return (true, verify.output)
                }
            }
            lastFailureDetails = result.output.isEmpty ? "exit \(result.code)" : result.output
        }

        let resolvedHint = candidates.first(where: { fileManager.isExecutableFile(atPath: $0) }) ?? "<none>"
        return (
            false,
            message(
                "Unable to auto-add xcode MCP server. Resolved bridge path: %@. %@",
                resolvedHint,
                lastFailureDetails.isEmpty
                    ? message("Ensure xcode-mcpbridge is installed, then add command in Developer > MCP Servers.")
                    : lastFailureDetails
            )
        )
    }

    private func detectedLocalPMPlanningPlugins(in directoryPath: String) -> [String] {
        detectedLocalPMPlannerPluginRecords(in: directoryPath)
            .filter { record in
                let capabilities = Set(record.manifest.capabilities ?? [])
                return capabilities.contains(Self.pmPlanningPluginCapability)
            }
            .map { record in
                let resolvedName = (record.manifest.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                return resolvedName.isEmpty ? record.directoryURL.lastPathComponent : resolvedName
            }
            .sorted { lhs, rhs in
                lhs.localizedCaseInsensitiveCompare(rhs) == .orderedAscending
            }
    }

    private func detectedLocalPMPlannerExtensions(
        in directoryPath: String,
        slot: String
    ) -> [PMPlannerUIExtensionDescriptor] {
        let normalizedSlot = slot.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedSlot.isEmpty else { return [] }

        let extensions = detectedLocalPMPlannerPluginRecords(in: directoryPath).flatMap { record -> [PMPlannerUIExtensionDescriptor] in
            let pluginID = (record.manifest.id ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !pluginID.isEmpty else { return [] }
            guard !pmPlanningPluginPolicy.disabledPluginIDs.contains(pluginID.lowercased()) else { return [] }
            let pluginName = {
                let trimmed = (record.manifest.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? record.directoryURL.lastPathComponent : trimmed
            }()

            return (record.manifest.uiExtensions ?? []).compactMap { extensionManifest in
                guard extensionManifest.enabled ?? true else { return nil }
                let extensionSlot = (extensionManifest.slot ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                guard extensionSlot == normalizedSlot else { return nil }

                let extensionID = (extensionManifest.id ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                let component = Self.normalizedPMPlannerComponentType(extensionManifest.component ?? "")
                guard !extensionID.isEmpty, !component.isEmpty else { return nil }

                let title = {
                    let trimmed = (extensionManifest.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    return trimmed.isEmpty ? pluginName : trimmed
                }()
                let subtitle = (extensionManifest.subtitle ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                let parsedSchema = Self.pmPlannerUISchema(from: extensionManifest.ui)
                let schema = parsedSchema ?? (
                    component == Self.pmPlannerBrainstormComponent
                        ? Self.defaultBrainstormPMPlannerUISchema()
                        : nil
                )

                return PMPlannerUIExtensionDescriptor(
                    id: "\(pluginID).\(extensionID)",
                    pluginID: pluginID,
                    pluginName: pluginName,
                    slot: extensionSlot,
                    title: title,
                    subtitle: subtitle,
                    componentType: component,
                    priority: extensionManifest.priority ?? 0,
                    source: .localPlugin,
                    uiSchema: schema
                )
            }
        }

        return extensions.sorted { lhs, rhs in
            if lhs.priority == rhs.priority {
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
            return lhs.priority > rhs.priority
        }
    }

    private func detectedLocalPMPlannerPluginRecords(in directoryPath: String) -> [LocalPMPlanningPluginRecord] {
        let trimmedPath = directoryPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPath.isEmpty else { return [] }

        let expandedPath = (trimmedPath as NSString).expandingTildeInPath
        let directoryURL = URL(fileURLWithPath: expandedPath, isDirectory: true)
        guard FileManager.default.fileExists(atPath: directoryURL.path) else { return [] }

        guard let childEntries = try? FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        let candidateDirectories = [directoryURL] + childEntries
        return candidateDirectories.compactMap { entryURL in
            localPMPlanningPluginRecord(at: entryURL)
        }
    }

    private func localPMPlanningPluginRecord(at entryURL: URL) -> LocalPMPlanningPluginRecord? {
        guard let values = try? entryURL.resourceValues(forKeys: [.isDirectoryKey]),
              values.isDirectory == true else {
            return nil
        }

        let pluginManifestCandidates = [
            entryURL.appendingPathComponent("plugin.json"),
            entryURL.appendingPathComponent("manifest.json")
        ]

        guard let manifestURL = pluginManifestCandidates.first(where: { FileManager.default.fileExists(atPath: $0.path) }),
              let data = try? Data(contentsOf: manifestURL),
              let manifest = try? JSONDecoder().decode(LocalPMPlanningPluginManifestSummary.self, from: data) else {
            return nil
        }

        guard manifest.enabled ?? true else { return nil }
        return LocalPMPlanningPluginRecord(manifest: manifest, directoryURL: entryURL)
    }

    private static func builtInBrainstormPMPlannerExtension(slot: String) -> PMPlannerUIExtensionDescriptor {
        PMPlannerUIExtensionDescriptor(
            id: "openmac.builtin.brainstorm",
            pluginID: "openmac.builtin.brainstorm",
            pluginName: "OpenMac",
            slot: slot,
            title: L10n.string("Brainstorm Extension"),
            subtitle: L10n.string("Use OpenMac runtime to brainstorm ideas and fold them back into your project brief."),
            componentType: pmPlannerBrainstormComponent,
            priority: -100,
            source: .builtIn,
            uiSchema: defaultBrainstormPMPlannerUISchema()
        )
    }

    private static func builtInGoogleStitchPMPlannerExtension(slot: String) -> PMPlannerUIExtensionDescriptor {
        PMPlannerUIExtensionDescriptor(
            id: "openmac.system.google-stitch",
            pluginID: systemExtensionPluginID,
            pluginName: systemExtensionPluginName,
            slot: slot,
            title: L10n.string("Google Stitch UI Generator"),
            subtitle: L10n.string("Generate a polished UI direction and ready-to-use Stitch prompt from your project brief."),
            componentType: pmPlannerStitchComponent,
            priority: -95,
            source: .builtIn,
            uiSchema: defaultGoogleStitchPMPlannerUISchema()
        )
    }

    private static func normalizedPMPlannerComponentType(_ rawValue: String) -> String {
        let normalized = rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch normalized {
        case "brainstorm", "brainstorm.v1", "pm.brainstorm.v1":
            return pmPlannerBrainstormComponent
        case "stitch", "stitch.v1", "pm.stitch.v1", "google.stitch.v1":
            return pmPlannerStitchComponent
        case "form", "form.v1", "pm.form.v1":
            return "form.v1"
        default:
            return normalized
        }
    }

    private static let pmPlanningPluginCapability = "pm.plan.generate"
    private static let pmPlannerExtensionSlot = "pm.planner"
    private static let extensionCommandDefaultSlot = "app.toolbar"
    private static let extensionCommandTaskCardSlot = "task.card"
    private static let extensionCommandPlannerPanelSlot = "pm.planner.panel"
    private static let extensionCommandKanbanToolbarSlot = "kanban.toolbar"
    private static let extensionCommandKanbanSidebarSlot = "kanban.sidebar"
    private static let extensionCommandMarketplacePanelSlot = "marketplace.panel"
    private static let systemExtensionPluginID = "openmac.system"
    private static let systemExtensionPluginName = "OpenMac System"
    private static let systemRealArtifactVerifyCommandID = "system.real-artifact-verify"
    private static let systemGoogleStitchGenerateCommandID = "system.google-stitch.generate"
    private static let extensionE2EToolbarCommandID = "toolbar-probe"
    private static let extensionE2EHookCommandID = "hook-probe"
    private static let extensionE2EKanbanToolbarCommandID = "kanban-toolbar-probe"
    private static let extensionE2EKanbanSidebarCommandID = "kanban-sidebar-probe"
    private static let extensionE2EMarketplacePanelCommandID = "marketplace-panel-probe"
    private static let extensionCommandRequiredPermission = "command.execute"
    private static let extensionCommandDefaultTimeoutSeconds = 45
    private static let extensionCommandMaxTimeoutSeconds = 300
    private static let pmPlannerBrainstormComponent = "brainstorm.v1"
    private static let pmPlannerStitchComponent = "stitch.v1"
    private static let pmPlannerUIFieldFocusInput = "focus.input"
    private static let pmPlannerUIFieldStatusText = "status.text"
    private static let pmPlannerUIFieldTranscriptOutput = "transcript.output"
    private static let pmPlannerUIActionRun = "pm.brainstorm.run"
    private static let pmPlannerUIActionApply = "pm.brainstorm.apply"
    private static let pmPlannerUIActionApplyGenerate = "pm.brainstorm.apply.generate"
    private static let pmPlannerUIActionApplyCreate = "pm.brainstorm.apply.create"
    private static let pmPlannerUIActionClear = "pm.brainstorm.clear"
    private static let iso8601Formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static func normalizedExtensionCommandSlot(_ rawValue: String) -> String {
        let normalized = rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch normalized {
        case "", "default", "toolbar", "toolbar.menu", "app.toolbar", "extensions.menu":
            return extensionCommandDefaultSlot
        case "task", "task.card", "task.card.menu", "kanban.task.card":
            return extensionCommandTaskCardSlot
        case "planner", "pm.planner.panel", "pm.panel", "planner.panel":
            return extensionCommandPlannerPanelSlot
        case "kanban.toolbar", "board.toolbar", "kanban.topbar":
            return extensionCommandKanbanToolbarSlot
        case "kanban.sidebar", "board.sidebar":
            return extensionCommandKanbanSidebarSlot
        case "marketplace.panel", "extensions.marketplace.panel":
            return extensionCommandMarketplacePanelSlot
        default:
            return normalized
        }
    }

    private static func normalizedExtensionCommandSlots(_ slots: [String]?, singleSlot: String?) -> [String] {
        var collected: [String] = []
        if let slots {
            collected.append(contentsOf: slots)
        }
        if let singleSlot, !singleSlot.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            collected.append(singleSlot)
        }
        if collected.isEmpty {
            return [extensionCommandDefaultSlot]
        }

        var resolved: [String] = []
        var seen = Set<String>()
        for slot in collected {
            let normalized = normalizedExtensionCommandSlot(slot)
            guard !normalized.isEmpty else { continue }
            guard seen.insert(normalized).inserted else { continue }
            resolved.append(normalized)
        }
        return resolved.isEmpty ? [extensionCommandDefaultSlot] : resolved
    }

    private static func normalizedExtensionPermissions(_ permissions: [String]) -> [String] {
        var normalized: [String] = []
        var seen = Set<String>()
        for permission in permissions {
            let trimmed = permission.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !trimmed.isEmpty else { continue }
            guard seen.insert(trimmed).inserted else { continue }
            normalized.append(trimmed)
        }
        return normalized
    }

    nonisolated private static func normalizedProviderDescriptorID(_ rawValue: String?) -> String? {
        guard let rawValue else { return nil }
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return trimmed
    }

    private static func resolvedExtensionCommandTimeout(_ timeoutSeconds: Int?) -> Int? {
        guard let timeoutSeconds else { return nil }
        let minimum = max(1, timeoutSeconds)
        return min(extensionCommandMaxTimeoutSeconds, minimum)
    }

    private static func currentOpenMacVersionString() -> String {
        let bundleVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let trimmed = (bundleVersion ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "0.0.0" : trimmed
    }

    private static func normalizedVersionSegments(_ rawVersion: String) -> [Int] {
        rawVersion
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: ".")
            .prefix(4)
            .map { segment in
                Int(segment.filter(\.isNumber)) ?? 0
            }
    }

    private static func compareVersions(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let lhsSegments = normalizedVersionSegments(lhs)
        let rhsSegments = normalizedVersionSegments(rhs)
        let maxCount = max(lhsSegments.count, rhsSegments.count)
        for index in 0..<maxCount {
            let lhsValue = index < lhsSegments.count ? lhsSegments[index] : 0
            let rhsValue = index < rhsSegments.count ? rhsSegments[index] : 0
            if lhsValue < rhsValue { return .orderedAscending }
            if lhsValue > rhsValue { return .orderedDescending }
        }
        return .orderedSame
    }

    private static func pmExtensionCompatibilitySummary(
        minVersion: String?,
        maxVersion: String?
    ) -> String {
        let current = currentOpenMacVersionString()
        let minTrimmed = (minVersion ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let maxTrimmed = (maxVersion ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

        if !minTrimmed.isEmpty, compareVersions(current, minTrimmed) == .orderedAscending {
            return "Requires OpenMac >= \(minTrimmed) (current \(current))"
        }
        if !maxTrimmed.isEmpty, compareVersions(current, maxTrimmed) == .orderedDescending {
            return "Requires OpenMac <= \(maxTrimmed) (current \(current))"
        }
        if !minTrimmed.isEmpty, !maxTrimmed.isEmpty {
            return "Compatible with OpenMac \(minTrimmed) - \(maxTrimmed)"
        }
        if !minTrimmed.isEmpty {
            return "Compatible with OpenMac >= \(minTrimmed)"
        }
        if !maxTrimmed.isEmpty {
            return "Compatible with OpenMac <= \(maxTrimmed)"
        }
        return "Compatibility: no explicit OpenMac version constraints"
    }

    private static func pmExtensionCompatibilityViolation(
        minVersion: String?,
        maxVersion: String?
    ) -> String? {
        let current = currentOpenMacVersionString()
        let minTrimmed = (minVersion ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let maxTrimmed = (maxVersion ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !minTrimmed.isEmpty, compareVersions(current, minTrimmed) == .orderedAscending {
            return "Requires OpenMac >= \(minTrimmed) (current \(current))"
        }
        if !maxTrimmed.isEmpty, compareVersions(current, maxTrimmed) == .orderedDescending {
            return "Requires OpenMac <= \(maxTrimmed) (current \(current))"
        }
        return nil
    }

    private static func pmExtensionVersionTransitionLabel(
        previousVersion: String?,
        incomingVersion: String?
    ) -> String {
        let previous = (previousVersion ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let incoming = (incomingVersion ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !incoming.isEmpty else {
            return previous.isEmpty ? "installed" : "updated"
        }
        guard !previous.isEmpty else {
            return "installed v\(incoming)"
        }
        switch compareVersions(incoming, previous) {
        case .orderedDescending:
            return "upgraded \(previous) -> \(incoming)"
        case .orderedAscending:
            return "downgraded \(previous) -> \(incoming)"
        case .orderedSame:
            return "reinstalled v\(incoming)"
        }
    }

    private static func normalizedPMExtensionUpdateChannel(_ rawValue: String?) -> PMExtensionUpdateChannel {
        let normalized = (rawValue ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch normalized {
        case "stable", "":
            return .stable
        case "beta", "preview":
            return .beta
        case "alpha", "nightly", "dev":
            return .alpha
        default:
            return .stable
        }
    }

    private static func isAllowedPMExtensionUpdateChannel(
        _ candidate: PMExtensionUpdateChannel,
        preferred: PMExtensionUpdateChannel
    ) -> Bool {
        let rank: [PMExtensionUpdateChannel: Int] = [.stable: 0, .beta: 1, .alpha: 2]
        return (rank[candidate] ?? 0) <= (rank[preferred] ?? 0)
    }

    private func pmExtensionSourceCandidates(for normalizedPluginID: String) -> [URL] {
        guard !normalizedPluginID.isEmpty else { return [] }
        var resolved: [URL] = []
        var seen = Set<String>()
        for source in pmPlanningPluginPolicy.marketplaceSources {
            let trimmed = source.source.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let expanded = (trimmed as NSString).expandingTildeInPath
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: expanded, isDirectory: &isDirectory), isDirectory.boolValue else {
                continue
            }
            let rootURL = URL(fileURLWithPath: expanded, isDirectory: true)
            guard let match = findPMExtensionDirectory(in: rootURL, matchingPluginID: normalizedPluginID) else { continue }
            let key = match.standardizedFileURL.path
            guard seen.insert(key).inserted else { continue }
            resolved.append(match)
        }
        return resolved
    }

    private func findPMExtensionDirectory(in rootURL: URL, matchingPluginID normalizedPluginID: String) -> URL? {
        if let rootRecord = localPMPlanningPluginRecord(at: rootURL),
           (rootRecord.manifest.id ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == normalizedPluginID {
            return rootURL
        }
        let fileManager = FileManager.default
        var queue: [(url: URL, depth: Int)] = [(rootURL, 0)]
        var visited = Set<String>()
        let maxDepth = 3
        while !queue.isEmpty {
            let current = queue.removeFirst()
            guard current.depth <= maxDepth else { continue }
            let key = current.url.standardizedFileURL.path
            guard visited.insert(key).inserted else { continue }
            guard let children = try? fileManager.contentsOfDirectory(
                at: current.url,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else {
                continue
            }
            for childURL in children {
                guard let values = try? childURL.resourceValues(forKeys: [.isDirectoryKey]),
                      values.isDirectory == true else {
                    continue
                }
                if let record = localPMPlanningPluginRecord(at: childURL),
                   (record.manifest.id ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == normalizedPluginID {
                    return childURL
                }
                queue.append((childURL, current.depth + 1))
            }
        }
        return nil
    }

    private static func summarizedExtensionInputs(_ inputs: [String: String]) -> String {
        guard !inputs.isEmpty else { return "-" }
        let pairs = inputs
            .sorted { $0.key.localizedCaseInsensitiveCompare($1.key) == .orderedAscending }
            .map { key, value in
                "\(key)=\(value)"
            }
            .joined(separator: ", ")
        return summarizedExtensionOutput(pairs)
    }

    private static func summarizedExtensionOutput(_ output: String) -> String {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "-" }
        let normalized = trimmed.replacingOccurrences(of: "\n", with: " ")
        if normalized.count <= 180 { return normalized }
        return String(normalized.prefix(177)) + "..."
    }

    private static func pmExtensionE2EProbeManifest(pluginID: String, pluginName: String) -> String {
        """
        {
          "id": "\(pluginID)",
          "name": "\(pluginName)",
          "version": "0.0.1",
          "summary": "OpenMac generated extension acceptance probe",
          "entrypoint": "./run.sh",
          "permissions": ["\(extensionCommandRequiredPermission)"],
          "commands": [
            { "id": "\(extensionE2EToolbarCommandID)", "title": "Toolbar Probe", "slots": ["\(extensionCommandDefaultSlot)"], "permissions": ["\(extensionCommandRequiredPermission)"], "enabled": true },
            { "id": "\(extensionE2EKanbanToolbarCommandID)", "title": "Kanban Toolbar Probe", "slots": ["\(extensionCommandKanbanToolbarSlot)"], "permissions": ["\(extensionCommandRequiredPermission)"], "enabled": true },
            { "id": "\(extensionE2EKanbanSidebarCommandID)", "title": "Kanban Sidebar Probe", "slots": ["\(extensionCommandKanbanSidebarSlot)"], "permissions": ["\(extensionCommandRequiredPermission)"], "enabled": true },
            { "id": "\(extensionE2EMarketplacePanelCommandID)", "title": "Marketplace Panel Probe", "slots": ["\(extensionCommandMarketplacePanelSlot)"], "permissions": ["\(extensionCommandRequiredPermission)"], "enabled": true },
            { "id": "\(extensionE2EHookCommandID)", "title": "Hook Probe", "slots": ["\(extensionCommandTaskCardSlot)"], "permissions": ["\(extensionCommandRequiredPermission)"], "enabled": true }
          ],
          "eventHooks": [
            { "id": "ticket-created-hook", "event": "\(PMExtensionHookEvent.ticketCreated.rawValue)", "commandID": "\(extensionE2EHookCommandID)", "enabled": true }
          ],
          "enabled": true
        }
        """
    }

    private static let pmExtensionE2EProbeScript = """
    #!/bin/zsh
    set -euo pipefail

    payload="$(cat)"
    command_id="unknown"
    for candidate in "\(extensionE2EToolbarCommandID)" "\(extensionE2EHookCommandID)" "\(extensionE2EKanbanToolbarCommandID)" "\(extensionE2EKanbanSidebarCommandID)" "\(extensionE2EMarketplacePanelCommandID)"; do
      if [[ "$payload" == *"\\"commandID\\":\\"${candidate}\\""* ]]; then
        command_id="$candidate"
        break
      fi
    done

    echo "{\\"message\\":\\"e2e-ok:${command_id}\\"}"
    """

    private func readOnMain<T>(_ block: @escaping () -> T) -> T {
        if Thread.isMainThread {
            return block()
        }
        return DispatchQueue.main.sync(execute: block)
    }

    private static func waitForPMExtensionCondition(
        timeoutSeconds: TimeInterval,
        pollIntervalSeconds: TimeInterval = 0.05,
        condition: @escaping () -> Bool
    ) -> Bool {
        let deadline = Date().addingTimeInterval(max(0.1, timeoutSeconds))
        while Date() < deadline {
            if condition() {
                return true
            }
            let spinUntil = Date().addingTimeInterval(max(0.01, pollIntervalSeconds))
            if Thread.isMainThread {
                _ = RunLoop.main.run(mode: .default, before: spinUntil)
                _ = RunLoop.main.run(mode: .common, before: spinUntil)
            } else {
                Thread.sleep(forTimeInterval: max(0.01, pollIntervalSeconds))
            }
        }
        return condition()
    }

    private static func isLikelyHTTPRemoteSource(_ source: String) -> Bool {
        let lowercased = source.lowercased()
        return lowercased.hasPrefix("https://") || lowercased.hasPrefix("http://")
    }

    private static func isLikelyGitRemoteSource(_ source: String) -> Bool {
        let lowercased = source.lowercased()
        if lowercased.hasSuffix(".git") || lowercased.hasPrefix("git@") {
            return true
        }
        return lowercased.hasPrefix("https://github.com/") || lowercased.hasPrefix("http://github.com/")
    }

    private static func isLikelyZipSource(_ source: String) -> Bool {
        source.lowercased().hasSuffix(".zip")
    }

    private func firstPMExtensionDirectoryCandidate(in rootURL: URL) -> URL? {
        if localPMPlanningPluginRecord(at: rootURL) != nil {
            return rootURL
        }

        let fileManager = FileManager.default
        var queue: [(url: URL, depth: Int)] = [(rootURL, 0)]
        let maxDepth = 3
        var visited = Set<String>()

        while !queue.isEmpty {
            let current = queue.removeFirst()
            guard current.depth <= maxDepth else { continue }
            let key = current.url.standardizedFileURL.path
            guard visited.insert(key).inserted else { continue }

            guard let children = try? fileManager.contentsOfDirectory(
                at: current.url,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else {
                continue
            }

            for childURL in children {
                guard let values = try? childURL.resourceValues(forKeys: [.isDirectoryKey]),
                      values.isDirectory == true else {
                    continue
                }
                if localPMPlanningPluginRecord(at: childURL) != nil {
                    return childURL
                }
                queue.append((childURL, current.depth + 1))
            }
        }
        return nil
    }

    private func enqueuePMExtensionHookWorkItem(_ item: PMExtensionHookWorkItem) {
        if pmExtensionHookQueuedKeys.contains(item.key) || pmExtensionHookRunningKeys.contains(item.key) {
            appendPMExtensionActivity(
                pluginID: item.descriptor.pluginID,
                pluginName: item.descriptor.pluginName,
                commandID: item.descriptor.commandID,
                commandTitle: item.descriptor.title,
                outcome: .info,
                detail: "Hook deduped while pending/running: \(item.event.rawValue)"
            )
            return
        }
        if let expiry = pmExtensionHookDedupExpirations[item.key], expiry > Date() {
            appendPMExtensionActivity(
                pluginID: item.descriptor.pluginID,
                pluginName: item.descriptor.pluginName,
                commandID: item.descriptor.commandID,
                commandTitle: item.descriptor.title,
                outcome: .info,
                detail: "Hook deduped in window: \(item.event.rawValue)"
            )
            return
        }
        pmExtensionHookQueuedKeys.insert(item.key)
        pmExtensionHookQueue.append(item)
    }

    private func expireStalePMExtensionHookDedupKeys() {
        let now = Date()
        pmExtensionHookDedupExpirations = pmExtensionHookDedupExpirations.filter { _, expiry in
            expiry > now
        }
    }

    private func drainPMExtensionHookQueueIfNeeded() {
        expireStalePMExtensionHookDedupKeys()
        while pmExtensionHookRunningCount < Self.hookMaxConcurrentRuns,
              !pmExtensionHookQueue.isEmpty {
            let workItem = pmExtensionHookQueue.removeFirst()
            pmExtensionHookQueuedKeys.remove(workItem.key)
            pmExtensionHookRunningKeys.insert(workItem.key)
            pmExtensionHookRunningCount += 1
            let descriptor = workItem.descriptor
            let task = workItem.task
            let extensionInputs = workItem.extensionInputs
            let event = workItem.event
            let retryCount = workItem.retryCount
            runPMExtensionCommandInBackground(
                descriptor,
                task: task,
                extensionInputs: extensionInputs
            ) { [weak self] succeeded in
                guard let self else { return }
                self.pmExtensionHookRunningCount = max(0, self.pmExtensionHookRunningCount - 1)
                self.pmExtensionHookRunningKeys.remove(workItem.key)
                if succeeded {
                    self.pmExtensionHookDedupExpirations[workItem.key] = Date().addingTimeInterval(Self.hookDedupWindowSeconds)
                } else if retryCount < Self.maxHookRetryCount {
                    let backoff = Double(retryCount + 1) * Self.hookRetryBackoffBaseSeconds
                    let retryItem = PMExtensionHookWorkItem(
                        key: workItem.key,
                        event: event,
                        descriptor: descriptor,
                        task: task,
                        extensionInputs: extensionInputs,
                        retryCount: retryCount + 1
                    )
                    self.appendPMExtensionActivity(
                        pluginID: descriptor.pluginID,
                        pluginName: descriptor.pluginName,
                        commandID: descriptor.commandID,
                        commandTitle: descriptor.title,
                        outcome: .info,
                        detail: "Hook retry scheduled in \(Int(backoff))s (\(retryCount + 1)/\(Self.maxHookRetryCount))"
                    )
                    self.runOnBackground { [weak self] in
                        Thread.sleep(forTimeInterval: backoff)
                        self?.runOnMain {
                            guard let self else { return }
                            self.enqueuePMExtensionHookWorkItem(retryItem)
                            self.drainPMExtensionHookQueueIfNeeded()
                        }
                    }
                } else {
                    self.pmExtensionHookDedupExpirations[workItem.key] = Date().addingTimeInterval(Self.hookDedupWindowSeconds)
                }
                self.drainPMExtensionHookQueueIfNeeded()
            }
        }
    }

    private func markPMExtensionRunStarted(
        pluginID: String,
        pluginName: String,
        inputSummary: String
    ) {
        let key = pluginID.lowercased()
        var stats = pmExtensionStatsByPluginID[key] ?? PMExtensionMutableStats(
            pluginID: pluginID,
            pluginName: pluginName
        )
        stats.pluginName = pluginName
        stats.totalRuns += 1
        stats.runningCount += 1
        stats.lastInputSummary = inputSummary
        pmExtensionStatsByPluginID[key] = stats
        refreshPMExtensionObservabilitySnapshots()
    }

    private func markPMExtensionRunFinished(
        pluginID: String,
        pluginName: String,
        startedAt: Date,
        succeeded: Bool,
        outputSummary: String,
        error: String?
    ) {
        let key = pluginID.lowercased()
        var stats = pmExtensionStatsByPluginID[key] ?? PMExtensionMutableStats(
            pluginID: pluginID,
            pluginName: pluginName
        )
        stats.pluginName = pluginName
        stats.runningCount = max(0, stats.runningCount - 1)
        if succeeded {
            stats.succeededRuns += 1
            stats.lastError = nil
        } else {
            stats.failedRuns += 1
            stats.lastError = error
        }
        let durationMS = max(0, Int(Date().timeIntervalSince(startedAt) * 1000))
        stats.totalDurationMS += durationMS
        stats.lastRunAt = Date()
        stats.lastOutputSummary = outputSummary
        pmExtensionStatsByPluginID[key] = stats
        refreshPMExtensionObservabilitySnapshots()
    }

    private func refreshPMExtensionObservabilitySnapshots() {
        pmExtensionObservability = pmExtensionStatsByPluginID.values
            .map { stats in
                let completed = max(1, stats.succeededRuns + stats.failedRuns)
                let avg = completed == 0 ? 0 : stats.totalDurationMS / completed
                let successRate = stats.totalRuns == 0 ? 0 : Int((Double(stats.succeededRuns) / Double(stats.totalRuns)) * 100)
                return PMExtensionObservabilitySnapshot(
                    id: stats.pluginID.lowercased(),
                    pluginID: stats.pluginID,
                    pluginName: stats.pluginName,
                    totalRuns: stats.totalRuns,
                    succeededRuns: stats.succeededRuns,
                    failedRuns: stats.failedRuns,
                    avgDurationMS: avg,
                    successRatePercent: successRate,
                    runningCount: stats.runningCount,
                    lastRunAt: stats.lastRunAt,
                    lastError: stats.lastError,
                    lastInputSummary: stats.lastInputSummary,
                    lastOutputSummary: stats.lastOutputSummary
                )
            }
            .sorted { lhs, rhs in
                if lhs.pluginName.localizedCaseInsensitiveCompare(rhs.pluginName) == .orderedSame {
                    return lhs.pluginID.localizedCaseInsensitiveCompare(rhs.pluginID) == .orderedAscending
                }
                return lhs.pluginName.localizedCaseInsensitiveCompare(rhs.pluginName) == .orderedAscending
            }
    }

    private func appendPMExtensionActivity(
        pluginID: String,
        pluginName: String,
        commandID: String?,
        commandTitle: String?,
        outcome: PMExtensionActivityLogEntry.Outcome,
        detail: String
    ) {
        let entry = PMExtensionActivityLogEntry(
            id: UUID(),
            timestamp: Date(),
            pluginID: pluginID,
            pluginName: pluginName,
            commandID: commandID,
            commandTitle: commandTitle,
            outcome: outcome,
            detail: detail
        )
        pmExtensionActivityLog.append(entry)
        if pmExtensionActivityLog.count > Self.maxExtensionActivityLogEntries {
            pmExtensionActivityLog.removeFirst(pmExtensionActivityLog.count - Self.maxExtensionActivityLogEntries)
        }
    }

    private static func sanitizedExtensionDirectoryName(_ rawValue: String, fallback: String) -> String {
        let normalized = rawValue
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9._-]+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        if !normalized.isEmpty {
            return normalized
        }
        let fallbackNormalized = fallback
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9._-]+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return fallbackNormalized.isEmpty ? "extension" : fallbackNormalized
    }

    private static func decodedPMExtensionCommandResponseMessage(from rawOutput: String) -> String? {
        let trimmed = rawOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let data = trimmed.data(using: .utf8),
           let decoded = try? JSONDecoder().decode(PMExtensionCommandResponse.self, from: data) {
            let message = decoded.message?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return message.isEmpty ? nil : message
        }

        guard let start = trimmed.firstIndex(of: "{"),
              let end = trimmed.lastIndex(of: "}"),
              start <= end else {
            return trimmed
        }
        let candidate = String(trimmed[start ... end])
        if let data = candidate.data(using: .utf8),
           let decoded = try? JSONDecoder().decode(PMExtensionCommandResponse.self, from: data) {
            let message = decoded.message?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return message.isEmpty ? trimmed : message
        }
        return trimmed
    }

    private struct GoogleStitchPromptOutput {
        let prompt: String
        let summary: String
    }

    private struct GoogleStitchExternalCommandResult {
        let succeeded: Bool
        let message: String
    }

    private static func generateGoogleStitchPrompt(from extensionInputs: [String: String]) -> GoogleStitchPromptOutput {
        let projectBrief = extensionInputs["projectBrief"]?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let productContext = extensionInputs["productContext"]?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let platform = extensionInputs["targetPlatform"]?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let visualStyle = extensionInputs["visualStyle"]?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let colorDirection = extensionInputs["colorDirection"]?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let typographyDirection = extensionInputs["typographyDirection"]?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let motionLevel = extensionInputs["motionLevel"]?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let accessibilityNotes = extensionInputs["accessibilityNotes"]?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let uiNotes = extensionInputs["uiNotes"]?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let rawProjectName = extensionInputs["projectName"]?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let normalizedProjectName = rawProjectName.lowercased()

        let effectiveProjectName: String
        if rawProjectName.isEmpty ||
            normalizedProjectName == "openmac" ||
            normalizedProjectName == "openmac system" {
            effectiveProjectName = "OpenMac Project"
        } else {
            effectiveProjectName = rawProjectName
        }
        let effectivePlatform = platform.isEmpty ? "macOS + iOS + iPadOS" : platform
        let effectiveVisualStyle = visualStyle.isEmpty
            ? "Contemporary, confident, product-grade interface with clear hierarchy."
            : visualStyle
        let effectiveColorDirection = colorDirection.isEmpty
            ? "Balanced, high-contrast palette with semantic status colors and restrained accents."
            : colorDirection
        let effectiveTypographyDirection = typographyDirection.isEmpty
            ? "Readable, modern UI typography with strong headings and compact body text rhythm."
            : typographyDirection
        let effectiveMotionLevel = motionLevel.isEmpty
            ? "Subtle and meaningful transitions only (state change, list updates, and panel transitions)."
            : motionLevel
        let effectiveAccessibility = accessibilityNotes.isEmpty
            ? "Meet contrast requirements, keyboard navigation, and clear focus states."
            : accessibilityNotes

        let effectiveProductContext: String
        if !productContext.isEmpty {
            effectiveProductContext = productContext
        } else if !projectBrief.isEmpty {
            effectiveProductContext = projectBrief
        } else {
            effectiveProductContext = "A productivity-focused app with Kanban workflow, multi-agent orchestration, and execution observability."
        }

        var promptSections: [String] = []
        promptSections.append("Design a polished app UI concept for \"\(effectiveProjectName)\".")
        promptSections.append("Platform scope: \(effectivePlatform)")
        promptSections.append("Product context:\n\(effectiveProductContext)")
        promptSections.append("Visual style direction:\n\(effectiveVisualStyle)")
        promptSections.append("Color direction:\n\(effectiveColorDirection)")
        promptSections.append("Typography direction:\n\(effectiveTypographyDirection)")
        promptSections.append("Motion direction:\n\(effectiveMotionLevel)")
        promptSections.append("Accessibility bar:\n\(effectiveAccessibility)")
        if !uiNotes.isEmpty {
            promptSections.append("Additional UI notes:\n\(uiNotes)")
        }
        promptSections.append(
            """
            Expected output:
            1) High-level visual concept and rationale.
            2) Key screens (overview, primary workflow, details).
            3) Reusable component system (buttons, cards, list items, status indicators).
            4) Responsive behavior across supported platforms.
            5) A concise style guide (spacing, radius, elevation, icon style, motion principles).
            """
        )
        let prompt = promptSections.joined(separator: "\n\n")
        let summary = "Generated Stitch UI prompt for \(effectiveProjectName) (\(effectivePlatform))."
        return GoogleStitchPromptOutput(prompt: prompt, summary: summary)
    }

    private static func runGoogleStitchExternalCommandIfConfigured(
        output: GoogleStitchPromptOutput,
        environment: [String: String]
    ) -> GoogleStitchExternalCommandResult? {
        let configuredCommand = environment["OPENMAC_GOOGLE_STITCH_COMMAND"]?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !configuredCommand.isEmpty else { return nil }

        let payload: [String: Any] = [
            "prompt": output.prompt,
            "summary": output.summary
        ]
        guard let payloadData = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted]),
              let payloadJSON = String(data: payloadData, encoding: .utf8) else {
            return GoogleStitchExternalCommandResult(
                succeeded: false,
                message: "Failed to encode Stitch payload JSON"
            )
        }

        let homePath = environment["HOME"] ?? NSHomeDirectory()
        do {
            let result = try runShellCommand(
                configuredCommand,
                workingDirectoryPath: homePath,
                stdin: payloadJSON,
                timeoutSeconds: 90,
                environment: environment
            )
            if result.timedOut {
                return GoogleStitchExternalCommandResult(
                    succeeded: false,
                    message: "Google Stitch command timed out in 90s"
                )
            }
            if result.code != 0 {
                let detail = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
                    : result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                let failure = detail.isEmpty ? "exit \(result.code)" : detail
                return GoogleStitchExternalCommandResult(
                    succeeded: false,
                    message: "Google Stitch command failed: \(failure)"
                )
            }
            let stdout = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            let resolved = decodedPMExtensionCommandResponseMessage(from: stdout)
                ?? output.prompt
            return GoogleStitchExternalCommandResult(
                succeeded: true,
                message: resolved
            )
        } catch {
            return GoogleStitchExternalCommandResult(
                succeeded: false,
                message: "Google Stitch command failed to launch: \(error.localizedDescription)"
            )
        }
    }

    private static func defaultBrainstormPMPlannerUISchema() -> PMPlannerUIExtensionSchema {
        PMPlannerUIExtensionSchema(
            fields: [
                PMPlannerUIExtensionField(
                    id: "focus",
                    type: pmPlannerUIFieldFocusInput,
                    label: "",
                    placeholder: L10n.string("Brainstorm Focus (optional)"),
                    minHeight: nil,
                    maxHeight: nil
                ),
                PMPlannerUIExtensionField(
                    id: "status",
                    type: pmPlannerUIFieldStatusText,
                    label: "",
                    placeholder: "",
                    minHeight: nil,
                    maxHeight: nil
                ),
                PMPlannerUIExtensionField(
                    id: "transcript",
                    type: pmPlannerUIFieldTranscriptOutput,
                    label: "",
                    placeholder: L10n.string("No brainstorm output yet. Run a brainstorm round to collect ideas."),
                    minHeight: 130,
                    maxHeight: 200
                )
            ],
            actions: [
                PMPlannerUIExtensionAction(
                    id: pmPlannerUIActionRun,
                    title: L10n.string("Run Brainstorm Round"),
                    commandID: nil
                ),
                PMPlannerUIExtensionAction(
                    id: pmPlannerUIActionApply,
                    title: L10n.string("Apply Brainstorm to Brief"),
                    commandID: nil
                ),
                PMPlannerUIExtensionAction(
                    id: pmPlannerUIActionApplyGenerate,
                    title: L10n.string("Apply + Generate"),
                    commandID: nil
                ),
                PMPlannerUIExtensionAction(
                    id: pmPlannerUIActionApplyCreate,
                    title: L10n.string("Create + Run Assigned"),
                    commandID: nil
                ),
                PMPlannerUIExtensionAction(
                    id: pmPlannerUIActionClear,
                    title: L10n.string("Clear Brainstorm"),
                    commandID: nil
                )
            ]
        )
    }

    private static func defaultGoogleStitchPMPlannerUISchema() -> PMPlannerUIExtensionSchema {
        PMPlannerUIExtensionSchema(
            fields: [
                PMPlannerUIExtensionField(
                    id: "targetPlatform",
                    type: "text.input",
                    label: "Target Platform",
                    placeholder: "macOS / iOS / iPadOS / web",
                    minHeight: nil,
                    maxHeight: nil
                ),
                PMPlannerUIExtensionField(
                    id: "visualStyle",
                    type: "multiline.input",
                    label: "Visual Style",
                    placeholder: "Clean, modern, energetic, premium, playful...",
                    minHeight: 70,
                    maxHeight: 120
                ),
                PMPlannerUIExtensionField(
                    id: "colorDirection",
                    type: "text.input",
                    label: "Color Direction",
                    placeholder: "e.g. warm neutral base + vivid action accents",
                    minHeight: nil,
                    maxHeight: nil
                ),
                PMPlannerUIExtensionField(
                    id: "typographyDirection",
                    type: "text.input",
                    label: "Typography Direction",
                    placeholder: "e.g. bold headings + compact readable body",
                    minHeight: nil,
                    maxHeight: nil
                ),
                PMPlannerUIExtensionField(
                    id: "motionLevel",
                    type: "text.input",
                    label: "Motion Level",
                    placeholder: "subtle / medium / expressive",
                    minHeight: nil,
                    maxHeight: nil
                ),
                PMPlannerUIExtensionField(
                    id: "accessibilityNotes",
                    type: "text.input",
                    label: "Accessibility Notes",
                    placeholder: "contrast, keyboard nav, screen reader constraints...",
                    minHeight: nil,
                    maxHeight: nil
                ),
                PMPlannerUIExtensionField(
                    id: "uiNotes",
                    type: "multiline.input",
                    label: "Additional UI Notes",
                    placeholder: "Special component ideas, layouts, and constraints...",
                    minHeight: 90,
                    maxHeight: 150
                ),
                PMPlannerUIExtensionField(
                    id: "stitchPrompt",
                    type: "multiline.input",
                    label: "Generated Stitch Prompt",
                    placeholder: "Run Generate Stitch Prompt to fill this field.",
                    minHeight: 150,
                    maxHeight: 240
                )
            ],
            actions: [
                PMPlannerUIExtensionAction(
                    id: "command:\(systemGoogleStitchGenerateCommandID)",
                    title: "Generate Stitch Prompt",
                    commandID: systemGoogleStitchGenerateCommandID
                )
            ]
        )
    }

    private static func pmPlannerUISchema(
        from summary: LocalPMPlanningUIExtensionUISummary?
    ) -> PMPlannerUIExtensionSchema? {
        guard let summary else { return nil }

        let fields = (summary.fields ?? []).enumerated().compactMap { index, fieldSummary -> PMPlannerUIExtensionField? in
            guard fieldSummary.enabled ?? true else { return nil }
            let normalizedType = normalizedPMPlannerUIFieldType(fieldSummary.type ?? "")
            guard !normalizedType.isEmpty else { return nil }
            let fieldID = {
                let trimmed = (fieldSummary.id ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? "field-\(index)" : trimmed
            }()
            let label = (fieldSummary.label ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let placeholder = (fieldSummary.placeholder ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let minHeight = (fieldSummary.minHeight ?? 0) > 0 ? fieldSummary.minHeight : nil
            let maxHeight = (fieldSummary.maxHeight ?? 0) > 0 ? fieldSummary.maxHeight : nil
            return PMPlannerUIExtensionField(
                id: fieldID,
                type: normalizedType,
                label: label,
                placeholder: placeholder,
                minHeight: minHeight,
                maxHeight: maxHeight
            )
        }

        let actions = (summary.actions ?? []).enumerated().compactMap { index, actionSummary -> PMPlannerUIExtensionAction? in
            guard actionSummary.enabled ?? true else { return nil }
            let normalizedActionID = normalizedPMPlannerUIActionID(actionSummary.id ?? "")
            guard !normalizedActionID.isEmpty else { return nil }
            let title = (actionSummary.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let fallbackTitle = "Action \(index + 1)"
            return PMPlannerUIExtensionAction(
                id: normalizedActionID,
                title: title.isEmpty ? fallbackTitle : title,
                commandID: (actionSummary.commandID ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }

        if fields.isEmpty, actions.isEmpty {
            return nil
        }
        return PMPlannerUIExtensionSchema(fields: fields, actions: actions)
    }

    private static func normalizedPMPlannerUIFieldType(_ rawValue: String) -> String {
        let normalized = rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch normalized {
        case "focus", "focus.input":
            return pmPlannerUIFieldFocusInput
        case "input", "text.input", "singleline.input":
            return "text.input"
        case "status", "status.text", "message.status":
            return pmPlannerUIFieldStatusText
        case "transcript", "transcript.output":
            return pmPlannerUIFieldTranscriptOutput
        case "output", "multiline.input", "multiline.output", "text.output", "textarea.input":
            return "multiline.input"
        default:
            return normalized
        }
    }

    private static func normalizedPMPlannerUIActionID(_ rawValue: String) -> String {
        let normalized = rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch normalized {
        case "run", "run-round", "brainstorm.run", "pm.brainstorm.run":
            return pmPlannerUIActionRun
        case "apply", "apply-brief", "brainstorm.apply", "pm.brainstorm.apply":
            return pmPlannerUIActionApply
        case "apply-generate", "brainstorm.apply.generate", "pm.brainstorm.apply.generate":
            return pmPlannerUIActionApplyGenerate
        case "apply-create", "brainstorm.apply.create", "pm.brainstorm.apply.create":
            return pmPlannerUIActionApplyCreate
        case "clear", "brainstorm.clear", "pm.brainstorm.clear":
            return pmPlannerUIActionClear
        default:
            return normalized
        }
    }

    private static func normalizedPMExtensionHookEvent(_ rawValue: String) -> String {
        let normalized = rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch normalized {
        case "ticket.created", "task.created":
            return PMExtensionHookEvent.ticketCreated.rawValue
        case "run.finished", "task.run.finished", "execution.finished":
            return PMExtensionHookEvent.runFinished.rawValue
        case "review.entered", "task.review.entered":
            return PMExtensionHookEvent.reviewEntered.rawValue
        case "board.run.finished", "board.finished", "pipeline.finished", "autopilot.finished":
            return PMExtensionHookEvent.boardRunFinished.rawValue
        default:
            return normalized
        }
    }

    private static func pmPluginNamesPreview(_ names: [String], maxShown: Int = 3) -> String {
        let normalized = names
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !normalized.isEmpty else { return "-" }
        if normalized.count <= maxShown {
            return normalized.joined(separator: ", ")
        }
        let shown = normalized.prefix(maxShown).joined(separator: ", ")
        let remaining = normalized.count - maxShown
        return shown + L10n.format(" and %d more", remaining)
    }

    private struct LocalPMPlanningPluginManifestSummary: Decodable {
        let id: String?
        let name: String?
        let version: String?
        let channel: String?
        let summary: String?
        let minOpenMacVersion: String?
        let maxOpenMacVersion: String?
        let conflictsWith: [String]?
        let dependencies: [String]?
        let capabilities: [String]?
        let permissions: [String]?
        let entrypoint: String?
        let commands: [LocalPMPlanningCommandManifestSummary]?
        let eventHooks: [LocalPMPlanningEventHookManifestSummary]?
        let memoryProviders: [LocalPMPlanningMemoryProviderManifestSummary]?
        let enabled: Bool?
        let uiExtensions: [LocalPMPlanningUIExtensionManifestSummary]?
    }

    private struct LocalPMPlanningCommandManifestSummary: Decodable {
        let id: String?
        let title: String?
        let subtitle: String?
        let slots: [String]?
        let slot: String?
        let permissions: [String]?
        let timeoutSeconds: Int?
        let entrypoint: String?
        let enabled: Bool?
    }

    private struct LocalPMPlanningUIExtensionManifestSummary: Decodable {
        let id: String?
        let slot: String?
        let title: String?
        let subtitle: String?
        let component: String?
        let ui: LocalPMPlanningUIExtensionUISummary?
        let priority: Int?
        let enabled: Bool?
    }

    private struct LocalPMPlanningMemoryProviderManifestSummary: Decodable {
        let id: String?
        let title: String?
        let commandID: String?
        let strategy: String?
        let priority: Int?
        let enabled: Bool?
    }

    private struct LocalPMPlanningUIExtensionUISummary: Decodable {
        let fields: [LocalPMPlanningUIExtensionUIFieldSummary]?
        let actions: [LocalPMPlanningUIExtensionUIActionSummary]?
    }

    private struct LocalPMPlanningUIExtensionUIFieldSummary: Decodable {
        let id: String?
        let type: String?
        let label: String?
        let placeholder: String?
        let minHeight: Int?
        let maxHeight: Int?
        let enabled: Bool?
    }

    private struct LocalPMPlanningUIExtensionUIActionSummary: Decodable {
        let id: String?
        let title: String?
        let commandID: String?
        let enabled: Bool?
    }

    private struct LocalPMPlanningEventHookManifestSummary: Decodable {
        let id: String?
        let event: String?
        let commandID: String?
        let enabled: Bool?
    }

    private struct LocalPMPlanningPluginRecord {
        let manifest: LocalPMPlanningPluginManifestSummary
        let directoryURL: URL
    }

    private struct PMExtensionCommandRequest: Encodable {
        let type: String
        let commandID: String
        let slots: [String]
        let boardName: String
        let projectName: String
        let projectBrief: String
        let extensionInputs: [String: String]
        let selectedTask: PMExtensionCommandTaskDescriptor?
        let availableAgents: [PMExtensionCommandAgentDescriptor]
    }

    private struct PMExtensionCommandTaskDescriptor: Encodable {
        let id: UUID
        let title: String
        let details: String
        let status: String
        let storyPoints: Int
        let requiredSkills: [String]
        let assignedAgent: String?
    }

    private struct PMExtensionCommandAgentDescriptor: Encodable {
        let name: String
        let skills: [String]
        let maxConcurrentTasks: Int
    }

    private struct PMExtensionCommandResponse: Decodable {
        let message: String?
    }

    private func shouldSyncMCPRegistry(lastSyncedAt: Date?) -> Bool {
        guard let lastSyncedAt else { return true }
        return Date().timeIntervalSince(lastSyncedAt) >= Self.mcpRegistrySyncTTL
    }

    private struct MCPRegistryResponse: Decodable {
        let servers: [MCPRegistryEntry]
    }

    private struct MCPRegistryEntry: Decodable {
        let server: MCPRegistryServer
    }

    private struct MCPRegistryServer: Decodable {
        let name: String
        let description: String?
        let remotes: [MCPRegistryRemote]?
    }

    private struct MCPRegistryRemote: Decodable {
        let url: String?
    }

    private static func fetchMCPServersFromRegistry(
        registryURL: String
    ) -> (servers: [MCPServerDescriptor]?, error: String?) {
        let trimmedRegistryURL = registryURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmedRegistryURL), !trimmedRegistryURL.isEmpty else {
            return (nil, "invalid registry URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let semaphore = DispatchSemaphore(value: 0)
        var receivedData: Data?
        var httpStatusCode = 0
        var receivedError: Error?

        URLSession.shared.dataTask(with: request) { data, response, error in
            receivedData = data
            httpStatusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            receivedError = error
            semaphore.signal()
        }.resume()

        if semaphore.wait(timeout: .now() + 15) == .timedOut {
            return (nil, "network timeout")
        }

        if let receivedError {
            return (nil, receivedError.localizedDescription)
        }
        guard (200 ... 299).contains(httpStatusCode) else {
            return (nil, "HTTP \(httpStatusCode)")
        }
        guard let receivedData else {
            return (nil, "empty response")
        }

        let decoder = JSONDecoder()
        guard let payload = try? decoder.decode(MCPRegistryResponse.self, from: receivedData) else {
            return (nil, "invalid registry JSON")
        }

        var seen = Set<String>()
        let servers: [MCPServerDescriptor] = payload.servers.compactMap { entry in
            let name = entry.server.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return nil }
            guard let remoteURL = entry.server.remotes?
                .compactMap({ $0.url?.trimmingCharacters(in: .whitespacesAndNewlines) })
                .first(where: { !$0.isEmpty }) else {
                return nil
            }
            let cliName = MCPServerDescriptor.cliSafeServerName(name)
            guard !seen.contains(cliName) else { return nil }
            seen.insert(cliName)

            let bootstrapCommand = "codex mcp add \(shellQuoted(cliName)) --url \(shellQuoted(remoteURL))"
            let keywordHints = inferredKeywordHints(name: name, description: entry.server.description)
            return MCPServerDescriptor(
                name: name,
                remoteURL: remoteURL,
                bootstrapCommand: bootstrapCommand,
                verificationCommand: "codex mcp get \(shellQuoted(cliName)) --json",
                keywordHints: keywordHints,
                isEnabled: true,
                source: .registry,
                notes: entry.server.description
            )
        }

        return (servers, nil)
    }

    private static func inferredKeywordHints(name: String, description _: String?) -> [String] {
        let raw = name.lowercased()
        let separators = CharacterSet.alphanumerics.inverted
        var seen = Set<String>()
        var keywords: [String] = []
        for token in raw.components(separatedBy: separators) {
            let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.count >= 3 else { continue }
            guard !seen.contains(trimmed) else { continue }
            seen.insert(trimmed)
            keywords.append(trimmed)
            if keywords.count >= 16 { break }
        }
        return keywords
    }

    private static func installedXcodeDeveloperDirectoryPath(
        fileManager: FileManager = .default
    ) -> String? {
        let defaultPath = "/Applications/Xcode.app/Contents/Developer"
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: defaultPath, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            return nil
        }
        return defaultPath
    }

    private static func activeDeveloperDirectoryPath(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> String? {
        if let override = environment["DEVELOPER_DIR"]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !override.isEmpty {
            return override
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcode-select")
        process.arguments = ["-p"]
        process.environment = environment

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = outputPipe

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }

        guard process.terminationStatus == 0 else { return nil }
        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: outputData, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let output, !output.isEmpty else { return nil }
        return output
    }

    fileprivate static func xcodeSelectRepairCommandIfNeeded(
        activeDeveloperDirectoryPath: String?,
        installedXcodeDeveloperDirectoryPath: String?
    ) -> String? {
        guard let installedXcodeDeveloperDirectoryPath,
              !installedXcodeDeveloperDirectoryPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        guard let activeDeveloperDirectoryPath,
              !activeDeveloperDirectoryPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        let normalizedInstalledPath = URL(
            fileURLWithPath: installedXcodeDeveloperDirectoryPath,
            isDirectory: true
        ).standardizedFileURL.path
        let normalizedActivePath = URL(
            fileURLWithPath: activeDeveloperDirectoryPath,
            isDirectory: true
        ).standardizedFileURL.path

        guard normalizedActivePath != normalizedInstalledPath else { return nil }
        guard normalizedActivePath.hasPrefix("/Library/Developer/CommandLineTools") else { return nil }
        return "sudo xcode-select -s \(shellQuoted(normalizedInstalledPath))"
    }

    fileprivate static func parseXcodeBuildSettingValue(
        _ key: String,
        from output: String
    ) -> String? {
        for line in output.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.hasPrefix("\(key) = ") else { continue }
            let value = trimmed.dropFirst((key + " = ").count)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else { continue }
            return value
        }
        return nil
    }

    fileprivate static func verificationBuildOverrides(
        forSDKRoot sdkRoot: String?
    ) -> (sdk: String?, destination: String?, modeLabel: String) {
        let normalized = sdkRoot?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""

        if normalized.contains("iphoneos") || normalized.contains("iphonesimulator") {
            return ("iphonesimulator", "generic/platform=iOS Simulator", "iOS Simulator")
        }
        if normalized.contains("appletvos") || normalized.contains("appletvsimulator") {
            return ("appletvsimulator", "generic/platform=tvOS Simulator", "tvOS Simulator")
        }
        if normalized.contains("watchos") || normalized.contains("watchsimulator") {
            return ("watchsimulator", "generic/platform=watchOS Simulator", "watchOS Simulator")
        }
        if normalized.contains("xros") || normalized.contains("xrsimulator") {
            return ("xrsimulator", "generic/platform=visionOS Simulator", "visionOS Simulator")
        }
        return (nil, nil, "Default")
    }

    private static func shellQuoted(_ value: String) -> String {
        let escaped = value.replacingOccurrences(of: "'", with: "'\"'\"'")
        return "'\(escaped)'"
    }

    private static func shellCommandEnvironment(
        _ sourceEnvironment: [String: String] = ProcessInfo.processInfo.environment
    ) -> [String: String] {
        var environment = sourceEnvironment
        if let codexHome = environment["CODEX_HOME"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           codexHome.isEmpty {
            environment["CODEX_HOME"] = nil
        }

        let fileManager = FileManager.default
        let homePath = environment["HOME"] ?? NSHomeDirectory()
        let codexExecutableCandidates = [
            environment["CODEX_CLI_PATH"]?.trimmingCharacters(in: .whitespacesAndNewlines),
            "/Applications/Codex.app/Contents/Resources/codex",
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex",
            "\(homePath)/.local/bin/codex"
        ]
            .compactMap { $0 }
            .filter { !$0.isEmpty && fileManager.isExecutableFile(atPath: $0) }
        let codexExecutableDirectories = codexExecutableCandidates
            .map { URL(fileURLWithPath: $0).deletingLastPathComponent().path }

        let pathDirectories = codexExecutableDirectories + [
            "\(homePath)/.codex/bin",
            "/opt/homebrew/bin",
            "/usr/local/bin"
        ]
        if let mergedPath = mergedShellPATH(
            prependingDirectories: pathDirectories,
            existingPath: environment["PATH"],
            fileManager: fileManager
        ) {
            environment["PATH"] = mergedPath
        }

        return environment
    }

    private static func mergedShellPATH(
        prependingDirectories directories: [String],
        existingPath: String?,
        fileManager: FileManager
    ) -> String? {
        var orderedPaths: [String] = []
        var seen = Set<String>()

        for directory in directories {
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: directory, isDirectory: &isDirectory),
                  isDirectory.boolValue else {
                continue
            }
            guard seen.insert(directory).inserted else { continue }
            orderedPaths.append(directory)
        }

        let existingSegments = (existingPath ?? "")
            .split(separator: ":")
            .map { String($0) }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        for segment in existingSegments where seen.insert(segment).inserted {
            orderedPaths.append(segment)
        }

        guard !orderedPaths.isEmpty else { return nil }
        return orderedPaths.joined(separator: ":")
    }

    private struct ShellCommandExecutionResult {
        let code: Int32
        let stdout: String
        let stderr: String
        let timedOut: Bool
    }

    private static func mergedShellOutput(stdout: String, stderr: String, trim: Bool = true) -> String {
        let merged = [stdout, stderr]
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
        if trim {
            return merged.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return merged
    }

    private static func executeShellCommand(
        _ command: String,
        workingDirectoryPath: String? = nil,
        stdin: String? = nil,
        timeoutSeconds: Int? = nil,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> ShellCommandExecutionResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", command]
        if let workingDirectoryPath {
            process.currentDirectoryURL = URL(fileURLWithPath: workingDirectoryPath, isDirectory: true)
        }
        process.environment = shellCommandEnvironment(environment)

        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let dataLock = NSLock()
        var stdoutData = Data()
        var stderrData = Data()

        stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else {
                handle.readabilityHandler = nil
                return
            }
            dataLock.lock()
            stdoutData.append(chunk)
            dataLock.unlock()
        }

        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else {
                handle.readabilityHandler = nil
                return
            }
            dataLock.lock()
            stderrData.append(chunk)
            dataLock.unlock()
        }

        let waitGroup = DispatchGroup()
        waitGroup.enter()
        process.terminationHandler = { _ in
            waitGroup.leave()
        }

        try process.run()
        if let stdinData = stdin?.data(using: .utf8), !stdinData.isEmpty {
            stdinPipe.fileHandleForWriting.write(stdinData)
        }
        stdinPipe.fileHandleForWriting.closeFile()

        let timedOut: Bool
        if let timeoutSeconds {
            let resolvedTimeout = max(1, timeoutSeconds)
            timedOut = waitGroup.wait(timeout: .now() + .seconds(resolvedTimeout)) == .timedOut
        } else {
            waitGroup.wait()
            timedOut = false
        }

        if timedOut {
            process.terminate()
            _ = waitGroup.wait(timeout: .now() + .seconds(2))
        }

        stdoutPipe.fileHandleForReading.readabilityHandler = nil
        stderrPipe.fileHandleForReading.readabilityHandler = nil

        let stdoutRemainder = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrRemainder = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        dataLock.lock()
        stdoutData.append(stdoutRemainder)
        stderrData.append(stderrRemainder)
        dataLock.unlock()

        let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
        let stderr = String(data: stderrData, encoding: .utf8) ?? ""
        let code = timedOut ? -9 : process.terminationStatus
        return ShellCommandExecutionResult(
            code: code,
            stdout: stdout,
            stderr: stderr,
            timedOut: timedOut
        )
    }

    private static func runShellCommand(
        _ command: String,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> (code: Int32, output: String) {
        let result = try executeShellCommand(
            command,
            timeoutSeconds: nil,
            environment: environment
        )
        return (
            result.code,
            mergedShellOutput(stdout: result.stdout, stderr: result.stderr)
        )
    }

    private static func runShellCommand(
        _ command: String,
        timeoutSeconds: Int,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> (code: Int32, output: String, timedOut: Bool) {
        let result = try executeShellCommand(
            command,
            timeoutSeconds: timeoutSeconds,
            environment: environment
        )
        return (
            result.code,
            mergedShellOutput(stdout: result.stdout, stderr: result.stderr),
            result.timedOut
        )
    }

    private static func runShellCommand(
        _ command: String,
        workingDirectoryPath: String,
        stdin: String,
        timeoutSeconds: Int,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> (code: Int32, stdout: String, stderr: String, timedOut: Bool) {
        let result = try executeShellCommand(
            command,
            workingDirectoryPath: workingDirectoryPath,
            stdin: stdin,
            timeoutSeconds: timeoutSeconds,
            environment: environment
        )
        return (result.code, result.stdout, result.stderr, result.timedOut)
    }

    private func executeWithAutoRetry(
        task: WorkTask,
        agent: AgentProfile,
        onProgress: @escaping (_ update: String) -> Void
    ) -> ExecutionAttemptResult {
        if let mcpFailure = ensureMCPServersReadyForExecution(task: task, agent: agent, onProgress: onProgress) {
            return ExecutionAttemptResult(
                outcome: .failure(message: mcpFailure),
                retriesPerformed: 0
            )
        }

        var outcome = executeTaskWithBoardScopedProjectsDirectory(task: task, agent: agent, onProgress: onProgress)
        outcome = enforceRealArtifactVerificationIfNeeded(
            task: task,
            outcome: outcome,
            onProgress: onProgress
        )
        let config = executionAutoRetryConfiguration
        guard config.isEnabled, config.maxRetryCount > 0 else {
            return ExecutionAttemptResult(outcome: outcome, retriesPerformed: 0)
        }

        var retriesPerformed = 0
        while retriesPerformed < config.maxRetryCount {
            guard case let .failure(errorMessage) = outcome else {
                break
            }
            guard let retryType = retryableErrorType(for: errorMessage),
                  config.retryableErrorTypes.contains(retryType) else {
                break
            }

            let backoff = max(0, config.backoffSeconds * pow(2.0, Double(retriesPerformed)))
            retriesPerformed += 1
            onProgress(
                "Auto-retry scheduled (\(retriesPerformed)/\(config.maxRetryCount)) in \(String(format: "%.1f", backoff))s due to \(retryType.rawValue)"
            )
            if backoff > 0 {
                Thread.sleep(forTimeInterval: backoff)
            }
            onProgress("Auto-retry attempt \(retriesPerformed) for \"\(task.title)\"")
            outcome = executeTaskWithBoardScopedProjectsDirectory(task: task, agent: agent, onProgress: onProgress)
            outcome = enforceRealArtifactVerificationIfNeeded(
                task: task,
                outcome: outcome,
                onProgress: onProgress
            )
        }

        return ExecutionAttemptResult(outcome: outcome, retriesPerformed: retriesPerformed)
    }

    private struct RealArtifactVerificationResult {
        let successNote: String?
        let failureReason: String?
        let debugLog: String?

        static func passed(note: String?) -> Self {
            Self(successNote: note, failureReason: nil, debugLog: nil)
        }

        static func failed(reason: String, debugLog: String? = nil) -> Self {
            Self(successNote: nil, failureReason: reason, debugLog: debugLog)
        }
    }

    private struct DeferredRealArtifactVerificationOutcome {
        let task: WorkTask?
        let status: String
        let detail: String
        let boardMessage: String?
        let boardMessageSeverity: BoardMessageSeverity?
    }

    private enum RealArtifactIntegrityIssueCode {
        case missingBundleIdentifier
    }

    private struct RealArtifactIntegrityIssue {
        let code: RealArtifactIntegrityIssueCode
        let reason: String
        let debugLog: String?
    }

    private struct RealArtifactIntegrityCheckResult {
        let notes: [String]
        let issue: RealArtifactIntegrityIssue?
    }

    private struct RealArtifactRepairResult {
        let didRepair: Bool
        let note: String?
        let debugLog: String?
    }

    private struct PBXBuildSettingsSnapshot {
        let hasInfoPlist: Bool
        let sdkRoot: String?
        let productName: String?
        let bundleIdentifierPrefix: String?
        let bundleIdentifier: String?
        let lineIndexByKey: [String: Int]
        let indentByKey: [String: String]

        var isCandidateAppBuildSettings: Bool {
            hasInfoPlist && sdkRoot != nil
        }

        var hasBundleIdentifier: Bool {
            guard let bundleIdentifier else { return false }
            return !bundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private enum XcodeBuildContainer {
        case project(URL)
        case workspace(URL)

        var url: URL {
            switch self {
            case let .project(url), let .workspace(url):
                return url
            }
        }

        var displayName: String {
            url.lastPathComponent
        }

        var xcodebuildListArgument: String {
            switch self {
            case .project:
                return "-project"
            case .workspace:
                return "-workspace"
            }
        }
    }

    private static let realArtifactXcodeListTimeoutSeconds = 45
    private static let realArtifactBuildSettingsTimeoutSeconds = 45
    private static let realArtifactBuildTimeoutSeconds = 240

    private func enforceRealArtifactVerificationIfNeeded(
        task: WorkTask,
        outcome: AgentTaskExecutionOutcome,
        onProgress: @escaping (_ update: String) -> Void
    ) -> AgentTaskExecutionOutcome {
        guard case let .success(summary) = outcome else { return outcome }
        guard shouldRunRealArtifactVerification(for: task) else { return outcome }

        onProgress(message("Running real install verification..."))
        let verification = runRealArtifactVerification(for: task)
        if let failureReason = verification.failureReason {
            let userMessage = message("Real install verification failed: %@", failureReason)
            onProgress(userMessage)
            if let debugLog = verification.debugLog,
               !debugLog.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return .failure(
                    message: userMessage + DefaultAgentTaskExecutor.debugLogDelimiter + debugLog
                )
            }
            return .failure(message: userMessage)
        }

        guard let successNote = verification.successNote,
              !successNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return outcome
        }
        onProgress(successNote)
        let normalizedSummary = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        let mergedSummary: String
        if normalizedSummary.isEmpty {
            mergedSummary = successNote
        } else {
            mergedSummary = normalizedSummary + "\n\n" + successNote
        }
        return .success(summary: mergedSummary)
    }

    private func shouldRunRealArtifactVerification(for task: WorkTask) -> Bool {
        let policy = executionRealArtifactVerificationPolicy
        guard policy.isEnabled else { return false }
        guard policy.requireInfoPlistExecutableKey || policy.requireXcodeBuild else { return false }
        if policy.runVerificationOnlyOnTerminalTask,
           !isTerminalTaskForRealArtifactVerification(task) {
            return false
        }

        let contract = task.resolvedDeliveryContract
        guard contract.gateMode == .strict && contract.outputType == .app else { return false }
        return !shouldDeferRealArtifactVerification(for: task)
    }

    private func isTerminalTaskForRealArtifactVerification(_ task: WorkTask) -> Bool {
        isTerminalTaskForRealArtifactVerification(task, within: tasks)
    }

    private func isTerminalTaskForRealArtifactVerification(
        _ task: WorkTask,
        within allTasks: [WorkTask]
    ) -> Bool {
        let normalizedTitle = Self.normalizedDependencyTitle(task.title)
        guard !normalizedTitle.isEmpty else { return false }

        return !allTasks.contains { candidate in
            guard candidate.id != task.id else { return false }
            let dependencies = Self.parsedDependencyReferences(from: candidate.details)
            return dependencies.contains(where: { $0.normalizedTitle == normalizedTitle })
        }
    }

    private func shouldDeferRealArtifactVerification(for task: WorkTask) -> Bool {
        let context = "\(task.title)\n\(task.details)".lowercased()

        // Keep M2 core-implementation execution unblocked; strict install checks
        // should happen at quality/release gates.
        let isM2CoreImplementation =
            context.contains("milestone: m2") &&
            (context.contains("core implementation") ||
             (context.contains("core") && context.contains("implementation")) ||
             context.contains("epic: core product"))
        if isM2CoreImplementation {
            return true
        }

        let verifyNowSignals = [
            "quality gate",
            "integration & quality gate",
            "release",
            "handoff",
            "real install verification",
            "strict app install verification",
            "install verification",
            "final install validation",
            "build and run",
            "archive",
            "testflight",
            "xcodebuild",
            "simulator",
            ".xcodeproj",
            ".xcworkspace",
            "cfbundleexecutable",
            "ipa",
            "審查",
            "整合與品質閘門",
            "品質",
            "發佈",
            "交付",
            "上架",
            "真實安裝驗證",
            "安裝驗證"
        ]
        if verifyNowSignals.contains(where: { context.contains($0) }) {
            return false
        }

        let deferSignals = [
            "epic: planning",
            "scope",
            "success criteria",
            "architecture",
            "delivery plan",
            "roadmap",
            "requirements",
            "spec",
            "specification",
            "docs",
            "document",
            "risk spike",
            "research",
            "core implementation",
            "epic: core product",
            "mvp complete",
            "實作",
            "規劃",
            "需求",
            "藍圖",
            "說明文件"
        ]

        return deferSignals.contains { context.contains($0) }
    }

    private func candidateTaskForDeferredRealArtifactVerification() -> WorkTask? {
        candidateTaskForDeferredRealArtifactVerification(within: tasks)
    }

    private func candidateTaskForDeferredRealArtifactVerification(
        within allTasks: [WorkTask]
    ) -> WorkTask? {
        let succeededStrictAppTasks = allTasks
            .filter { task in
                let contract = task.resolvedDeliveryContract
                guard contract.gateMode == .strict, contract.outputType == .app else { return false }
                guard !shouldDeferRealArtifactVerification(for: task) else { return false }
                return task.executionRecord?.status == .succeeded
            }

        guard !succeededStrictAppTasks.isEmpty else { return nil }
        if let terminal = succeededStrictAppTasks.first(where: { task in
            isTerminalTaskForRealArtifactVerification(task, within: allTasks)
        }) {
            return terminal
        }

        return succeededStrictAppTasks.max { lhs, rhs in
            let lhsFinishedAt = lhs.executionRecord?.lastFinishedAt ?? lhs.createdAt
            let rhsFinishedAt = rhs.executionRecord?.lastFinishedAt ?? rhs.createdAt
            if lhsFinishedAt != rhsFinishedAt {
                return lhsFinishedAt < rhsFinishedAt
            }
            return lhs.createdAt < rhs.createdAt
        }
    }

    private func runDeferredRealArtifactVerificationIfNeeded() -> DeferredRealArtifactVerificationOutcome? {
        let snapshot = readOnMain { [self] in
            (
                policy: self.executionRealArtifactVerificationPolicy,
                tasks: self.tasks,
                boardScopedProjectsPath: self.resolvedBoardScopedProjectsDirectoryPath()
            )
        }

        let policy = snapshot.policy
        guard policy.isEnabled else { return nil }
        guard policy.requireInfoPlistExecutableKey || policy.requireXcodeBuild else { return nil }
        guard policy.runVerificationOnlyOnTerminalTask else { return nil }
        let alreadyVerified = snapshot.tasks.contains { task in
            guard task.executionRecord?.status == .succeeded else { return false }
            let summary = task.executionRecord?.lastOutputSummary?.lowercased() ?? ""
            return summary.contains("real install verification passed")
        }
        if alreadyVerified {
            return DeferredRealArtifactVerificationOutcome(
                task: nil,
                status: "skipped",
                detail: "Real install verification already completed during task execution",
                boardMessage: nil,
                boardMessageSeverity: nil
            )
        }

        guard let candidate = candidateTaskForDeferredRealArtifactVerification(within: snapshot.tasks) else {
            return DeferredRealArtifactVerificationOutcome(
                task: nil,
                status: "skipped",
                detail: "No succeeded strict app task eligible for deferred verification",
                boardMessage: nil,
                boardMessageSeverity: nil
            )
        }

        let verification = runRealArtifactVerification(
            for: candidate,
            policy: policy,
            boardScopedProjectsPath: snapshot.boardScopedProjectsPath
        )
        if let failureReason = verification.failureReason {
            let userMessage = message("Real install verification failed: %@", failureReason)

            let detail = verification.debugLog.flatMap { debug in
                debug.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : userMessage + " | " + debug
            } ?? userMessage
            return DeferredRealArtifactVerificationOutcome(
                task: candidate,
                status: "failed",
                detail: detail,
                boardMessage: userMessage,
                boardMessageSeverity: .warning
            )
        }

        let successNote = verification.successNote?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return DeferredRealArtifactVerificationOutcome(
            task: candidate,
            status: "passed",
            detail: successNote.isEmpty ? "Real install verification passed" : successNote,
            boardMessage: successNote.isEmpty ? "Real install verification passed" : successNote,
            boardMessageSeverity: .info
        )
    }

    private func applyDeferredRealArtifactVerificationBoardMessage(
        _ outcome: DeferredRealArtifactVerificationOutcome?
    ) {
        guard let outcome,
              let boardMessage = outcome.boardMessage?.trimmingCharacters(in: .whitespacesAndNewlines),
              !boardMessage.isEmpty else {
            return
        }
        if let existing = lastBoardMessage, !existing.isEmpty {
            lastBoardMessage = existing + "\n" + boardMessage
        } else {
            lastBoardMessage = boardMessage
        }
        if let severity = outcome.boardMessageSeverity {
            if severity == .warning || lastBoardMessageSeverity != .warning {
                lastBoardMessageSeverity = severity
            }
        }
    }

    private func shouldEnableSystemRealArtifactVerificationBoardHook() -> Bool {
        let policy = executionRealArtifactVerificationPolicy
        return policy.isEnabled &&
            (policy.requireInfoPlistExecutableKey || policy.requireXcodeBuild) &&
            policy.runVerificationOnlyOnTerminalTask
    }

    private func hasEnabledSystemRealArtifactVerificationBoardHook() -> Bool {
        pmBoardExtensionHookBindings.contains { binding in
            binding.isEnabled &&
                binding.event == .boardRunFinished &&
                binding.pluginID.caseInsensitiveCompare(Self.systemExtensionPluginID) == .orderedSame &&
                binding.commandID.caseInsensitiveCompare(Self.systemRealArtifactVerifyCommandID) == .orderedSame
        }
    }

    @discardableResult
    private func syncSystemRealArtifactVerificationBoardHookBinding() -> Bool {
        let shouldEnable = shouldEnableSystemRealArtifactVerificationBoardHook()
        let existingIndex = pmBoardExtensionHookBindings.firstIndex { binding in
            binding.event == .boardRunFinished &&
                binding.pluginID.caseInsensitiveCompare(Self.systemExtensionPluginID) == .orderedSame &&
                binding.commandID.caseInsensitiveCompare(Self.systemRealArtifactVerifyCommandID) == .orderedSame
        }

        if let existingIndex {
            guard pmBoardExtensionHookBindings[existingIndex].isEnabled != shouldEnable else {
                return false
            }
            pmBoardExtensionHookBindings[existingIndex].isEnabled = shouldEnable
            pmBoardExtensionHookBindings = Self.normalizedBoardExtensionHookBindings(pmBoardExtensionHookBindings)
            return true
        }

        guard shouldEnable else { return false }
        pmBoardExtensionHookBindings.append(
            PMBoardExtensionHookBinding(
                event: .boardRunFinished,
                pluginID: Self.systemExtensionPluginID,
                commandID: Self.systemRealArtifactVerifyCommandID,
                isEnabled: true
            )
        )
        pmBoardExtensionHookBindings = Self.normalizedBoardExtensionHookBindings(pmBoardExtensionHookBindings)
        return true
    }

    private func emitBoardRunFinishedHook(
        flow: String,
        totalStarted: Int,
        completedPasses: Int,
        wasCancelled: Bool
    ) {
        guard Thread.isMainThread else {
            runOnMain { [weak self] in
                self?.emitBoardRunFinishedHook(
                    flow: flow,
                    totalStarted: totalStarted,
                    completedPasses: completedPasses,
                    wasCancelled: wasCancelled
                )
            }
            return
        }
        let shouldRunViaSystemHook = hasEnabledSystemRealArtifactVerificationBoardHook()
        let deferredVerification = shouldRunViaSystemHook ? nil : runDeferredRealArtifactVerificationIfNeeded()
        applyDeferredRealArtifactVerificationBoardMessage(deferredVerification)
        var inputs: [String: String] = [
            "flow": flow,
            "totalStarted": String(totalStarted),
            "completedPasses": String(completedPasses),
            "wasCancelled": wasCancelled ? "true" : "false"
        ]
        if let deferredVerification {
            inputs["realArtifactVerificationStatus"] = deferredVerification.status
            inputs["realArtifactVerificationDetail"] = deferredVerification.detail
        }
        let hookTask = deferredVerification?.task ?? candidateTaskForDeferredRealArtifactVerification()
        triggerPMExtensionHooks(
            event: .boardRunFinished,
            task: hookTask,
            additionalInputs: inputs
        )
    }

    private func runRealArtifactVerification(for task: WorkTask) -> RealArtifactVerificationResult {
        let context = readOnMain { [self] in
            (
                policy: self.executionRealArtifactVerificationPolicy,
                boardScopedProjectsPath: self.resolvedBoardScopedProjectsDirectoryPath()
            )
        }
        return runRealArtifactVerification(
            for: task,
            policy: context.policy,
            boardScopedProjectsPath: context.boardScopedProjectsPath
        )
    }

    private func runRealArtifactVerification(
        for _: WorkTask,
        policy: ExecutionRealArtifactVerificationPolicy,
        boardScopedProjectsPath: String
    ) -> RealArtifactVerificationResult {
        let boardScopedProjectsURL = URL(fileURLWithPath: boardScopedProjectsPath, isDirectory: true)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: boardScopedProjectsPath, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            return .failed(reason: "workspace folder not found (\(boardScopedProjectsPath))")
        }

        let containerResolution = resolveXcodeBuildContainer(in: boardScopedProjectsURL)
        guard let resolvedContainer = containerResolution.container else {
            return .failed(
                reason: containerResolution.failureReason ?? "no Xcode project or workspace found in \(boardScopedProjectsPath)",
                debugLog: containerResolution.debugLog
            )
        }

        var container = resolvedContainer
        var projectName = container.displayName
        var projectRootURL = container.url.deletingLastPathComponent()

        var checks: [String] = ["Real install verification passed"]
        checks.append("Project: \(projectName)")
        var repairAttempts = 0
        let maxRepairAttempts = policy.enableDeterministicRepairCycle ? 1 : 0

        while true {
            let integrityResult = runRealArtifactIntegrityChecks(
                for: container,
                projectName: projectName,
                projectRootURL: projectRootURL
            )
            checks.append(contentsOf: integrityResult.notes)
            guard let issue = integrityResult.issue else { break }

            guard repairAttempts < maxRepairAttempts else {
                return .failed(reason: issue.reason, debugLog: issue.debugLog)
            }

            let repair = attemptDeterministicRealArtifactRepair(
                for: issue,
                container: container,
                projectRootURL: projectRootURL
            )
            guard repair.didRepair else {
                return .failed(reason: issue.reason, debugLog: repair.debugLog ?? issue.debugLog)
            }
            repairAttempts += 1
            if let note = repair.note, !note.isEmpty {
                checks.append(note)
            }

            let refreshedResolution = resolveXcodeBuildContainer(in: boardScopedProjectsURL)
            guard let refreshedContainer = refreshedResolution.container else {
                return .failed(
                    reason: refreshedResolution.failureReason ?? "no Xcode project or workspace found in \(boardScopedProjectsPath)",
                    debugLog: refreshedResolution.debugLog
                )
            }
            container = refreshedContainer
            projectName = container.displayName
            projectRootURL = container.url.deletingLastPathComponent()
            checks.append("Re-verified project container after deterministic repair")
        }

        if policy.requireInfoPlistExecutableKey {
            let plistCandidates = discoverInfoPlistURLs(near: projectRootURL)
            guard !plistCandidates.isEmpty else {
                return .failed(reason: "no Info.plist found near \(projectName)")
            }

            let executableKeyFound = plistCandidates.contains { infoPlistContainsExecutableKey(at: $0) }
            guard executableKeyFound else {
                let listedCandidates = plistCandidates
                    .map(\.lastPathComponent)
                    .joined(separator: ", ")
                let details = listedCandidates.isEmpty
                    ? nil
                    : "Checked Info.plist files: \(listedCandidates)"
                return .failed(reason: "missing CFBundleExecutable in Info.plist", debugLog: details)
            }
            checks.append("Info.plist includes CFBundleExecutable")
        }

        if policy.requireXcodeBuild {
            let listCommand = "xcodebuild -list \(container.xcodebuildListArgument) \(Self.shellQuoted(container.url.path))"
            let listResult: (code: Int32, output: String, timedOut: Bool)
            do {
                listResult = try Self.runShellCommand(
                    listCommand,
                    timeoutSeconds: Self.realArtifactXcodeListTimeoutSeconds
                )
            } catch {
                return .failed(reason: "xcodebuild -list failed for \(projectName)", debugLog: String(describing: error))
            }
            if listResult.timedOut {
                let debugLog = DefaultAgentTaskExecutor.summarizeCommandOutputForConsole(
                    listResult.output,
                    maxLines: 32,
                    maxCharacters: 5000
                )
                return .failed(
                    reason: "xcodebuild -list timed out for \(projectName) after \(Self.realArtifactXcodeListTimeoutSeconds)s",
                    debugLog: debugLog.isEmpty ? nil : debugLog
                )
            }
            guard listResult.code == 0 else {
                return .failed(
                    reason: "xcodebuild -list failed for \(projectName)",
                    debugLog: DefaultAgentTaskExecutor.summarizeCommandOutputForConsole(
                        listResult.output,
                        maxLines: 32,
                        maxCharacters: 5000
                    )
                )
            }

            let schemes = parseXcodeSchemes(fromListOutput: listResult.output)
            guard let scheme = preferredBuildScheme(from: schemes) else {
                return .failed(reason: "no shared scheme found in \(projectName)")
            }

            let buildSettingsCommand = """
            xcodebuild \(container.xcodebuildListArgument) \(Self.shellQuoted(container.url.path)) -scheme \(Self.shellQuoted(scheme)) -showBuildSettings
            """
            let buildSettingsResult = try? Self.runShellCommand(
                buildSettingsCommand,
                timeoutSeconds: Self.realArtifactBuildSettingsTimeoutSeconds
            )
            let sdkRoot: String?
            if let buildSettingsResult,
               !buildSettingsResult.timedOut,
               buildSettingsResult.code == 0 {
                sdkRoot = Self.parseXcodeBuildSettingValue("SDKROOT", from: buildSettingsResult.output)
            } else {
                sdkRoot = nil
            }
            let overrides = Self.verificationBuildOverrides(forSDKRoot: sdkRoot)
            var buildCommand = "xcodebuild \(container.xcodebuildListArgument) \(Self.shellQuoted(container.url.path)) -scheme \(Self.shellQuoted(scheme)) -configuration Debug"
            if let sdk = overrides.sdk {
                buildCommand += " -sdk \(sdk)"
            }
            if let destination = overrides.destination {
                buildCommand += " -destination \(Self.shellQuoted(destination))"
            }
            buildCommand += " build CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO DEVELOPMENT_TEAM="
            let buildResult: (code: Int32, output: String, timedOut: Bool)
            do {
                buildResult = try Self.runShellCommand(
                    buildCommand,
                    timeoutSeconds: Self.realArtifactBuildTimeoutSeconds
                )
            } catch {
                return .failed(reason: "xcodebuild build failed for \(scheme)", debugLog: String(describing: error))
            }
            if buildResult.timedOut {
                let debugLog = DefaultAgentTaskExecutor.summarizeCommandOutputForConsole(
                    buildResult.output,
                    maxLines: 48,
                    maxCharacters: 7000
                )
                return .failed(
                    reason: "xcodebuild build timed out for \(scheme) after \(Self.realArtifactBuildTimeoutSeconds)s",
                    debugLog: debugLog.isEmpty ? nil : debugLog
                )
            }
            guard buildResult.code == 0 else {
                return .failed(
                    reason: "xcodebuild build failed for \(scheme)",
                    debugLog: DefaultAgentTaskExecutor.summarizeCommandOutputForConsole(
                        buildResult.output,
                        maxLines: 48,
                        maxCharacters: 7000
                    )
                )
            }
            checks.append("xcodebuild verification mode: \(overrides.modeLabel) (code signing bypass)")
            checks.append("xcodebuild succeeded (scheme: \(scheme))")
        }

        return .passed(note: checks.joined(separator: " · "))
    }

    private func runRealArtifactIntegrityChecks(
        for container: XcodeBuildContainer,
        projectName: String,
        projectRootURL: URL
    ) -> RealArtifactIntegrityCheckResult {
        let projectURLs = resolvedProjectURLsForIntegrityChecks(container: container, projectRootURL: projectRootURL)
        guard !projectURLs.isEmpty else {
            return RealArtifactIntegrityCheckResult(notes: [], issue: nil)
        }

        var totalCandidateBuildSettings = 0
        var missingContexts: [String] = []

        for projectURL in projectURLs {
            guard let content = loadPBXProjectContent(for: projectURL) else { continue }
            let snapshots = parsePBXBuildSettingsSnapshots(from: content)
            let candidateSnapshots = snapshots.filter(\.isCandidateAppBuildSettings)
            totalCandidateBuildSettings += candidateSnapshots.count
            let projectMissing = candidateSnapshots
                .filter { !$0.hasBundleIdentifier }
                .map { snapshot in
                    let descriptor = descriptorForBundleIdentifierRepair(from: snapshot)
                    return "\(projectURL.lastPathComponent): \(descriptor)"
                }
            missingContexts.append(contentsOf: projectMissing)
        }

        guard missingContexts.isEmpty else {
            let contextText = missingContexts.joined(separator: " | ")
            let reason = "missing PRODUCT_BUNDLE_IDENTIFIER in Xcode target build settings"
            let debugLog = """
            Integrity check failed for \(projectName).
            Missing contexts: \(contextText)
            Deterministic repair can add PRODUCT_BUNDLE_IDENTIFIER into candidate build settings blocks.
            """
            return RealArtifactIntegrityCheckResult(
                notes: [],
                issue: RealArtifactIntegrityIssue(
                    code: .missingBundleIdentifier,
                    reason: reason,
                    debugLog: debugLog
                )
            )
        }

        let note = totalCandidateBuildSettings > 0
            ? "Integrity check passed: PRODUCT_BUNDLE_IDENTIFIER present in \(totalCandidateBuildSettings) build setting block(s)"
            : "Integrity check skipped: no candidate app build settings found"
        return RealArtifactIntegrityCheckResult(notes: [note], issue: nil)
    }

    private func attemptDeterministicRealArtifactRepair(
        for issue: RealArtifactIntegrityIssue,
        container: XcodeBuildContainer,
        projectRootURL: URL
    ) -> RealArtifactRepairResult {
        switch issue.code {
        case .missingBundleIdentifier:
            let projectURLs = resolvedProjectURLsForIntegrityChecks(container: container, projectRootURL: projectRootURL)
            guard !projectURLs.isEmpty else {
                return RealArtifactRepairResult(
                    didRepair: false,
                    note: nil,
                    debugLog: issue.debugLog
                )
            }

            var repairedProjects: [String] = []
            var skippedProjects: [String] = []
            for projectURL in projectURLs {
                let repairResult = repairMissingBundleIdentifier(inXcodeProject: projectURL)
                if repairResult.modified {
                    repairedProjects.append(projectURL.lastPathComponent)
                } else {
                    skippedProjects.append(projectURL.lastPathComponent)
                }
            }

            guard !repairedProjects.isEmpty else {
                let detail = (issue.debugLog ?? "")
                    + (skippedProjects.isEmpty ? "" : "\nNo deterministic patch applied for: \(skippedProjects.joined(separator: ", "))")
                return RealArtifactRepairResult(
                    didRepair: false,
                    note: nil,
                    debugLog: detail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : detail
                )
            }

            let note = "Auto-repair applied: added PRODUCT_BUNDLE_IDENTIFIER in \(repairedProjects.joined(separator: ", "))"
            let debug = skippedProjects.isEmpty
                ? nil
                : "Skipped projects (already valid or not patchable): \(skippedProjects.joined(separator: ", "))"
            return RealArtifactRepairResult(didRepair: true, note: note, debugLog: debug)
        }
    }

    private func resolvedProjectURLsForIntegrityChecks(
        container: XcodeBuildContainer,
        projectRootURL: URL
    ) -> [URL] {
        switch container {
        case let .project(projectURL):
            return [projectURL]
        case .workspace:
            let discoveredProjects = discoverXcodeProjectURLs(in: projectRootURL)
            return discoveredProjects.isEmpty ? [] : discoveredProjects
        }
    }

    private func repairMissingBundleIdentifier(inXcodeProject projectURL: URL) -> (modified: Bool, debugLog: String?) {
        let projectFileURL = projectURL.appendingPathComponent("project.pbxproj")
        guard let content = loadPBXProjectContent(for: projectURL) else {
            return (false, "Unable to read \(projectFileURL.path)")
        }

        let rewrite = rewritePBXProjectWithMissingBundleIdentifiersFilled(content)
        guard rewrite.fixedCount > 0, rewrite.content != content else {
            return (false, rewrite.debugLog)
        }

        do {
            try rewrite.content.write(to: projectFileURL, atomically: true, encoding: .utf8)
            let debug = "Updated \(projectFileURL.lastPathComponent): inserted PRODUCT_BUNDLE_IDENTIFIER in \(rewrite.fixedCount) block(s)"
            return (true, debug)
        } catch {
            return (false, "Failed to write \(projectFileURL.path): \(error)")
        }
    }

    private func rewritePBXProjectWithMissingBundleIdentifiersFilled(_ content: String) -> (content: String, fixedCount: Int, debugLog: String?) {
        var lines = content.components(separatedBy: "\n")
        let defaultPrefix = inferredBundleIdentifierPrefix(fromPBXProjectContent: content) ?? "com.generated.app"
        var fixedCount = 0
        var index = 0

        while index < lines.count {
            guard lines[index].contains("buildSettings = {") else {
                index += 1
                continue
            }

            let startIndex = index
            var endIndex = index
            var balance = braceDelta(in: lines[index])
            while balance > 0, endIndex + 1 < lines.count {
                endIndex += 1
                balance += braceDelta(in: lines[endIndex])
            }

            guard balance == 0, endIndex >= startIndex else {
                index += 1
                continue
            }

            var blockLines = Array(lines[startIndex...endIndex])
            let snapshot = parsePBXBuildSettingsSnapshot(from: blockLines)
            guard snapshot.isCandidateAppBuildSettings else {
                index = endIndex + 1
                continue
            }
            guard !snapshot.hasBundleIdentifier else {
                index = endIndex + 1
                continue
            }

            let insertionIndent = snapshot.indentByKey["PRODUCT_NAME"]
                ?? snapshot.indentByKey["INFOPLIST_FILE"]
                ?? snapshot.indentByKey["SDKROOT"]
                ?? "\t\t\t\t"
            let bundleIdentifier = synthesizedBundleIdentifier(
                from: snapshot,
                defaultPrefix: defaultPrefix
            )
            let replacementLine = "\(insertionIndent)PRODUCT_BUNDLE_IDENTIFIER = \(bundleIdentifier);"

            if let existingLineIndex = snapshot.lineIndexByKey["PRODUCT_BUNDLE_IDENTIFIER"] {
                blockLines[existingLineIndex] = replacementLine
            } else {
                blockLines.insert(replacementLine, at: max(1, blockLines.count - 1))
            }

            lines.replaceSubrange(startIndex...endIndex, with: blockLines)
            fixedCount += 1
            index = startIndex + blockLines.count
        }

        let updatedContent = lines.joined(separator: "\n")
        let debugLog: String?
        if fixedCount > 0 {
            debugLog = "Deterministic repair synthesized PRODUCT_BUNDLE_IDENTIFIER with prefix \(defaultPrefix)"
        } else {
            debugLog = "No candidate buildSettings block required PRODUCT_BUNDLE_IDENTIFIER repair"
        }
        return (updatedContent, fixedCount, debugLog)
    }

    private func parsePBXBuildSettingsSnapshots(from content: String) -> [PBXBuildSettingsSnapshot] {
        let lines = content.components(separatedBy: "\n")
        var snapshots: [PBXBuildSettingsSnapshot] = []
        var index = 0

        while index < lines.count {
            guard lines[index].contains("buildSettings = {") else {
                index += 1
                continue
            }

            let startIndex = index
            var endIndex = index
            var balance = braceDelta(in: lines[index])
            while balance > 0, endIndex + 1 < lines.count {
                endIndex += 1
                balance += braceDelta(in: lines[endIndex])
            }
            guard balance == 0, endIndex >= startIndex else {
                index += 1
                continue
            }

            let blockLines = Array(lines[startIndex...endIndex])
            snapshots.append(parsePBXBuildSettingsSnapshot(from: blockLines))
            index = endIndex + 1
        }

        return snapshots
    }

    private func parsePBXBuildSettingsSnapshot(from blockLines: [String]) -> PBXBuildSettingsSnapshot {
        var values: [String: String] = [:]
        var lineIndexByKey: [String: Int] = [:]
        var indentByKey: [String: String] = [:]

        for (lineIndex, line) in blockLines.enumerated() {
            guard let parsed = parsePBXBuildSetting(from: line) else { continue }
            values[parsed.key] = parsed.value
            lineIndexByKey[parsed.key] = lineIndex
            indentByKey[parsed.key] = parsed.indent
        }

        return PBXBuildSettingsSnapshot(
            hasInfoPlist: values["INFOPLIST_FILE"] != nil,
            sdkRoot: values["SDKROOT"],
            productName: values["PRODUCT_NAME"],
            bundleIdentifierPrefix: values["PRODUCT_BUNDLE_IDENTIFIER_PREFIX"],
            bundleIdentifier: values["PRODUCT_BUNDLE_IDENTIFIER"],
            lineIndexByKey: lineIndexByKey,
            indentByKey: indentByKey
        )
    }

    private func parsePBXBuildSetting(from line: String) -> (key: String, value: String, indent: String)? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.contains(" = "), trimmed.hasSuffix(";") else { return nil }
        let components = trimmed.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
        guard components.count == 2 else { return nil }
        let rawKey = String(components[0]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawKey.isEmpty else { return nil }
        let rawValue = String(components[1])
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .dropLast()
        let value = String(rawValue).trimmingCharacters(in: .whitespacesAndNewlines)
        let indent = String(line.prefix { $0 == "\t" || $0 == " " })
        return (rawKey, value, indent)
    }

    private func descriptorForBundleIdentifierRepair(from snapshot: PBXBuildSettingsSnapshot) -> String {
        let product = normalizedPBXBuildSettingValue(snapshot.productName) ?? "unknown-product"
        let sdk = normalizedPBXBuildSettingValue(snapshot.sdkRoot) ?? "unknown-sdk"
        return "product=\(product), sdk=\(sdk)"
    }

    private func synthesizedBundleIdentifier(
        from snapshot: PBXBuildSettingsSnapshot,
        defaultPrefix: String
    ) -> String {
        let prefix = normalizedBundleIdentifierPrefix(snapshot.bundleIdentifierPrefix) ?? defaultPrefix
        let product = sanitizedBundleIdentifierComponent(
            normalizedPBXBuildSettingValue(snapshot.productName) ?? ""
        )
        let platformSuffix = platformSuffixForSDKRoot(snapshot.sdkRoot)

        var components: [String] = [prefix]
        if !product.isEmpty, product != "target-name" {
            components.append(product)
        }
        components.append(platformSuffix)
        return components.joined(separator: ".")
    }

    private func normalizedBundleIdentifierPrefix(_ rawPrefix: String?) -> String? {
        guard var prefix = normalizedPBXBuildSettingValue(rawPrefix), !prefix.isEmpty else {
            return nil
        }
        if prefix.contains("$(") {
            return nil
        }
        prefix = prefix.trimmingCharacters(in: CharacterSet(charactersIn: "."))
        return prefix.isEmpty ? nil : prefix
    }

    private func normalizedPBXBuildSettingValue(_ value: String?) -> String? {
        guard var value else { return nil }
        value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("\""), value.hasSuffix("\""), value.count >= 2 {
            value.removeFirst()
            value.removeLast()
        }
        value = value.replacingOccurrences(of: "$(", with: "")
        value = value.replacingOccurrences(of: ")", with: "")
        value = value.replacingOccurrences(of: "\"", with: "")
        value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private func sanitizedBundleIdentifierComponent(_ value: String) -> String {
        let lowercased = value.lowercased()
        var component = ""
        var previousWasSeparator = false
        for character in lowercased {
            if character.isLetter || character.isNumber {
                component.append(character)
                previousWasSeparator = false
            } else if !previousWasSeparator {
                component.append("-")
                previousWasSeparator = true
            }
        }
        return component.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }

    private func platformSuffixForSDKRoot(_ sdkRoot: String?) -> String {
        guard let sdkRoot = normalizedPBXBuildSettingValue(sdkRoot)?.lowercased() else {
            return "app"
        }
        if sdkRoot.contains("iphoneos") { return "ios" }
        if sdkRoot.contains("macosx") { return "macos" }
        if sdkRoot.contains("appletvos") { return "tvos" }
        if sdkRoot.contains("watchos") { return "watchos" }
        if sdkRoot.contains("xros") { return "visionos" }
        return "app"
    }

    private func inferredBundleIdentifierPrefix(fromPBXProjectContent content: String) -> String? {
        for line in content.split(whereSeparator: \.isNewline) {
            guard let parsed = parsePBXBuildSetting(from: String(line)),
                  parsed.key == "PRODUCT_BUNDLE_IDENTIFIER_PREFIX",
                  let normalized = normalizedBundleIdentifierPrefix(parsed.value) else {
                continue
            }
            return normalized
        }
        return nil
    }

    private func loadPBXProjectContent(for projectURL: URL) -> String? {
        let projectFileURL = projectURL.appendingPathComponent("project.pbxproj")
        return try? String(contentsOf: projectFileURL, encoding: .utf8)
    }

    private func braceDelta(in line: String) -> Int {
        var delta = 0
        for character in line {
            if character == "{" {
                delta += 1
            } else if character == "}" {
                delta -= 1
            }
        }
        return delta
    }

    private func resolvedBoardScopedProjectsDirectoryPath() -> String {
        let baseProjectsDirectoryPath = projectsDirectoryPathProvider()
        return CodexProjectsDirectorySettings.boardScopedProjectsDirectoryPath(
            baseDirectoryPath: baseProjectsDirectoryPath,
            boardName: selectedBoardName
        )
    }

    private func resolveXcodeBuildContainer(in rootURL: URL) -> (container: XcodeBuildContainer?, failureReason: String?, debugLog: String?) {
        let projects = discoverXcodeProjectURLs(in: rootURL)
        if let firstProject = projects.first {
            return (.project(firstProject), nil, nil)
        }

        let workspaces = discoverXcodeWorkspaceURLs(in: rootURL)
        if let firstWorkspace = workspaces.first {
            return (.workspace(firstWorkspace), nil, nil)
        }

        if let manifestURL = discoverXcodeGenManifestURLs(in: rootURL).first {
            let generation = attemptGenerateXcodeProject(withXcodeGenAt: manifestURL)
            if let generatedContainer = generation.container {
                return (generatedContainer, nil, nil)
            }
            return (
                nil,
                generation.failureReason ?? "failed to generate Xcode project from project.yml",
                generation.debugLog
            )
        }

        if hasSwiftPackageManifest(in: rootURL) {
            return (
                nil,
                "detected Package.swift but no .xcodeproj/.xcworkspace. Strict app install verification requires an Xcode project/workspace",
                "Convert/generate an Xcode project (for example via xcodegen) before strict install verification."
            )
        }

        return (nil, "no Xcode project (.xcodeproj/.xcworkspace) found in \(rootURL.path)", nil)
    }

    private func attemptGenerateXcodeProject(withXcodeGenAt manifestURL: URL) -> (container: XcodeBuildContainer?, failureReason: String?, debugLog: String?) {
        let workingDirectory = manifestURL.deletingLastPathComponent().path
        let generateCommand = "cd \(Self.shellQuoted(workingDirectory)) && xcodegen generate"
        let result: (code: Int32, output: String)
        do {
            result = try Self.runShellCommand(generateCommand)
        } catch {
            return (
                nil,
                "failed to run xcodegen generate for \(manifestURL.lastPathComponent)",
                String(describing: error)
            )
        }

        guard result.code == 0 else {
            let lowered = result.output.lowercased()
            if lowered.contains("command not found: xcodegen") {
                return (
                    nil,
                    "project.yml detected but xcodegen is not installed",
                    "Install xcodegen and retry. Command: brew install xcodegen"
                )
            }
            return (
                nil,
                "xcodegen generate failed for \(manifestURL.lastPathComponent)",
                DefaultAgentTaskExecutor.summarizeCommandOutputForConsole(
                    result.output,
                    maxLines: 32,
                    maxCharacters: 5000
                )
            )
        }

        let generatedProjects = discoverXcodeProjectURLs(in: manifestURL.deletingLastPathComponent())
        if let generatedProject = generatedProjects.first {
            return (.project(generatedProject), nil, nil)
        }

        let generatedWorkspaces = discoverXcodeWorkspaceURLs(in: manifestURL.deletingLastPathComponent())
        if let generatedWorkspace = generatedWorkspaces.first {
            return (.workspace(generatedWorkspace), nil, nil)
        }

        return (
            nil,
            "xcodegen completed but no .xcodeproj/.xcworkspace was generated",
            DefaultAgentTaskExecutor.summarizeCommandOutputForConsole(
                result.output,
                maxLines: 24,
                maxCharacters: 4000
            )
        )
    }

    private func discoverXcodeProjectURLs(in rootURL: URL) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var projectURLs: [URL] = []
        for case let fileURL as URL in enumerator {
            guard fileURL.pathExtension.lowercased() == "xcodeproj" else { continue }
            projectURLs.append(fileURL)
        }
        return projectURLs.sorted { lhs, rhs in
            lhs.path.localizedCaseInsensitiveCompare(rhs.path) == .orderedAscending
        }
    }

    private func discoverXcodeWorkspaceURLs(in rootURL: URL) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var workspaceURLs: [URL] = []
        for case let fileURL as URL in enumerator {
            guard fileURL.pathExtension.lowercased() == "xcworkspace" else { continue }
            workspaceURLs.append(fileURL)
        }
        return workspaceURLs.sorted { lhs, rhs in
            lhs.path.localizedCaseInsensitiveCompare(rhs.path) == .orderedAscending
        }
    }

    private func discoverXcodeGenManifestURLs(in rootURL: URL) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var manifestURLs: [URL] = []
        for case let fileURL as URL in enumerator {
            let lowercasedName = fileURL.lastPathComponent.lowercased()
            guard lowercasedName == "project.yml" || lowercasedName == "project.yaml" else { continue }
            manifestURLs.append(fileURL)
        }

        return manifestURLs.sorted { lhs, rhs in
            lhs.path.localizedCaseInsensitiveCompare(rhs.path) == .orderedAscending
        }
    }

    private func hasSwiftPackageManifest(in rootURL: URL) -> Bool {
        guard let enumerator = FileManager.default.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return false
        }

        for case let fileURL as URL in enumerator {
            if fileURL.lastPathComponent == "Package.swift" {
                return true
            }
        }
        return false
    }

    private func discoverInfoPlistURLs(near projectRootURL: URL) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: projectRootURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var plistURLs: [URL] = []
        for case let fileURL as URL in enumerator {
            let fileName = fileURL.lastPathComponent.lowercased()
            guard fileName.hasSuffix("info.plist") else { continue }

            let normalizedPath = fileURL.path.lowercased()
            if normalizedPath.contains("/.build/") ||
                normalizedPath.contains("/deriveddata/") ||
                normalizedPath.contains("/sourcepackages/") ||
                normalizedPath.contains("/checkouts/") {
                continue
            }
            plistURLs.append(fileURL)
        }

        return plistURLs.sorted { lhs, rhs in
            lhs.path.localizedCaseInsensitiveCompare(rhs.path) == .orderedAscending
        }
    }

    private func infoPlistContainsExecutableKey(at plistURL: URL) -> Bool {
        guard let plistData = try? Data(contentsOf: plistURL),
              let rawValue = try? PropertyListSerialization.propertyList(from: plistData, options: [], format: nil),
              let dictionary = rawValue as? [String: Any],
              let executableValue = dictionary["CFBundleExecutable"] else {
            return false
        }
        if let executableString = executableValue as? String {
            return !executableString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return true
    }

    private func parseXcodeSchemes(fromListOutput output: String) -> [String] {
        let lines = output
            .split(whereSeparator: \.isNewline)
            .map(String.init)
        var collectingSchemes = false
        var schemes: [String] = []

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed == "Schemes:" {
                collectingSchemes = true
                continue
            }

            guard collectingSchemes else { continue }
            if trimmed.isEmpty {
                if !schemes.isEmpty {
                    break
                }
                continue
            }

            let hasIndentation = line.first?.isWhitespace ?? false
            if !hasIndentation {
                if !schemes.isEmpty {
                    break
                }
                continue
            }
            schemes.append(trimmed)
        }

        var seen = Set<String>()
        return schemes.filter { seen.insert($0).inserted }
    }

    private func preferredBuildScheme(from schemes: [String]) -> String? {
        if let nonTestScheme = schemes.first(where: { !$0.lowercased().contains("test") }) {
            return nonTestScheme
        }
        return schemes.first
    }

    private func executeTaskWithBoardScopedProjectsDirectory(
        task: WorkTask,
        agent: AgentProfile,
        onProgress: @escaping (_ update: String) -> Void
    ) -> AgentTaskExecutionOutcome {
        guard var defaultExecutor = taskExecutor as? DefaultAgentTaskExecutor else {
            return taskExecutor.execute(task: task, agent: agent, onProgress: onProgress)
        }

        let upstreamEnvironmentProvider = defaultExecutor.environmentProvider
        let boardName = selectedBoardName
        let baselineEnvironment = upstreamEnvironmentProvider()
        let resolvedWorkingDirectory = resolvedExecutionWorkingDirectoryPath(
            task: task,
            agent: agent,
            boardName: boardName,
            environment: baselineEnvironment,
            onProgress: onProgress
        )
        defaultExecutor.environmentProvider = {
            var environment = upstreamEnvironmentProvider()
            environment[CodexProjectsDirectorySettings.environmentOverrideKey] = resolvedWorkingDirectory
            return environment
        }

        return defaultExecutor.execute(task: task, agent: agent, onProgress: onProgress)
    }

    private func resolvedExecutionWorkingDirectoryPath(
        task: WorkTask,
        agent: AgentProfile,
        boardName: String,
        environment: [String: String],
        onProgress: @escaping (_ update: String) -> Void
    ) -> String {
        let baseProjectsDirectoryPath = CodexProjectsDirectorySettings.resolvedProjectsDirectoryPath(
            environment: environment
        )
        let boardScopedPath = CodexProjectsDirectorySettings.boardScopedProjectsDirectoryPath(
            baseDirectoryPath: baseProjectsDirectoryPath,
            boardName: boardName
        )

        guard WorktreeExecutionSettings.isEnabled() else {
            return boardScopedPath
        }

        let repositoryPath = WorktreeExecutionSettings.resolvedRepositoryPath()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !repositoryPath.isEmpty else {
            onProgress("Worktree enabled but repository path is empty. Falling back to board workspace.")
            return boardScopedPath
        }

        let branchPrefix = WorktreeExecutionSettings.resolvedBranchPrefix()
        do {
            let worktreePath = try Self.prepareWorktreeDirectoryForExecution(
                task: task,
                agent: agent,
                boardName: boardName,
                repositoryPath: repositoryPath,
                boardScopedPath: boardScopedPath,
                branchPrefix: branchPrefix,
                environment: environment
            )
            onProgress("Worktree ready: \(worktreePath)")
            return worktreePath
        } catch {
            onProgress("Worktree setup failed (\(error.localizedDescription)). Falling back to board workspace.")
            return boardScopedPath
        }
    }

    private static func prepareWorktreeDirectoryForExecution(
        task: WorkTask,
        agent: AgentProfile,
        boardName: String,
        repositoryPath: String,
        boardScopedPath: String,
        branchPrefix: String,
        environment: [String: String]
    ) throws -> String {
        let expandedRepositoryPath = (repositoryPath as NSString).expandingTildeInPath
        let fileManager = FileManager.default
        let repositoryURL = URL(fileURLWithPath: expandedRepositoryPath, isDirectory: true)
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: repositoryURL.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw NSError(
                domain: "OpenMac.Worktree",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Repository path does not exist"]
            )
        }

        let repositoryCheck = try runShellCommand(
            "git -C \(shellQuoted(repositoryURL.path)) rev-parse --is-inside-work-tree",
            environment: environment
        )
        guard repositoryCheck.code == 0 else {
            throw NSError(
                domain: "OpenMac.Worktree",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Repository path is not a git repository"]
            )
        }

        let worktreesRootURL = URL(fileURLWithPath: boardScopedPath, isDirectory: true)
            .appendingPathComponent(".worktrees", isDirectory: true)
        try fileManager.createDirectory(at: worktreesRootURL, withIntermediateDirectories: true)

        let boardSlug = worktreeSlug(boardName, fallback: "board")
        let agentSlug = worktreeSlug(agent.name, fallback: "agent")
        let taskSlug = worktreeSlug(task.title, fallback: "task")
        let taskIDPrefix = String(task.id.uuidString.lowercased().prefix(8))
        let worktreeDirectoryName = "\(boardSlug)-\(agentSlug)-\(taskSlug)-\(taskIDPrefix)"
        let worktreeURL = worktreesRootURL.appendingPathComponent(worktreeDirectoryName, isDirectory: true)
        let worktreePath = worktreeURL.path
        let worktreeGitMarker = worktreeURL.appendingPathComponent(".git", isDirectory: false).path
        if fileManager.fileExists(atPath: worktreeGitMarker) {
            return worktreePath
        }

        let resolvedBranchPrefix = branchPrefix.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "openmac"
            : branchPrefix
        let branchName = "\(resolvedBranchPrefix)/\(boardSlug)/\(agentSlug)-\(taskIDPrefix)"
        let createBranchCommand =
            "git -C \(shellQuoted(repositoryURL.path)) worktree add -b \(shellQuoted(branchName)) \(shellQuoted(worktreePath))"
        let createBranchResult = try runShellCommand(createBranchCommand, environment: environment)
        if createBranchResult.code == 0 {
            return worktreePath
        }

        let attachExistingCommand =
            "git -C \(shellQuoted(repositoryURL.path)) worktree add \(shellQuoted(worktreePath)) \(shellQuoted(branchName))"
        let attachExistingResult = try runShellCommand(attachExistingCommand, environment: environment)
        if attachExistingResult.code == 0 {
            return worktreePath
        }

        let debugOutput = [
            mergedShellOutput(stdout: createBranchResult.output, stderr: ""),
            mergedShellOutput(stdout: attachExistingResult.output, stderr: "")
        ]
        .joined(separator: "\n")
        .trimmingCharacters(in: .whitespacesAndNewlines)
        let detail = debugOutput.isEmpty ? "git worktree add failed" : debugOutput
        throw NSError(
            domain: "OpenMac.Worktree",
            code: 3,
            userInfo: [NSLocalizedDescriptionKey: detail]
        )
    }

    private static func worktreeSlug(_ rawValue: String, fallback: String) -> String {
        let lowered = rawValue
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let slug = lowered
            .map { character -> Character in
                if character.isLetter || character.isNumber {
                    return character
                }
                return "-"
            }
        let collapsed = String(slug)
            .replacingOccurrences(of: "-+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        let resolved = collapsed.isEmpty ? fallback : collapsed
        return String(resolved.prefix(32))
    }

    private func applyRetryRunCount(for taskID: UUID, additionalAttempts: Int) {
        guard additionalAttempts > 0,
              let taskIndex = tasks.firstIndex(where: { $0.id == taskID }),
              var record = tasks[taskIndex].executionRecord else {
            return
        }
        record.runCount = max(0, record.runCount) + additionalAttempts
        tasks[taskIndex].executionRecord = record
    }

    private func updateExecutionCheckpoint(_ checkpoint: ExecutionCheckpoint?) {
        executionCheckpoint = checkpoint
        persistBoardState()
    }

    @discardableResult
    private func performTaskExecution(_ taskID: UUID, requiresTaskDetails: Bool) -> Bool {
        ExecutionCoordinator.runTaskExecution(
            taskID: taskID,
            requiresTaskDetails: requiresTaskDetails,
            prepareTaskExecution: { taskID, requiresTaskDetails in
                self.prepareTaskExecution(taskID, requiresTaskDetails: requiresTaskDetails)
            },
            executeWithAutoRetry: { task, agent, onProgress in
                self.executeWithAutoRetry(task: task, agent: agent, onProgress: onProgress)
            },
            captureExecutionProgress: { update, prepared in
                self.captureExecutionProgress(update, for: prepared)
            },
            applyRetryRunCount: { taskID, additionalAttempts in
                self.applyRetryRunCount(for: taskID, additionalAttempts: additionalAttempts)
            },
            finalizeTaskExecution: { prepared, outcome in
                self.finalizeTaskExecution(prepared, outcome: outcome)
            }
        )
    }

    private func performTaskExecutionInBackground(
        _ taskID: UUID,
        requiresTaskDetails: Bool,
        completion: @escaping (Bool) -> Void
    ) {
        ExecutionCoordinator.runTaskExecutionInBackground(
            taskID: taskID,
            requiresTaskDetails: requiresTaskDetails,
            prepareTaskExecution: { taskID, requiresTaskDetails in
                self.prepareTaskExecution(taskID, requiresTaskDetails: requiresTaskDetails)
            },
            executeWithAutoRetry: { task, agent, onProgress in
                self.executeWithAutoRetry(task: task, agent: agent, onProgress: onProgress)
            },
            runOnBackground: runOnBackground,
            runOnMain: runOnMain,
            captureExecutionProgress: { update, prepared in
                self.captureExecutionProgress(update, for: prepared)
            },
            applyRetryRunCount: { taskID, additionalAttempts in
                self.applyRetryRunCount(for: taskID, additionalAttempts: additionalAttempts)
            },
            finalizeTaskExecution: { prepared, outcome in
                self.finalizeTaskExecution(prepared, outcome: outcome)
            },
            completion: completion
        )
    }

    @discardableResult
    func runTaskExecution(_ taskID: UUID) -> Bool {
        performTaskExecution(taskID, requiresTaskDetails: true)
    }

    func runTaskExecutionInBackground(_ taskID: UUID, completion: @escaping (Bool) -> Void) {
        performTaskExecutionInBackground(taskID, requiresTaskDetails: true, completion: completion)
    }

    @discardableResult
    func retryTaskExecution(_ taskID: UUID) -> Bool {
        ExecutionCoordinator.retryTaskExecution(
            taskID: taskID,
            canRetryTask: { taskID in
                self.executionRecord(for: taskID)?.status == .failed
            },
            onRetryRejected: {
                self.lastBoardMessage = self.message("Only failed executions can be retried")
                self.lastBoardMessageSeverity = .warning
            },
            runTaskExecution: { taskID, requiresTaskDetails in
                self.performTaskExecution(taskID, requiresTaskDetails: requiresTaskDetails)
            }
        )
    }

    func retryTaskExecutionInBackground(_ taskID: UUID, completion: @escaping (Bool) -> Void) {
        ExecutionCoordinator.retryTaskExecutionInBackground(
            taskID: taskID,
            canRetryTask: { taskID in
                self.executionRecord(for: taskID)?.status == .failed
            },
            onRetryRejected: {
                self.lastBoardMessage = self.message("Only failed executions can be retried")
                self.lastBoardMessageSeverity = .warning
            },
            runTaskExecutionInBackground: { taskID, requiresTaskDetails, completion in
                self.performTaskExecutionInBackground(
                    taskID,
                    requiresTaskDetails: requiresTaskDetails,
                    completion: completion
                )
            },
            completion: completion
        )
    }

    private struct DependencyReference {
        let normalizedTitle: String
        let displayTitle: String
    }

    private struct MissingDependencyDescriptor {
        let reference: DependencyReference
        let dependentTaskTitles: [String]
        let inferredSkills: [String]
    }

    private struct HealthAutoFixSnapshot: Equatable {
        let tasks: [WorkTask]
        let agents: [AgentProfile]
        let wipLimits: [KanbanStatus: Int]
        let unassignedTaskIDs: Set<UUID>
        let assignmentReasons: [UUID: String]
    }

    private static func normalizedDependencyTitle(_ raw: String) -> String {
        raw
            .trimmingCharacters(
                in: CharacterSet.whitespacesAndNewlines.union(
                    CharacterSet(charactersIn: "\"'`•-")
                )
            )
            .lowercased()
    }

    private static func dependencyTitles(from details: String) -> [String] {
        parsedDependencyReferences(from: details).map(\.normalizedTitle)
    }

    private static func parsedDependencyReferences(from details: String) -> [DependencyReference] {
        let lines = details
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var dependencies: [DependencyReference] = []
        for line in lines {
            guard let separatorIndex = line.firstIndex(where: { $0 == ":" || $0 == "：" }) else {
                continue
            }

            let prefix = line[..<separatorIndex]
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            let matchesPrefix =
                prefix == "depends on" ||
                prefix == "dependency" ||
                prefix == "dependencies" ||
                prefix == "依賴" ||
                prefix == "依赖"
            guard matchesPrefix else { continue }

            let payload = line[line.index(after: separatorIndex)...]
            let parsed = payload
                .split(separator: ",")
                .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                .map { rawDependency in
                    let normalized = normalizedDependencyTitle(rawDependency)
                    return DependencyReference(
                        normalizedTitle: normalized,
                        displayTitle: rawDependency.trimmingCharacters(
                            in: CharacterSet.whitespacesAndNewlines.union(
                                CharacterSet(charactersIn: "\"'`•-")
                            )
                        )
                    )
                }
                .filter {
                    !$0.normalizedTitle.isEmpty &&
                        $0.normalizedTitle != "none" &&
                        $0.normalizedTitle != "無" &&
                        $0.normalizedTitle != "无"
                }

            dependencies.append(contentsOf: parsed)
        }

        var uniqueByNormalized: [String: String] = [:]
        for dependency in dependencies where uniqueByNormalized[dependency.normalizedTitle] == nil {
            uniqueByNormalized[dependency.normalizedTitle] = dependency.displayTitle
        }
        return uniqueByNormalized.keys.sorted().compactMap { normalizedTitle in
            guard let displayTitle = uniqueByNormalized[normalizedTitle] else { return nil }
            return DependencyReference(normalizedTitle: normalizedTitle, displayTitle: displayTitle)
        }
    }

    private static func acceptanceCriteriaLines(from details: String) -> [String] {
        let lines = details
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

        var started = false
        var criteria: [String] = []
        for line in lines {
            guard !line.isEmpty else {
                if started, !criteria.isEmpty {
                    break
                }
                continue
            }

            let normalized = line.lowercased()
            if !started {
                let isAcceptanceHeader =
                    normalized.hasPrefix("acceptance criteria") ||
                    normalized.hasPrefix("acceptance:") ||
                    normalized.hasPrefix("acceptance criteria:") ||
                    normalized.hasPrefix("驗收標準") ||
                    normalized.hasPrefix("验收标准")
                if isAcceptanceHeader {
                    started = true
                }
                continue
            }

            if normalized.hasPrefix("depends on:") ||
                normalized.hasPrefix("milestone:") ||
                normalized.hasPrefix("epic:") {
                break
            }

            let bulletPrefixes = ["- ", "• ", "* "]
            if let bulletPrefix = bulletPrefixes.first(where: { line.hasPrefix($0) }) {
                let trimmed = line.dropFirst(bulletPrefix.count).trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    criteria.append(trimmed)
                }
                continue
            }

            if line.hasPrefix("-") || line.hasPrefix("•") || line.hasPrefix("*") {
                let trimmed = line.dropFirst().trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    criteria.append(trimmed)
                }
                continue
            }

            if !criteria.isEmpty {
                break
            }
            criteria.append(line)
        }

        var uniqueCriteria: [String] = []
        var seen = Set<String>()
        for criterion in criteria {
            let normalized = criterion.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalized.isEmpty else { continue }
            let lowercased = normalized.lowercased()
            guard !seen.contains(lowercased) else { continue }
            seen.insert(lowercased)
            uniqueCriteria.append(normalized)
        }
        return uniqueCriteria
    }

    private static func acceptanceE2EDetails(
        sourceTitle: String,
        acceptanceCriteria: [String]
    ) -> String {
        var lines: [String] = []
        lines.append("Validate end-to-end acceptance outcomes for \"\(sourceTitle)\".")
        lines.append("Depends on: \(sourceTitle)")
        lines.append("Acceptance Criteria:")
        lines.append(contentsOf: acceptanceCriteria.map { "- \($0)" })
        lines.append("")
        lines.append("Test Focus:")
        lines.append("- Cover happy-path and critical edge-path behavior.")
        lines.append("- Report pass/fail evidence for each acceptance line.")
        return lines.joined(separator: "\n")
    }

    private static func isDependencyCompleted(_ task: WorkTask) -> Bool {
        task.status == .review || task.status == .done
    }

    private func dependencyCompletionMap() -> [String: Bool] {
        tasks.reduce(into: [String: Bool]()) { partialResult, task in
            let normalizedTitle = Self.normalizedDependencyTitle(task.title)
            guard !normalizedTitle.isEmpty else { return }
            let existing = partialResult[normalizedTitle] ?? false
            partialResult[normalizedTitle] = existing || Self.isDependencyCompleted(task)
        }
    }

    func unresolvedDependencies(for taskID: UUID) -> [String] {
        guard let task = tasks.first(where: { $0.id == taskID }) else { return [] }
        let dependencies = Self.parsedDependencyReferences(from: task.details)
        guard !dependencies.isEmpty else { return [] }
        let completionByTitle = dependencyCompletionMap()

        return dependencies
            .filter { dependency in
                guard let isCompleted = completionByTitle[dependency.normalizedTitle] else {
                    return true
                }
                return !isCompleted
            }
            .map(\.displayTitle)
    }

    private func missingDependencyReferences() -> [DependencyReference] {
        missingDependencyDescriptors().map(\.reference)
    }

    private func missingDependencyDescriptors() -> [MissingDependencyDescriptor] {
        let existingDependencyTitles = Set(
            tasks.compactMap { task in
                let normalized = Self.normalizedDependencyTitle(task.title)
                return normalized.isEmpty ? nil : normalized
            }
        )

        var descriptorsByNormalizedTitle: [String: (
            displayTitle: String, dependentTaskTitles: Set<String>, inferredSkills: Set<String>
        )] = [:]

        for task in tasks where task.status == .todo || task.status == .inProgress {
            let dependencies = Self.parsedDependencyReferences(from: task.details)
            let normalizedTaskTitle = task.title.trimmingCharacters(in: .whitespacesAndNewlines)
            for dependency in dependencies {
                guard !existingDependencyTitles.contains(dependency.normalizedTitle) else { continue }
                var descriptor = descriptorsByNormalizedTitle[dependency.normalizedTitle] ?? (
                    displayTitle: dependency.displayTitle,
                    dependentTaskTitles: [],
                    inferredSkills: []
                )
                if descriptor.displayTitle.isEmpty {
                    descriptor.displayTitle = dependency.displayTitle
                }
                if !normalizedTaskTitle.isEmpty {
                    descriptor.dependentTaskTitles.insert(normalizedTaskTitle)
                }
                descriptor.inferredSkills.formUnion(task.requiredSkills)
                descriptorsByNormalizedTitle[dependency.normalizedTitle] = descriptor
            }
        }

        return descriptorsByNormalizedTitle.keys.sorted().compactMap { normalizedTitle in
            guard let descriptor = descriptorsByNormalizedTitle[normalizedTitle] else {
                return nil
            }
            let dependentTaskTitles = descriptor.dependentTaskTitles.sorted {
                $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
            }
            let inferredSkills = descriptor.inferredSkills.sorted()
            return MissingDependencyDescriptor(
                reference: DependencyReference(
                    normalizedTitle: normalizedTitle,
                    displayTitle: descriptor.displayTitle
                ),
                dependentTaskTitles: dependentTaskTitles,
                inferredSkills: inferredSkills
            )
        }
    }

    func dependencyBlockReason(for taskID: UUID) -> String? {
        let unresolved = unresolvedDependencies(for: taskID)
        guard !unresolved.isEmpty else { return nil }
        return message("Blocked by dependencies: %@", unresolved.joined(separator: ", "))
    }

    private func prepareAssignedBatchRunQueue(excluding attemptedTaskIDs: Set<UUID> = []) -> AssignedBatchRunPreparation {
        let assignedQueue = tasks
            .filter { task in
                (task.status == .todo || task.status == .inProgress) &&
                    task.assignedAgentID != nil &&
                    task.executionRecord?.status != .failed &&
                    !attemptedTaskIDs.contains(task.id)
            }
            .sorted { lhs, rhs in
                if lhs.storyPoints != rhs.storyPoints {
                    return lhs.storyPoints > rhs.storyPoints
                }
                return lhs.createdAt < rhs.createdAt
            }

        let detailsMissingCount = assignedQueue.filter {
            $0.details.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }.count

        let completionByTitle = dependencyCompletionMap()

        var runnableTaskIDs: [UUID] = []
        runnableTaskIDs.reserveCapacity(assignedQueue.count)
        var dependencyBlockedCount = 0
        var approvalBlockedCount = 0
        var quotaBlockedCount = 0
        var qualitySafetyBlockedCount = 0

        for task in assignedQueue {
            guard !task.details.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                continue
            }

            if requiresHumanApproval(for: task.id) && !isTaskApprovedForExecution(task.id) {
                approvalBlockedCount += 1
                continue
            }

            if quotaCheckMessage(for: task) != nil {
                quotaBlockedCount += 1
                continue
            }

            if qualitySafetyGateBlockReason(for: task) != nil {
                qualitySafetyBlockedCount += 1
                continue
            }

            let dependencies = Self.parsedDependencyReferences(from: task.details)
            guard !dependencies.isEmpty else {
                runnableTaskIDs.append(task.id)
                continue
            }

            let isBlocked = dependencies.contains { dependencyTitle in
                guard let isCompleted = completionByTitle[dependencyTitle.normalizedTitle] else {
                    return true
                }
                return !isCompleted
            }

            if isBlocked {
                dependencyBlockedCount += 1
            } else {
                runnableTaskIDs.append(task.id)
            }
        }

        return AssignedBatchRunPreparation(
            runnableTaskIDs: runnableTaskIDs,
            detailsMissingCount: detailsMissingCount,
            dependencyBlockedCount: dependencyBlockedCount,
            approvalBlockedCount: approvalBlockedCount,
            quotaBlockedCount: quotaBlockedCount,
            qualitySafetyBlockedCount: qualitySafetyBlockedCount
        )
    }

    private func noRunnableAssignedBatchMessage(
        detailsMissingCount: Int,
        dependencyBlockedCount: Int,
        approvalBlockedCount: Int,
        quotaBlockedCount: Int,
        qualitySafetyBlockedCount: Int
    ) -> String {
        ExecutionSummaryBuilder.noRunnableAssignedBatchMessage(
            detailsMissingCount: detailsMissingCount,
            dependencyBlockedCount: dependencyBlockedCount,
            approvalBlockedCount: approvalBlockedCount,
            quotaBlockedCount: quotaBlockedCount,
            qualitySafetyBlockedCount: qualitySafetyBlockedCount
        )
    }

    @discardableResult
    func runAssignedTaskExecutions() -> Int {
        ExecutionCoordinator.runAssignedTaskExecutions(
            prepareQueue: { attemptedTaskIDs in
                self.prepareAssignedBatchRunQueue(excluding: attemptedTaskIDs)
            },
            runTaskExecution: { taskID in
                self.runTaskExecution(taskID)
            },
            executionStatusForTask: { taskID in
                self.executionRecord(for: taskID)?.status
            },
            handleNoRunnable: { preparation in
                self.lastBoardMessage = self.noRunnableAssignedBatchMessage(
                    detailsMissingCount: preparation.detailsMissingCount,
                    dependencyBlockedCount: preparation.dependencyBlockedCount,
                    approvalBlockedCount: preparation.approvalBlockedCount,
                    quotaBlockedCount: preparation.quotaBlockedCount,
                    qualitySafetyBlockedCount: preparation.qualitySafetyBlockedCount
                )
                self.lastBoardMessageSeverity = ExecutionSeverityPolicy.noRunnableAssignedBatch
            },
            handleFinished: { state in
                let counters = state.counters
                let detailsMissingCount = state.finalPreparation.detailsMissingCount
                let dependencyBlockedCount = state.finalPreparation.dependencyBlockedCount
                let approvalBlockedCount = state.finalPreparation.approvalBlockedCount
                let quotaBlockedCount = state.finalPreparation.quotaBlockedCount
                let qualitySafetyBlockedCount = state.finalPreparation.qualitySafetyBlockedCount
                self.lastBoardMessage = ExecutionSummaryBuilder.batchRunFinishedMessage(
                    counters: counters,
                    detailsMissingCount: detailsMissingCount,
                    dependencyBlockedCount: dependencyBlockedCount,
                    approvalBlockedCount: approvalBlockedCount,
                    quotaBlockedCount: quotaBlockedCount,
                    qualitySafetyBlockedCount: qualitySafetyBlockedCount,
                    wasCancelled: false
                )
                self.lastBoardMessageSeverity = ExecutionSeverityPolicy.batchRunFinished(
                    counters: counters,
                    wasCancelled: false,
                    detailsMissingCount: detailsMissingCount,
                    dependencyBlockedCount: dependencyBlockedCount,
                    approvalBlockedCount: approvalBlockedCount,
                    quotaBlockedCount: quotaBlockedCount,
                    qualitySafetyBlockedCount: qualitySafetyBlockedCount
                )
                self.emitBoardRunFinishedHook(
                    flow: "assigned.batch",
                    totalStarted: counters.startedCount,
                    completedPasses: 1,
                    wasCancelled: false
                )
            }
        )
    }

    func runAssignedTaskExecutionsInBackground(
        emitBoardRunFinishedHook: Bool = true,
        completion: @escaping (Int) -> Void
    ) {
        updateExecutionCheckpoint(
            ExecutionCheckpointUseCase.makeAssignedBatchCheckpoint(boardID: selectedBoardID)
        )
        ExecutionCoordinator.runAssignedTaskExecutionsInBackground(
            setCancelRequested: { self.isBatchRunCancelRequested = $0 },
            isCancelRequested: { self.isBatchRunCancelRequested },
            prepareQueue: { attemptedTaskIDs in
                self.prepareAssignedBatchRunQueue(excluding: attemptedTaskIDs)
            },
            runTaskExecutionInBackground: { taskID, completion in
                self.runTaskExecutionInBackground(taskID, completion: completion)
            },
            maxConcurrentExecutions: executionParallelizationPolicy.isEnabled
                ? executionParallelizationPolicy.maxConcurrentAgents
                : 1,
            groupKeyForTask: { taskID in
                self.tasks.first(where: { $0.id == taskID })?.assignedAgentID
            },
            executionStatusForTask: { taskID in
                self.executionRecord(for: taskID)?.status
            },
            handleNoRunnable: { preparation in
                self.updateExecutionCheckpoint(nil)
                self.lastBoardMessage = self.noRunnableAssignedBatchMessage(
                    detailsMissingCount: preparation.detailsMissingCount,
                    dependencyBlockedCount: preparation.dependencyBlockedCount,
                    approvalBlockedCount: preparation.approvalBlockedCount,
                    quotaBlockedCount: preparation.quotaBlockedCount,
                    qualitySafetyBlockedCount: preparation.qualitySafetyBlockedCount
                )
                self.lastBoardMessageSeverity = ExecutionSeverityPolicy.noRunnableAssignedBatch
                if emitBoardRunFinishedHook {
                    self.emitBoardRunFinishedHook(
                        flow: "assigned.batch",
                        totalStarted: 0,
                        completedPasses: 0,
                        wasCancelled: false
                    )
                }
            },
            handleFinished: { state in
                self.updateExecutionCheckpoint(nil)
                let counters = state.counters
                let detailsMissingCount = state.finalPreparation.detailsMissingCount
                let dependencyBlockedCount = state.finalPreparation.dependencyBlockedCount
                let approvalBlockedCount = state.finalPreparation.approvalBlockedCount
                let quotaBlockedCount = state.finalPreparation.quotaBlockedCount
                let qualitySafetyBlockedCount = state.finalPreparation.qualitySafetyBlockedCount
                self.lastBoardMessage = ExecutionSummaryBuilder.batchRunFinishedMessage(
                    counters: counters,
                    detailsMissingCount: detailsMissingCount,
                    dependencyBlockedCount: dependencyBlockedCount,
                    approvalBlockedCount: approvalBlockedCount,
                    quotaBlockedCount: quotaBlockedCount,
                    qualitySafetyBlockedCount: qualitySafetyBlockedCount,
                    wasCancelled: state.wasCancelled
                )
                self.lastBoardMessageSeverity = ExecutionSeverityPolicy.batchRunFinished(
                    counters: counters,
                    wasCancelled: state.wasCancelled,
                    detailsMissingCount: detailsMissingCount,
                    dependencyBlockedCount: dependencyBlockedCount,
                    approvalBlockedCount: approvalBlockedCount,
                    quotaBlockedCount: quotaBlockedCount,
                    qualitySafetyBlockedCount: qualitySafetyBlockedCount
                )
                if emitBoardRunFinishedHook {
                    self.emitBoardRunFinishedHook(
                        flow: "assigned.batch",
                        totalStarted: counters.startedCount,
                        completedPasses: 1,
                        wasCancelled: state.wasCancelled
                    )
                }
            },
            completion: completion
        )
    }

    func runAutoDispatchCycleInBackground(
        maxPasses: Int = 3,
        autoCreateMissingDependencies: Bool = false,
        autoAssignBeforeRun: Bool = true,
        autoAssignFallbackWithoutSkillMatch: Bool? = nil,
        autoRelaxWIPLimitsDuringRun: Bool? = nil,
        completion: @escaping (_ totalStarted: Int, _ completedPasses: Int) -> Void
    ) {
        let resolvedAutoAssignFallback = autoAssignFallbackWithoutSkillMatch
            ?? dagExecutionPolicy.autoAssignFallbackWithoutSkillMatch
        let resolvedAutoRelaxWIPLimits = autoRelaxWIPLimitsDuringRun
            ?? dagExecutionPolicy.autoRelaxWIPLimitsDuringRun
        updateExecutionCheckpoint(
            ExecutionCheckpointUseCase.makeAutoCycleCheckpoint(
                boardID: selectedBoardID,
                maxPasses: maxPasses,
                autoCreateMissingDependencies: autoCreateMissingDependencies,
                autoAssignBeforeRun: autoAssignBeforeRun,
                autoAssignFallbackWithoutSkillMatch: resolvedAutoAssignFallback
            )
        )
        ExecutionCoordinator.runAutoDispatchCycleInBackground(
            maxPasses: maxPasses,
            autoCreateMissingDependencies: autoCreateMissingDependencies,
            autoAssignBeforeRun: autoAssignBeforeRun,
            setCancelRequested: { self.isAutoCycleCancelRequested = $0 },
            isCancelRequested: { self.isAutoCycleCancelRequested },
            setCreatedDependencyTaskCount: { self.lastAutoCycleCreatedDependencyTaskCount = $0 },
            createMissingDependencyTasks: { self.createMissingDependencyTasks() },
            autoAssignTasks: {
                self.autoAssignTasks(allowFallbackWithoutSkillMatch: resolvedAutoAssignFallback)
            },
            runAssignedTaskExecutionsInBackground: { completion in
                self.runAssignedTaskExecutionsInBackground(emitBoardRunFinishedHook: false) { started in
                    guard started == 0, resolvedAutoRelaxWIPLimits else {
                        completion(started)
                        return
                    }
                    let relaxedCount = self.autoRelaxWIPLimitsForAutoCycle()
                    guard relaxedCount > 0 else {
                        completion(started)
                        return
                    }
                    self.runAssignedTaskExecutionsInBackground(
                        emitBoardRunFinishedHook: false,
                        completion: completion
                    )
                }
            },
            boardMessageSeverity: { self.lastBoardMessageSeverity },
            isTerminalNoRunnablePass: { started, totalStarted in
                started == 0 &&
                    totalStarted > 0 &&
                    self.lastBoardMessage == ExecutionSummaryBuilder.noRunnableAssignedTasksMessage
            },
            prepareRemainingQueue: { self.prepareAssignedBatchRunQueue() },
            handleFinished: { state in
                self.updateExecutionCheckpoint(nil)
                if state.totalStarted > 0 || state.wasCancelled {
                    let remainingDetailsMissing = state.remainingPreparation.detailsMissingCount
                    let remainingDependencyBlocked = state.remainingPreparation.dependencyBlockedCount
                    let remainingQualitySafetyBlocked = state.remainingPreparation.qualitySafetyBlockedCount
                    self.lastBoardMessage = ExecutionSummaryBuilder.autoCycleFinishedMessage(
                        completedPasses: state.completedPasses,
                        totalStarted: state.totalStarted,
                        wasCancelled: state.wasCancelled,
                        createdDependencyTaskCount: state.createdDependencyTaskCount,
                        remainingDetailsMissing: remainingDetailsMissing,
                        remainingDependencyBlocked: remainingDependencyBlocked,
                        remainingApprovalBlocked: state.remainingPreparation.approvalBlockedCount,
                        remainingQuotaBlocked: state.remainingPreparation.quotaBlockedCount,
                        remainingQualitySafetyBlocked: remainingQualitySafetyBlocked
                    )
                    self.lastBoardMessageSeverity = ExecutionSeverityPolicy.autoCycleFinished(
                        hadWarning: state.hadWarning,
                        wasCancelled: state.wasCancelled,
                        remainingDetailsMissing: remainingDetailsMissing,
                        remainingDependencyBlocked: remainingDependencyBlocked,
                        remainingApprovalBlocked: state.remainingPreparation.approvalBlockedCount,
                        remainingQuotaBlocked: state.remainingPreparation.quotaBlockedCount,
                        remainingQualitySafetyBlocked: remainingQualitySafetyBlocked
                    )
                } else if self.lastBoardMessage == nil {
                    self.lastBoardMessage = ExecutionSummaryBuilder.autoCycleNoRunnableMessage
                    self.lastBoardMessageSeverity = ExecutionSeverityPolicy.autoCycleNoRunnable
                }
                self.emitBoardRunFinishedHook(
                    flow: "auto.dispatch.cycle",
                    totalStarted: state.totalStarted,
                    completedPasses: state.completedPasses,
                    wasCancelled: state.wasCancelled
                )
            },
            completion: completion
        )
    }

    func runDAGAutopilotInBackground(
        completion: @escaping (_ totalStarted: Int, _ completedPasses: Int) -> Void
    ) {
        let policy = dagExecutionPolicy
        let resolvedMaxPasses = policy.isEnabled ? policy.maxPasses : 3
        let resolvedAutoAssign = policy.isEnabled ? policy.autoAssignBeforeRun : true
        let resolvedAutoAssignFallback = policy.isEnabled
            ? policy.autoAssignFallbackWithoutSkillMatch
            : false
        let resolvedAutoRelaxWIPLimits = policy.isEnabled
            ? policy.autoRelaxWIPLimitsDuringRun
            : false
        let resolvedAutoCreateDependencies = policy.isEnabled
            ? policy.autoCreateMissingDependenciesDuringRun
            : false

        runAutoDispatchCycleInBackground(
            maxPasses: resolvedMaxPasses,
            autoCreateMissingDependencies: resolvedAutoCreateDependencies,
            autoAssignBeforeRun: resolvedAutoAssign,
            autoAssignFallbackWithoutSkillMatch: resolvedAutoAssignFallback,
            autoRelaxWIPLimitsDuringRun: resolvedAutoRelaxWIPLimits,
            completion: completion
        )
    }

    @discardableResult
    func clearExecutionCheckpoint() -> Bool {
        guard executionCheckpoint != nil else { return false }
        updateExecutionCheckpoint(nil)
        lastBoardMessage = message("Cleared interrupted run checkpoint")
        lastBoardMessageSeverity = .info
        return true
    }

    func resumeExecutionFromCheckpointInBackground(completion: @escaping (Bool) -> Void) {
        guard let action = ExecutionCheckpointUseCase.resumeAction(
            for: executionCheckpoint,
            selectedBoardID: selectedBoardID
        ) else {
            lastBoardMessage = message("No interrupted run checkpoint available for this board")
            lastBoardMessageSeverity = .warning
            completion(false)
            return
        }

        switch action {
        case .assignedBatch:
            lastBoardMessage = message("Resuming interrupted assigned run")
            lastBoardMessageSeverity = .info
            runAssignedTaskExecutionsInBackground { startedCount in
                completion(startedCount > 0)
            }
        case let .autoCycle(maxPasses, autoCreateMissingDependencies, autoAssignBeforeRun, autoAssignFallbackWithoutSkillMatch):
            lastBoardMessage = message("Resuming interrupted auto cycle")
            lastBoardMessageSeverity = .info
            runAutoDispatchCycleInBackground(
                maxPasses: maxPasses,
                autoCreateMissingDependencies: autoCreateMissingDependencies,
                autoAssignBeforeRun: autoAssignBeforeRun,
                autoAssignFallbackWithoutSkillMatch: autoAssignFallbackWithoutSkillMatch
            ) { startedCount, _ in
                completion(startedCount > 0)
            }
        }
    }

    func runGitHubPRFlowForSelectedBoardInBackground(
        repositoryPath: String,
        baseBranch: String,
        remoteName: String,
        branchPrefix: String,
        completion: @escaping (Bool) -> Void
    ) {
        syncCurrentBoardRecord()
        guard let selectedBoard = boards.first(where: { $0.id == selectedBoardID }) else {
            lastBoardMessage = message("Board not found")
            lastBoardMessageSeverity = .warning
            completion(false)
            return
        }
        guard let executionReportMarkdown = executionReportMarkdownForSelectedBoard() else {
            lastBoardMessage = message("Failed to generate execution report")
            lastBoardMessageSeverity = .warning
            completion(false)
            return
        }

        let dependencyInsights = selectedBoardDependencyInsights
        let boardName = selectedBoard.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedBoardName = boardName.isEmpty ? message("Default Board") : boardName

        let request = GitHubPRFlowRequest(
            repositoryPath: repositoryPath,
            boardName: resolvedBoardName,
            baseBranch: baseBranch,
            remoteName: remoteName,
            branchPrefix: branchPrefix,
            commitMessage: "chore(\(resolvedBoardName)): OpenMac board sync",
            prTitle: "[OpenMac] \(resolvedBoardName) board update",
            prBody: githubPRBody(
                boardName: resolvedBoardName,
                executionReportMarkdown: executionReportMarkdown,
                dependencyInsights: dependencyInsights
            ),
            qualityGateEnabled: gitHubPRQualityGatePolicy.isEnabled,
            qualityGateCommands: gitHubPRQualityGatePolicy.commands
        )

        runOnBackground {
            let result = GitHubPRFlowUseCase.run(
                request: request,
                commandRunner: self.gitCommandRunner
            )
            self.runOnMain {
                self.lastGitHubPRURL = result.pullRequestURL
                self.lastGitHubPRLog = result.debugLog
                self.lastExecutionDebugLog = result.debugLog.isEmpty ? nil : result.debugLog
                self.lastCodexLoginCommand = nil
                if result.succeeded {
                    if let pullRequestURL = result.pullRequestURL, !pullRequestURL.isEmpty {
                        self.lastBoardMessage = self.message("GitHub PR created: %@", pullRequestURL)
                    } else {
                        self.lastBoardMessage = self.message("GitHub PR created for branch %@", result.branchName)
                    }
                    self.lastBoardMessageSeverity = .info
                } else {
                    self.lastBoardMessage = self.message("GitHub PR flow failed: %@", result.message)
                    self.lastBoardMessageSeverity = .warning
                }
                completion(result.succeeded)
            }
        }
    }

    func requestCancelAssignedTaskExecutions() {
        isBatchRunCancelRequested = true
        let runningTaskIDs = tasks
            .filter { $0.executionRecord?.status == .running }
            .map(\.id)
        taskExecutor.requestCancellation(taskIDs: runningTaskIDs)
        if !runningTaskIDs.isEmpty {
            lastBoardMessage = message("Cancellation requested for %d running task(s)", runningTaskIDs.count)
            lastBoardMessageSeverity = .warning
        }
    }

    func requestCancelAutoDispatchCycle() {
        isAutoCycleCancelRequested = true
        requestCancelAssignedTaskExecutions()
    }

    @discardableResult
    func requestCancelTaskExecution(_ taskID: UUID) -> Bool {
        guard let taskIndex = tasks.firstIndex(where: { $0.id == taskID }),
              tasks[taskIndex].executionRecord?.status == .running else {
            lastBoardMessage = message("Task is not currently running")
            lastBoardMessageSeverity = .warning
            return false
        }

        taskExecutor.requestCancellation(taskID: taskID)
        if let agentID = tasks[taskIndex].assignedAgentID ?? tasks[taskIndex].executionRecord?.lastAgentID {
            appendAgentExecutionEvent(
                agentID: agentID,
                taskID: tasks[taskIndex].id,
                taskTitle: tasks[taskIndex].title,
                status: .running,
                phase: .system,
                message: message("Cancellation requested for \"%@\"", tasks[taskIndex].title)
            )
        }
        lastBoardMessage = message("Cancellation requested for \"%@\"", tasks[taskIndex].title)
        lastBoardMessageSeverity = .warning
        return true
    }

    private func preparePMAutopilot(
        plannedTickets: [PMPlannedTicket],
        autoAssign: Bool,
        deliveryContract: TaskDeliveryContract,
        generateAcceptanceE2ETasks: Bool
    ) -> PMAutopilotPreparation<PMCreatedTaskDescriptor>? {
        let normalizedTickets = plannedTickets.compactMap(Self.normalizedPlannedTicket(from:))
        guard !normalizedTickets.isEmpty else {
            lastBoardMessage = message("PM autopilot requires at least one planned ticket")
            lastBoardMessageSeverity = .warning
            return nil
        }

        let createdAgents = createMissingAgentsForPlannedTickets(normalizedTickets)
        let createdTaskDescriptors = addNormalizedPlannedTickets(
            normalizedTickets,
            autoAssign: autoAssign,
            deliveryContract: deliveryContract
        )
        if generateAcceptanceE2ETasks {
            _ = createAcceptanceE2ETasks(
                autoAssign: autoAssign,
                sourceTaskIDs: Set(createdTaskDescriptors.map(\.taskID)),
                updateBoardMessage: false
            )
        }
        let roadmapMilestoneCount = Self.plannedTicketMilestoneCount(normalizedTickets)
        let roadmapEpicCount = Self.plannedTicketEpicCount(normalizedTickets)

        return PMAutopilotPreparation(
            createdAgents: createdAgents,
            createdTaskDescriptors: createdTaskDescriptors,
            roadmapMilestoneCount: roadmapMilestoneCount,
            roadmapEpicCount: roadmapEpicCount
        )
    }

    func runPMAutopilotInBackground(
        plannedTickets: [PMPlannedTicket],
        autoAssign: Bool = true,
        deliveryContract: TaskDeliveryContract = .defaultContract,
        autoCreateAcceptanceE2ETasks: Bool = false,
        autoCreateMissingDependenciesDuringCycle: Bool = true,
        maxAutoCyclePasses: Int = 3,
        completion: @escaping (_ createdAgents: Int, _ createdTickets: Int, _ startedExecutions: Int, _ completedPasses: Int) -> Void
    ) {
        ExecutionCoordinator.runPMAutopilotInBackground(
            plannedTickets: plannedTickets,
            autoAssign: autoAssign,
            autoCreateMissingDependenciesDuringCycle: autoCreateMissingDependenciesDuringCycle,
            maxAutoCyclePasses: maxAutoCyclePasses,
            preparePMAutopilot: { plannedTickets, autoAssign in
                self.preparePMAutopilot(
                    plannedTickets: plannedTickets,
                    autoAssign: autoAssign,
                    deliveryContract: deliveryContract,
                    generateAcceptanceE2ETasks: autoCreateAcceptanceE2ETasks
                )
            },
            runAutoDispatchCycleInBackground: { maxPasses, autoCreateMissingDependencies, autoAssignBeforeRun, completion in
                self.runAutoDispatchCycleInBackground(
                    maxPasses: maxPasses,
                    autoCreateMissingDependencies: autoCreateMissingDependencies,
                    autoAssignBeforeRun: autoAssignBeforeRun,
                    completion: completion
                )
            },
            boardMessageSeverity: { self.lastBoardMessageSeverity },
            prepareAssignedBatchRunQueue: { self.prepareAssignedBatchRunQueue() },
            lastAutoCycleCreatedDependencyTaskCount: { self.lastAutoCycleCreatedDependencyTaskCount },
            handleFinished: { state in
                let createdTickets = state.createdTaskDescriptors.count
                let remainingDetailsMissing = state.remainingPreparation.detailsMissingCount
                let remainingDependencyBlocked = state.remainingPreparation.dependencyBlockedCount
                let remainingQualitySafetyBlocked = state.remainingPreparation.qualitySafetyBlockedCount

                let roadmapSections = PMRoadmapSummaryBuilder.buildSections(
                    createdTasks: state.createdTaskDescriptors,
                    tasks: self.tasks,
                    taskID: { $0.taskID },
                    milestone: { $0.milestone },
                    epic: { $0.epic }
                )
                self.lastBoardMessage = ExecutionSummaryBuilder.pmAutopilotFinishedMessage(
                    createdAgents: state.createdAgents,
                    createdTickets: createdTickets,
                    startedExecutions: state.startedExecutions,
                    completedPasses: state.completedPasses,
                    roadmapMilestoneCount: state.roadmapMilestoneCount,
                    roadmapEpicCount: state.roadmapEpicCount,
                    roadmapSections: roadmapSections,
                    autoCycleCreatedDependencyTaskCount: state.autoCycleCreatedDependencyTaskCount,
                    remainingDetailsMissing: remainingDetailsMissing,
                    remainingDependencyBlocked: remainingDependencyBlocked,
                    remainingApprovalBlocked: state.remainingPreparation.approvalBlockedCount,
                    remainingQuotaBlocked: state.remainingPreparation.quotaBlockedCount,
                    remainingQualitySafetyBlocked: remainingQualitySafetyBlocked
                )
                self.lastBoardMessageSeverity = ExecutionSeverityPolicy.pmAutopilotFinished(
                    cycleHadWarning: state.cycleHadWarning,
                    startedExecutions: state.startedExecutions,
                    remainingDetailsMissing: remainingDetailsMissing,
                    remainingDependencyBlocked: remainingDependencyBlocked,
                    remainingApprovalBlocked: state.remainingPreparation.approvalBlockedCount,
                    remainingQuotaBlocked: state.remainingPreparation.quotaBlockedCount,
                    remainingQualitySafetyBlocked: remainingQualitySafetyBlocked
                )
            },
            completion: completion
        )
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

    func assignableAgents(for taskID: UUID, allowPartialSkillMatch: Bool = false) -> [AgentProfile] {
        guard let task = tasks.first(where: { $0.id == taskID }) else { return [] }
        guard task.status == .todo, task.assignedAgentID == nil else { return [] }

        return agents
            .filter { agent in
                agentMatchesTaskSkills(
                    agent,
                    task: task,
                    allowPartialSkillMatch: allowPartialSkillMatch
                ) && activeTaskCount(for: agent.id) < agent.maxConcurrentTasks
            }
            .sorted { lhs, rhs in
                if allowPartialSkillMatch {
                    let lhsExact = lhs.hasSkills(for: task)
                    let rhsExact = rhs.hasSkills(for: task)
                    if lhsExact != rhsExact {
                        return lhsExact && !rhsExact
                    }

                    let leftMatchCount = skillMatchCount(agent: lhs, task: task)
                    let rightMatchCount = skillMatchCount(agent: rhs, task: task)
                    if leftMatchCount != rightMatchCount {
                        return leftMatchCount > rightMatchCount
                    }
                }

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

    func resolvedTriageAssignments(
        existing: [UUID: UUID] = [:],
        allowPartialSkillMatch: Bool = false
    ) -> [UUID: UUID] {
        bulkTriageAssignmentPlan(
            using: existing,
            allowPartialSkillMatch: allowPartialSkillMatch
        )
    }

    func bulkAssignableTriageTaskCount(
        using preferredAssignments: [UUID: UUID] = [:],
        allowPartialSkillMatch: Bool = false
    ) -> Int {
        bulkTriageAssignmentPlan(
            using: preferredAssignments,
            allowPartialSkillMatch: allowPartialSkillMatch
        ).count
    }

    func bulkUnassignableTriageTaskCount(
        using preferredAssignments: [UUID: UUID] = [:],
        allowPartialSkillMatch: Bool = false
    ) -> Int {
        let assignableCount = bulkAssignableTriageTaskCount(
            using: preferredAssignments,
            allowPartialSkillMatch: allowPartialSkillMatch
        )
        return max(0, triageCandidates().count - assignableCount)
    }

    func bulkTriageAssignmentPlan(
        using preferredAssignments: [UUID: UUID] = [:],
        allowPartialSkillMatch: Bool = false
    ) -> [UUID: UUID] {
        let agentsByID = Dictionary(uniqueKeysWithValues: agents.map { ($0.id, $0) })
        var loadsByAgentID = Dictionary(uniqueKeysWithValues: agents.map { ($0.id, activeTaskCount(for: $0.id)) })
        var plan: [UUID: UUID] = [:]

        for task in triageCandidates() {
            guard let selectedAgent = selectBulkTriageAgent(
                for: task,
                preferredAgentID: preferredAssignments[task.id],
                agentsByID: agentsByID,
                loadsByAgentID: loadsByAgentID,
                allowPartialSkillMatch: allowPartialSkillMatch
            ) else {
                continue
            }

            plan[task.id] = selectedAgent.id
            loadsByAgentID[selectedAgent.id, default: 0] += 1
        }

        return plan
    }

    @discardableResult
    func manuallyAssignTask(
        _ taskID: UUID,
        to agentID: UUID,
        allowPartialSkillMatch: Bool = false
    ) -> Bool {
        guard let taskIndex = tasks.firstIndex(where: { $0.id == taskID }) else { return false }
        guard let agent = agents.first(where: { $0.id == agentID }) else { return false }

        guard tasks[taskIndex].status == .todo else {
            lastBoardMessage = message("Only To Do tasks can be manually triaged")
            return false
        }
        guard tasks[taskIndex].assignedAgentID == nil else {
            lastBoardMessage = message("Task is already assigned")
            return false
        }

        guard agentMatchesTaskSkills(
            agent,
            task: tasks[taskIndex],
            allowPartialSkillMatch: allowPartialSkillMatch
        ) else {
            lastBoardMessage = message("Agent %@ does not match required skills", agent.name)
            return false
        }

        let currentLoad = activeTaskCount(for: agentID)
        guard currentLoad < agent.maxConcurrentTasks else {
            lastBoardMessage = message("Agent %@ is at max load (%d)", agent.name, agent.maxConcurrentTasks)
            return false
        }

        tasks[taskIndex].assignedAgentID = agentID
        lastUnassignedTaskIDs.remove(taskID)
        if allowPartialSkillMatch, !agent.hasSkills(for: tasks[taskIndex]) {
            lastAssignmentReasons[taskID] = "manual-partial[\(agent.name)] load[\(currentLoad + 1)/\(agent.maxConcurrentTasks)]"
        } else {
            lastAssignmentReasons[taskID] = "manual[\(agent.name)] load[\(currentLoad + 1)/\(agent.maxConcurrentTasks)]"
        }
        persistBoardState()
        lastBoardMessage = nil
        return true
    }

    @discardableResult
    func reassignTask(_ taskID: UUID, to agentID: UUID) -> Bool {
        guard let taskIndex = tasks.firstIndex(where: { $0.id == taskID }) else { return false }
        guard let agent = agents.first(where: { $0.id == agentID }) else { return false }

        guard tasks[taskIndex].status == .todo else {
            lastBoardMessage = message("Only To Do tasks can be reassigned")
            return false
        }
        guard let currentAgentID = tasks[taskIndex].assignedAgentID else {
            lastBoardMessage = message("Task is unassigned")
            return false
        }
        guard currentAgentID != agentID else {
            lastBoardMessage = message("Task already assigned to %@", agent.name)
            return false
        }

        guard agent.hasSkills(for: tasks[taskIndex]) else {
            lastBoardMessage = message("Agent %@ does not match required skills", agent.name)
            return false
        }

        let currentLoad = activeTaskCount(for: agentID)
        guard currentLoad < agent.maxConcurrentTasks else {
            lastBoardMessage = message("Agent %@ is at max load (%d)", agent.name, agent.maxConcurrentTasks)
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
    func bulkAssignTriageTasks(
        using preferredAssignments: [UUID: UUID] = [:],
        allowPartialSkillMatch: Bool = false
    ) -> Int {
        let assignmentPlan = bulkTriageAssignmentPlan(
            using: preferredAssignments,
            allowPartialSkillMatch: allowPartialSkillMatch
        )
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
            if allowPartialSkillMatch, !selectedAgent.hasSkills(for: task) {
                lastAssignmentReasons[task.id] = "manual-bulk-partial[\(selectedAgent.name)] load[\(currentLoad + 1)/\(selectedAgent.maxConcurrentTasks)]"
            } else {
                lastAssignmentReasons[task.id] = "manual-bulk[\(selectedAgent.name)] load[\(currentLoad + 1)/\(selectedAgent.maxConcurrentTasks)]"
            }
            assignedCount += 1
        }

        guard assignedCount > 0 else {
            if !candidates.isEmpty {
                lastBoardMessage = message("No eligible agents available for pending triage tasks")
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
        loadsByAgentID: [UUID: Int],
        allowPartialSkillMatch: Bool
    ) -> AgentProfile? {
        if let preferredAgentID,
           let preferredAgent = agentsByID[preferredAgentID],
           isEligibleForBulkTriage(
            preferredAgent,
            task: task,
            loadsByAgentID: loadsByAgentID,
            allowPartialSkillMatch: allowPartialSkillMatch
           ) {
            return preferredAgent
        }

        return agents
            .filter { agent in
                isEligibleForBulkTriage(
                    agent,
                    task: task,
                    loadsByAgentID: loadsByAgentID,
                    allowPartialSkillMatch: allowPartialSkillMatch
                )
            }
            .sorted { lhs, rhs in
                if allowPartialSkillMatch {
                    let lhsExact = lhs.hasSkills(for: task)
                    let rhsExact = rhs.hasSkills(for: task)
                    if lhsExact != rhsExact {
                        return lhsExact && !rhsExact
                    }

                    let leftMatchCount = skillMatchCount(agent: lhs, task: task)
                    let rightMatchCount = skillMatchCount(agent: rhs, task: task)
                    if leftMatchCount != rightMatchCount {
                        return leftMatchCount > rightMatchCount
                    }
                }

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
        loadsByAgentID: [UUID: Int],
        allowPartialSkillMatch: Bool
    ) -> Bool {
        guard agentMatchesTaskSkills(
            agent,
            task: task,
            allowPartialSkillMatch: allowPartialSkillMatch
        ) else { return false }
        return loadsByAgentID[agent.id, default: 0] < agent.maxConcurrentTasks
    }

    private func agentMatchesTaskSkills(
        _ agent: AgentProfile,
        task: WorkTask,
        allowPartialSkillMatch: Bool
    ) -> Bool {
        if agent.hasSkills(for: task) {
            return true
        }
        guard allowPartialSkillMatch else { return false }
        if task.requiredSkills.isEmpty { return true }
        return skillMatchCount(agent: agent, task: task) > 0
    }

    private func skillMatchCount(agent: AgentProfile, task: WorkTask) -> Int {
        agent.skills.intersection(task.requiredSkills).count
    }

    private func bulkTriageAssignmentSummary(assignedCount: Int, remainingCount: Int) -> String {
        let assignedLabel = assignedCount == 1 ? message("task") : message("tasks")
        let remainingLabel = remainingCount == 1 ? message("task") : message("tasks")
        return message(
            "Assigned %d triage %@. %d %@ still need manual attention",
            assignedCount,
            assignedLabel,
            remainingCount,
            remainingLabel
        )
    }

    private func normalizeExecutionText(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func normalizeExecutionSummary(_ value: String?) -> String? {
        guard let normalized = normalizeExecutionText(value) else { return nil }
        let lines = normalized
            .split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
            .map(String.init)
        guard let firstNonEmptyIndex = lines.firstIndex(where: {
            !$0.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).isEmpty
        }) else {
            return normalized
        }

        let firstLine = lines[firstNonEmptyIndex].trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        let headingPattern = #"^(Summary|摘要|Resumen|Resume|要約|요약)\s*[:：]\s*(.*)$"#
        guard let regex = try? NSRegularExpression(pattern: headingPattern, options: [.caseInsensitive]) else {
            return normalized
        }
        let firstLineRange = NSRange(firstLine.startIndex..<firstLine.endIndex, in: firstLine)
        guard let match = regex.firstMatch(in: firstLine, options: [], range: firstLineRange) else {
            return normalized
        }

        let inlineBodyRange = match.range(at: 2)
        let inlineBody: String
        if inlineBodyRange.location != NSNotFound,
           let swiftRange = Range(inlineBodyRange, in: firstLine) {
            inlineBody = firstLine[swiftRange].trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        } else {
            inlineBody = ""
        }

        var remainingLines = lines
        remainingLines.remove(at: firstNonEmptyIndex)
        let bodyFromRemaining = remainingLines
            .joined(separator: "\n")
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        let merged = [inlineBody, bodyFromRemaining]
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return merged.isEmpty ? nil : merged
    }

    private func sharedAgentMemoryEntries(limit: Int) -> [SharedAgentMemoryEntry] {
        guard limit > 0 else { return [] }
        if sharedAgentMemory.count <= limit {
            return sharedAgentMemory.reversed()
        }
        return sharedAgentMemory.suffix(limit).reversed()
    }

    private func sharedAgentMemoryPromptContext(excludingTaskID: UUID?) -> String {
        let selectedEntries = sharedAgentMemory
            .reversed()
            .filter { entry in
                guard let excludingTaskID else { return true }
                return entry.taskID != excludingTaskID
            }
            .prefix(Self.sharedAgentMemoryPromptLimit)

        guard !selectedEntries.isEmpty else { return "" }

        var lines: [String] = []
        var usedCharacters = 0
        for entry in selectedEntries {
            let summary = Self.summarizedExtensionOutput(entry.summary)
            guard !summary.isEmpty else { continue }
            let line = "- [\(entry.source.rawValue)] \(entry.taskTitle) (\(entry.agentName)): \(summary)"
            let additionalChars = line.count + 1
            if usedCharacters + additionalChars > Self.sharedAgentMemoryPromptCharsLimit {
                break
            }
            usedCharacters += additionalChars
            lines.append(line)
        }
        return lines.joined(separator: "\n")
    }

    private func taskSnapshotWithSharedMemoryContext(_ task: WorkTask, agent: AgentProfile) -> WorkTask {
        let coreContext = sharedAgentMemoryPromptContext(excludingTaskID: task.id)
        let extensionContext = extensionMemoryProviderContext(for: task, agent: agent, coreContext: coreContext)
        let context: String
        switch sharedAgentMemoryProviderMode {
        case .coreOnly:
            context = coreContext
        case .extensionPreferred:
            if let extensionContext, !extensionContext.isEmpty {
                if coreContext.isEmpty {
                    context = "Extension memory context:\n\(extensionContext)"
                } else {
                    context = "Extension memory context:\n\(extensionContext)\n\nShared team memory (latest context):\n\(coreContext)"
                }
            } else {
                context = coreContext
            }
        }
        guard !context.isEmpty else { return task }

        let baseDetails = task.details.trimmingCharacters(in: .whitespacesAndNewlines)
        let memoryHeader = context
        var enrichedTask = task
        if baseDetails.isEmpty {
            enrichedTask.details = memoryHeader
        } else {
            enrichedTask.details = "\(baseDetails)\n\n\(memoryHeader)"
        }
        appendAgentExecutionEvent(
            agentID: agent.id,
            taskID: task.id,
            taskTitle: task.title,
            status: .running,
            phase: .system,
            message: message(
                "Loaded shared memory context (%d entries)",
                max(1, context.split(whereSeparator: \.isNewline).count)
            )
        )
        return enrichedTask
    }

    private func extensionMemoryProviderContext(for task: WorkTask, agent: AgentProfile, coreContext: String) -> String? {
        guard sharedAgentMemoryProviderMode == .extensionPreferred else { return nil }
        let providers = sharedMemoryExecutionProviders()
        guard !providers.isEmpty else { return nil }
        let commands = pmExtensionCommands()

        for provider in providers {
            guard let command = commands.first(where: {
                $0.pluginID == provider.pluginID && $0.commandID == provider.commandID
            }) else {
                continue
            }
            let extensionInputs: [String: String] = [
                "memoryProvider": provider.providerID,
                "memoryStrategy": provider.strategy,
                "memoryPhase": "context.inject",
                "memoryCoreContext": coreContext,
                "currentTaskTitle": task.title,
                "currentTaskID": task.id.uuidString,
                "currentAgent": agent.name
            ]
            let succeeded = runPMExtensionCommand(command, task: task, extensionInputs: extensionInputs)
            guard succeeded else { continue }
            let providerOutput = pmExtensionObservability.first(where: {
                $0.pluginID == provider.pluginID
            })?.lastOutputSummary
            if let providerOutput = normalizeExecutionText(providerOutput),
               providerOutput != "-" {
                appendAgentExecutionEvent(
                    agentID: agent.id,
                    taskID: task.id,
                    taskTitle: task.title,
                    status: .running,
                    phase: .system,
                    message: message("Loaded extension memory provider: %@", provider.title)
                )
                return providerOutput
            }
        }
        return nil
    }

    private func appendSharedAgentMemoryEntry(_ entry: SharedAgentMemoryEntry) {
        let normalizedSummary = normalizeExecutionText(entry.summary)
        guard let normalizedSummary else { return }

        let normalizedEntry = SharedAgentMemoryEntry(
            id: entry.id,
            createdAt: entry.createdAt,
            source: entry.source,
            agentID: entry.agentID,
            agentName: entry.agentName,
            taskID: entry.taskID,
            taskTitle: entry.taskTitle,
            summary: normalizedSummary
        )
        if let latest = sharedAgentMemory.last,
           latest.source == normalizedEntry.source,
           latest.taskID == normalizedEntry.taskID,
           latest.agentID == normalizedEntry.agentID,
           latest.summary == normalizedEntry.summary,
           abs(latest.createdAt.timeIntervalSince(normalizedEntry.createdAt)) < 4 {
            return
        }
        sharedAgentMemory.append(normalizedEntry)
        if sharedAgentMemory.count > Self.maxSharedAgentMemoryEntries {
            sharedAgentMemory.removeFirst(sharedAgentMemory.count - Self.maxSharedAgentMemoryEntries)
        }
    }

    private func rememberExecutionOutcomeInSharedMemory(
        task: WorkTask,
        agent: AgentProfile,
        status: TaskExecutionStatus,
        summary: String?,
        source: SharedAgentMemoryEntry.Source
    ) {
        let normalizedSummary = normalizeExecutionText(summary)
        guard let normalizedSummary else { return }
        appendSharedAgentMemoryEntry(
            SharedAgentMemoryEntry(
                source: source,
                agentID: agent.id,
                agentName: agent.name,
                taskID: task.id,
                taskTitle: task.title,
                summary: "[\(status.rawValue)] \(normalizedSummary)"
            )
        )
    }

    private func appendAgentExecutionEvent(
        agentID: UUID,
        taskID: UUID,
        taskTitle: String,
        status: TaskExecutionStatus,
        phase: ExecutionEventPhase = .progress,
        message: String,
        details: String? = nil
    ) {
        let event = AgentExecutionEvent(
            agentID: agentID,
            taskID: taskID,
            taskTitle: taskTitle,
            status: status,
            phase: phase,
            message: message,
            details: normalizeExecutionText(details)
        )

        var events = agentExecutionEventsByAgentID[agentID] ?? []
        events.append(event)
        if events.count > Self.maxAgentExecutionEventsPerAgent {
            events.removeFirst(events.count - Self.maxAgentExecutionEventsPerAgent)
        }
        agentExecutionEventsByAgentID[agentID] = events

        var timelineEvents = executionTimelineByTaskID[taskID] ?? []
        timelineEvents.append(event)
        if timelineEvents.count > Self.maxTaskTimelineEventsPerTask {
            timelineEvents.removeFirst(timelineEvents.count - Self.maxTaskTimelineEventsPerTask)
        }
        executionTimelineByTaskID[taskID] = timelineEvents
    }

    private func captureExecutionProgress(_ update: String, for prepared: PreparedTaskExecution) {
        let normalized = normalizeExecutionText(update)
        guard let normalized else { return }

        let lines = normalized
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        if lines.isEmpty {
            appendAgentExecutionEvent(
                agentID: prepared.agent.id,
                taskID: prepared.taskID,
                taskTitle: prepared.taskSnapshot.title,
                status: .running,
                phase: .progress,
                message: normalized
            )
            return
        }

        for line in lines {
            appendAgentExecutionEvent(
                agentID: prepared.agent.id,
                taskID: prepared.taskID,
                taskTitle: prepared.taskSnapshot.title,
                status: .running,
                phase: .progress,
                message: line
            )
        }
    }

    private func prepareTaskExecution(_ taskID: UUID, requiresTaskDetails: Bool) -> PreparedTaskExecution? {
        guard let taskIndex = tasks.firstIndex(where: { $0.id == taskID }) else { return nil }
        lastExecutionDebugLog = nil
        lastCodexLoginCommand = nil
        if tasks[taskIndex].executionRecord?.status == .running {
            lastBoardMessage = message("Task execution is already running")
            lastBoardMessageSeverity = .warning
            return nil
        }
        guard tasks[taskIndex].status != .done else {
            lastBoardMessage = message("Done tasks cannot be executed")
            lastBoardMessageSeverity = .warning
            return nil
        }
        guard let agentID = tasks[taskIndex].assignedAgentID,
              let agent = agents.first(where: { $0.id == agentID }) else {
            lastBoardMessage = message("Assign an agent before running this task")
            lastBoardMessageSeverity = .warning
            return nil
        }
        guard !requiresTaskDetails || !tasks[taskIndex].details.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            lastBoardMessage = message("Task details are required before running this task")
            lastBoardMessageSeverity = .warning
            return nil
        }
        let unresolvedDependencies = unresolvedDependencies(for: taskID)
        guard unresolvedDependencies.isEmpty else {
            lastBoardMessage = message("Task blocked by dependencies: %@", unresolvedDependencies.joined(separator: ", "))
            lastBoardMessageSeverity = .warning
            return nil
        }
        if requiresHumanApproval(for: taskID) && !isTaskApprovedForExecution(taskID) {
            let blockedMessage = message("Execution requires human approval for this task")
            lastBoardMessage = blockedMessage
            lastBoardMessageSeverity = .warning
            appendAgentExecutionEvent(
                agentID: agent.id,
                taskID: taskID,
                taskTitle: tasks[taskIndex].title,
                status: .failed,
                phase: .governance,
                message: blockedMessage
            )
            return nil
        }
        if let quotaMessage = quotaCheckMessage(for: tasks[taskIndex]) {
            lastBoardMessage = quotaMessage
            lastBoardMessageSeverity = .warning
            appendAgentExecutionEvent(
                agentID: agent.id,
                taskID: taskID,
                taskTitle: tasks[taskIndex].title,
                status: .failed,
                phase: .governance,
                message: quotaMessage
            )
            return nil
        }
        if let qualitySafetyMessage = qualitySafetyGateBlockReason(for: tasks[taskIndex]) {
            lastBoardMessage = qualitySafetyMessage
            lastBoardMessageSeverity = .warning
            appendAgentExecutionEvent(
                agentID: agent.id,
                taskID: taskID,
                taskTitle: tasks[taskIndex].title,
                status: .failed,
                phase: .governance,
                message: qualitySafetyMessage
            )
            return nil
        }

        if tasks[taskIndex].status == .todo {
            guard !isWIPLimitReached(for: .inProgress, excluding: taskID) else {
                let limit = wipLimits[.inProgress] ?? 0
                lastBoardMessage = message("WIP limit reached for In Progress (%d)", limit)
                lastBoardMessageSeverity = .warning
                return nil
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
        taskExecutor.clearCancellation(taskID: taskID)
        taskExecutionApprovalsByTaskID[taskID] = nil
        consumeExecutionQuota(for: tasks[taskIndex])
        appendAgentExecutionEvent(
            agentID: agent.id,
            taskID: taskID,
            taskTitle: tasks[taskIndex].title,
            status: .running,
            phase: .lifecycle,
            message: message("Started execution · %@", tasks[taskIndex].title),
            details: message("Story points: %d", tasks[taskIndex].storyPoints)
        )

        let taskSnapshot = taskSnapshotWithSharedMemoryContext(tasks[taskIndex], agent: agent)
        return PreparedTaskExecution(
            taskID: taskID,
            taskSnapshot: taskSnapshot,
            agent: agent
        )
    }

    private func moveTaskBackToTodoAfterFailureIfNeeded(taskIndex: Int) {
        guard tasks.indices.contains(taskIndex) else { return }
        if tasks[taskIndex].status == .inProgress {
            tasks[taskIndex].status = .todo
        }
    }

    private func finalizeTaskExecution(_ prepared: PreparedTaskExecution, outcome: AgentTaskExecutionOutcome) {
        guard let taskIndex = tasks.firstIndex(where: { $0.id == prepared.taskID }) else { return }
        let baselineRecord = tasks[taskIndex].executionRecord ?? TaskExecutionRecord(status: .running)
        let finishedAt = Date()

        switch outcome {
        case let .success(summary):
            let normalizedSummary = normalizeExecutionSummary(summary)
            if let normalizedSummary, let blockerMessage = blockedExecutionMessage(from: normalizedSummary) {
                var blockedRecord = baselineRecord
                blockedRecord.status = .failed
                blockedRecord.lastFinishedAt = finishedAt
                blockedRecord.lastOutputSummary = normalizedSummary
                blockedRecord.lastError = blockerMessage
                blockedRecord.lastDebugOutput = nil
                blockedRecord.lastAgentID = prepared.agent.id
                tasks[taskIndex].executionRecord = blockedRecord
                moveTaskBackToTodoAfterFailureIfNeeded(taskIndex: taskIndex)
                lastExecutionDebugLog = nil
                lastCodexLoginCommand = nil
                lastBoardMessage = blockerMessage
                lastBoardMessageSeverity = .warning
                appendAgentExecutionEvent(
                    agentID: prepared.agent.id,
                    taskID: prepared.taskID,
                    taskTitle: tasks[taskIndex].title,
                    status: .failed,
                    phase: .result,
                    message: blockerMessage,
                    details: normalizedSummary
                )
                rememberExecutionOutcomeInSharedMemory(
                    task: tasks[taskIndex],
                    agent: prepared.agent,
                    status: .failed,
                    summary: normalizedSummary,
                    source: .executionFailed
                )
                triggerPMExtensionHooks(
                    event: .runFinished,
                    task: tasks[taskIndex],
                    additionalInputs: ["runStatus": "failed", "failureType": "blocked"]
                )
            } else if let normalizedSummary,
                      let blockerMessage = deliveryGateBlockMessage(for: tasks[taskIndex], normalizedSummary: normalizedSummary) {
                var blockedRecord = baselineRecord
                blockedRecord.status = .failed
                blockedRecord.lastFinishedAt = finishedAt
                blockedRecord.lastOutputSummary = normalizedSummary
                blockedRecord.lastError = blockerMessage
                blockedRecord.lastDebugOutput = nil
                blockedRecord.lastAgentID = prepared.agent.id
                tasks[taskIndex].executionRecord = blockedRecord
                moveTaskBackToTodoAfterFailureIfNeeded(taskIndex: taskIndex)
                lastExecutionDebugLog = nil
                lastCodexLoginCommand = nil
                lastBoardMessage = blockerMessage
                lastBoardMessageSeverity = .warning
                appendAgentExecutionEvent(
                    agentID: prepared.agent.id,
                    taskID: prepared.taskID,
                    taskTitle: tasks[taskIndex].title,
                    status: .failed,
                    phase: .governance,
                    message: blockerMessage,
                    details: normalizedSummary
                )
                rememberExecutionOutcomeInSharedMemory(
                    task: tasks[taskIndex],
                    agent: prepared.agent,
                    status: .failed,
                    summary: normalizedSummary,
                    source: .executionFailed
                )
                triggerPMExtensionHooks(
                    event: .runFinished,
                    task: tasks[taskIndex],
                    additionalInputs: ["runStatus": "failed", "failureType": "delivery-gate"]
                )
            } else {
                var finishedRecord = baselineRecord
                finishedRecord.status = .succeeded
                finishedRecord.lastFinishedAt = finishedAt
                finishedRecord.lastOutputSummary = normalizedSummary
                finishedRecord.lastError = nil
                finishedRecord.lastDebugOutput = nil
                finishedRecord.lastAgentID = prepared.agent.id
                tasks[taskIndex].executionRecord = finishedRecord
                lastExecutionDebugLog = nil
                lastCodexLoginCommand = nil

                if tasks[taskIndex].status == .inProgress {
                    if isWIPLimitReached(for: .review, excluding: prepared.taskID) {
                        let limit = wipLimits[.review] ?? 0
                        lastBoardMessage = message("Execution completed, but Review WIP limit reached (%d)", limit)
                        lastBoardMessageSeverity = .warning
                    } else {
                        tasks[taskIndex].status = .review
                        triggerPMExtensionHooks(event: .reviewEntered, task: tasks[taskIndex])
                        lastBoardMessage = message("Execution succeeded: %@", tasks[taskIndex].title)
                        lastBoardMessageSeverity = .info
                    }
                } else {
                    lastBoardMessage = message("Execution succeeded: %@", tasks[taskIndex].title)
                    lastBoardMessageSeverity = .info
                }
                appendAgentExecutionEvent(
                    agentID: prepared.agent.id,
                    taskID: prepared.taskID,
                    taskTitle: tasks[taskIndex].title,
                    status: .succeeded,
                    phase: .result,
                    message: message("Execution succeeded · %@", tasks[taskIndex].title),
                    details: normalizedSummary
                )
                rememberExecutionOutcomeInSharedMemory(
                    task: tasks[taskIndex],
                    agent: prepared.agent,
                    status: .succeeded,
                    summary: normalizedSummary ?? message("Execution succeeded"),
                    source: .executionSucceeded
                )
                triggerPMExtensionHooks(
                    event: .runFinished,
                    task: tasks[taskIndex],
                    additionalInputs: ["runStatus": "succeeded"]
                )
            }

        case let .failure(message):
            var failedRecord = baselineRecord
            let parsedFailure = parseExecutionFailure(message)
            failedRecord.status = .failed
            failedRecord.lastFinishedAt = finishedAt
            failedRecord.lastOutputSummary = nil
            failedRecord.lastError = normalizeExecutionText(parsedFailure.userMessage) ?? self.message("Unknown execution error")
            failedRecord.lastDebugOutput = normalizeExecutionText(parsedFailure.debugLog)
            failedRecord.lastAgentID = prepared.agent.id
            tasks[taskIndex].executionRecord = failedRecord
            moveTaskBackToTodoAfterFailureIfNeeded(taskIndex: taskIndex)
            lastExecutionDebugLog = failedRecord.lastDebugOutput
            lastCodexLoginCommand = extractCodexLoginCommand(
                from: failedRecord.lastError,
                debugLog: failedRecord.lastDebugOutput
            )
            lastBoardMessage = self.message("Execution failed: %@", failedRecord.lastError ?? self.message("Unknown execution error"))
            lastBoardMessageSeverity = .warning
            let eventDetails: String?
            if let debug = failedRecord.lastDebugOutput, !debug.isEmpty {
                eventDetails = self.message("Debug:\n%@", debug)
            } else {
                eventDetails = nil
            }
            appendAgentExecutionEvent(
                agentID: prepared.agent.id,
                taskID: prepared.taskID,
                taskTitle: tasks[taskIndex].title,
                status: .failed,
                phase: .result,
                message: failedRecord.lastError ?? self.message("Unknown execution error"),
                details: eventDetails
            )
            rememberExecutionOutcomeInSharedMemory(
                task: tasks[taskIndex],
                agent: prepared.agent,
                status: .failed,
                summary: failedRecord.lastError,
                source: .executionFailed
            )
            triggerPMExtensionHooks(
                event: .runFinished,
                task: tasks[taskIndex],
                additionalInputs: ["runStatus": "failed", "failureType": "executor"]
            )
        }

        persistBoardState()
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

    private func blockedExecutionMessage(from summary: String) -> String? {
        let normalized = summary.lowercased()
        let missingDetailsSignals = [
            "no implementation details",
            "acceptance criteria were provided",
            "acceptance criteria provided",
            "insufficient implementation details",
            "missing task details",
            "could not proceed beyond intake",
            "unable to proceed"
        ]
        guard missingDetailsSignals.contains(where: { normalized.contains($0) }) else {
            return nil
        }
        return self.message("Execution blocked: missing task details or acceptance criteria")
    }

    private func deliveryGateBlockMessage(for task: WorkTask, normalizedSummary: String) -> String? {
        let contract = task.resolvedDeliveryContract
        guard contract.gateMode == .strict else { return nil }
        let evidence = detectedDeliveryArtifacts(from: normalizedSummary)
        let required = contract.requiredArtifacts

        let passed: Bool
        switch contract.artifactRule {
        case .all:
            passed = required.isSubset(of: evidence)
        case .any:
            passed = !required.intersection(evidence).isEmpty
        }
        guard !passed else { return nil }

        let missingArtifacts: [TaskDeliveryArtifact]
        switch contract.artifactRule {
        case .all:
            missingArtifacts = required.subtracting(evidence)
                .sorted { $0.rawValue < $1.rawValue }
        case .any:
            missingArtifacts = required
                .sorted { $0.rawValue < $1.rawValue }
        }
        let expected = missingArtifacts.map(\.title).joined(separator: ", ")
        return message("Delivery gate blocked: missing evidence for %@", expected)
    }

    private func detectedDeliveryArtifacts(from normalizedSummary: String) -> Set<TaskDeliveryArtifact> {
        let lowered = normalizedSummary.lowercased()
        var artifacts: Set<TaskDeliveryArtifact> = [.summary]
        if !normalizedSummary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            artifacts.insert(.report)
        }
        if hasEvidence(
            in: lowered,
            positive: ["files:", "file:", "檔案:", "文件:", ".swift", ".kt", ".js", ".ts", ".py", ".md", ".xcodeproj", ".xcworkspace", ".zip"],
            negative: ["files: none", "file: none", "檔案: 無", "文件: 無", "files: n/a", "file: n/a"]
        ) {
            artifacts.insert(.files)
        }
        if hasEvidence(
            in: lowered,
            positive: ["commands:", "command:", "指令:", "命令:", "xcodebuild", "swift test", "npm run", "pnpm ", "yarn ", "make ", "cargo ", "./"],
            negative: ["commands: none", "command: none", "指令: 無", "命令: 無", "commands: n/a", "command: n/a"]
        ) {
            artifacts.insert(.commands)
        }
        if hasEvidence(
            in: lowered,
            positive: ["test", "tests", "測試", "coverage", "covered", "passed", "all green", "green"],
            negative: ["no tests", "tests: none", "測試: 無", "測試覆蓋: 無", "without tests"]
        ) {
            artifacts.insert(.tests)
        }
        if hasEvidence(
            in: lowered,
            positive: ["image", "images", "screenshot", "png", "jpg", "jpeg", "webp", "heic", "圖片", "截圖"],
            negative: ["image: none", "images: none", "圖片: 無", "截圖: 無"]
        ) {
            artifacts.insert(.images)
        }
        return artifacts
    }

    private func hasEvidence(in normalizedText: String, positive: [String], negative: [String]) -> Bool {
        let hasPositive = positive.contains(where: { normalizedText.contains($0) })
        guard hasPositive else { return false }
        return !negative.contains(where: { normalizedText.contains($0) })
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

    private func markRunningExecutionsAsInterruptedIfNeeded() {
        guard executionCheckpoint != nil else { return }

        var hasInterruptedRunningExecution = false
        for taskIndex in tasks.indices {
            guard var record = tasks[taskIndex].executionRecord,
                  record.status == .running else {
                continue
            }

            hasInterruptedRunningExecution = true
            record.status = .failed
            record.lastFinishedAt = Date()
            if (record.lastError ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                record.lastError = message("Execution interrupted by app restart. Resume interrupted run to continue.")
            }
            tasks[taskIndex].executionRecord = record
            if tasks[taskIndex].status == .inProgress {
                tasks[taskIndex].status = .todo
            }

            if let agentID = record.lastAgentID ?? tasks[taskIndex].assignedAgentID {
                appendAgentExecutionEvent(
                    agentID: agentID,
                    taskID: tasks[taskIndex].id,
                    taskTitle: tasks[taskIndex].title,
                    status: .failed,
                    phase: .system,
                    message: record.lastError ?? message("Execution interrupted by app restart. Resume interrupted run to continue.")
                )
            }
        }

        guard hasInterruptedRunningExecution else { return }
        lastBoardMessage = message("Detected interrupted execution. Use Resume Interrupted Run to continue.")
        lastBoardMessageSeverity = .warning
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
        boards[selectedBoardIndex].sharedAgentMemory = sharedAgentMemory
        boards[selectedBoardIndex].pmExtensionHookBindings = pmBoardExtensionHookBindings
        boards[selectedBoardIndex].executionRealArtifactVerificationPolicy =
            selectedBoardUsesDefaultRealArtifactVerificationPolicy
            ? nil
            : executionRealArtifactVerificationPolicy
    }

    private func pruneExecutionGovernanceStateForExistingTasks() {
        let validTaskIDs = Set(boards.flatMap { $0.tasks.map(\.id) })
        taskExecutionApprovalsByTaskID = taskExecutionApprovalsByTaskID.filter { validTaskIDs.contains($0.key) }
        executionTimelineByTaskID = executionTimelineByTaskID.filter { validTaskIDs.contains($0.key) }
    }

    private func loadBoard(_ boardID: UUID) {
        guard let index = boards.firstIndex(where: { $0.id == boardID }) else { return }
        let board = boards[index]
        selectedBoardID = board.id
        tasks = board.tasks
        agents = board.agents
        wipLimits = board.wipLimits
        selectedBoardUsesDefaultRealArtifactVerificationPolicy =
            board.executionRealArtifactVerificationPolicy == nil
        executionRealArtifactVerificationPolicy =
            board.executionRealArtifactVerificationPolicy ?? executionRealArtifactVerificationDefaultPolicy
        sharedAgentMemory = board.sharedAgentMemory ?? []
        pmBoardExtensionHookBindings = Self.normalizedBoardExtensionHookBindings(board.pmExtensionHookBindings ?? [])
        if syncSystemRealArtifactVerificationBoardHookBinding() {
            syncCurrentBoardRecord()
            persistBoardState()
        }
        lastUnassignedTaskIDs = Set(tasks.filter { $0.status == .todo && $0.assignedAgentID == nil }.map(\.id))
        lastAssignmentReasons = [:]
        lastBoardMessage = nil
        lastBoardMessageSeverity = nil
        lastExecutionDebugLog = nil
        lastCodexLoginCommand = nil
        agentExecutionEventsByAgentID = [:]
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
            wipLimits: resolvedWIPLimits,
            executionRealArtifactVerificationPolicy: board.executionRealArtifactVerificationPolicy,
            sharedAgentMemory: (board.sharedAgentMemory ?? []).filter {
                !$0.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            },
            pmExtensionHookBindings: Self.normalizedBoardExtensionHookBindings(board.pmExtensionHookBindings ?? [])
        )
    }

    private static func normalizedBoardExtensionHookBindings(
        _ bindings: [PMBoardExtensionHookBinding]
    ) -> [PMBoardExtensionHookBinding] {
        var seen = Set<String>()
        var normalized: [PMBoardExtensionHookBinding] = []

        for binding in bindings {
            let pluginID = binding.pluginID.trimmingCharacters(in: .whitespacesAndNewlines)
            let commandID = binding.commandID.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !pluginID.isEmpty, !commandID.isEmpty else { continue }

            let key = "\(binding.event.rawValue)|\(pluginID.lowercased())|\(commandID.lowercased())"
            guard seen.insert(key).inserted else { continue }

            normalized.append(
                PMBoardExtensionHookBinding(
                    id: binding.id,
                    event: binding.event,
                    pluginID: pluginID,
                    commandID: commandID,
                    isEnabled: binding.isEnabled,
                    createdAt: binding.createdAt
                )
            )
        }

        return normalized.sorted { lhs, rhs in
            if lhs.createdAt == rhs.createdAt {
                if lhs.event.rawValue == rhs.event.rawValue {
                    if lhs.pluginID.caseInsensitiveCompare(rhs.pluginID) == .orderedSame {
                        return lhs.commandID.localizedCaseInsensitiveCompare(rhs.commandID) == .orderedAscending
                    }
                    return lhs.pluginID.localizedCaseInsensitiveCompare(rhs.pluginID) == .orderedAscending
                }
                return lhs.event.rawValue < rhs.event.rawValue
            }
            return lhs.createdAt < rhs.createdAt
        }
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

    private func mergedTaskTemplates(current: [TaskTemplate], imported: [TaskTemplate]) -> [TaskTemplate] {
        var merged = current
        var usedNames = Set(current.map { $0.name.lowercased() })
        for template in imported {
            let normalizedName = template.name.lowercased()
            guard !usedNames.contains(normalizedName) else { continue }
            merged.append(template)
            usedNames.insert(normalizedName)
        }
        return merged.sorted { lhs, rhs in
            lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
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
            items.append((message("Unassigned To Do"), unassignedPenalty))
        }

        let overloadedPenalty = min(30, overloadedAgentCount * 10)
        if overloadedPenalty > 0 {
            items.append((message("Overloaded Agents"), overloadedPenalty))
        }

        if wipPressurePercent(for: .inProgress) >= 100 {
            items.append((message("In Progress WIP Pressure"), 10))
        }

        if wipPressurePercent(for: .review) >= 100 {
            items.append((message("Review WIP Pressure"), 10))
        }

        if doneTaskCount > 0 {
            items.append((message("Done Backlog"), 5))
        }

        return items
    }

    private func persistBoardState() {
        guard let boardStore else { return }
        syncCurrentBoardRecord()
        pruneExecutionGovernanceStateForExistingTasks()
        let snapshot = KanbanBoardSnapshot(
            tasks: tasks,
            agents: agents,
            wipLimits: wipLimits,
            boards: boards,
            selectedBoardID: selectedBoardID,
            taskTemplates: taskTemplates,
            executionAutoRetryConfiguration: executionAutoRetryConfiguration,
            executionCheckpoint: executionCheckpoint,
            executionApprovalPolicy: executionApprovalPolicy,
            taskExecutionApprovalsByTaskID: taskExecutionApprovalsByTaskID,
            executionQuotaPolicy: executionQuotaPolicy,
            executionQuotaUsage: executionQuotaUsage,
            executionParallelizationPolicy: executionParallelizationPolicy,
            gitHubPRQualityGatePolicy: gitHubPRQualityGatePolicy,
            dagExecutionPolicy: dagExecutionPolicy,
            executionQualitySafetyGatePolicy: executionQualitySafetyGatePolicy,
            executionRealArtifactVerificationPolicy: executionRealArtifactVerificationDefaultPolicy,
            mcpServerPolicy: mcpServerPolicy,
            pmPlannerEngineMode: pmPlannerEngineMode,
            pmPlanningPluginPolicy: pmPlanningPluginPolicy,
            sharedAgentMemory: sharedAgentMemory,
            sharedAgentMemoryProviderMode: sharedAgentMemoryProviderMode,
            sharedAgentMemoryPreferredProviderID: sharedAgentMemoryPreferredProviderID,
            sharedAgentMemoryMutedProviderIDs: Array(sharedAgentMemoryMutedProviderIDs).sorted()
        )
        try? boardStore.save(snapshot)
    }
}

extension KanbanBoardViewModel {
    static func persistentBoard(
        boardStore: KanbanBoardStore = FileKanbanBoardStore(),
        assignmentEngine: AutoAssignmentEngine = AutoAssignmentEngine(),
        projectPlanner: any ProjectPlanning = ExtensibleProjectPlanner(),
        taskExecutor: any AgentTaskExecuting = DefaultAgentTaskExecutor(),
        projectsDirectoryPathProvider: @escaping () -> String = {
            CodexProjectsDirectorySettings.resolvedProjectsDirectoryPath()
        },
        gitCommandRunner: @escaping GitCommandRunner = GitHubPRFlowUseCase.runSystemCommand,
        runOnBackground: @escaping ExecutionDispatcher = { work in
            DispatchQueue.global(qos: .userInitiated).async(execute: work)
        },
        runOnMain: @escaping ExecutionDispatcher = { work in
            DispatchQueue.main.async(execute: work)
        }
    ) -> KanbanBoardViewModel {
        if let snapshot = try? boardStore.load() {
            if let boards = snapshot.boards, !boards.isEmpty {
                let resolvedSelectedBoardID = snapshot.selectedBoardID ?? boards[0].id
                return KanbanBoardViewModel(
                    boards: boards,
                    selectedBoardID: resolvedSelectedBoardID,
                    taskTemplates: snapshot.taskTemplates,
                    executionAutoRetryConfiguration: snapshot.executionAutoRetryConfiguration ?? .init(),
                    executionCheckpoint: snapshot.executionCheckpoint,
                    executionApprovalPolicy: snapshot.executionApprovalPolicy ?? .init(),
                    taskExecutionApprovalsByTaskID: snapshot.taskExecutionApprovalsByTaskID ?? [:],
                    executionQuotaPolicy: snapshot.executionQuotaPolicy ?? .init(),
                    executionQuotaUsage: snapshot.executionQuotaUsage ?? .init(),
                    executionParallelizationPolicy: snapshot.executionParallelizationPolicy ?? .init(),
                    gitHubPRQualityGatePolicy: snapshot.gitHubPRQualityGatePolicy ?? .init(),
                    dagExecutionPolicy: snapshot.dagExecutionPolicy ?? .init(),
                    executionQualitySafetyGatePolicy: snapshot.executionQualitySafetyGatePolicy ?? .init(),
                    executionRealArtifactVerificationPolicy: snapshot.executionRealArtifactVerificationPolicy ?? .init(),
                    mcpServerPolicy: snapshot.mcpServerPolicy ?? .init(),
                    pmPlannerEngineMode: snapshot.pmPlannerEngineMode ?? .builtIn,
                    pmPlanningPluginPolicy: snapshot.pmPlanningPluginPolicy ?? .init(),
                    sharedAgentMemoryProviderMode: snapshot.sharedAgentMemoryProviderMode ?? .coreOnly,
                    sharedAgentMemoryPreferredProviderID: snapshot.sharedAgentMemoryPreferredProviderID,
                    sharedAgentMemoryMutedProviderIDs: Set((snapshot.sharedAgentMemoryMutedProviderIDs ?? []).compactMap(Self.normalizedProviderDescriptorID)),
                    projectsDirectoryPathProvider: projectsDirectoryPathProvider,
                    assignmentEngine: assignmentEngine,
                    projectPlanner: projectPlanner,
                    taskExecutor: taskExecutor,
                    boardStore: boardStore,
                    gitCommandRunner: gitCommandRunner,
                    runOnBackground: runOnBackground,
                    runOnMain: runOnMain
                )
            }
            return KanbanBoardViewModel(
                tasks: snapshot.tasks,
                agents: snapshot.agents,
                wipLimits: snapshot.wipLimits,
                taskTemplates: snapshot.taskTemplates,
                executionAutoRetryConfiguration: snapshot.executionAutoRetryConfiguration ?? .init(),
                executionCheckpoint: snapshot.executionCheckpoint,
                executionApprovalPolicy: snapshot.executionApprovalPolicy ?? .init(),
                taskExecutionApprovalsByTaskID: snapshot.taskExecutionApprovalsByTaskID ?? [:],
                executionQuotaPolicy: snapshot.executionQuotaPolicy ?? .init(),
                executionQuotaUsage: snapshot.executionQuotaUsage ?? .init(),
                executionParallelizationPolicy: snapshot.executionParallelizationPolicy ?? .init(),
                gitHubPRQualityGatePolicy: snapshot.gitHubPRQualityGatePolicy ?? .init(),
                dagExecutionPolicy: snapshot.dagExecutionPolicy ?? .init(),
                executionQualitySafetyGatePolicy: snapshot.executionQualitySafetyGatePolicy ?? .init(),
                executionRealArtifactVerificationPolicy: snapshot.executionRealArtifactVerificationPolicy ?? .init(),
                mcpServerPolicy: snapshot.mcpServerPolicy ?? .init(),
                pmPlannerEngineMode: snapshot.pmPlannerEngineMode ?? .builtIn,
                pmPlanningPluginPolicy: snapshot.pmPlanningPluginPolicy ?? .init(),
                sharedAgentMemory: snapshot.sharedAgentMemory ?? [],
                sharedAgentMemoryProviderMode: snapshot.sharedAgentMemoryProviderMode ?? .coreOnly,
                sharedAgentMemoryPreferredProviderID: snapshot.sharedAgentMemoryPreferredProviderID,
                sharedAgentMemoryMutedProviderIDs: Set((snapshot.sharedAgentMemoryMutedProviderIDs ?? []).compactMap(Self.normalizedProviderDescriptorID)),
                projectsDirectoryPathProvider: projectsDirectoryPathProvider,
                assignmentEngine: assignmentEngine,
                projectPlanner: projectPlanner,
                taskExecutor: taskExecutor,
                boardStore: boardStore,
                gitCommandRunner: gitCommandRunner,
                runOnBackground: runOnBackground,
                runOnMain: runOnMain
            )
        }
        return demoBoard(
            boardStore: boardStore,
            assignmentEngine: assignmentEngine,
            projectPlanner: projectPlanner,
            taskExecutor: taskExecutor,
            projectsDirectoryPathProvider: projectsDirectoryPathProvider,
            gitCommandRunner: gitCommandRunner,
            runOnBackground: runOnBackground,
            runOnMain: runOnMain
        )
    }

    static func demoBoard(
        boardStore: KanbanBoardStore? = nil,
        assignmentEngine: AutoAssignmentEngine = AutoAssignmentEngine(),
        projectPlanner: any ProjectPlanning = ExtensibleProjectPlanner(),
        taskExecutor: any AgentTaskExecuting = DefaultAgentTaskExecutor(),
        projectsDirectoryPathProvider: @escaping () -> String = {
            CodexProjectsDirectorySettings.resolvedProjectsDirectoryPath()
        },
        gitCommandRunner: @escaping GitCommandRunner = GitHubPRFlowUseCase.runSystemCommand,
        runOnBackground: @escaping ExecutionDispatcher = { work in
            DispatchQueue.global(qos: .userInitiated).async(execute: work)
        },
        runOnMain: @escaping ExecutionDispatcher = { work in
            DispatchQueue.main.async(execute: work)
        }
    ) -> KanbanBoardViewModel {
        let demoData = demoSeedData()
        return KanbanBoardViewModel(
            tasks: demoData.tasks,
            agents: demoData.agents,
            projectsDirectoryPathProvider: projectsDirectoryPathProvider,
            assignmentEngine: assignmentEngine,
            projectPlanner: projectPlanner,
            taskExecutor: taskExecutor,
            boardStore: boardStore,
            gitCommandRunner: gitCommandRunner,
            runOnBackground: runOnBackground,
            runOnMain: runOnMain
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

#if DEBUG
private extension DefaultAgentTaskExecutor {
    func testCodexBridgePrompt(task: WorkTask, agent: AgentProfile) -> String {
        buildCodexBridgePrompt(task: task, agent: agent, environment: environmentProvider())
    }

    func testResolvedEndpoint(configuredEndpoint: String?, environment: [String: String]) -> String {
        resolvedEndpoint(configuredEndpoint: configuredEndpoint, environment: environment)
    }

    static func testExecutorErrorDescriptions(serverMessage: String) -> [String] {
        [
            ExecutorError.timeout.errorDescription ?? "",
            ExecutorError.invalidResponse.errorDescription ?? "",
            ExecutorError.emptyResponse.errorDescription ?? "",
            ExecutorError.serverError(serverMessage).errorDescription ?? "",
            ExecutorError.codexBridgeFailed(serverMessage).errorDescription ?? ""
        ]
    }

    static func testSummarizeCodexBridgeFailure(_ rawFailure: String) -> String {
        summarizeCodexBridgeFailure(rawFailure)
    }

    static func testIsCodexChatGPTModelUnsupported(_ rawFailure: String) -> Bool {
        isCodexChatGPTModelUnsupported(rawFailure)
    }

    static func testIsCodexReasoningEffortUnsupported(_ rawFailure: String) -> Bool {
        isCodexReasoningEffortUnsupported(rawFailure)
    }

    static func testIsCodexUsageLimitError(_ rawFailure: String) -> Bool {
        isCodexUsageLimitError(rawFailure)
    }

    static func testResolvedCodexBridgeSandboxMode(environment: [String: String]) -> String? {
        resolvedCodexBridgeSandboxMode(environment: environment)
    }

    static func testCodexBridgeProcessEnvironment(environment: [String: String]) -> [String: String] {
        codexBridgeProcessEnvironment(environment: environment)
    }

    static func testCodexLoginCommandForCurrentProfile(
        environment: [String: String],
        homeDirectoryPath: String
    ) -> String {
        codexLoginCommandForCurrentProfile(environment: environment, homeDirectoryPath: homeDirectoryPath)
    }

    static func testResolvedCodexExecutableURL(
        environment: [String: String],
        fallbackCandidates: [String],
        homeDirectoryPath: String
    ) -> URL? {
        resolvedCodexExecutableURL(
            environment: environment,
            fallbackCandidates: fallbackCandidates,
            homeDirectoryPath: homeDirectoryPath
        )
    }

    static func testDefaultCodexBridgeRunner(
        request: CodexBridgeRequest,
        onProgress: @escaping (_ update: String) -> Void,
        environment: [String: String]
    ) throws -> String {
        try defaultCodexBridgeRunner(
            request: request,
            onProgress: onProgress,
            environment: environment
        )
    }

    static func testDefaultCodexBridgePreflight(environment: [String: String]) throws {
        try defaultCodexBridgePreflight(environment: environment)
    }

    static func testDefaultCodexBridgeRecovery(
        reason: String,
        onProgress: @escaping (_ update: String) -> Void,
        environment: [String: String],
        commandRunner: @escaping (
            _ executablePath: String,
            _ arguments: [String],
            _ environment: [String: String]
        ) throws -> (code: Int32, output: String),
        sleeper: @escaping (_ seconds: TimeInterval) -> Void
    ) throws {
        try defaultCodexBridgeRecovery(
            reason: reason,
            onProgress: onProgress,
            environment: environment,
            commandRunner: commandRunner,
            sleeper: sleeper
        )
    }

    static func testRunSystemCommand(
        executablePath: String,
        arguments: [String],
        environment: [String: String]
    ) throws -> (code: Int32, output: String) {
        try runSystemCommand(executablePath: executablePath, arguments: arguments, environment: environment)
    }
}

private extension KanbanBoardViewModel {
    static func testRunShellCommand(
        command: String,
        timeoutSeconds: Int,
        environment: [String: String]
    ) throws -> (code: Int32, output: String, timedOut: Bool) {
        try runShellCommand(
            command,
            timeoutSeconds: timeoutSeconds,
            environment: environment
        )
    }

    static func testPrepareWorktreeDirectoryForExecution(
        task: WorkTask,
        agent: AgentProfile,
        boardName: String,
        repositoryPath: String,
        boardScopedPath: String,
        branchPrefix: String,
        environment: [String: String]
    ) throws -> String {
        try prepareWorktreeDirectoryForExecution(
            task: task,
            agent: agent,
            boardName: boardName,
            repositoryPath: repositoryPath,
            boardScopedPath: boardScopedPath,
            branchPrefix: branchPrefix,
            environment: environment
        )
    }

    static func testWorktreeSlug(_ rawValue: String, fallback: String) -> String {
        worktreeSlug(rawValue, fallback: fallback)
    }

    static func testRepairedMCPBootstrapCommand(
        rawCommand: String,
        preferredServerName: String
    ) -> String {
        let viewModel = KanbanBoardViewModel(tasks: [], agents: [])
        return viewModel.repairedMCPBootstrapCommandIfNeeded(
            rawCommand: rawCommand,
            preferredServerName: preferredServerName
        )
    }

    static func testInferredMCPKeywordHints(name: String, description: String?) -> [String] {
        inferredKeywordHints(name: name, description: description)
    }

    static func testParseXcodeSchemes(fromListOutput output: String) -> [String] {
        let viewModel = KanbanBoardViewModel(tasks: [], agents: [])
        return viewModel.parseXcodeSchemes(fromListOutput: output)
    }

    static func testPreferredBuildScheme(from schemes: [String]) -> String? {
        let viewModel = KanbanBoardViewModel(tasks: [], agents: [])
        return viewModel.preferredBuildScheme(from: schemes)
    }

    static func testIsLikelyGitRemoteSource(_ source: String) -> Bool {
        isLikelyGitRemoteSource(source)
    }

    static func testNormalizedBoardExtensionHookBindings(
        _ bindings: [PMBoardExtensionHookBinding]
    ) -> [PMBoardExtensionHookBinding] {
        normalizedBoardExtensionHookBindings(bindings)
    }
}

enum KanbanBoardViewModelTestHooks {
    static func codexPrompt(
        languageOverrideRawValue: String?,
        task: WorkTask,
        agent: AgentProfile,
        environment: [String: String] = [:]
    ) -> String {
        let executor = DefaultAgentTaskExecutor(
            environmentProvider: { environment },
            urlSession: .shared,
            timeoutSeconds: 1,
            appLanguageOverrideProvider: { languageOverrideRawValue },
            codexBridgePreflight: {},
            codexBridgeRunner: { _, _ in "" },
            codexBridgeRecovery: { _, _ in }
        )
        return executor.testCodexBridgePrompt(task: task, agent: agent)
    }

    static func resolvedEndpoint(configuredEndpoint: String?, environment: [String: String]) -> String {
        let executor = DefaultAgentTaskExecutor(
            environmentProvider: { environment },
            urlSession: .shared,
            timeoutSeconds: 1
        )
        return executor.testResolvedEndpoint(configuredEndpoint: configuredEndpoint, environment: environment)
    }

    static func summarizeCodexBridgeFailure(_ rawFailure: String) -> String {
        DefaultAgentTaskExecutor.testSummarizeCodexBridgeFailure(rawFailure)
    }

    static func isCodexChatGPTModelUnsupported(_ rawFailure: String) -> Bool {
        DefaultAgentTaskExecutor.testIsCodexChatGPTModelUnsupported(rawFailure)
    }

    static func isCodexReasoningEffortUnsupported(_ rawFailure: String) -> Bool {
        DefaultAgentTaskExecutor.testIsCodexReasoningEffortUnsupported(rawFailure)
    }

    static func isCodexUsageLimitError(_ rawFailure: String) -> Bool {
        DefaultAgentTaskExecutor.testIsCodexUsageLimitError(rawFailure)
    }

    static func resolvedCodexBridgeSandboxMode(environment: [String: String]) -> String? {
        DefaultAgentTaskExecutor.testResolvedCodexBridgeSandboxMode(environment: environment)
    }

    static func codexBridgeProcessEnvironment(environment: [String: String]) -> [String: String] {
        DefaultAgentTaskExecutor.testCodexBridgeProcessEnvironment(environment: environment)
    }

    static func codexLoginCommand(environment: [String: String], homeDirectoryPath: String) -> String {
        DefaultAgentTaskExecutor.testCodexLoginCommandForCurrentProfile(
            environment: environment,
            homeDirectoryPath: homeDirectoryPath
        )
    }

    static func resolvedCodexExecutablePath(
        environment: [String: String],
        fallbackCandidates: [String],
        homeDirectoryPath: String
    ) -> String? {
        DefaultAgentTaskExecutor.testResolvedCodexExecutableURL(
            environment: environment,
            fallbackCandidates: fallbackCandidates,
            homeDirectoryPath: homeDirectoryPath
        )?.path
    }

    static func executorErrorDescriptions(serverMessage: String) -> [String] {
        DefaultAgentTaskExecutor.testExecutorErrorDescriptions(serverMessage: serverMessage)
    }

    static func runDefaultCodexBridgeRunner(
        request: DefaultAgentTaskExecutor.CodexBridgeRequest,
        onProgress: @escaping (_ update: String) -> Void,
        environment: [String: String]
    ) throws -> String {
        try DefaultAgentTaskExecutor.testDefaultCodexBridgeRunner(
            request: request,
            onProgress: onProgress,
            environment: environment
        )
    }

    static func runDefaultCodexBridgePreflight(environment: [String: String]) throws {
        try DefaultAgentTaskExecutor.testDefaultCodexBridgePreflight(environment: environment)
    }

    static func runDefaultCodexBridgeRecovery(
        reason: String,
        onProgress: @escaping (_ update: String) -> Void,
        environment: [String: String],
        commandRunner: @escaping (
            _ executablePath: String,
            _ arguments: [String],
            _ environment: [String: String]
        ) throws -> (code: Int32, output: String),
        sleeper: @escaping (_ seconds: TimeInterval) -> Void
    ) throws {
        try DefaultAgentTaskExecutor.testDefaultCodexBridgeRecovery(
            reason: reason,
            onProgress: onProgress,
            environment: environment,
            commandRunner: commandRunner,
            sleeper: sleeper
        )
    }

    static func runSystemCommand(
        executablePath: String,
        arguments: [String],
        environment: [String: String]
    ) throws -> (code: Int32, output: String) {
        try DefaultAgentTaskExecutor.testRunSystemCommand(
            executablePath: executablePath,
            arguments: arguments,
            environment: environment
        )
    }

    static func runShellCommand(
        command: String,
        timeoutSeconds: Int,
        environment: [String: String]
    ) throws -> (code: Int32, output: String, timedOut: Bool) {
        try KanbanBoardViewModel.testRunShellCommand(
            command: command,
            timeoutSeconds: timeoutSeconds,
            environment: environment
        )
    }

    static func prepareWorktreeDirectoryForExecution(
        task: WorkTask,
        agent: AgentProfile,
        boardName: String,
        repositoryPath: String,
        boardScopedPath: String,
        branchPrefix: String,
        environment: [String: String]
    ) throws -> String {
        try KanbanBoardViewModel.testPrepareWorktreeDirectoryForExecution(
            task: task,
            agent: agent,
            boardName: boardName,
            repositoryPath: repositoryPath,
            boardScopedPath: boardScopedPath,
            branchPrefix: branchPrefix,
            environment: environment
        )
    }

    static func worktreeSlug(_ rawValue: String, fallback: String) -> String {
        KanbanBoardViewModel.testWorktreeSlug(rawValue, fallback: fallback)
    }

    static func xcodeSelectRepairCommandIfNeeded(
        activeDeveloperDirectoryPath: String?,
        installedXcodeDeveloperDirectoryPath: String?
    ) -> String? {
        KanbanBoardViewModel.xcodeSelectRepairCommandIfNeeded(
            activeDeveloperDirectoryPath: activeDeveloperDirectoryPath,
            installedXcodeDeveloperDirectoryPath: installedXcodeDeveloperDirectoryPath
        )
    }

    static func parseXcodeBuildSettingValue(_ key: String, output: String) -> String? {
        KanbanBoardViewModel.parseXcodeBuildSettingValue(key, from: output)
    }

    static func verificationBuildOverrides(forSDKRoot sdkRoot: String?) -> (sdk: String?, destination: String?, modeLabel: String) {
        KanbanBoardViewModel.verificationBuildOverrides(forSDKRoot: sdkRoot)
    }

    static func repairedMCPBootstrapCommand(rawCommand: String, preferredServerName: String) -> String {
        KanbanBoardViewModel.testRepairedMCPBootstrapCommand(
            rawCommand: rawCommand,
            preferredServerName: preferredServerName
        )
    }

    static func inferredMCPKeywordHints(name: String, description: String?) -> [String] {
        KanbanBoardViewModel.testInferredMCPKeywordHints(name: name, description: description)
    }

    static func parseXcodeSchemes(fromListOutput output: String) -> [String] {
        KanbanBoardViewModel.testParseXcodeSchemes(fromListOutput: output)
    }

    static func preferredBuildScheme(from schemes: [String]) -> String? {
        KanbanBoardViewModel.testPreferredBuildScheme(from: schemes)
    }

    static func isLikelyGitRemoteSource(_ source: String) -> Bool {
        KanbanBoardViewModel.testIsLikelyGitRemoteSource(source)
    }

    static func normalizedBoardExtensionHookBindings(
        _ bindings: [PMBoardExtensionHookBinding]
    ) -> [PMBoardExtensionHookBinding] {
        KanbanBoardViewModel.testNormalizedBoardExtensionHookBindings(bindings)
    }
}
#endif
