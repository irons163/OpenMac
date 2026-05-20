import Combine
import Foundation

extension KanbanBoardViewModel {
    func updatePMPlanningPolicyState(
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

    func persistPMPlanningPolicyChange(infoMessage: String? = nil) {
        persistBoardState()
        guard let infoMessage else { return }
        lastBoardMessage = infoMessage
        lastBoardMessageSeverity = .info
    }

    func normalizedPMExtensionLookupKey(_ rawValue: String) -> String {
        rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    func failPMExtensionOperation(_ key: String, _ arguments: CVarArg...) -> Bool {
        if arguments.isEmpty {
            lastBoardMessage = message(key)
        } else {
            lastBoardMessage = L10n.format(key, locale: nil, arguments: arguments)
        }
        lastBoardMessageSeverity = .warning
        return false
    }

    func publishPMExtensionPluginOperation(
        pluginID: String,
        pluginName: String,
        boardMessage: String,
        boardMessageSeverity: BoardMessageSeverity,
        outcome: PMExtensionActivityLogEntry.Outcome,
        detail: String,
        result: Bool
    ) -> Bool {
        lastBoardMessage = boardMessage
        lastBoardMessageSeverity = boardMessageSeverity
        appendPMExtensionPluginActivity(
            pluginID: pluginID,
            pluginName: pluginName,
            outcome: outcome,
            detail: detail
        )
        return result
    }

    func failPMExtensionInstall(
        pluginID: String,
        pluginName: String,
        boardMessage: String,
        detail: String
    ) -> Bool {
        publishPMExtensionPluginOperation(
            pluginID: pluginID,
            pluginName: pluginName,
            boardMessage: boardMessage,
            boardMessageSeverity: .warning,
            outcome: .failed,
            detail: detail,
            result: false
        )
    }

    func failBlockedPMExtensionInstall(
        pluginID: String,
        pluginName: String,
        boardMessage: String,
        detail: String
    ) -> Bool {
        failPMExtensionInstall(
            pluginID: pluginID,
            pluginName: pluginName,
            boardMessage: boardMessage,
            detail: "Install blocked: \(detail)"
        )
    }

    func completePMExtensionInstall(
        pluginID: String,
        pluginName: String,
        boardMessage: String,
        outcome: PMExtensionActivityLogEntry.Outcome,
        detail: String
    ) -> Bool {
        publishPMExtensionPluginOperation(
            pluginID: pluginID,
            pluginName: pluginName,
            boardMessage: boardMessage,
            boardMessageSeverity: .info,
            outcome: outcome,
            detail: detail,
            result: true
        )
    }

    func failPMExtensionUninstall(
        pluginID: String,
        pluginName: String,
        boardMessage: String,
        detail: String
    ) -> Bool {
        failPMExtensionInstall(
            pluginID: pluginID,
            pluginName: pluginName,
            boardMessage: boardMessage,
            detail: detail
        )
    }

    func completePMExtensionUninstall(
        pluginID: String,
        pluginName: String,
        boardMessage: String,
        detail: String
    ) -> Bool {
        completePMExtensionInstall(
            pluginID: pluginID,
            pluginName: pluginName,
            boardMessage: boardMessage,
            outcome: .succeeded,
            detail: detail
        )
    }

    static let remotePMExtensionActivityPluginID = "remote"
    static let remotePMExtensionActivityPluginName = "Remote Source"

    enum PMExtensionRemoteSourceResolution {
        case resolved(URL)
        case unsupported
        case failed
    }

    func appendRemotePMExtensionActivity(
        outcome: PMExtensionActivityLogEntry.Outcome,
        detail: String
    ) {
        appendPMExtensionPluginActivity(
            pluginID: Self.remotePMExtensionActivityPluginID,
            pluginName: Self.remotePMExtensionActivityPluginName,
            outcome: outcome,
            detail: detail
        )
    }

    func appendPMExtensionPluginActivity(
        pluginID: String,
        pluginName: String,
        outcome: PMExtensionActivityLogEntry.Outcome,
        detail: String
    ) {
        appendPMExtensionActivity(
            pluginID: pluginID,
            pluginName: pluginName,
            commandID: nil,
            commandTitle: nil,
            outcome: outcome,
            detail: detail
        )
    }

    func failRemotePMExtensionInstall(
        boardMessage: String,
        detail: String
    ) -> Bool {
        failPMExtensionInstall(
            pluginID: Self.remotePMExtensionActivityPluginID,
            pluginName: Self.remotePMExtensionActivityPluginName,
            boardMessage: boardMessage,
            detail: detail
        )
    }

    static func resolvedPMExtensionShellFailureMessage(
        from result: (code: Int32, output: String)?,
        fallback: String
    ) -> String {
        let details = result?.output.trimmingCharacters(in: .whitespacesAndNewlines)
        return details?.isEmpty == false ? details! : fallback
    }

    func runRemotePMExtensionShellStep(
        _ command: String,
        fallbackFailure: String,
        detailPrefix: String
    ) -> Bool {
        let result = try? Self.runShellCommand(command)
        guard let result, result.code == 0 else {
            let failure = Self.resolvedPMExtensionShellFailureMessage(
                from: result,
                fallback: fallbackFailure
            )
            return failRemotePMExtensionInstall(
                boardMessage: message("Extension install failed: %@", failure),
                detail: "\(detailPrefix): \(failure)"
            )
        }
        return true
    }

    func resolvePMExtensionRemoteSourceRoot(
        _ trimmedSource: String,
        extractionRootURL: URL,
        tempRootURL: URL,
        fileManager: FileManager
    ) -> PMExtensionRemoteSourceResolution {
        let expandedSourcePath = (trimmedSource as NSString).expandingTildeInPath
        if fileManager.fileExists(atPath: expandedSourcePath) {
            var isDirectory: ObjCBool = false
            if fileManager.fileExists(atPath: expandedSourcePath, isDirectory: &isDirectory), isDirectory.boolValue {
                return .resolved(URL(fileURLWithPath: expandedSourcePath, isDirectory: true))
            }
            guard Self.isLikelyZipSource(expandedSourcePath) else {
                return .unsupported
            }
            let unzipCommand = "/usr/bin/unzip -q \(Self.shellQuoted(expandedSourcePath)) -d \(Self.shellQuoted(extractionRootURL.path))"
            guard runRemotePMExtensionShellStep(
                unzipCommand,
                fallbackFailure: "unzip failed",
                detailPrefix: "Unzip failed"
            ) else { return .failed }
            return .resolved(extractionRootURL)
        }

        if Self.isLikelyGitRemoteSource(trimmedSource) {
            let cloneURL = extractionRootURL.appendingPathComponent("repo", isDirectory: true)
            let cloneCommand = "/usr/bin/git clone --depth 1 \(Self.shellQuoted(trimmedSource)) \(Self.shellQuoted(cloneURL.path))"
            guard runRemotePMExtensionShellStep(
                cloneCommand,
                fallbackFailure: "git clone failed",
                detailPrefix: "Git clone failed"
            ) else { return .failed }
            return .resolved(cloneURL)
        }

        if Self.isLikelyHTTPRemoteSource(trimmedSource) {
            let archiveURL = tempRootURL.appendingPathComponent("plugin.zip")
            let downloadCommand = "/usr/bin/curl -L --fail \(Self.shellQuoted(trimmedSource)) -o \(Self.shellQuoted(archiveURL.path))"
            guard runRemotePMExtensionShellStep(
                downloadCommand,
                fallbackFailure: "download failed",
                detailPrefix: "Remote download failed"
            ) else { return .failed }
            let unzipCommand = "/usr/bin/unzip -q \(Self.shellQuoted(archiveURL.path)) -d \(Self.shellQuoted(extractionRootURL.path))"
            guard runRemotePMExtensionShellStep(
                unzipCommand,
                fallbackFailure: "unzip failed",
                detailPrefix: "Remote unzip failed"
            ) else { return .failed }
            return .resolved(extractionRootURL)
        }

        return .unsupported
    }

    struct PMExtensionRemoteInstallWorkspace {
        let fileManager: FileManager
        let tempRootURL: URL
        let extractionRootURL: URL
    }

    func preparedPMExtensionRemoteInstallWorkspace(
        remoteSource: String
    ) -> (trimmedSource: String, workspace: PMExtensionRemoteInstallWorkspace)? {
        let trimmedSource = remoteSource.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSource.isEmpty else {
            lastBoardMessage = message("Extension install failed: remote source is empty")
            lastBoardMessageSeverity = .warning
            return nil
        }

        let fileManager = FileManager.default
        let tempRootURL = fileManager.temporaryDirectory
            .appendingPathComponent("openmac-extension-\(UUID().uuidString)", isDirectory: true)
        let extractionRootURL = tempRootURL.appendingPathComponent("payload", isDirectory: true)
        do {
            try fileManager.createDirectory(at: extractionRootURL, withIntermediateDirectories: true)
        } catch {
            lastBoardMessage = message("Extension install failed: %@", error.localizedDescription)
            lastBoardMessageSeverity = .warning
            return nil
        }

        return (
            trimmedSource,
            PMExtensionRemoteInstallWorkspace(
                fileManager: fileManager,
                tempRootURL: tempRootURL,
                extractionRootURL: extractionRootURL
            )
        )
    }

    struct PMExtensionInstallRequest {
        let sourceURL: URL
        let manifest: LocalPMPlanningPluginManifestSummary
        let pluginID: String
        let pluginName: String
        let normalizedPluginID: String
        let pluginVersion: String
    }

    func failedPMExtensionInstallRequest(
        pluginName: String,
        boardMessage: String,
        detail: String
    ) -> PMExtensionInstallRequest? {
        _ = failPMExtensionInstall(
            pluginID: "unknown",
            pluginName: pluginName,
            boardMessage: boardMessage,
            detail: detail
        )
        return nil
    }

    func resolvedPMExtensionInstallRequest(
        from sourceDirectoryPath: String
    ) -> PMExtensionInstallRequest? {
        let trimmedSourcePath = sourceDirectoryPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSourcePath.isEmpty else {
            return failedPMExtensionInstallRequest(
                pluginName: "Unknown",
                boardMessage: message("Extension install failed: source folder is empty"),
                detail: "Install failed: source folder is empty"
            )
        }

        let sourceURL = URL(fileURLWithPath: (trimmedSourcePath as NSString).expandingTildeInPath, isDirectory: true)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: sourceURL.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return failedPMExtensionInstallRequest(
                pluginName: "Unknown",
                boardMessage: message("Extension install failed: source folder not found"),
                detail: "Install failed: source folder not found"
            )
        }

        guard let record = localPMPlanningPluginRecord(at: sourceURL) else {
            return failedPMExtensionInstallRequest(
                pluginName: sourceURL.lastPathComponent,
                boardMessage: message("Extension install failed: plugin.json/manifest.json is missing or invalid"),
                detail: "Install failed: plugin manifest is missing or invalid"
            )
        }

        let pluginID = (record.manifest.id ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !pluginID.isEmpty else {
            return failedPMExtensionInstallRequest(
                pluginName: sourceURL.lastPathComponent,
                boardMessage: message("Extension install failed: plugin id is required"),
                detail: "Install failed: plugin id is required"
            )
        }

        let pluginName = resolvedPMExtensionPluginName(
            from: record,
            fallback: sourceURL.lastPathComponent
        )
        let pluginVersion = (record.manifest.version ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return PMExtensionInstallRequest(
            sourceURL: sourceURL,
            manifest: record.manifest,
            pluginID: pluginID,
            pluginName: pluginName,
            normalizedPluginID: normalizedPMExtensionLookupKey(pluginID),
            pluginVersion: pluginVersion
        )
    }

    func validatePMExtensionInstallPolicy(
        manifest: LocalPMPlanningPluginManifestSummary,
        pluginID: String,
        pluginName: String,
        normalizedPluginID: String,
        pluginVersion: String
    ) -> Bool {
        if let violation = Self.pmExtensionCompatibilityViolation(
            minVersion: manifest.minOpenMacVersion,
            maxVersion: manifest.maxOpenMacVersion
        ) {
            return failBlockedPMExtensionInstall(
                pluginID: pluginID,
                pluginName: pluginName,
                boardMessage: message("Extension install blocked: %@", violation),
                detail: violation
            )
        }

        let pluginChannel = Self.normalizedPMExtensionUpdateChannel(manifest.channel)
        if !Self.isAllowedPMExtensionUpdateChannel(
            pluginChannel,
            preferred: pmPlanningPluginPolicy.preferredMarketplaceChannel
        ) {
            return failBlockedPMExtensionInstall(
                pluginID: pluginID,
                pluginName: pluginName,
                boardMessage: message(
                    "Extension install blocked: %@ channel is not allowed by %@ policy",
                    pluginChannel.title,
                    pmPlanningPluginPolicy.preferredMarketplaceChannel.title
                ),
                detail: "channel \(pluginChannel.rawValue) not allowed"
            )
        }

        if let lockedVersion = pmPlanningPluginPolicy.lockedPluginVersions[normalizedPluginID],
           !pluginVersion.isEmpty,
           pluginVersion != lockedVersion {
            return failBlockedPMExtensionInstall(
                pluginID: pluginID,
                pluginName: pluginName,
                boardMessage: message(
                    "Extension install blocked: %@ is version-locked to %@",
                    pluginID,
                    lockedVersion
                ),
                detail: "locked to \(lockedVersion), incoming \(pluginVersion)"
            )
        }

        return true
    }

    func executeWithinPMExtensionInstallStack(
        normalizedPluginID: String,
        pluginID: String,
        pluginName: String,
        operation: () -> Bool
    ) -> Bool {
        if pmExtensionInstallStack.contains(normalizedPluginID) {
            return failBlockedPMExtensionInstall(
                pluginID: pluginID,
                pluginName: pluginName,
                boardMessage: message("Extension install blocked: cyclic dependency detected for %@", pluginID),
                detail: "cyclic dependency detected"
            )
        }
        pmExtensionInstallStack.insert(normalizedPluginID)
        defer { pmExtensionInstallStack.remove(normalizedPluginID) }
        return operation()
    }

    func installMissingPMExtensionDependencies(
        dependencyRawValues: [String],
        excluding normalizedPluginID: String,
        pluginID: String,
        pluginName: String
    ) -> Bool {
        let installedPluginIDs = Set(pmInstalledExtensions().map {
            normalizedPMExtensionLookupKey($0.pluginID)
        })
        let dependencyIDs = normalizedPMExtensionLookupKeySet(
            dependencyRawValues,
            excluding: [normalizedPluginID]
        )
        for dependencyID in dependencyIDs.sorted() where !installedPluginIDs.contains(dependencyID) {
            appendPMExtensionPluginActivity(
                pluginID: pluginID,
                pluginName: pluginName,
                outcome: .info,
                detail: "Auto-installing dependency: \(dependencyID)"
            )
            guard installPMExtensionByID(dependencyID) else {
                return failBlockedPMExtensionInstall(
                    pluginID: pluginID,
                    pluginName: pluginName,
                    boardMessage: message("Extension install blocked: missing dependency %@", dependencyID),
                    detail: "missing dependency \(dependencyID)"
                )
            }
        }
        return true
    }

    func validatePMExtensionInstallConflicts(
        pluginID: String,
        pluginName: String,
        normalizedPluginID: String,
        conflictsRawValues: [String],
        existingPluginRecords: [LocalPMPlanningPluginRecord]
    ) -> Bool {
        let activePluginIDs = enabledInstalledPMExtensionIDs(
            from: existingPluginRecords
        )
        let newPluginConflicts = normalizedPMExtensionLookupKeySet(
            conflictsRawValues,
            excluding: [normalizedPluginID]
        )
        if let conflictingID = newPluginConflicts.first(where: { activePluginIDs.contains($0) }) {
            return failBlockedPMExtensionInstall(
                pluginID: pluginID,
                pluginName: pluginName,
                boardMessage: message("Extension install blocked: conflicts with installed plugin %@", conflictingID),
                detail: "conflicts with \(conflictingID)"
            )
        }
        if let reverseID = firstReversePMExtensionConflictID(
            for: normalizedPluginID,
            in: existingPluginRecords
        ) {
            return failBlockedPMExtensionInstall(
                pluginID: pluginID,
                pluginName: pluginName,
                boardMessage: message("Extension install blocked: installed plugin %@ conflicts with %@", reverseID, pluginID),
                detail: "reverse conflict from \(reverseID)"
            )
        }
        return true
    }

    func localPMPlannerPluginRecord(
        pluginID: String,
        in records: [LocalPMPlanningPluginRecord]
    ) -> LocalPMPlanningPluginRecord? {
        let trimmedPluginID = pluginID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPluginID.isEmpty else { return nil }
        return records.first(where: { record in
            ((record.manifest.id ?? "").trimmingCharacters(in: .whitespacesAndNewlines)) == trimmedPluginID
        })
    }

    func resolvedPMExtensionInstallDestination(
        destinationRootURL: URL,
        sourceURL: URL,
        pluginID: String,
        existingPluginRecords: [LocalPMPlanningPluginRecord]
    ) -> (existingPluginRecord: LocalPMPlanningPluginRecord?, destinationURL: URL) {
        let baseFolderName = Self.sanitizedExtensionDirectoryName(pluginID, fallback: sourceURL.lastPathComponent)
        let sourceCanonicalPath = sourceURL.standardizedFileURL.path
        let existingPluginRecord = localPMPlannerPluginRecord(
            pluginID: pluginID,
            in: existingPluginRecords
        )
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
        return (existingPluginRecord, destinationURL)
    }

    func resolvedPMExtensionInstallDestinationRootURL(
        pluginID: String,
        pluginName: String
    ) -> URL? {
        let destinationRootPath = (pmPlanningPluginPolicy.pluginsDirectoryPath as NSString).expandingTildeInPath
        let destinationRootURL = URL(fileURLWithPath: destinationRootPath, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: destinationRootURL, withIntermediateDirectories: true)
            return destinationRootURL
        } catch {
            _ = failPMExtensionInstall(
                pluginID: pluginID,
                pluginName: pluginName,
                boardMessage: message("Extension install failed: %@", error.localizedDescription),
                detail: "Install failed: \(error.localizedDescription)"
            )
            return nil
        }
    }

    func appendPMExtensionE2EAcceptanceStep(
        to steps: inout [PMExtensionE2EAcceptanceStep],
        title: String,
        status: PMExtensionE2EAcceptanceStep.Status,
        detail: String
    ) {
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

    func failPMExtensionE2EAcceptanceReport(
        pluginID: String,
        pluginName: String,
        steps: [PMExtensionE2EAcceptanceStep],
        errorDescription: String
    ) -> PMExtensionE2EAcceptanceReport {
        let report = PMExtensionE2EAcceptanceReport(
            generatedAt: Date(),
            pluginID: pluginID,
            pluginName: pluginName,
            succeeded: false,
            steps: steps
        )
        pmExtensionLastAcceptanceReport = report
        lastBoardMessage = message("Extension E2E acceptance failed: %@", errorDescription)
        lastBoardMessageSeverity = .warning
        return report
    }

    func publishPMExtensionE2EAcceptanceReport(
        pluginID: String,
        pluginName: String,
        steps: [PMExtensionE2EAcceptanceStep]
    ) -> PMExtensionE2EAcceptanceReport {
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

    enum PMExtensionE2EToolbarCommandExecutionResult {
        case missing
        case executed(succeeded: Bool, boardMessage: String)
    }

    func writePMExtensionE2EProbePlugin(
        pluginID: String,
        pluginName: String,
        pluginRootURL: URL,
        fileManager: FileManager
    ) throws {
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
    }

    func missingPMExtensionE2ESlots(pluginID: String) -> [String] {
        let slotChecks: [(String, String, Bool)] = [
            ("app.toolbar", Self.extensionE2EToolbarCommandID, pmToolbarExtensionCommands().contains(where: { $0.pluginID == pluginID && $0.commandID == Self.extensionE2EToolbarCommandID })),
            ("kanban.toolbar", Self.extensionE2EKanbanToolbarCommandID, pmKanbanToolbarExtensionCommands().contains(where: { $0.pluginID == pluginID && $0.commandID == Self.extensionE2EKanbanToolbarCommandID })),
            ("kanban.sidebar", Self.extensionE2EKanbanSidebarCommandID, pmKanbanSidebarExtensionCommands().contains(where: { $0.pluginID == pluginID && $0.commandID == Self.extensionE2EKanbanSidebarCommandID })),
            ("marketplace.panel", Self.extensionE2EMarketplacePanelCommandID, pmMarketplacePanelExtensionCommands().contains(where: { $0.pluginID == pluginID && $0.commandID == Self.extensionE2EMarketplacePanelCommandID })),
            ("task.card", Self.extensionE2EHookCommandID, pmTaskCardExtensionCommands().contains(where: { $0.pluginID == pluginID && $0.commandID == Self.extensionE2EHookCommandID }))
        ]
        return slotChecks
            .filter { !$0.2 }
            .map { "\($0.0)=\($0.1)" }
    }

    func executePMExtensionE2EToolbarCommand(pluginID: String) -> PMExtensionE2EToolbarCommandExecutionResult {
        guard let toolbarCommand = pmToolbarExtensionCommands().first(where: {
            $0.pluginID == pluginID && $0.commandID == Self.extensionE2EToolbarCommandID
        }) else {
            return .missing
        }
        let commandSucceeded = runPMExtensionCommand(
            toolbarCommand,
            extensionInputs: ["e2e": "acceptance", "source": "marketplace"]
        )
        return .executed(succeeded: commandSucceeded, boardMessage: lastBoardMessage ?? "")
    }

    func runPMExtensionE2EHookProbe(pluginID: String) -> Bool {
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
        return Self.waitForPMExtensionCondition(timeoutSeconds: 6) { [weak self] in
            guard let self else { return false }
            return self.pmExtensionActivityLog.contains(where: {
                $0.pluginID == pluginID &&
                    $0.commandID == Self.extensionE2EHookCommandID &&
                    $0.outcome == .succeeded
            })
        }
    }

    func pmExtensionE2EWritebackPassed(pluginID: String, toolbarMessage: String) -> Bool {
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
        return writebackFromMessage || writebackFromActivity || writebackFromObservability
    }

    enum PMExtensionInstallFileTransactionResult {
        case succeeded
        case failed(errorDescription: String, rolledBack: Bool)
    }

    func executePMExtensionInstallFileTransaction(
        sourceURL: URL,
        destinationURL: URL,
        backupRootURL: URL,
        backupURL: URL
    ) -> PMExtensionInstallFileTransactionResult {
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
            return .succeeded
        } catch {
            if movedToBackup {
                try? FileManager.default.removeItem(at: destinationURL)
                if FileManager.default.fileExists(atPath: backupURL.path) {
                    try? FileManager.default.moveItem(at: backupURL, to: destinationURL)
                }
            }
            return .failed(
                errorDescription: error.localizedDescription,
                rolledBack: movedToBackup
            )
        }
    }

    func normalizedPMExtensionLookupKeySet(
        _ rawValues: [String],
        excluding excluded: Set<String> = []
    ) -> Set<String> {
        Set(rawValues.map(normalizedPMExtensionLookupKey))
            .subtracting([""])
            .subtracting(excluded)
    }

    func enabledInstalledPMExtensionIDs(
        from records: [LocalPMPlanningPluginRecord]
    ) -> Set<String> {
        Set(records.compactMap { item -> String? in
            let installedID = normalizedPMExtensionLookupKey(item.manifest.id ?? "")
            guard !installedID.isEmpty else { return nil }
            guard !pmPlanningPluginPolicy.disabledPluginIDs.contains(installedID) else { return nil }
            return installedID
        })
    }

    func firstReversePMExtensionConflictID(
        for normalizedPluginID: String,
        in records: [LocalPMPlanningPluginRecord]
    ) -> String? {
        for item in records {
            let installedID = normalizedPMExtensionLookupKey(item.manifest.id ?? "")
            guard !installedID.isEmpty, installedID != normalizedPluginID else { continue }
            guard !pmPlanningPluginPolicy.disabledPluginIDs.contains(installedID) else { continue }
            let conflicts = normalizedPMExtensionLookupKeySet(item.manifest.conflictsWith ?? [])
            guard conflicts.contains(normalizedPluginID) else { continue }
            let reverseID = (item.manifest.id ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return reverseID.isEmpty ? installedID : reverseID
        }
        return nil
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
        persistPMPlanningPolicyChange(
            infoMessage: announce ? message("Updated PM plugin settings") : nil
        )
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
            return failPMExtensionOperation("Marketplace source is required")
        }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedName = trimmedName.isEmpty ? trimmedSource : trimmedName
        let duplicate = pmPlanningPluginPolicy.marketplaceSources.contains {
            normalizedPMExtensionLookupKey($0.source) == normalizedPMExtensionLookupKey(trimmedSource)
        }
        guard !duplicate else {
            return failPMExtensionOperation("Marketplace source already exists")
        }

        var sources = pmPlanningPluginPolicy.marketplaceSources
        sources.append(PMExtensionMarketplaceSource(name: resolvedName, source: trimmedSource))
        updatePMPlanningPolicyState(marketplaceSources: sources)
        persistPMPlanningPolicyChange(
            infoMessage: message("Added marketplace source: %@", resolvedName)
        )
        return true
    }

    @discardableResult
    func removePMExtensionMarketplaceSource(id: UUID) -> Bool {
        let original = pmPlanningPluginPolicy.marketplaceSources
        let filtered = original.filter { $0.id != id }
        guard filtered.count != original.count else { return false }
        updatePMPlanningPolicyState(marketplaceSources: filtered)
        persistPMPlanningPolicyChange(
            infoMessage: message("Removed marketplace source")
        )
        return true
    }

    @discardableResult
    func installPMExtensionFromMarketplaceSource(id: UUID) -> Bool {
        guard let source = pmPlanningPluginPolicy.marketplaceSources.first(where: { $0.id == id }) else { return false }
        return installPMExtensionFromRemote(source.source)
    }

    @discardableResult
    func installPMExtensionByID(_ pluginID: String) -> Bool {
        let normalizedTarget = normalizedPMExtensionLookupKey(pluginID)
        guard !normalizedTarget.isEmpty else {
            return failPMExtensionOperation("Extension id is required")
        }

        let candidates = pmExtensionSourceCandidates(for: normalizedTarget)
        guard let candidate = candidates.first else {
            return failPMExtensionOperation("Extension not found in configured marketplace sources: %@", pluginID)
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
        let normalizedPluginID = normalizedPMExtensionLookupKey(pluginID)
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
        persistPMPlanningPolicyChange(
            infoMessage: enabled
                ? message("Enabled extension: %@", pluginID)
                : message("Disabled extension: %@", pluginID)
        )
        return true
    }

    func pmPreferredExtensionChannel() -> PMExtensionUpdateChannel {
        pmPlanningPluginPolicy.preferredMarketplaceChannel
    }

    func updatePMPreferredExtensionChannel(_ channel: PMExtensionUpdateChannel) {
        guard channel != pmPlanningPluginPolicy.preferredMarketplaceChannel else { return }
        updatePMPlanningPolicyState(preferredMarketplaceChannel: channel)
        persistPMPlanningPolicyChange(
            infoMessage: message("Updated extension update channel: %@", channel.title)
        )
    }

    func pmLockedExtensionVersions() -> [String: String] {
        pmPlanningPluginPolicy.lockedPluginVersions
    }

    @discardableResult
    func lockPMExtensionToInstalledVersion(pluginID: String) -> Bool {
        let normalizedPluginID = normalizedPMExtensionLookupKey(pluginID)
        guard !normalizedPluginID.isEmpty else { return false }
        guard let installed = pmInstalledExtensions().first(where: {
            normalizedPMExtensionLookupKey($0.pluginID) == normalizedPluginID
        }) else {
            return false
        }
        var locks = pmPlanningPluginPolicy.lockedPluginVersions
        locks[normalizedPluginID] = installed.version
        updatePMPlanningPolicyState(lockedPluginVersions: locks)
        persistPMPlanningPolicyChange(
            infoMessage: message("Locked extension %@ to version %@", installed.name, installed.version)
        )
        return true
    }

    @discardableResult
    func unlockPMExtensionVersion(pluginID: String) -> Bool {
        let normalizedPluginID = normalizedPMExtensionLookupKey(pluginID)
        guard !normalizedPluginID.isEmpty else { return false }
        var locks = pmPlanningPluginPolicy.lockedPluginVersions
        guard locks.removeValue(forKey: normalizedPluginID) != nil else { return false }
        updatePMPlanningPolicyState(lockedPluginVersions: locks)
        persistPMPlanningPolicyChange(
            infoMessage: message("Unlocked extension version: %@", pluginID)
        )
        return true
    }

    func pmInstalledExtensions() -> [PMInstalledExtensionDescriptor] {
        detectedLocalPMPlannerPluginRecords(in: pmPlanningPluginPolicy.pluginsDirectoryPath)
            .map { record in
                let pluginID = (record.manifest.id ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                let name = resolvedPMExtensionPluginName(from: record)
                let version = (record.manifest.version ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                let summary = (record.manifest.summary ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                let capabilities = record.manifest.capabilities ?? []
                let commands = (record.manifest.commands ?? []).filter { $0.enabled ?? true }
                let uiExtensions = (record.manifest.uiExtensions ?? []).filter { $0.enabled ?? true }
                let normalizedPluginID = normalizedPMExtensionLookupKey(
                    pluginID.isEmpty ? name : pluginID
                )
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
                guard !pmPlanningPluginPolicy.disabledPluginIDs.contains(
                    normalizedPMExtensionLookupKey(pluginID)
                ) else { return [] }
                let pluginName = resolvedPMExtensionPluginName(from: record)
                return (record.manifest.commands ?? []).compactMap { command in
                    guard command.enabled ?? true else { return nil }
                    guard let descriptor = pmExtensionCommandDescriptor(
                        pluginID: pluginID,
                        pluginName: pluginName,
                        commandManifest: command,
                        fallbackPermissions: record.manifest.permissions ?? []
                    ) else { return nil }
                    if !normalizedFilter.isEmpty, !descriptor.slots.contains(normalizedFilter) {
                        return nil
                    }
                    return descriptor
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

    func resolvedPMExtensionPluginName(
        from record: LocalPMPlanningPluginRecord,
        fallback: String? = nil
    ) -> String {
        let trimmed = (record.manifest.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            return trimmed
        }
        if let fallback {
            let trimmedFallback = fallback.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedFallback.isEmpty {
                return trimmedFallback
            }
        }
        return record.directoryURL.lastPathComponent
    }

    func pmInstalledExtensionNamesByPluginID() -> [String: String] {
        Dictionary(
            uniqueKeysWithValues: pmInstalledExtensions().map { ($0.pluginID.lowercased(), $0.name) }
        )
    }

    func resolvedPMInstalledExtensionName(
        pluginID: String,
        installedByPluginID: [String: String]
    ) -> String {
        installedByPluginID[pluginID.lowercased()] ?? pluginID
    }

    func pmExtensionCommandDescriptor(
        pluginID: String,
        pluginName: String,
        commandManifest: LocalPMPlanningCommandManifestSummary,
        fallbackPermissions: [String]
    ) -> PMExtensionCommandDescriptor? {
        let commandID = (commandManifest.id ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !commandID.isEmpty else { return nil }
        let commandSlots = Self.normalizedExtensionCommandSlots(
            commandManifest.slots,
            singleSlot: commandManifest.slot
        )
        let title = {
            let trimmed = (commandManifest.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? commandID : trimmed
        }()
        let subtitle = (commandManifest.subtitle ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let permissions = Self.normalizedExtensionPermissions(
            commandManifest.permissions ?? fallbackPermissions
        )
        return PMExtensionCommandDescriptor(
            id: "\(pluginID).\(commandID)",
            pluginID: pluginID,
            pluginName: pluginName,
            commandID: commandID,
            title: title,
            subtitle: subtitle,
            slots: commandSlots,
            permissions: permissions,
            timeoutSeconds: Self.resolvedExtensionCommandTimeout(commandManifest.timeoutSeconds),
            entrypoint: (commandManifest.entrypoint ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    func normalizedPMExtensionCommandLookupKey(
        pluginID: String,
        commandID: String
    ) -> String {
        let normalizedPluginID = normalizedPMExtensionLookupKey(pluginID)
        let normalizedCommandID = commandID
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return "\(normalizedPluginID)|\(normalizedCommandID)"
    }

    func pmExtensionCommandLookupTable(
        descriptors: [PMExtensionCommandDescriptor]
    ) -> [String: PMExtensionCommandDescriptor] {
        var lookup: [String: PMExtensionCommandDescriptor] = [:]
        for descriptor in descriptors {
            let key = normalizedPMExtensionCommandLookupKey(
                pluginID: descriptor.pluginID,
                commandID: descriptor.commandID
            )
            lookup[key] = descriptor
        }
        return lookup
    }

    func resolvedPMExtensionCommandDescriptor(
        pluginID: String,
        commandID: String,
        lookupTable: [String: PMExtensionCommandDescriptor]
    ) -> PMExtensionCommandDescriptor? {
        let key = normalizedPMExtensionCommandLookupKey(
            pluginID: pluginID,
            commandID: commandID
        )
        return lookupTable[key]
    }

    func pmBoardExtensionHookBindingMatchesCommand(
        _ binding: PMBoardExtensionHookBinding,
        pluginID: String,
        commandID: String
    ) -> Bool {
        let bindingKey = normalizedPMExtensionCommandLookupKey(
            pluginID: binding.pluginID,
            commandID: binding.commandID
        )
        let targetKey = normalizedPMExtensionCommandLookupKey(
            pluginID: pluginID,
            commandID: commandID
        )
        return bindingKey == targetKey
    }

    func systemPMExtensionCommands(slot normalizedFilter: String) -> [PMExtensionCommandDescriptor] {
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
        let commandLookup = pmExtensionCommandLookupTable(descriptors: commands)
        let installedByPluginID = pmInstalledExtensionNamesByPluginID()
        return pmBoardExtensionHookBindings.map { binding in
            let matchingCommand = resolvedPMExtensionCommandDescriptor(
                pluginID: binding.pluginID,
                commandID: binding.commandID,
                lookupTable: commandLookup
            )
            let pluginName = matchingCommand?.pluginName
                ?? resolvedPMInstalledExtensionName(
                    pluginID: binding.pluginID,
                    installedByPluginID: installedByPluginID
                )
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
                pmBoardExtensionHookBindingMatchesCommand(
                    binding,
                    pluginID: descriptor.pluginID,
                    commandID: descriptor.commandID
                )
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

    struct PreparedPMExtensionCommandExecution {
        let descriptor: PMExtensionCommandDescriptor
        let workingDirectoryPath: String
        let shellCommand: String
        let payloadJSON: String
        let timeoutSeconds: Int
        let startedAt: Date
    }

    struct PMExtensionCommandExecutionOutcome {
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

    func isSystemPMExtensionCommand(_ descriptor: PMExtensionCommandDescriptor) -> Bool {
        descriptor.pluginID.caseInsensitiveCompare(Self.systemExtensionPluginID) == .orderedSame
    }

    func beginPMExtensionCommandRun(
        descriptor: PMExtensionCommandDescriptor,
        extensionInputs: [String: String]
    ) -> Date {
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
        return startedAt
    }

    @discardableResult
    func runSystemPMExtensionCommand(
        _ descriptor: PMExtensionCommandDescriptor,
        task: WorkTask?,
        extensionInputs: [String: String]
    ) -> Bool {
        let startedAt = beginPMExtensionCommandRun(
            descriptor: descriptor,
            extensionInputs: extensionInputs
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

    func runSystemPMExtensionCommandInBackground(
        _ descriptor: PMExtensionCommandDescriptor,
        task: WorkTask?,
        extensionInputs: [String: String],
        completion: @escaping (Bool) -> Void
    ) {
        let startedAt = beginPMExtensionCommandRun(
            descriptor: descriptor,
            extensionInputs: extensionInputs
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

    func executeSystemPMExtensionCommand(
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

    func failPMExtensionCommandPreparation(
        descriptor: PMExtensionCommandDescriptor,
        boardMessage: String,
        detail: String
    ) -> PreparedPMExtensionCommandExecution? {
        lastBoardMessage = boardMessage
        lastBoardMessageSeverity = .warning
        appendPMExtensionActivity(
            pluginID: descriptor.pluginID,
            pluginName: descriptor.pluginName,
            commandID: descriptor.commandID,
            commandTitle: descriptor.title,
            outcome: .failed,
            detail: detail
        )
        return nil
    }

    func localPMExtensionCommandRecord(
        for descriptor: PMExtensionCommandDescriptor
    ) -> LocalPMPlanningPluginRecord? {
        let records = detectedLocalPMPlannerPluginRecords(
            in: pmPlanningPluginPolicy.pluginsDirectoryPath
        )
        return localPMPlannerPluginRecord(pluginID: descriptor.pluginID, in: records)
    }

    func validatedLocalPMExtensionCommandRecord(
        for descriptor: PMExtensionCommandDescriptor
    ) -> LocalPMPlanningPluginRecord? {
        if pmPlanningPluginPolicy.disabledPluginIDs.contains(descriptor.pluginID.lowercased()) {
            _ = failPMExtensionCommandPreparation(
                descriptor: descriptor,
                boardMessage: message("Extension command failed: plugin is disabled"),
                detail: "Plugin is disabled"
            )
            return nil
        }
        guard let record = localPMExtensionCommandRecord(for: descriptor) else {
            _ = failPMExtensionCommandPreparation(
                descriptor: descriptor,
                boardMessage: message("Extension command failed: plugin not found"),
                detail: "Plugin not found"
            )
            return nil
        }
        return record
    }

    func resolvedPMExtensionCommandEntrypoint(
        descriptor: PMExtensionCommandDescriptor,
        record: LocalPMPlanningPluginRecord
    ) -> String {
        let commandEntrypoint = (descriptor.entrypoint ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !commandEntrypoint.isEmpty {
            return commandEntrypoint
        }
        return (record.manifest.entrypoint ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func resolvedPMExtensionCommandEntrypointPath(
        entrypoint: String,
        record: LocalPMPlanningPluginRecord
    ) -> String {
        if entrypoint.hasPrefix("/") || entrypoint.hasPrefix("~") {
            return (entrypoint as NSString).expandingTildeInPath
        }
        return record.directoryURL.appendingPathComponent(entrypoint).path
    }

    func validatedPMExtensionCommandEntrypoint(
        descriptor: PMExtensionCommandDescriptor,
        record: LocalPMPlanningPluginRecord
    ) -> String? {
        let entrypoint = resolvedPMExtensionCommandEntrypoint(
            descriptor: descriptor,
            record: record
        )
        guard !entrypoint.isEmpty else {
            _ = failPMExtensionCommandPreparation(
                descriptor: descriptor,
                boardMessage: message("Extension command failed: plugin entrypoint is missing"),
                detail: "Entrypoint is missing"
            )
            return nil
        }
        return entrypoint
    }

    func hasValidPMExtensionCommandPermissions(
        descriptor: PMExtensionCommandDescriptor,
        declaredPermissions: Set<String>
    ) -> Bool {
        if !declaredPermissions.isEmpty,
           !declaredPermissions.contains(Self.extensionCommandRequiredPermission) {
            _ = failPMExtensionCommandPreparation(
                descriptor: descriptor,
                boardMessage: message(
                    "Extension command blocked: missing %@ permission",
                    Self.extensionCommandRequiredPermission
                ),
                detail: "Missing permission: \(Self.extensionCommandRequiredPermission)"
            )
            return false
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
        return true
    }

    func pmExtensionCommandPayloadJSON(
        descriptor: PMExtensionCommandDescriptor,
        task: WorkTask?,
        extensionInputs: [String: String]
    ) -> String? {
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
            return nil
        }
        return payloadJSON
    }

    func validatedPMExtensionCommandPayloadJSON(
        descriptor: PMExtensionCommandDescriptor,
        task: WorkTask?,
        extensionInputs: [String: String]
    ) -> String? {
        guard let payloadJSON = pmExtensionCommandPayloadJSON(
            descriptor: descriptor,
            task: task,
            extensionInputs: extensionInputs
        ) else {
            _ = failPMExtensionCommandPreparation(
                descriptor: descriptor,
                boardMessage: message("Extension command failed: could not build payload"),
                detail: "Could not build command payload"
            )
            return nil
        }
        return payloadJSON
    }

    func preparePMExtensionCommandExecution(
        _ descriptor: PMExtensionCommandDescriptor,
        task: WorkTask?,
        extensionInputs: [String: String]
    ) -> PreparedPMExtensionCommandExecution? {
        guard let record = validatedLocalPMExtensionCommandRecord(for: descriptor) else {
            return nil
        }
        guard let entrypoint = validatedPMExtensionCommandEntrypoint(
            descriptor: descriptor,
            record: record
        ) else {
            return nil
        }

        let declaredPermissions = Set(Self.normalizedExtensionPermissions(descriptor.permissions))
        guard hasValidPMExtensionCommandPermissions(
            descriptor: descriptor,
            declaredPermissions: declaredPermissions
        ) else {
            return nil
        }

        let resolvedEntrypointPath = resolvedPMExtensionCommandEntrypointPath(
            entrypoint: entrypoint,
            record: record
        )
        guard let payloadJSON = validatedPMExtensionCommandPayloadJSON(
            descriptor: descriptor,
            task: task,
            extensionInputs: extensionInputs
        ) else {
            return nil
        }

        let startedAt = beginPMExtensionCommandRun(
            descriptor: descriptor,
            extensionInputs: extensionInputs
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

    static func failedPMExtensionCommandExecutionOutcome(
        detail: String,
        outputSummary: String? = nil
    ) -> PMExtensionCommandExecutionOutcome {
        PMExtensionCommandExecutionOutcome(
            succeeded: false,
            responseMessage: nil,
            detail: detail,
            outputSummary: outputSummary ?? summarizedExtensionOutput(detail),
            error: detail
        )
    }

    static func succeededPMExtensionCommandExecutionOutcome(
        responseMessage: String?,
        stdout: String
    ) -> PMExtensionCommandExecutionOutcome {
        let detail = responseMessage ?? "Completed"
        return PMExtensionCommandExecutionOutcome(
            succeeded: true,
            responseMessage: responseMessage,
            detail: detail,
            outputSummary: summarizedExtensionOutput(responseMessage ?? stdout),
            error: nil
        )
    }

    static func executePMExtensionCommand(
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
                return failedPMExtensionCommandExecutionOutcome(
                    detail: detail,
                    outputSummary: detail
                )
            }

            if result.code != 0 {
                let stderr = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                let details = stderr.isEmpty ? result.stdout : stderr
                let detail = details.isEmpty ? "exit \(result.code)" : details
                return failedPMExtensionCommandExecutionOutcome(detail: detail)
            }

            let stdout = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            let responseMessage = decodedPMExtensionCommandResponseMessage(from: stdout)
            return succeededPMExtensionCommandExecutionOutcome(
                responseMessage: responseMessage,
                stdout: stdout
            )
        } catch {
            let detail = error.localizedDescription
            return failedPMExtensionCommandExecutionOutcome(detail: detail)
        }
    }

    @discardableResult
    func finishPMExtensionCommandExecution(
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

    func publishSucceededPMExtensionCommandExecution(
        descriptor: PMExtensionCommandDescriptor,
        outcome: PMExtensionCommandExecutionOutcome
    ) {
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
    }

    func publishFailedPMExtensionCommandExecution(
        descriptor: PMExtensionCommandDescriptor,
        timeoutSeconds: Int?,
        outcome: PMExtensionCommandExecutionOutcome
    ) {
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

    func pmExtensionHookMergedInputs(
        additionalInputs: [String: String],
        eventKey: String,
        hookSource: String,
        hookBindingID: UUID?,
        task: WorkTask?
    ) -> [String: String] {
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
        return mergedInputs
    }

    func pmExtensionHookDedupKey(
        eventKey: String,
        descriptor: PMExtensionCommandDescriptor,
        task: WorkTask?
    ) -> String {
        let dedupTaskID = task?.id.uuidString ?? "none"
        return "\(eventKey)|\(descriptor.pluginID.lowercased())|\(descriptor.commandID.lowercased())|\(dedupTaskID)"
    }

    func appendMissingPMExtensionHookCommandActivity(
        pluginID: String,
        pluginName: String,
        commandID: String,
        hookSource: String
    ) {
        appendPMExtensionActivity(
            pluginID: pluginID,
            pluginName: pluginName,
            commandID: commandID,
            commandTitle: commandID,
            outcome: .info,
            detail: "Hook skipped: command not found (\(hookSource))"
        )
    }

    func enqueuePMExtensionHookDescriptor(
        event: PMExtensionHookEvent,
        eventKey: String,
        descriptor: PMExtensionCommandDescriptor,
        task: WorkTask?,
        additionalInputs: [String: String],
        hookSource: String,
        hookBindingID: UUID? = nil
    ) {
        let mergedInputs = pmExtensionHookMergedInputs(
            additionalInputs: additionalInputs,
            eventKey: eventKey,
            hookSource: hookSource,
            hookBindingID: hookBindingID,
            task: task
        )
        let key = pmExtensionHookDedupKey(
            eventKey: eventKey,
            descriptor: descriptor,
            task: task
        )
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

    func resolvedPMExtensionHookManifestCommandDescriptor(
        commandID: String,
        pluginID: String,
        pluginName: String,
        commands: [LocalPMPlanningCommandManifestSummary],
        fallbackPermissions: [String]
    ) -> (foundManifest: Bool, descriptor: PMExtensionCommandDescriptor?) {
        guard let commandManifest = commands.first(where: {
            (($0.id ?? "").trimmingCharacters(in: .whitespacesAndNewlines))
                .caseInsensitiveCompare(commandID) == .orderedSame
        }) else {
            return (false, nil)
        }
        let descriptor = pmExtensionCommandDescriptor(
            pluginID: pluginID,
            pluginName: pluginName,
            commandManifest: commandManifest,
            fallbackPermissions: fallbackPermissions
        )
        return (true, descriptor)
    }

    @discardableResult
    func finishPMExtensionCommandExecution(
        descriptor: PMExtensionCommandDescriptor,
        startedAt: Date,
        timeoutSeconds: Int?,
        outcome: PMExtensionCommandExecutionOutcome
    ) -> Bool {
        if outcome.succeeded {
            publishSucceededPMExtensionCommandExecution(
                descriptor: descriptor,
                outcome: outcome
            )
        } else {
            publishFailedPMExtensionCommandExecution(
                descriptor: descriptor,
                timeoutSeconds: timeoutSeconds,
                outcome: outcome
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
        let knownCommandLookup = pmExtensionCommandLookupTable(
            descriptors: pmExtensionCommands()
        )
        let installedByPluginID = pmInstalledExtensionNamesByPluginID()

        let records = detectedLocalPMPlannerPluginRecords(in: pmPlanningPluginPolicy.pluginsDirectoryPath)
        for record in records {
            let pluginID = (record.manifest.id ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !pluginID.isEmpty else { continue }
            guard !pmPlanningPluginPolicy.disabledPluginIDs.contains(pluginID.lowercased()) else { continue }

            let pluginName = resolvedPMExtensionPluginName(from: record)
            let commands = (record.manifest.commands ?? []).filter { $0.enabled ?? true }
            let hooks = (record.manifest.eventHooks ?? []).filter { $0.enabled ?? true }

            for hook in hooks {
                let hookEvent = Self.normalizedPMExtensionHookEvent(hook.event ?? "")
                guard hookEvent == eventKey else { continue }
                let commandID = (hook.commandID ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                guard !commandID.isEmpty else { continue }

                let resolved = resolvedPMExtensionHookManifestCommandDescriptor(
                    commandID: commandID,
                    pluginID: pluginID,
                    pluginName: pluginName,
                    commands: commands,
                    fallbackPermissions: record.manifest.permissions ?? []
                )
                guard resolved.foundManifest else {
                    appendMissingPMExtensionHookCommandActivity(
                        pluginID: pluginID,
                        pluginName: pluginName,
                        commandID: commandID,
                        hookSource: "manifest"
                    )
                    continue
                }
                guard let descriptor = resolved.descriptor else { continue }
                enqueuePMExtensionHookDescriptor(
                    event: event,
                    eventKey: eventKey,
                    descriptor: descriptor,
                    task: task,
                    additionalInputs: additionalInputs,
                    hookSource: "manifest"
                )
            }
        }

        let boardHooks = pmBoardExtensionHookBindings.filter { binding in
            binding.isEnabled && binding.event.rawValue == eventKey
        }
        for binding in boardHooks {
            guard let descriptor = resolvedPMExtensionCommandDescriptor(
                pluginID: binding.pluginID,
                commandID: binding.commandID,
                lookupTable: knownCommandLookup
            ) else {
                let pluginName = resolvedPMInstalledExtensionName(
                    pluginID: binding.pluginID,
                    installedByPluginID: installedByPluginID
                )
                appendMissingPMExtensionHookCommandActivity(
                    pluginID: binding.pluginID,
                    pluginName: pluginName,
                    commandID: binding.commandID,
                    hookSource: "board"
                )
                continue
            }
            enqueuePMExtensionHookDescriptor(
                event: event,
                eventKey: eventKey,
                descriptor: descriptor,
                task: task,
                additionalInputs: additionalInputs,
                hookSource: "board",
                hookBindingID: binding.id
            )
        }
        drainPMExtensionHookQueueIfNeeded()
    }

    @discardableResult
    func installPMExtensionFromDirectory(_ sourceDirectoryPath: String) -> Bool {
        guard let installRequest = resolvedPMExtensionInstallRequest(from: sourceDirectoryPath) else {
            return false
        }

        let sourceURL = installRequest.sourceURL
        let manifest = installRequest.manifest
        let pluginID = installRequest.pluginID
        let pluginName = installRequest.pluginName
        let normalizedPluginID = installRequest.normalizedPluginID
        let pluginVersion = installRequest.pluginVersion
        return executeWithinPMExtensionInstallStack(
            normalizedPluginID: normalizedPluginID,
            pluginID: pluginID,
            pluginName: pluginName
        ) {
            guard validatePMExtensionInstallPolicy(
                manifest: manifest,
                pluginID: pluginID,
                pluginName: pluginName,
                normalizedPluginID: normalizedPluginID,
                pluginVersion: pluginVersion
            ) else { return false }

            guard installMissingPMExtensionDependencies(
                dependencyRawValues: manifest.dependencies ?? [],
                excluding: normalizedPluginID,
                pluginID: pluginID,
                pluginName: pluginName,
            ) else { return false }
            appendPMExtensionPluginActivity(
                pluginID: pluginID,
                pluginName: pluginName,
                outcome: .running,
                detail: "Installing from folder: \(sourceURL.path)"
            )

            guard let destinationRootURL = resolvedPMExtensionInstallDestinationRootURL(
                pluginID: pluginID,
                pluginName: pluginName
            ) else { return false }

            let existingPluginRecords = detectedLocalPMPlannerPluginRecords(in: destinationRootURL.path)
            guard validatePMExtensionInstallConflicts(
                pluginID: pluginID,
                pluginName: pluginName,
                normalizedPluginID: normalizedPluginID,
                conflictsRawValues: manifest.conflictsWith ?? [],
                existingPluginRecords: existingPluginRecords
            ) else { return false }

            let sourceCanonicalPath = sourceURL.standardizedFileURL.path
            let destination = resolvedPMExtensionInstallDestination(
                destinationRootURL: destinationRootURL,
                sourceURL: sourceURL,
                pluginID: pluginID,
                existingPluginRecords: existingPluginRecords
            )
            let existingPluginRecord = destination.existingPluginRecord
            let destinationURL = destination.destinationURL

            if destinationURL.standardizedFileURL.path == sourceCanonicalPath {
                return completePMExtensionInstall(
                    pluginID: pluginID,
                    pluginName: pluginName,
                    boardMessage: message("Extension already installed: %@", pluginName),
                    outcome: .info,
                    detail: "Install skipped: already installed"
                )
            }

            if let existingPluginRecord {
                let installedVersion = (existingPluginRecord.manifest.version ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                if !pluginVersion.isEmpty, installedVersion == pluginVersion {
                    return completePMExtensionInstall(
                        pluginID: pluginID,
                        pluginName: pluginName,
                        boardMessage: message("Extension already up to date: %@ (v%@)", pluginName, pluginVersion),
                        outcome: .info,
                        detail: "Already up to date (v\(pluginVersion))"
                    )
                }
            }

            let previousVersion = (existingPluginRecord?.manifest.version ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let backupRootURL = destinationRootURL.appendingPathComponent(".openmac-extension-backups", isDirectory: true)
            let backupFolderName = Self.sanitizedExtensionDirectoryName(pluginID, fallback: sourceURL.lastPathComponent)
            let backupURL = backupRootURL.appendingPathComponent("\(backupFolderName)-\(UUID().uuidString)", isDirectory: true)
            switch executePMExtensionInstallFileTransaction(
                sourceURL: sourceURL,
                destinationURL: destinationURL,
                backupRootURL: backupRootURL,
                backupURL: backupURL
            ) {
            case .succeeded:
                let isUpdate = existingPluginRecord != nil
                let transition = Self.pmExtensionVersionTransitionLabel(
                    previousVersion: previousVersion,
                    incomingVersion: pluginVersion
                )
                let boardMessage = isUpdate
                    ? message("Updated PM extension: %@", pluginName)
                    : message("Installed PM extension: %@", pluginName)
                return completePMExtensionInstall(
                    pluginID: pluginID,
                    pluginName: pluginName,
                    boardMessage: boardMessage,
                    outcome: .succeeded,
                    detail: transition
                )
            case let .failed(errorDescription, rolledBack):
                return failPMExtensionInstall(
                    pluginID: pluginID,
                    pluginName: pluginName,
                    boardMessage: message("Extension install failed: %@", errorDescription),
                    detail: rolledBack
                        ? "Install failed and rolled back: \(errorDescription)"
                        : "Install failed: \(errorDescription)"
                )
            }
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
        guard let record = localPMPlannerPluginRecord(
            pluginID: trimmedPluginID,
            in: records
        ) else {
            return failPMExtensionUninstall(
                pluginID: trimmedPluginID,
                pluginName: trimmedPluginID,
                boardMessage: message("Extension remove failed: plugin not found"),
                detail: "Remove failed: plugin not found"
            )
        }

        do {
            try FileManager.default.removeItem(at: record.directoryURL)
            let resolvedPluginName = resolvedPMExtensionPluginName(
                from: record,
                fallback: trimmedPluginID
            )
            let normalizedPluginID = normalizedPMExtensionLookupKey(trimmedPluginID)
            var disabled = pmPlanningPluginPolicy.disabledPluginIDs
            disabled.remove(normalizedPluginID)
            var locks = pmPlanningPluginPolicy.lockedPluginVersions
            locks.removeValue(forKey: normalizedPluginID)
            updatePMPlanningPolicyState(disabledPluginIDs: disabled, lockedPluginVersions: locks)
            persistBoardState()
            return completePMExtensionUninstall(
                pluginID: trimmedPluginID,
                pluginName: resolvedPluginName,
                boardMessage: message(
                    "Removed PM extension: %@",
                    resolvedPluginName
                ),
                detail: "Removed"
            )
        } catch {
            return failPMExtensionUninstall(
                pluginID: trimmedPluginID,
                pluginName: trimmedPluginID,
                boardMessage: message("Extension remove failed: %@", error.localizedDescription),
                detail: "Remove failed: \(error.localizedDescription)"
            )
        }
    }

    @discardableResult
    func installPMExtensionFromRemote(_ remoteSource: String) -> Bool {
        guard let preparedWorkspace = preparedPMExtensionRemoteInstallWorkspace(
            remoteSource: remoteSource
        ) else {
            return false
        }

        let trimmedSource = preparedWorkspace.trimmedSource
        let workspace = preparedWorkspace.workspace
        let fileManager = workspace.fileManager
        let tempRootURL = workspace.tempRootURL
        let extractionRootURL = workspace.extractionRootURL
        defer { try? fileManager.removeItem(at: tempRootURL) }

        appendRemotePMExtensionActivity(
            outcome: .running,
            detail: "Fetching extension source: \(trimmedSource)"
        )

        let sourceResolution = resolvePMExtensionRemoteSourceRoot(
            trimmedSource,
            extractionRootURL: extractionRootURL,
            tempRootURL: tempRootURL,
            fileManager: fileManager
        )
        let candidateRootURL: URL
        switch sourceResolution {
        case let .resolved(url):
            candidateRootURL = url
        case .failed:
            return false
        case .unsupported:
            return failRemotePMExtensionInstall(
                boardMessage: message("Extension install failed: unsupported source"),
                detail: "Unsupported source"
            )
        }

        let pluginRootURL = firstPMExtensionDirectoryCandidate(in: candidateRootURL) ?? candidateRootURL
        let installed = installPMExtensionFromDirectory(pluginRootURL.path)
        if installed {
            appendRemotePMExtensionActivity(
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

        let fileManager = FileManager.default
        let tempRootURL = fileManager.temporaryDirectory
            .appendingPathComponent("openmac-extension-e2e-\(UUID().uuidString)", isDirectory: true)
        let pluginRootURL = tempRootURL.appendingPathComponent("probe", isDirectory: true)
        defer { try? fileManager.removeItem(at: tempRootURL) }

        do {
            try writePMExtensionE2EProbePlugin(
                pluginID: pluginID,
                pluginName: pluginName,
                pluginRootURL: pluginRootURL,
                fileManager: fileManager
            )
            appendPMExtensionE2EAcceptanceStep(
                to: &steps,
                title: "Create Probe Plugin",
                status: .passed,
                detail: pluginRootURL.path
            )
        } catch {
            appendPMExtensionE2EAcceptanceStep(
                to: &steps,
                title: "Create Probe Plugin",
                status: .failed,
                detail: error.localizedDescription
            )
            return failPMExtensionE2EAcceptanceReport(
                pluginID: pluginID,
                pluginName: pluginName,
                steps: steps,
                errorDescription: error.localizedDescription
            )
        }

        let installed = installPMExtensionFromDirectory(pluginRootURL.path)
        appendPMExtensionE2EAcceptanceStep(
            to: &steps,
            title: "Install Extension",
            status: installed ? .passed : .failed,
            detail: installed ? "Installed \(pluginID)" : (lastBoardMessage ?? "Install failed")
        )

        if installed {
            let disableApplied = setPMExtensionEnabled(pluginID: pluginID, enabled: false)
            let hiddenWhileDisabled = !pmExtensionCommands().contains(where: { $0.pluginID == pluginID })
            let enableApplied = setPMExtensionEnabled(pluginID: pluginID, enabled: true)
            let visibleWhenEnabled = pmExtensionCommands().contains(where: { $0.pluginID == pluginID })
            let enablePassed = disableApplied && hiddenWhileDisabled && enableApplied && visibleWhenEnabled
            appendPMExtensionE2EAcceptanceStep(
                to: &steps,
                title: "Enable Toggle",
                status: enablePassed ? .passed : .failed,
                detail: enablePassed
                    ? "Disable/enable flow validated"
                    : "disableApplied=\(disableApplied) hidden=\(hiddenWhileDisabled) enableApplied=\(enableApplied) visible=\(visibleWhenEnabled)"
            )
        } else {
            appendPMExtensionE2EAcceptanceStep(
                to: &steps,
                title: "Enable Toggle",
                status: .skipped,
                detail: "Skipped because install failed"
            )
        }

        let missingSlots = missingPMExtensionE2ESlots(pluginID: pluginID)
        appendPMExtensionE2EAcceptanceStep(
            to: &steps,
            title: "Slot Contributions",
            status: missingSlots.isEmpty ? .passed : .failed,
            detail: missingSlots.isEmpty ? "All expected slots are discoverable" : "Missing: \(missingSlots.joined(separator: ", "))"
        )

        var toolbarMessage = ""
        switch executePMExtensionE2EToolbarCommand(pluginID: pluginID) {
        case .missing:
            appendPMExtensionE2EAcceptanceStep(
                to: &steps,
                title: "Run Command",
                status: .failed,
                detail: "\(Self.extensionE2EToolbarCommandID) command not found"
            )
        case let .executed(succeeded: commandSucceeded, boardMessage: capturedBoardMessage):
            toolbarMessage = capturedBoardMessage
            appendPMExtensionE2EAcceptanceStep(
                to: &steps,
                title: "Run Command",
                status: commandSucceeded ? .passed : .failed,
                detail: commandSucceeded ? "\(Self.extensionE2EToolbarCommandID) executed" : (lastBoardMessage ?? "Run command failed")
            )
        }

        let hookSucceeded = runPMExtensionE2EHookProbe(pluginID: pluginID)
        appendPMExtensionE2EAcceptanceStep(
            to: &steps,
            title: "Hook Execution",
            status: hookSucceeded ? .passed : .failed,
            detail: hookSucceeded
                ? "ticket.created hook triggered \(Self.extensionE2EHookCommandID)"
                : "No succeeded \(Self.extensionE2EHookCommandID) entry within timeout"
        )

        let writebackPassed = pmExtensionE2EWritebackPassed(
            pluginID: pluginID,
            toolbarMessage: toolbarMessage
        )
        appendPMExtensionE2EAcceptanceStep(
            to: &steps,
            title: "Output Writeback",
            status: writebackPassed ? .passed : .failed,
            detail: writebackPassed
                ? "Response message propagated to OpenMac state"
                : "No writeback signal found in board message/activity/observability"
        )

        if installed {
            let removed = uninstallPMExtension(pluginID: pluginID)
            appendPMExtensionE2EAcceptanceStep(
                to: &steps,
                title: "Cleanup",
                status: removed ? .passed : .failed,
                detail: removed ? "Removed probe extension" : (lastBoardMessage ?? "Cleanup failed")
            )
        } else {
            appendPMExtensionE2EAcceptanceStep(
                to: &steps,
                title: "Cleanup",
                status: .skipped,
                detail: "Skipped because install failed"
            )
        }

        return publishPMExtensionE2EAcceptanceReport(
            pluginID: pluginID,
            pluginName: pluginName,
            steps: steps
        )
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

}
