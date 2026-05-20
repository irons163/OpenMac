import Combine
import Foundation

extension KanbanBoardViewModel {
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

    func qualitySafetyGateBlockReason(for task: WorkTask) -> String? {
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

    func estimatedTokenUsage(for task: WorkTask) -> Int {
        let detailLength = task.details.count
        let skillsWeight = task.requiredSkills.count * 30
        return max(120, task.storyPoints * 260 + detailLength / 2 + skillsWeight)
    }

    func estimatedCostUSD(for tokens: Int) -> Double {
        (Double(tokens) / 1000.0) * executionQuotaPolicy.costPer1KTokensUSD
    }

    func quotaCheckMessage(for task: WorkTask) -> String? {
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

    func consumeExecutionQuota(for task: WorkTask) {
        guard executionQuotaPolicy.isEnabled else { return }
        let estimatedTokens = estimatedTokenUsage(for: task)
        executionQuotaUsage.consumedRuns += 1
        executionQuotaUsage.estimatedTokensUsed += estimatedTokens
        executionQuotaUsage.estimatedCostUSD += estimatedCostUSD(for: estimatedTokens)
        executionQuotaUsage.lastUpdatedAt = Date()
    }

    func retryableErrorType(for message: String) -> RetryableExecutionErrorType? {
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

    func ensureMCPServersReadyForExecution(
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

    func requiredMCPServers(for task: WorkTask, agent: AgentProfile) -> [MCPServerDescriptor] {
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

    func ensureMCPServerReady(
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

    func isMCPServerRegisteredAndEnabled(_ server: MCPServerDescriptor) -> Bool {
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

    func provisionMCPServer(
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

    func repairedMCPBootstrapCommandIfNeeded(
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

    func provisionBuiltinXcodeMCPServer() -> (success: Bool, details: String) {
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

    func detectedLocalPMPlanningPlugins(in directoryPath: String) -> [String] {
        detectedLocalPMPlannerPluginRecords(in: directoryPath)
            .filter { record in
                let capabilities = Set(record.manifest.capabilities ?? [])
                return capabilities.contains(Self.pmPlanningPluginCapability)
            }
            .map { record in resolvedPMExtensionPluginName(from: record) }
            .sorted { lhs, rhs in
                lhs.localizedCaseInsensitiveCompare(rhs) == .orderedAscending
            }
    }

    func detectedLocalPMPlannerExtensions(
        in directoryPath: String,
        slot: String
    ) -> [PMPlannerUIExtensionDescriptor] {
        let normalizedSlot = slot.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedSlot.isEmpty else { return [] }

        let extensions = detectedLocalPMPlannerPluginRecords(in: directoryPath).flatMap { record -> [PMPlannerUIExtensionDescriptor] in
            let pluginID = (record.manifest.id ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !pluginID.isEmpty else { return [] }
            guard !pmPlanningPluginPolicy.disabledPluginIDs.contains(pluginID.lowercased()) else { return [] }
            let pluginName = resolvedPMExtensionPluginName(from: record)

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

    func detectedLocalPMPlannerPluginRecords(in directoryPath: String) -> [LocalPMPlanningPluginRecord] {
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

    func localPMPlanningPluginRecord(at entryURL: URL) -> LocalPMPlanningPluginRecord? {
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

    static func builtInBrainstormPMPlannerExtension(slot: String) -> PMPlannerUIExtensionDescriptor {
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

    static func builtInGoogleStitchPMPlannerExtension(slot: String) -> PMPlannerUIExtensionDescriptor {
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

    static func normalizedPMPlannerComponentType(_ rawValue: String) -> String {
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

    static let pmPlanningPluginCapability = "pm.plan.generate"
    static let pmPlannerExtensionSlot = "pm.planner"
    static let extensionCommandDefaultSlot = "app.toolbar"
    static let extensionCommandTaskCardSlot = "task.card"
    static let extensionCommandPlannerPanelSlot = "pm.planner.panel"
    static let extensionCommandKanbanToolbarSlot = "kanban.toolbar"
    static let extensionCommandKanbanSidebarSlot = "kanban.sidebar"
    static let extensionCommandMarketplacePanelSlot = "marketplace.panel"
    static let systemExtensionPluginID = "openmac.system"
    static let systemExtensionPluginName = "OpenMac System"
    static let systemRealArtifactVerifyCommandID = "system.real-artifact-verify"
    static let systemGoogleStitchGenerateCommandID = "system.google-stitch.generate"
    static let extensionE2EToolbarCommandID = "toolbar-probe"
    static let extensionE2EHookCommandID = "hook-probe"
    static let extensionE2EKanbanToolbarCommandID = "kanban-toolbar-probe"
    static let extensionE2EKanbanSidebarCommandID = "kanban-sidebar-probe"
    static let extensionE2EMarketplacePanelCommandID = "marketplace-panel-probe"
    static let extensionCommandRequiredPermission = "command.execute"
    static let extensionCommandDefaultTimeoutSeconds = 45
    static let extensionCommandMaxTimeoutSeconds = 300
    static let pmPlannerBrainstormComponent = "brainstorm.v1"
    static let pmPlannerStitchComponent = "stitch.v1"
    static let pmPlannerUIFieldFocusInput = "focus.input"
    static let pmPlannerUIFieldStatusText = "status.text"
    static let pmPlannerUIFieldTranscriptOutput = "transcript.output"
    static let pmPlannerUIActionRun = "pm.brainstorm.run"
    static let pmPlannerUIActionApply = "pm.brainstorm.apply"
    static let pmPlannerUIActionApplyGenerate = "pm.brainstorm.apply.generate"
    static let pmPlannerUIActionApplyCreate = "pm.brainstorm.apply.create"
    static let pmPlannerUIActionClear = "pm.brainstorm.clear"
    static let iso8601Formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static func normalizedExtensionCommandSlot(_ rawValue: String) -> String {
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

    static func normalizedExtensionCommandSlots(_ slots: [String]?, singleSlot: String?) -> [String] {
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

    static func normalizedExtensionPermissions(_ permissions: [String]) -> [String] {
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

    nonisolated static func normalizedProviderDescriptorID(_ rawValue: String?) -> String? {
        guard let rawValue else { return nil }
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return trimmed
    }

    static func resolvedExtensionCommandTimeout(_ timeoutSeconds: Int?) -> Int? {
        guard let timeoutSeconds else { return nil }
        let minimum = max(1, timeoutSeconds)
        return min(extensionCommandMaxTimeoutSeconds, minimum)
    }

    static func currentOpenMacVersionString() -> String {
        let bundleVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let trimmed = (bundleVersion ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "0.0.0" : trimmed
    }

    static func normalizedVersionSegments(_ rawVersion: String) -> [Int] {
        rawVersion
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: ".")
            .prefix(4)
            .map { segment in
                Int(segment.filter(\.isNumber)) ?? 0
            }
    }

    static func compareVersions(_ lhs: String, _ rhs: String) -> ComparisonResult {
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

    static func pmExtensionCompatibilitySummary(
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

    static func pmExtensionCompatibilityViolation(
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

    static func pmExtensionVersionTransitionLabel(
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

    static func normalizedPMExtensionUpdateChannel(_ rawValue: String?) -> PMExtensionUpdateChannel {
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

    static func isAllowedPMExtensionUpdateChannel(
        _ candidate: PMExtensionUpdateChannel,
        preferred: PMExtensionUpdateChannel
    ) -> Bool {
        let rank: [PMExtensionUpdateChannel: Int] = [.stable: 0, .beta: 1, .alpha: 2]
        return (rank[candidate] ?? 0) <= (rank[preferred] ?? 0)
    }

    func pmExtensionSourceCandidates(for normalizedPluginID: String) -> [URL] {
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

    func findPMExtensionDirectory(in rootURL: URL, matchingPluginID normalizedPluginID: String) -> URL? {
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

    static func summarizedExtensionInputs(_ inputs: [String: String]) -> String {
        guard !inputs.isEmpty else { return "-" }
        let pairs = inputs
            .sorted { $0.key.localizedCaseInsensitiveCompare($1.key) == .orderedAscending }
            .map { key, value in
                "\(key)=\(value)"
            }
            .joined(separator: ", ")
        return summarizedExtensionOutput(pairs)
    }

    static func summarizedExtensionOutput(_ output: String) -> String {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "-" }
        let normalized = trimmed.replacingOccurrences(of: "\n", with: " ")
        if normalized.count <= 180 { return normalized }
        return String(normalized.prefix(177)) + "..."
    }

    static func pmExtensionE2EProbeManifest(pluginID: String, pluginName: String) -> String {
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

    static let pmExtensionE2EProbeScript = """
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

    func readOnMain<T>(_ block: @escaping () -> T) -> T {
        if Thread.isMainThread {
            return block()
        }
        return DispatchQueue.main.sync(execute: block)
    }

    static func waitForPMExtensionCondition(
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

    static func isLikelyHTTPRemoteSource(_ source: String) -> Bool {
        let lowercased = source.lowercased()
        return lowercased.hasPrefix("https://") || lowercased.hasPrefix("http://")
    }

    static func isLikelyGitRemoteSource(_ source: String) -> Bool {
        let lowercased = source.lowercased()
        if lowercased.hasSuffix(".git") || lowercased.hasPrefix("git@") {
            return true
        }
        return lowercased.hasPrefix("https://github.com/") || lowercased.hasPrefix("http://github.com/")
    }

    static func isLikelyZipSource(_ source: String) -> Bool {
        source.lowercased().hasSuffix(".zip")
    }

    func firstPMExtensionDirectoryCandidate(in rootURL: URL) -> URL? {
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

    func enqueuePMExtensionHookWorkItem(_ item: PMExtensionHookWorkItem) {
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

    func expireStalePMExtensionHookDedupKeys() {
        let now = Date()
        pmExtensionHookDedupExpirations = pmExtensionHookDedupExpirations.filter { _, expiry in
            expiry > now
        }
    }

    func drainPMExtensionHookQueueIfNeeded() {
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

    func markPMExtensionRunStarted(
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

    func markPMExtensionRunFinished(
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

    func refreshPMExtensionObservabilitySnapshots() {
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

    func appendPMExtensionActivity(
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

    static func sanitizedExtensionDirectoryName(_ rawValue: String, fallback: String) -> String {
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

    static func decodedPMExtensionCommandResponseMessage(from rawOutput: String) -> String? {
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

    struct GoogleStitchPromptOutput {
        let prompt: String
        let summary: String
    }

    struct GoogleStitchExternalCommandResult {
        let succeeded: Bool
        let message: String
    }

    static func generateGoogleStitchPrompt(from extensionInputs: [String: String]) -> GoogleStitchPromptOutput {
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

    static func runGoogleStitchExternalCommandIfConfigured(
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

    static func defaultBrainstormPMPlannerUISchema() -> PMPlannerUIExtensionSchema {
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

    static func defaultGoogleStitchPMPlannerUISchema() -> PMPlannerUIExtensionSchema {
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

    static func pmPlannerUISchema(
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

    static func normalizedPMPlannerUIFieldType(_ rawValue: String) -> String {
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

    static func normalizedPMPlannerUIActionID(_ rawValue: String) -> String {
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

    static func normalizedPMExtensionHookEvent(_ rawValue: String) -> String {
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

    static func pmPluginNamesPreview(_ names: [String], maxShown: Int = 3) -> String {
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

    struct LocalPMPlanningPluginManifestSummary: Decodable {
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

    struct LocalPMPlanningCommandManifestSummary: Decodable {
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

    struct LocalPMPlanningUIExtensionManifestSummary: Decodable {
        let id: String?
        let slot: String?
        let title: String?
        let subtitle: String?
        let component: String?
        let ui: LocalPMPlanningUIExtensionUISummary?
        let priority: Int?
        let enabled: Bool?
    }

    struct LocalPMPlanningMemoryProviderManifestSummary: Decodable {
        let id: String?
        let title: String?
        let commandID: String?
        let strategy: String?
        let priority: Int?
        let enabled: Bool?
    }

    struct LocalPMPlanningUIExtensionUISummary: Decodable {
        let fields: [LocalPMPlanningUIExtensionUIFieldSummary]?
        let actions: [LocalPMPlanningUIExtensionUIActionSummary]?
    }

    struct LocalPMPlanningUIExtensionUIFieldSummary: Decodable {
        let id: String?
        let type: String?
        let label: String?
        let placeholder: String?
        let minHeight: Int?
        let maxHeight: Int?
        let enabled: Bool?
    }

    struct LocalPMPlanningUIExtensionUIActionSummary: Decodable {
        let id: String?
        let title: String?
        let commandID: String?
        let enabled: Bool?
    }

    struct LocalPMPlanningEventHookManifestSummary: Decodable {
        let id: String?
        let event: String?
        let commandID: String?
        let enabled: Bool?
    }

    struct LocalPMPlanningPluginRecord {
        let manifest: LocalPMPlanningPluginManifestSummary
        let directoryURL: URL
    }

    struct PMExtensionCommandRequest: Encodable {
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

    struct PMExtensionCommandTaskDescriptor: Encodable {
        let id: UUID
        let title: String
        let details: String
        let status: String
        let storyPoints: Int
        let requiredSkills: [String]
        let assignedAgent: String?
    }

    struct PMExtensionCommandAgentDescriptor: Encodable {
        let name: String
        let skills: [String]
        let maxConcurrentTasks: Int
    }

    struct PMExtensionCommandResponse: Decodable {
        let message: String?
    }

    func shouldSyncMCPRegistry(lastSyncedAt: Date?) -> Bool {
        guard let lastSyncedAt else { return true }
        return Date().timeIntervalSince(lastSyncedAt) >= Self.mcpRegistrySyncTTL
    }

    struct MCPRegistryResponse: Decodable {
        let servers: [MCPRegistryEntry]
    }

    struct MCPRegistryEntry: Decodable {
        let server: MCPRegistryServer
    }

    struct MCPRegistryServer: Decodable {
        let name: String
        let description: String?
        let remotes: [MCPRegistryRemote]?
    }

    struct MCPRegistryRemote: Decodable {
        let url: String?
    }

    static func fetchMCPServersFromRegistry(
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

    static func inferredKeywordHints(name: String, description _: String?) -> [String] {
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

    static func installedXcodeDeveloperDirectoryPath(
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

    static func activeDeveloperDirectoryPath(
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

    static func xcodeSelectRepairCommandIfNeeded(
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

    static func parseXcodeBuildSettingValue(
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

    static func verificationBuildOverrides(
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

    static func shellQuoted(_ value: String) -> String {
        let escaped = value.replacingOccurrences(of: "'", with: "'\"'\"'")
        return "'\(escaped)'"
    }

    static func shellCommandEnvironment(
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

    static func mergedShellPATH(
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

    struct ShellCommandExecutionResult {
        let code: Int32
        let stdout: String
        let stderr: String
        let timedOut: Bool
    }

    static func mergedShellOutput(stdout: String, stderr: String, trim: Bool = true) -> String {
        let merged = [stdout, stderr]
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
        if trim {
            return merged.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return merged
    }

    static func executeShellCommand(
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

    static func runShellCommand(
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

    static func runShellCommand(
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

    static func runShellCommand(
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

    func executeWithAutoRetry(
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

}
