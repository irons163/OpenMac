import Combine
import Foundation

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

#if DEBUG
extension DefaultAgentTaskExecutor {
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
#endif
