import Combine
import Foundation

#if DEBUG
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
