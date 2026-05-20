import Combine
import Foundation

extension KanbanBoardViewModel {
    struct RealArtifactVerificationResult {
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

    struct DeferredRealArtifactVerificationOutcome {
        let task: WorkTask?
        let status: String
        let detail: String
        let boardMessage: String?
        let boardMessageSeverity: BoardMessageSeverity?
    }

    enum RealArtifactIntegrityIssueCode {
        case missingBundleIdentifier
    }

    struct RealArtifactIntegrityIssue {
        let code: RealArtifactIntegrityIssueCode
        let reason: String
        let debugLog: String?
    }

    struct RealArtifactIntegrityCheckResult {
        let notes: [String]
        let issue: RealArtifactIntegrityIssue?
    }

    struct RealArtifactRepairResult {
        let didRepair: Bool
        let note: String?
        let debugLog: String?
    }

    struct PBXBuildSettingsSnapshot {
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

    enum XcodeBuildContainer {
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

    static let realArtifactXcodeListTimeoutSeconds = 45
    static let realArtifactBuildSettingsTimeoutSeconds = 45
    static let realArtifactBuildTimeoutSeconds = 240

    func enforceRealArtifactVerificationIfNeeded(
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

    func shouldRunRealArtifactVerification(for task: WorkTask) -> Bool {
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

    func isTerminalTaskForRealArtifactVerification(_ task: WorkTask) -> Bool {
        isTerminalTaskForRealArtifactVerification(task, within: tasks)
    }

    func isTerminalTaskForRealArtifactVerification(
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

    func shouldDeferRealArtifactVerification(for task: WorkTask) -> Bool {
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

    func candidateTaskForDeferredRealArtifactVerification() -> WorkTask? {
        candidateTaskForDeferredRealArtifactVerification(within: tasks)
    }

    func candidateTaskForDeferredRealArtifactVerification(
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

    func runDeferredRealArtifactVerificationIfNeeded() -> DeferredRealArtifactVerificationOutcome? {
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

    func applyDeferredRealArtifactVerificationBoardMessage(
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

    func shouldEnableSystemRealArtifactVerificationBoardHook() -> Bool {
        let policy = executionRealArtifactVerificationPolicy
        return policy.isEnabled &&
            (policy.requireInfoPlistExecutableKey || policy.requireXcodeBuild) &&
            policy.runVerificationOnlyOnTerminalTask
    }

    func isSystemRealArtifactVerificationBoardHookBinding(
        _ binding: PMBoardExtensionHookBinding
    ) -> Bool {
        binding.event == .boardRunFinished &&
            pmBoardExtensionHookBindingMatchesCommand(
                binding,
                pluginID: Self.systemExtensionPluginID,
                commandID: Self.systemRealArtifactVerifyCommandID
            )
    }

    func hasEnabledSystemRealArtifactVerificationBoardHook() -> Bool {
        pmBoardExtensionHookBindings.contains { binding in
            binding.isEnabled &&
                isSystemRealArtifactVerificationBoardHookBinding(binding)
        }
    }

    @discardableResult
    func syncSystemRealArtifactVerificationBoardHookBinding() -> Bool {
        let shouldEnable = shouldEnableSystemRealArtifactVerificationBoardHook()
        let existingIndex = pmBoardExtensionHookBindings.firstIndex { binding in
            isSystemRealArtifactVerificationBoardHookBinding(binding)
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

    func emitBoardRunFinishedHook(
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

    func runRealArtifactVerification(for task: WorkTask) -> RealArtifactVerificationResult {
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

    func runRealArtifactVerification(
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

    func runRealArtifactIntegrityChecks(
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

    func attemptDeterministicRealArtifactRepair(
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

    func resolvedProjectURLsForIntegrityChecks(
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

    func repairMissingBundleIdentifier(inXcodeProject projectURL: URL) -> (modified: Bool, debugLog: String?) {
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

    func rewritePBXProjectWithMissingBundleIdentifiersFilled(_ content: String) -> (content: String, fixedCount: Int, debugLog: String?) {
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

    func parsePBXBuildSettingsSnapshots(from content: String) -> [PBXBuildSettingsSnapshot] {
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

    func parsePBXBuildSettingsSnapshot(from blockLines: [String]) -> PBXBuildSettingsSnapshot {
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

    func parsePBXBuildSetting(from line: String) -> (key: String, value: String, indent: String)? {
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

    func descriptorForBundleIdentifierRepair(from snapshot: PBXBuildSettingsSnapshot) -> String {
        let product = normalizedPBXBuildSettingValue(snapshot.productName) ?? "unknown-product"
        let sdk = normalizedPBXBuildSettingValue(snapshot.sdkRoot) ?? "unknown-sdk"
        return "product=\(product), sdk=\(sdk)"
    }

    func synthesizedBundleIdentifier(
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

    func normalizedBundleIdentifierPrefix(_ rawPrefix: String?) -> String? {
        guard var prefix = normalizedPBXBuildSettingValue(rawPrefix), !prefix.isEmpty else {
            return nil
        }
        if prefix.contains("$(") {
            return nil
        }
        prefix = prefix.trimmingCharacters(in: CharacterSet(charactersIn: "."))
        return prefix.isEmpty ? nil : prefix
    }

    func normalizedPBXBuildSettingValue(_ value: String?) -> String? {
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

    func sanitizedBundleIdentifierComponent(_ value: String) -> String {
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

    func platformSuffixForSDKRoot(_ sdkRoot: String?) -> String {
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

    func inferredBundleIdentifierPrefix(fromPBXProjectContent content: String) -> String? {
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

    func loadPBXProjectContent(for projectURL: URL) -> String? {
        let projectFileURL = projectURL.appendingPathComponent("project.pbxproj")
        return try? String(contentsOf: projectFileURL, encoding: .utf8)
    }

    func braceDelta(in line: String) -> Int {
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

    func resolvedBoardScopedProjectsDirectoryPath() -> String {
        let baseProjectsDirectoryPath = projectsDirectoryPathProvider()
        return CodexProjectsDirectorySettings.boardScopedProjectsDirectoryPath(
            baseDirectoryPath: baseProjectsDirectoryPath,
            boardName: selectedBoardName
        )
    }

    func resolveXcodeBuildContainer(in rootURL: URL) -> (container: XcodeBuildContainer?, failureReason: String?, debugLog: String?) {
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

    func attemptGenerateXcodeProject(withXcodeGenAt manifestURL: URL) -> (container: XcodeBuildContainer?, failureReason: String?, debugLog: String?) {
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

    func discoverXcodeProjectURLs(in rootURL: URL) -> [URL] {
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

    func discoverXcodeWorkspaceURLs(in rootURL: URL) -> [URL] {
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

    func discoverXcodeGenManifestURLs(in rootURL: URL) -> [URL] {
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

    func hasSwiftPackageManifest(in rootURL: URL) -> Bool {
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

    func discoverInfoPlistURLs(near projectRootURL: URL) -> [URL] {
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

    func infoPlistContainsExecutableKey(at plistURL: URL) -> Bool {
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

    func parseXcodeSchemes(fromListOutput output: String) -> [String] {
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

    func preferredBuildScheme(from schemes: [String]) -> String? {
        if let nonTestScheme = schemes.first(where: { !$0.lowercased().contains("test") }) {
            return nonTestScheme
        }
        return schemes.first
    }

    func executeTaskWithBoardScopedProjectsDirectory(
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

    func resolvedExecutionWorkingDirectoryPath(
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

    static func prepareWorktreeDirectoryForExecution(
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

    static func worktreeSlug(_ rawValue: String, fallback: String) -> String {
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

    func applyRetryRunCount(for taskID: UUID, additionalAttempts: Int) {
        guard additionalAttempts > 0,
              let taskIndex = tasks.firstIndex(where: { $0.id == taskID }),
              var record = tasks[taskIndex].executionRecord else {
            return
        }
        record.runCount = max(0, record.runCount) + additionalAttempts
        tasks[taskIndex].executionRecord = record
    }

    func updateExecutionCheckpoint(_ checkpoint: ExecutionCheckpoint?) {
        executionCheckpoint = checkpoint
        persistBoardState()
    }

    @discardableResult
    func performTaskExecution(_ taskID: UUID, requiresTaskDetails: Bool) -> Bool {
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

    func performTaskExecutionInBackground(
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

    struct DependencyReference {
        let normalizedTitle: String
        let displayTitle: String
    }

    struct MissingDependencyDescriptor {
        let reference: DependencyReference
        let dependentTaskTitles: [String]
        let inferredSkills: [String]
    }

    struct HealthAutoFixSnapshot: Equatable {
        let tasks: [WorkTask]
        let agents: [AgentProfile]
        let wipLimits: [KanbanStatus: Int]
        let unassignedTaskIDs: Set<UUID>
        let assignmentReasons: [UUID: String]
    }

    static func normalizedDependencyTitle(_ raw: String) -> String {
        raw
            .trimmingCharacters(
                in: CharacterSet.whitespacesAndNewlines.union(
                    CharacterSet(charactersIn: "\"'`•-")
                )
            )
            .lowercased()
    }

    static func dependencyTitles(from details: String) -> [String] {
        parsedDependencyReferences(from: details).map(\.normalizedTitle)
    }

    static func parsedDependencyReferences(from details: String) -> [DependencyReference] {
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

    static func acceptanceCriteriaLines(from details: String) -> [String] {
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

    static func acceptanceE2EDetails(
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

    static func isDependencyCompleted(_ task: WorkTask) -> Bool {
        task.status == .review || task.status == .done
    }

    func dependencyCompletionMap() -> [String: Bool] {
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

    func missingDependencyReferences() -> [DependencyReference] {
        missingDependencyDescriptors().map(\.reference)
    }

    func missingDependencyDescriptors() -> [MissingDependencyDescriptor] {
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

    func prepareAssignedBatchRunQueue(excluding attemptedTaskIDs: Set<UUID> = []) -> AssignedBatchRunPreparation {
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

    func noRunnableAssignedBatchMessage(
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

    func preparePMAutopilot(
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

    func selectBulkTriageAgent(
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

    func isEligibleForBulkTriage(
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

    func agentMatchesTaskSkills(
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

    func skillMatchCount(agent: AgentProfile, task: WorkTask) -> Int {
        agent.skills.intersection(task.requiredSkills).count
    }

    func bulkTriageAssignmentSummary(assignedCount: Int, remainingCount: Int) -> String {
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

    func normalizeExecutionText(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    func normalizeExecutionSummary(_ value: String?) -> String? {
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

    func sharedAgentMemoryEntries(limit: Int) -> [SharedAgentMemoryEntry] {
        guard limit > 0 else { return [] }
        if sharedAgentMemory.count <= limit {
            return sharedAgentMemory.reversed()
        }
        return sharedAgentMemory.suffix(limit).reversed()
    }

    func sharedAgentMemoryPromptContext(excludingTaskID: UUID?) -> String {
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

    func taskSnapshotWithSharedMemoryContext(_ task: WorkTask, agent: AgentProfile) -> WorkTask {
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

    func extensionMemoryProviderContext(for task: WorkTask, agent: AgentProfile, coreContext: String) -> String? {
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

    func appendSharedAgentMemoryEntry(_ entry: SharedAgentMemoryEntry) {
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

    func rememberExecutionOutcomeInSharedMemory(
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

    func appendAgentExecutionEvent(
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

    func captureExecutionProgress(_ update: String, for prepared: PreparedTaskExecution) {
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

    func prepareTaskExecution(_ taskID: UUID, requiresTaskDetails: Bool) -> PreparedTaskExecution? {
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

    func moveTaskBackToTodoAfterFailureIfNeeded(taskIndex: Int) {
        guard tasks.indices.contains(taskIndex) else { return }
        if tasks[taskIndex].status == .inProgress {
            tasks[taskIndex].status = .todo
        }
    }

    func finalizeTaskExecution(_ prepared: PreparedTaskExecution, outcome: AgentTaskExecutionOutcome) {
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

    func parseExecutionFailure(_ value: String) -> (userMessage: String, debugLog: String?) {
        let delimiter = DefaultAgentTaskExecutor.debugLogDelimiter
        guard let range = value.range(of: delimiter) else {
            return (value, nil)
        }
        let userMessage = String(value[..<range.lowerBound])
        let debugLog = String(value[range.upperBound...])
        return (userMessage, debugLog)
    }

    func blockedExecutionMessage(from summary: String) -> String? {
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

    func deliveryGateBlockMessage(for task: WorkTask, normalizedSummary: String) -> String? {
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

    func detectedDeliveryArtifacts(from normalizedSummary: String) -> Set<TaskDeliveryArtifact> {
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

    func hasEvidence(in normalizedText: String, positive: [String], negative: [String]) -> Bool {
        let hasPositive = positive.contains(where: { normalizedText.contains($0) })
        guard hasPositive else { return false }
        return !negative.contains(where: { normalizedText.contains($0) })
    }

    func extractCodexLoginCommand(from userMessage: String?, debugLog: String?) -> String? {
        [userMessage, debugLog]
            .compactMap { $0 }
            .compactMap { extractCodexLoginCommand(from: $0) }
            .first
    }

    func extractCodexLoginCommand(from value: String) -> String? {
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

    func markRunningExecutionsAsInterruptedIfNeeded() {
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

    func isWIPLimitReached(for destination: KanbanStatus, excluding taskID: UUID) -> Bool {
        guard let limit = wipLimits[destination] else { return false }
        let currentCount = tasks.filter { $0.status == destination && $0.id != taskID }.count
        return currentCount >= limit
    }

    var selectedBoardIndex: Int? {
        boards.firstIndex(where: { $0.id == selectedBoardID })
    }

    func syncCurrentBoardRecord() {
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

    func pruneExecutionGovernanceStateForExistingTasks() {
        let validTaskIDs = Set(boards.flatMap { $0.tasks.map(\.id) })
        taskExecutionApprovalsByTaskID = taskExecutionApprovalsByTaskID.filter { validTaskIDs.contains($0.key) }
        executionTimelineByTaskID = executionTimelineByTaskID.filter { validTaskIDs.contains($0.key) }
    }

    func loadBoard(_ boardID: UUID) {
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

    func uniqueBoardCopyName(for sourceName: String) -> String {
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

    func uniqueTaskCopyTitle(for sourceTitle: String) -> String {
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

    func normalizedBoardRecord(_ board: KanbanBoardRecord) -> KanbanBoardRecord {
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

    static func normalizedBoardExtensionHookBindings(
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

    struct ImportedWorkspaceBoards {
        let boards: [KanbanBoardRecord]
        let preferredSelectedBoardID: UUID?
    }

    struct WorkspaceImportExecutionResult {
        let resolvedSelectedBoardID: UUID
        let message: String
    }

    func importedWorkspaceBoards(from snapshot: KanbanBoardSnapshot) -> ImportedWorkspaceBoards {
        let boards: [KanbanBoardRecord]
        let preferredSelectedBoardID: UUID?
        if let snapshotBoards = snapshot.boards, !snapshotBoards.isEmpty {
            boards = normalizedImportedBoardRecords(snapshotBoards)
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
            boards = normalizedImportedBoardRecords([fallbackBoard])
            preferredSelectedBoardID = nil
        }
        return ImportedWorkspaceBoards(
            boards: boards,
            preferredSelectedBoardID: preferredSelectedBoardID
        )
    }

    func executeWorkspaceReplaceImport(
        snapshot: KanbanBoardSnapshot,
        importedBoards: [KanbanBoardRecord],
        preferredSelectedBoardID: UUID?
    ) -> WorkspaceImportExecutionResult {
        let restoredState = Self.restoredSnapshotState(from: snapshot)
        boards = importedBoards
        if let importedTemplates = snapshot.taskTemplates, !importedTemplates.isEmpty {
            taskTemplates = importedTemplates
        }
        if let importedRetryConfiguration = snapshot.executionAutoRetryConfiguration {
            executionAutoRetryConfiguration = importedRetryConfiguration
        }
        applyImportedWorkspaceReplaceState(restoredState: restoredState, importedBoards: importedBoards)
        let resolvedSelectedBoardID = resolvedImportedSelectedBoardID(
            preferredSelectedBoardID: preferredSelectedBoardID,
            importedBoards: importedBoards,
            fallbackBoardID: importedBoards[0].id
        )
        let boardLabel = boards.count == 1 ? message("board") : message("boards")
        let summary = message("Imported workspace (%d %@)", boards.count, boardLabel)
        return WorkspaceImportExecutionResult(
            resolvedSelectedBoardID: resolvedSelectedBoardID,
            message: summary
        )
    }

    func executeWorkspaceMergeImport(
        snapshot: KanbanBoardSnapshot,
        importedBoards: [KanbanBoardRecord],
        preferredSelectedBoardID: UUID?
    ) -> WorkspaceImportExecutionResult {
        syncCurrentBoardRecord()
        let currentSelectedBoardID = selectedBoardID
        boards = mergedBoardRecords(currentBoards: boards, importedBoards: importedBoards)
        if let importedTemplates = snapshot.taskTemplates, !importedTemplates.isEmpty {
            taskTemplates = mergedTaskTemplates(current: taskTemplates, imported: importedTemplates)
        }
        if let importedRetryConfiguration = snapshot.executionAutoRetryConfiguration {
            executionAutoRetryConfiguration = importedRetryConfiguration
        }
        applyImportedWorkspaceMergeState(snapshot: snapshot)
        let resolvedSelectedBoardID = resolvedImportedSelectedBoardID(
            preferredSelectedBoardID: preferredSelectedBoardID,
            importedBoards: importedBoards,
            fallbackBoardID: currentSelectedBoardID
        )
        let boardLabel = importedBoards.count == 1 ? message("board") : message("boards")
        let summary = message("Merged workspace (+%d %@)", importedBoards.count, boardLabel)
        return WorkspaceImportExecutionResult(
            resolvedSelectedBoardID: resolvedSelectedBoardID,
            message: summary
        )
    }

    func normalizedImportedBoardRecords(_ importedBoards: [KanbanBoardRecord]) -> [KanbanBoardRecord] {
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

    func mergedBoardRecords(
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

    func mergedTaskTemplates(current: [TaskTemplate], imported: [TaskTemplate]) -> [TaskTemplate] {
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

    func applyImportedWorkspaceReplaceState(
        restoredState: RestoredSnapshotState,
        importedBoards: [KanbanBoardRecord]
    ) {
        executionCheckpoint = restoredState.executionCheckpoint
        executionApprovalPolicy = restoredState.executionApprovalPolicy
        executionQuotaPolicy = restoredState.executionQuotaPolicy
        executionQuotaUsage = restoredState.executionQuotaUsage
        executionParallelizationPolicy = restoredState.executionParallelizationPolicy
        gitHubPRQualityGatePolicy = restoredState.gitHubPRQualityGatePolicy
        dagExecutionPolicy = restoredState.dagExecutionPolicy
        executionQualitySafetyGatePolicy = restoredState.executionQualitySafetyGatePolicy
        executionRealArtifactVerificationDefaultPolicy = restoredState.executionRealArtifactVerificationPolicy
        mcpServerPolicy = restoredState.mcpServerPolicy
        pmPlannerEngineMode = restoredState.pmPlannerEngineMode
        pmPlanningPluginPolicy = restoredState.pmPlanningPluginPolicy
        sharedAgentMemoryProviderMode = restoredState.sharedAgentMemoryProviderMode
        sharedAgentMemoryPreferredProviderID = restoredState.normalizedSharedAgentMemoryPreferredProviderID
        sharedAgentMemoryMutedProviderIDs = restoredState.sharedAgentMemoryMutedProviderIDs
        mcpReadinessCacheByServerName = [:]
        taskExecutionApprovalsByTaskID = restoredState.taskExecutionApprovalsByTaskID.filter { approvalEntry in
            importedBoards.contains { board in
                board.tasks.contains(where: { $0.id == approvalEntry.key })
            }
        }
    }

    func applyImportedWorkspaceMergeState(snapshot: KanbanBoardSnapshot) {
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
    }

    func resolvedImportedSelectedBoardID(
        preferredSelectedBoardID: UUID?,
        importedBoards: [KanbanBoardRecord],
        fallbackBoardID: UUID
    ) -> UUID {
        preferredSelectedBoardID.flatMap { candidate in
            importedBoards.contains(where: { $0.id == candidate }) ? candidate : nil
        } ?? fallbackBoardID
    }

    func decodeWorkspaceSnapshot(from data: Data) -> KanbanBoardSnapshot? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return try? decoder.decode(KanbanBoardSnapshot.self, from: data)
    }

    func boardHealthPenaltyItems() -> [(label: String, points: Int)] {
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

    func persistBoardState() {
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
