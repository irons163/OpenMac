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
        let runtimeProfile = agent.runtimeProfile ?? AgentRuntimeProfile(provider: .localMock)
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
        return """
        \(template.preamble)
        \(template.agentLabel): \(agent.name)
        \(template.taskTitleLabel): \(task.title)
        \(template.taskDetailsLabel): \(task.details)
        \(template.requiredSkillsLabel): \(skillsLine)
        \(template.storyPointsLabel): \(task.storyPoints)

        \(template.sectionsInstruction)
        \(template.summarySection)
        \(template.actionsSection)
        \(template.evidenceSection)
        \(template.risksSection)
        """
    }

    private func executionPromptTemplate() -> ExecutionPromptTemplate {
        switch AppLanguageResolver.resolvedLanguage() {
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
                agentLabel: "Agent",
                taskTitleLabel: "任務標題",
                taskDetailsLabel: "任務細節",
                requiredSkillsLabel: "所需技能",
                storyPointsLabel: "故事點數",
                sectionsInstruction: "請用純文字並使用以下段落：",
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
                agentLabel: "Agent",
                taskTitleLabel: "任务标题",
                taskDetailsLabel: "任务细节",
                requiredSkillsLabel: "所需技能",
                storyPointsLabel: "故事点数",
                sectionsInstruction: "请用纯文本并使用以下段落：",
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
                agentLabel: "Agent",
                taskTitleLabel: "タスクタイトル",
                taskDetailsLabel: "タスク詳細",
                requiredSkillsLabel: "必要スキル",
                storyPointsLabel: "ストーリーポイント",
                sectionsInstruction: "次の見出しで簡潔なプレーンテキストを返してください:",
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
                agentLabel: "Agent",
                taskTitleLabel: "작업 제목",
                taskDetailsLabel: "작업 세부사항",
                requiredSkillsLabel: "필수 스킬",
                storyPointsLabel: "스토리 포인트",
                sectionsInstruction: "다음 섹션으로 간결한 일반 텍스트를 반환하세요:",
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
        onProgress: @escaping (_ update: String) -> Void
    ) throws -> String {
        guard let codexExecutable = resolvedCodexExecutableURL() else {
            throw ExecutorError.codexBridgeFailed(
                L10n.string("Codex CLI not found. Install Codex CLI (or Codex app), then retry. You can also switch OpenAI Auth to API Key.")
            )
        }

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("openmac-codex-bridge-\(UUID().uuidString).txt")
        defer {
            try? FileManager.default.removeItem(at: outputURL)
        }

        let sandboxMode = resolvedCodexBridgeSandboxMode()
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
        process.environment = codexBridgeProcessEnvironment()
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

        guard let item = json["item"] as? [String: Any] else {
            return nil
        }

        switch type {
        case "item.started":
            guard let itemType = item["type"] as? String else { return nil }
            if itemType == "command_execution",
               let command = item["command"] as? String,
               !command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return "Running command: \(command)"
            }
            return nil

        case "item.completed":
            guard let itemType = item["type"] as? String else { return nil }
            if itemType == "agent_message",
               let text = item["text"] as? String {
                let message = text.trimmingCharacters(in: .whitespacesAndNewlines)
                return message.isEmpty ? nil : message
            }

            if itemType == "command_execution" {
                var progressParts: [String] = []
                if let command = item["command"] as? String,
                   !command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    progressParts.append("Command completed: \(command)")
                }
                if let output = item["aggregated_output"] as? String,
                   !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    progressParts.append(summarizeCommandOutputForConsole(output))
                }
                return progressParts.isEmpty ? nil : progressParts.joined(separator: "\n")
            }
            return nil

        default:
            return nil
        }
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

    private static func defaultCodexBridgePreflight() throws {
        guard resolvedCodexExecutableURL() != nil else {
            throw ExecutorError.codexBridgeFailed(
                L10n.string("Codex CLI not found. Install Codex CLI (or Codex app), then retry. You can also switch OpenAI Auth to API Key.")
            )
        }

        let loginStatus = try runCodex(arguments: ["login", "status"])
        let normalized = loginStatus.output.lowercased()
        guard loginStatus.code == 0, normalized.contains("logged in") else {
            let loginCommand = codexLoginCommandForCurrentProfile()
            throw ExecutorError.codexBridgeFailed(
                L10n.format("Codex Bridge profile is not logged in. Run this once in Terminal: %@", loginCommand)
            )
        }
    }

    private static func defaultCodexBridgeRecovery(
        reason: String,
        onProgress: @escaping (_ update: String) -> Void
    ) throws {
        onProgress(L10n.string("Codex usage limit detected. Restarting Codex app..."))

        _ = try? runSystemCommand(
            executablePath: "/usr/bin/osascript",
            arguments: ["-e", "tell application \"Codex\" to quit"]
        )

        Thread.sleep(forTimeInterval: 1.0)

        let launch = try runSystemCommand(
            executablePath: "/usr/bin/open",
            arguments: ["-a", "Codex"]
        )
        guard launch.code == 0 else {
            let output = launch.output.isEmpty ? L10n.format("open exited with code %d", launch.code) : launch.output
            throw ExecutorError.codexBridgeFailed(L10n.format("Codex app restart failed: %@", output))
        }

        Thread.sleep(forTimeInterval: 1.5)
        onProgress(L10n.string("Codex app restart complete. Resuming task..."))
    }

    private static func runCodex(arguments: [String]) throws -> (code: Int32, output: String) {
        guard let executableURL = resolvedCodexExecutableURL() else {
            throw ExecutorError.codexBridgeFailed(
                L10n.string("Codex CLI not found. Install Codex CLI (or Codex app), then retry. You can also switch OpenAI Auth to API Key.")
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

    private static func runSystemCommand(
        executablePath: String,
        arguments: [String]
    ) throws -> (code: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
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

    private static func resolvedCodexBridgeSandboxMode() -> String? {
        let rawOverride = ProcessInfo.processInfo.environment["OPENMAC_CODEX_SANDBOX"]?
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

struct AgentExecutionEvent: Identifiable, Equatable {
    let id: UUID
    let timestamp: Date
    let agentID: UUID
    let taskID: UUID
    let taskTitle: String
    let status: TaskExecutionStatus
    let message: String
    let details: String?

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        agentID: UUID,
        taskID: UUID,
        taskTitle: String,
        status: TaskExecutionStatus,
        message: String,
        details: String? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.agentID = agentID
        self.taskID = taskID
        self.taskTitle = taskTitle
        self.status = status
        self.message = message
        self.details = details
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
    @Published private(set) var agentExecutionEventsByAgentID: [UUID: [AgentExecutionEvent]] = [:]

    private let assignmentEngine: AutoAssignmentEngine
    private let taskExecutor: any AgentTaskExecuting
    private let boardStore: KanbanBoardStore?
    private static let defaultBoardName = "Default Board"
    private static let maxAgentExecutionEventsPerAgent = 120

    private func message(_ key: String) -> String {
        L10n.string(key)
    }

    private func message(_ key: String, _ arguments: CVarArg...) -> String {
        L10n.format(key, locale: nil, arguments: arguments)
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
                    selectedBoardID: selectedBoardID
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
                    selectedBoardID: selectedBoard.id
                )
            )
        } catch {
            lastBoardMessage = message("Failed to export board")
            return nil
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
            agents: agents
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
    func applyAllHealthRecommendations() -> Int {
        let actions = healthRecommendations().map(\.action)
        var appliedCount = 0

        for action in actions where action.isAutoFixable {
            if applyHealthRecommendation(action) {
                appliedCount += 1
            }
        }

        if appliedCount > 0 {
            lastBoardMessage = message("Applied %d health recommendation(s)", appliedCount)
            lastBoardMessageSeverity = .info
        } else if !actions.isEmpty {
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

    func clearExecutionEvents(for agentID: UUID) {
        agentExecutionEventsByAgentID[agentID] = []
    }

    func isAgentExecutionRunning(_ agentID: UUID) -> Bool {
        tasks.contains { task in
            guard task.executionRecord?.status == .running else { return false }
            return task.executionRecord?.lastAgentID == agentID || task.assignedAgentID == agentID
        }
    }

    private struct PreparedTaskExecution {
        let taskID: UUID
        let taskSnapshot: WorkTask
        let agent: AgentProfile
    }

    @discardableResult
    func runTaskExecution(_ taskID: UUID) -> Bool {
        guard let prepared = prepareTaskExecution(taskID, requiresTaskDetails: true) else {
            return false
        }
        let outcome = taskExecutor.execute(task: prepared.taskSnapshot, agent: prepared.agent) { update in
            self.captureExecutionProgress(update, for: prepared)
        }
        finalizeTaskExecution(prepared, outcome: outcome)
        return true
    }

    func runTaskExecutionInBackground(_ taskID: UUID, completion: @escaping (Bool) -> Void) {
        guard let prepared = prepareTaskExecution(taskID, requiresTaskDetails: true) else {
            completion(false)
            return
        }
        let executor = taskExecutor
        DispatchQueue.global(qos: .userInitiated).async {
            let outcome = executor.execute(task: prepared.taskSnapshot, agent: prepared.agent) { update in
                DispatchQueue.main.async { [weak self] in
                    self?.captureExecutionProgress(update, for: prepared)
                }
            }
            DispatchQueue.main.async { [weak self] in
                guard let self else {
                    completion(false)
                    return
                }
                self.finalizeTaskExecution(prepared, outcome: outcome)
                completion(true)
            }
        }
    }

    @discardableResult
    func retryTaskExecution(_ taskID: UUID) -> Bool {
        guard let record = executionRecord(for: taskID), record.status == .failed else {
            lastBoardMessage = message("Only failed executions can be retried")
            lastBoardMessageSeverity = .warning
            return false
        }
        guard let prepared = prepareTaskExecution(taskID, requiresTaskDetails: false) else {
            return false
        }
        let outcome = taskExecutor.execute(task: prepared.taskSnapshot, agent: prepared.agent) { update in
            self.captureExecutionProgress(update, for: prepared)
        }
        finalizeTaskExecution(prepared, outcome: outcome)
        return true
    }

    func retryTaskExecutionInBackground(_ taskID: UUID, completion: @escaping (Bool) -> Void) {
        guard let record = executionRecord(for: taskID), record.status == .failed else {
            lastBoardMessage = message("Only failed executions can be retried")
            lastBoardMessageSeverity = .warning
            completion(false)
            return
        }
        guard let prepared = prepareTaskExecution(taskID, requiresTaskDetails: false) else {
            completion(false)
            return
        }
        let executor = taskExecutor
        DispatchQueue.global(qos: .userInitiated).async {
            let outcome = executor.execute(task: prepared.taskSnapshot, agent: prepared.agent) { update in
                DispatchQueue.main.async { [weak self] in
                    self?.captureExecutionProgress(update, for: prepared)
                }
            }
            DispatchQueue.main.async { [weak self] in
                guard let self else {
                    completion(false)
                    return
                }
                self.finalizeTaskExecution(prepared, outcome: outcome)
                completion(true)
            }
        }
    }

    @discardableResult
    func runAssignedTaskExecutions() -> Int {
        let assignedQueue = tasks
            .filter { task in
                (task.status == .todo || task.status == .inProgress) && task.assignedAgentID != nil
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
        let runnableTaskIDs = assignedQueue
            .filter { !$0.details.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .map(\.id)

        guard !runnableTaskIDs.isEmpty else {
            if detailsMissingCount > 0 {
                let label = detailsMissingCount == 1 ? message("task has") : message("tasks have")
                lastBoardMessage = message(
                    "%d assigned %@ empty details. Fill details before batch run.",
                    detailsMissingCount,
                    label
                )
            } else {
                lastBoardMessage = message("No assigned tasks are ready to run")
            }
            lastBoardMessageSeverity = .warning
            return 0
        }

        var startedCount = 0
        var succeededCount = 0
        var failedCount = 0
        var skippedCount = 0

        for taskID in runnableTaskIDs {
            let didRun = runTaskExecution(taskID)
            guard didRun else {
                skippedCount += 1
                continue
            }

            startedCount += 1
            if let record = executionRecord(for: taskID) {
                switch record.status {
                case .succeeded:
                    succeededCount += 1
                case .failed:
                    failedCount += 1
                case .running:
                    break
                }
            }
        }

        var summaryParts = [
            message("Batch run finished"),
            message("%d started", startedCount),
            message("%d succeeded", succeededCount),
            message("%d failed", failedCount)
        ]
        if skippedCount > 0 {
            summaryParts.append(message("%d skipped", skippedCount))
        }
        if detailsMissingCount > 0 {
            summaryParts.append(message("%d missing details", detailsMissingCount))
        }

        lastBoardMessage = summaryParts.joined(separator: " · ")
        lastBoardMessageSeverity = (failedCount > 0 || skippedCount > 0 || detailsMissingCount > 0) ? .warning : .info
        return startedCount
    }

    func runAssignedTaskExecutionsInBackground(completion: @escaping (Int) -> Void) {
        let assignedQueue = tasks
            .filter { task in
                (task.status == .todo || task.status == .inProgress) && task.assignedAgentID != nil
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
        let runnableTaskIDs = assignedQueue
            .filter { !$0.details.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .map(\.id)

        guard !runnableTaskIDs.isEmpty else {
            if detailsMissingCount > 0 {
                let label = detailsMissingCount == 1 ? message("task has") : message("tasks have")
                lastBoardMessage = message(
                    "%d assigned %@ empty details. Fill details before batch run.",
                    detailsMissingCount,
                    label
                )
            } else {
                lastBoardMessage = message("No assigned tasks are ready to run")
            }
            lastBoardMessageSeverity = .warning
            completion(0)
            return
        }

        var startedCount = 0
        var succeededCount = 0
        var failedCount = 0
        var skippedCount = 0

        func finish() {
            var summaryParts = [
                message("Batch run finished"),
                message("%d started", startedCount),
                message("%d succeeded", succeededCount),
                message("%d failed", failedCount)
            ]
            if skippedCount > 0 {
                summaryParts.append(message("%d skipped", skippedCount))
            }
            if detailsMissingCount > 0 {
                summaryParts.append(message("%d missing details", detailsMissingCount))
            }
            lastBoardMessage = summaryParts.joined(separator: " · ")
            lastBoardMessageSeverity = (failedCount > 0 || skippedCount > 0 || detailsMissingCount > 0) ? .warning : .info
            completion(startedCount)
        }

        func runNext(at index: Int) {
            guard index < runnableTaskIDs.count else {
                finish()
                return
            }

            let taskID = runnableTaskIDs[index]
            runTaskExecutionInBackground(taskID) { didRun in
                if !didRun {
                    skippedCount += 1
                    runNext(at: index + 1)
                    return
                }

                startedCount += 1
                if let record = self.executionRecord(for: taskID) {
                    switch record.status {
                    case .succeeded:
                        succeededCount += 1
                    case .failed:
                        failedCount += 1
                    case .running:
                        break
                    }
                }

                runNext(at: index + 1)
            }
        }

        runNext(at: 0)
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
        let remainingLabel = remainingCount == 1 ? message("task still needs") : message("tasks still need")
        return message(
            "Assigned %d triage %@. %d %@ manual attention",
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

    private func appendAgentExecutionEvent(
        agentID: UUID,
        taskID: UUID,
        taskTitle: String,
        status: TaskExecutionStatus,
        message: String,
        details: String? = nil
    ) {
        let event = AgentExecutionEvent(
            agentID: agentID,
            taskID: taskID,
            taskTitle: taskTitle,
            status: status,
            message: message,
            details: normalizeExecutionText(details)
        )

        var events = agentExecutionEventsByAgentID[agentID] ?? []
        events.append(event)
        if events.count > Self.maxAgentExecutionEventsPerAgent {
            events.removeFirst(events.count - Self.maxAgentExecutionEventsPerAgent)
        }
        agentExecutionEventsByAgentID[agentID] = events
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
        appendAgentExecutionEvent(
            agentID: agent.id,
            taskID: taskID,
            taskTitle: tasks[taskIndex].title,
            status: .running,
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
            let normalizedSummary = normalizeExecutionText(summary)
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
