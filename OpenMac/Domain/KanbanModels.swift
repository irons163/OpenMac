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
    static let codexBridgeDefaultModel = "gpt-5"

    static var defaultCodexBridge: AgentRuntimeProfile {
        AgentRuntimeProfile(
            provider: .openAICompatible,
            model: codexBridgeDefaultModel,
            openAIAuthMode: .codexBridge
        )
    }

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
    var autoAssignFallbackWithoutSkillMatch: Bool

    init(
        boardID: UUID,
        mode: ExecutionCheckpointMode,
        startedAt: Date = Date(),
        maxAutoCyclePasses: Int = 1,
        autoCreateMissingDependencies: Bool = false,
        autoAssignBeforeRun: Bool = true,
        autoAssignFallbackWithoutSkillMatch: Bool = false
    ) {
        self.boardID = boardID
        self.mode = mode
        self.startedAt = startedAt
        self.maxAutoCyclePasses = max(1, maxAutoCyclePasses)
        self.autoCreateMissingDependencies = autoCreateMissingDependencies
        self.autoAssignBeforeRun = autoAssignBeforeRun
        self.autoAssignFallbackWithoutSkillMatch = autoAssignFallbackWithoutSkillMatch
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

struct ExecutionParallelizationPolicy: Equatable, Codable {
    var isEnabled: Bool
    var maxConcurrentAgents: Int

    init(
        isEnabled: Bool = false,
        maxConcurrentAgents: Int = 2
    ) {
        self.isEnabled = isEnabled
        self.maxConcurrentAgents = max(1, maxConcurrentAgents)
    }
}

struct GitHubPRQualityGatePolicy: Equatable, Codable {
    var isEnabled: Bool
    var commands: [String]

    init(
        isEnabled: Bool = false,
        commands: [String] = Self.defaultCommands
    ) {
        self.isEnabled = isEnabled
        self.commands = Self.normalizedCommands(commands)
    }

    nonisolated static var defaultCommands: [String] {
        [
            "DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -project OpenMac.xcodeproj -scheme OpenMac -destination 'platform=macOS' -only-testing:OpenMacTests"
        ]
    }

    nonisolated private static func normalizedCommands(_ rawCommands: [String]) -> [String] {
        var seen = Set<String>()
        var normalized: [String] = []
        for command in rawCommands {
            let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            guard !seen.contains(trimmed) else { continue }
            seen.insert(trimmed)
            normalized.append(trimmed)
        }
        return normalized.isEmpty ? defaultCommands : normalized
    }
}

struct DAGExecutionPolicy: Equatable, Codable {
    var isEnabled: Bool
    var autoAssignBeforeRun: Bool
    var autoAssignFallbackWithoutSkillMatch: Bool
    var autoRelaxWIPLimitsDuringRun: Bool
    var autoCreateMissingDependenciesDuringRun: Bool
    var maxPasses: Int

    init(
        isEnabled: Bool = true,
        autoAssignBeforeRun: Bool = true,
        autoAssignFallbackWithoutSkillMatch: Bool = true,
        autoRelaxWIPLimitsDuringRun: Bool = true,
        autoCreateMissingDependenciesDuringRun: Bool = true,
        maxPasses: Int = 6
    ) {
        self.isEnabled = isEnabled
        self.autoAssignBeforeRun = autoAssignBeforeRun
        self.autoAssignFallbackWithoutSkillMatch = autoAssignFallbackWithoutSkillMatch
        self.autoRelaxWIPLimitsDuringRun = autoRelaxWIPLimitsDuringRun
        self.autoCreateMissingDependenciesDuringRun = autoCreateMissingDependenciesDuringRun
        self.maxPasses = max(1, min(24, maxPasses))
    }
}

struct ExecutionQualitySafetyGatePolicy: Equatable, Codable {
    var isEnabled: Bool
    var requireAcceptanceCriteria: Bool
    var requireTestCoverageIntent: Bool
    var requireSecurityPrivacyForSensitiveTasks: Bool
    var sensitiveKeywords: [String]

    init(
        isEnabled: Bool = false,
        requireAcceptanceCriteria: Bool = true,
        requireTestCoverageIntent: Bool = true,
        requireSecurityPrivacyForSensitiveTasks: Bool = true,
        sensitiveKeywords: [String] = Self.defaultSensitiveKeywords
    ) {
        self.isEnabled = isEnabled
        self.requireAcceptanceCriteria = requireAcceptanceCriteria
        self.requireTestCoverageIntent = requireTestCoverageIntent
        self.requireSecurityPrivacyForSensitiveTasks = requireSecurityPrivacyForSensitiveTasks
        self.sensitiveKeywords = Self.normalizedKeywords(sensitiveKeywords)
    }

    nonisolated static var defaultSensitiveKeywords: [String] {
        [
            "auth", "oauth", "login", "password",
            "payment", "billing", "card",
            "privacy", "pii", "profile", "matchmaking"
        ]
    }

    nonisolated private static func normalizedKeywords(_ rawKeywords: [String]) -> [String] {
        var seen = Set<String>()
        var normalized: [String] = []
        for keyword in rawKeywords {
            let trimmed = keyword.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !trimmed.isEmpty else { continue }
            guard !seen.contains(trimmed) else { continue }
            seen.insert(trimmed)
            normalized.append(trimmed)
        }
        return normalized.isEmpty ? defaultSensitiveKeywords : normalized
    }
}

struct ExecutionRealArtifactVerificationPolicy: Equatable, Codable {
    var isEnabled: Bool
    var requireInfoPlistExecutableKey: Bool
    var requireXcodeBuild: Bool
    var runVerificationOnlyOnTerminalTask: Bool
    var enableDeterministicRepairCycle: Bool

    init(
        isEnabled: Bool = false,
        requireInfoPlistExecutableKey: Bool = true,
        requireXcodeBuild: Bool = true,
        runVerificationOnlyOnTerminalTask: Bool = true,
        enableDeterministicRepairCycle: Bool = true
    ) {
        self.isEnabled = isEnabled
        self.requireInfoPlistExecutableKey = requireInfoPlistExecutableKey
        self.requireXcodeBuild = requireXcodeBuild
        self.runVerificationOnlyOnTerminalTask = runVerificationOnlyOnTerminalTask
        self.enableDeterministicRepairCycle = enableDeterministicRepairCycle
    }

    enum CodingKeys: String, CodingKey {
        case isEnabled
        case requireInfoPlistExecutableKey
        case requireXcodeBuild
        case runVerificationOnlyOnTerminalTask
        case enableDeterministicRepairCycle
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? false
        requireInfoPlistExecutableKey =
            try container.decodeIfPresent(Bool.self, forKey: .requireInfoPlistExecutableKey) ?? true
        requireXcodeBuild = try container.decodeIfPresent(Bool.self, forKey: .requireXcodeBuild) ?? true
        runVerificationOnlyOnTerminalTask =
            try container.decodeIfPresent(Bool.self, forKey: .runVerificationOnlyOnTerminalTask) ?? true
        enableDeterministicRepairCycle =
            try container.decodeIfPresent(Bool.self, forKey: .enableDeterministicRepairCycle) ?? true
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(isEnabled, forKey: .isEnabled)
        try container.encode(requireInfoPlistExecutableKey, forKey: .requireInfoPlistExecutableKey)
        try container.encode(requireXcodeBuild, forKey: .requireXcodeBuild)
        try container.encode(runVerificationOnlyOnTerminalTask, forKey: .runVerificationOnlyOnTerminalTask)
        try container.encode(enableDeterministicRepairCycle, forKey: .enableDeterministicRepairCycle)
    }
}

enum MCPServerSourceType: String, Codable, Equatable {
    case builtin
    case registry
    case manual
}

struct MCPServerDescriptor: Identifiable, Equatable, Codable {
    var name: String
    var remoteURL: String?
    var bootstrapCommand: String?
    var verificationCommand: String?
    var keywordHints: [String]
    var isEnabled: Bool
    var source: MCPServerSourceType
    var notes: String?

    nonisolated var id: String { Self.normalizedServerName(name) }
    nonisolated var normalizedName: String { Self.normalizedServerName(name) }
    nonisolated var cliServerName: String { Self.cliSafeServerName(name) }

    nonisolated init(
        name: String,
        remoteURL: String? = nil,
        bootstrapCommand: String? = nil,
        verificationCommand: String? = nil,
        keywordHints: [String] = [],
        isEnabled: Bool = true,
        source: MCPServerSourceType = .manual,
        notes: String? = nil
    ) {
        self.name = Self.normalizedLabel(name)
        self.remoteURL = Self.normalizedOptionalText(remoteURL)
        self.bootstrapCommand = Self.normalizedOptionalText(bootstrapCommand)
        self.verificationCommand = Self.normalizedOptionalText(verificationCommand)
        self.keywordHints = Self.normalizedKeywordHints(keywordHints)
        self.isEnabled = isEnabled
        self.source = source
        self.notes = Self.normalizedOptionalText(notes)
    }

    nonisolated static func normalizedServerName(_ value: String) -> String {
        normalizedLabel(value).lowercased()
    }

    nonisolated static func cliSafeServerName(_ value: String) -> String {
        let source = normalizedServerName(value)
        var safe = ""
        var previousWasSeparator = false

        for character in source {
            let isAllowed = character.isASCII && (character.isLetter || character.isNumber || character == "-" || character == "_")
            if isAllowed {
                safe.append(character)
                previousWasSeparator = false
            } else if !previousWasSeparator {
                safe.append("-")
                previousWasSeparator = true
            }
        }

        let trimmed = safe.trimmingCharacters(in: CharacterSet(charactersIn: "-_"))
        return trimmed.isEmpty ? "mcp-server" : trimmed
    }

    nonisolated private static func normalizedLabel(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "mcp-server" : trimmed
    }

    nonisolated private static func normalizedOptionalText(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    nonisolated private static func normalizedKeywordHints(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var normalized: [String] = []
        for value in values {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !trimmed.isEmpty else { continue }
            guard !seen.contains(trimmed) else { continue }
            seen.insert(trimmed)
            normalized.append(trimmed)
        }
        return normalized
    }
}

struct MCPServerPolicy: Equatable, Codable {
    static let defaultRegistryURL = "https://registry.modelcontextprotocol.io/v0.1/servers?limit=100"

    var autoFetchEnabled: Bool
    var registryURL: String
    var autoFetchedServers: [MCPServerDescriptor]
    var manualServers: [MCPServerDescriptor]
    var lastSyncedAt: Date?
    var lastSyncError: String?

    init(
        autoFetchEnabled: Bool = true,
        registryURL: String = MCPServerPolicy.defaultRegistryURL,
        autoFetchedServers: [MCPServerDescriptor] = [],
        manualServers: [MCPServerDescriptor] = [],
        lastSyncedAt: Date? = nil,
        lastSyncError: String? = nil
    ) {
        self.autoFetchEnabled = autoFetchEnabled
        let trimmedRegistryURL = registryURL.trimmingCharacters(in: .whitespacesAndNewlines)
        self.registryURL = trimmedRegistryURL.isEmpty ? MCPServerPolicy.defaultRegistryURL : trimmedRegistryURL
        self.autoFetchedServers = MCPServerPolicy.normalizedServers(autoFetchedServers, source: .registry)
        self.manualServers = MCPServerPolicy.normalizedServers(manualServers, source: .manual)
        self.lastSyncedAt = lastSyncedAt
        let trimmedSyncError = lastSyncError?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        self.lastSyncError = trimmedSyncError.isEmpty ? nil : trimmedSyncError
    }

    var effectiveServers: [MCPServerDescriptor] {
        let autoServers = autoFetchEnabled ? autoFetchedServers : []
        return MCPServerPolicy.mergedServers(
            builtin: MCPServerPolicy.defaultBuiltinServers,
            autoFetched: autoServers,
            manual: manualServers
        )
    }

    nonisolated static var defaultBuiltinServers: [MCPServerDescriptor] {
        [
            MCPServerDescriptor(
                name: "xcode",
                bootstrapCommand: nil,
                verificationCommand: "codex mcp get xcode --json",
                keywordHints: ["xcode", "xcodebuild", "ios", "macos", "uikit", "simulator"],
                isEnabled: true,
                source: .builtin,
                notes: "Apple/Xcode build and simulator tooling"
            )
        ]
    }

    nonisolated private static func normalizedServers(
        _ rawServers: [MCPServerDescriptor],
        source: MCPServerSourceType
    ) -> [MCPServerDescriptor] {
        var seen = Set<String>()
        var normalized: [MCPServerDescriptor] = []
        for rawServer in rawServers {
            let key = rawServer.normalizedName
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            normalized.append(
                MCPServerDescriptor(
                    name: rawServer.name,
                    remoteURL: rawServer.remoteURL,
                    bootstrapCommand: rawServer.bootstrapCommand,
                    verificationCommand: rawServer.verificationCommand,
                    keywordHints: rawServer.keywordHints,
                    isEnabled: rawServer.isEnabled,
                    source: source,
                    notes: rawServer.notes
                )
            )
        }
        return normalized
    }

    nonisolated private static func mergedServers(
        builtin: [MCPServerDescriptor],
        autoFetched: [MCPServerDescriptor],
        manual: [MCPServerDescriptor]
    ) -> [MCPServerDescriptor] {
        let ordered = builtin + autoFetched + manual
        var byName: [String: MCPServerDescriptor] = [:]
        for server in ordered {
            byName[server.normalizedName] = server
        }

        return byName.values.sorted { lhs, rhs in
            lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
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

enum TaskDeliveryOutputType: String, CaseIterable, Codable, Identifiable {
    case app
    case codeModule
    case document
    case image
    case data
    case mixed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .app:
            return L10n.string("App")
        case .codeModule:
            return L10n.string("Code Module")
        case .document:
            return L10n.string("Document")
        case .image:
            return L10n.string("Image")
        case .data:
            return L10n.string("Data")
        case .mixed:
            return L10n.string("Mixed")
        }
    }
}

enum PMTicketDeliveryProfile: String, CaseIterable, Codable, Identifiable {
    case balanced
    case productBuild
    case contentAndDocs

    var id: String { rawValue }

    var title: String {
        switch self {
        case .balanced:
            return L10n.string("Balanced")
        case .productBuild:
            return L10n.string("Product Build")
        case .contentAndDocs:
            return L10n.string("Content & Docs")
        }
    }

    var detail: String {
        switch self {
        case .balanced:
            return L10n.string("Balanced profile: allows progressive output while still expecting evidence.")
        case .productBuild:
            return L10n.string("Product Build profile: requires runnable deliverables with strict evidence.")
        case .contentAndDocs:
            return L10n.string("Content & Docs profile: optimized for summaries, docs, and non-code outputs.")
        }
    }

    var contract: TaskDeliveryContract {
        switch self {
        case .balanced:
            return .defaultContract
        case .productBuild:
            return TaskDeliveryContract(
                outputType: .app,
                gateMode: .strict
            )
        case .contentAndDocs:
            return TaskDeliveryContract(
                outputType: .document,
                gateMode: .flexible
            )
        }
    }
}

enum PMRealArtifactVerificationPreset: String, CaseIterable, Codable, Identifiable {
    case useDeveloperDefaults
    case disabled
    case standard
    case strict

    var id: String { rawValue }

    var title: String {
        switch self {
        case .useDeveloperDefaults:
            return L10n.string("Use Developer Defaults")
        case .disabled:
            return L10n.string("Off (Summary only)")
        case .standard:
            return L10n.string("Standard (xcodebuild)")
        case .strict:
            return L10n.string("Strict (Info.plist + xcodebuild)")
        }
    }

    var detail: String {
        switch self {
        case .useDeveloperDefaults:
            return L10n.string("Follow the Developer default verification policy for this board.")
        case .disabled:
            return L10n.string("Skip installation checks and accept summary-level evidence for strict app tasks.")
        case .standard:
            return L10n.string("Run build-level verification (xcodebuild) for strict app tasks.")
        case .strict:
            return L10n.string("Enforce both Info.plist executable key and xcodebuild verification for strict app tasks.")
        }
    }

    func resolvedPolicy(defaultPolicy: ExecutionRealArtifactVerificationPolicy) -> ExecutionRealArtifactVerificationPolicy {
        switch self {
        case .useDeveloperDefaults:
            return defaultPolicy
        case .disabled:
            return ExecutionRealArtifactVerificationPolicy(
                isEnabled: false,
                requireInfoPlistExecutableKey: defaultPolicy.requireInfoPlistExecutableKey,
                requireXcodeBuild: defaultPolicy.requireXcodeBuild
            )
        case .standard:
            return ExecutionRealArtifactVerificationPolicy(
                isEnabled: true,
                requireInfoPlistExecutableKey: false,
                requireXcodeBuild: true
            )
        case .strict:
            return ExecutionRealArtifactVerificationPolicy(
                isEnabled: true,
                requireInfoPlistExecutableKey: true,
                requireXcodeBuild: true
            )
        }
    }
}

enum PMPlannerEngineMode: String, CaseIterable, Codable, Identifiable {
    case builtIn
    case brainstormPluginPreferred

    var id: String { rawValue }

    var title: String {
        switch self {
        case .builtIn:
            return L10n.string("Built-in Planner")
        case .brainstormPluginPreferred:
            return L10n.string("Brainstorm Plugin (Preferred)")
        }
    }

    var detail: String {
        switch self {
        case .builtIn:
            return L10n.string("Use OpenMac built-in PM planner only.")
        case .brainstormPluginPreferred:
            return L10n.string("Try plugin-based brainstorm planning first, then fallback to built-in planner.")
        }
    }
}

struct PMPlanningPluginPolicy: Equatable, Codable {
    nonisolated static let defaultRelativePath = "Library/Application Support/OpenMac/Plugins"

    var autoDiscoverLocalPlugins: Bool
    var pluginsDirectoryPath: String

    init(
        autoDiscoverLocalPlugins: Bool = true,
        pluginsDirectoryPath: String = PMPlanningPluginPolicy.defaultPluginsDirectoryURL().path
    ) {
        self.autoDiscoverLocalPlugins = autoDiscoverLocalPlugins
        let trimmedPath = pluginsDirectoryPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedPath.isEmpty {
            self.pluginsDirectoryPath = PMPlanningPluginPolicy.defaultPluginsDirectoryURL().path
        } else {
            self.pluginsDirectoryPath = (trimmedPath as NSString).expandingTildeInPath
        }
    }

    nonisolated static func defaultPluginsDirectoryURL(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> URL {
        homeDirectory.appendingPathComponent(defaultRelativePath, isDirectory: true)
    }
}

struct PMPlannerUIExtensionDescriptor: Equatable, Identifiable {
    enum Source: String, Codable {
        case builtIn
        case localPlugin
    }

    var id: String
    var pluginID: String
    var pluginName: String
    var slot: String
    var title: String
    var subtitle: String
    var componentType: String
    var priority: Int
    var source: Source
    var uiSchema: PMPlannerUIExtensionSchema?
}

struct PMInstalledExtensionDescriptor: Equatable, Identifiable {
    var id: String
    var pluginID: String
    var name: String
    var version: String
    var summary: String
    var directoryPath: String
    var capabilityCount: Int
    var uiExtensionCount: Int
    var commandCount: Int
}

struct PMExtensionCommandDescriptor: Equatable, Identifiable {
    var id: String
    var pluginID: String
    var pluginName: String
    var commandID: String
    var title: String
    var subtitle: String
}

struct PMPlannerUIExtensionSchema: Equatable {
    var fields: [PMPlannerUIExtensionField]
    var actions: [PMPlannerUIExtensionAction]
}

struct PMPlannerUIExtensionField: Equatable, Identifiable {
    var id: String
    var type: String
    var label: String
    var placeholder: String
    var minHeight: Int?
    var maxHeight: Int?
}

struct PMPlannerUIExtensionAction: Equatable, Identifiable {
    var id: String
    var title: String
}

enum TaskDeliveryGateMode: String, CaseIterable, Codable, Identifiable {
    case strict
    case flexible

    var id: String { rawValue }

    var title: String {
        switch self {
        case .strict:
            return L10n.string("Strict")
        case .flexible:
            return L10n.string("Flexible")
        }
    }
}

enum TaskDeliveryArtifactRule: String, CaseIterable, Codable, Identifiable {
    case all
    case any

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all:
            return L10n.string("All")
        case .any:
            return L10n.string("Any")
        }
    }
}

enum TaskDeliveryArtifact: String, CaseIterable, Codable, Identifiable {
    case files
    case commands
    case tests
    case report
    case images
    case summary

    var id: String { rawValue }

    var title: String {
        switch self {
        case .files:
            return L10n.string("Files")
        case .commands:
            return L10n.string("Commands")
        case .tests:
            return L10n.string("Tests")
        case .report:
            return L10n.string("Report")
        case .images:
            return L10n.string("Images")
        case .summary:
            return L10n.string("Summary")
        }
    }
}

struct TaskDeliveryContract: Equatable, Codable {
    var outputType: TaskDeliveryOutputType
    var gateMode: TaskDeliveryGateMode
    var artifactRule: TaskDeliveryArtifactRule
    var requiredArtifacts: Set<TaskDeliveryArtifact>

    init(
        outputType: TaskDeliveryOutputType,
        gateMode: TaskDeliveryGateMode,
        artifactRule: TaskDeliveryArtifactRule? = nil,
        requiredArtifacts: Set<TaskDeliveryArtifact>? = nil
    ) {
        self.outputType = outputType
        self.gateMode = gateMode
        self.artifactRule = artifactRule ?? Self.defaultArtifactRule(for: gateMode)
        self.requiredArtifacts = requiredArtifacts ?? Self.defaultRequiredArtifacts(
            outputType: outputType,
            gateMode: gateMode
        )
    }

    static var defaultContract: TaskDeliveryContract {
        TaskDeliveryContract(
            outputType: .mixed,
            gateMode: .flexible
        )
    }

    static func defaultArtifactRule(for gateMode: TaskDeliveryGateMode) -> TaskDeliveryArtifactRule {
        switch gateMode {
        case .strict:
            return .all
        case .flexible:
            return .any
        }
    }

    static func defaultRequiredArtifacts(
        outputType: TaskDeliveryOutputType,
        gateMode: TaskDeliveryGateMode
    ) -> Set<TaskDeliveryArtifact> {
        switch gateMode {
        case .strict:
            switch outputType {
            case .app, .codeModule:
                return [.files, .commands, .tests, .report]
            case .document:
                return [.files, .report]
            case .image:
                return [.images, .report]
            case .data:
                return [.files, .commands, .report]
            case .mixed:
                return [.report]
            }
        case .flexible:
            switch outputType {
            case .app, .codeModule:
                return [.files, .report]
            case .document:
                return [.report, .summary]
            case .image:
                return [.images, .report]
            case .data:
                return [.files, .report]
            case .mixed:
                return [.report, .summary]
            }
        }
    }

    var normalized: TaskDeliveryContract {
        TaskDeliveryContract(
            outputType: outputType,
            gateMode: gateMode,
            artifactRule: artifactRule,
            requiredArtifacts: requiredArtifacts
        )
    }

    var requiredArtifactsText: String {
        requiredArtifacts
            .sorted { $0.rawValue < $1.rawValue }
            .map(\.title)
            .joined(separator: ", ")
    }

    mutating func resetDefaultsForCurrentMode() {
        artifactRule = Self.defaultArtifactRule(for: gateMode)
        requiredArtifacts = Self.defaultRequiredArtifacts(outputType: outputType, gateMode: gateMode)
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
    var deliveryContract: TaskDeliveryContract?
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
        deliveryContract: TaskDeliveryContract? = nil,
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
        self.deliveryContract = deliveryContract?.normalized
        self.createdAt = createdAt
    }

    var isAssignable: Bool {
        status == .todo && assignedAgentID == nil
    }

    var resolvedDeliveryContract: TaskDeliveryContract {
        deliveryContract?.normalized ?? .defaultContract
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
    var executionRealArtifactVerificationPolicy: ExecutionRealArtifactVerificationPolicy?

    init(
        id: UUID = UUID(),
        name: String,
        tasks: [WorkTask] = [],
        agents: [AgentProfile] = [],
        wipLimits: [KanbanStatus: Int] = [.inProgress: 3, .review: 2],
        executionRealArtifactVerificationPolicy: ExecutionRealArtifactVerificationPolicy? = nil
    ) {
        self.id = id
        self.name = name
        self.tasks = tasks
        self.agents = agents
        self.wipLimits = wipLimits.reduce(into: [:]) { partialResult, pair in
            partialResult[pair.key] = max(1, pair.value)
        }
        self.executionRealArtifactVerificationPolicy = executionRealArtifactVerificationPolicy
    }
}
