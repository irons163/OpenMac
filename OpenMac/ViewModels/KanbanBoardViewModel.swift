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
}

extension AgentTaskExecuting {
    func execute(
        task: WorkTask,
        agent: AgentProfile,
        onProgress: @escaping (_ update: String) -> Void
    ) -> AgentTaskExecutionOutcome {
        execute(task: task, agent: agent)
    }
}

struct DefaultAgentTaskExecutor: AgentTaskExecuting {
    static let debugLogDelimiter = "\n\n--- debug ---\n"

    struct CodexBridgeRequest: Equatable {
        let prompt: String
        let model: String
        let profile: String?
        let workingDirectoryPath: String?
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
        let prompt = buildCodexBridgePrompt(task: task, agent: agent)
        let workingDirectoryPath = CodexProjectsDirectorySettings.resolvedProjectsDirectoryPath(
            environment: environmentProvider()
        )
        let request = CodexBridgeRequest(
            prompt: prompt,
            model: runtimeProfile.model,
            profile: runtimeProfile.codexProfile,
            workingDirectoryPath: workingDirectoryPath
        )
        let trimmedModel = runtimeProfile.model.trimmingCharacters(in: .whitespacesAndNewlines)
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

            // ChatGPT account login with Codex may reject some API models (for example gpt-4.1-mini).
            // Retry once without --model so Codex profile default can be used automatically.
            if !trimmedModel.isEmpty,
               Self.isCodexChatGPTModelUnsupported(initialRawFailure) {
                let fallbackRequest = CodexBridgeRequest(
                    prompt: prompt,
                    model: "",
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
        let userPrompt = executionPrompt(task: task, agent: agent, template: template)
        return [
            ChatMessage(role: "system", content: template.systemPrompt),
            ChatMessage(role: "user", content: userPrompt)
        ]
    }

    private func buildCodexBridgePrompt(task: WorkTask, agent: AgentProfile) -> String {
        let template = executionPromptTemplate()
        return executionPrompt(task: task, agent: agent, template: template)
    }

    private func executionPrompt(task: WorkTask, agent: AgentProfile, template: ExecutionPromptTemplate) -> String {
        let sortedSkills = task.requiredSkills.sorted().joined(separator: ", ")
        let skillsLine = sortedSkills.isEmpty ? template.noneSkillsText : sortedSkills
        let deliveryContract = task.resolvedDeliveryContract
        let expectedEvidence = deliveryContract.requiredArtifactsText.isEmpty
            ? "none"
            : deliveryContract.requiredArtifactsText
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

        \(template.sectionsInstruction)
        \(template.languageInstruction)
        \(template.summarySection)
        \(template.actionsSection)
        \(template.evidenceSection)
        \(template.risksSection)
        """
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
    @Published private(set) var mcpServerPolicy: MCPServerPolicy
    @Published private(set) var agentExecutionEventsByAgentID: [UUID: [AgentExecutionEvent]] = [:]
    @Published private(set) var executionTimelineByTaskID: [UUID: [AgentExecutionEvent]] = [:]

    private let assignmentEngine: AutoAssignmentEngine
    private let projectPlanner: any ProjectPlanning
    private let taskExecutor: any AgentTaskExecuting
    private let boardStore: KanbanBoardStore?
    private let runOnBackground: ExecutionDispatcher
    private let runOnMain: ExecutionDispatcher
    private let gitCommandRunner: GitCommandRunner
    private static let defaultBoardName = "Default Board"
    private static let maxAgentExecutionEventsPerAgent = 120
    private static let maxTaskTimelineEventsPerTask = 240
    private static let mcpRegistrySyncTTL: TimeInterval = 60 * 30
    private var mcpReadinessCacheByServerName: [String: Bool] = [:]

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
        mcpServerPolicy: MCPServerPolicy = .init(),
        assignmentEngine: AutoAssignmentEngine = AutoAssignmentEngine(),
        projectPlanner: any ProjectPlanning = RuleBasedProjectPlanner(),
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
        self.mcpServerPolicy = mcpServerPolicy
        self.assignmentEngine = assignmentEngine
        self.projectPlanner = projectPlanner
        self.taskExecutor = taskExecutor
        self.boardStore = boardStore
        self.gitCommandRunner = gitCommandRunner
        self.runOnBackground = runOnBackground
        self.runOnMain = runOnMain
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
        mcpServerPolicy: MCPServerPolicy = .init(),
        assignmentEngine: AutoAssignmentEngine = AutoAssignmentEngine(),
        projectPlanner: any ProjectPlanning = RuleBasedProjectPlanner(),
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
            resolvedBoard = KanbanBoardRecord(name: Self.defaultBoardName)
        }

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
        self.mcpServerPolicy = mcpServerPolicy
        self.assignmentEngine = assignmentEngine
        self.projectPlanner = projectPlanner
        self.taskExecutor = taskExecutor
        self.boardStore = boardStore
        self.gitCommandRunner = gitCommandRunner
        self.runOnBackground = runOnBackground
        self.runOnMain = runOnMain
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
                    mcpServerPolicy: mcpServerPolicy
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
                    mcpServerPolicy: mcpServerPolicy
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
                wipLimits: snapshot.wipLimits
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
            mcpServerPolicy = snapshot.mcpServerPolicy ?? .init()
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
            if let importedMCPPolicy = snapshot.mcpServerPolicy {
                mcpServerPolicy = importedMCPPolicy
                mcpReadinessCacheByServerName = [:]
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

        guard let plan = projectPlanner.generatePlan(
            projectName: projectName,
            projectBrief: trimmedBrief,
            availableAgents: agents
        ),
            !plan.tickets.isEmpty else {
            lastBoardMessage = message("PM planner could not generate actionable tickets")
            lastBoardMessageSeverity = .warning
            return nil
        }

        lastBoardMessage = nil
        return plan
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

        guard let blueprintPlanner = projectPlanner as? any ProjectBlueprintPlanning,
              let blueprint = blueprintPlanner.generateBlueprint(
                  projectName: projectName,
                  projectBrief: trimmedBrief,
                  availableAgents: agents
              ),
              !blueprint.tickets.isEmpty else {
            lastBoardMessage = message("PM planner could not generate actionable tickets")
            lastBoardMessageSeverity = .warning
            return nil
        }

        lastBoardMessage = nil
        return blueprint
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
        defaultMaxConcurrentTasks: Int = 3
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

            let created = addAgent(
                name: agentName,
                skillsText: skillsChunk.joined(separator: ", "),
                maxConcurrentTasks: maxTasks
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
            bootstrapCommand: trimmedBootstrapCommand,
            verificationCommand: "codex mcp get \(Self.shellQuoted(trimmedName)) --json",
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
        let verificationCommand = server.verificationCommand
            ?? "codex mcp get \(Self.shellQuoted(server.name)) --json"
        guard let result = try? Self.runShellCommand(verificationCommand) else {
            return false
        }
        guard result.code == 0 else {
            return false
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

        guard let result = try? Self.runShellCommand(bootstrapCommand) else {
            return (false, message("MCP bootstrap command failed to launch for %@", server.name))
        }
        guard result.code == 0 else {
            let reason = result.output.isEmpty ? "exit \(result.code)" : result.output
            return (false, message("MCP bootstrap failed for %@: %@", server.name, reason))
        }
        onProgress(message("MCP bootstrap completed: %@", server.name))
        return (true, result.output)
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
            let normalizedName = MCPServerDescriptor.normalizedServerName(name)
            guard !seen.contains(normalizedName) else { return nil }
            seen.insert(normalizedName)

            let bootstrapCommand = "codex mcp add \(shellQuoted(name)) --url \(shellQuoted(remoteURL))"
            let keywordHints = inferredKeywordHints(name: name, description: entry.server.description)
            return MCPServerDescriptor(
                name: name,
                bootstrapCommand: bootstrapCommand,
                verificationCommand: "codex mcp get \(shellQuoted(name)) --json",
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

    private static func runShellCommand(
        _ command: String,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> (code: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", command]
        process.environment = shellCommandEnvironment(environment)

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

        var outcome = taskExecutor.execute(task: task, agent: agent, onProgress: onProgress)
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
            outcome = taskExecutor.execute(task: task, agent: agent, onProgress: onProgress)
        }

        return ExecutionAttemptResult(outcome: outcome, retriesPerformed: retriesPerformed)
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
        if task.status == .review || task.status == .done {
            return true
        }
        if task.executionRecord?.status == .succeeded {
            return true
        }
        return false
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
            }
        )
    }

    func runAssignedTaskExecutionsInBackground(completion: @escaping (Int) -> Void) {
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
                self.runAssignedTaskExecutionsInBackground { started in
                    guard started == 0, resolvedAutoRelaxWIPLimits else {
                        completion(started)
                        return
                    }
                    let relaxedCount = self.autoRelaxWIPLimitsForAutoCycle()
                    guard relaxedCount > 0 else {
                        completion(started)
                        return
                    }
                    self.runAssignedTaskExecutionsInBackground(completion: completion)
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
    }

    func requestCancelAutoDispatchCycle() {
        isAutoCycleCancelRequested = true
        requestCancelAssignedTaskExecutions()
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
            lastBoardMessage = message("Only To Do tasks can be manually triaged")
            return false
        }
        guard tasks[taskIndex].assignedAgentID == nil else {
            lastBoardMessage = message("Task is already assigned")
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

        return PreparedTaskExecution(
            taskID: taskID,
            taskSnapshot: tasks[taskIndex],
            agent: agent
        )
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
            mcpServerPolicy: mcpServerPolicy
        )
        try? boardStore.save(snapshot)
    }
}

extension KanbanBoardViewModel {
    static func persistentBoard(
        boardStore: KanbanBoardStore = FileKanbanBoardStore(),
        assignmentEngine: AutoAssignmentEngine = AutoAssignmentEngine(),
        projectPlanner: any ProjectPlanning = RuleBasedProjectPlanner(),
        taskExecutor: any AgentTaskExecuting = DefaultAgentTaskExecutor(),
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
                    mcpServerPolicy: snapshot.mcpServerPolicy ?? .init(),
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
                mcpServerPolicy: snapshot.mcpServerPolicy ?? .init(),
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
            gitCommandRunner: gitCommandRunner,
            runOnBackground: runOnBackground,
            runOnMain: runOnMain
        )
    }

    static func demoBoard(
        boardStore: KanbanBoardStore? = nil,
        assignmentEngine: AutoAssignmentEngine = AutoAssignmentEngine(),
        projectPlanner: any ProjectPlanning = RuleBasedProjectPlanner(),
        taskExecutor: any AgentTaskExecuting = DefaultAgentTaskExecutor(),
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
        buildCodexBridgePrompt(task: task, agent: agent)
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

enum KanbanBoardViewModelTestHooks {
    static func codexPrompt(
        languageOverrideRawValue: String?,
        task: WorkTask,
        agent: AgentProfile
    ) -> String {
        let executor = DefaultAgentTaskExecutor(
            environmentProvider: { [:] },
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

    static func xcodeSelectRepairCommandIfNeeded(
        activeDeveloperDirectoryPath: String?,
        installedXcodeDeveloperDirectoryPath: String?
    ) -> String? {
        KanbanBoardViewModel.xcodeSelectRepairCommandIfNeeded(
            activeDeveloperDirectoryPath: activeDeveloperDirectoryPath,
            installedXcodeDeveloperDirectoryPath: installedXcodeDeveloperDirectoryPath
        )
    }
}
#endif
