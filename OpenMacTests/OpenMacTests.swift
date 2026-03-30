import Foundation
import SwiftUI
import Testing
@testable import OpenMac

private final class MockURLProtocol: URLProtocol {
    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.requestHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private func makeMockedURLSession() -> URLSession {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [MockURLProtocol.self]
    return URLSession(configuration: configuration)
}

@discardableResult
private func waitForMainQueue(
    timeout: TimeInterval = 2.0,
    condition: @escaping () -> Bool
) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if condition() {
            return true
        }
        let spinUntil = Date().addingTimeInterval(0.01)
        if Thread.isMainThread {
            _ = RunLoop.main.run(mode: .default, before: spinUntil)
            _ = RunLoop.main.run(mode: .common, before: spinUntil)
        } else {
            Thread.sleep(forTimeInterval: 0.01)
        }
    }
    return condition()
}

struct AutoAssignmentEngineTests {

    @Test("assigns task to an agent with all required skills")
    func assignsTaskToSkillMatchedAgent() {
        let task = WorkTask(
            title: "Design onboarding flow",
            details: "Create welcome flow for first-time users",
            requiredSkills: ["ui", "ux"],
            storyPoints: 3,
            status: .todo,
            assignedAgentID: nil
        )

        let matchingAgent = AgentProfile(name: "Vision Agent", skills: ["ui", "ux", "swiftui"], maxConcurrentTasks: 2)
        let nonMatchingAgent = AgentProfile(name: "Backend Agent", skills: ["api", "db"], maxConcurrentTasks: 2)

        let result = AutoAssignmentEngine().assign(tasks: [task], agents: [matchingAgent, nonMatchingAgent])

        #expect(result.tasks[0].assignedAgentID == matchingAgent.id)
    }

    @Test("prefers less-loaded agent among eligible candidates")
    func prefersLessLoadedAgent() {
        let todoTask = WorkTask(
            title: "Implement cards",
            details: "Create kanban card UI",
            requiredSkills: ["swiftui"],
            storyPoints: 2,
            status: .todo,
            assignedAgentID: nil
        )

        let busyAgent = AgentProfile(name: "Agent A", skills: ["swiftui"], maxConcurrentTasks: 4)
        let freeAgent = AgentProfile(name: "Agent B", skills: ["swiftui"], maxConcurrentTasks: 4)
        let existingTask = WorkTask(
            title: "Existing",
            details: "Existing in-progress work",
            requiredSkills: ["swiftui"],
            storyPoints: 2,
            status: .inProgress,
            assignedAgentID: busyAgent.id
        )

        let result = AutoAssignmentEngine().assign(tasks: [existingTask, todoTask], agents: [busyAgent, freeAgent])
        let assignedTodo = result.tasks.first { $0.title == "Implement cards" }

        #expect(assignedTodo?.assignedAgentID == freeAgent.id)
    }

    @Test("keeps task unassigned when no agent has required skills")
    func keepsTaskUnassignedWithoutSkillMatch() {
        let task = WorkTask(
            title: "Train ranking model",
            details: "Need ml expertise",
            requiredSkills: ["ml"],
            storyPoints: 5,
            status: .todo,
            assignedAgentID: nil
        )

        let result = AutoAssignmentEngine().assign(
            tasks: [task],
            agents: [AgentProfile(name: "UI Agent", skills: ["swiftui"], maxConcurrentTasks: 2)]
        )

        #expect(result.tasks[0].assignedAgentID == nil)
        #expect(result.unassignedTaskIDs.contains(task.id))
    }

    @Test("uses task context keywords to break ties between equally-loaded candidates")
    func prefersContextRelevantAgent() {
        let task = WorkTask(
            title: "Polish animation transition",
            details: "Need smoother animation timing for drag interaction",
            requiredSkills: ["swiftui"],
            storyPoints: 2,
            status: .todo,
            assignedAgentID: nil
        )
        let generalAgent = AgentProfile(name: "General Agent", skills: ["swiftui"], maxConcurrentTasks: 3)
        let animationAgent = AgentProfile(name: "Motion Agent", skills: ["swiftui", "animation"], maxConcurrentTasks: 3)

        let result = AutoAssignmentEngine().assign(tasks: [task], agents: [generalAgent, animationAgent])

        #expect(result.tasks[0].assignedAgentID == animationAgent.id)
    }

    @Test("returns assignment explanation for assigned task")
    func includesAssignmentReason() {
        let task = WorkTask(
            title: "Implement board",
            details: "Create board UI",
            requiredSkills: ["swiftui"],
            storyPoints: 3,
            status: .todo,
            assignedAgentID: nil
        )
        let agent = AgentProfile(name: "UI Agent", skills: ["swiftui", "ui"], maxConcurrentTasks: 2)

        let result = AutoAssignmentEngine().assign(tasks: [task], agents: [agent])

        let decision = result.decisions[task.id]
        #expect(decision?.agentID == agent.id)
        #expect(!(decision?.reason.isEmpty ?? true))
        #expect((decision?.score ?? 0) > 0)
    }

    @Test("assign resolves equal-score ties by agent name")
    func assignResolvesEqualScoreTiesByAgentName() {
        let task = WorkTask(
            title: "Build board shell",
            details: "Implement kanban layout",
            requiredSkills: ["swiftui"],
            storyPoints: 2,
            status: .todo,
            assignedAgentID: nil
        )
        let laterName = AgentProfile(name: "Zeta Agent", skills: ["swiftui"], maxConcurrentTasks: 3)
        let earlierName = AgentProfile(name: "Alpha Agent", skills: ["swiftui"], maxConcurrentTasks: 3)

        let result = AutoAssignmentEngine().assign(tasks: [task], agents: [laterName, earlierName])

        #expect(result.tasks[0].assignedAgentID == earlierName.id)
    }

    @Test("bestAgent resolves equal-score ties by agent name")
    func bestAgentResolvesEqualScoreTiesByAgentName() {
        let task = WorkTask(
            title: "Build board shell",
            details: "Implement kanban layout",
            requiredSkills: ["swiftui"],
            storyPoints: 2,
            status: .todo,
            assignedAgentID: nil
        )
        let laterName = AgentProfile(name: "Zeta Agent", skills: ["swiftui"], maxConcurrentTasks: 3)
        let earlierName = AgentProfile(name: "Alpha Agent", skills: ["swiftui"], maxConcurrentTasks: 3)

        let decision = AutoAssignmentEngine().bestAgent(
            for: task,
            among: [task],
            agents: [laterName, earlierName]
        )

        #expect(decision?.agentID == earlierName.id)
    }

    @Test("bestAgent remains deterministic when candidate names are identical")
    func bestAgentHandlesIdenticalCandidateNames() {
        let task = WorkTask(
            title: "Build board shell",
            details: "Implement kanban layout",
            requiredSkills: ["swiftui"],
            storyPoints: 2,
            status: .todo,
            assignedAgentID: nil
        )
        let firstAgent = AgentProfile(name: "Same Agent", skills: ["swiftui"], maxConcurrentTasks: 3)
        let secondAgent = AgentProfile(name: "Same Agent", skills: ["swiftui"], maxConcurrentTasks: 3)

        let decision = AutoAssignmentEngine().bestAgent(
            for: task,
            among: [task],
            agents: [firstAgent, secondAgent]
        )

        #expect(decision != nil)
        #expect([firstAgent.id, secondAgent.id].contains(decision?.agentID ?? UUID()))
    }

    @Test("assign prefers lower load when candidate scores tie")
    func assignPrefersLowerLoadWhenScoresTie() {
        let task = WorkTask(
            title: "Kanban polish",
            details: "Refine board interactions",
            requiredSkills: ["swiftui"],
            storyPoints: 2,
            status: .todo,
            assignedAgentID: nil
        )

        let lowerLoadAgent = AgentProfile(name: "Lower Load", skills: ["swiftui"], maxConcurrentTasks: 10)
        let higherLoadAgent = AgentProfile(name: "Higher Load", skills: ["swiftui", "kanban"], maxConcurrentTasks: 10)

        let lowerLoadTasks = (0..<8).map { index in
            WorkTask(
                title: "Lower \(index)",
                details: "",
                requiredSkills: ["swiftui"],
                storyPoints: 1,
                status: .inProgress,
                assignedAgentID: lowerLoadAgent.id
            )
        }
        let higherLoadTasks = (0..<9).map { index in
            WorkTask(
                title: "Higher \(index)",
                details: "",
                requiredSkills: ["swiftui"],
                storyPoints: 1,
                status: .inProgress,
                assignedAgentID: higherLoadAgent.id
            )
        }

        let result = AutoAssignmentEngine().assign(
            tasks: lowerLoadTasks + higherLoadTasks + [task],
            agents: [higherLoadAgent, lowerLoadAgent]
        )

        let assignedTask = result.tasks.first { $0.id == task.id }
        #expect(assignedTask?.assignedAgentID == lowerLoadAgent.id)
    }

    @Test("bestAgent prefers lower load when candidate scores tie")
    func bestAgentPrefersLowerLoadWhenScoresTie() {
        let task = WorkTask(
            title: "Kanban polish",
            details: "Refine board interactions",
            requiredSkills: ["swiftui"],
            storyPoints: 2,
            status: .todo,
            assignedAgentID: nil
        )

        let lowerLoadAgent = AgentProfile(name: "Lower Load", skills: ["swiftui"], maxConcurrentTasks: 10)
        let higherLoadAgent = AgentProfile(name: "Higher Load", skills: ["swiftui", "kanban"], maxConcurrentTasks: 10)

        let lowerLoadTasks = (0..<8).map { index in
            WorkTask(
                title: "Lower \(index)",
                details: "",
                requiredSkills: ["swiftui"],
                storyPoints: 1,
                status: .inProgress,
                assignedAgentID: lowerLoadAgent.id
            )
        }
        let higherLoadTasks = (0..<9).map { index in
            WorkTask(
                title: "Higher \(index)",
                details: "",
                requiredSkills: ["swiftui"],
                storyPoints: 1,
                status: .inProgress,
                assignedAgentID: higherLoadAgent.id
            )
        }

        let decision = AutoAssignmentEngine().bestAgent(
            for: task,
            among: lowerLoadTasks + higherLoadTasks + [task],
            agents: [higherLoadAgent, lowerLoadAgent]
        )

        #expect(decision?.agentID == lowerLoadAgent.id)
    }
}

@Suite(.serialized)
struct OpenMacAppLogicTests {
    @Test("appearance selection action resolves raw value")
    func appearanceSelectionActionResolvesRawValue() {
        let updatedRawValue = OpenMacAppTestHooks.appearanceSelectionRawValue(
            initialRawValue: AppAppearanceMode.system.rawValue,
            mode: .dark
        )

        #expect(updatedRawValue == AppAppearanceMode.dark.rawValue)
        #expect(OpenMacAppTestHooks.appearanceRawValue(for: .light) == AppAppearanceMode.light.rawValue)
    }

    @Test("language selection action supports explicit and system values")
    func languageSelectionActionSupportsExplicitAndSystemValues() {
        let explicit = OpenMacAppTestHooks.languageSelectionRawValue(
            initialRawValue: AppLanguageSettings.systemValue,
            language: .japanese
        )
        #expect(explicit == AppLanguage.japanese.rawValue)

        let system = OpenMacAppTestHooks.languageSelectionRawValue(
            initialRawValue: AppLanguage.japanese.rawValue,
            language: nil
        )
        #expect(system == AppLanguageSettings.systemValue)
        #expect(OpenMacAppTestHooks.languageOverrideRawValue(for: .english) == AppLanguage.english.rawValue)
        #expect(OpenMacAppTestHooks.languageOverrideRawValue(for: nil) == AppLanguageSettings.systemValue)
    }

    @Test("selected language matching covers system and explicit branches")
    func selectedLanguageMatchingCoversSystemAndExplicitBranches() {
        #expect(OpenMacAppTestHooks.isSelectedLanguage(overrideRawValue: AppLanguageSettings.systemValue, language: nil))
        #expect(OpenMacAppTestHooks.isSelectedLanguage(overrideRawValue: AppLanguage.korean.rawValue, language: .korean))
        #expect(!OpenMacAppTestHooks.isSelectedLanguage(overrideRawValue: AppLanguage.korean.rawValue, language: nil))
        #expect(!OpenMacAppTestHooks.isSelectedLanguage(overrideRawValue: AppLanguageSettings.systemValue, language: .english))
    }

    @Test("language label and appearance cycle helpers return expected values")
    func languageLabelAndAppearanceCycleHelpersReturnExpectedValues() {
        #expect(OpenMacAppTestHooks.languageLabel(for: nil) == L10n.string("System Default"))
        #expect(OpenMacAppTestHooks.languageLabel(for: .french) == L10n.string(AppLanguage.french.displayNameKey))

        let cycledFromSystem = OpenMacAppTestHooks.cycledAppearanceRawValue(
            currentRawValue: AppAppearanceMode.system.rawValue
        )
        #expect(cycledFromSystem == AppAppearanceMode.system.next().rawValue)

        let cycledFromInvalid = OpenMacAppTestHooks.cycledAppearanceRawValue(currentRawValue: "invalid-mode")
        #expect(cycledFromInvalid == AppAppearanceMode.system.next().rawValue)

        let cycledViaAction = OpenMacAppTestHooks.cycleAppearanceActionRawValue(
            initialRawValue: AppAppearanceMode.light.rawValue
        )
        #expect(cycledViaAction == AppAppearanceMode.light.next().rawValue)
    }

    @Test("app mutators update and cycle persisted appearance/language values")
    func appMutatorsUpdateAndCyclePersistedValues() {
        let result = OpenMacAppTestHooks.exerciseInternalMutators(
            initialAppearanceRawValue: AppAppearanceMode.system.rawValue,
            initialLanguageRawValue: AppLanguageSettings.systemValue,
            appearanceRawValueToApply: AppAppearanceMode.dark.rawValue,
            languageRawValueToApply: AppLanguage.japanese.rawValue
        )

        #expect(result.appliedAppearance == AppAppearanceMode.dark.rawValue)
        #expect(result.appliedLanguage == AppLanguage.japanese.rawValue)
        #expect(result.cycledAppearance == AppAppearanceMode.dark.next().rawValue)

        let readBack = OpenMacAppTestHooks.readAppearanceRawValueFromAppStorage(
            initialAppearanceRawValue: AppAppearanceMode.light.rawValue
        )
        #expect(readBack == AppAppearanceMode.light.rawValue)
    }
}

@Suite(.serialized)
struct AgentTaskExecutorTests {
    private func makeExecutableScript(
        contents: String,
        in directory: URL,
        name: String
    ) throws -> URL {
        let scriptURL = directory.appendingPathComponent(name)
        try Data(contents.utf8).write(to: scriptURL)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)
        return scriptURL
    }

    @Test("default executor local mock returns success summary")
    func localMockReturnsSuccessSummary() {
        let task = WorkTask(
            title: "Summarize sprint",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 1,
            status: .todo,
            assignedAgentID: nil
        )
        let agent = AgentProfile(
            name: "Mock Agent",
            skills: ["swiftui"],
            runtimeProfile: AgentRuntimeProfile(provider: .localMock)
        )
        let executor = DefaultAgentTaskExecutor(
            environmentProvider: { [:] },
            urlSession: .shared,
            timeoutSeconds: 1
        )

        let outcome = executor.execute(task: task, agent: agent)

        switch outcome {
        case let .success(summary):
            #expect(summary.contains("Mock Agent"))
            #expect(summary.contains("Summarize sprint"))
        case .failure:
            #expect(Bool(false), "Expected success for local mock runtime")
        }
    }

    @Test("default executor openai compatible reports missing API key")
    func openAICompatibleRequiresAPIKey() {
        let task = WorkTask(
            title: "Generate plan",
            details: "",
            requiredSkills: ["automation"],
            storyPoints: 2,
            status: .todo,
            assignedAgentID: nil
        )
        let agent = AgentProfile(
            name: "OpenAI Agent",
            skills: ["automation"],
            runtimeProfile: AgentRuntimeProfile(provider: .openAICompatible, model: "gpt-4.1-mini")
        )
        let executor = DefaultAgentTaskExecutor(
            environmentProvider: { ["OPENAI_API_KEY": "   "] },
            urlSession: .shared,
            timeoutSeconds: 1
        )

        let outcome = executor.execute(task: task, agent: agent)

        switch outcome {
        case .success:
            #expect(Bool(false), "Expected missing key failure for OpenAI-compatible runtime")
        case let .failure(message):
            #expect(message == "Missing OPENAI_API_KEY for OpenAI-compatible runtime")
        }
    }

    @Test("default executor openai compatible supports codex bridge mode")
    func openAICompatibleCodexBridgeUsesRunner() {
        let task = WorkTask(
            title: "Generate dispatch notes",
            details: "Bridge path",
            requiredSkills: ["automation"],
            storyPoints: 2,
            status: .todo,
            assignedAgentID: nil
        )
        let agent = AgentProfile(
            name: "Bridge Agent",
            skills: ["automation"],
            runtimeProfile: AgentRuntimeProfile(
                provider: .openAICompatible,
                model: "gpt-5.2",
                openAIAuthMode: .codexBridge,
                codexProfile: "default"
            )
        )
        let executor = DefaultAgentTaskExecutor(
            environmentProvider: { [:] },
            urlSession: .shared,
            timeoutSeconds: 1,
            codexBridgePreflight: {},
            codexBridgeRunner: { request, _ in
                #expect(request.model == "gpt-5.2")
                #expect(request.profile == "default")
                #expect(request.prompt.contains("Generate dispatch notes"))
                #expect(request.workingDirectoryPath?.contains("Library/Application Support/OpenMac/Projects") == true)
                return "Bridge run complete"
            }
        )

        let outcome = executor.execute(task: task, agent: agent)

        switch outcome {
        case let .success(summary):
            #expect(summary == "Bridge run complete")
        case .failure:
            #expect(Bool(false), "Expected success for Codex Bridge runtime")
        }
    }

    @Test("default executor codex bridge prompt follows selected app language")
    func openAICompatibleCodexBridgePromptFollowsSelectedLanguage() {
        let task = WorkTask(
            title: "建立",
            details: "建立 macOS 專用 app",
            requiredSkills: [],
            storyPoints: 2,
            status: .todo,
            assignedAgentID: nil
        )
        let agent = AgentProfile(
            name: "Bridge Agent",
            skills: ["automation"],
            runtimeProfile: AgentRuntimeProfile(
                provider: .openAICompatible,
                model: "gpt-5.2",
                openAIAuthMode: .codexBridge
            )
        )

        var capturedPrompt = ""
        let executor = DefaultAgentTaskExecutor(
            environmentProvider: { [:] },
            urlSession: .shared,
            timeoutSeconds: 1,
            appLanguageOverrideProvider: { AppLanguage.traditionalChinese.rawValue },
            codexBridgePreflight: {},
            codexBridgeRunner: { request, _ in
                capturedPrompt = request.prompt
                return "Bridge run complete"
            }
        )

        let outcome = executor.execute(task: task, agent: agent)

        switch outcome {
        case let .success(summary):
            #expect(summary == "Bridge run complete")
        case .failure:
            #expect(Bool(false), "Expected success for Codex Bridge runtime")
        }
        #expect(capturedPrompt.contains("你正在看板執行系統中支援一位已指派的 AI 代理。"))
        #expect(capturedPrompt.contains("代理: Bridge Agent"))
        #expect(capturedPrompt.contains("任務標題"))
        #expect(capturedPrompt.contains("請使用繁體中文撰寫所有段落標題與敘述內容"))
        #expect(capturedPrompt.contains("摘要："))
        #expect(capturedPrompt.contains("所需技能: 無"))
    }

    @Test("default executor codex bridge request honors projects directory override environment")
    func openAICompatibleCodexBridgeUsesProjectsDirectoryOverride() {
        let task = WorkTask(
            title: "Generate dispatch notes",
            details: "Bridge path",
            requiredSkills: ["automation"],
            storyPoints: 2,
            status: .todo,
            assignedAgentID: nil
        )
        let agent = AgentProfile(
            name: "Bridge Agent",
            skills: ["automation"],
            runtimeProfile: AgentRuntimeProfile(
                provider: .openAICompatible,
                model: "gpt-5.2",
                openAIAuthMode: .codexBridge,
                codexProfile: "default"
            )
        )
        let expectedPath = "/tmp/openmac-projects-override"
        let executor = DefaultAgentTaskExecutor(
            environmentProvider: { [CodexProjectsDirectorySettings.environmentOverrideKey: expectedPath] },
            urlSession: .shared,
            timeoutSeconds: 1,
            codexBridgePreflight: {},
            codexBridgeRunner: { request, _ in
                #expect(request.workingDirectoryPath == expectedPath)
                return "Bridge run complete"
            }
        )

        let outcome = executor.execute(task: task, agent: agent)

        switch outcome {
        case let .success(summary):
            #expect(summary == "Bridge run complete")
        case .failure:
            #expect(Bool(false), "Expected success for Codex Bridge runtime")
        }
    }

    @Test("default executor surfaces codex bridge failures")
    func openAICompatibleCodexBridgeFailure() {
        let task = WorkTask(
            title: "Bridge failure",
            details: "",
            requiredSkills: ["automation"],
            storyPoints: 1,
            status: .todo,
            assignedAgentID: nil
        )
        let agent = AgentProfile(
            name: "Bridge Agent",
            skills: ["automation"],
            runtimeProfile: AgentRuntimeProfile(
                provider: .openAICompatible,
                model: "gpt-5.2",
                openAIAuthMode: .codexBridge
            )
        )
        let executor = DefaultAgentTaskExecutor(
            environmentProvider: { [:] },
            urlSession: .shared,
            timeoutSeconds: 1,
            codexBridgePreflight: {},
            codexBridgeRunner: { _, _ in
                struct BridgeError: LocalizedError {
                    var errorDescription: String? { "codex unavailable" }
                }
                throw BridgeError()
            }
        )

        let outcome = executor.execute(task: task, agent: agent)

        switch outcome {
        case .success:
            #expect(Bool(false), "Expected Codex Bridge failure")
        case let .failure(message):
            #expect(message.contains("Codex Bridge run failed"))
            #expect(message.contains("codex unavailable"))
        }
    }

    @Test("default executor summarizes codex bridge websocket DNS failures and keeps debug log")
    func openAICompatibleCodexBridgeNetworkFailureSummary() {
        let task = WorkTask(
            title: "Bridge network failure",
            details: "",
            requiredSkills: ["automation"],
            storyPoints: 1,
            status: .todo,
            assignedAgentID: nil
        )
        let agent = AgentProfile(
            name: "Bridge Agent",
            skills: ["automation"],
            runtimeProfile: AgentRuntimeProfile(
                provider: .openAICompatible,
                model: "gpt-5.2",
                openAIAuthMode: .codexBridge
            )
        )
        let executor = DefaultAgentTaskExecutor(
            environmentProvider: { [:] },
            urlSession: .shared,
            timeoutSeconds: 1,
            codexBridgePreflight: {},
            codexBridgeRunner: { _, _ in
                struct BridgeError: LocalizedError {
                    var errorDescription: String? {
                        """
                        OpenAI Codex v0.118.0-alpha.2
                        workdir: /tmp
                        ERROR codex_api::endpoint::responses_websocket: failed to connect to websocket: IO error: failed to lookup address information: nodename nor servname provided, or not known, url: wss://api.openai.com/v1/responses
                        """
                    }
                }
                throw BridgeError()
            }
        )

        let outcome = executor.execute(task: task, agent: agent)

        switch outcome {
        case .success:
            #expect(Bool(false), "Expected Codex Bridge network failure")
        case let .failure(message):
            #expect(message.contains("Network/DNS lookup failed while Codex Bridge contacted OpenAI"))
            #expect(message.contains("--- debug ---"))
            #expect(message.contains("failed to connect to websocket"))
        }
    }

    @Test("default executor restarts codex and retries when quota is exhausted")
    func openAICompatibleCodexBridgeRecoversFromQuotaError() {
        let task = WorkTask(
            title: "Bridge quota recovery",
            details: "",
            requiredSkills: ["automation"],
            storyPoints: 1,
            status: .todo,
            assignedAgentID: nil
        )
        let agent = AgentProfile(
            name: "Bridge Agent",
            skills: ["automation"],
            runtimeProfile: AgentRuntimeProfile(
                provider: .openAICompatible,
                model: "gpt-5.2",
                openAIAuthMode: .codexBridge
            )
        )
        var runAttemptCount = 0
        var recoveryCalled = false
        let executor = DefaultAgentTaskExecutor(
            environmentProvider: { [:] },
            urlSession: .shared,
            timeoutSeconds: 1,
            codexBridgePreflight: {},
            codexBridgeRunner: { _, _ in
                runAttemptCount += 1
                if runAttemptCount == 1 {
                    struct QuotaError: LocalizedError {
                        var errorDescription: String? {
                            "usage limit exceeded: insufficient_quota"
                        }
                    }
                    throw QuotaError()
                }
                return "Recovered after restart"
            },
            codexBridgeRecovery: { reason, onProgress in
                recoveryCalled = true
                #expect(reason.contains("insufficient_quota"))
                onProgress("Restarted Codex app")
            }
        )

        var progressEvents: [String] = []
        let outcome = executor.execute(task: task, agent: agent) { update in
            progressEvents.append(update)
        }

        switch outcome {
        case let .success(summary):
            #expect(summary == "Recovered after restart")
        case .failure:
            #expect(Bool(false), "Expected Codex quota auto-recovery to succeed")
        }
        #expect(recoveryCalled)
        #expect(runAttemptCount == 2)
        #expect(progressEvents.contains(where: { $0.contains("Codex Bridge started") }))
        #expect(progressEvents.contains(where: { $0.contains("Retrying interrupted run") }))
    }

    @Test("default executor codex bridge preflight failure stops execution")
    func openAICompatibleCodexBridgePreflightFailure() {
        let task = WorkTask(
            title: "Bridge preflight",
            details: "",
            requiredSkills: ["automation"],
            storyPoints: 1,
            status: .todo,
            assignedAgentID: nil
        )
        let agent = AgentProfile(
            name: "Bridge Agent",
            skills: ["automation"],
            runtimeProfile: AgentRuntimeProfile(
                provider: .openAICompatible,
                model: "gpt-5.2",
                openAIAuthMode: .codexBridge
            )
        )
        var runnerCalled = false
        let executor = DefaultAgentTaskExecutor(
            environmentProvider: { [:] },
            urlSession: .shared,
            timeoutSeconds: 1,
            codexBridgePreflight: {
                struct PreflightError: LocalizedError {
                    var errorDescription: String? { "please run codex login" }
                }
                throw PreflightError()
            },
            codexBridgeRunner: { _, _ in
                runnerCalled = true
                return "should not run"
            }
        )

        let outcome = executor.execute(task: task, agent: agent)

        switch outcome {
        case .success:
            #expect(Bool(false), "Expected Codex Bridge preflight failure")
        case let .failure(message):
            #expect(message.contains("Codex Bridge run failed"))
            #expect(message.contains("please run codex login"))
        }
        #expect(runnerCalled == false)
    }

    @Test("default executor retries codex bridge without model when ChatGPT account rejects configured model")
    func openAICompatibleCodexBridgeRetriesWithoutModelForChatGPTAccount() {
        let task = WorkTask(
            title: "Bridge unsupported model",
            details: "",
            requiredSkills: ["automation"],
            storyPoints: 1,
            status: .todo,
            assignedAgentID: nil
        )
        let agent = AgentProfile(
            name: "Bridge Agent",
            skills: ["automation"],
            runtimeProfile: AgentRuntimeProfile(
                provider: .openAICompatible,
                model: "gpt-4.1-mini",
                openAIAuthMode: .codexBridge
            )
        )
        var seenRequests: [DefaultAgentTaskExecutor.CodexBridgeRequest] = []
        let executor = DefaultAgentTaskExecutor(
            environmentProvider: { [:] },
            urlSession: .shared,
            timeoutSeconds: 1,
            codexBridgePreflight: {},
            codexBridgeRunner: { request, _ in
                seenRequests.append(request)
                if seenRequests.count == 1 {
                    struct UnsupportedModelError: LocalizedError {
                        var errorDescription: String? {
                            "The 'gpt-4.1-mini' model is not supported when using Codex with a ChatGPT account."
                        }
                    }
                    throw UnsupportedModelError()
                }
                return "Fallback model execution succeeded"
            }
        )

        let outcome = executor.execute(task: task, agent: agent)

        switch outcome {
        case let .success(summary):
            #expect(summary == "Fallback model execution succeeded")
        case .failure:
            #expect(Bool(false), "Expected fallback success for unsupported ChatGPT-account model")
        }
        #expect(seenRequests.count == 2)
        #expect(seenRequests.first?.model == "gpt-4.1-mini")
        #expect(seenRequests.last?.model == "")
    }

    @Test("codex progress parser reports command start events")
    func codexProgressParsesCommandStartEvent() {
        let line = #"{"type":"item.started","item":{"type":"command_execution","command":"ls -la"}}"#

        let update = DefaultAgentTaskExecutor.codexProgressUpdate(from: line)

        #expect(update == "Running command: ls -la")
    }

    @Test("codex progress parser reports agent message completion events")
    func codexProgressParsesAgentMessageEvent() {
        let line = #"{"type":"item.completed","item":{"type":"agent_message","text":"Implemented task and added tests."}}"#

        let update = DefaultAgentTaskExecutor.codexProgressUpdate(from: line)

        #expect(update == "Implemented task and added tests.")
    }

    @Test("codex progress parser reports command completion with summarized output")
    func codexProgressParsesCommandCompletionEvent() {
        let line = #"{"type":"item.completed","item":{"type":"command_execution","command":"swift test","aggregated_output":"Build started\nBuild finished\nAll tests passed"}}"#

        let update = DefaultAgentTaskExecutor.codexProgressUpdate(from: line)

        #expect(update?.contains("Command completed: swift test") == true)
        #expect(update?.contains("Build started") == true)
        #expect(update?.contains("All tests passed") == true)
    }

    @Test("codex progress parser reports command live output delta events")
    func codexProgressParsesCommandDeltaEvent() {
        let line = #"{"type":"item.updated","item":{"type":"command_execution","command":"swift test","output_delta":"Compiling OpenMacTests.swift"}}"#

        let update = DefaultAgentTaskExecutor.codexProgressUpdate(from: line)

        #expect(update == "Compiling OpenMacTests.swift")
    }

    @Test("codex progress parser surfaces top-level error messages")
    func codexProgressParsesTopLevelErrorMessage() {
        let line = #"{"type":"turn.error","error":{"message":"connection dropped during stream"}}"#

        let update = DefaultAgentTaskExecutor.codexProgressUpdate(from: line)

        #expect(update == "Codex error: connection dropped during stream")
    }

    @Test("codex progress parser ignores non-item json events")
    func codexProgressIgnoresNonItemEvents() {
        let line = #"{"type":"turn.started","turn_id":"abc"}"#

        let update = DefaultAgentTaskExecutor.codexProgressUpdate(from: line)

        #expect(update == nil)
    }

    @Test("codex progress parser falls back to raw text for non-json lines")
    func codexProgressReturnsRawTextForNonJSON() {
        let line = "ERROR: Reconnecting... 2/5"

        let update = DefaultAgentTaskExecutor.codexProgressUpdate(from: line)

        #expect(update == line)
    }

    @Test("codex output summary limits line count and appends ellipsis")
    func codexOutputSummaryTruncatesLines() {
        let output = """
        line1
        line2
        line3
        line4
        """

        let summary = DefaultAgentTaskExecutor.summarizeCommandOutputForConsole(
            output,
            maxLines: 3,
            maxCharacters: 1_000
        )

        #expect(summary == "line1\nline2\nline3\n...")
    }

    @Test("codex output summary limits character count")
    func codexOutputSummaryTruncatesCharacters() {
        let summary = DefaultAgentTaskExecutor.summarizeCommandOutputForConsole(
            "123456789",
            maxLines: 8,
            maxCharacters: 5
        )

        #expect(summary == "12345...")
    }

    @Test("openai compatible api key mode succeeds with mocked chat completion response")
    func openAICompatibleAPIKeySuccess() {
        let task = WorkTask(
            title: "Draft release notes",
            details: "Summarize key changes",
            requiredSkills: ["automation"],
            storyPoints: 2,
            status: .todo,
            assignedAgentID: nil
        )
        let agent = AgentProfile(
            name: "API Agent",
            skills: ["automation"],
            runtimeProfile: AgentRuntimeProfile(
                provider: .openAICompatible,
                model: "gpt-4.1-mini",
                openAIAuthMode: .apiKey
            )
        )

        let mockedSession = makeMockedURLSession()
        MockURLProtocol.requestHandler = { request in
            #expect(request.url?.absoluteString == "https://api.openai.com/v1/chat/completions")
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer sk-test")
            #expect(request.httpMethod == "POST")

            let payload = """
            {
              "choices": [
                {
                  "message": {
                    "role": "assistant",
                    "content": "Summary: Completed release notes draft."
                  }
                }
              ]
            }
            """
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data(payload.utf8))
        }
        defer { MockURLProtocol.requestHandler = nil }

        var progressEvents: [String] = []
        let executor = DefaultAgentTaskExecutor(
            environmentProvider: { ["OPENAI_API_KEY": "sk-test"] },
            urlSession: mockedSession,
            timeoutSeconds: 2
        )
        let outcome = executor.execute(task: task, agent: agent) { update in
            progressEvents.append(update)
        }

        switch outcome {
        case let .success(summary):
            #expect(summary.contains("Completed release notes draft"))
        case let .failure(message):
            #expect(Bool(false), "Expected success, got failure: \(message)")
        }
        #expect(progressEvents.contains(where: { $0.contains("OpenAI request started") }))
        #expect(progressEvents.contains(where: { $0.contains("OpenAI response received") }))
    }

    @Test("openai compatible api key mode uses custom endpoint and returns failure on server errors")
    func openAICompatibleAPIKeyServerError() {
        let task = WorkTask(
            title: "Analyze incidents",
            details: "Summarize outage impact",
            requiredSkills: ["automation"],
            storyPoints: 3,
            status: .todo,
            assignedAgentID: nil
        )
        let agent = AgentProfile(
            name: "API Agent",
            skills: ["automation"],
            runtimeProfile: AgentRuntimeProfile(
                provider: .openAICompatible,
                model: "gpt-4.1-mini",
                endpoint: "https://gateway.example.internal/",
                openAIAuthMode: .apiKey
            )
        )

        let mockedSession = makeMockedURLSession()
        MockURLProtocol.requestHandler = { request in
            #expect(request.url?.absoluteString == "https://gateway.example.internal/v1/chat/completions")
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 500,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data("backend unavailable".utf8))
        }
        defer { MockURLProtocol.requestHandler = nil }

        let executor = DefaultAgentTaskExecutor(
            environmentProvider: { ["OPENAI_API_KEY": "sk-test"] },
            urlSession: mockedSession,
            timeoutSeconds: 2
        )
        let outcome = executor.execute(task: task, agent: agent)

        switch outcome {
        case .success:
            #expect(Bool(false), "Expected failure for 500 server response")
        case let .failure(message):
            #expect(message.contains("backend unavailable"))
        }
    }

    @Test("openai compatible api key mode derives endpoint from OPENAI_BASE_URL")
    func openAICompatibleAPIKeyUsesBaseURLFromEnvironment() {
        let task = WorkTask(
            title: "Refine changelog",
            details: "Use proxy endpoint",
            requiredSkills: ["automation"],
            storyPoints: 1,
            status: .todo,
            assignedAgentID: nil
        )
        let agent = AgentProfile(
            name: "API Agent",
            skills: ["automation"],
            runtimeProfile: AgentRuntimeProfile(
                provider: .openAICompatible,
                model: "gpt-4.1-mini",
                openAIAuthMode: .apiKey
            )
        )

        let mockedSession = makeMockedURLSession()
        MockURLProtocol.requestHandler = { request in
            #expect(request.url?.absoluteString == "https://proxy.example.internal/v1/chat/completions")
            let payload = """
            {
              "choices": [
                {
                  "message": {
                    "role": "assistant",
                    "content": "Summary: Routed through proxy."
                  }
                }
              ]
            }
            """
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data(payload.utf8))
        }
        defer { MockURLProtocol.requestHandler = nil }

        let executor = DefaultAgentTaskExecutor(
            environmentProvider: {
                [
                    "OPENAI_API_KEY": "sk-test",
                    "OPENAI_BASE_URL": "https://proxy.example.internal"
                ]
            },
            urlSession: mockedSession,
            timeoutSeconds: 2
        )
        let outcome = executor.execute(task: task, agent: agent)

        switch outcome {
        case let .success(summary):
            #expect(summary.contains("Routed through proxy"))
        case let .failure(message):
            #expect(Bool(false), "Expected success via proxy endpoint, got: \(message)")
        }
    }

    @Test("agent task executing protocol default progress overload delegates to base execute")
    func agentTaskExecutingDefaultProgressOverloadDelegates() {
        struct StubExecutor: AgentTaskExecuting {
            let outcome: AgentTaskExecutionOutcome

            func execute(task _: WorkTask, agent _: AgentProfile) -> AgentTaskExecutionOutcome {
                outcome
            }
        }

        let task = WorkTask(
            title: "Delegate",
            details: "",
            requiredSkills: [],
            storyPoints: 1,
            status: .todo,
            assignedAgentID: nil
        )
        let agent = AgentProfile(name: "Agent", skills: [], maxConcurrentTasks: 1)
        let executor = StubExecutor(outcome: .success(summary: "ok"))

        let outcome = executor.execute(task: task, agent: agent) { _ in
            #expect(Bool(false), "Default overload should ignore progress closure")
        }

        switch outcome {
        case let .success(summary):
            #expect(summary == "ok")
        case .failure:
            #expect(Bool(false), "Expected delegated success outcome")
        }
    }

    @Test("codex prompt template supports all configured app languages")
    func codexPromptTemplateSupportsAllLanguages() {
        let task = WorkTask(
            title: "Build",
            details: "Implement feature",
            requiredSkills: [],
            storyPoints: 3,
            status: .todo,
            assignedAgentID: nil
        )
        let agent = AgentProfile(name: "A", skills: ["swift"], maxConcurrentTasks: 1)

        let expectations: [(AppLanguage, String, String)] = [
            (.english, "You are supporting an assigned AI agent in a kanban execution system.", "Required skills: none"),
            (.traditionalChinese, "你正在看板執行系統中支援一位已指派的 AI 代理。", "所需技能: 無"),
            (.simplifiedChinese, "你正在看板执行系统中支持一位已分配的 AI 代理。", "所需技能: 无"),
            (.french, "Vous assistez un agent IA assigne dans un systeme d'execution kanban.", "Competences requises: aucune"),
            (.spanish, "Estas apoyando a un agente de IA asignado en un sistema kanban de ejecucion.", "Habilidades requeridas: ninguna"),
            (.japanese, "あなたはカンバン実行システムで割り当て済みの AI エージェントを支援しています。", "必要スキル: なし"),
            (.korean, "당신은 칸반 실행 시스템에서 할당된 AI 에이전트를 지원하고 있습니다.", "필수 스킬: 없음")
        ]

        for (language, preamble, noSkillsLine) in expectations {
            let prompt = KanbanBoardViewModelTestHooks.codexPrompt(
                languageOverrideRawValue: language.rawValue,
                task: task,
                agent: agent
            )
            #expect(prompt.contains(preamble))
            #expect(prompt.contains(noSkillsLine))
        }
    }

    @Test("endpoint resolution normalizes configured and environment base URLs")
    func endpointResolutionNormalizationRules() {
        #expect(
            KanbanBoardViewModelTestHooks.resolvedEndpoint(
                configuredEndpoint: "https://gateway.example/v1/chat/completions",
                environment: [:]
            ) == "https://gateway.example/v1/chat/completions"
        )
        #expect(
            KanbanBoardViewModelTestHooks.resolvedEndpoint(
                configuredEndpoint: "https://gateway.example/",
                environment: [:]
            ) == "https://gateway.example/v1/chat/completions"
        )
        #expect(
            KanbanBoardViewModelTestHooks.resolvedEndpoint(
                configuredEndpoint: "https://gateway.example",
                environment: [:]
            ) == "https://gateway.example/v1/chat/completions"
        )
        #expect(
            KanbanBoardViewModelTestHooks.resolvedEndpoint(
                configuredEndpoint: nil,
                environment: ["OPENAI_BASE_URL": "https://proxy.example/v1/chat/completions"]
            ) == "https://proxy.example/v1/chat/completions"
        )
        #expect(
            KanbanBoardViewModelTestHooks.resolvedEndpoint(
                configuredEndpoint: nil,
                environment: ["OPENAI_BASE_URL": "https://proxy.example"]
            ) == "https://proxy.example/v1/chat/completions"
        )
        #expect(
            KanbanBoardViewModelTestHooks.resolvedEndpoint(
                configuredEndpoint: nil,
                environment: [:]
            ) == "https://api.openai.com/v1/chat/completions"
        )
    }

    @Test("codex failure summary maps common bridge failure categories")
    func codexFailureSummaryMappings() {
        let unsupported = KanbanBoardViewModelTestHooks.summarizeCodexBridgeFailure(
            "The 'gpt-4.1-mini' model is not supported when using Codex with a ChatGPT account."
        )
        #expect(unsupported.contains("not supported for Codex Bridge with ChatGPT login"))

        let quota = KanbanBoardViewModelTestHooks.summarizeCodexBridgeFailure("usage limit exceeded: insufficient_quota")
        #expect(quota.contains("usage limit/quota appears exhausted"))

        let unauthorized = KanbanBoardViewModelTestHooks.summarizeCodexBridgeFailure(
            "401 Unauthorized: Missing bearer or basic authentication in header"
        )
        #expect(unauthorized.contains("authentication missing"))
        #expect(unauthorized.contains("codex login --device-auth"))

        let permission = KanbanBoardViewModelTestHooks.summarizeCodexBridgeFailure("Operation not permitted (os error 1)")
        #expect(permission.contains("Permission denied while accessing Codex profile"))

        let dns = KanbanBoardViewModelTestHooks.summarizeCodexBridgeFailure(
            "failed to connect to websocket: failed to lookup address information: nodename nor servname provided"
        )
        #expect(dns.contains("Network/DNS lookup failed"))

        let websocket = KanbanBoardViewModelTestHooks.summarizeCodexBridgeFailure(
            "failed to connect to websocket: connection dropped"
        )
        #expect(websocket.contains("could not connect to OpenAI"))

        let login = KanbanBoardViewModelTestHooks.summarizeCodexBridgeFailure("please run codex login first")
        #expect(login.contains("Codex Bridge requires login"))

        let notFound = KanbanBoardViewModelTestHooks.summarizeCodexBridgeFailure("env: codex: No such file or directory")
        #expect(notFound.contains("Codex CLI not found"))

        let unknown = KanbanBoardViewModelTestHooks.summarizeCodexBridgeFailure("")
        #expect(unknown == "Unknown Codex Bridge error")
    }

    @Test("codex failure detectors classify usage-limit and unsupported-model messages")
    func codexFailureDetectors() {
        #expect(KanbanBoardViewModelTestHooks.isCodexUsageLimitError("usage limit exceeded"))
        #expect(KanbanBoardViewModelTestHooks.isCodexUsageLimitError("billing hard limit reached"))
        #expect(!KanbanBoardViewModelTestHooks.isCodexUsageLimitError("network timeout"))

        #expect(
            KanbanBoardViewModelTestHooks.isCodexChatGPTModelUnsupported(
                "model is not supported when using Codex with a ChatGPT account"
            )
        )
        #expect(!KanbanBoardViewModelTestHooks.isCodexChatGPTModelUnsupported("model unavailable"))
    }

    @Test("codex bridge sandbox mode and environment helpers are deterministic")
    func codexBridgeSandboxAndEnvironmentHelpers() throws {
        #expect(
            KanbanBoardViewModelTestHooks.resolvedCodexBridgeSandboxMode(environment: [:]) == "danger-full-access"
        )
        #expect(
            KanbanBoardViewModelTestHooks.resolvedCodexBridgeSandboxMode(
                environment: ["OPENMAC_CODEX_SANDBOX": "workspace_write"]
            ) == "workspace-write"
        )
        #expect(
            KanbanBoardViewModelTestHooks.resolvedCodexBridgeSandboxMode(
                environment: ["OPENMAC_CODEX_SANDBOX": "none"]
            ) == nil
        )
        #expect(
            KanbanBoardViewModelTestHooks.resolvedCodexBridgeSandboxMode(
                environment: ["OPENMAC_CODEX_SANDBOX": "unexpected-value"]
            ) == "danger-full-access"
        )

        let processedEnv = KanbanBoardViewModelTestHooks.codexBridgeProcessEnvironment(
            environment: ["CODEX_HOME": "   ", "PATH": "/usr/bin"]
        )
        #expect(processedEnv["CODEX_HOME"] == nil)
        #expect(processedEnv["PATH"] == "/usr/bin")

        let loginCommand = KanbanBoardViewModelTestHooks.codexLoginCommand(
            environment: ["HOME": "/tmp/home", "CODEX_HOME": "/tmp/custom-codex-home"],
            homeDirectoryPath: "/fallback/home"
        )
        #expect(loginCommand.contains("HOME=\"/tmp/home\""))
        #expect(loginCommand.contains("CODEX_HOME=\"/tmp/custom-codex-home\""))
        #expect(loginCommand.contains("codex login --device-auth"))

        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("openmac-codex-hook-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }
        let executableURL = tempDirectory.appendingPathComponent("codex")
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: executableURL)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executableURL.path)

        let resolvedFromExplicit = KanbanBoardViewModelTestHooks.resolvedCodexExecutablePath(
            environment: ["CODEX_CLI_PATH": executableURL.path, "PATH": ""],
            fallbackCandidates: [],
            homeDirectoryPath: tempDirectory.path
        )
        #expect(resolvedFromExplicit == executableURL.path)

        let resolvedFromPATH = KanbanBoardViewModelTestHooks.resolvedCodexExecutablePath(
            environment: ["PATH": tempDirectory.path],
            fallbackCandidates: [],
            homeDirectoryPath: tempDirectory.path
        )
        #expect(resolvedFromPATH == executableURL.path)

        let unresolved = KanbanBoardViewModelTestHooks.resolvedCodexExecutablePath(
            environment: ["PATH": "/non-existent"],
            fallbackCandidates: [],
            homeDirectoryPath: tempDirectory.path
        )
        #expect(unresolved == nil)
    }

    @Test("executor error descriptions remain user-readable")
    func executorErrorDescriptionsRemainReadable() {
        let descriptions = KanbanBoardViewModelTestHooks.executorErrorDescriptions(serverMessage: "server exploded")

        #expect(descriptions[0] == "Request timed out")
        #expect(descriptions[1] == "Invalid response")
        #expect(descriptions[2] == "Empty response")
        #expect(descriptions[3] == "server exploded")
        #expect(descriptions[4] == "server exploded")
    }

    @Test("default codex bridge runner prefers output-last-message file and streams progress")
    func defaultCodexBridgeRunnerUsesOutputFileSummary() throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("openmac-codex-runner-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let script = try makeExecutableScript(
            contents: """
            #!/bin/sh
            out=""
            while [ "$#" -gt 0 ]; do
              if [ "$1" = "--output-last-message" ]; then
                shift
                out="$1"
              fi
              shift
            done
            echo '{"type":"item.started","item":{"type":"command_execution","command":"echo hi"}}'
            echo '{"type":"item.completed","item":{"type":"agent_message","text":"agent finished"}}'
            if [ -n "$out" ]; then
              printf 'Summary from fake codex\\n' > "$out"
            fi
            exit 0
            """,
            in: tempDirectory,
            name: "codex"
        )

        let request = DefaultAgentTaskExecutor.CodexBridgeRequest(
            prompt: "run",
            model: "gpt-5",
            profile: "test",
            workingDirectoryPath: tempDirectory.path
        )
        var progressUpdates: [String] = []
        let environment = [
            "CODEX_CLI_PATH": script.path,
            "PATH": "",
            "OPENMAC_CODEX_SANDBOX": "none"
        ]
        let summary = try KanbanBoardViewModelTestHooks.runDefaultCodexBridgeRunner(
            request: request,
            onProgress: { update in
                progressUpdates.append(update)
            },
            environment: environment
        )

        #expect(summary == "Summary from fake codex")
        #expect(progressUpdates.contains(where: { $0.contains("Codex workdir:") }))
        #expect(progressUpdates.contains("Running command: echo hi"))
        #expect(progressUpdates.contains("agent finished"))
    }

    @Test("default codex bridge runner falls back to raw output when output file is missing")
    func defaultCodexBridgeRunnerFallsBackToRawOutput() throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("openmac-codex-raw-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let script = try makeExecutableScript(
            contents: """
            #!/bin/sh
            echo 'RAW OUTPUT LINE'
            exit 0
            """,
            in: tempDirectory,
            name: "codex"
        )

        let request = DefaultAgentTaskExecutor.CodexBridgeRequest(
            prompt: "run",
            model: "gpt-5",
            profile: nil,
            workingDirectoryPath: tempDirectory.path
        )

        let summary = try KanbanBoardViewModelTestHooks.runDefaultCodexBridgeRunner(
            request: request,
            onProgress: { _ in },
            environment: [
                "CODEX_CLI_PATH": script.path,
                "PATH": "",
                "OPENMAC_CODEX_SANDBOX": "none"
            ]
        )

        #expect(summary.contains("RAW OUTPUT LINE"))
    }

    @Test("default codex bridge runner reports empty response when codex returns no output")
    func defaultCodexBridgeRunnerEmptyResponseFailure() throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("openmac-codex-empty-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let script = try makeExecutableScript(
            contents: """
            #!/bin/sh
            exit 0
            """,
            in: tempDirectory,
            name: "codex"
        )

        let request = DefaultAgentTaskExecutor.CodexBridgeRequest(
            prompt: "run",
            model: "gpt-5",
            profile: nil,
            workingDirectoryPath: tempDirectory.path
        )

        do {
            _ = try KanbanBoardViewModelTestHooks.runDefaultCodexBridgeRunner(
                request: request,
                onProgress: { _ in },
                environment: [
                    "CODEX_CLI_PATH": script.path,
                    "PATH": "",
                    "OPENMAC_CODEX_SANDBOX": "none"
                ]
            )
            #expect(Bool(false), "Expected empty-response failure")
        } catch {
            #expect(error.localizedDescription.contains("Empty response"))
        }
    }

    @Test("default codex bridge runner surfaces non-zero codex exit output")
    func defaultCodexBridgeRunnerNonZeroExitFailure() throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("openmac-codex-nonzero-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let script = try makeExecutableScript(
            contents: """
            #!/bin/sh
            echo 'codex failed hard'
            exit 3
            """,
            in: tempDirectory,
            name: "codex"
        )

        let request = DefaultAgentTaskExecutor.CodexBridgeRequest(
            prompt: "run",
            model: "gpt-5",
            profile: nil,
            workingDirectoryPath: tempDirectory.path
        )

        do {
            _ = try KanbanBoardViewModelTestHooks.runDefaultCodexBridgeRunner(
                request: request,
                onProgress: { _ in },
                environment: [
                    "CODEX_CLI_PATH": script.path,
                    "PATH": "",
                    "OPENMAC_CODEX_SANDBOX": "none"
                ]
            )
            #expect(Bool(false), "Expected non-zero exit failure")
        } catch {
            #expect(error.localizedDescription.contains("codex failed hard"))
        }
    }

    @Test("default codex bridge preflight validates login status output")
    func defaultCodexBridgePreflightLoginStatusValidation() throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("openmac-codex-preflight-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let successScript = try makeExecutableScript(
            contents: """
            #!/bin/sh
            if [ "$1" = "login" ] && [ "$2" = "status" ]; then
              echo 'Logged in as test-user'
              exit 0
            fi
            exit 1
            """,
            in: tempDirectory,
            name: "codex-success"
        )

        try KanbanBoardViewModelTestHooks.runDefaultCodexBridgePreflight(
            environment: [
                "CODEX_CLI_PATH": successScript.path,
                "PATH": ""
            ]
        )

        let failScript = try makeExecutableScript(
            contents: """
            #!/bin/sh
            echo 'authentication missing'
            exit 0
            """,
            in: tempDirectory,
            name: "codex-fail"
        )

        do {
            try KanbanBoardViewModelTestHooks.runDefaultCodexBridgePreflight(
                environment: [
                    "CODEX_CLI_PATH": failScript.path,
                    "PATH": ""
                ]
            )
            #expect(Bool(false), "Expected preflight failure when login status is not authenticated")
        } catch {
            #expect(error.localizedDescription.contains("profile is not logged in"))
        }
    }

    @Test("default codex bridge recovery emits progress and runs quit/open command sequence")
    func defaultCodexBridgeRecoveryCommandSequence() throws {
        var progress: [String] = []
        var sleepDurations: [TimeInterval] = []
        var commands: [(path: String, arguments: [String])] = []

        try KanbanBoardViewModelTestHooks.runDefaultCodexBridgeRecovery(
            reason: "usage limit exceeded",
            onProgress: { progress.append($0) },
            environment: [:],
            commandRunner: { executablePath, arguments, _ in
                commands.append((executablePath, arguments))
                return (0, "")
            },
            sleeper: { sleepDurations.append($0) }
        )

        #expect(commands.count == 2)
        #expect(commands[0].path == "/usr/bin/osascript")
        #expect(commands[0].arguments == ["-e", "tell application \"Codex\" to quit"])
        #expect(commands[1].path == "/usr/bin/open")
        #expect(commands[1].arguments == ["-a", "Codex"])
        #expect(sleepDurations == [1.0, 1.5])
        #expect(progress.contains(where: { $0.contains("Restarting Codex app") }))
        #expect(progress.contains(where: { $0.contains("restart complete") }))
    }

    @Test("default codex bridge recovery surfaces restart failure output")
    func defaultCodexBridgeRecoveryFailureOutput() {
        do {
            try KanbanBoardViewModelTestHooks.runDefaultCodexBridgeRecovery(
                reason: "quota",
                onProgress: { _ in },
                environment: [:],
                commandRunner: { executablePath, _, _ in
                    if executablePath == "/usr/bin/open" {
                        return (1, "LSOpenURLsWithRole() failed")
                    }
                    return (0, "")
                },
                sleeper: { _ in }
            )
            #expect(Bool(false), "Expected recovery to fail when `open -a Codex` fails")
        } catch {
            #expect(error.localizedDescription.contains("Codex app restart failed"))
            #expect(error.localizedDescription.contains("LSOpenURLsWithRole() failed"))
        }
    }

    @Test("system command helper captures stdout/stderr and termination status")
    func runSystemCommandCapturesOutputAndExitCode() throws {
        let success = try KanbanBoardViewModelTestHooks.runSystemCommand(
            executablePath: "/bin/sh",
            arguments: ["-c", "printf 'ok-output'"],
            environment: ["PATH": "/usr/bin:/bin"]
        )
        #expect(success.code == 0)
        #expect(success.output == "ok-output")

        let failure = try KanbanBoardViewModelTestHooks.runSystemCommand(
            executablePath: "/bin/sh",
            arguments: ["-c", "echo err-output 1>&2; exit 7"],
            environment: ["PATH": "/usr/bin:/bin"]
        )
        #expect(failure.code == 7)
        #expect(failure.output.contains("err-output"))
    }

    @Test("default initializer keeps sensible executor defaults")
    func defaultExecutorInitializerDefaults() {
        let executor = DefaultAgentTaskExecutor()
        let env = executor.environmentProvider()

        #expect(executor.timeoutSeconds == 30)
        #expect(!env.isEmpty)
    }

    @Test("projects directory resolver honors user defaults fallback and trims invalid values")
    func projectsDirectoryResolverUserDefaultsFallback() {
        let suiteName = "openmac-tests.projects.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            #expect(Bool(false), "Failed to initialize isolated UserDefaults suite")
            return
        }
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let customPath = "/tmp/openmac-projects-\(UUID().uuidString)"
        defaults.set("  \(customPath)  ", forKey: CodexProjectsDirectorySettings.userDefaultsKey)

        let resolvedFromDefaults = CodexProjectsDirectorySettings.resolvedProjectsDirectoryPath(
            environment: [CodexProjectsDirectorySettings.environmentOverrideKey: "   "],
            userDefaults: defaults
        )
        #expect(resolvedFromDefaults == customPath)

        defaults.set("   ", forKey: CodexProjectsDirectorySettings.userDefaultsKey)
        let resolvedDefault = CodexProjectsDirectorySettings.resolvedProjectsDirectoryPath(
            environment: [:],
            userDefaults: defaults
        )
        #expect(resolvedDefault.contains("Library/Application Support/OpenMac/Projects"))
    }
}

struct ItemModelTests {
    @Test("item stores provided timestamp")
    func storesProvidedTimestamp() {
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
        let item = Item(timestamp: timestamp)

        #expect(item.timestamp == timestamp)
    }
}

struct AppearanceModeTests {

    @Test("maps appearance mode to preferred color scheme")
    func mapsAppearanceModeToPreferredColorScheme() {
        #expect(AppAppearanceMode.system.preferredColorScheme == nil)
        #expect(AppAppearanceMode.light.preferredColorScheme == .light)
        #expect(AppAppearanceMode.dark.preferredColorScheme == .dark)
    }

    @Test("defaults invalid stored appearance mode to system")
    func defaultsInvalidStoredAppearanceModeToSystem() {
        #expect(AppAppearanceMode.resolve(rawValue: "invalid") == .system)
    }

    @Test("cycles appearance mode in stable order")
    func cyclesAppearanceModeInStableOrder() {
        #expect(AppAppearanceMode.system.next() == .light)
        #expect(AppAppearanceMode.light.next() == .dark)
        #expect(AppAppearanceMode.dark.next() == .system)
    }

    @Test("resolves effective color scheme from system scheme and selected appearance mode")
    func resolvesEffectiveColorSchemeFromAppearanceSelection() {
        #expect(AppearanceSchemeResolver.resolve(systemScheme: .light, appearanceMode: .system) == .light)
        #expect(AppearanceSchemeResolver.resolve(systemScheme: .dark, appearanceMode: .system) == .dark)
        #expect(AppearanceSchemeResolver.resolve(systemScheme: .light, appearanceMode: .dark) == .dark)
        #expect(AppearanceSchemeResolver.resolve(systemScheme: .dark, appearanceMode: .light) == .light)
    }

    @Test("board message palette falls back to error tone when severity is missing")
    func boardMessagePaletteFallbacksToError() {
        let fallbackDark = BoardMessageColorPalette.token(for: nil, scheme: .dark)
        let fallbackLight = BoardMessageColorPalette.token(for: nil, scheme: .light)
        let errorDark = BoardMessageColorPalette.token(for: .error, scheme: .dark)
        let errorLight = BoardMessageColorPalette.token(for: .error, scheme: .light)

        #expect(fallbackDark.red == errorDark.red)
        #expect(fallbackDark.green == errorDark.green)
        #expect(fallbackDark.blue == errorDark.blue)
        #expect(fallbackDark.opacity == errorDark.opacity)

        #expect(fallbackLight.red == errorLight.red)
        #expect(fallbackLight.green == errorLight.green)
        #expect(fallbackLight.blue == errorLight.blue)
        #expect(fallbackLight.opacity == errorLight.opacity)
    }

    @Test("board message palette maintains dark mode contrast for all severities")
    func boardMessagePaletteDarkContrast() {
        let background = BoardMessageColorPalette.darkBoardBackground
        let infoContrast = BoardMessageColorPalette.token(for: .info, scheme: .dark).contrastRatio(against: background)
        let warningContrast = BoardMessageColorPalette.token(for: .warning, scheme: .dark).contrastRatio(against: background)
        let errorContrast = BoardMessageColorPalette.token(for: .error, scheme: .dark).contrastRatio(against: background)

        #expect(infoContrast >= 4.5)
        #expect(warningContrast >= 4.5)
        #expect(errorContrast >= 4.5)
    }

    @Test("board message palette maintains light mode contrast for all severities")
    func boardMessagePaletteLightContrast() {
        let background = BoardMessageColorPalette.lightBoardBackground
        let infoContrast = BoardMessageColorPalette.token(for: .info, scheme: .light).contrastRatio(against: background)
        let warningContrast = BoardMessageColorPalette.token(for: .warning, scheme: .light).contrastRatio(against: background)
        let errorContrast = BoardMessageColorPalette.token(for: .error, scheme: .light).contrastRatio(against: background)

        #expect(infoContrast >= 4.5)
        #expect(warningContrast >= 4.5)
        #expect(errorContrast >= 4.5)
    }

    @Test("summary badge palette maintains dark mode contrast across all accents")
    func summaryBadgePaletteDarkContrast() {
        let primaryText = BoardMessageColorToken(red: 1.0, green: 1.0, blue: 1.0, opacity: 1.0)

        for accent in SummaryBadgeAccent.allCases {
            let token = SummaryBadgePalette.token(for: accent, scheme: .dark)
            #expect(primaryText.contrastRatio(against: token) >= 4.5)
        }
    }

    @Test("summary badge palette maintains light mode contrast across all accents")
    func summaryBadgePaletteLightContrast() {
        let primaryText = BoardMessageColorToken(red: 0.0, green: 0.0, blue: 0.0, opacity: 1.0)

        for accent in SummaryBadgeAccent.allCases {
            let token = SummaryBadgePalette.token(for: accent, scheme: .light)
            #expect(primaryText.contrastRatio(against: token) >= 7.0)
        }
    }

    @Test("semantic status text palette keeps contrast in dark and light board backgrounds")
    func semanticStatusTextPaletteContrast() {
        let darkBackground = BoardMessageColorPalette.darkBoardBackground
        let lightBackground = BoardMessageColorPalette.lightBoardBackground
        let darkSupplementary = BoardSurfacePalette.supplementaryCardToken(for: .dark)
        let lightSupplementary = BoardSurfacePalette.supplementaryCardToken(for: .light)

        let successDark = BoardSemanticTextPalette.token(for: .success, scheme: .dark)
        let successLight = BoardSemanticTextPalette.token(for: .success, scheme: .light)
        let warningDark = BoardSemanticTextPalette.token(for: .warning, scheme: .dark)
        let warningLight = BoardSemanticTextPalette.token(for: .warning, scheme: .light)
        let errorDark = BoardSemanticTextPalette.token(for: .error, scheme: .dark)
        let errorLight = BoardSemanticTextPalette.token(for: .error, scheme: .light)

        #expect(successDark.contrastRatio(against: darkBackground) >= 4.5)
        #expect(successLight.contrastRatio(against: lightBackground) >= 4.5)
        #expect(warningDark.contrastRatio(against: darkBackground) >= 4.5)
        #expect(warningLight.contrastRatio(against: lightBackground) >= 4.5)
        #expect(errorDark.contrastRatio(against: darkBackground) >= 4.5)
        #expect(errorLight.contrastRatio(against: lightBackground) >= 4.5)
        #expect(errorDark.contrastRatio(against: darkSupplementary) >= 4.5)
        #expect(errorLight.contrastRatio(against: lightSupplementary) >= 4.5)
    }

    @Test("semantic error text keeps contrast on WIP counter surfaces")
    func semanticErrorTextCounterContrast() {
        let errorDark = BoardSemanticTextPalette.token(for: .error, scheme: .dark)
        let errorLight = BoardSemanticTextPalette.token(for: .error, scheme: .light)
        let counterDark = BoardChromePalette.counterToken(for: .dark)
        let counterLight = BoardChromePalette.counterToken(for: .light)

        #expect(errorDark.contrastRatio(against: counterDark) >= 4.5)
        #expect(errorLight.contrastRatio(against: counterLight) >= 4.5)
    }

    @Test("neutral secondary text palette remains readable across board surfaces")
    func neutralSecondaryTextPaletteContrast() {
        let secondaryDark = BoardNeutralTextPalette.token(for: .secondary, scheme: .dark)
        let secondaryLight = BoardNeutralTextPalette.token(for: .secondary, scheme: .light)

        let darkSurfaces = KanbanStatus.allCases.map { BoardSurfacePalette.columnToken(for: $0, scheme: .dark) }
            + [
                BoardSurfacePalette.taskCardToken(for: .dark),
                BoardSurfacePalette.supplementaryCardToken(for: .dark)
            ]

        let lightSurfaces = KanbanStatus.allCases.map { BoardSurfacePalette.columnToken(for: $0, scheme: .light) }
            + [
                BoardSurfacePalette.taskCardToken(for: .light),
                BoardSurfacePalette.supplementaryCardToken(for: .light)
            ]

        for surface in darkSurfaces {
            #expect(secondaryDark.contrastRatio(against: surface) >= 4.5)
        }

        for surface in lightSurfaces {
            #expect(secondaryLight.contrastRatio(against: surface) >= 4.5)
        }
    }

    @Test("dark task cards stay visually distinct from each kanban column background")
    func darkTaskCardsRemainDistinctFromColumns() {
        let taskCard = BoardSurfacePalette.taskCardToken(for: .dark)

        for status in KanbanStatus.allCases {
            let column = BoardSurfacePalette.columnToken(for: status, scheme: .dark)
            #expect(taskCard.contrastRatio(against: column) >= 1.5)
        }
    }

    @Test("dark board surfaces keep readable primary text contrast")
    func darkBoardSurfacesKeepReadablePrimaryTextContrast() {
        let primaryText = BoardMessageColorToken(red: 1.0, green: 1.0, blue: 1.0, opacity: 1.0)
        let taskCardContrast = primaryText.contrastRatio(against: BoardSurfacePalette.taskCardToken(for: .dark))

        #expect(taskCardContrast >= 4.5)
        for status in KanbanStatus.allCases {
            let columnContrast = primaryText.contrastRatio(against: BoardSurfacePalette.columnToken(for: status, scheme: .dark))
            #expect(columnContrast >= 4.5)
        }
    }

    @Test("dark supplementary surfaces keep readable primary text contrast")
    func darkSupplementarySurfacesKeepReadablePrimaryTextContrast() {
        let primaryText = BoardMessageColorToken(red: 1.0, green: 1.0, blue: 1.0, opacity: 1.0)
        let supplementaryContrast = primaryText.contrastRatio(against: BoardSurfacePalette.supplementaryCardToken(for: .dark))
        let emptyStateContrast = primaryText.contrastRatio(against: BoardSurfacePalette.emptyStateToken(for: .dark))

        #expect(supplementaryContrast >= 4.5)
        #expect(emptyStateContrast >= 4.5)
    }

    @Test("dark empty state remains distinct from dark task card")
    func darkEmptyStateRemainsDistinctFromTaskCard() {
        let emptyState = BoardSurfacePalette.emptyStateToken(for: .dark)
        let taskCard = BoardSurfacePalette.taskCardToken(for: .dark)

        #expect(emptyState.contrastRatio(against: taskCard) >= 1.2)
    }

    @Test("dark chrome surfaces keep readable primary text contrast")
    func darkChromeSurfacesKeepReadablePrimaryTextContrast() {
        let primaryText = BoardMessageColorToken(red: 1.0, green: 1.0, blue: 1.0, opacity: 1.0)
        let counterContrast = primaryText.contrastRatio(against: BoardChromePalette.counterToken(for: .dark))
        let storyPointContrast = primaryText.contrastRatio(against: BoardChromePalette.storyPointToken(for: .dark))

        #expect(counterContrast >= 4.5)
        #expect(storyPointContrast >= 4.5)
    }

    @Test("dark chrome borders remain visible against their host surfaces")
    func darkChromeBordersRemainVisibleAgainstHostSurfaces() {
        let columnBorder = BoardChromePalette.columnBorderToken(for: .dark)
        let taskBorder = BoardChromePalette.taskCardBorderToken(for: .dark)
        let supplementaryBorder = BoardChromePalette.supplementaryCardBorderToken(for: .dark)

        for status in KanbanStatus.allCases {
            let column = BoardSurfacePalette.columnToken(for: status, scheme: .dark)
            #expect(columnBorder.contrastRatio(against: column) >= 1.3)
        }

        #expect(taskBorder.contrastRatio(against: BoardSurfacePalette.taskCardToken(for: .dark)) >= 1.3)
        #expect(supplementaryBorder.contrastRatio(against: BoardSurfacePalette.supplementaryCardToken(for: .dark)) >= 1.3)
    }

    @Test("light chrome surfaces keep readable primary text contrast")
    func lightChromeSurfacesKeepReadablePrimaryTextContrast() {
        let primaryText = BoardMessageColorToken(red: 0.0, green: 0.0, blue: 0.0, opacity: 1.0)
        let counterContrast = primaryText.contrastRatio(against: BoardChromePalette.counterToken(for: .light))
        let storyPointContrast = primaryText.contrastRatio(against: BoardChromePalette.storyPointToken(for: .light))

        #expect(counterContrast >= 7.0)
        #expect(storyPointContrast >= 7.0)
    }

    @Test("light chrome borders remain visible against their host surfaces")
    func lightChromeBordersRemainVisibleAgainstHostSurfaces() {
        let columnBorder = BoardChromePalette.columnBorderToken(for: .light)
        let taskBorder = BoardChromePalette.taskCardBorderToken(for: .light)
        let supplementaryBorder = BoardChromePalette.supplementaryCardBorderToken(for: .light)

        for status in KanbanStatus.allCases {
            let column = BoardSurfacePalette.columnToken(for: status, scheme: .light)
            #expect(columnBorder.contrastRatio(against: column) >= 1.25)
        }

        #expect(taskBorder.contrastRatio(against: BoardSurfacePalette.taskCardToken(for: .light)) >= 1.25)
        #expect(supplementaryBorder.contrastRatio(against: BoardSurfacePalette.supplementaryCardToken(for: .light)) >= 1.25)
    }
}

struct KanbanFlowTests {

    @Test("allows adjacent forward and backward transitions")
    func allowsAdjacentTransitions() {
        #expect(KanbanStatus.todo.canMove(to: .inProgress))
        #expect(KanbanStatus.inProgress.canMove(to: .review))
        #expect(KanbanStatus.review.canMove(to: .done))
        #expect(KanbanStatus.review.canMove(to: .inProgress))
        #expect(KanbanStatus.inProgress.canMove(to: .todo))
    }

    @Test("prevents skipping columns")
    func preventsSkippingColumns() {
        #expect(!KanbanStatus.todo.canMove(to: .review))
        #expect(!KanbanStatus.todo.canMove(to: .done))
        #expect(!KanbanStatus.done.canMove(to: .todo))
    }

    @Test("view model applies valid move and rejects invalid move")
    func viewModelMoveValidation() {
        let task = WorkTask(
            title: "Write tests",
            details: "TDD first",
            requiredSkills: ["swift"],
            storyPoints: 1,
            status: .todo,
            assignedAgentID: nil
        )

        let viewModel = KanbanBoardViewModel(tasks: [task], agents: [])
        viewModel.moveTask(task.id, to: .done)

        #expect(viewModel.tasks[0].status == .todo)

        viewModel.moveTask(task.id, to: .inProgress)
        #expect(viewModel.tasks[0].status == .inProgress)
    }

    @Test("moving task back to todo clears assignment for redispatch")
    func moveBackToTodoClearsAssignment() {
        let agent = AgentProfile(name: "Dispatch Agent", skills: ["swift"], maxConcurrentTasks: 2)
        let task = WorkTask(
            title: "Refine flow",
            details: "Needs another iteration",
            requiredSkills: ["swift"],
            storyPoints: 2,
            status: .inProgress,
            assignedAgentID: agent.id
        )

        let viewModel = KanbanBoardViewModel(tasks: [task], agents: [agent])
        viewModel.moveTask(task.id, to: .todo)

        #expect(viewModel.tasks[0].status == .todo)
        #expect(viewModel.tasks[0].assignedAgentID == nil)
    }

    @Test("drop handler applies adjacent move and rejects skipped columns")
    func dropHandlerRespectsWorkflow() {
        let task = WorkTask(
            title: "Drop test",
            details: "Validate drag and drop routing",
            requiredSkills: ["swiftui"],
            storyPoints: 1,
            status: .todo,
            assignedAgentID: nil
        )
        let viewModel = KanbanBoardViewModel(tasks: [task], agents: [])

        let skipped = viewModel.handleDrop(task.id, to: .review)
        #expect(!skipped)
        #expect(viewModel.tasks[0].status == .todo)

        let adjacent = viewModel.handleDrop(task.id, to: .inProgress)
        #expect(adjacent)
        #expect(viewModel.tasks[0].status == .inProgress)
    }

    @Test("prevents move into a column that reached WIP limit")
    func preventsMoveWhenWIPLimitReached() {
        let activeTask = WorkTask(
            title: "Already active",
            details: "Occupies WIP slot",
            requiredSkills: ["swiftui"],
            storyPoints: 2,
            status: .inProgress,
            assignedAgentID: nil
        )
        let todoTask = WorkTask(
            title: "Queued task",
            details: "Should wait for capacity",
            requiredSkills: ["swiftui"],
            storyPoints: 1,
            status: .todo,
            assignedAgentID: nil
        )

        let viewModel = KanbanBoardViewModel(
            tasks: [activeTask, todoTask],
            agents: [],
            wipLimits: [.inProgress: 1]
        )

        let moved = viewModel.handleDrop(todoTask.id, to: .inProgress)

        #expect(!moved)
        #expect(viewModel.tasks.first(where: { $0.id == todoTask.id })?.status == .todo)
        #expect(viewModel.lastBoardMessage == "WIP limit reached for In Progress (1)")
    }

    @Test("allows move once WIP slot becomes available")
    func allowsMoveAfterWIPSlotFreesUp() {
        let activeTask = WorkTask(
            title: "In progress task",
            details: "Will move forward",
            requiredSkills: ["swiftui"],
            storyPoints: 2,
            status: .inProgress,
            assignedAgentID: nil
        )
        let queuedTask = WorkTask(
            title: "Queued",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 1,
            status: .todo,
            assignedAgentID: nil
        )

        let viewModel = KanbanBoardViewModel(
            tasks: [activeTask, queuedTask],
            agents: [],
            wipLimits: [.inProgress: 1]
        )

        viewModel.moveTask(activeTask.id, to: .review)
        let moved = viewModel.handleDrop(queuedTask.id, to: .inProgress)

        #expect(moved)
        #expect(viewModel.tasks.first(where: { $0.id == queuedTask.id })?.status == .inProgress)
    }

    @Test("auto assign in view model updates task owner")
    func viewModelAutoAssign() {
        let task = WorkTask(
            title: "Build drag and drop",
            details: "Kanban interaction",
            requiredSkills: ["swiftui"],
            storyPoints: 3,
            status: .todo,
            assignedAgentID: nil
        )
        let agent = AgentProfile(name: "UI Agent", skills: ["swiftui"], maxConcurrentTasks: 2)
        let viewModel = KanbanBoardViewModel(tasks: [task], agents: [agent])

        viewModel.autoAssignTasks()

        #expect(viewModel.tasks[0].assignedAgentID == agent.id)
        #expect(viewModel.assignmentReason(for: task.id) != nil)
    }

    @Test("single-task auto assign only mutates requested task")
    func autoAssignSingleTaskOnlyMutatesRequestedTask() {
        let requestedTask = WorkTask(
            title: "Requested Task",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 1,
            status: .todo,
            assignedAgentID: nil
        )
        let otherTask = WorkTask(
            title: "Other Task",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 3,
            status: .todo,
            assignedAgentID: nil
        )
        let agent = AgentProfile(name: "UI Agent", skills: ["swiftui"], maxConcurrentTasks: 3)
        let viewModel = KanbanBoardViewModel(tasks: [requestedTask, otherTask], agents: [agent])

        let assigned = viewModel.autoAssignTask(requestedTask.id)

        #expect(assigned)
        #expect(viewModel.tasks.first(where: { $0.id == requestedTask.id })?.assignedAgentID == agent.id)
        #expect(viewModel.tasks.first(where: { $0.id == otherTask.id })?.assignedAgentID == nil)
    }

    @Test("single-task auto assign rejects already assigned task")
    func autoAssignSingleTaskRejectsAlreadyAssignedTask() {
        let agent = AgentProfile(name: "UI Agent", skills: ["swiftui"], maxConcurrentTasks: 2)
        let task = WorkTask(
            title: "Already assigned",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 1,
            status: .todo,
            assignedAgentID: agent.id
        )
        let viewModel = KanbanBoardViewModel(tasks: [task], agents: [agent])

        let assigned = viewModel.autoAssignTask(task.id)

        #expect(!assigned)
        #expect(viewModel.lastBoardMessage == "Task already assigned")
    }

    @Test("single-task auto assign reports when no eligible agent exists")
    func autoAssignSingleTaskReportsWhenNoEligibleAgentExists() {
        let task = WorkTask(
            title: "No match task",
            details: "",
            requiredSkills: ["backend"],
            storyPoints: 2,
            status: .todo,
            assignedAgentID: nil
        )
        let agent = AgentProfile(name: "UI Agent", skills: ["swiftui"], maxConcurrentTasks: 2)
        let viewModel = KanbanBoardViewModel(tasks: [task], agents: [agent])

        let assigned = viewModel.autoAssignTask(task.id)

        #expect(!assigned)
        #expect(viewModel.lastBoardMessage == "No eligible agent for task")
        #expect(viewModel.tasks.first?.assignedAgentID == nil)
    }

    @Test("single-task auto assign rejects non-To-Do task")
    func autoAssignSingleTaskRejectsNonTodoTask() {
        let task = WorkTask(
            title: "Already in progress",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 2,
            status: .inProgress,
            assignedAgentID: nil
        )
        let agent = AgentProfile(name: "UI Agent", skills: ["swiftui"], maxConcurrentTasks: 2)
        let viewModel = KanbanBoardViewModel(tasks: [task], agents: [agent])

        let assigned = viewModel.autoAssignTask(task.id)

        #expect(!assigned)
        #expect(viewModel.lastBoardMessage == "Only To Do tasks can be auto-assigned")
        #expect(viewModel.lastBoardMessageSeverity == .warning)
    }

    @Test("single-task auto assign returns false when task id is unknown")
    func autoAssignSingleTaskRejectsUnknownTaskID() {
        let task = WorkTask(
            title: "Known task",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 1,
            status: .todo,
            assignedAgentID: nil
        )
        let agent = AgentProfile(name: "UI Agent", skills: ["swiftui"], maxConcurrentTasks: 2)
        let viewModel = KanbanBoardViewModel(tasks: [task], agents: [agent])

        let assigned = viewModel.autoAssignTask(UUID())

        #expect(!assigned)
        #expect(viewModel.tasks.first?.assignedAgentID == nil)
    }

    @Test("filters tasks by search query across title details skills and assignee name")
    func filtersTasksBySearchQuery() {
        let searchAgent = AgentProfile(name: "Search Agent", skills: ["swiftui"], maxConcurrentTasks: 2)
        let matchByTitle = WorkTask(
            title: "Implement search panel",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 2,
            status: .todo,
            assignedAgentID: nil
        )
        let matchByDetails = WorkTask(
            title: "Board metrics",
            details: "Need search query parser",
            requiredSkills: ["swift"],
            storyPoints: 2,
            status: .todo,
            assignedAgentID: nil
        )
        let matchBySkills = WorkTask(
            title: "Styling",
            details: "",
            requiredSkills: ["search"],
            storyPoints: 1,
            status: .todo,
            assignedAgentID: searchAgent.id
        )
        let nonMatch = WorkTask(
            title: "Notifications",
            details: "No filter keyword",
            requiredSkills: ["backend"],
            storyPoints: 1,
            status: .todo,
            assignedAgentID: nil
        )
        let matchByAssignee = WorkTask(
            title: "Polish transitions",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 1,
            status: .todo,
            assignedAgentID: searchAgent.id
        )
        let viewModel = KanbanBoardViewModel(
            tasks: [matchByTitle, matchByDetails, matchBySkills, matchByAssignee, nonMatch],
            agents: [searchAgent]
        )

        let filtered = viewModel.filteredTasks(in: .todo, query: "search", assigneeFilter: .all)

        #expect(filtered.count == 4)
        #expect(filtered.contains(where: { $0.id == matchByTitle.id }))
        #expect(filtered.contains(where: { $0.id == matchByDetails.id }))
        #expect(filtered.contains(where: { $0.id == matchBySkills.id }))
        #expect(filtered.contains(where: { $0.id == matchByAssignee.id }))
        #expect(!filtered.contains(where: { $0.id == nonMatch.id }))
    }

    @Test("filters tasks by assignee option")
    func filtersTasksByAssigneeOption() {
        let agent = AgentProfile(name: "UI Agent", skills: ["swiftui"], maxConcurrentTasks: 2)
        let assigned = WorkTask(
            title: "Assigned",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 2,
            status: .inProgress,
            assignedAgentID: agent.id
        )
        let unassigned = WorkTask(
            title: "Unassigned",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 1,
            status: .inProgress,
            assignedAgentID: nil
        )
        let viewModel = KanbanBoardViewModel(tasks: [assigned, unassigned], agents: [agent])

        let onlyAssigned = viewModel.filteredTasks(in: .inProgress, query: "", assigneeFilter: .assigned(agent.id))
        let onlyUnassigned = viewModel.filteredTasks(in: .inProgress, query: "", assigneeFilter: .unassigned)

        #expect(onlyAssigned.count == 1)
        #expect(onlyAssigned.first?.id == assigned.id)
        #expect(onlyUnassigned.count == 1)
        #expect(onlyUnassigned.first?.id == unassigned.id)
    }

    @Test("matches multi-word search query across mixed fields")
    func matchesMultiWordSearchAcrossMixedFields() {
        let agent = AgentProfile(name: "Panel Crew", skills: ["ux"], maxConcurrentTasks: 2)
        let crossFieldMatch = WorkTask(
            title: "Polish panel layout",
            details: "Add better search parser",
            requiredSkills: ["swiftui"],
            storyPoints: 2,
            status: .todo,
            assignedAgentID: nil
        )
        let assigneeMatch = WorkTask(
            title: "Accessibility fixes",
            details: "Improve search support",
            requiredSkills: ["swiftui"],
            storyPoints: 1,
            status: .todo,
            assignedAgentID: agent.id
        )
        let partialMatch = WorkTask(
            title: "Search only",
            details: "No layout term here",
            requiredSkills: ["swiftui"],
            storyPoints: 1,
            status: .todo,
            assignedAgentID: nil
        )
        let viewModel = KanbanBoardViewModel(
            tasks: [crossFieldMatch, assigneeMatch, partialMatch],
            agents: [agent]
        )

        let filtered = viewModel.filteredTasks(in: .todo, query: "search panel", assigneeFilter: .all)

        #expect(filtered.count == 2)
        #expect(filtered.contains(where: { $0.id == crossFieldMatch.id }))
        #expect(filtered.contains(where: { $0.id == assigneeMatch.id }))
        #expect(!filtered.contains(where: { $0.id == partialMatch.id }))
    }

    @Test("computes agent load ratio and overload state")
    func computesAgentLoadMetrics() {
        let agent = AgentProfile(name: "UI Agent", skills: ["swiftui"], maxConcurrentTasks: 2)
        let taskA = WorkTask(
            title: "Task A",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 2,
            status: .inProgress,
            assignedAgentID: agent.id
        )
        let taskB = WorkTask(
            title: "Task B",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 1,
            status: .todo,
            assignedAgentID: agent.id
        )
        let taskC = WorkTask(
            title: "Task C",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 1,
            status: .review,
            assignedAgentID: agent.id
        )
        let viewModel = KanbanBoardViewModel(tasks: [taskA, taskB, taskC], agents: [agent])

        let ratio = viewModel.loadRatio(for: agent.id)
        let percent = viewModel.loadPercent(for: agent.id)
        let overloaded = viewModel.isAgentOverloaded(agent.id)

        #expect(ratio > 1.0)
        #expect(percent == 150)
        #expect(overloaded)
    }

    @Test("reports rebalance availability when overloaded todo can move")
    func canRebalanceWhenOverloadedTodoHasEligibleTarget() {
        let overloaded = AgentProfile(name: "A Agent", skills: ["swiftui"], maxConcurrentTasks: 1)
        let target = AgentProfile(name: "B Agent", skills: ["swiftui"], maxConcurrentTasks: 2)
        let taskA = WorkTask(
            title: "Task A",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 2,
            status: .todo,
            assignedAgentID: overloaded.id
        )
        let taskB = WorkTask(
            title: "Task B",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 1,
            status: .todo,
            assignedAgentID: overloaded.id
        )
        let viewModel = KanbanBoardViewModel(tasks: [taskA, taskB], agents: [overloaded, target])

        #expect(viewModel.canRebalanceTodoAssignments())
    }

    @Test("reports no rebalance availability when overloaded work is not todo")
    func cannotRebalanceWhenOnlyInProgressIsOverloaded() {
        let overloaded = AgentProfile(name: "A Agent", skills: ["swiftui"], maxConcurrentTasks: 1)
        let target = AgentProfile(name: "B Agent", skills: ["swiftui"], maxConcurrentTasks: 2)
        let taskA = WorkTask(
            title: "Task A",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 2,
            status: .inProgress,
            assignedAgentID: overloaded.id
        )
        let taskB = WorkTask(
            title: "Task B",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 1,
            status: .inProgress,
            assignedAgentID: overloaded.id
        )
        let viewModel = KanbanBoardViewModel(tasks: [taskA, taskB], agents: [overloaded, target])

        #expect(!viewModel.canRebalanceTodoAssignments())
    }

    @Test("computes board health counters")
    func computesBoardHealthCounters() {
        let overloaded = AgentProfile(name: "A Agent", skills: ["swiftui"], maxConcurrentTasks: 1)
        let healthy = AgentProfile(name: "B Agent", skills: ["swiftui"], maxConcurrentTasks: 3)
        let todoAssigned = WorkTask(
            title: "Todo Assigned",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 1,
            status: .todo,
            assignedAgentID: overloaded.id
        )
        let todoUnassigned = WorkTask(
            title: "Todo Unassigned",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 1,
            status: .todo,
            assignedAgentID: nil
        )
        let inProgress = WorkTask(
            title: "In Progress",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 2,
            status: .inProgress,
            assignedAgentID: overloaded.id
        )
        let done = WorkTask(
            title: "Done",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 3,
            status: .done,
            assignedAgentID: healthy.id
        )
        let viewModel = KanbanBoardViewModel(tasks: [todoAssigned, todoUnassigned, inProgress, done], agents: [overloaded, healthy])

        #expect(viewModel.totalTaskCount == 4)
        #expect(viewModel.todoTaskCount == 2)
        #expect(viewModel.unassignedTodoTaskCount == 1)
        #expect(viewModel.overloadedAgentCount == 1)
    }

    @Test("pm planner generates a multi-step plan with normalized story points")
    func pmPlannerGeneratesMultiStepPlan() {
        let planner = RuleBasedProjectPlanner()
        let agent = AgentProfile(name: "Builder", skills: ["swiftui", "testing", "documentation"], maxConcurrentTasks: 3)

        let plan = planner.generatePlan(
            projectName: "OpenMac Assistant",
            projectBrief: "Build a macOS AI assistant app with kanban workflow, testing, and release checklist.",
            availableAgents: [agent]
        )

        #expect(plan != nil)
        #expect((plan?.tickets.count ?? 0) >= 5)
        #expect(!(plan?.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true))

        let storyPoints = plan?.tickets.map(\.storyPoints) ?? []
        #expect(storyPoints.allSatisfy { $0 >= 1 })
        let milestones = Set(plan?.tickets.map(\.milestone).filter { !$0.isEmpty } ?? [])
        let epics = Set(plan?.tickets.map(\.epic).filter { !$0.isEmpty } ?? [])
        #expect(!milestones.isEmpty)
        #expect(!epics.isEmpty)
    }

    @Test("pm planner injects dependency hints for sequential execution flow")
    func pmPlannerInjectsDependencyHints() {
        let planner = RuleBasedProjectPlanner()
        let agent = AgentProfile(name: "Builder", skills: ["swiftui", "backend", "testing"], maxConcurrentTasks: 3)

        guard let plan = planner.generatePlan(
            projectName: "OpenMac Assistant",
            projectBrief: "Build AI kanban assistant with testing and release flow.",
            availableAgents: [agent]
        ) else {
            Issue.record("Expected planner to return a plan")
            return
        }

        #expect(plan.tickets.count >= 5)
        #expect(plan.tickets[0].details.contains("Depends on: none"))
        #expect(plan.tickets[1].details.contains("Depends on:"))
        #expect(plan.tickets[2].details.contains("Depends on:"))
    }

    @Test("pm planner preview requires non-empty project brief")
    func pmPlannerPreviewRequiresBrief() {
        let viewModel = KanbanBoardViewModel(tasks: [], agents: [])
        let plan = viewModel.previewProjectPlan(projectName: "Any", projectBrief: "   ")

        #expect(plan == nil)
        #expect(viewModel.lastBoardMessage == "Project brief is required")
        #expect(viewModel.lastBoardMessageSeverity == .warning)
    }

    @Test("pm planner creates tickets and auto-assigns eligible work")
    func pmPlannerCreatesTicketsAndAutoAssigns() {
        let implementationAgent = AgentProfile(name: "Implementation", skills: ["swiftui", "backend", "testing"], maxConcurrentTasks: 8)
        let viewModel = KanbanBoardViewModel(tasks: [], agents: [implementationAgent])
        let planner = RuleBasedProjectPlanner()

        guard let plan = planner.generatePlan(
            projectName: "Automation Board",
            projectBrief: "Create a kanban automation project with backend APIs and test coverage.",
            availableAgents: [implementationAgent]
        ) else {
            Issue.record("Expected planner to return a plan")
            return
        }

        let createdCount = viewModel.addPlannedTickets(plan.tickets, autoAssign: true)

        #expect(createdCount == plan.tickets.count)
        #expect(viewModel.tasks.count == plan.tickets.count)
        #expect(viewModel.tasks.allSatisfy { $0.status == .todo })
        #expect(viewModel.tasks.contains { $0.assignedAgentID == implementationAgent.id })
        #expect(viewModel.lastBoardMessage == "PM planner created \(plan.tickets.count) ticket(s)")
        #expect(viewModel.lastBoardMessageSeverity == .info)
    }

    @Test("planned ticket creation preserves milestone and epic metadata in task details")
    func pmPlannerPlannedTicketDetailsIncludeRoadmapMetadata() {
        let viewModel = KanbanBoardViewModel(tasks: [], agents: [])
        let plannedTickets = [
            PMPlannedTicket(
                title: "Foundation",
                details: "Initial scope alignment.",
                requiredSkills: ["planning"],
                storyPoints: 2,
                epic: "Planning",
                milestone: "M1 Scope Locked"
            )
        ]

        let createdCount = viewModel.addPlannedTickets(plannedTickets, autoAssign: false)

        #expect(createdCount == 1)
        #expect(viewModel.tasks.count == 1)
        #expect(viewModel.tasks[0].details.contains("Milestone: M1 Scope Locked"))
        #expect(viewModel.tasks[0].details.contains("Epic: Planning"))
        #expect(viewModel.tasks[0].details.contains("Initial scope alignment."))
    }

    @Test("pm planner bootstrap creates agents for missing required skills")
    func pmPlannerBootstrapCreatesMissingSkillAgents() {
        let existingAgent = AgentProfile(name: "Existing UI", skills: ["swiftui"], maxConcurrentTasks: 3)
        let viewModel = KanbanBoardViewModel(tasks: [], agents: [existingAgent])
        let plannedTickets = [
            PMPlannedTicket(
                title: "API",
                details: "Build service layer",
                requiredSkills: ["backend", "api", "swiftui"],
                storyPoints: 5
            ),
            PMPlannedTicket(
                title: "Quality",
                details: "Add quality suite",
                requiredSkills: ["qa", "testing", "security"],
                storyPoints: 3
            )
        ]

        let createdCount = viewModel.createMissingAgentsForPlannedTickets(plannedTickets)
        let createdAgents = viewModel.agents.filter { $0.id != existingAgent.id }
        let createdSkills = Set(createdAgents.flatMap(\.skills))

        #expect(createdCount == 2)
        #expect(viewModel.agents.count == 3)
        #expect(createdSkills.contains("backend"))
        #expect(createdSkills.contains("api"))
        #expect(createdSkills.contains("qa"))
        #expect(createdSkills.contains("testing"))
        #expect(createdSkills.contains("security"))
        #expect(viewModel.lastBoardMessage == "Created 2 PM bootstrap agent(s) for missing skills")
        #expect(viewModel.lastBoardMessageSeverity == .info)
    }

    @Test("pm planner bootstrap skips when all required skills are already covered")
    func pmPlannerBootstrapSkipsWhenSkillsCovered() {
        let fullStack = AgentProfile(
            name: "Fullstack",
            skills: ["swiftui", "backend", "qa"],
            maxConcurrentTasks: 3
        )
        let viewModel = KanbanBoardViewModel(tasks: [], agents: [fullStack])
        let plannedTickets = [
            PMPlannedTicket(
                title: "UI",
                details: "Build interface",
                requiredSkills: ["swiftui"],
                storyPoints: 2
            ),
            PMPlannedTicket(
                title: "API",
                details: "Build backend",
                requiredSkills: ["backend", "qa"],
                storyPoints: 3
            )
        ]

        let createdCount = viewModel.createMissingAgentsForPlannedTickets(plannedTickets)

        #expect(createdCount == 0)
        #expect(viewModel.agents.count == 1)
        #expect(viewModel.lastBoardMessage == "All required PM skills are already covered by existing agents")
        #expect(viewModel.lastBoardMessageSeverity == .info)
    }

    @Test("pm planner bootstrap warns when planned tickets have no required skills")
    func pmPlannerBootstrapWarnsWhenNoSkillsFound() {
        let viewModel = KanbanBoardViewModel(tasks: [], agents: [])
        let plannedTickets = [
            PMPlannedTicket(
                title: "General Task",
                details: "No skills",
                requiredSkills: [],
                storyPoints: 1
            )
        ]

        let createdCount = viewModel.createMissingAgentsForPlannedTickets(plannedTickets)

        #expect(createdCount == 0)
        #expect(viewModel.lastBoardMessage == "No required skills found in PM tickets")
        #expect(viewModel.lastBoardMessageSeverity == .warning)
    }

    @Test("reports perfect health score for stable board")
    func reportsPerfectHealthScoreForStableBoard() {
        let agent = AgentProfile(name: "UI Agent", skills: ["swiftui"], maxConcurrentTasks: 3)
        let todoAssigned = WorkTask(
            title: "Todo Assigned",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 1,
            status: .todo,
            assignedAgentID: agent.id
        )
        let inProgress = WorkTask(
            title: "In Progress",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 2,
            status: .inProgress,
            assignedAgentID: agent.id
        )
        let viewModel = KanbanBoardViewModel(
            tasks: [todoAssigned, inProgress],
            agents: [agent],
            wipLimits: [.inProgress: 4, .review: 2]
        )

        #expect(viewModel.boardHealthScore == 100)
        #expect(viewModel.boardHealthLabel == "Excellent")
        #expect(viewModel.boardHealthBreakdownText == "No active penalties")
    }

    @Test("reduces health score for unassigned work overload and WIP pressure")
    func reducesHealthScoreForBoardRisks() {
        let overloaded = AgentProfile(name: "A Agent", skills: ["swiftui"], maxConcurrentTasks: 1)
        let healthy = AgentProfile(name: "B Agent", skills: ["swiftui"], maxConcurrentTasks: 3)
        let todoAssignedA = WorkTask(
            title: "Todo A",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 1,
            status: .todo,
            assignedAgentID: overloaded.id
        )
        let todoAssignedB = WorkTask(
            title: "Todo B",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 1,
            status: .todo,
            assignedAgentID: overloaded.id
        )
        let todoUnassigned = WorkTask(
            title: "Todo C",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 1,
            status: .todo,
            assignedAgentID: nil
        )
        let inProgress = WorkTask(
            title: "In Progress",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 1,
            status: .inProgress,
            assignedAgentID: overloaded.id
        )
        let review = WorkTask(
            title: "Review",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 1,
            status: .review,
            assignedAgentID: healthy.id
        )
        let done = WorkTask(
            title: "Done",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 1,
            status: .done,
            assignedAgentID: nil
        )
        let viewModel = KanbanBoardViewModel(
            tasks: [todoAssignedA, todoAssignedB, todoUnassigned, inProgress, review, done],
            agents: [overloaded, healthy],
            wipLimits: [.inProgress: 1, .review: 1]
        )

        #expect(viewModel.boardHealthScore == 55)
        #expect(viewModel.boardHealthLabel == "Critical")
        #expect(viewModel.boardHealthBreakdownText.contains("Unassigned To Do: -10"))
        #expect(viewModel.boardHealthBreakdownText.contains("Overloaded Agents: -10"))
        #expect(viewModel.boardHealthBreakdownText.contains("In Progress WIP Pressure: -10"))
        #expect(viewModel.boardHealthBreakdownText.contains("Review WIP Pressure: -10"))
        #expect(viewModel.boardHealthBreakdownText.contains("Done Backlog: -5"))
        #expect(viewModel.boardHealthBreakdownText.contains("Total Penalty: -45"))
        #expect(viewModel.boardHealthBreakdownText.contains("Health Score: 55"))
    }

    @Test("maps medium health scores to watch label")
    func mapsMediumHealthScoresToWatchLabel() {
        let agent = AgentProfile(name: "UI Agent", skills: ["swiftui"], maxConcurrentTasks: 2)
        let todoAssigned = WorkTask(
            title: "Todo",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 1,
            status: .todo,
            assignedAgentID: agent.id
        )
        let done = WorkTask(
            title: "Done",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 1,
            status: .done,
            assignedAgentID: nil
        )
        let viewModel = KanbanBoardViewModel(
            tasks: [todoAssigned, done],
            agents: [agent],
            wipLimits: [.inProgress: 3, .review: 2]
        )

        #expect(viewModel.boardHealthScore == 95)
        #expect(viewModel.boardHealthLabel == "Excellent")

        _ = viewModel.addTask(
            title: "Unassigned",
            details: "",
            requiredSkillsText: "swiftui",
            storyPoints: 1
        )

        #expect(viewModel.boardHealthScore == 85)
        #expect(viewModel.boardHealthLabel == "Excellent")

        _ = viewModel.addTask(
            title: "Unassigned 2",
            details: "",
            requiredSkillsText: "swiftui",
            storyPoints: 1
        )

        #expect(viewModel.boardHealthScore == 75)
        #expect(viewModel.boardHealthLabel == "Watch")
    }

    @Test("computes wip pressure ratio against configured limits")
    func computesWIPPressureRatio() {
        let inProgressA = WorkTask(
            title: "A",
            details: "",
            requiredSkills: [],
            storyPoints: 1,
            status: .inProgress,
            assignedAgentID: nil
        )
        let inProgressB = WorkTask(
            title: "B",
            details: "",
            requiredSkills: [],
            storyPoints: 1,
            status: .inProgress,
            assignedAgentID: nil
        )
        let review = WorkTask(
            title: "Review",
            details: "",
            requiredSkills: [],
            storyPoints: 1,
            status: .review,
            assignedAgentID: nil
        )
        let viewModel = KanbanBoardViewModel(
            tasks: [inProgressA, inProgressB, review],
            agents: [],
            wipLimits: [.inProgress: 4, .review: 2]
        )

        #expect(viewModel.wipPressurePercent(for: .inProgress) == 50)
        #expect(viewModel.wipPressurePercent(for: .review) == 50)
    }

    @Test("builds actionable health recommendations from board state")
    func buildsActionableHealthRecommendations() {
        let overloaded = AgentProfile(name: "A Agent", skills: ["swiftui"], maxConcurrentTasks: 1)
        let available = AgentProfile(name: "B Agent", skills: ["swiftui"], maxConcurrentTasks: 3)
        let todoAssignedA = WorkTask(
            title: "Todo A",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 2,
            status: .todo,
            assignedAgentID: overloaded.id
        )
        let todoAssignedB = WorkTask(
            title: "Todo B",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 1,
            status: .todo,
            assignedAgentID: overloaded.id
        )
        let todoUnassigned = WorkTask(
            title: "Todo Unassigned",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 1,
            status: .todo,
            assignedAgentID: nil
        )
        let inProgress = WorkTask(
            title: "In Progress",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 3,
            status: .inProgress,
            assignedAgentID: overloaded.id
        )
        let done = WorkTask(
            title: "Done",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 1,
            status: .done,
            assignedAgentID: nil
        )
        let viewModel = KanbanBoardViewModel(
            tasks: [todoAssignedA, todoAssignedB, todoUnassigned, inProgress, done],
            agents: [overloaded, available],
            wipLimits: [.inProgress: 1, .review: 2]
        )

        let actions = viewModel.healthRecommendations().map(\.action)

        #expect(actions.contains(.autoAssignUnassignedTodo))
        #expect(actions.contains(.rebalanceTodoLoad))
        #expect(actions.contains(.increaseWIPLimit(.inProgress)))
        #expect(actions.contains(.archiveDone))
    }

    @Test("applies increase WIP health recommendation")
    func appliesIncreaseWIPHealthRecommendation() {
        let reviewTask = WorkTask(
            title: "Review",
            details: "",
            requiredSkills: ["testing"],
            storyPoints: 2,
            status: .review,
            assignedAgentID: nil
        )
        let viewModel = KanbanBoardViewModel(
            tasks: [reviewTask],
            agents: [],
            wipLimits: [.review: 1]
        )

        let applied = viewModel.applyHealthRecommendation(.increaseWIPLimit(.review))

        #expect(applied)
        #expect(viewModel.wipLimit(for: .review) == 2)
    }

    @Test("increase WIP recommendation fails when status has no configured WIP limit")
    func increaseWIPRecommendationFailsWithoutConfiguredLimit() {
        let viewModel = KanbanBoardViewModel(tasks: [], agents: [])

        let applied = viewModel.applyHealthRecommendation(.increaseWIPLimit(.todo))

        #expect(!applied)
        #expect(viewModel.lastBoardMessage == "To Do has no configured WIP limit")
    }

    @Test("open manual triage recommendation returns false when no triage candidates")
    func openManualTriageRecommendationReturnsFalseWhenNoCandidates() {
        let task = WorkTask(
            title: "Already assigned",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 1,
            status: .todo,
            assignedAgentID: UUID()
        )
        let viewModel = KanbanBoardViewModel(tasks: [task], agents: [])

        let applied = viewModel.applyHealthRecommendation(.openManualTriage)

        #expect(!applied)
    }

    @Test("open new agent recommendation returns false when agents already exist")
    func openNewAgentRecommendationReturnsFalseWhenAgentsExist() {
        let agent = AgentProfile(name: "Existing Agent", skills: ["swiftui"], maxConcurrentTasks: 2)
        let viewModel = KanbanBoardViewModel(tasks: [], agents: [agent])

        let applied = viewModel.applyHealthRecommendation(.openNewAgent)

        #expect(!applied)
    }

    @Test("archive done recommendation returns false when there are no done tasks")
    func archiveDoneRecommendationReturnsFalseWhenNoDoneTasks() {
        let task = WorkTask(
            title: "Todo task",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 1,
            status: .todo,
            assignedAgentID: nil
        )
        let viewModel = KanbanBoardViewModel(tasks: [task], agents: [])

        let applied = viewModel.applyHealthRecommendation(.archiveDone)

        #expect(!applied)
    }

    @Test("create-missing-dependency recommendation generates placeholder tasks")
    func applyCreateMissingDependencyTasksRecommendationCreatesTasks() {
        let agent = AgentProfile(name: "Executor", skills: ["swiftui"], maxConcurrentTasks: 3)
        let blocked = WorkTask(
            title: "Implementation",
            details: """
            Depends on: External API Contract
            Build feature code.
            """,
            requiredSkills: ["swiftui"],
            storyPoints: 3,
            status: .todo,
            assignedAgentID: agent.id
        )
        let viewModel = KanbanBoardViewModel(
            tasks: [blocked],
            agents: [agent],
            wipLimits: [.inProgress: 3, .review: 2]
        )

        let applied = viewModel.applyHealthRecommendation(.createMissingDependencyTasks)

        #expect(applied)
        #expect(viewModel.tasks.contains(where: { $0.title == "External API Contract" }))
        let generatedTask = viewModel.tasks.first(where: { $0.title == "External API Contract" })
        #expect(generatedTask?.requiredSkills == Set(["swiftui"]))
        #expect(generatedTask?.details.contains("Referenced by tasks: Implementation") == true)
        #expect(generatedTask?.details.contains("Inferred required skills: swiftui") == true)
        #expect(viewModel.lastBoardMessage == "Created 1 dependency placeholder task(s)")
        #expect(viewModel.lastBoardMessageSeverity == .info)
    }

    @Test("create-missing-dependency placeholder merges skills and context from dependent tasks")
    func createMissingDependencyTasksMergesSkillsAndContextFromDependentTasks() {
        let agent = AgentProfile(name: "Executor", skills: ["swiftui", "ux", "backend"], maxConcurrentTasks: 3)
        let blockedUI = WorkTask(
            title: "Mobile UI",
            details: """
            Depends on: Auth Service
            Build onboarding views.
            """,
            requiredSkills: ["swiftui", "ux"],
            storyPoints: 3,
            status: .todo,
            assignedAgentID: agent.id
        )
        let blockedAPI = WorkTask(
            title: "Session APIs",
            details: """
            Dependencies: Auth Service
            Expose login endpoints.
            """,
            requiredSkills: ["backend", "swiftui"],
            storyPoints: 2,
            status: .inProgress,
            assignedAgentID: agent.id
        )
        let viewModel = KanbanBoardViewModel(
            tasks: [blockedUI, blockedAPI],
            agents: [agent],
            wipLimits: [.inProgress: 3, .review: 2]
        )

        let createdCount = viewModel.createMissingDependencyTasks(storyPoints: 2)

        #expect(createdCount == 1)
        let generatedTask = viewModel.tasks.first(where: { $0.title == "Auth Service" })
        #expect(generatedTask?.storyPoints == 2)
        #expect(generatedTask?.requiredSkills == Set(["backend", "swiftui", "ux"]))
        #expect(generatedTask?.details.contains("Referenced by tasks: Mobile UI, Session APIs") == true)
        #expect(generatedTask?.details.contains("Inferred required skills: backend, swiftui, ux") == true)
    }

    @Test("health recommendations include review WIP increase when review reaches limit")
    func includesReviewWIPIncreaseRecommendationWhenReviewAtLimit() {
        let reviewTask = WorkTask(
            title: "Review task",
            details: "",
            requiredSkills: ["testing"],
            storyPoints: 1,
            status: .review,
            assignedAgentID: nil
        )
        let viewModel = KanbanBoardViewModel(
            tasks: [reviewTask],
            agents: [],
            wipLimits: [.inProgress: 3, .review: 1]
        )

        let actions = viewModel.healthRecommendations().map(\.action)

        #expect(actions.contains(.increaseWIPLimit(.review)))
    }

    @Test("includes create-missing-dependency-tasks recommendation when blockers reference unknown tickets")
    func includesCreateMissingDependencyTasksRecommendation() {
        let agent = AgentProfile(name: "Executor", skills: ["swiftui"], maxConcurrentTasks: 3)
        let blocked = WorkTask(
            title: "Implementation",
            details: """
            Depends on: External API Contract
            Build feature code.
            """,
            requiredSkills: ["swiftui"],
            storyPoints: 3,
            status: .todo,
            assignedAgentID: agent.id
        )
        let viewModel = KanbanBoardViewModel(
            tasks: [blocked],
            agents: [agent],
            wipLimits: [.inProgress: 3, .review: 2]
        )

        let recommendations = viewModel.healthRecommendations()
        let actions = recommendations.map(\.action)
        let missingDependencyRecommendation = recommendations.first(where: { $0.id == "create-missing-dependency-tasks" })

        #expect(actions.contains(.createMissingDependencyTasks))
        #expect(missingDependencyRecommendation?.title == "Create Missing Dependency Tasks")
        #expect(missingDependencyRecommendation?.detail.contains("1 missing dependency task(s)") == true)
    }

    @Test("includes manual triage recommendation when unassigned todo exists")
    func includesManualTriageRecommendation() {
        let task = WorkTask(
            title: "Needs assignment",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 2,
            status: .todo,
            assignedAgentID: nil
        )
        let agent = AgentProfile(name: "UI Agent", skills: ["swiftui"], maxConcurrentTasks: 2)
        let viewModel = KanbanBoardViewModel(tasks: [task], agents: [agent])

        let actions = viewModel.healthRecommendations().map(\.action)

        #expect(actions.contains(.openManualTriage))
    }

    @Test("includes add agent recommendation when unassigned todo exists and no agents are available")
    func includesAddAgentRecommendationWhenNoAgents() {
        let task = WorkTask(
            title: "Needs assignment",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 2,
            status: .todo,
            assignedAgentID: nil
        )
        let viewModel = KanbanBoardViewModel(tasks: [task], agents: [])

        let actions = viewModel.healthRecommendations().map(\.action)

        #expect(actions.contains(.openNewAgent))
        #expect(!actions.contains(.openManualTriage))
        #expect(!actions.contains(.autoAssignUnassignedTodo))
    }

    @Test("flags pending manual triage when unassigned todo exists and agents are available")
    func flagsPendingManualTriageWhenAgentsExist() {
        let task = WorkTask(
            title: "Needs assignment",
            details: "",
            requiredSkills: ["ml"],
            storyPoints: 2,
            status: .todo,
            assignedAgentID: nil
        )
        let agent = AgentProfile(name: "UI Agent", skills: ["swiftui"], maxConcurrentTasks: 2)
        let viewModel = KanbanBoardViewModel(tasks: [task], agents: [agent])

        viewModel.autoAssignTasks()

        #expect(viewModel.hasPendingManualTriage)
    }

    @Test("does not flag manual triage when no agents exist")
    func doesNotFlagManualTriageWhenNoAgentsExist() {
        let task = WorkTask(
            title: "Needs assignment",
            details: "",
            requiredSkills: ["ml"],
            storyPoints: 2,
            status: .todo,
            assignedAgentID: nil
        )
        let viewModel = KanbanBoardViewModel(tasks: [task], agents: [])

        #expect(!viewModel.hasPendingManualTriage)
    }

    @Test("counts auto-fixable health recommendations")
    func countsAutoFixableHealthRecommendations() {
        let overloaded = AgentProfile(name: "A Agent", skills: ["swiftui"], maxConcurrentTasks: 1)
        let available = AgentProfile(name: "B Agent", skills: ["swiftui"], maxConcurrentTasks: 3)
        let todoAssignedA = WorkTask(
            title: "Todo A",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 2,
            status: .todo,
            assignedAgentID: overloaded.id
        )
        let todoAssignedB = WorkTask(
            title: "Todo B",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 1,
            status: .todo,
            assignedAgentID: overloaded.id
        )
        let todoUnassigned = WorkTask(
            title: "Todo C",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 1,
            status: .todo,
            assignedAgentID: nil
        )
        let inProgress = WorkTask(
            title: "In Progress",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 3,
            status: .inProgress,
            assignedAgentID: overloaded.id
        )
        let done = WorkTask(
            title: "Done",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 1,
            status: .done,
            assignedAgentID: nil
        )
        let viewModel = KanbanBoardViewModel(
            tasks: [todoAssignedA, todoAssignedB, todoUnassigned, inProgress, done],
            agents: [overloaded, available],
            wipLimits: [.inProgress: 1, .review: 2]
        )

        #expect(viewModel.autoFixableHealthRecommendationCount == 4)
        #expect(viewModel.hasAutoFixableHealthRecommendations)
    }

    @Test("reports no auto-fixable health recommendations when only navigation actions exist")
    func reportsNoAutoFixableHealthRecommendationsForNavigationOnlyActions() {
        let task = WorkTask(
            title: "Needs assignment",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 2,
            status: .todo,
            assignedAgentID: nil
        )
        let viewModel = KanbanBoardViewModel(tasks: [task], agents: [])

        #expect(viewModel.autoFixableHealthRecommendationCount == 0)
        #expect(!viewModel.hasAutoFixableHealthRecommendations)
    }

    @Test("applies all mutating health recommendations in one pass")
    func appliesAllMutatingHealthRecommendationsInOnePass() {
        let overloaded = AgentProfile(name: "A Agent", skills: ["swiftui"], maxConcurrentTasks: 1)
        let available = AgentProfile(name: "B Agent", skills: ["swiftui"], maxConcurrentTasks: 3)
        let todoAssignedA = WorkTask(
            title: "Todo A",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 2,
            status: .todo,
            assignedAgentID: overloaded.id
        )
        let todoAssignedB = WorkTask(
            title: "Todo B",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 1,
            status: .todo,
            assignedAgentID: overloaded.id
        )
        let todoUnassigned = WorkTask(
            title: "Todo C",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 1,
            status: .todo,
            assignedAgentID: nil
        )
        let inProgress = WorkTask(
            title: "In Progress",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 3,
            status: .inProgress,
            assignedAgentID: overloaded.id
        )
        let done = WorkTask(
            title: "Done",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 1,
            status: .done,
            assignedAgentID: nil
        )
        let viewModel = KanbanBoardViewModel(
            tasks: [todoAssignedA, todoAssignedB, todoUnassigned, inProgress, done],
            agents: [overloaded, available],
            wipLimits: [.inProgress: 1, .review: 2]
        )

        let appliedCount = viewModel.applyAllHealthRecommendations()

        #expect(appliedCount == 4)
        #expect(viewModel.doneTaskCount == 0)
        #expect(viewModel.wipLimit(for: .inProgress) == 2)
        #expect(viewModel.unassignedTodoTaskCount == 0)
        #expect(viewModel.activeTaskCount(for: overloaded.id) == 1)
        #expect(viewModel.healthRecommendations().isEmpty)
        #expect(viewModel.lastBoardMessage == "Applied 4 health recommendation(s)")
        #expect(viewModel.lastBoardMessageSeverity?.rawValue == "info")
    }

    @Test("reports when apply-all has no automatic fixes available")
    func reportsWhenApplyAllHasNoAutomaticFixes() {
        let task = WorkTask(
            title: "Needs assignment",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 2,
            status: .todo,
            assignedAgentID: nil
        )
        let viewModel = KanbanBoardViewModel(tasks: [task], agents: [])

        let appliedCount = viewModel.applyAllHealthRecommendations()

        #expect(appliedCount == 0)
        #expect(viewModel.lastBoardMessage == "No automatic fixes available for current recommendations")
        #expect(viewModel.lastBoardMessageSeverity?.rawValue == "warning")
    }

    @Test("reports info tone when board is already stable during apply-all")
    func applyAllReportsInfoWhenBoardAlreadyStable() {
        let agent = AgentProfile(name: "UI Agent", skills: ["swiftui"], maxConcurrentTasks: 2)
        let task = WorkTask(
            title: "Assigned task",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 2,
            status: .todo,
            assignedAgentID: agent.id
        )
        let viewModel = KanbanBoardViewModel(tasks: [task], agents: [agent])

        let appliedCount = viewModel.applyAllHealthRecommendations()

        #expect(appliedCount == 0)
        #expect(viewModel.lastBoardMessage == "Board health already stable")
        #expect(viewModel.lastBoardMessageSeverity?.rawValue == "info")
    }

    @Test("apply-all includes create-missing-dependency auto-fix")
    func applyAllIncludesCreateMissingDependencyTasksRecommendation() {
        let agent = AgentProfile(name: "Executor", skills: ["swiftui"], maxConcurrentTasks: 2)
        let blocked = WorkTask(
            title: "Implementation",
            details: """
            Depends on: External API Contract
            Build feature code.
            """,
            requiredSkills: ["swiftui"],
            storyPoints: 3,
            status: .todo,
            assignedAgentID: agent.id
        )
        let viewModel = KanbanBoardViewModel(
            tasks: [blocked],
            agents: [agent],
            wipLimits: [.inProgress: 3, .review: 2]
        )

        let appliedCount = viewModel.applyAllHealthRecommendations()

        #expect(appliedCount == 2)
        let generatedTask = viewModel.tasks.first(where: { $0.title == "External API Contract" })
        #expect(generatedTask != nil)
        #expect(generatedTask?.assignedAgentID == agent.id)
        #expect(viewModel.lastBoardMessage == "Applied 2 health recommendation(s)")
        #expect(viewModel.lastBoardMessageSeverity == .info)
    }

    @Test("returns no health recommendations when board is healthy")
    func returnsNoHealthRecommendationsWhenHealthy() {
        let agent = AgentProfile(name: "UI Agent", skills: ["swiftui"], maxConcurrentTasks: 3)
        let todoAssigned = WorkTask(
            title: "Todo Assigned",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 1,
            status: .todo,
            assignedAgentID: agent.id
        )
        let inProgress = WorkTask(
            title: "In Progress",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 2,
            status: .inProgress,
            assignedAgentID: agent.id
        )
        let viewModel = KanbanBoardViewModel(
            tasks: [todoAssigned, inProgress],
            agents: [agent],
            wipLimits: [.inProgress: 3, .review: 2]
        )

        #expect(viewModel.healthRecommendations().isEmpty)
    }
}

@MainActor
struct KanbanSupportTypeTests {
    @Test("board health recommendation id is stable for each action")
    func boardHealthRecommendationIDMapping() {
        #expect(
            BoardHealthRecommendation(action: .autoAssignUnassignedTodo, title: "", detail: "").id
                == "auto-assign-unassigned-todo"
        )
        #expect(
            BoardHealthRecommendation(action: .createMissingDependencyTasks, title: "", detail: "").id
                == "create-missing-dependency-tasks"
        )
        #expect(
            BoardHealthRecommendation(action: .openManualTriage, title: "", detail: "").id
                == "open-manual-triage"
        )
        #expect(
            BoardHealthRecommendation(action: .openNewAgent, title: "", detail: "").id
                == "open-new-agent"
        )
        #expect(
            BoardHealthRecommendation(action: .rebalanceTodoLoad, title: "", detail: "").id
                == "rebalance-todo-load"
        )
        #expect(
            BoardHealthRecommendation(action: .increaseWIPLimit(.review), title: "", detail: "").id
                == "increase-wip-Review"
        )
        #expect(
            BoardHealthRecommendation(action: .archiveDone, title: "", detail: "").id
                == "archive-done"
        )
    }

    @Test("global task search result id combines board and task identifiers")
    func globalTaskSearchResultID() {
        let boardID = UUID()
        let taskID = UUID()
        let result = GlobalTaskSearchResult(
            taskID: taskID,
            taskTitle: "Task",
            taskDetails: "Details",
            status: .todo,
            boardID: boardID,
            boardName: "Board",
            assigneeName: "None"
        )

        #expect(result.id == "\(boardID.uuidString)-\(taskID.uuidString)")
    }

    @Test("runtime provider and auth mode ids map to raw values")
    func runtimeProviderAndAuthModeIDs() {
        for provider in AgentRuntimeProvider.allCases {
            #expect(provider.id == provider.rawValue)
        }
        for authMode in OpenAICompatibleAuthMode.allCases {
            #expect(authMode.id == authMode.rawValue)
        }
    }

    @Test("agent runtime profile encodes and decodes all persisted fields")
    func agentRuntimeProfileCodableRoundTrip() throws {
        let profile = AgentRuntimeProfile(
            provider: .openAICompatible,
            model: "gpt-5-mini",
            endpoint: "https://api.openai.com/v1",
            tools: ["shell", "git"],
            openAIAuthMode: .codexBridge,
            codexProfile: "team-default"
        )

        let encoded = try JSONEncoder().encode(profile)
        let decoded = try JSONDecoder().decode(AgentRuntimeProfile.self, from: encoded)

        #expect(decoded.provider == .openAICompatible)
        #expect(decoded.model == "gpt-5-mini")
        #expect(decoded.endpoint == "https://api.openai.com/v1")
        #expect(decoded.tools == Set(["shell", "git"]))
        #expect(decoded.openAIAuthMode == .codexBridge)
        #expect(decoded.codexProfile == "team-default")
    }

    @Test("agent runtime profile decode defaults optional coding keys")
    func agentRuntimeProfileDecodeDefaultsMissingKeys() throws {
        let json = """
        {
          "provider": "openAICompatible",
          "model": "gpt-4.1-mini",
          "endpoint": "https://api.openai.com/v1"
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(AgentRuntimeProfile.self, from: json)

        #expect(decoded.provider == .openAICompatible)
        #expect(decoded.model == "gpt-4.1-mini")
        #expect(decoded.endpoint == "https://api.openai.com/v1")
        #expect(decoded.tools.isEmpty)
        #expect(decoded.openAIAuthMode == .apiKey)
        #expect(decoded.codexProfile == nil)
    }
}

@Suite(.serialized)
@MainActor
struct ContentViewLogicTests {

    @Test("normalizes execution summary headings across locales")
    func normalizedExecutionSummaryRemovesHeadingTokens() {
        #expect(ContentViewTestHooks.normalizedExecutionSummary("Summary: Done") == "Done")
        #expect(ContentViewTestHooks.normalizedExecutionSummary("摘要：完成") == "完成")
        #expect(
            ContentViewTestHooks.normalizedExecutionSummary(
                "Resumen:\nFinalizado"
            ) == "Finalizado"
        )
        #expect(ContentViewTestHooks.normalizedExecutionSummary("  Already clean  ") == "Already clean")
        #expect(ContentViewTestHooks.normalizedExecutionSummary("   ") == "   ")
    }

    @Test("execution details status label maps each execution status")
    func executionDetailsStatusLabelMapping() {
        #expect(ContentViewTestHooks.executionDetailsStatusLabel(for: .running) == "Running")
        #expect(ContentViewTestHooks.executionDetailsStatusLabel(for: .succeeded) == "Succeeded")
        #expect(ContentViewTestHooks.executionDetailsStatusLabel(for: .failed) == "Failed")
    }

    @Test("agent live console status label maps each execution status")
    func agentLiveConsoleStatusLabelMapping() {
        #expect(ContentViewTestHooks.agentLiveConsoleStatusLabel(for: .running) == "Running")
        #expect(ContentViewTestHooks.agentLiveConsoleStatusLabel(for: .succeeded) == "Succeeded")
        #expect(ContentViewTestHooks.agentLiveConsoleStatusLabel(for: .failed) == "Failed")
    }

    @Test("agent execution row status label maps each execution status")
    func agentExecutionRowStatusLabelMapping() {
        #expect(ContentViewTestHooks.agentExecutionEventRowStatusLabel(for: .running) == "Running")
        #expect(ContentViewTestHooks.agentExecutionEventRowStatusLabel(for: .succeeded) == "Succeeded")
        #expect(ContentViewTestHooks.agentExecutionEventRowStatusLabel(for: .failed) == "Failed")
    }

    @Test("agent execution row copy text includes optional details when present")
    func agentExecutionRowCopyTextIncludesDetailsConditionally() {
        let withDetails = ContentViewTestHooks.agentExecutionEventRowCopyText(
            status: .failed,
            message: "Command failed",
            details: "stderr details"
        )
        #expect(withDetails.contains("[Failed] Task"))
        #expect(withDetails.contains("Command failed"))
        #expect(withDetails.contains("stderr details"))

        let withoutDetails = ContentViewTestHooks.agentExecutionEventRowCopyText(
            status: .running,
            message: "Still running",
            details: nil
        )
        #expect(withoutDetails.contains("[Running] Task"))
        #expect(withoutDetails.contains("Still running"))
        #expect(!withoutDetails.contains("stderr details"))
    }

    @Test("agent live console copy text composes event message and details")
    func agentLiveConsoleAllEventsTextComposition() {
        let agentID = UUID()
        let eventA = AgentExecutionEvent(
            timestamp: Date(timeIntervalSince1970: 1_735_000_000),
            agentID: agentID,
            taskID: UUID(),
            taskTitle: "Task A",
            status: .succeeded,
            message: "Completed",
            details: "Summary line"
        )
        let eventB = AgentExecutionEvent(
            timestamp: Date(timeIntervalSince1970: 1_735_000_030),
            agentID: agentID,
            taskID: UUID(),
            taskTitle: "Task B",
            status: .failed,
            message: "Failed",
            details: nil
        )

        let text = ContentViewTestHooks.agentLiveConsoleAllEventsText([eventA, eventB])

        #expect(text.contains("[Succeeded]"))
        #expect(text.contains("[Failed]"))
        #expect(text.contains("Task A"))
        #expect(text.contains("Task B"))
        #expect(text.contains("Completed"))
        #expect(text.contains("Summary line"))
        #expect(text.contains("Failed"))
    }

    @Test("task card execution status labels map correctly")
    func taskCardExecutionStatusLabelMapping() {
        #expect(ContentViewTestHooks.taskCardExecutionStatusLabel(for: .running) == "Running")
        #expect(ContentViewTestHooks.taskCardExecutionStatusLabel(for: .succeeded) == "Succeeded")
        #expect(ContentViewTestHooks.taskCardExecutionStatusLabel(for: .failed) == "Failed")
    }

    @Test("execution status color helpers cover all task states")
    func executionStatusColorCoverage() {
        let exercisedCount = ContentViewTestHooks.exerciseStatusColorCoverage()
        #expect(exercisedCount >= 6)
    }

    @Test("palette token helpers cover both color schemes and enum variants")
    func paletteTokenCoverage() {
        let exercisedCount = ContentViewTestHooks.exercisePaletteTokenCoverage()
        #expect(exercisedCount >= 50)
    }

    @Test("board health score accent thresholds are stable")
    func boardHealthScoreAccentThresholds() {
        #expect(ContentViewTestHooks.healthScoreAccent(for: 90) == .green)
        #expect(ContentViewTestHooks.healthScoreAccent(for: 70) == .amber)
        #expect(ContentViewTestHooks.healthScoreAccent(for: 50) == .red)
    }

    @Test("board health recommendations count only auto-fixable actions")
    func boardHealthAutoFixRecommendationCount() {
        let recommendations = [
            BoardHealthRecommendation(action: .autoAssignUnassignedTodo, title: "", detail: ""),
            BoardHealthRecommendation(action: .openManualTriage, title: "", detail: ""),
            BoardHealthRecommendation(action: .increaseWIPLimit(.review), title: "", detail: ""),
            BoardHealthRecommendation(action: .archiveDone, title: "", detail: "")
        ]

        #expect(ContentViewTestHooks.autoFixRecommendationCount(for: recommendations) == 3)
    }

    @Test("runtime summary reflects runtime profile configuration")
    func runtimeSummaryReflectsProfile() {
        let disabled = ContentViewTestHooks.runtimeSummary(runtimeProfile: nil)
        #expect(disabled == L10n.string("Runtime: Disabled"))

        let local = AgentRuntimeProfile(provider: .localMock, model: "mock-v2")
        let localSummary = ContentViewTestHooks.runtimeSummary(runtimeProfile: local)
        #expect(localSummary.contains(local.provider.displayName))
        #expect(localSummary.contains("mock-v2"))
        #expect(!localSummary.contains(OpenAICompatibleAuthMode.apiKey.displayName))

        let codex = AgentRuntimeProfile(
            provider: .openAICompatible,
            model: "gpt-5",
            openAIAuthMode: .codexBridge
        )
        let codexSummary = ContentViewTestHooks.runtimeSummary(runtimeProfile: codex)
        #expect(codexSummary.contains(codex.provider.displayName))
        #expect(codexSummary.contains("gpt-5"))
        #expect(codexSummary.contains(OpenAICompatibleAuthMode.codexBridge.displayName))
    }

    @Test("build runtime profile normalizes endpoint, tools, and auth mode")
    func buildRuntimeProfileNormalization() {
        #expect(
            ContentViewTestHooks.buildRuntimeProfile(
                isEnabled: false,
                provider: .localMock,
                model: "",
                endpoint: "",
                toolsText: "",
                openAIAuthMode: .apiKey,
                codexProfile: ""
            ) == nil
        )

        let openAIAPIKey = ContentViewTestHooks.buildRuntimeProfile(
            isEnabled: true,
            provider: .openAICompatible,
            model: " ",
            endpoint: "https://api.example.com/v1",
            toolsText: " Git , shell,git ",
            openAIAuthMode: .apiKey,
            codexProfile: "ignored"
        )
        #expect(openAIAPIKey?.model == AgentRuntimeProvider.openAICompatible.defaultModel)
        #expect(openAIAPIKey?.endpoint == "https://api.example.com/v1")
        #expect(openAIAPIKey?.openAIAuthMode == .apiKey)
        #expect(openAIAPIKey?.codexProfile == nil)
        #expect(openAIAPIKey?.tools == Set(["git", "shell"]))

        let openAICodex = ContentViewTestHooks.buildRuntimeProfile(
            isEnabled: true,
            provider: .openAICompatible,
            model: "gpt-5-codex",
            endpoint: "https://should-be-ignored",
            toolsText: "",
            openAIAuthMode: .codexBridge,
            codexProfile: "team-profile"
        )
        #expect(openAICodex?.openAIAuthMode == .codexBridge)
        #expect(openAICodex?.endpoint == nil)
        #expect(openAICodex?.codexProfile == "team-profile")

        let localRuntime = ContentViewTestHooks.buildRuntimeProfile(
            isEnabled: true,
            provider: .localMock,
            model: "local-v2",
            endpoint: "https://ignored-for-local",
            toolsText: "",
            openAIAuthMode: .codexBridge,
            codexProfile: "ignored"
        )
        #expect(localRuntime?.provider == .localMock)
        #expect(localRuntime?.openAIAuthMode == .apiKey)
        #expect(localRuntime?.endpoint == nil)
        #expect(localRuntime?.codexProfile == nil)
    }

    @Test("assignee filter selection resolves to valid enum values")
    func assigneeFilterSelectionMapping() {
        let agent = AgentProfile(name: "A", skills: [], maxConcurrentTasks: 1)

        #expect(
            ContentViewTestHooks.selectedAssigneeFilter(selectedKey: "all", agents: [agent]) == .all
        )
        #expect(
            ContentViewTestHooks.selectedAssigneeFilter(selectedKey: "unassigned", agents: [agent]) == .unassigned
        )
        #expect(
            ContentViewTestHooks.selectedAssigneeFilter(selectedKey: agent.id.uuidString, agents: [agent])
                == .assigned(agent.id)
        )
        #expect(
            ContentViewTestHooks.selectedAssigneeFilter(selectedKey: UUID().uuidString, agents: [agent]) == .all
        )
        #expect(
            ContentViewTestHooks.selectedAssigneeFilter(selectedKey: "not-a-uuid", agents: [agent]) == .all
        )
    }

    @Test("selected agent console resolver prefers selected id and falls back safely")
    func selectedAgentForConsoleResolverCoverage() {
        let agentA = AgentProfile(name: "A", skills: [], maxConcurrentTasks: 1)
        let agentB = AgentProfile(name: "B", skills: [], maxConcurrentTasks: 1)

        #expect(
            ContentViewTestHooks.selectedAgentForConsoleID(selectedAgentID: nil, agents: [agentA, agentB]) == agentA.id
        )
        #expect(
            ContentViewTestHooks.selectedAgentForConsoleID(selectedAgentID: agentB.id, agents: [agentA, agentB]) == agentB.id
        )
        #expect(
            ContentViewTestHooks.selectedAgentForConsoleID(selectedAgentID: UUID(), agents: [agentA, agentB]) == agentA.id
        )
        #expect(
            ContentViewTestHooks.selectedAgentForConsoleID(selectedAgentID: agentA.id, agents: []) == nil
        )
    }

    @Test("console selection sync helper keeps valid id and repairs invalid or empty states")
    func syncedSelectedAgentConsoleAgentIDCoverage() {
        let agentA = AgentProfile(name: "A", skills: [], maxConcurrentTasks: 1)
        let agentB = AgentProfile(name: "B", skills: [], maxConcurrentTasks: 1)
        let agents = [agentA, agentB]

        #expect(
            ContentViewTestHooks.syncedSelectedAgentConsoleAgentID(currentID: nil, agents: agents) == agentA.id
        )
        #expect(
            ContentViewTestHooks.syncedSelectedAgentConsoleAgentID(currentID: agentB.id, agents: agents) == agentB.id
        )
        #expect(
            ContentViewTestHooks.syncedSelectedAgentConsoleAgentID(currentID: UUID(), agents: agents) == agentA.id
        )
        #expect(
            ContentViewTestHooks.syncedSelectedAgentConsoleAgentID(currentID: agentA.id, agents: []) == nil
        )
    }

    @Test("assignee filter key normalization keeps valid key and resets invalid key")
    func normalizedAssigneeFilterKeyCoverage() {
        let validKeys: Set<String> = ["all", "unassigned", "agent-id"]

        #expect(
            ContentViewTestHooks.normalizedAssigneeFilterKey(currentKey: "all", validKeys: validKeys) == "all"
        )
        #expect(
            ContentViewTestHooks.normalizedAssigneeFilterKey(currentKey: "agent-id", validKeys: validKeys) == "agent-id"
        )
        #expect(
            ContentViewTestHooks.normalizedAssigneeFilterKey(currentKey: "missing", validKeys: validKeys) == "all"
        )
    }

    @Test("toolbar auto-assign availability depends on unassigned todo tasks and agents")
    func canAutoAssignFromToolbarRequiresTasksAndAgents() {
        let agent = AgentProfile(name: "A", skills: ["swift"], maxConcurrentTasks: 1)
        let unassignedTodo = WorkTask(
            title: "Task",
            details: "Details",
            requiredSkills: [],
            storyPoints: 1,
            status: .todo,
            assignedAgentID: nil
        )
        let assignedTodo = WorkTask(
            title: "Assigned",
            details: "Details",
            requiredSkills: [],
            storyPoints: 1,
            status: .todo,
            assignedAgentID: agent.id
        )

        #expect(ContentViewTestHooks.canAutoAssignFromToolbar(tasks: [unassignedTodo], agents: [agent]))
        #expect(!ContentViewTestHooks.canAutoAssignFromToolbar(tasks: [unassignedTodo], agents: []))
        #expect(!ContentViewTestHooks.canAutoAssignFromToolbar(tasks: [assignedTodo], agents: [agent]))
    }

    @Test("batch run availability respects running-state and runnable-task rules")
    func canBatchRunAssignedTasksRules() {
        let agent = AgentProfile(name: "A", skills: ["swift"], maxConcurrentTasks: 1)

        let runnable = WorkTask(
            title: "Runnable",
            details: "Implement feature",
            requiredSkills: [],
            storyPoints: 1,
            status: .todo,
            assignedAgentID: agent.id
        )
        let emptyDetails = WorkTask(
            title: "Empty",
            details: "   ",
            requiredSkills: [],
            storyPoints: 1,
            status: .todo,
            assignedAgentID: agent.id
        )
        let unassigned = WorkTask(
            title: "Unassigned",
            details: "Has details",
            requiredSkills: [],
            storyPoints: 1,
            status: .todo,
            assignedAgentID: nil
        )
        let doneTask = WorkTask(
            title: "Done",
            details: "Has details",
            requiredSkills: [],
            storyPoints: 1,
            status: .done,
            assignedAgentID: agent.id
        )

        #expect(
            ContentViewTestHooks.canBatchRunAssignedTasks(
                tasks: [runnable],
                isBatchRunning: false,
                isAutoCycleRunning: false
            )
        )
        #expect(
            !ContentViewTestHooks.canBatchRunAssignedTasks(
                tasks: [runnable],
                isBatchRunning: true,
                isAutoCycleRunning: false
            )
        )
        #expect(
            !ContentViewTestHooks.canBatchRunAssignedTasks(
                tasks: [runnable],
                isBatchRunning: false,
                isAutoCycleRunning: true
            )
        )
        #expect(
            !ContentViewTestHooks.canBatchRunAssignedTasks(
                tasks: [emptyDetails, unassigned, doneTask],
                isBatchRunning: false,
                isAutoCycleRunning: false
            )
        )
    }

    @Test("auto cycle availability allows unassigned work and blocks concurrent runs")
    func canRunAutoCycleRules() {
        let agent = AgentProfile(name: "A", skills: ["swift"], maxConcurrentTasks: 1)

        let unassignedTodo = WorkTask(
            title: "Unassigned",
            details: "",
            requiredSkills: [],
            storyPoints: 1,
            status: .todo,
            assignedAgentID: nil
        )
        let inProgress = WorkTask(
            title: "In Progress",
            details: "",
            requiredSkills: [],
            storyPoints: 1,
            status: .inProgress,
            assignedAgentID: agent.id
        )
        let doneTask = WorkTask(
            title: "Done",
            details: "",
            requiredSkills: [],
            storyPoints: 1,
            status: .done,
            assignedAgentID: agent.id
        )

        #expect(
            ContentViewTestHooks.canRunAutoCycle(
                tasks: [unassignedTodo],
                isBatchRunning: false,
                isAutoCycleRunning: false
            )
        )
        #expect(
            ContentViewTestHooks.canRunAutoCycle(
                tasks: [inProgress],
                isBatchRunning: false,
                isAutoCycleRunning: false
            )
        )
        #expect(
            !ContentViewTestHooks.canRunAutoCycle(
                tasks: [doneTask],
                isBatchRunning: false,
                isAutoCycleRunning: false
            )
        )
        #expect(
            !ContentViewTestHooks.canRunAutoCycle(
                tasks: [unassignedTodo],
                isBatchRunning: true,
                isAutoCycleRunning: false
            )
        )
        #expect(
            !ContentViewTestHooks.canRunAutoCycle(
                tasks: [unassignedTodo],
                isBatchRunning: false,
                isAutoCycleRunning: true
            )
        )
    }

    @Test("boolean and count mutation helpers invoke callbacks only on successful outcomes")
    func mutationResultHelpersCoverage() {
        var changedCount = 0
        #expect(
            !ContentViewTestHooks.handleBoolResult(false) {
                changedCount += 1
            }
        )
        #expect(changedCount == 0)
        #expect(
            ContentViewTestHooks.handleBoolResult(true) {
                changedCount += 1
            }
        )
        #expect(changedCount == 1)

        var positiveCountCallback = 0
        #expect(
            ContentViewTestHooks.handlePositiveCountResult(0) {
                positiveCountCallback += 1
            } == 0
        )
        #expect(positiveCountCallback == 0)
        #expect(
            ContentViewTestHooks.handlePositiveCountResult(3) {
                positiveCountCallback += 1
            } == 3
        )
        #expect(positiveCountCallback == 1)
    }

    @Test("editable change helper handles missing identifier failed apply and successful apply")
    func applyEditableChangeHelperCoverage() {
        var callbackCount = 0

        let missingID = ContentViewTestHooks.applyEditableChange(
            editingID: UUID?.none,
            apply: { _ in true },
            onApplied: {
                callbackCount += 1
            }
        )
        #expect(!missingID)

        let failedApply = ContentViewTestHooks.applyEditableChange(
            editingID: UUID(),
            apply: { _ in false },
            onApplied: {
                callbackCount += 1
            }
        )
        #expect(!failedApply)
        #expect(callbackCount == 0)

        let successfulApply = ContentViewTestHooks.applyEditableChange(
            editingID: UUID(),
            apply: { _ in true },
            onApplied: {
                callbackCount += 1
            }
        )
        #expect(successfulApply)
        #expect(callbackCount == 1)
    }

    @Test("manual assignment helper requires selected agent and returns assigner result")
    func manualAssignTaskHelperCoverage() {
        let taskID = UUID()
        let agentID = UUID()
        var assignAttempts = 0

        let missingSelection = ContentViewTestHooks.manualAssignTask(
            taskID: taskID,
            selectedAgentID: nil,
            assigner: { _, _ in
                assignAttempts += 1
                return true
            }
        )
        #expect(!missingSelection)
        #expect(assignAttempts == 0)

        let failed = ContentViewTestHooks.manualAssignTask(
            taskID: taskID,
            selectedAgentID: agentID,
            assigner: { _, _ in
                assignAttempts += 1
                return false
            }
        )
        #expect(!failed)

        let succeeded = ContentViewTestHooks.manualAssignTask(
            taskID: taskID,
            selectedAgentID: agentID,
            assigner: { _, _ in
                assignAttempts += 1
                return true
            }
        )
        #expect(succeeded)
        #expect(assignAttempts == 2)
    }

    @Test("post manual assignment helper updates selections refreshes and closes triage when needed")
    func postManualAssignmentHelperCoverage() {
        let taskID = UUID()
        let otherTaskID = UUID()
        var triageSelectionByTaskID: [UUID: UUID] = [
            taskID: UUID(),
            otherTaskID: UUID()
        ]
        var refreshCount = 0
        var closeCount = 0

        let rejected = ContentViewTestHooks.postManualAssignment(
            assigned: false,
            taskID: taskID,
            triageSelectionByTaskID: &triageSelectionByTaskID,
            refresh: { refreshCount += 1 },
            hasRemainingCandidates: { true },
            closeManualTriage: { closeCount += 1 }
        )
        #expect(!rejected)
        #expect(triageSelectionByTaskID.count == 2)
        #expect(refreshCount == 0)
        #expect(closeCount == 0)

        let assignedWithRemaining = ContentViewTestHooks.postManualAssignment(
            assigned: true,
            taskID: taskID,
            triageSelectionByTaskID: &triageSelectionByTaskID,
            refresh: { refreshCount += 1 },
            hasRemainingCandidates: { true },
            closeManualTriage: { closeCount += 1 }
        )
        #expect(assignedWithRemaining)
        #expect(triageSelectionByTaskID[taskID] == nil)
        #expect(triageSelectionByTaskID[otherTaskID] != nil)
        #expect(refreshCount == 1)
        #expect(closeCount == 0)

        let assignedWithoutRemaining = ContentViewTestHooks.postManualAssignment(
            assigned: true,
            taskID: otherTaskID,
            triageSelectionByTaskID: &triageSelectionByTaskID,
            refresh: { refreshCount += 1 },
            hasRemainingCandidates: { false },
            closeManualTriage: { closeCount += 1 }
        )
        #expect(assignedWithoutRemaining)
        #expect(triageSelectionByTaskID.isEmpty)
        #expect(refreshCount == 2)
        #expect(closeCount == 1)
    }

    @Test("post auto-assign helper always refreshes and opens triage when required")
    func postAutoAssignHelperCoverage() {
        var refreshCount = 0
        var manualTriageCount = 0

        ContentViewTestHooks.postAutoAssign(
            hasPendingManualTriage: false,
            refresh: { refreshCount += 1 },
            openManualTriage: { manualTriageCount += 1 }
        )
        #expect(refreshCount == 1)
        #expect(manualTriageCount == 0)

        ContentViewTestHooks.postAutoAssign(
            hasPendingManualTriage: true,
            refresh: { refreshCount += 1 },
            openManualTriage: { manualTriageCount += 1 }
        )
        #expect(refreshCount == 2)
        #expect(manualTriageCount == 1)
    }

    @Test("health recommendation post-handler covers all action branches")
    func postHealthRecommendationHelperCoverage() {
        var refreshCount = 0
        var manualTriageCount = 0
        var newAgentSheetCount = 0

        ContentViewTestHooks.postHealthRecommendation(
            action: .archiveDone,
            applied: false,
            hasPendingManualTriage: false,
            refresh: { refreshCount += 1 },
            openManualTriage: { manualTriageCount += 1 },
            openNewAgent: { newAgentSheetCount += 1 }
        )
        #expect(refreshCount == 0)
        #expect(manualTriageCount == 0)
        #expect(newAgentSheetCount == 0)

        ContentViewTestHooks.postHealthRecommendation(
            action: .autoAssignUnassignedTodo,
            applied: true,
            hasPendingManualTriage: true,
            refresh: { refreshCount += 1 },
            openManualTriage: { manualTriageCount += 1 },
            openNewAgent: { newAgentSheetCount += 1 }
        )
        ContentViewTestHooks.postHealthRecommendation(
            action: .rebalanceTodoLoad,
            applied: true,
            hasPendingManualTriage: false,
            refresh: { refreshCount += 1 },
            openManualTriage: { manualTriageCount += 1 },
            openNewAgent: { newAgentSheetCount += 1 }
        )
        ContentViewTestHooks.postHealthRecommendation(
            action: .archiveDone,
            applied: true,
            hasPendingManualTriage: false,
            refresh: { refreshCount += 1 },
            openManualTriage: { manualTriageCount += 1 },
            openNewAgent: { newAgentSheetCount += 1 }
        )
        ContentViewTestHooks.postHealthRecommendation(
            action: .createMissingDependencyTasks,
            applied: true,
            hasPendingManualTriage: false,
            refresh: { refreshCount += 1 },
            openManualTriage: { manualTriageCount += 1 },
            openNewAgent: { newAgentSheetCount += 1 }
        )
        ContentViewTestHooks.postHealthRecommendation(
            action: .openManualTriage,
            applied: true,
            hasPendingManualTriage: false,
            refresh: { refreshCount += 1 },
            openManualTriage: { manualTriageCount += 1 },
            openNewAgent: { newAgentSheetCount += 1 }
        )
        ContentViewTestHooks.postHealthRecommendation(
            action: .openNewAgent,
            applied: true,
            hasPendingManualTriage: false,
            refresh: { refreshCount += 1 },
            openManualTriage: { manualTriageCount += 1 },
            openNewAgent: { newAgentSheetCount += 1 }
        )
        ContentViewTestHooks.postHealthRecommendation(
            action: .increaseWIPLimit(.review),
            applied: true,
            hasPendingManualTriage: false,
            refresh: { refreshCount += 1 },
            openManualTriage: { manualTriageCount += 1 },
            openNewAgent: { newAgentSheetCount += 1 }
        )

        #expect(refreshCount == 5)
        #expect(manualTriageCount == 2)
        #expect(newAgentSheetCount == 1)
    }

    @Test("apply-all health post-handler refreshes only for positive counts")
    func postApplyAllHealthRecommendationsHelperCoverage() {
        var refreshCount = 0
        var manualTriageCount = 0

        ContentViewTestHooks.postApplyAllHealthRecommendations(
            appliedCount: 0,
            hasPendingManualTriage: true,
            refresh: { refreshCount += 1 },
            openManualTriage: { manualTriageCount += 1 }
        )
        #expect(refreshCount == 0)
        #expect(manualTriageCount == 0)

        ContentViewTestHooks.postApplyAllHealthRecommendations(
            appliedCount: 2,
            hasPendingManualTriage: false,
            refresh: { refreshCount += 1 },
            openManualTriage: { manualTriageCount += 1 }
        )
        #expect(refreshCount == 1)
        #expect(manualTriageCount == 0)

        ContentViewTestHooks.postApplyAllHealthRecommendations(
            appliedCount: 1,
            hasPendingManualTriage: true,
            refresh: { refreshCount += 1 },
            openManualTriage: { manualTriageCount += 1 }
        )
        #expect(refreshCount == 2)
        #expect(manualTriageCount == 1)
    }

    @Test("task edit helper applies valid updates and rejects invalid title")
    func applyTaskEditsHelperCoverage() {
        let task = WorkTask(
            title: "Original",
            details: "details",
            requiredSkills: ["swiftui"],
            storyPoints: 2,
            status: .todo,
            assignedAgentID: nil
        )
        let viewModel = KanbanBoardViewModel(tasks: [task], agents: [])

        let updated = ContentViewTestHooks.applyTaskEdits(
            viewModel: viewModel,
            taskID: task.id,
            title: "Updated",
            details: "new details",
            requiredSkillsText: "swiftui, qa",
            storyPoints: 5
        )
        #expect(updated)
        #expect(viewModel.tasks.first?.title == "Updated")
        #expect(viewModel.tasks.first?.storyPoints == 5)

        let rejected = ContentViewTestHooks.applyTaskEdits(
            viewModel: viewModel,
            taskID: task.id,
            title: "   ",
            details: "invalid",
            requiredSkillsText: "",
            storyPoints: 1
        )
        #expect(!rejected)
    }

    @Test("task edit helper with optional editing id covers nil and valid id paths")
    func applyTaskEditsOptionalIDCoverage() {
        let task = WorkTask(
            title: "Optional Original",
            details: "details",
            requiredSkills: [],
            storyPoints: 1,
            status: .todo,
            assignedAgentID: nil
        )
        let viewModel = KanbanBoardViewModel(tasks: [task], agents: [])

        let nilID = ContentViewTestHooks.applyTaskEdits(
            viewModel: viewModel,
            editingTaskID: nil,
            title: "Updated",
            details: "details",
            requiredSkillsText: "",
            storyPoints: 2
        )
        #expect(!nilID)

        let valid = ContentViewTestHooks.applyTaskEdits(
            viewModel: viewModel,
            editingTaskID: task.id,
            title: "Optional Updated",
            details: "updated",
            requiredSkillsText: "swift",
            storyPoints: 3
        )
        #expect(valid)
        #expect(viewModel.tasks.first?.title == "Optional Updated")
    }

    @Test("agent edit helper applies profile updates and rejects empty name")
    func applyAgentEditsHelperCoverage() {
        let agent = AgentProfile(
            name: "Agent A",
            skills: ["swiftui"],
            maxConcurrentTasks: 2
        )
        let viewModel = KanbanBoardViewModel(tasks: [], agents: [agent])
        let runtimeProfile = AgentRuntimeProfile(provider: .openAICompatible, model: "gpt-5", openAIAuthMode: .apiKey)

        let updated = ContentViewTestHooks.applyAgentEdits(
            viewModel: viewModel,
            agentID: agent.id,
            name: "Agent B",
            skillsText: "swiftui, qa",
            maxConcurrentTasks: 3,
            runtimeProfile: runtimeProfile
        )
        #expect(updated)
        #expect(viewModel.agents.first?.name == "Agent B")
        #expect(viewModel.agents.first?.runtimeProfile?.model == "gpt-5")

        let rejected = ContentViewTestHooks.applyAgentEdits(
            viewModel: viewModel,
            agentID: agent.id,
            name: " ",
            skillsText: "",
            maxConcurrentTasks: 3,
            runtimeProfile: nil
        )
        #expect(!rejected)
    }

    @Test("agent edit helper with optional editing id covers nil and valid id paths")
    func applyAgentEditsOptionalIDCoverage() {
        let agent = AgentProfile(
            name: "Optional Agent",
            skills: ["swiftui"],
            maxConcurrentTasks: 2
        )
        let viewModel = KanbanBoardViewModel(tasks: [], agents: [agent])
        let runtimeProfile = AgentRuntimeProfile(provider: .localMock, model: "local", openAIAuthMode: .apiKey)

        let nilID = ContentViewTestHooks.applyAgentEdits(
            viewModel: viewModel,
            editingAgentID: nil,
            name: "Updated",
            skillsText: "swift",
            maxConcurrentTasks: 3,
            runtimeProfile: runtimeProfile
        )
        #expect(!nilID)

        let valid = ContentViewTestHooks.applyAgentEdits(
            viewModel: viewModel,
            editingAgentID: agent.id,
            name: "Optional Agent Updated",
            skillsText: "swiftui, qa",
            maxConcurrentTasks: 3,
            runtimeProfile: runtimeProfile
        )
        #expect(valid)
        #expect(viewModel.agents.first?.name == "Optional Agent Updated")
    }

    @Test("save panel helper handles cancel, missing URL, and exporter result")
    func savePanelHelperCoverage() {
        let fileURL = URL(fileURLWithPath: "/tmp/openmac-export.json")
        var exportedURLs: [URL] = []

        let cancelled = ContentViewTestHooks.handleSavePanelResult(
            modalResponse: .cancel,
            url: fileURL
        ) { url in
            exportedURLs.append(url)
            return true
        }
        #expect(!cancelled)
        #expect(exportedURLs.isEmpty)

        let missingURL = ContentViewTestHooks.handleSavePanelResult(
            modalResponse: .OK,
            url: nil
        ) { url in
            exportedURLs.append(url)
            return true
        }
        #expect(!missingURL)
        #expect(exportedURLs.isEmpty)

        let exported = ContentViewTestHooks.handleSavePanelResult(
            modalResponse: .OK,
            url: fileURL
        ) { url in
            exportedURLs.append(url)
            return true
        }
        #expect(exported)
        #expect(exportedURLs == [fileURL])
    }

    @Test("workspace import helper handles preview strategy and import outcomes")
    func workspaceImportHelperCoverage() {
        let fileURL = URL(fileURLWithPath: "/tmp/openmac-import.json")
        let preview = WorkspaceImportPreview(boardCount: 2, taskCount: 5, agentCount: 3)
        var importedPayloads: [(URL, WorkspaceImportStrategy)] = []
        var importedCallbackCount = 0

        let cancelled = ContentViewTestHooks.handleWorkspaceImport(
            modalResponse: .cancel,
            url: fileURL,
            previewProvider: { _ in preview },
            strategyChooser: { _ in .merge },
            importer: { url, strategy in
                importedPayloads.append((url, strategy))
                return true
            },
            onImported: {
                importedCallbackCount += 1
            }
        )
        #expect(!cancelled)
        #expect(importedPayloads.isEmpty)
        #expect(importedCallbackCount == 0)

        let missingPreview = ContentViewTestHooks.handleWorkspaceImport(
            modalResponse: .OK,
            url: fileURL,
            previewProvider: { _ in nil },
            strategyChooser: { _ in .merge },
            importer: { _, _ in true },
            onImported: {}
        )
        #expect(!missingPreview)

        let cancelledStrategy = ContentViewTestHooks.handleWorkspaceImport(
            modalResponse: .OK,
            url: fileURL,
            previewProvider: { _ in preview },
            strategyChooser: { _ in nil },
            importer: { _, _ in true },
            onImported: {}
        )
        #expect(!cancelledStrategy)

        let failedImport = ContentViewTestHooks.handleWorkspaceImport(
            modalResponse: .OK,
            url: fileURL,
            previewProvider: { _ in preview },
            strategyChooser: { _ in .replace },
            importer: { url, strategy in
                importedPayloads.append((url, strategy))
                return false
            },
            onImported: {
                importedCallbackCount += 1
            }
        )
        #expect(!failedImport)
        #expect(importedCallbackCount == 0)

        let succeededImport = ContentViewTestHooks.handleWorkspaceImport(
            modalResponse: .OK,
            url: fileURL,
            previewProvider: { _ in preview },
            strategyChooser: { _ in .merge },
            importer: { url, strategy in
                importedPayloads.append((url, strategy))
                return true
            },
            onImported: {
                importedCallbackCount += 1
            }
        )
        #expect(succeededImport)
        #expect(importedPayloads.last?.0 == fileURL)
        #expect(importedPayloads.last?.1 == .merge)
        #expect(importedCallbackCount == 1)
    }

    @Test("workspace import strategy helper maps button responses and summary text")
    func workspaceImportStrategyHelperCoverage() {
        #expect(ContentViewTestHooks.workspaceImportStrategy(for: .alertFirstButtonReturn) == .merge)
        #expect(ContentViewTestHooks.workspaceImportStrategy(for: .alertSecondButtonReturn) == .replace)
        #expect(ContentViewTestHooks.workspaceImportStrategy(for: .cancel) == nil)

        let preview = WorkspaceImportPreview(boardCount: 3, taskCount: 8, agentCount: 2)
        let text = ContentViewTestHooks.workspaceImportInformativeText(preview: preview)
        #expect(text.contains("Boards: 3"))
        #expect(text.contains("Tasks: 8"))
        #expect(text.contains("Agents: 2"))
        #expect(text.contains("Merge keeps current boards"))
    }

    @Test("workspace panel and alert helpers configure expected defaults")
    func workspacePanelConfigurationCoverage() {
        let workspaceExportPanel = ContentViewTestHooks.configuredWorkspaceExportPanel()
        #expect(workspaceExportPanel.canCreateDirectories)
        #expect(!workspaceExportPanel.isExtensionHidden)
        #expect(workspaceExportPanel.nameFieldStringValue == "openmac-workspace.json")
        #expect(workspaceExportPanel.title == "Export Workspace")

        let boardExportPanel = ContentViewTestHooks.configuredSelectedBoardExportPanel(
            defaultFileName: "openmac-board-1.json"
        )
        #expect(boardExportPanel.canCreateDirectories)
        #expect(!boardExportPanel.isExtensionHidden)
        #expect(boardExportPanel.nameFieldStringValue == "openmac-board-1.json")
        #expect(boardExportPanel.title == "Export Current Board")

        let importPanel = ContentViewTestHooks.configuredWorkspaceImportPanel()
        #expect(!importPanel.allowsMultipleSelection)
        #expect(!importPanel.canChooseDirectories)
        #expect(importPanel.canChooseFiles)
        #expect(importPanel.title == "Import Workspace")

        let preview = WorkspaceImportPreview(boardCount: 1, taskCount: 2, agentCount: 1)
        let importAlert = ContentViewTestHooks.configuredWorkspaceImportAlert(preview: preview)
        let buttonTitles = importAlert.buttons.map(\.title)
        #expect(importAlert.messageText == "Import Workspace")
        #expect(buttonTitles == ["Merge", "Replace", "Cancel"])
    }

    @Test("pm board naming helper resolves default and duplicate names")
    func pmBoardNamingHelperCoverage() {
        let fallback = ContentViewTestHooks.uniquePMBoardName(
            baseName: "   ",
            existingNames: []
        )
        #expect(fallback == "PM Project")

        let direct = ContentViewTestHooks.uniquePMBoardName(
            baseName: "Website Revamp",
            existingNames: ["Default Board"]
        )
        #expect(direct == "Website Revamp")

        let duplicated = ContentViewTestHooks.uniquePMBoardName(
            baseName: "Website Revamp",
            existingNames: ["website revamp", "Website Revamp (2)"]
        )
        #expect(duplicated == "Website Revamp (3)")
    }

    @Test("pm planner skill list normalization trims deduplicates and lowercases")
    func pmPlannerSkillListNormalizationCoverage() {
        let normalized = ContentViewTestHooks.normalizedSkillList(
            from: " SwiftUI,  QA ,swiftui, , Backend , qa "
        )
        #expect(normalized == ["backend", "qa", "swiftui"])
    }

    @Test("pm planner template options expose expected quick-start ids")
    func pmPlannerTemplateOptionIDsCoverage() {
        let optionIDs = ContentViewTestHooks.pmBriefTemplateOptionIDs()
        #expect(optionIDs == ["custom", "saas", "app", "api"])
    }

    @Test("pm planner apply template fills brief and handles project name defaults")
    func pmPlannerApplyTemplateCoverage() {
        var existingName = "Existing Board"
        var existingBrief = "old brief"
        let applied = ContentViewTestHooks.applyPMTemplate(
            selectedTemplateID: "api",
            projectName: &existingName,
            projectBrief: &existingBrief
        )
        #expect(applied)
        #expect(existingName == "Existing Board")
        #expect(existingBrief == L10n.string("PM Template Brief API"))

        var blankName = "   "
        var blankBrief = ""
        let appliedToBlank = ContentViewTestHooks.applyPMTemplate(
            selectedTemplateID: "saas",
            projectName: &blankName,
            projectBrief: &blankBrief
        )
        #expect(appliedToBlank)
        #expect(blankName == L10n.string("SaaS MVP"))
        #expect(blankBrief == L10n.string("PM Template Brief SaaS"))

        var untouchedName = "No Change"
        var untouchedBrief = "No Change"
        let notApplied = ContentViewTestHooks.applyPMTemplate(
            selectedTemplateID: "custom",
            projectName: &untouchedName,
            projectBrief: &untouchedBrief
        )
        #expect(!notApplied)
        #expect(untouchedName == "No Change")
        #expect(untouchedBrief == "No Change")
    }

    @Test("pm planner apply template reset clears prior generated plan state")
    func pmPlannerApplyTemplateResetCoverage() {
        var name = "Board A"
        var brief = "Old brief"
        var planSummary = "Old summary"
        var tickets = [
            PMPlannedTicket(
                title: "Old Task",
                details: "Old details",
                requiredSkills: ["qa"],
                storyPoints: 2
            )
        ]

        let applied = ContentViewTestHooks.applyPMTemplateAndReset(
            selectedTemplateID: "app",
            projectName: &name,
            projectBrief: &brief,
            planSummary: &planSummary,
            plannedTickets: &tickets
        )
        #expect(applied)
        #expect(brief == L10n.string("PM Template Brief App"))
        #expect(planSummary.isEmpty)
        #expect(tickets.isEmpty)

        var untouchedName = "Board B"
        var untouchedBrief = "Keep brief"
        var untouchedSummary = "Keep summary"
        var untouchedTickets = [
            PMPlannedTicket(
                title: "Keep task",
                details: "Keep details",
                requiredSkills: ["swiftui"],
                storyPoints: 1
            )
        ]
        let notApplied = ContentViewTestHooks.applyPMTemplateAndReset(
            selectedTemplateID: "custom",
            projectName: &untouchedName,
            projectBrief: &untouchedBrief,
            planSummary: &untouchedSummary,
            plannedTickets: &untouchedTickets
        )
        #expect(!notApplied)
        #expect(untouchedBrief == "Keep brief")
        #expect(untouchedSummary == "Keep summary")
        #expect(untouchedTickets.count == 1)
    }

    @Test("pm blueprint wizard composes brief sections from non-empty fields")
    func pmBlueprintBriefCompositionCoverage() {
        let composed = ContentViewTestHooks.pmBlueprintBriefText(
            vision: "Build a privacy-first dating app",
            targetUsers: "Young professionals in cities",
            coreFeatures: "profiles, matching, chat",
            techScope: "",
            constraints: "ship MVP in 8 weeks",
            qualityBar: "crash-free > 99.5%"
        )

        #expect(composed.contains("Product Vision:"))
        #expect(composed.contains("Build a privacy-first dating app"))
        #expect(composed.contains("Target Users:"))
        #expect(composed.contains("Core Features:"))
        #expect(!composed.contains("Tech Scope:"))
        #expect(composed.contains("Constraints:"))
        #expect(composed.contains("Quality Bar:"))
    }

    @Test("pm blueprint wizard updates project brief and preserves existing project name")
    func pmBlueprintApplyCoverage() {
        var existingProjectName = "OpenMac Board"
        var projectBrief = ""

        let applied = ContentViewTestHooks.applyPMBlueprint(
            vision: "Dating app MVP",
            targetUsers: "Gen Z",
            coreFeatures: "match, chat",
            techScope: "iOS + backend API",
            constraints: "",
            qualityBar: "",
            projectName: &existingProjectName,
            projectBrief: &projectBrief
        )
        #expect(applied)
        #expect(existingProjectName == "OpenMac Board")
        #expect(projectBrief.contains("Product Vision:"))
        #expect(projectBrief.contains("Dating app MVP"))

        var blankName = "   "
        var blankBrief = "old"
        let appliedWithBlankName = ContentViewTestHooks.applyPMBlueprint(
            vision: "New Product Name",
            targetUsers: "",
            coreFeatures: "",
            techScope: "",
            constraints: "",
            qualityBar: "",
            projectName: &blankName,
            projectBrief: &blankBrief
        )
        #expect(appliedWithBlankName)
        #expect(blankName == "New Product Name")
        #expect(blankBrief.contains("Product Vision:"))

        var untouchedName = "Keep Name"
        var untouchedBrief = "Keep Brief"
        let notApplied = ContentViewTestHooks.applyPMBlueprint(
            vision: "   ",
            targetUsers: "",
            coreFeatures: "",
            techScope: "",
            constraints: "",
            qualityBar: "",
            projectName: &untouchedName,
            projectBrief: &untouchedBrief
        )
        #expect(!notApplied)
        #expect(untouchedName == "Keep Name")
        #expect(untouchedBrief == "Keep Brief")
    }

    @Test("pm auto acceptance criteria appends checklist and avoids duplication")
    func pmAutoAcceptanceCriteriaCoverage() {
        let base = PMPlannedTicket(
            title: "Core Chat Flow",
            details: "Implement message sending.",
            requiredSkills: ["swiftui", "backend"],
            storyPoints: 8
        )
        let withAC = ContentViewTestHooks.applyingAutoAcceptanceCriteria(to: base)
        #expect(withAC.details.contains("Acceptance Criteria:"))
        #expect(withAC.details.contains("Automated tests are added or updated"))
        #expect(withAC.details.contains("Performance and reliability checks"))

        let duplicateAttempt = ContentViewTestHooks.applyingAutoAcceptanceCriteria(to: withAC)
        #expect(duplicateAttempt.details == withAC.details)
    }

    @Test("pm dependency chain injects and updates depends-on lines")
    func pmDependencyChainCoverage() {
        let tickets = [
            PMPlannedTicket(
                title: "Scope",
                details: "Clarify scope and deliverables.",
                requiredSkills: ["planning"],
                storyPoints: 2
            ),
            PMPlannedTicket(
                title: "Architecture",
                details: """
                Depends on: OLD
                Build architecture.
                """,
                requiredSkills: ["backend"],
                storyPoints: 3
            ),
            PMPlannedTicket(
                title: "Implementation",
                details: "",
                requiredSkills: ["swiftui"],
                storyPoints: 5
            )
        ]

        let chained = ContentViewTestHooks.applyingDependencyChain(to: tickets)

        #expect(chained.count == 3)
        #expect(chained[0].details.hasPrefix("Depends on: none"))
        #expect(chained[1].details.hasPrefix("Depends on: Scope"))
        #expect(chained[1].details.contains("Build architecture."))
        #expect(chained[1].details.contains("Depends on: OLD") == false)
        #expect(chained[2].details == "Depends on: Architecture")
    }

    @Test("pm test plan helper generates core test sections")
    func pmTestPlanTextCoverage() {
        let tickets = [
            PMPlannedTicket(
                title: "Matching Engine",
                details: "Build candidate ranking",
                requiredSkills: ["backend"],
                storyPoints: 5
            ),
            PMPlannedTicket(
                title: "Chat UI",
                details: "Build chat thread view",
                requiredSkills: ["swiftui"],
                storyPoints: 3
            )
        ]

        let text = ContentViewTestHooks.pmTestPlanText(
            projectName: "Dating App",
            projectBrief: "Ship MVP for matching and chat",
            tickets: tickets
        )
        #expect(text.contains("Test Plan"))
        #expect(text.contains("Total Tickets: 2"))
        #expect(text.contains("Unit Test Coverage"))
        #expect(text.contains("Integration Test Flows"))
        #expect(text.contains("End-to-End Scenarios"))
        #expect(text.contains("Quality Gates"))
    }

    @Test("pm plan copy text helper includes summary and ticket breakdown")
    func pmPlanCopyTextCoverage() {
        let tickets = [
            PMPlannedTicket(
                title: "Build MVP",
                details: "Ship first milestone.",
                requiredSkills: ["swiftui", "qa"],
                storyPoints: 5,
                epic: "Core Product",
                milestone: "M2 MVP Complete"
            ),
            PMPlannedTicket(
                title: "Release Notes",
                details: "",
                requiredSkills: [],
                storyPoints: 1,
                epic: "Release",
                milestone: "M4 Release Ready"
            )
        ]

        let text = ContentViewTestHooks.pmPlanCopyText(
            projectName: "OpenMac PM",
            summary: "Plan generated for delivery.",
            tickets: tickets
        )

        #expect(text.contains("# OpenMac PM"))
        #expect(text.contains("Plan generated for delivery."))
        #expect(text.contains("Total Tickets: 2"))
        #expect(text.contains("Total Story Points: 6"))
        #expect(text.contains("Total Milestones: 2"))
        #expect(text.contains("Total Epics: 2"))
        #expect(text.contains("## Roadmap"))
        #expect(text.contains("1. Build MVP (SP: 5)"))
        #expect(text.contains("Skills: qa, swiftui") || text.contains("Skills: swiftui, qa"))
        #expect(text.contains("Milestone: M2 MVP Complete"))
        #expect(text.contains("Epic: Core Product"))
        #expect(text.contains("2. Release Notes (SP: 1)"))
    }

    @Test("pm roadmap helper groups tickets by milestone and includes epic tags")
    func pmRoadmapTextCoverage() {
        let tickets = [
            PMPlannedTicket(
                title: "Scope",
                details: "",
                requiredSkills: ["planning"],
                storyPoints: 2,
                epic: "Planning",
                milestone: "M1 Scope Locked"
            ),
            PMPlannedTicket(
                title: "Ship",
                details: "",
                requiredSkills: ["release"],
                storyPoints: 3,
                epic: "Release",
                milestone: "M4 Release Ready"
            )
        ]

        let roadmap = ContentViewTestHooks.pmRoadmapText(
            projectName: "OpenMac PM",
            tickets: tickets
        )

        #expect(roadmap.contains("Project: OpenMac PM"))
        #expect(roadmap.contains("Milestone: M1 Scope Locked"))
        #expect(roadmap.contains("[Planning] Scope"))
        #expect(roadmap.contains("Milestone: M4 Release Ready"))
        #expect(roadmap.contains("[Release] Ship"))
    }

    @Test("pm plan copy text helper appends test plan block when provided")
    func pmPlanCopyTextIncludesTestPlanCoverage() {
        let text = ContentViewTestHooks.pmPlanCopyText(
            projectName: "OpenMac PM",
            summary: "Plan generated.",
            tickets: [],
            testPlan: "# Test Plan\nUnit and integration checks."
        )

        #expect(text.contains("## Test Plan"))
        #expect(text.contains("Unit and integration checks."))
    }

    @Test("content subviews can render representative body states")
    func renderSubviewBodiesForCoverage() {
        let renderedCount = ContentViewTestHooks.renderSubviewBodiesForCoverage()
        #expect(renderedCount >= 20)
    }

    @Test("content action handlers execute representative non-UI side effects")
    func exerciseActionHandlersForCoverage() {
        let exercisedCount = ContentViewTestHooks.exerciseActionHandlersForCoverage()
        #expect(exercisedCount >= 40)
    }

    @Test("content helper branches execute search and triage edge cases")
    func exerciseTargetedHelperBranchesForCoverage() {
        let exercisedCount = ContentViewTestHooks.exerciseTargetedHelperBranchesForCoverage()
        #expect(exercisedCount >= 5)
    }

    @Test("content recommendation and triage helper accessors are exercised")
    func exerciseRecommendationAndTriageHelpersForCoverage() {
        let exercisedCount = ContentViewTestHooks.exerciseRecommendationAndTriageHelpersForCoverage()
        #expect(exercisedCount >= 5)
    }
}

@Suite(.serialized)
@MainActor
struct KanbanPersistenceTests {

    @Test("clears localized transient board message")
    func clearsLocalizedTransientBoardMessage() {
        let viewModel = KanbanBoardViewModel(tasks: [], agents: [])
        _ = viewModel.addTask(
            title: "",
            details: "missing title",
            requiredSkillsText: "",
            storyPoints: 1
        )
        #expect(viewModel.lastBoardMessage != nil)

        viewModel.clearLocalizedTransientBoardMessage()

        #expect(viewModel.lastBoardMessage == nil)
        #expect(viewModel.lastBoardMessageSeverity == nil)
    }

    @Test("persists board snapshot after successful state mutation")
    func persistsBoardAfterMove() {
        let task = WorkTask(
            title: "Persist me",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 1,
            status: .todo,
            assignedAgentID: nil
        )
        let store = SpyBoardStore()
        let viewModel = KanbanBoardViewModel(tasks: [task], agents: [], boardStore: store)

        let moved = viewModel.moveTask(task.id, to: .inProgress)

        #expect(moved)
        #expect(store.savedSnapshots.count == 1)
        #expect(store.savedSnapshots.last?.tasks.first?.status == .inProgress)
    }

    @Test("loads saved snapshot when creating persistent board")
    func persistentBoardLoadsSnapshot() {
        let persistedTask = WorkTask(
            title: "Loaded task",
            details: "From disk",
            requiredSkills: ["testing"],
            storyPoints: 2,
            status: .review,
            assignedAgentID: nil
        )
        let persistedAgent = AgentProfile(name: "Stored Agent", skills: ["testing"], maxConcurrentTasks: 2)
        let snapshot = KanbanBoardSnapshot(
            tasks: [persistedTask],
            agents: [persistedAgent],
            wipLimits: [.inProgress: 1, .review: 1]
        )
        let store = SpyBoardStore(loadSnapshot: snapshot)

        let viewModel = KanbanBoardViewModel.persistentBoard(boardStore: store)

        #expect(viewModel.tasks.count == 1)
        #expect(viewModel.tasks[0].title == "Loaded task")
        #expect(viewModel.agents[0].name == "Stored Agent")
        #expect(viewModel.wipLimit(for: .inProgress) == 1)
    }

    @Test("creates a new board and switches to it with isolated state")
    func createsBoardAndSwitchesToIsolatedContext() {
        let seedTask = WorkTask(
            title: "Seed task",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 2,
            status: .todo,
            assignedAgentID: nil
        )
        let seedAgent = AgentProfile(name: "Seed Agent", skills: ["swiftui"], maxConcurrentTasks: 2)
        let viewModel = KanbanBoardViewModel(tasks: [seedTask], agents: [seedAgent])

        let created = viewModel.createBoard(name: "Platform Board")

        #expect(created)
        #expect(viewModel.boards.count == 2)
        #expect(viewModel.selectedBoardName == "Platform Board")
        #expect(viewModel.tasks.isEmpty)
        #expect(viewModel.agents.isEmpty)
        #expect(viewModel.wipLimit(for: .inProgress) == 3)
        #expect(viewModel.wipLimit(for: .review) == 2)
    }

    @Test("rejects creating board when name is empty after trimming")
    func rejectsCreatingBoardWithEmptyName() {
        let viewModel = KanbanBoardViewModel(tasks: [], agents: [])

        let created = viewModel.createBoard(name: "   ")

        #expect(!created)
        #expect(viewModel.boards.count == 1)
        #expect(viewModel.lastBoardMessage == "Board name is required")
    }

    @Test("rejects creating board when normalized name already exists")
    func rejectsCreatingBoardWithDuplicateName() {
        let viewModel = KanbanBoardViewModel(tasks: [], agents: [])
        _ = viewModel.createBoard(name: "Platform")

        let created = viewModel.createBoard(name: "platform")

        #expect(!created)
        #expect(viewModel.boards.count == 2)
        #expect(viewModel.lastBoardMessage == "Board name already exists")
    }

    @Test("switching boards restores each board's independent tasks and agents")
    func switchingBoardsRestoresIndependentState() {
        let defaultTask = WorkTask(
            title: "Default task",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 2,
            status: .todo,
            assignedAgentID: nil
        )
        let defaultAgent = AgentProfile(name: "Default Agent", skills: ["swiftui"], maxConcurrentTasks: 2)
        let viewModel = KanbanBoardViewModel(tasks: [defaultTask], agents: [defaultAgent])
        let defaultBoardID = viewModel.selectedBoardID

        _ = viewModel.createBoard(name: "Research Board")
        _ = viewModel.addTask(
            title: "Research task",
            details: "",
            requiredSkillsText: "analysis",
            storyPoints: 1
        )
        _ = viewModel.addAgent(name: "Research Agent", skillsText: "analysis", maxConcurrentTasks: 1)

        let switchedBack = viewModel.switchBoard(to: defaultBoardID)
        #expect(switchedBack)
        #expect(viewModel.selectedBoardID == defaultBoardID)
        #expect(viewModel.tasks.count == 1)
        #expect(viewModel.tasks.first?.title == "Default task")
        #expect(viewModel.agents.count == 1)
        #expect(viewModel.agents.first?.name == "Default Agent")

        let researchBoardID = viewModel.boards.first(where: { $0.name == "Research Board" })?.id
        #expect(researchBoardID != nil)

        if let researchBoardID {
            let switchedToResearch = viewModel.switchBoard(to: researchBoardID)
            #expect(switchedToResearch)
            #expect(viewModel.selectedBoardID == researchBoardID)
            #expect(viewModel.tasks.count == 1)
            #expect(viewModel.tasks.first?.title == "Research task")
            #expect(viewModel.agents.count == 1)
            #expect(viewModel.agents.first?.name == "Research Agent")
        }
    }

    @Test("loads selected board from multi-board snapshot")
    func persistentBoardLoadsSelectedBoardFromMultiBoardSnapshot() {
        let deliveryTask = WorkTask(
            title: "Delivery task",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 2,
            status: .todo,
            assignedAgentID: nil
        )
        let qaTask = WorkTask(
            title: "QA task",
            details: "",
            requiredSkills: ["testing"],
            storyPoints: 1,
            status: .review,
            assignedAgentID: nil
        )
        let deliveryBoard = KanbanBoardRecord(name: "Delivery", tasks: [deliveryTask], agents: [], wipLimits: [.inProgress: 3, .review: 2])
        let qaBoard = KanbanBoardRecord(name: "QA", tasks: [qaTask], agents: [], wipLimits: [.inProgress: 2, .review: 1])
        let snapshot = KanbanBoardSnapshot(
            tasks: deliveryBoard.tasks,
            agents: deliveryBoard.agents,
            wipLimits: deliveryBoard.wipLimits,
            boards: [deliveryBoard, qaBoard],
            selectedBoardID: qaBoard.id
        )
        let store = SpyBoardStore(loadSnapshot: snapshot)

        let viewModel = KanbanBoardViewModel.persistentBoard(boardStore: store)

        #expect(viewModel.boards.count == 2)
        #expect(viewModel.selectedBoardID == qaBoard.id)
        #expect(viewModel.selectedBoardName == "QA")
        #expect(viewModel.tasks.count == 1)
        #expect(viewModel.tasks.first?.title == "QA task")
    }

    @Test("persistent board falls back to first board when snapshot selection is missing")
    func persistentBoardFallsBackToFirstBoardWhenSelectionMissing() {
        let firstTask = WorkTask(
            title: "First board task",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 2,
            status: .todo,
            assignedAgentID: nil
        )
        let secondTask = WorkTask(
            title: "Second board task",
            details: "",
            requiredSkills: ["testing"],
            storyPoints: 1,
            status: .review,
            assignedAgentID: nil
        )
        let firstBoard = KanbanBoardRecord(name: "First", tasks: [firstTask], agents: [], wipLimits: [.inProgress: 3, .review: 2])
        let secondBoard = KanbanBoardRecord(name: "Second", tasks: [secondTask], agents: [], wipLimits: [.inProgress: 2, .review: 1])
        let snapshot = KanbanBoardSnapshot(
            tasks: firstBoard.tasks,
            agents: firstBoard.agents,
            wipLimits: firstBoard.wipLimits,
            boards: [firstBoard, secondBoard],
            selectedBoardID: nil
        )
        let store = SpyBoardStore(loadSnapshot: snapshot)

        let viewModel = KanbanBoardViewModel.persistentBoard(boardStore: store)

        #expect(viewModel.selectedBoardID == firstBoard.id)
        #expect(viewModel.selectedBoardName == "First")
        #expect(viewModel.tasks.first?.title == "First board task")
    }

    @Test("renames selected board and persists updated board metadata")
    func renamesSelectedBoardAndPersists() {
        let store = SpyBoardStore()
        let viewModel = KanbanBoardViewModel(tasks: [], agents: [], boardStore: store)
        _ = viewModel.createBoard(name: "Research Board")
        let selectedBoardID = viewModel.selectedBoardID

        let renamed = viewModel.renameBoard(selectedBoardID, to: "Strategy Board")

        #expect(renamed)
        #expect(viewModel.selectedBoardName == "Strategy Board")
        #expect(viewModel.boards.contains(where: { $0.id == selectedBoardID && $0.name == "Strategy Board" }))
        #expect(store.savedSnapshots.last?.boards?.contains(where: { $0.id == selectedBoardID && $0.name == "Strategy Board" }) == true)
    }

    @Test("rejects board rename when target name already exists")
    func rejectsDuplicateBoardRename() {
        let viewModel = KanbanBoardViewModel(tasks: [], agents: [])
        let defaultBoardID = viewModel.selectedBoardID
        _ = viewModel.createBoard(name: "Research Board")

        let renamed = viewModel.renameBoard(defaultBoardID, to: "research board")

        #expect(!renamed)
        #expect(viewModel.lastBoardMessage == "Board name already exists")
    }

    @Test("rejects board rename when new name is empty")
    func rejectsBoardRenameWithEmptyName() {
        let viewModel = KanbanBoardViewModel(tasks: [], agents: [])

        let renamed = viewModel.renameBoard(viewModel.selectedBoardID, to: "   ")

        #expect(!renamed)
        #expect(viewModel.lastBoardMessage == "Board name is required")
    }

    @Test("rejects board rename when board id is unknown")
    func rejectsBoardRenameForUnknownBoard() {
        let viewModel = KanbanBoardViewModel(tasks: [], agents: [])

        let renamed = viewModel.renameBoard(UUID(), to: "Strategy")

        #expect(!renamed)
        #expect(viewModel.lastBoardMessage == "Board not found")
    }

    @Test("removes selected board and switches to remaining board")
    func removesSelectedBoardAndSwitchesContext() {
        let baselineTask = WorkTask(
            title: "Baseline",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 1,
            status: .todo,
            assignedAgentID: nil
        )
        let store = SpyBoardStore()
        let viewModel = KanbanBoardViewModel(tasks: [baselineTask], agents: [], boardStore: store)
        let defaultBoardID = viewModel.selectedBoardID
        _ = viewModel.createBoard(name: "Research Board")
        let researchBoardID = viewModel.selectedBoardID
        _ = viewModel.addTask(
            title: "Research Task",
            details: "",
            requiredSkillsText: "analysis",
            storyPoints: 2
        )

        let removed = viewModel.removeBoard(researchBoardID)

        #expect(removed)
        #expect(viewModel.boards.count == 1)
        #expect(viewModel.selectedBoardID == defaultBoardID)
        #expect(viewModel.tasks.count == 1)
        #expect(viewModel.tasks.first?.title == "Baseline")
        #expect(store.savedSnapshots.last?.boards?.count == 1)
    }

    @Test("prevents removing the last remaining board")
    func preventsRemovingLastBoard() {
        let viewModel = KanbanBoardViewModel(tasks: [], agents: [])

        let removed = viewModel.removeBoard(viewModel.selectedBoardID)

        #expect(!removed)
        #expect(viewModel.boards.count == 1)
        #expect(viewModel.lastBoardMessage == "At least one board is required")
    }

    @Test("duplicates board with copied state and switches context")
    func duplicatesBoardAndSwitchesContext() {
        let baselineTask = WorkTask(
            title: "Baseline",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 2,
            status: .todo,
            assignedAgentID: nil
        )
        let baselineAgent = AgentProfile(name: "Baseline Agent", skills: ["swiftui"], maxConcurrentTasks: 2)
        let store = SpyBoardStore()
        let viewModel = KanbanBoardViewModel(
            tasks: [baselineTask],
            agents: [baselineAgent],
            wipLimits: [.inProgress: 4, .review: 3],
            boardStore: store
        )
        let sourceBoardID = viewModel.selectedBoardID

        let duplicated = viewModel.duplicateBoard(sourceBoardID)

        #expect(duplicated)
        #expect(viewModel.boards.count == 2)
        #expect(viewModel.selectedBoardID != sourceBoardID)
        #expect(viewModel.selectedBoardName == "Default Board Copy")
        #expect(viewModel.tasks.count == 1)
        #expect(viewModel.tasks.first?.title == "Baseline")
        #expect(viewModel.agents.count == 1)
        #expect(viewModel.agents.first?.name == "Baseline Agent")
        #expect(viewModel.wipLimit(for: .inProgress) == 4)
        #expect(store.savedSnapshots.last?.boards?.count == 2)
        #expect(store.savedSnapshots.last?.selectedBoardID == viewModel.selectedBoardID)
    }

    @Test("rejects board duplication when explicit target name already exists")
    func rejectsDuplicateBoardCopyName() {
        let viewModel = KanbanBoardViewModel(tasks: [], agents: [])
        let sourceBoardID = viewModel.selectedBoardID
        _ = viewModel.createBoard(name: "Research Board")

        let duplicated = viewModel.duplicateBoard(sourceBoardID, name: "Research Board")

        #expect(!duplicated)
        #expect(viewModel.lastBoardMessage == "Board name already exists")
    }

    @Test("rejects removing board when board id does not exist")
    func rejectsRemovingUnknownBoard() {
        let viewModel = KanbanBoardViewModel(tasks: [], agents: [])
        _ = viewModel.createBoard(name: "Research Board")
        let existingBoardCount = viewModel.boards.count

        let removed = viewModel.removeBoard(UUID())

        #expect(!removed)
        #expect(viewModel.boards.count == existingBoardCount)
        #expect(viewModel.lastBoardMessage == "Board not found")
    }

    @Test("rejects duplicating board when source board id does not exist")
    func rejectsDuplicatingUnknownBoard() {
        let viewModel = KanbanBoardViewModel(tasks: [], agents: [])

        let duplicated = viewModel.duplicateBoard(UUID())

        #expect(!duplicated)
        #expect(viewModel.lastBoardMessage == "Board not found")
    }

    @Test("rejects duplicating board when explicit name is empty")
    func rejectsDuplicatingBoardWithEmptyName() {
        let viewModel = KanbanBoardViewModel(tasks: [], agents: [])

        let duplicated = viewModel.duplicateBoard(viewModel.selectedBoardID, name: "   ")

        #expect(!duplicated)
        #expect(viewModel.lastBoardMessage == "Board name is required")
    }

    @Test("duplicating board auto-name increments copy suffix")
    func duplicateBoardAutoNameIncrementsSuffix() {
        let viewModel = KanbanBoardViewModel(tasks: [], agents: [])
        let sourceBoardID = viewModel.selectedBoardID

        let firstCopy = viewModel.duplicateBoard(sourceBoardID)
        let secondCopy = viewModel.duplicateBoard(sourceBoardID)

        #expect(firstCopy)
        #expect(secondCopy)
        #expect(viewModel.boards.contains(where: { $0.name == "Default Board Copy" }))
        #expect(viewModel.boards.contains(where: { $0.name == "Default Board Copy 2" }))
    }

    @Test("moves task to another board and persists both board states")
    func movesTaskToAnotherBoardAndPersists() {
        let task = WorkTask(
            title: "Cross board task",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 2,
            status: .todo,
            assignedAgentID: nil
        )
        let store = SpyBoardStore()
        let viewModel = KanbanBoardViewModel(tasks: [task], agents: [], boardStore: store)
        let sourceBoardID = viewModel.selectedBoardID
        _ = viewModel.createBoard(name: "Target Board")
        let targetBoardID = viewModel.selectedBoardID
        _ = viewModel.switchBoard(to: sourceBoardID)

        let moved = viewModel.moveTask(task.id, toBoard: targetBoardID)

        #expect(moved)
        #expect(viewModel.tasks.isEmpty)
        #expect(store.savedSnapshots.last?.boards?.count == 2)

        let switched = viewModel.switchBoard(to: targetBoardID)
        #expect(switched)
        #expect(viewModel.tasks.count == 1)
        #expect(viewModel.tasks.first?.title == "Cross board task")
    }

    @Test("rejects moving task to unknown board")
    func rejectsMovingTaskToUnknownBoard() {
        let task = WorkTask(
            title: "Cross board task",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 2,
            status: .todo,
            assignedAgentID: nil
        )
        let viewModel = KanbanBoardViewModel(tasks: [task], agents: [])

        let moved = viewModel.moveTask(task.id, toBoard: UUID())

        #expect(!moved)
        #expect(viewModel.lastBoardMessage == "Board not found")
    }

    @Test("rejects moving task to the same board")
    func rejectsMovingTaskToSameBoard() {
        let task = WorkTask(
            title: "Same board move",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 1,
            status: .todo,
            assignedAgentID: nil
        )
        let viewModel = KanbanBoardViewModel(tasks: [task], agents: [])

        let moved = viewModel.moveTask(task.id, toBoard: viewModel.selectedBoardID)

        #expect(!moved)
        #expect(viewModel.lastBoardMessage == "Select a different board")
    }

    @Test("rejects moving task to another board when task is missing")
    func rejectsMovingMissingTaskToAnotherBoard() {
        let task = WorkTask(
            title: "Cross board task",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 2,
            status: .todo,
            assignedAgentID: nil
        )
        let viewModel = KanbanBoardViewModel(tasks: [task], agents: [])
        let sourceBoardID = viewModel.selectedBoardID
        _ = viewModel.createBoard(name: "Target Board")
        let targetBoardID = viewModel.selectedBoardID
        _ = viewModel.switchBoard(to: sourceBoardID)

        let moved = viewModel.moveTask(UUID(), toBoard: targetBoardID)

        #expect(!moved)
        #expect(viewModel.lastBoardMessage == "Task not found")
    }

    @Test("moving task to board without assigned agent unassigns task")
    func movingTaskToBoardWithoutAgentUnassignsTask() {
        let agent = AgentProfile(name: "Source Agent", skills: ["swiftui"], maxConcurrentTasks: 2)
        let task = WorkTask(
            title: "Assigned cross board task",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 2,
            status: .todo,
            assignedAgentID: agent.id
        )
        let viewModel = KanbanBoardViewModel(tasks: [task], agents: [agent])
        let sourceBoardID = viewModel.selectedBoardID
        _ = viewModel.createBoard(name: "Agentless Target")
        let targetBoardID = viewModel.selectedBoardID
        _ = viewModel.switchBoard(to: sourceBoardID)

        let moved = viewModel.moveTask(task.id, toBoard: targetBoardID)

        #expect(moved)
        let switched = viewModel.switchBoard(to: targetBoardID)
        #expect(switched)
        #expect(viewModel.tasks.first?.assignedAgentID == nil)
    }

    @Test("moving task to board with non-matching agents clears assignment")
    func movingTaskToBoardWithNonMatchingAgentsClearsAssignment() {
        let sourceAgent = AgentProfile(name: "Source Agent", skills: ["swiftui"], maxConcurrentTasks: 2)
        let task = WorkTask(
            title: "Assigned cross board task",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 2,
            status: .todo,
            assignedAgentID: sourceAgent.id
        )
        let viewModel = KanbanBoardViewModel(tasks: [task], agents: [sourceAgent])
        let sourceBoardID = viewModel.selectedBoardID
        _ = viewModel.createBoard(name: "Target With Agents")
        _ = viewModel.addAgent(name: "Target Agent", skillsText: "swiftui", maxConcurrentTasks: 2)
        let targetBoardID = viewModel.selectedBoardID
        _ = viewModel.switchBoard(to: sourceBoardID)

        let moved = viewModel.moveTask(task.id, toBoard: targetBoardID)

        #expect(moved)
        _ = viewModel.switchBoard(to: targetBoardID)
        #expect(viewModel.tasks.first?.assignedAgentID == nil)
    }

    @Test("copies task to another board while keeping source task intact")
    func copiesTaskToAnotherBoardAndKeepsSourceTask() {
        let task = WorkTask(
            title: "Shared backlog item",
            details: "Track in both boards",
            requiredSkills: ["swiftui"],
            storyPoints: 3,
            status: .todo,
            assignedAgentID: nil
        )
        let store = SpyBoardStore()
        let viewModel = KanbanBoardViewModel(tasks: [task], agents: [], boardStore: store)
        let sourceBoardID = viewModel.selectedBoardID
        _ = viewModel.createBoard(name: "Copied Target")
        let targetBoardID = viewModel.selectedBoardID
        _ = viewModel.switchBoard(to: sourceBoardID)

        let copied = viewModel.copyTask(task.id, toBoard: targetBoardID)

        #expect(copied)
        #expect(viewModel.tasks.count == 1)
        #expect(viewModel.tasks.first?.id == task.id)
        #expect(store.savedSnapshots.last?.boards?.count == 2)

        let switched = viewModel.switchBoard(to: targetBoardID)
        #expect(switched)
        #expect(viewModel.tasks.count == 1)
        #expect(viewModel.tasks.first?.id != task.id)
        #expect(viewModel.tasks.first?.title == task.title)
        #expect(viewModel.tasks.first?.details == task.details)
        #expect(viewModel.tasks.first?.requiredSkills == task.requiredSkills)
        #expect(viewModel.tasks.first?.storyPoints == task.storyPoints)
    }

    @Test("copying task to board without assigned agent unassigns copied task only")
    func copyingTaskToBoardWithoutAgentUnassignsCopiedTaskOnly() {
        let agent = AgentProfile(name: "Source Agent", skills: ["swiftui"], maxConcurrentTasks: 2)
        let task = WorkTask(
            title: "Assigned shared task",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 2,
            status: .todo,
            assignedAgentID: agent.id
        )
        let viewModel = KanbanBoardViewModel(tasks: [task], agents: [agent])
        let sourceBoardID = viewModel.selectedBoardID
        _ = viewModel.createBoard(name: "Agentless Copy Target")
        let targetBoardID = viewModel.selectedBoardID
        _ = viewModel.switchBoard(to: sourceBoardID)

        let copied = viewModel.copyTask(task.id, toBoard: targetBoardID)

        #expect(copied)
        #expect(viewModel.tasks.first?.assignedAgentID == agent.id)

        let switched = viewModel.switchBoard(to: targetBoardID)
        #expect(switched)
        #expect(viewModel.tasks.count == 1)
        #expect(viewModel.tasks.first?.assignedAgentID == nil)
    }

    @Test("copying task to board with non-matching agents clears copied assignment")
    func copyingTaskToBoardWithNonMatchingAgentsClearsCopiedAssignment() {
        let sourceAgent = AgentProfile(name: "Source Agent", skills: ["swiftui"], maxConcurrentTasks: 2)
        let task = WorkTask(
            title: "Assigned shared task",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 2,
            status: .todo,
            assignedAgentID: sourceAgent.id
        )
        let viewModel = KanbanBoardViewModel(tasks: [task], agents: [sourceAgent])
        let sourceBoardID = viewModel.selectedBoardID
        _ = viewModel.createBoard(name: "Copy Target With Agents")
        _ = viewModel.addAgent(name: "Target Agent", skillsText: "swiftui", maxConcurrentTasks: 2)
        let targetBoardID = viewModel.selectedBoardID
        _ = viewModel.switchBoard(to: sourceBoardID)

        let copied = viewModel.copyTask(task.id, toBoard: targetBoardID)

        #expect(copied)
        _ = viewModel.switchBoard(to: targetBoardID)
        #expect(viewModel.tasks.first?.assignedAgentID == nil)
    }

    @Test("rejects copying task to the same board")
    func rejectsCopyingTaskToSameBoard() {
        let task = WorkTask(
            title: "Same board",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 1,
            status: .todo,
            assignedAgentID: nil
        )
        let store = SpyBoardStore()
        let viewModel = KanbanBoardViewModel(tasks: [task], agents: [], boardStore: store)

        let copied = viewModel.copyTask(task.id, toBoard: viewModel.selectedBoardID)

        #expect(!copied)
        #expect(viewModel.lastBoardMessage == "Select a different board")
        #expect(viewModel.tasks.count == 1)
        #expect(store.savedSnapshots.isEmpty)
    }

    @Test("rejects copying task to unknown board")
    func rejectsCopyingTaskToUnknownBoard() {
        let task = WorkTask(
            title: "Unknown target",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 1,
            status: .todo,
            assignedAgentID: nil
        )
        let viewModel = KanbanBoardViewModel(tasks: [task], agents: [])

        let copied = viewModel.copyTask(task.id, toBoard: UUID())

        #expect(!copied)
        #expect(viewModel.lastBoardMessage == "Board not found")
    }

    @Test("rejects copying missing task to another board")
    func rejectsCopyingMissingTaskToAnotherBoard() {
        let task = WorkTask(
            title: "Source task",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 1,
            status: .todo,
            assignedAgentID: nil
        )
        let viewModel = KanbanBoardViewModel(tasks: [task], agents: [])
        let sourceBoardID = viewModel.selectedBoardID
        _ = viewModel.createBoard(name: "Target Board")
        let targetBoardID = viewModel.selectedBoardID
        _ = viewModel.switchBoard(to: sourceBoardID)

        let copied = viewModel.copyTask(UUID(), toBoard: targetBoardID)

        #expect(!copied)
        #expect(viewModel.lastBoardMessage == "Task not found")
    }

    @Test("global task search finds tasks across boards with board metadata")
    func globalTaskSearchFindsTasksAcrossBoards() {
        let sourceTask = WorkTask(
            title: "Design Home",
            details: "",
            requiredSkills: ["ui"],
            storyPoints: 2,
            status: .todo,
            assignedAgentID: nil
        )
        let viewModel = KanbanBoardViewModel(tasks: [sourceTask], agents: [])
        _ = viewModel.createBoard(name: "Ops Board")
        _ = viewModel.addTask(
            title: "Incident Response",
            details: "Fix prod issue",
            requiredSkillsText: "ops",
            storyPoints: 3
        )

        let results = viewModel.globalTaskSearchResults(query: "incident")

        #expect(results.count == 1)
        #expect(results.first?.boardName == "Ops Board")
        #expect(results.first?.taskTitle == "Incident Response")
    }

    @Test("global task search results are sorted by board then task title")
    func globalTaskSearchSortsByBoardThenTitle() {
        let seedTask = WorkTask(
            title: "Seed",
            details: "crosssort",
            requiredSkills: ["swiftui"],
            storyPoints: 1,
            status: .todo,
            assignedAgentID: nil
        )
        let viewModel = KanbanBoardViewModel(tasks: [seedTask], agents: [])

        _ = viewModel.createBoard(name: "Beta")
        _ = viewModel.addTask(
            title: "Zulu Task",
            details: "crosssort",
            requiredSkillsText: "ops",
            storyPoints: 2
        )
        _ = viewModel.addTask(
            title: "Alpha Task",
            details: "crosssort",
            requiredSkillsText: "ops",
            storyPoints: 1
        )

        _ = viewModel.createBoard(name: "Alpha")
        _ = viewModel.addTask(
            title: "Gamma Task",
            details: "crosssort",
            requiredSkillsText: "ops",
            storyPoints: 1
        )

        let results = viewModel.globalTaskSearchResults(query: "crosssort task")

        let orderedLabels = results.map { "\($0.boardName)|\($0.taskTitle)" }
        #expect(orderedLabels == [
            "Alpha|Gamma Task",
            "Beta|Alpha Task",
            "Beta|Zulu Task"
        ])
    }

    @Test("global task search resolves assignee names from board agent directory")
    func globalTaskSearchResolvesAssigneeNamesFromBoardAgents() {
        let agent = AgentProfile(name: "Ops Agent", skills: ["ops"], maxConcurrentTasks: 2)
        let task = WorkTask(
            title: "Incident triage",
            details: "critical path",
            requiredSkills: ["ops"],
            storyPoints: 2,
            status: .todo,
            assignedAgentID: agent.id
        )
        let board = KanbanBoardRecord(name: "Ops", tasks: [task], agents: [agent], wipLimits: [.inProgress: 3, .review: 2])
        let snapshot = KanbanBoardSnapshot(
            tasks: board.tasks,
            agents: board.agents,
            wipLimits: board.wipLimits,
            boards: [board],
            selectedBoardID: board.id
        )
        let viewModel = KanbanBoardViewModel.persistentBoard(boardStore: SpyBoardStore(loadSnapshot: snapshot))

        let results = viewModel.globalTaskSearchResults(query: "ops agent")

        #expect(results.count == 1)
        #expect(results.first?.assigneeName == "Ops Agent")
    }

    @Test("open task switches board context and persists selection")
    func openTaskSwitchesBoardContextAndPersists() {
        let defaultTask = WorkTask(
            title: "Default Task",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 1,
            status: .todo,
            assignedAgentID: nil
        )
        let store = SpyBoardStore()
        let viewModel = KanbanBoardViewModel(tasks: [defaultTask], agents: [], boardStore: store)
        let defaultBoardID = viewModel.selectedBoardID
        _ = viewModel.createBoard(name: "Release Board")
        _ = viewModel.addTask(
            title: "Ship Candidate",
            details: "",
            requiredSkillsText: "release",
            storyPoints: 2
        )
        let targetBoardID = viewModel.selectedBoardID
        let targetTaskID = viewModel.tasks.first?.id
        _ = viewModel.switchBoard(to: defaultBoardID)

        #expect(targetTaskID != nil)
        guard let targetTaskID else { return }

        let opened = viewModel.openTask(targetTaskID, in: targetBoardID)

        #expect(opened)
        #expect(viewModel.selectedBoardID == targetBoardID)
        #expect(viewModel.tasks.contains(where: { $0.id == targetTaskID }))
        #expect(store.savedSnapshots.last?.selectedBoardID == targetBoardID)
    }

    @Test("open task rejects unknown board id")
    func openTaskRejectsUnknownBoardID() {
        let task = WorkTask(
            title: "Default Task",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 1,
            status: .todo,
            assignedAgentID: nil
        )
        let viewModel = KanbanBoardViewModel(tasks: [task], agents: [])

        let opened = viewModel.openTask(task.id, in: UUID())

        #expect(!opened)
        #expect(viewModel.lastBoardMessage == "Board not found")
    }

    @Test("open task rejects unknown task id in existing board")
    func openTaskRejectsUnknownTaskID() {
        let task = WorkTask(
            title: "Default Task",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 1,
            status: .todo,
            assignedAgentID: nil
        )
        let viewModel = KanbanBoardViewModel(tasks: [task], agents: [])

        let opened = viewModel.openTask(UUID(), in: viewModel.selectedBoardID)

        #expect(!opened)
        #expect(viewModel.lastBoardMessage == "Task not found")
    }

    @Test("open task on current board clears message without persisting selection")
    func openTaskOnCurrentBoardClearsMessageWithoutPersistingSelection() {
        let task = WorkTask(
            title: "Default Task",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 1,
            status: .todo,
            assignedAgentID: nil
        )
        let store = SpyBoardStore()
        let viewModel = KanbanBoardViewModel(tasks: [task], agents: [], boardStore: store)
        _ = viewModel.openTask(UUID(), in: viewModel.selectedBoardID)

        let opened = viewModel.openTask(task.id, in: viewModel.selectedBoardID)

        #expect(opened)
        #expect(viewModel.lastBoardMessage == nil)
        #expect(store.savedSnapshots.isEmpty)
    }

    @Test("exports workspace snapshot JSON including multi-board metadata")
    func exportsWorkspaceSnapshotJSON() throws {
        let seedTask = WorkTask(
            title: "Seed",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 1,
            status: .todo,
            assignedAgentID: nil
        )
        let viewModel = KanbanBoardViewModel(tasks: [seedTask], agents: [])
        _ = viewModel.createBoard(name: "Ops Board")

        let exported = viewModel.workspaceExportData()

        #expect(exported != nil)
        guard let exported else { return }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let snapshot = try decoder.decode(KanbanBoardSnapshot.self, from: exported)
        #expect(snapshot.boards?.count == 2)
        #expect(snapshot.selectedBoardID == viewModel.selectedBoardID)
    }

    @Test("exports selected board snapshot JSON only")
    func exportsSelectedBoardSnapshotJSON() throws {
        let seedTask = WorkTask(
            title: "Seed",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 1,
            status: .todo,
            assignedAgentID: nil
        )
        let viewModel = KanbanBoardViewModel(tasks: [seedTask], agents: [])
        _ = viewModel.createBoard(name: "Ops Board")
        _ = viewModel.addTask(
            title: "Ops Task",
            details: "Board-specific",
            requiredSkillsText: "ops",
            storyPoints: 2
        )
        let selectedBoardID = viewModel.selectedBoardID

        let exported = viewModel.selectedBoardExportData()

        #expect(exported != nil)
        guard let exported else { return }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let snapshot = try decoder.decode(KanbanBoardSnapshot.self, from: exported)
        #expect(snapshot.boards?.count == 1)
        #expect(snapshot.boards?.first?.id == selectedBoardID)
        #expect(snapshot.selectedBoardID == selectedBoardID)
    }

    @Test("imports workspace snapshot and persists board selection")
    func importsWorkspaceSnapshotAndPersistsSelection() throws {
        let deliveryTask = WorkTask(
            title: "Delivery",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 2,
            status: .todo,
            assignedAgentID: nil
        )
        let qaTask = WorkTask(
            title: "QA",
            details: "",
            requiredSkills: ["testing"],
            storyPoints: 2,
            status: .review,
            assignedAgentID: nil
        )
        let deliveryBoard = KanbanBoardRecord(name: "Delivery", tasks: [deliveryTask], agents: [], wipLimits: [.inProgress: 3, .review: 2])
        let qaBoard = KanbanBoardRecord(name: "QA", tasks: [qaTask], agents: [], wipLimits: [.inProgress: 2, .review: 1])
        let snapshot = KanbanBoardSnapshot(
            tasks: deliveryBoard.tasks,
            agents: deliveryBoard.agents,
            wipLimits: deliveryBoard.wipLimits,
            boards: [deliveryBoard, qaBoard],
            selectedBoardID: qaBoard.id
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .secondsSince1970
        let data = try encoder.encode(snapshot)

        let store = SpyBoardStore()
        let viewModel = KanbanBoardViewModel(tasks: [], agents: [], boardStore: store)

        let imported = viewModel.importWorkspaceData(data)

        #expect(imported)
        #expect(viewModel.boards.count == 2)
        #expect(viewModel.selectedBoardID == qaBoard.id)
        #expect(viewModel.selectedBoardName == "QA")
        #expect(viewModel.tasks.first?.title == "QA")
        #expect(store.savedSnapshots.last?.selectedBoardID == qaBoard.id)
    }

    @Test("replace import falls back to first board when selected board id is missing")
    func replaceImportFallsBackToFirstBoardWhenSelectedIDMissing() throws {
        let boardA = KanbanBoardRecord(name: "Board A")
        let boardB = KanbanBoardRecord(name: "Board B")
        let snapshot = KanbanBoardSnapshot(
            tasks: boardA.tasks,
            agents: boardA.agents,
            wipLimits: boardA.wipLimits,
            boards: [boardA, boardB],
            selectedBoardID: UUID()
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .secondsSince1970
        let data = try encoder.encode(snapshot)

        let viewModel = KanbanBoardViewModel(tasks: [], agents: [])
        let imported = viewModel.importWorkspaceData(data, strategy: .replace)

        #expect(imported)
        #expect(viewModel.selectedBoardID == boardA.id)
    }

    @Test("replace import supports legacy snapshot without boards array")
    func replaceImportSupportsLegacySnapshotWithoutBoardsArray() throws {
        let legacyTask = WorkTask(
            title: "Legacy task",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 1,
            status: .todo,
            assignedAgentID: nil
        )
        let legacyAgent = AgentProfile(name: "Legacy Agent", skills: ["swiftui"], maxConcurrentTasks: 2)
        let legacySnapshot = KanbanBoardSnapshot(
            tasks: [legacyTask],
            agents: [legacyAgent],
            wipLimits: [.inProgress: 3, .review: 2]
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .secondsSince1970
        let data = try encoder.encode(legacySnapshot)

        let viewModel = KanbanBoardViewModel(tasks: [], agents: [])
        let imported = viewModel.importWorkspaceData(data, strategy: .replace)

        #expect(imported)
        #expect(viewModel.boards.count == 1)
        #expect(viewModel.selectedBoardName == "Default Board")
        #expect(viewModel.tasks.count == 1)
        #expect(viewModel.tasks.first?.title == "Legacy task")
    }

    @Test("imports workspace snapshot with duplicate board names and resolves collisions")
    func importsWorkspaceSnapshotWithDuplicateBoardNames() throws {
        let firstBoard = KanbanBoardRecord(name: "Ops", tasks: [], agents: [], wipLimits: [.inProgress: 3, .review: 2])
        let secondBoard = KanbanBoardRecord(name: "Ops", tasks: [], agents: [], wipLimits: [.inProgress: 2, .review: 1])
        let snapshot = KanbanBoardSnapshot(
            tasks: firstBoard.tasks,
            agents: firstBoard.agents,
            wipLimits: firstBoard.wipLimits,
            boards: [firstBoard, secondBoard],
            selectedBoardID: secondBoard.id
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .secondsSince1970
        let data = try encoder.encode(snapshot)

        let viewModel = KanbanBoardViewModel(tasks: [], agents: [])
        let imported = viewModel.importWorkspaceData(data)

        #expect(imported)
        #expect(viewModel.boards.count == 2)
        #expect(viewModel.boards.map(\.name) == ["Ops", "Ops (2)"])
    }

    @Test("imports workspace snapshot and unassigns tasks with unknown agents")
    func importsWorkspaceSnapshotUnassignsUnknownAgents() throws {
        let unknownAgentID = UUID()
        let task = WorkTask(
            title: "Orphan Assignment",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 1,
            status: .todo,
            assignedAgentID: unknownAgentID
        )
        let validAgent = AgentProfile(name: "Valid Agent", skills: ["swiftui"], maxConcurrentTasks: 2)
        let board = KanbanBoardRecord(
            name: "Import Board",
            tasks: [task],
            agents: [validAgent],
            wipLimits: [.inProgress: 3, .review: 2]
        )
        let snapshot = KanbanBoardSnapshot(
            tasks: board.tasks,
            agents: board.agents,
            wipLimits: board.wipLimits,
            boards: [board],
            selectedBoardID: board.id
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .secondsSince1970
        let data = try encoder.encode(snapshot)

        let viewModel = KanbanBoardViewModel(tasks: [], agents: [])
        let imported = viewModel.importWorkspaceData(data)

        #expect(imported)
        #expect(viewModel.tasks.count == 1)
        #expect(viewModel.tasks[0].assignedAgentID == nil)
    }

    @Test("merges workspace snapshot without replacing existing boards")
    func mergesWorkspaceSnapshotWithoutReplacingExistingBoards() throws {
        let viewModel = KanbanBoardViewModel(tasks: [], agents: [])
        _ = viewModel.createBoard(name: "Local Board")

        let importedTask = WorkTask(
            title: "Imported Task",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 1,
            status: .todo,
            assignedAgentID: nil
        )
        let importedBoard = KanbanBoardRecord(
            name: "Imported Board",
            tasks: [importedTask],
            agents: [],
            wipLimits: [.inProgress: 3, .review: 2]
        )
        let snapshot = KanbanBoardSnapshot(
            tasks: importedBoard.tasks,
            agents: importedBoard.agents,
            wipLimits: importedBoard.wipLimits,
            boards: [importedBoard],
            selectedBoardID: importedBoard.id
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .secondsSince1970
        let data = try encoder.encode(snapshot)

        let imported = viewModel.importWorkspaceData(data, strategy: .merge)

        #expect(imported)
        #expect(viewModel.boards.count == 3)
        #expect(viewModel.boards.contains(where: { $0.name == "Local Board" }))
        #expect(viewModel.boards.contains(where: { $0.name == "Imported Board" }))
        #expect(viewModel.selectedBoardID == importedBoard.id)
        #expect(viewModel.tasks.first?.title == "Imported Task")
    }

    @Test("merge import resolves imported board names against existing boards")
    func mergeImportResolvesImportedBoardNamesAgainstExistingBoards() throws {
        let viewModel = KanbanBoardViewModel(tasks: [], agents: [])
        _ = viewModel.createBoard(name: "Ops")

        let importedBoard = KanbanBoardRecord(name: "Ops", tasks: [], agents: [], wipLimits: [.inProgress: 2, .review: 1])
        let snapshot = KanbanBoardSnapshot(
            tasks: importedBoard.tasks,
            agents: importedBoard.agents,
            wipLimits: importedBoard.wipLimits,
            boards: [importedBoard],
            selectedBoardID: importedBoard.id
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .secondsSince1970
        let data = try encoder.encode(snapshot)

        let imported = viewModel.importWorkspaceData(data, strategy: .merge)

        #expect(imported)
        #expect(viewModel.boards.contains(where: { $0.name == "Ops" }))
        #expect(viewModel.boards.contains(where: { $0.name == "Ops (2)" }))
    }

    @Test("merge import keeps current selection when imported selected id is missing")
    func mergeImportKeepsCurrentSelectionWhenImportedSelectedIDMissing() throws {
        let localTask = WorkTask(
            title: "Local Task",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 1,
            status: .todo,
            assignedAgentID: nil
        )
        let viewModel = KanbanBoardViewModel(tasks: [localTask], agents: [])
        let currentSelectedBoardID = viewModel.selectedBoardID

        let importedBoard = KanbanBoardRecord(name: "Imported", tasks: [], agents: [], wipLimits: [.inProgress: 2, .review: 1])
        let snapshot = KanbanBoardSnapshot(
            tasks: importedBoard.tasks,
            agents: importedBoard.agents,
            wipLimits: importedBoard.wipLimits,
            boards: [importedBoard],
            selectedBoardID: UUID()
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .secondsSince1970
        let data = try encoder.encode(snapshot)

        let imported = viewModel.importWorkspaceData(data, strategy: .merge)

        #expect(imported)
        #expect(viewModel.selectedBoardID == currentSelectedBoardID)
    }

    @Test("merge import supports legacy snapshot and appends normalized board")
    func mergeImportSupportsLegacySnapshotWithoutBoardsArray() throws {
        let existingTask = WorkTask(
            title: "Existing task",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 1,
            status: .todo,
            assignedAgentID: nil
        )
        let legacyTask = WorkTask(
            title: "Imported legacy task",
            details: "",
            requiredSkills: ["testing"],
            storyPoints: 2,
            status: .review,
            assignedAgentID: nil
        )
        let legacySnapshot = KanbanBoardSnapshot(
            tasks: [legacyTask],
            agents: [],
            wipLimits: [.inProgress: 4, .review: 3]
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .secondsSince1970
        let data = try encoder.encode(legacySnapshot)

        let viewModel = KanbanBoardViewModel(tasks: [existingTask], agents: [])
        let initialBoardCount = viewModel.boards.count
        let imported = viewModel.importWorkspaceData(data, strategy: .merge)

        #expect(imported)
        #expect(viewModel.boards.count == initialBoardCount + 1)
        #expect(viewModel.boards.contains(where: { $0.name == "Default Board (2)" }))
    }

    @Test("builds workspace import preview counts from snapshot data")
    func buildsWorkspaceImportPreviewCounts() throws {
        let taskA = WorkTask(
            title: "Task A",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 1,
            status: .todo,
            assignedAgentID: nil
        )
        let taskB = WorkTask(
            title: "Task B",
            details: "",
            requiredSkills: ["testing"],
            storyPoints: 2,
            status: .review,
            assignedAgentID: nil
        )
        let agentA = AgentProfile(name: "Agent A", skills: ["swiftui"], maxConcurrentTasks: 2)
        let boardA = KanbanBoardRecord(name: "Board A", tasks: [taskA], agents: [agentA], wipLimits: [.inProgress: 3, .review: 2])
        let boardB = KanbanBoardRecord(name: "Board B", tasks: [taskB], agents: [], wipLimits: [.inProgress: 2, .review: 1])
        let snapshot = KanbanBoardSnapshot(
            tasks: boardA.tasks,
            agents: boardA.agents,
            wipLimits: boardA.wipLimits,
            boards: [boardA, boardB],
            selectedBoardID: boardB.id
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .secondsSince1970
        let data = try encoder.encode(snapshot)

        let viewModel = KanbanBoardViewModel(tasks: [], agents: [])
        let preview = viewModel.workspaceImportPreview(from: data)

        #expect(preview != nil)
        #expect(preview?.boardCount == 2)
        #expect(preview?.taskCount == 2)
        #expect(preview?.agentCount == 1)
    }

    @Test("workspace import preview rejects invalid JSON")
    func workspaceImportPreviewRejectsInvalidJSON() {
        let viewModel = KanbanBoardViewModel(tasks: [], agents: [])
        let invalidData = Data("not-valid-json".utf8)

        let preview = viewModel.workspaceImportPreview(from: invalidData)

        #expect(preview == nil)
        #expect(viewModel.lastBoardMessage == "Invalid workspace JSON")
    }

    @Test("workspace import preview supports legacy snapshots without boards array")
    func workspaceImportPreviewSupportsLegacySnapshotWithoutBoards() throws {
        let legacyTask = WorkTask(
            title: "Legacy Task",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 2,
            status: .todo,
            assignedAgentID: nil
        )
        let legacyAgent = AgentProfile(name: "Legacy Agent", skills: ["swiftui"], maxConcurrentTasks: 2)
        let legacySnapshot = KanbanBoardSnapshot(
            tasks: [legacyTask],
            agents: [legacyAgent],
            wipLimits: [.inProgress: 3, .review: 2]
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .secondsSince1970
        let data = try encoder.encode(legacySnapshot)
        let viewModel = KanbanBoardViewModel(tasks: [], agents: [])

        let preview = viewModel.workspaceImportPreview(from: data)

        #expect(preview?.boardCount == 1)
        #expect(preview?.taskCount == 1)
        #expect(preview?.agentCount == 1)
    }

    @Test("rejects invalid workspace JSON import")
    func rejectsInvalidWorkspaceImport() {
        let viewModel = KanbanBoardViewModel(tasks: [], agents: [])
        let invalidData = Data("not-valid-json".utf8)

        let imported = viewModel.importWorkspaceData(invalidData)

        #expect(!imported)
        #expect(viewModel.lastBoardMessage == "Invalid workspace JSON")
    }

    @Test("exports workspace snapshot to JSON file URL")
    func exportsWorkspaceSnapshotToFileURL() throws {
        let workspaceURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("openmac-workspace.json")
        defer { try? FileManager.default.removeItem(at: workspaceURL.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(
            at: workspaceURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let task = WorkTask(
            title: "Seed",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 1,
            status: .todo,
            assignedAgentID: nil
        )
        let viewModel = KanbanBoardViewModel(tasks: [task], agents: [])
        _ = viewModel.createBoard(name: "Ops Board")

        let exported = viewModel.exportWorkspace(to: workspaceURL)

        #expect(exported)
        let exportedData = try Data(contentsOf: workspaceURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let snapshot = try decoder.decode(KanbanBoardSnapshot.self, from: exportedData)
        #expect(snapshot.boards?.count == 2)
        #expect(viewModel.lastBoardMessageSeverity == .info)
    }

    @Test("exports selected board snapshot to JSON file URL")
    func exportsSelectedBoardSnapshotToFileURL() throws {
        let workspaceURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("openmac-board.json")
        defer { try? FileManager.default.removeItem(at: workspaceURL.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(
            at: workspaceURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let task = WorkTask(
            title: "Seed",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 1,
            status: .todo,
            assignedAgentID: nil
        )
        let viewModel = KanbanBoardViewModel(tasks: [task], agents: [])

        let exported = viewModel.exportSelectedBoard(to: workspaceURL)

        #expect(exported)
        let exportedData = try Data(contentsOf: workspaceURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let snapshot = try decoder.decode(KanbanBoardSnapshot.self, from: exportedData)
        #expect(snapshot.boards?.count == 1)
        #expect(snapshot.selectedBoardID == viewModel.selectedBoardID)
    }

    @Test("imports workspace snapshot from JSON file URL")
    func importsWorkspaceSnapshotFromFileURL() throws {
        let workspaceURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("openmac-workspace.json")
        defer { try? FileManager.default.removeItem(at: workspaceURL.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(
            at: workspaceURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let deliveryTask = WorkTask(
            title: "Delivery",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 2,
            status: .todo,
            assignedAgentID: nil
        )
        let qaTask = WorkTask(
            title: "QA",
            details: "",
            requiredSkills: ["testing"],
            storyPoints: 2,
            status: .review,
            assignedAgentID: nil
        )
        let deliveryBoard = KanbanBoardRecord(name: "Delivery", tasks: [deliveryTask], agents: [], wipLimits: [.inProgress: 3, .review: 2])
        let qaBoard = KanbanBoardRecord(name: "QA", tasks: [qaTask], agents: [], wipLimits: [.inProgress: 2, .review: 1])
        let snapshot = KanbanBoardSnapshot(
            tasks: deliveryBoard.tasks,
            agents: deliveryBoard.agents,
            wipLimits: deliveryBoard.wipLimits,
            boards: [deliveryBoard, qaBoard],
            selectedBoardID: qaBoard.id
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .secondsSince1970
        let data = try encoder.encode(snapshot)
        try data.write(to: workspaceURL, options: .atomic)

        let viewModel = KanbanBoardViewModel(tasks: [], agents: [])

        let imported = viewModel.importWorkspace(from: workspaceURL)

        #expect(imported)
        #expect(viewModel.boards.count == 2)
        #expect(viewModel.selectedBoardID == qaBoard.id)
        #expect(viewModel.lastBoardMessageSeverity == .info)
    }

    @Test("rejects workspace import when file URL cannot be read")
    func rejectsWorkspaceImportWhenFileCannotBeRead() {
        let missingURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("missing-workspace.json")
        let viewModel = KanbanBoardViewModel(tasks: [], agents: [])

        let imported = viewModel.importWorkspace(from: missingURL)

        #expect(!imported)
        #expect(viewModel.lastBoardMessage == "Failed to read workspace file")
    }

    @Test("rejects workspace export when file URL cannot be written")
    func rejectsWorkspaceExportWhenFileCannotBeWritten() throws {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directoryURL) }
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        let viewModel = KanbanBoardViewModel(tasks: [], agents: [])

        let exported = viewModel.exportWorkspace(to: directoryURL)

        #expect(!exported)
        #expect(viewModel.lastBoardMessage == "Failed to write workspace file")
    }

    @Test("file store saves and loads snapshot round trip")
    func fileStoreRoundTrip() throws {
        let directoryURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directoryURL) }
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        let fileURL = directoryURL.appendingPathComponent("kanban-board.json")
        let task = WorkTask(
            title: "Round trip",
            details: "Verify disk persistence",
            requiredSkills: ["swift"],
            storyPoints: 3,
            status: .todo,
            assignedAgentID: nil
        )
        let agent = AgentProfile(name: "Disk Agent", skills: ["swift"], maxConcurrentTasks: 2)
        let snapshot = KanbanBoardSnapshot(
            tasks: [task],
            agents: [agent],
            wipLimits: [.inProgress: 2]
        )

        let store = FileKanbanBoardStore(fileURL: fileURL)
        try store.save(snapshot)

        let loaded = try store.load()
        #expect(loaded?.agents == snapshot.agents)
        #expect(loaded?.wipLimits == snapshot.wipLimits)
        #expect(loaded?.tasks.count == snapshot.tasks.count)

        let loadedTask = loaded?.tasks.first
        let snapshotTask = snapshot.tasks.first
        #expect(loadedTask?.id == snapshotTask?.id)
        #expect(loadedTask?.title == snapshotTask?.title)
        #expect(loadedTask?.details == snapshotTask?.details)
        #expect(loadedTask?.requiredSkills == snapshotTask?.requiredSkills)
        #expect(loadedTask?.storyPoints == snapshotTask?.storyPoints)
        #expect(loadedTask?.status == snapshotTask?.status)
        #expect(loadedTask?.assignedAgentID == snapshotTask?.assignedAgentID)
        #expect(abs((loadedTask?.createdAt.timeIntervalSince(snapshotTask?.createdAt ?? .distantPast) ?? 1)) < 0.01)
    }

    @Test("file store load returns nil when snapshot file is missing")
    func fileStoreLoadReturnsNilWhenSnapshotFileIsMissing() throws {
        let directoryURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directoryURL) }
        let fileURL = directoryURL.appendingPathComponent("missing-board.json")
        let store = FileKanbanBoardStore(fileURL: fileURL)

        let loaded = try store.load()

        #expect(loaded == nil)
    }

    @Test("agentName resolves unassigned, known, and unknown ids")
    func agentNameResolvesKnownUnknownAndUnassigned() {
        let agent = AgentProfile(name: "Known Agent", skills: ["swiftui"], maxConcurrentTasks: 2)
        let viewModel = KanbanBoardViewModel(tasks: [], agents: [agent])

        #expect(viewModel.agentName(for: nil) == "Unassigned")
        #expect(viewModel.agentName(for: agent.id) == "Known Agent")
        #expect(viewModel.agentName(for: UUID()) == "Unknown")
    }

    @Test("updates WIP limit and persists new board snapshot")
    func updatesWIPLimitAndPersists() {
        let task = WorkTask(
            title: "Active task",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 2,
            status: .inProgress,
            assignedAgentID: nil
        )
        let store = SpyBoardStore()
        let viewModel = KanbanBoardViewModel(
            tasks: [task],
            agents: [],
            wipLimits: [.inProgress: 3],
            boardStore: store
        )

        let updated = viewModel.updateWIPLimit(for: .inProgress, limit: 4)

        #expect(updated)
        #expect(viewModel.wipLimit(for: .inProgress) == 4)
        #expect(store.savedSnapshots.count == 1)
        #expect(store.savedSnapshots.last?.wipLimits[.inProgress] == 4)
    }

    @Test("rejects WIP limit lower than current task count in that column")
    func rejectsWIPLimitLowerThanCurrentCount() {
        let reviewTask1 = WorkTask(
            title: "Review A",
            details: "",
            requiredSkills: ["testing"],
            storyPoints: 1,
            status: .review,
            assignedAgentID: nil
        )
        let reviewTask2 = WorkTask(
            title: "Review B",
            details: "",
            requiredSkills: ["testing"],
            storyPoints: 1,
            status: .review,
            assignedAgentID: nil
        )
        let store = SpyBoardStore()
        let viewModel = KanbanBoardViewModel(
            tasks: [reviewTask1, reviewTask2],
            agents: [],
            wipLimits: [.review: 3],
            boardStore: store
        )

        let updated = viewModel.updateWIPLimit(for: .review, limit: 1)

        #expect(!updated)
        #expect(viewModel.wipLimit(for: .review) == 3)
        #expect(viewModel.lastBoardMessage == "Cannot set Review WIP below current count (2)")
        #expect(store.savedSnapshots.isEmpty)
    }

    @Test("updates multiple WIP limits atomically and persists once")
    func updatesMultipleWIPLimitsAtomically() {
        let inProgressTask = WorkTask(
            title: "In progress",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 2,
            status: .inProgress,
            assignedAgentID: nil
        )
        let reviewTask = WorkTask(
            title: "Review",
            details: "",
            requiredSkills: ["testing"],
            storyPoints: 1,
            status: .review,
            assignedAgentID: nil
        )
        let store = SpyBoardStore()
        let viewModel = KanbanBoardViewModel(
            tasks: [inProgressTask, reviewTask],
            agents: [],
            wipLimits: [.inProgress: 3, .review: 2],
            boardStore: store
        )

        let updated = viewModel.updateWIPLimits([.inProgress: 4, .review: 5])

        #expect(updated)
        #expect(viewModel.wipLimit(for: .inProgress) == 4)
        #expect(viewModel.wipLimit(for: .review) == 5)
        #expect(store.savedSnapshots.count == 1)
    }

    @Test("does not partially apply WIP changes when one update is invalid")
    func rejectsBatchWIPUpdateWithoutPartialMutation() {
        let reviewTask1 = WorkTask(
            title: "Review 1",
            details: "",
            requiredSkills: ["testing"],
            storyPoints: 1,
            status: .review,
            assignedAgentID: nil
        )
        let reviewTask2 = WorkTask(
            title: "Review 2",
            details: "",
            requiredSkills: ["testing"],
            storyPoints: 1,
            status: .review,
            assignedAgentID: nil
        )
        let store = SpyBoardStore()
        let viewModel = KanbanBoardViewModel(
            tasks: [reviewTask1, reviewTask2],
            agents: [],
            wipLimits: [.inProgress: 3, .review: 3],
            boardStore: store
        )

        let updated = viewModel.updateWIPLimits([.inProgress: 5, .review: 1])

        #expect(!updated)
        #expect(viewModel.wipLimit(for: .inProgress) == 3)
        #expect(viewModel.wipLimit(for: .review) == 3)
        #expect(viewModel.lastBoardMessage == "Cannot set Review WIP below current count (2)")
        #expect(store.savedSnapshots.isEmpty)
    }

    @Test("manually assigns triage task to a valid agent and persists")
    func manuallyAssignsTriageTaskAndPersists() {
        let task = WorkTask(
            title: "Unassigned task",
            details: "Need manual help",
            requiredSkills: ["swiftui"],
            storyPoints: 2,
            status: .todo,
            assignedAgentID: nil
        )
        let unmatchedAgent = AgentProfile(name: "Backend Agent", skills: ["api"], maxConcurrentTasks: 2)
        let triageAgent = AgentProfile(name: "UI Agent", skills: ["swiftui", "ui"], maxConcurrentTasks: 2)
        let store = SpyBoardStore()
        let viewModel = KanbanBoardViewModel(tasks: [task], agents: [unmatchedAgent], boardStore: store)

        viewModel.autoAssignTasks()
        #expect(viewModel.lastUnassignedTaskIDs.contains(task.id))

        viewModel.agents.append(triageAgent)
        let assigned = viewModel.manuallyAssignTask(task.id, to: triageAgent.id)

        #expect(assigned)
        #expect(viewModel.tasks.first?.assignedAgentID == triageAgent.id)
        #expect(!viewModel.lastUnassignedTaskIDs.contains(task.id))
        #expect(viewModel.assignmentReason(for: task.id)?.contains("manual[UI Agent]") == true)
        #expect(store.savedSnapshots.count == 2)
    }

    @Test("rejects manual triage when agent lacks required skills")
    func rejectsManualTriageForSkillMismatch() {
        let task = WorkTask(
            title: "ML task",
            details: "",
            requiredSkills: ["ml"],
            storyPoints: 3,
            status: .todo,
            assignedAgentID: nil
        )
        let agent = AgentProfile(name: "Frontend Agent", skills: ["swiftui"], maxConcurrentTasks: 2)
        let store = SpyBoardStore()
        let viewModel = KanbanBoardViewModel(tasks: [task], agents: [agent], boardStore: store)

        let assigned = viewModel.manuallyAssignTask(task.id, to: agent.id)

        #expect(!assigned)
        #expect(viewModel.tasks.first?.assignedAgentID == nil)
        #expect(viewModel.lastBoardMessage == "Agent Frontend Agent does not match required skills")
        #expect(store.savedSnapshots.isEmpty)
    }

    @Test("rejects manual triage when agent is already at max load")
    func rejectsManualTriageForOverloadedAgent() {
        let overloadedAgent = AgentProfile(name: "Busy Agent", skills: ["swiftui"], maxConcurrentTasks: 1)
        let activeTask = WorkTask(
            title: "Already active",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 2,
            status: .inProgress,
            assignedAgentID: overloadedAgent.id
        )
        let todoTask = WorkTask(
            title: "Need assignment",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 1,
            status: .todo,
            assignedAgentID: nil
        )
        let store = SpyBoardStore()
        let viewModel = KanbanBoardViewModel(
            tasks: [activeTask, todoTask],
            agents: [overloadedAgent],
            boardStore: store
        )

        let assigned = viewModel.manuallyAssignTask(todoTask.id, to: overloadedAgent.id)

        #expect(!assigned)
        #expect(viewModel.tasks.first(where: { $0.id == todoTask.id })?.assignedAgentID == nil)
        #expect(viewModel.lastBoardMessage == "Agent Busy Agent is at max load (1)")
        #expect(store.savedSnapshots.isEmpty)
    }

    @Test("rejects manual triage when task is not in To Do")
    func rejectsManualTriageForNonTodoTask() {
        let agent = AgentProfile(name: "Executor", skills: ["swiftui"], maxConcurrentTasks: 2)
        let task = WorkTask(
            title: "Review task",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 1,
            status: .review,
            assignedAgentID: nil
        )
        let viewModel = KanbanBoardViewModel(tasks: [task], agents: [agent])

        let assigned = viewModel.manuallyAssignTask(task.id, to: agent.id)

        #expect(!assigned)
        #expect(viewModel.lastBoardMessage == "Only To Do tasks can be manually triaged")
    }

    @Test("rejects manual triage when task is already assigned")
    func rejectsManualTriageForAlreadyAssignedTask() {
        let sourceAgent = AgentProfile(name: "Source Agent", skills: ["swiftui"], maxConcurrentTasks: 2)
        let targetAgent = AgentProfile(name: "Target Agent", skills: ["swiftui"], maxConcurrentTasks: 2)
        let task = WorkTask(
            title: "Already assigned",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 1,
            status: .todo,
            assignedAgentID: sourceAgent.id
        )
        let viewModel = KanbanBoardViewModel(tasks: [task], agents: [sourceAgent, targetAgent])

        let assigned = viewModel.manuallyAssignTask(task.id, to: targetAgent.id)

        #expect(!assigned)
        #expect(viewModel.lastBoardMessage == "Task is already assigned")
    }

    @Test("reassigns todo task to another eligible agent and persists")
    func reassignsTodoTaskToAnotherEligibleAgent() {
        let sourceAgent = AgentProfile(name: "Source Agent", skills: ["swiftui"], maxConcurrentTasks: 2)
        let targetAgent = AgentProfile(name: "Target Agent", skills: ["swiftui"], maxConcurrentTasks: 2)
        let task = WorkTask(
            title: "Assigned task",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 2,
            status: .todo,
            assignedAgentID: sourceAgent.id
        )
        let store = SpyBoardStore()
        let viewModel = KanbanBoardViewModel(tasks: [task], agents: [sourceAgent, targetAgent], boardStore: store)

        let reassigned = viewModel.reassignTask(task.id, to: targetAgent.id)

        #expect(reassigned)
        #expect(viewModel.tasks.first?.assignedAgentID == targetAgent.id)
        #expect(viewModel.assignmentReason(for: task.id)?.contains("manual[Target Agent]") == true)
        #expect(store.savedSnapshots.count == 1)
    }

    @Test("rejects reassignment when target agent is already at max load")
    func rejectsReassigningTaskForOverloadedAgent() {
        let sourceAgent = AgentProfile(name: "Source Agent", skills: ["swiftui"], maxConcurrentTasks: 2)
        let overloadedAgent = AgentProfile(name: "Busy Agent", skills: ["swiftui"], maxConcurrentTasks: 1)
        let alreadyAssigned = WorkTask(
            title: "Already active",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 2,
            status: .inProgress,
            assignedAgentID: overloadedAgent.id
        )
        let targetTask = WorkTask(
            title: "Need move",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 1,
            status: .todo,
            assignedAgentID: sourceAgent.id
        )
        let store = SpyBoardStore()
        let viewModel = KanbanBoardViewModel(
            tasks: [alreadyAssigned, targetTask],
            agents: [sourceAgent, overloadedAgent],
            boardStore: store
        )

        let reassigned = viewModel.reassignTask(targetTask.id, to: overloadedAgent.id)

        #expect(!reassigned)
        #expect(viewModel.tasks.first(where: { $0.id == targetTask.id })?.assignedAgentID == sourceAgent.id)
        #expect(viewModel.lastBoardMessage == "Agent Busy Agent is at max load (1)")
        #expect(store.savedSnapshots.isEmpty)
    }

    @Test("rejects reassigning when task is currently unassigned")
    func rejectsReassigningUnassignedTask() {
        let targetAgent = AgentProfile(name: "Target Agent", skills: ["swiftui"], maxConcurrentTasks: 2)
        let task = WorkTask(
            title: "Unassigned task",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 1,
            status: .todo,
            assignedAgentID: nil
        )
        let viewModel = KanbanBoardViewModel(tasks: [task], agents: [targetAgent])

        let reassigned = viewModel.reassignTask(task.id, to: targetAgent.id)

        #expect(!reassigned)
        #expect(viewModel.lastBoardMessage == "Task is unassigned")
    }

    @Test("rejects reassigning when target agent is current assignee")
    func rejectsReassigningToCurrentAssignee() {
        let sourceAgent = AgentProfile(name: "Source Agent", skills: ["swiftui"], maxConcurrentTasks: 2)
        let task = WorkTask(
            title: "Assigned task",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 1,
            status: .todo,
            assignedAgentID: sourceAgent.id
        )
        let viewModel = KanbanBoardViewModel(tasks: [task], agents: [sourceAgent])

        let reassigned = viewModel.reassignTask(task.id, to: sourceAgent.id)

        #expect(!reassigned)
        #expect(viewModel.lastBoardMessage == "Task already assigned to Source Agent")
    }

    @Test("rejects reassigning when task status is not To Do")
    func rejectsReassigningNonTodoTask() {
        let sourceAgent = AgentProfile(name: "Source Agent", skills: ["swiftui"], maxConcurrentTasks: 2)
        let targetAgent = AgentProfile(name: "Target Agent", skills: ["swiftui"], maxConcurrentTasks: 2)
        let task = WorkTask(
            title: "In-progress task",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 1,
            status: .inProgress,
            assignedAgentID: sourceAgent.id
        )
        let viewModel = KanbanBoardViewModel(tasks: [task], agents: [sourceAgent, targetAgent])

        let reassigned = viewModel.reassignTask(task.id, to: targetAgent.id)

        #expect(!reassigned)
        #expect(viewModel.lastBoardMessage == "Only To Do tasks can be reassigned")
    }

    @Test("rejects reassigning when target agent lacks required skills")
    func rejectsReassigningForSkillMismatch() {
        let sourceAgent = AgentProfile(name: "Source Agent", skills: ["swiftui"], maxConcurrentTasks: 2)
        let targetAgent = AgentProfile(name: "Target Agent", skills: ["backend"], maxConcurrentTasks: 2)
        let task = WorkTask(
            title: "Assigned task",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 1,
            status: .todo,
            assignedAgentID: sourceAgent.id
        )
        let viewModel = KanbanBoardViewModel(tasks: [task], agents: [sourceAgent, targetAgent])

        let reassigned = viewModel.reassignTask(task.id, to: targetAgent.id)

        #expect(!reassigned)
        #expect(viewModel.lastBoardMessage == "Agent Target Agent does not match required skills")
    }

    @Test("reassignable agents list excludes current assignee and overloaded candidates")
    func reassignableAgentsExcludeCurrentAndOverloadedAgents() {
        let sourceAgent = AgentProfile(name: "Source Agent", skills: ["swiftui"], maxConcurrentTasks: 3)
        let eligibleAgent = AgentProfile(name: "Eligible Agent", skills: ["swiftui"], maxConcurrentTasks: 2)
        let overloadedAgent = AgentProfile(name: "Overloaded Agent", skills: ["swiftui"], maxConcurrentTasks: 1)
        let supportingTask = WorkTask(
            title: "Busy",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 1,
            status: .inProgress,
            assignedAgentID: overloadedAgent.id
        )
        let assignedTask = WorkTask(
            title: "To reassign",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 1,
            status: .todo,
            assignedAgentID: sourceAgent.id
        )
        let viewModel = KanbanBoardViewModel(
            tasks: [supportingTask, assignedTask],
            agents: [sourceAgent, overloadedAgent, eligibleAgent]
        )

        let candidates = viewModel.reassignableAgents(for: assignedTask.id)

        #expect(candidates.map(\.id) == [eligibleAgent.id])
    }

    @Test("assignable agents are ordered by load then name")
    func assignableAgentsAreOrderedByLoadThenName() {
        let task = WorkTask(
            title: "Triage target",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 2,
            status: .todo,
            assignedAgentID: nil
        )
        let alpha = AgentProfile(name: "Alpha", skills: ["swiftui"], maxConcurrentTasks: 3)
        let beta = AgentProfile(name: "Beta", skills: ["swiftui"], maxConcurrentTasks: 3)
        let zetaLoaded = AgentProfile(name: "Zeta", skills: ["swiftui"], maxConcurrentTasks: 3)
        let loadTask = WorkTask(
            title: "Busy",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 1,
            status: .inProgress,
            assignedAgentID: zetaLoaded.id
        )
        let viewModel = KanbanBoardViewModel(
            tasks: [task, loadTask],
            agents: [zetaLoaded, beta, alpha]
        )

        let eligible = viewModel.assignableAgents(for: task.id)

        #expect(eligible.map(\.name) == ["Alpha", "Beta", "Zeta"])
    }

    @Test("reassignable agents are ordered by load then name")
    func reassignableAgentsAreOrderedByLoadThenName() {
        let source = AgentProfile(name: "Source", skills: ["swiftui"], maxConcurrentTasks: 3)
        let alpha = AgentProfile(name: "Alpha", skills: ["swiftui"], maxConcurrentTasks: 3)
        let beta = AgentProfile(name: "Beta", skills: ["swiftui"], maxConcurrentTasks: 3)
        let zetaLoaded = AgentProfile(name: "Zeta", skills: ["swiftui"], maxConcurrentTasks: 3)
        let assignedTask = WorkTask(
            title: "Reassign me",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 2,
            status: .todo,
            assignedAgentID: source.id
        )
        let loadTask = WorkTask(
            title: "Busy",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 1,
            status: .inProgress,
            assignedAgentID: zetaLoaded.id
        )
        let viewModel = KanbanBoardViewModel(
            tasks: [assignedTask, loadTask],
            agents: [source, zetaLoaded, beta, alpha]
        )

        let candidates = viewModel.reassignableAgents(for: assignedTask.id)

        #expect(candidates.map(\.name) == ["Alpha", "Beta", "Zeta"])
    }

    @Test("triage candidates include todo tasks that remain unassigned without auto-assign")
    func triageCandidatesIncludePlainUnassignedTodoTasks() {
        let todoUnassigned = WorkTask(
            title: "Unassigned To Do",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 2,
            status: .todo,
            assignedAgentID: nil
        )
        let todoAssigned = WorkTask(
            title: "Assigned To Do",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 1,
            status: .todo,
            assignedAgentID: UUID()
        )
        let reviewUnassigned = WorkTask(
            title: "Review task",
            details: "",
            requiredSkills: ["testing"],
            storyPoints: 3,
            status: .review,
            assignedAgentID: nil
        )
        let viewModel = KanbanBoardViewModel(tasks: [todoUnassigned, todoAssigned, reviewUnassigned], agents: [])

        let candidates = viewModel.triageCandidates()

        #expect(candidates.count == 1)
        #expect(candidates.first?.id == todoUnassigned.id)
    }

    @Test("assignable agents for triage only include skill-matched agents with remaining capacity")
    func assignableAgentsFilterBySkillAndCapacity() {
        let task = WorkTask(
            title: "Triage target",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 2,
            status: .todo,
            assignedAgentID: nil
        )
        let qualifiedAgent = AgentProfile(name: "Qualified", skills: ["swiftui"], maxConcurrentTasks: 2)
        let overloadedAgent = AgentProfile(name: "Overloaded", skills: ["swiftui"], maxConcurrentTasks: 1)
        let skillMismatchAgent = AgentProfile(name: "Mismatch", skills: ["backend"], maxConcurrentTasks: 3)
        let activeTask = WorkTask(
            title: "Existing load",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 1,
            status: .inProgress,
            assignedAgentID: overloadedAgent.id
        )
        let viewModel = KanbanBoardViewModel(
            tasks: [task, activeTask],
            agents: [qualifiedAgent, overloadedAgent, skillMismatchAgent]
        )

        let eligible = viewModel.assignableAgents(for: task.id)

        #expect(eligible.count == 1)
        #expect(eligible.first?.id == qualifiedAgent.id)
    }

    @Test("resolves triage assignments by keeping valid selections and dropping stale task ids")
    func resolvesTriageAssignmentsKeepingValidSelections() {
        let firstTask = WorkTask(
            title: "Task A",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 2,
            status: .todo,
            assignedAgentID: nil
        )
        let secondTask = WorkTask(
            title: "Task B",
            details: "",
            requiredSkills: ["testing"],
            storyPoints: 1,
            status: .todo,
            assignedAgentID: nil
        )
        let uiAgent = AgentProfile(name: "UI Agent", skills: ["swiftui"], maxConcurrentTasks: 2)
        let qaAgent = AgentProfile(name: "QA Agent", skills: ["testing"], maxConcurrentTasks: 2)
        let viewModel = KanbanBoardViewModel(tasks: [firstTask, secondTask], agents: [uiAgent, qaAgent])

        let staleTaskID = UUID()
        let resolved = viewModel.resolvedTriageAssignments(existing: [
            firstTask.id: uiAgent.id,
            staleTaskID: qaAgent.id
        ])

        #expect(resolved[firstTask.id] == uiAgent.id)
        #expect(resolved[secondTask.id] == qaAgent.id)
        #expect(resolved[staleTaskID] == nil)
    }

    @Test("resolves triage assignments by replacing invalid selected agent with fallback")
    func resolvesTriageAssignmentsReplacingInvalidSelection() {
        let task = WorkTask(
            title: "Task A",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 2,
            status: .todo,
            assignedAgentID: nil
        )
        let uiAgent = AgentProfile(name: "UI Agent", skills: ["swiftui"], maxConcurrentTasks: 2)
        let backendAgent = AgentProfile(name: "Backend Agent", skills: ["backend"], maxConcurrentTasks: 2)
        let viewModel = KanbanBoardViewModel(tasks: [task], agents: [uiAgent, backendAgent])

        let resolved = viewModel.resolvedTriageAssignments(existing: [task.id: backendAgent.id])

        #expect(resolved[task.id] == uiAgent.id)
    }

    @Test("resolves triage assignments with capacity-aware fallback across multiple tasks")
    func resolvesTriageAssignmentsWithCapacityAwareFallback() {
        let highPriorityTask = WorkTask(
            title: "Task High",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 3,
            status: .todo,
            assignedAgentID: nil
        )
        let lowPriorityTask = WorkTask(
            title: "Task Low",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 1,
            status: .todo,
            assignedAgentID: nil
        )
        let alphaAgent = AgentProfile(name: "Alpha Agent", skills: ["swiftui"], maxConcurrentTasks: 1)
        let betaAgent = AgentProfile(name: "Beta Agent", skills: ["swiftui"], maxConcurrentTasks: 1)
        let viewModel = KanbanBoardViewModel(tasks: [highPriorityTask, lowPriorityTask], agents: [alphaAgent, betaAgent])

        let resolved = viewModel.resolvedTriageAssignments(existing: [
            highPriorityTask.id: alphaAgent.id,
            lowPriorityTask.id: alphaAgent.id
        ])

        #expect(resolved[highPriorityTask.id] == alphaAgent.id)
        #expect(resolved[lowPriorityTask.id] == betaAgent.id)
    }

    @Test("bulk triage assignable count follows capacity-aware selection planning")
    func bulkTriageAssignableCountFollowsCapacityAwarePlan() {
        let highPriorityTask = WorkTask(
            title: "Task High",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 3,
            status: .todo,
            assignedAgentID: nil
        )
        let lowPriorityTask = WorkTask(
            title: "Task Low",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 1,
            status: .todo,
            assignedAgentID: nil
        )
        let alphaAgent = AgentProfile(name: "Alpha Agent", skills: ["swiftui"], maxConcurrentTasks: 1)
        let betaAgent = AgentProfile(name: "Beta Agent", skills: ["swiftui"], maxConcurrentTasks: 1)
        let viewModel = KanbanBoardViewModel(tasks: [highPriorityTask, lowPriorityTask], agents: [alphaAgent, betaAgent])

        let count = viewModel.bulkAssignableTriageTaskCount(using: [
            highPriorityTask.id: alphaAgent.id,
            lowPriorityTask.id: alphaAgent.id
        ])

        #expect(count == 2)
    }

    @Test("bulk triage plan matches capacity-aware fallback decisions")
    func bulkTriagePlanMatchesCapacityAwareFallback() {
        let highPriorityTask = WorkTask(
            title: "Task High",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 3,
            status: .todo,
            assignedAgentID: nil
        )
        let lowPriorityTask = WorkTask(
            title: "Task Low",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 1,
            status: .todo,
            assignedAgentID: nil
        )
        let alphaAgent = AgentProfile(name: "Alpha Agent", skills: ["swiftui"], maxConcurrentTasks: 1)
        let betaAgent = AgentProfile(name: "Beta Agent", skills: ["swiftui"], maxConcurrentTasks: 1)
        let viewModel = KanbanBoardViewModel(tasks: [highPriorityTask, lowPriorityTask], agents: [alphaAgent, betaAgent])

        let plan = viewModel.bulkTriageAssignmentPlan(using: [
            highPriorityTask.id: alphaAgent.id,
            lowPriorityTask.id: alphaAgent.id
        ])

        #expect(plan[highPriorityTask.id] == alphaAgent.id)
        #expect(plan[lowPriorityTask.id] == betaAgent.id)
        #expect(plan.count == 2)
    }

    @Test("bulk triage assignable count matches executable assignment plan size")
    func bulkTriageAssignableCountMatchesPlanSize() {
        let firstTask = WorkTask(
            title: "Task A",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 2,
            status: .todo,
            assignedAgentID: nil
        )
        let secondTask = WorkTask(
            title: "Task B",
            details: "",
            requiredSkills: ["ml"],
            storyPoints: 1,
            status: .todo,
            assignedAgentID: nil
        )
        let uiAgent = AgentProfile(name: "UI Agent", skills: ["swiftui"], maxConcurrentTasks: 2)
        let viewModel = KanbanBoardViewModel(tasks: [firstTask, secondTask], agents: [uiAgent])

        let count = viewModel.bulkAssignableTriageTaskCount()
        let plan = viewModel.bulkTriageAssignmentPlan()

        #expect(count == plan.count)
        #expect(count == 1)
    }

    @Test("bulk triage unassignable count tracks tasks without current assignment plan")
    func bulkTriageUnassignableCountTracksPlanGap() {
        let firstTask = WorkTask(
            title: "Task A",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 2,
            status: .todo,
            assignedAgentID: nil
        )
        let secondTask = WorkTask(
            title: "Task B",
            details: "",
            requiredSkills: ["ml"],
            storyPoints: 1,
            status: .todo,
            assignedAgentID: nil
        )
        let uiAgent = AgentProfile(name: "UI Agent", skills: ["swiftui"], maxConcurrentTasks: 2)
        let viewModel = KanbanBoardViewModel(tasks: [firstTask, secondTask], agents: [uiAgent])

        let assignable = viewModel.bulkAssignableTriageTaskCount()
        let unassignable = viewModel.bulkUnassignableTriageTaskCount()

        #expect(assignable == 1)
        #expect(unassignable == 1)
        #expect(assignable + unassignable == viewModel.triageCandidates().count)
    }

    @Test("bulk triage assignable count is a read-only preview")
    func bulkTriageAssignableCountDoesNotMutateBoardState() {
        let task = WorkTask(
            title: "ML task",
            details: "",
            requiredSkills: ["ml"],
            storyPoints: 3,
            status: .todo,
            assignedAgentID: nil
        )
        let agent = AgentProfile(name: "UI Agent", skills: ["swiftui"], maxConcurrentTasks: 2)
        let viewModel = KanbanBoardViewModel(tasks: [task], agents: [agent])

        let count = viewModel.bulkAssignableTriageTaskCount()

        #expect(count == 0)
        #expect(viewModel.tasks.count == 1)
        #expect(viewModel.tasks.first?.id == task.id)
        #expect(viewModel.tasks.first?.assignedAgentID == nil)
    }

    @Test("bulk triage assigns all currently eligible unassigned todo tasks")
    func bulkTriageAssignsEligibleTasks() {
        let uiTask = WorkTask(
            title: "UI task",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 2,
            status: .todo,
            assignedAgentID: nil
        )
        let testingTask = WorkTask(
            title: "Testing task",
            details: "",
            requiredSkills: ["testing"],
            storyPoints: 1,
            status: .todo,
            assignedAgentID: nil
        )
        let uiAgent = AgentProfile(name: "UI Agent", skills: ["swiftui"], maxConcurrentTasks: 2)
        let store = SpyBoardStore()
        let viewModel = KanbanBoardViewModel(
            tasks: [uiTask, testingTask],
            agents: [uiAgent],
            boardStore: store
        )

        let assignedCount = viewModel.bulkAssignTriageTasks()

        #expect(assignedCount == 1)
        #expect(viewModel.tasks.first(where: { $0.id == uiTask.id })?.assignedAgentID == uiAgent.id)
        #expect(viewModel.tasks.first(where: { $0.id == testingTask.id })?.assignedAgentID == nil)
        #expect(viewModel.triageCandidates().count == 1)
        #expect(store.savedSnapshots.count == 1)
    }

    @Test("bulk triage reports partial assignment when some tasks still need manual triage")
    func bulkTriageReportsPartialAssignmentSummary() {
        let uiTask = WorkTask(
            title: "UI task",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 2,
            status: .todo,
            assignedAgentID: nil
        )
        let testingTask = WorkTask(
            title: "Testing task",
            details: "",
            requiredSkills: ["testing"],
            storyPoints: 1,
            status: .todo,
            assignedAgentID: nil
        )
        let uiAgent = AgentProfile(name: "UI Agent", skills: ["swiftui"], maxConcurrentTasks: 2)
        let viewModel = KanbanBoardViewModel(tasks: [uiTask, testingTask], agents: [uiAgent])

        let assignedCount = viewModel.bulkAssignTriageTasks()

        #expect(assignedCount == 1)
        #expect(viewModel.lastBoardMessage == "Assigned 1 triage task. 1 task still need manual attention")
        #expect(viewModel.lastBoardMessageSeverity?.rawValue == "warning")
    }

    @Test("bulk triage clears summary message when all triage tasks are assigned")
    func bulkTriageClearsSummaryMessageWhenFullyAssigned() {
        let firstTask = WorkTask(
            title: "Task A",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 2,
            status: .todo,
            assignedAgentID: nil
        )
        let secondTask = WorkTask(
            title: "Task B",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 1,
            status: .todo,
            assignedAgentID: nil
        )
        let uiAgent = AgentProfile(name: "UI Agent", skills: ["swiftui"], maxConcurrentTasks: 2)
        let viewModel = KanbanBoardViewModel(tasks: [firstTask, secondTask], agents: [uiAgent])

        let assignedCount = viewModel.bulkAssignTriageTasks()

        #expect(assignedCount == 2)
        #expect(viewModel.lastBoardMessage == nil)
        #expect(viewModel.lastBoardMessageSeverity == nil)
    }

    @Test("bulk triage prefers selected agents from manual triage choices")
    func bulkTriagePrefersSelectedAgents() {
        let firstTask = WorkTask(
            title: "Task A",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 2,
            status: .todo,
            assignedAgentID: nil
        )
        let secondTask = WorkTask(
            title: "Task B",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 2,
            status: .todo,
            assignedAgentID: nil
        )
        let alphaAgent = AgentProfile(name: "Alpha Agent", skills: ["swiftui"], maxConcurrentTasks: 1)
        let betaAgent = AgentProfile(name: "Beta Agent", skills: ["swiftui"], maxConcurrentTasks: 1)
        let store = SpyBoardStore()
        let viewModel = KanbanBoardViewModel(
            tasks: [firstTask, secondTask],
            agents: [alphaAgent, betaAgent],
            boardStore: store
        )

        let assignedCount = viewModel.bulkAssignTriageTasks(using: [
            firstTask.id: betaAgent.id,
            secondTask.id: alphaAgent.id
        ])

        #expect(assignedCount == 2)
        #expect(viewModel.tasks.first(where: { $0.id == firstTask.id })?.assignedAgentID == betaAgent.id)
        #expect(viewModel.tasks.first(where: { $0.id == secondTask.id })?.assignedAgentID == alphaAgent.id)
        #expect(store.savedSnapshots.count == 1)
    }

    @Test("bulk triage falls back when selected agent is no longer eligible")
    func bulkTriageFallsBackWhenSelectionIsInvalid() {
        let firstTask = WorkTask(
            title: "Task A",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 3,
            status: .todo,
            assignedAgentID: nil
        )
        let secondTask = WorkTask(
            title: "Task B",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 1,
            status: .todo,
            assignedAgentID: nil
        )
        let alphaAgent = AgentProfile(name: "Alpha Agent", skills: ["swiftui"], maxConcurrentTasks: 1)
        let betaAgent = AgentProfile(name: "Beta Agent", skills: ["swiftui"], maxConcurrentTasks: 1)
        let store = SpyBoardStore()
        let viewModel = KanbanBoardViewModel(
            tasks: [firstTask, secondTask],
            agents: [alphaAgent, betaAgent],
            boardStore: store
        )

        let assignedCount = viewModel.bulkAssignTriageTasks(using: [
            firstTask.id: alphaAgent.id,
            secondTask.id: alphaAgent.id
        ])

        #expect(assignedCount == 2)
        #expect(viewModel.tasks.first(where: { $0.id == firstTask.id })?.assignedAgentID == alphaAgent.id)
        #expect(viewModel.tasks.first(where: { $0.id == secondTask.id })?.assignedAgentID == betaAgent.id)
        #expect(store.savedSnapshots.count == 1)
    }

    @Test("bulk triage reports when no eligible assignment can be made")
    func bulkTriageReportsNoEligibleAssignments() {
        let task = WorkTask(
            title: "ML task",
            details: "",
            requiredSkills: ["ml"],
            storyPoints: 3,
            status: .todo,
            assignedAgentID: nil
        )
        let agent = AgentProfile(name: "UI Agent", skills: ["swiftui"], maxConcurrentTasks: 2)
        let store = SpyBoardStore()
        let viewModel = KanbanBoardViewModel(tasks: [task], agents: [agent], boardStore: store)

        let assignedCount = viewModel.bulkAssignTriageTasks()

        #expect(assignedCount == 0)
        #expect(viewModel.lastBoardMessage == "No eligible agents available for pending triage tasks")
        #expect(viewModel.lastBoardMessageSeverity?.rawValue == "warning")
        #expect(store.savedSnapshots.isEmpty)
    }

    @Test("adds task with normalized skills and persists snapshot")
    func addsTaskAndPersists() {
        let store = SpyBoardStore()
        let viewModel = KanbanBoardViewModel(tasks: [], agents: [], boardStore: store)

        let added = viewModel.addTask(
            title: "Implement Search",
            details: "Add board filtering",
            requiredSkillsText: "swiftui, ui,  ",
            storyPoints: 3
        )

        #expect(added)
        #expect(viewModel.tasks.count == 1)
        #expect(viewModel.tasks[0].title == "Implement Search")
        #expect(viewModel.tasks[0].requiredSkills == Set(["swiftui", "ui"]))
        #expect(store.savedSnapshots.count == 1)
    }

    @Test("adds task with create-and-auto-assign flow when eligible agent exists")
    func addsTaskAndAutoAssigns() {
        let agent = AgentProfile(name: "UI Agent", skills: ["swiftui", "ui"], maxConcurrentTasks: 2)
        let store = SpyBoardStore()
        let viewModel = KanbanBoardViewModel(tasks: [], agents: [agent], boardStore: store)

        let added = viewModel.addTask(
            title: "Implement card",
            details: "Task should be auto assigned",
            requiredSkillsText: "swiftui",
            storyPoints: 3,
            autoAssign: true
        )

        #expect(added)
        #expect(viewModel.tasks.count == 1)
        #expect(viewModel.tasks[0].assignedAgentID == agent.id)
        #expect(viewModel.assignmentReason(for: viewModel.tasks[0].id) != nil)
        #expect(!viewModel.lastUnassignedTaskIDs.contains(viewModel.tasks[0].id))
        #expect(store.savedSnapshots.count == 1)
    }

    @Test("create-and-auto-assign leaves task unassigned when no eligible agent exists")
    func addTaskAutoAssignFallsBackToUnassigned() {
        let agent = AgentProfile(name: "Backend Agent", skills: ["api"], maxConcurrentTasks: 2)
        let store = SpyBoardStore()
        let viewModel = KanbanBoardViewModel(tasks: [], agents: [agent], boardStore: store)

        let added = viewModel.addTask(
            title: "Design view",
            details: "",
            requiredSkillsText: "swiftui",
            storyPoints: 2,
            autoAssign: true
        )

        #expect(added)
        #expect(viewModel.tasks.count == 1)
        #expect(viewModel.tasks[0].assignedAgentID == nil)
        #expect(viewModel.lastUnassignedTaskIDs.contains(viewModel.tasks[0].id))
        #expect(viewModel.lastBoardMessage == nil)
        #expect(store.savedSnapshots.count == 1)
    }

    @Test("rejects adding task with empty title")
    func rejectsAddingTaskWithEmptyTitle() {
        let store = SpyBoardStore()
        let viewModel = KanbanBoardViewModel(tasks: [], agents: [], boardStore: store)

        let added = viewModel.addTask(
            title: "   ",
            details: "No title",
            requiredSkillsText: "swiftui",
            storyPoints: 2
        )

        #expect(!added)
        #expect(viewModel.tasks.isEmpty)
        #expect(viewModel.lastBoardMessage == "Task title is required")
        #expect(store.savedSnapshots.isEmpty)
    }

    @Test("updates task fields and persists snapshot")
    func updatesTaskAndPersists() {
        let task = WorkTask(
            title: "Build board",
            details: "Initial details",
            requiredSkills: ["swiftui"],
            storyPoints: 2,
            status: .todo,
            assignedAgentID: nil
        )
        let store = SpyBoardStore()
        let viewModel = KanbanBoardViewModel(tasks: [task], agents: [], boardStore: store)

        let updated = viewModel.updateTask(
            task.id,
            title: "Build kanban board",
            details: "Updated details",
            requiredSkillsText: "swiftui, ui",
            storyPoints: 5
        )

        #expect(updated)
        #expect(viewModel.tasks.count == 1)
        #expect(viewModel.tasks[0].title == "Build kanban board")
        #expect(viewModel.tasks[0].details == "Updated details")
        #expect(viewModel.tasks[0].requiredSkills == Set(["swiftui", "ui"]))
        #expect(viewModel.tasks[0].storyPoints == 5)
        #expect(store.savedSnapshots.count == 1)
    }

    @Test("rejects updating task with empty title")
    func rejectsUpdatingTaskWithEmptyTitle() {
        let task = WorkTask(
            title: "Build board",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 2,
            status: .todo,
            assignedAgentID: nil
        )
        let store = SpyBoardStore()
        let viewModel = KanbanBoardViewModel(tasks: [task], agents: [], boardStore: store)

        let updated = viewModel.updateTask(
            task.id,
            title: "   ",
            details: "",
            requiredSkillsText: "swiftui",
            storyPoints: 2
        )

        #expect(!updated)
        #expect(viewModel.tasks[0].title == "Build board")
        #expect(viewModel.lastBoardMessage == "Task title is required")
        #expect(store.savedSnapshots.isEmpty)
    }

    @Test("removes task and persists snapshot")
    func removesTaskAndPersists() {
        let task = WorkTask(
            title: "Build board",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 2,
            status: .todo,
            assignedAgentID: nil
        )
        let store = SpyBoardStore()
        let viewModel = KanbanBoardViewModel(tasks: [task], agents: [], boardStore: store)

        let removed = viewModel.removeTask(task.id)

        #expect(removed)
        #expect(viewModel.tasks.isEmpty)
        #expect(store.savedSnapshots.count == 1)
    }

    @Test("duplicates task into a new unassigned todo copy and persists")
    func duplicatesTaskAndPersists() {
        let agent = AgentProfile(name: "Reviewer", skills: ["swiftui"], maxConcurrentTasks: 2)
        let task = WorkTask(
            title: "Review flow",
            details: "Current implementation",
            requiredSkills: ["swiftui"],
            storyPoints: 3,
            status: .review,
            assignedAgentID: agent.id
        )
        let store = SpyBoardStore()
        let viewModel = KanbanBoardViewModel(tasks: [task], agents: [agent], boardStore: store)

        let duplicated = viewModel.duplicateTask(task.id)

        #expect(duplicated)
        #expect(viewModel.tasks.count == 2)
        let copy = viewModel.tasks.first(where: { $0.id != task.id })
        #expect(copy?.title == "Review flow Copy")
        #expect(copy?.details == task.details)
        #expect(copy?.requiredSkills == task.requiredSkills)
        #expect(copy?.storyPoints == task.storyPoints)
        #expect(copy?.status == .todo)
        #expect(copy?.assignedAgentID == nil)
        #expect(store.savedSnapshots.count == 1)
    }

    @Test("duplicate task increments copy suffix when copy names already exist")
    func duplicateTaskIncrementsCopySuffix() {
        let original = WorkTask(
            title: "Task",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 1,
            status: .todo,
            assignedAgentID: nil
        )
        let copyOne = WorkTask(
            title: "Task Copy",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 1,
            status: .todo,
            assignedAgentID: nil
        )
        let copyTwo = WorkTask(
            title: "Task Copy 2",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 1,
            status: .todo,
            assignedAgentID: nil
        )
        let viewModel = KanbanBoardViewModel(tasks: [original, copyOne, copyTwo], agents: [])

        let duplicated = viewModel.duplicateTask(original.id)

        #expect(duplicated)
        #expect(viewModel.tasks.contains(where: { $0.title == "Task Copy 3" }))
    }

    @Test("run task execution success moves todo task to review and persists execution record")
    func runTaskExecutionSuccessMovesTaskToReview() {
        let agent = AgentProfile(name: "Executor", skills: ["swiftui"], maxConcurrentTasks: 2)
        let task = WorkTask(
            title: "Generate UI spec",
            details: "Produce handoff notes",
            requiredSkills: ["swiftui"],
            storyPoints: 2,
            status: .todo,
            assignedAgentID: agent.id
        )
        let store = SpyBoardStore()
        let executor = StubTaskExecutor(
            outcomesByTaskID: [task.id: .success(summary: "Spec generated")]
        )
        let viewModel = KanbanBoardViewModel(
            tasks: [task],
            agents: [agent],
            taskExecutor: executor,
            boardStore: store
        )

        let executed = viewModel.runTaskExecution(task.id)
        let updatedTask = viewModel.tasks.first(where: { $0.id == task.id })
        let record = updatedTask?.executionRecord
        let agentEvents = viewModel.executionEvents(for: agent.id)

        #expect(executed)
        #expect(updatedTask?.status == .review)
        #expect(record?.status == .succeeded)
        #expect(record?.runCount == 1)
        #expect(record?.lastOutputSummary == "Spec generated")
        #expect(record?.lastError == nil)
        #expect(record?.lastAgentID == agent.id)
        #expect(record?.lastStartedAt != nil)
        #expect(record?.lastFinishedAt != nil)
        #expect(viewModel.lastBoardMessageSeverity == .info)
        #expect(store.savedSnapshots.count == 1)
        #expect(agentEvents.count == 2)
        #expect(agentEvents.first?.status == .succeeded)
        #expect(agentEvents.last?.status == .running)
        #expect(agentEvents.first?.taskID == task.id)
    }

    @Test("run task execution strips leading summary heading from successful output")
    func runTaskExecutionStripsSummaryHeading() {
        let agent = AgentProfile(name: "Executor", skills: ["swiftui"], maxConcurrentTasks: 2)
        let task = WorkTask(
            title: "Generate UI spec",
            details: "Produce handoff notes",
            requiredSkills: ["swiftui"],
            storyPoints: 2,
            status: .todo,
            assignedAgentID: agent.id
        )
        let executor = StubTaskExecutor(
            outcomesByTaskID: [task.id: .success(summary: "Summary: Spec generated\nActions taken:\n- Drafted UI notes")]
        )
        let viewModel = KanbanBoardViewModel(
            tasks: [task],
            agents: [agent],
            taskExecutor: executor
        )

        let executed = viewModel.runTaskExecution(task.id)
        let updatedTask = viewModel.tasks.first(where: { $0.id == task.id })
        let summary = updatedTask?.executionRecord?.lastOutputSummary

        #expect(executed)
        #expect(summary == "Spec generated\nActions taken:\n- Drafted UI notes")
    }

    @Test("run task execution rejects unassigned task")
    func runTaskExecutionRejectsUnassignedTask() {
        let task = WorkTask(
            title: "Unassigned execution",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 1,
            status: .todo,
            assignedAgentID: nil
        )
        let store = SpyBoardStore()
        let viewModel = KanbanBoardViewModel(tasks: [task], agents: [], boardStore: store)

        let executed = viewModel.runTaskExecution(task.id)

        #expect(!executed)
        #expect(viewModel.tasks.first?.status == .todo)
        #expect(viewModel.tasks.first?.executionRecord == nil)
        #expect(viewModel.lastBoardMessage == "Assign an agent before running this task")
        #expect(viewModel.lastBoardMessageSeverity == .warning)
        #expect(store.savedSnapshots.isEmpty)
    }

    @Test("run task execution requires non-empty task details")
    func runTaskExecutionRequiresTaskDetails() {
        let agent = AgentProfile(name: "Executor", skills: ["swiftui"], maxConcurrentTasks: 2)
        let task = WorkTask(
            title: "Missing details",
            details: "   ",
            requiredSkills: ["swiftui"],
            storyPoints: 1,
            status: .todo,
            assignedAgentID: agent.id
        )
        let store = SpyBoardStore()
        let executor = StubTaskExecutor(
            outcomesByTaskID: [task.id: .success(summary: "Should not execute")]
        )
        let viewModel = KanbanBoardViewModel(
            tasks: [task],
            agents: [agent],
            taskExecutor: executor,
            boardStore: store
        )

        let executed = viewModel.runTaskExecution(task.id)

        #expect(!executed)
        #expect(viewModel.tasks.first?.status == .todo)
        #expect(viewModel.tasks.first?.executionRecord == nil)
        #expect(viewModel.lastBoardMessage == "Task details are required before running this task")
        #expect(viewModel.lastBoardMessageSeverity == .warning)
        #expect(store.savedSnapshots.isEmpty)
    }

    @Test("run task execution blocks when unresolved dependencies remain")
    func runTaskExecutionBlocksOnUnresolvedDependencies() {
        let agent = AgentProfile(name: "Executor", skills: ["swiftui"], maxConcurrentTasks: 2)
        let blockedTask = WorkTask(
            title: "Implementation",
            details: """
            Depends on: Missing Spec
            Implement core feature.
            """,
            requiredSkills: ["swiftui"],
            storyPoints: 3,
            status: .todo,
            assignedAgentID: agent.id
        )
        let viewModel = KanbanBoardViewModel(
            tasks: [blockedTask],
            agents: [agent],
            taskExecutor: StubTaskExecutor()
        )

        let blockedReason = viewModel.dependencyBlockReason(for: blockedTask.id)
        let executed = viewModel.runTaskExecution(blockedTask.id)

        #expect(blockedReason == "Blocked by dependencies: Missing Spec")
        #expect(!executed)
        #expect(viewModel.tasks.first?.executionRecord == nil)
        #expect(viewModel.lastBoardMessage == "Task blocked by dependencies: Missing Spec")
        #expect(viewModel.lastBoardMessageSeverity == .warning)
    }

    @Test("batch run executes assigned runnable tasks and skips empty details")
    func batchRunAssignedExecutionsSkipsEmptyDetails() {
        let agent = AgentProfile(name: "Executor", skills: ["swiftui"], maxConcurrentTasks: 3)
        let runnableTask = WorkTask(
            title: "Runnable",
            details: "Implement card view",
            requiredSkills: ["swiftui"],
            storyPoints: 3,
            status: .todo,
            assignedAgentID: agent.id
        )
        let missingDetailsTask = WorkTask(
            title: "Missing details",
            details: "   ",
            requiredSkills: ["swiftui"],
            storyPoints: 2,
            status: .todo,
            assignedAgentID: agent.id
        )
        let store = SpyBoardStore()
        let executor = StubTaskExecutor(
            outcomesByTaskID: [runnableTask.id: .success(summary: "Done")]
        )
        let viewModel = KanbanBoardViewModel(
            tasks: [runnableTask, missingDetailsTask],
            agents: [agent],
            taskExecutor: executor,
            boardStore: store
        )

        let started = viewModel.runAssignedTaskExecutions()
        let updatedRunnable = viewModel.tasks.first(where: { $0.id == runnableTask.id })
        let untouchedTask = viewModel.tasks.first(where: { $0.id == missingDetailsTask.id })

        #expect(started == 1)
        #expect(updatedRunnable?.executionRecord?.status == .succeeded)
        #expect(untouchedTask?.executionRecord == nil)
        #expect(untouchedTask?.status == .todo)
        #expect(viewModel.lastBoardMessage?.contains("1 missing details") == true)
    }

    @Test("batch run reports when assigned tasks are not runnable")
    func batchRunAssignedExecutionsReportsNoRunnableTasks() {
        let agent = AgentProfile(name: "Executor", skills: ["swiftui"], maxConcurrentTasks: 2)
        let task = WorkTask(
            title: "Blocked",
            details: "  ",
            requiredSkills: ["swiftui"],
            storyPoints: 1,
            status: .todo,
            assignedAgentID: agent.id
        )
        let store = SpyBoardStore()
        let viewModel = KanbanBoardViewModel(
            tasks: [task],
            agents: [agent],
            taskExecutor: StubTaskExecutor(),
            boardStore: store
        )

        let started = viewModel.runAssignedTaskExecutions()

        #expect(started == 0)
        #expect(viewModel.lastBoardMessage == "1 assigned task with empty details. Fill details before batch run.")
        #expect(viewModel.lastBoardMessageSeverity == .warning)
        #expect(viewModel.tasks.first?.executionRecord == nil)
        #expect(store.savedSnapshots.isEmpty)
    }

    @Test("batch run includes skipped count when assigned task cannot execute")
    func batchRunAssignedExecutionsCountsSkippedTasks() {
        let agent = AgentProfile(name: "Executor", skills: ["swiftui"], maxConcurrentTasks: 3)
        let runnableTask = WorkTask(
            title: "Runnable",
            details: "Implement card view",
            requiredSkills: ["swiftui"],
            storyPoints: 3,
            status: .todo,
            assignedAgentID: agent.id
        )
        let invalidAssignmentTask = WorkTask(
            title: "Ghost assignment",
            details: "Has details but assignee does not exist",
            requiredSkills: ["swiftui"],
            storyPoints: 2,
            status: .todo,
            assignedAgentID: UUID()
        )
        let executor = StubTaskExecutor(
            outcomesByTaskID: [runnableTask.id: .success(summary: "Done")]
        )
        let viewModel = KanbanBoardViewModel(
            tasks: [runnableTask, invalidAssignmentTask],
            agents: [agent],
            taskExecutor: executor
        )

        let started = viewModel.runAssignedTaskExecutions()

        #expect(started == 1)
        #expect(viewModel.lastBoardMessage?.contains("1 skipped") == true)
        #expect(viewModel.lastBoardMessageSeverity == .warning)
    }

    @Test("batch run respects depends-on ordering before executing assigned tasks")
    func batchRunAssignedExecutionsRespectsDependsOnOrdering() {
        let agent = AgentProfile(name: "Executor", skills: ["swiftui"], maxConcurrentTasks: 3)
        let prerequisite = WorkTask(
            title: "Design Spec",
            details: "Finalize target UX flow",
            requiredSkills: ["swiftui"],
            storyPoints: 3,
            status: .todo,
            assignedAgentID: agent.id
        )
        let dependent = WorkTask(
            title: "Implementation",
            details: """
            Depends on: Design Spec
            Implement feature based on approved spec.
            """,
            requiredSkills: ["swiftui"],
            storyPoints: 5,
            status: .todo,
            assignedAgentID: agent.id
        )
        let executor = StubTaskExecutor(
            outcomesByTaskID: [
                prerequisite.id: .success(summary: "spec done"),
                dependent.id: .success(summary: "impl done")
            ]
        )
        let viewModel = KanbanBoardViewModel(
            tasks: [dependent, prerequisite],
            agents: [agent],
            taskExecutor: executor
        )

        let startedFirstPass = viewModel.runAssignedTaskExecutions()

        #expect(startedFirstPass == 2)
        #expect(viewModel.tasks.first(where: { $0.id == prerequisite.id })?.executionRecord?.status == .succeeded)
        #expect(viewModel.tasks.first(where: { $0.id == dependent.id })?.executionRecord?.status == .succeeded)

        let startedSecondPass = viewModel.runAssignedTaskExecutions()

        #expect(startedSecondPass == 0)
        #expect(viewModel.lastBoardMessage == "No assigned tasks are ready to run")
    }

    @Test("batch run summary includes remaining dependency blockers after runnable tasks finish")
    func batchRunAssignedExecutionsSummaryIncludesRemainingDependencyBlockedCount() {
        let agent = AgentProfile(name: "Executor", skills: ["swiftui"], maxConcurrentTasks: 3)
        let runnable = WorkTask(
            title: "Build Spec",
            details: "Write implementation notes",
            requiredSkills: ["swiftui"],
            storyPoints: 2,
            status: .todo,
            assignedAgentID: agent.id
        )
        let blocked = WorkTask(
            title: "Implement Feature",
            details: """
            Depends on: External API Contract
            Build feature code.
            """,
            requiredSkills: ["swiftui"],
            storyPoints: 1,
            status: .todo,
            assignedAgentID: agent.id
        )
        let executor = StubTaskExecutor(
            outcomesByTaskID: [runnable.id: .success(summary: "spec ready")]
        )
        let viewModel = KanbanBoardViewModel(
            tasks: [blocked, runnable],
            agents: [agent],
            taskExecutor: executor
        )

        let started = viewModel.runAssignedTaskExecutions()

        #expect(started == 1)
        #expect(viewModel.tasks.first(where: { $0.id == runnable.id })?.executionRecord?.status == .succeeded)
        #expect(viewModel.tasks.first(where: { $0.id == blocked.id })?.executionRecord == nil)
        #expect(viewModel.lastBoardMessage?.contains("1 blocked by dependencies") == true)
        #expect(viewModel.lastBoardMessageSeverity == .warning)
    }

    @Test("batch run warns when assigned tasks are blocked by unresolved dependencies")
    func batchRunAssignedExecutionsWarnsForDependencyBlockedTasks() {
        let agent = AgentProfile(name: "Executor", skills: ["swiftui"], maxConcurrentTasks: 2)
        let blocked = WorkTask(
            title: "Implementation",
            details: """
            Depends on: Missing Spec
            Implement feature.
            """,
            requiredSkills: ["swiftui"],
            storyPoints: 3,
            status: .todo,
            assignedAgentID: agent.id
        )
        let viewModel = KanbanBoardViewModel(
            tasks: [blocked],
            agents: [agent],
            taskExecutor: StubTaskExecutor()
        )

        let started = viewModel.runAssignedTaskExecutions()

        #expect(started == 0)
        #expect(viewModel.lastBoardMessage == "1 assigned task blocked by dependencies. Resolve dependencies before batch run.")
        #expect(viewModel.lastBoardMessageSeverity == .warning)
    }

    @Test("run task execution failure writes failed record and keeps task in progress")
    func runTaskExecutionFailureWritesRecord() {
        let agent = AgentProfile(name: "Executor", skills: ["swiftui"], maxConcurrentTasks: 2)
        let task = WorkTask(
            title: "Run command",
            details: "Expect failure",
            requiredSkills: ["swiftui"],
            storyPoints: 2,
            status: .todo,
            assignedAgentID: agent.id
        )
        let store = SpyBoardStore()
        let executor = StubTaskExecutor(
            outcomesByTaskID: [task.id: .failure(message: "Tool timeout")]
        )
        let viewModel = KanbanBoardViewModel(
            tasks: [task],
            agents: [agent],
            taskExecutor: executor,
            boardStore: store
        )

        let executed = viewModel.runTaskExecution(task.id)
        let updatedTask = viewModel.tasks.first(where: { $0.id == task.id })
        let record = updatedTask?.executionRecord
        let agentEvents = viewModel.executionEvents(for: agent.id)

        #expect(executed)
        #expect(updatedTask?.status == .inProgress)
        #expect(record?.status == .failed)
        #expect(record?.runCount == 1)
        #expect(record?.lastError == "Tool timeout")
        #expect(record?.lastOutputSummary == nil)
        #expect(record?.lastFinishedAt != nil)
        #expect(viewModel.lastBoardMessage == "Execution failed: Tool timeout")
        #expect(viewModel.lastBoardMessageSeverity == .warning)
        #expect(store.savedSnapshots.count == 1)
        #expect(agentEvents.count == 2)
        #expect(agentEvents.first?.status == .failed)
        #expect(agentEvents.last?.status == .running)
        #expect(agentEvents.first?.taskID == task.id)
    }

    @Test("run task execution extracts debug log from failure delimiter")
    func runTaskExecutionFailureExtractsDebugLog() {
        let agent = AgentProfile(name: "Executor", skills: ["swiftui"], maxConcurrentTasks: 2)
        let task = WorkTask(
            title: "Run command",
            details: "Expect failure",
            requiredSkills: ["swiftui"],
            storyPoints: 2,
            status: .todo,
            assignedAgentID: agent.id
        )
        let store = SpyBoardStore()
        let executor = StubTaskExecutor(
            outcomesByTaskID: [
                task.id: .failure(
                    message: "Codex Bridge run failed: Network issue\n\n--- debug ---\nRAW DEBUG"
                )
            ]
        )
        let viewModel = KanbanBoardViewModel(
            tasks: [task],
            agents: [agent],
            taskExecutor: executor,
            boardStore: store
        )

        let executed = viewModel.runTaskExecution(task.id)
        let updatedTask = viewModel.tasks.first(where: { $0.id == task.id })
        let record = updatedTask?.executionRecord

        #expect(executed)
        #expect(record?.status == .failed)
        #expect(record?.lastError == "Codex Bridge run failed: Network issue")
        #expect(record?.lastDebugOutput == "RAW DEBUG")
        #expect(viewModel.lastExecutionDebugLog == "RAW DEBUG")
        #expect(viewModel.lastCodexLoginCommand == nil)
        #expect(viewModel.lastBoardMessage == "Execution failed: Codex Bridge run failed: Network issue")
        #expect(viewModel.lastBoardMessageSeverity == .warning)
    }

    @Test("run task execution captures streaming progress updates for agent console")
    func runTaskExecutionCapturesStreamingProgressUpdates() {
        let agent = AgentProfile(name: "Executor", skills: ["swiftui"], maxConcurrentTasks: 2)
        let task = WorkTask(
            title: "Streaming task",
            details: "Track progress logs",
            requiredSkills: ["swiftui"],
            storyPoints: 2,
            status: .todo,
            assignedAgentID: agent.id
        )
        let store = SpyBoardStore()
        let executor = StubTaskExecutor(
            outcomesByTaskID: [task.id: .success(summary: "Done")],
            progressUpdatesByTaskID: [task.id: ["Planning changes", "Applying patch"]]
        )
        let viewModel = KanbanBoardViewModel(
            tasks: [task],
            agents: [agent],
            taskExecutor: executor,
            boardStore: store
        )

        let executed = viewModel.runTaskExecution(task.id)
        let events = viewModel.executionEvents(for: agent.id)

        #expect(executed)
        #expect(events.contains(where: { $0.message == "Planning changes" }))
        #expect(events.contains(where: { $0.message == "Applying patch" }))
        #expect(events.contains(where: { $0.status == .succeeded }))
    }

    @Test("execution events respects limit and zero-limit branches")
    func executionEventsRespectsLimitAndZeroLimitBranches() {
        let agent = AgentProfile(name: "Executor", skills: ["swiftui"], maxConcurrentTasks: 2)
        let task = WorkTask(
            title: "Streaming task",
            details: "Track progress logs",
            requiredSkills: ["swiftui"],
            storyPoints: 2,
            status: .todo,
            assignedAgentID: agent.id
        )
        let executor = StubTaskExecutor(
            outcomesByTaskID: [task.id: .success(summary: "Done")],
            progressUpdatesByTaskID: [task.id: ["Analyze\nPlan", "Implement"]]
        )
        let viewModel = KanbanBoardViewModel(
            tasks: [task],
            agents: [agent],
            taskExecutor: executor
        )

        _ = viewModel.runTaskExecution(task.id)
        let allEvents = viewModel.executionEvents(for: agent.id, limit: 99)
        let limitedEvents = viewModel.executionEvents(for: agent.id, limit: 2)
        let zeroLimitEvents = viewModel.executionEvents(for: agent.id, limit: 0)

        #expect(allEvents.count > 2)
        #expect(limitedEvents.count == 2)
        #expect(limitedEvents.first?.status == .succeeded)
        #expect(zeroLimitEvents.count == allEvents.count)
    }

    @Test("clearExecutionEvents removes stored events for a specific agent")
    func clearExecutionEventsRemovesStoredEventsForAgent() {
        let agent = AgentProfile(name: "Executor", skills: ["swiftui"], maxConcurrentTasks: 2)
        let task = WorkTask(
            title: "Streaming task",
            details: "Track progress logs",
            requiredSkills: ["swiftui"],
            storyPoints: 2,
            status: .todo,
            assignedAgentID: agent.id
        )
        let executor = StubTaskExecutor(
            outcomesByTaskID: [task.id: .success(summary: "Done")],
            progressUpdatesByTaskID: [task.id: ["Planning changes"]]
        )
        let viewModel = KanbanBoardViewModel(
            tasks: [task],
            agents: [agent],
            taskExecutor: executor
        )

        _ = viewModel.runTaskExecution(task.id)
        #expect(!viewModel.executionEvents(for: agent.id).isEmpty)

        viewModel.clearExecutionEvents(for: agent.id)

        #expect(viewModel.executionEvents(for: agent.id).isEmpty)
    }

    @Test("isAgentExecutionRunning checks running status by lastAgentID and assignee")
    func isAgentExecutionRunningChecksLastAgentAndAssignee() {
        let agentA = AgentProfile(name: "Agent A", skills: ["swiftui"], maxConcurrentTasks: 2)
        let agentB = AgentProfile(name: "Agent B", skills: ["swiftui"], maxConcurrentTasks: 2)
        let runningByLastAgent = WorkTask(
            title: "Run A",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 1,
            status: .inProgress,
            assignedAgentID: nil,
            executionRecord: TaskExecutionRecord(status: .running, lastAgentID: agentA.id)
        )
        let runningByAssignee = WorkTask(
            title: "Run B",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 1,
            status: .inProgress,
            assignedAgentID: agentB.id,
            executionRecord: TaskExecutionRecord(status: .running, lastAgentID: nil)
        )
        let completed = WorkTask(
            title: "Done C",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 1,
            status: .review,
            assignedAgentID: agentB.id,
            executionRecord: TaskExecutionRecord(status: .succeeded, lastAgentID: agentB.id)
        )
        let viewModel = KanbanBoardViewModel(
            tasks: [runningByLastAgent, runningByAssignee, completed],
            agents: [agentA, agentB]
        )

        #expect(viewModel.isAgentExecutionRunning(agentA.id))
        #expect(viewModel.isAgentExecutionRunning(agentB.id))
        #expect(!viewModel.isAgentExecutionRunning(UUID()))
    }

    @Test("run task execution marks blocker summaries as failed")
    func runTaskExecutionMarksBlockerSummaryAsFailed() {
        let agent = AgentProfile(name: "Executor", skills: ["swiftui"], maxConcurrentTasks: 2)
        let task = WorkTask(
            title: "AAA",
            details: "Draft objective captured; awaiting concrete acceptance criteria.",
            requiredSkills: [],
            storyPoints: 1,
            status: .todo,
            assignedAgentID: agent.id
        )
        let store = SpyBoardStore()
        let summary = "Execution summary: Reviewed Task \"AAA\" (1 story point) assigned to Agent A. No implementation details or acceptance criteria were provided, so execution could not proceed beyond intake."
        let executor = StubTaskExecutor(
            outcomesByTaskID: [task.id: .success(summary: summary)]
        )
        let viewModel = KanbanBoardViewModel(
            tasks: [task],
            agents: [agent],
            taskExecutor: executor,
            boardStore: store
        )

        let executed = viewModel.runTaskExecution(task.id)
        let updatedTask = viewModel.tasks.first(where: { $0.id == task.id })
        let record = updatedTask?.executionRecord

        #expect(executed)
        #expect(updatedTask?.status == .inProgress)
        #expect(record?.status == .failed)
        #expect(record?.lastOutputSummary == summary)
        #expect(record?.lastError == "Execution blocked: missing task details or acceptance criteria")
        #expect(viewModel.lastBoardMessage == "Execution blocked: missing task details or acceptance criteria")
        #expect(viewModel.lastBoardMessageSeverity == .warning)
    }

    @Test("run task execution exposes codex login command for quick copy")
    func runTaskExecutionExtractsCodexLoginCommand() {
        let agent = AgentProfile(name: "Executor", skills: ["swiftui"], maxConcurrentTasks: 2)
        let task = WorkTask(
            title: "Run command",
            details: "Expect auth failure",
            requiredSkills: ["swiftui"],
            storyPoints: 2,
            status: .todo,
            assignedAgentID: agent.id
        )
        let store = SpyBoardStore()
        let loginCommand = "HOME=\"/tmp/home\" CODEX_HOME=\"/tmp/home/.codex\" codex login --device-auth"
        let executor = StubTaskExecutor(
            outcomesByTaskID: [
                task.id: .failure(
                    message: "Codex Bridge run failed: Codex Bridge authentication missing. Run this once in Terminal: \(loginCommand)\n\n--- debug ---\n401 Unauthorized"
                )
            ]
        )
        let viewModel = KanbanBoardViewModel(
            tasks: [task],
            agents: [agent],
            taskExecutor: executor,
            boardStore: store
        )

        let executed = viewModel.runTaskExecution(task.id)

        #expect(executed)
        #expect(viewModel.lastCodexLoginCommand == loginCommand)
        #expect(viewModel.lastExecutionDebugLog == "401 Unauthorized")
        #expect(viewModel.lastBoardMessage?.contains("Codex Bridge authentication missing") == true)
    }

    @Test("run task execution extracts codex login command when only plain command is present")
    func runTaskExecutionExtractsPlainCodexLoginCommand() {
        let agent = AgentProfile(name: "Executor", skills: ["swiftui"], maxConcurrentTasks: 2)
        let task = WorkTask(
            title: "Run command",
            details: "Expect auth failure",
            requiredSkills: ["swiftui"],
            storyPoints: 2,
            status: .todo,
            assignedAgentID: agent.id
        )
        let plainLoginCommand = "codex login --device-auth"
        let executor = StubTaskExecutor(
            outcomesByTaskID: [
                task.id: .failure(
                    message: "Authentication missing.\n\(plainLoginCommand)"
                )
            ]
        )
        let viewModel = KanbanBoardViewModel(
            tasks: [task],
            agents: [agent],
            taskExecutor: executor
        )

        let executed = viewModel.runTaskExecution(task.id)

        #expect(executed)
        #expect(viewModel.lastCodexLoginCommand == plainLoginCommand)
    }

    @Test("retry task execution requires previous failed run")
    func retryTaskExecutionRequiresFailedRun() {
        let agent = AgentProfile(name: "Executor", skills: ["swiftui"], maxConcurrentTasks: 2)
        let task = WorkTask(
            title: "Already passed",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 1,
            status: .review,
            assignedAgentID: agent.id,
            executionRecord: TaskExecutionRecord(status: .succeeded, runCount: 1)
        )
        let store = SpyBoardStore()
        let viewModel = KanbanBoardViewModel(tasks: [task], agents: [agent], boardStore: store)

        let retried = viewModel.retryTaskExecution(task.id)

        #expect(!retried)
        #expect(viewModel.lastBoardMessage == "Only failed executions can be retried")
        #expect(viewModel.lastBoardMessageSeverity == .warning)
        #expect(store.savedSnapshots.isEmpty)
    }

    @Test("retry task execution reruns failed task and increments run count")
    func retryTaskExecutionRerunsFailedTask() {
        let agent = AgentProfile(name: "Executor", skills: ["swiftui"], maxConcurrentTasks: 2)
        let task = WorkTask(
            title: "Retry me",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 2,
            status: .inProgress,
            assignedAgentID: agent.id,
            executionRecord: TaskExecutionRecord(status: .failed, runCount: 1, lastError: "network")
        )
        let store = SpyBoardStore()
        let executor = StubTaskExecutor(
            outcomesByTaskID: [task.id: .success(summary: "Retry succeeded")],
            progressUpdatesByTaskID: [task.id: ["Retry step"]]
        )
        let viewModel = KanbanBoardViewModel(
            tasks: [task],
            agents: [agent],
            taskExecutor: executor,
            boardStore: store
        )

        let retried = viewModel.retryTaskExecution(task.id)
        let updatedTask = viewModel.tasks.first(where: { $0.id == task.id })
        let record = updatedTask?.executionRecord

        #expect(retried)
        #expect(updatedTask?.status == .review)
        #expect(record?.status == .succeeded)
        #expect(record?.runCount == 2)
        #expect(record?.lastOutputSummary == "Retry succeeded")
        #expect(record?.lastError == nil)
        #expect(viewModel.executionEvents(for: agent.id).contains(where: { $0.message == "Retry step" }))
        #expect(store.savedSnapshots.count == 1)
    }

    @Test("removing unknown task returns false and does not persist")
    func rejectsRemovingUnknownTask() {
        let task = WorkTask(
            title: "Build board",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 2,
            status: .todo,
            assignedAgentID: nil
        )
        let store = SpyBoardStore()
        let viewModel = KanbanBoardViewModel(tasks: [task], agents: [], boardStore: store)

        let removed = viewModel.removeTask(UUID())

        #expect(!removed)
        #expect(viewModel.tasks.count == 1)
        #expect(store.savedSnapshots.isEmpty)
    }

    @Test("unassigns task and persists snapshot")
    func unassignsTaskAndPersists() {
        let agent = AgentProfile(name: "UI Agent", skills: ["swiftui"], maxConcurrentTasks: 2)
        let task = WorkTask(
            title: "Build board",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 2,
            status: .todo,
            assignedAgentID: agent.id
        )
        let store = SpyBoardStore()
        let viewModel = KanbanBoardViewModel(tasks: [task], agents: [agent], boardStore: store)

        let unassigned = viewModel.unassignTask(task.id)

        #expect(unassigned)
        #expect(viewModel.tasks[0].assignedAgentID == nil)
        #expect(viewModel.assignmentReason(for: task.id) == nil)
        #expect(viewModel.triageCandidates().contains(where: { $0.id == task.id }))
        #expect(store.savedSnapshots.count == 1)
    }

    @Test("rejects unassigning task that is already unassigned")
    func rejectsUnassigningAlreadyUnassignedTask() {
        let task = WorkTask(
            title: "Build board",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 2,
            status: .todo,
            assignedAgentID: nil
        )
        let store = SpyBoardStore()
        let viewModel = KanbanBoardViewModel(tasks: [task], agents: [], boardStore: store)

        let unassigned = viewModel.unassignTask(task.id)

        #expect(!unassigned)
        #expect(viewModel.lastBoardMessage == "Task is already unassigned")
        #expect(store.savedSnapshots.isEmpty)
    }

    @Test("clears done tasks and persists snapshot once")
    func clearsDoneTasksAndPersists() {
        let doneA = WorkTask(
            title: "Ship v1",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 2,
            status: .done,
            assignedAgentID: nil
        )
        let doneB = WorkTask(
            title: "Close sprint",
            details: "",
            requiredSkills: ["testing"],
            storyPoints: 1,
            status: .done,
            assignedAgentID: nil
        )
        let todo = WorkTask(
            title: "Next task",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 3,
            status: .todo,
            assignedAgentID: nil
        )
        let store = SpyBoardStore()
        let viewModel = KanbanBoardViewModel(tasks: [doneA, todo, doneB], agents: [], boardStore: store)

        let removedCount = viewModel.clearDoneTasks()

        #expect(removedCount == 2)
        #expect(viewModel.tasks.count == 1)
        #expect(viewModel.tasks.first?.id == todo.id)
        #expect(store.savedSnapshots.count == 1)
    }

    @Test("clear done tasks reports when there is nothing to clear")
    func clearDoneTasksNoopWithoutDoneTasks() {
        let todo = WorkTask(
            title: "Next task",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 3,
            status: .todo,
            assignedAgentID: nil
        )
        let store = SpyBoardStore()
        let viewModel = KanbanBoardViewModel(tasks: [todo], agents: [], boardStore: store)

        let removedCount = viewModel.clearDoneTasks()

        #expect(removedCount == 0)
        #expect(viewModel.lastBoardMessage == "No done tasks to archive")
        #expect(viewModel.lastBoardMessageSeverity?.rawValue == "warning")
        #expect(store.savedSnapshots.isEmpty)
    }

    @Test("rebalances overloaded todo assignments and persists once")
    func rebalancesOverloadedTodoAssignments() {
        let overloaded = AgentProfile(name: "A Agent", skills: ["swiftui"], maxConcurrentTasks: 2)
        let available = AgentProfile(name: "B Agent", skills: ["swiftui"], maxConcurrentTasks: 3)
        let taskA = WorkTask(
            title: "Task A",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 2,
            status: .todo,
            assignedAgentID: overloaded.id
        )
        let taskB = WorkTask(
            title: "Task B",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 1,
            status: .todo,
            assignedAgentID: overloaded.id
        )
        let taskC = WorkTask(
            title: "Task C",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 3,
            status: .todo,
            assignedAgentID: overloaded.id
        )
        let store = SpyBoardStore()
        let viewModel = KanbanBoardViewModel(
            tasks: [taskA, taskB, taskC],
            agents: [overloaded, available],
            boardStore: store
        )

        let movedCount = viewModel.rebalanceTodoAssignments()

        #expect(movedCount == 1)
        #expect(viewModel.activeTaskCount(for: overloaded.id) == 2)
        #expect(viewModel.activeTaskCount(for: available.id) == 1)
        #expect(store.savedSnapshots.count == 1)
    }

    @Test("rebalance chooses lower-load target first and breaks ties by name")
    func rebalanceChoosesLowerLoadTargetThenName() {
        let overloaded = AgentProfile(name: "Overloaded", skills: ["swiftui"], maxConcurrentTasks: 1)
        let alpha = AgentProfile(name: "Alpha", skills: ["swiftui"], maxConcurrentTasks: 2)
        let beta = AgentProfile(name: "Beta", skills: ["swiftui"], maxConcurrentTasks: 2)
        let gammaLoaded = AgentProfile(name: "Gamma", skills: ["swiftui"], maxConcurrentTasks: 2)

        let overloadedTaskA = WorkTask(
            title: "Task A",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 1,
            status: .todo,
            assignedAgentID: overloaded.id
        )
        let overloadedTaskB = WorkTask(
            title: "Task B",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 2,
            status: .todo,
            assignedAgentID: overloaded.id
        )
        let overloadedTaskC = WorkTask(
            title: "Task C",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 3,
            status: .todo,
            assignedAgentID: overloaded.id
        )
        let gammaExisting = WorkTask(
            title: "Gamma Busy",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 1,
            status: .inProgress,
            assignedAgentID: gammaLoaded.id
        )
        let viewModel = KanbanBoardViewModel(
            tasks: [overloadedTaskA, overloadedTaskB, overloadedTaskC, gammaExisting],
            agents: [overloaded, beta, alpha, gammaLoaded]
        )

        let movedCount = viewModel.rebalanceTodoAssignments()

        #expect(movedCount == 2)
        #expect(viewModel.activeTaskCount(for: overloaded.id) == 1)
        #expect(viewModel.activeTaskCount(for: alpha.id) == 1)
        #expect(viewModel.activeTaskCount(for: beta.id) == 1)
        #expect(viewModel.activeTaskCount(for: gammaLoaded.id) == 1)
    }

    @Test("rebalance does not move in-progress assignments")
    func rebalanceDoesNotMoveInProgressAssignments() {
        let overloaded = AgentProfile(name: "A Agent", skills: ["swiftui"], maxConcurrentTasks: 1)
        let available = AgentProfile(name: "B Agent", skills: ["swiftui"], maxConcurrentTasks: 3)
        let inProgress = WorkTask(
            title: "In Progress",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 2,
            status: .inProgress,
            assignedAgentID: overloaded.id
        )
        let store = SpyBoardStore()
        let viewModel = KanbanBoardViewModel(
            tasks: [inProgress],
            agents: [overloaded, available],
            boardStore: store
        )

        let movedCount = viewModel.rebalanceTodoAssignments()

        #expect(movedCount == 0)
        #expect(viewModel.tasks.first?.assignedAgentID == overloaded.id)
        #expect(viewModel.lastBoardMessage == "No todo rebalancing needed")
        #expect(viewModel.lastBoardMessageSeverity?.rawValue == "warning")
        #expect(store.savedSnapshots.isEmpty)
    }

    @Test("unassigns all todo tasks for a specific agent")
    func unassignsAgentTodoTasks() {
        let agent = AgentProfile(name: "UI Agent", skills: ["swiftui"], maxConcurrentTasks: 3)
        let todoA = WorkTask(
            title: "Todo A",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 1,
            status: .todo,
            assignedAgentID: agent.id
        )
        let todoB = WorkTask(
            title: "Todo B",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 2,
            status: .todo,
            assignedAgentID: agent.id
        )
        let inProgress = WorkTask(
            title: "In Progress",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 3,
            status: .inProgress,
            assignedAgentID: agent.id
        )
        let store = SpyBoardStore()
        let viewModel = KanbanBoardViewModel(tasks: [todoA, todoB, inProgress], agents: [agent], boardStore: store)

        let count = viewModel.unassignTodoTasks(for: agent.id)

        #expect(count == 2)
        #expect(viewModel.tasks.first(where: { $0.id == todoA.id })?.assignedAgentID == nil)
        #expect(viewModel.tasks.first(where: { $0.id == todoB.id })?.assignedAgentID == nil)
        #expect(viewModel.tasks.first(where: { $0.id == inProgress.id })?.assignedAgentID == agent.id)
        #expect(store.savedSnapshots.count == 1)
    }

    @Test("unassign agent todo tasks reports when nothing can be unassigned")
    func unassignAgentTodoTasksNoop() {
        let agent = AgentProfile(name: "UI Agent", skills: ["swiftui"], maxConcurrentTasks: 3)
        let inProgress = WorkTask(
            title: "In Progress",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 3,
            status: .inProgress,
            assignedAgentID: agent.id
        )
        let store = SpyBoardStore()
        let viewModel = KanbanBoardViewModel(tasks: [inProgress], agents: [agent], boardStore: store)

        let count = viewModel.unassignTodoTasks(for: agent.id)

        #expect(count == 0)
        #expect(viewModel.lastBoardMessage == "No todo tasks assigned to selected agent")
        #expect(viewModel.lastBoardMessageSeverity?.rawValue == "warning")
        #expect(store.savedSnapshots.isEmpty)
    }

    @Test("updating task skills can unassign incompatible agent")
    func updateTaskUnassignsIncompatibleAgent() {
        let agent = AgentProfile(name: "UI Agent", skills: ["swiftui"], maxConcurrentTasks: 2)
        let task = WorkTask(
            title: "Build board",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 2,
            status: .todo,
            assignedAgentID: agent.id
        )
        let store = SpyBoardStore()
        let viewModel = KanbanBoardViewModel(tasks: [task], agents: [agent], boardStore: store)

        let updated = viewModel.updateTask(
            task.id,
            title: "Build board",
            details: "",
            requiredSkillsText: "backend",
            storyPoints: 2
        )

        #expect(updated)
        #expect(viewModel.tasks[0].assignedAgentID == nil)
        #expect(viewModel.assignmentReason(for: task.id) == nil)
        #expect(viewModel.triageCandidates().contains(where: { $0.id == task.id }))
        #expect(store.savedSnapshots.count == 1)
    }

    @Test("updating task clears assignment when assigned agent no longer exists")
    func updateTaskUnassignsMissingAssignedAgent() {
        let missingAgentID = UUID()
        let task = WorkTask(
            title: "Orphaned assignment",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 2,
            status: .todo,
            assignedAgentID: missingAgentID
        )
        let viewModel = KanbanBoardViewModel(tasks: [task], agents: [])

        let updated = viewModel.updateTask(
            task.id,
            title: "Orphaned assignment",
            details: "",
            requiredSkillsText: "swiftui",
            storyPoints: 2
        )

        #expect(updated)
        #expect(viewModel.tasks[0].assignedAgentID == nil)
        #expect(viewModel.triageCandidates().contains(where: { $0.id == task.id }))
    }

    @Test("updating non-todo task with missing assignee does not create triage candidate")
    func updateTaskMissingAssigneeOnReviewTaskDoesNotCreateTriageCandidate() {
        let missingAgentID = UUID()
        let task = WorkTask(
            title: "Review assignment",
            details: "",
            requiredSkills: ["testing"],
            storyPoints: 1,
            status: .review,
            assignedAgentID: missingAgentID
        )
        let viewModel = KanbanBoardViewModel(tasks: [task], agents: [])

        let updated = viewModel.updateTask(
            task.id,
            title: "Review assignment",
            details: "",
            requiredSkillsText: "testing",
            storyPoints: 1
        )

        #expect(updated)
        #expect(viewModel.tasks[0].assignedAgentID == nil)
        #expect(viewModel.triageCandidates().isEmpty)
    }

    @Test("adds agent with parsed skills and persists board snapshot")
    func addsAgentAndPersists() {
        let store = SpyBoardStore()
        let viewModel = KanbanBoardViewModel(tasks: [], agents: [], boardStore: store)

        let added = viewModel.addAgent(
            name: "Platform Agent",
            skillsText: "api, db, swiftui",
            maxConcurrentTasks: 4
        )

        #expect(added)
        #expect(viewModel.agents.count == 1)
        #expect(viewModel.agents[0].name == "Platform Agent")
        #expect(viewModel.agents[0].skills == Set(["api", "db", "swiftui"]))
        #expect(viewModel.agents[0].maxConcurrentTasks == 4)
        #expect(store.savedSnapshots.count == 1)
        #expect(store.savedSnapshots.last?.agents.count == 1)
    }

    @Test("adds agent with runtime profile and persists normalized runtime fields")
    func addsAgentWithRuntimeProfileAndPersists() {
        let store = SpyBoardStore()
        let viewModel = KanbanBoardViewModel(tasks: [], agents: [], boardStore: store)
        let runtime = AgentRuntimeProfile(
            provider: .openAICompatible,
            model: " ",
            endpoint: " https://api.example.com/v1 ",
            tools: [" Browser ", "code", "browser"]
        )

        let added = viewModel.addAgent(
            name: "Automation Agent",
            skillsText: "swiftui, automation",
            maxConcurrentTasks: 2,
            runtimeProfile: runtime
        )

        #expect(added)
        #expect(viewModel.agents.count == 1)
        #expect(viewModel.agents[0].runtimeProfile?.provider == .openAICompatible)
        #expect(viewModel.agents[0].runtimeProfile?.model == "gpt-4.1-mini")
        #expect(viewModel.agents[0].runtimeProfile?.endpoint == "https://api.example.com/v1")
        #expect(viewModel.agents[0].runtimeProfile?.tools == Set(["browser", "code"]))
        #expect(store.savedSnapshots.count == 1)
    }

    @Test("rejects adding agent with empty name")
    func rejectsAgentWithEmptyName() {
        let store = SpyBoardStore()
        let viewModel = KanbanBoardViewModel(tasks: [], agents: [], boardStore: store)

        let added = viewModel.addAgent(
            name: "   ",
            skillsText: "swiftui",
            maxConcurrentTasks: 2
        )

        #expect(!added)
        #expect(viewModel.agents.isEmpty)
        #expect(viewModel.lastBoardMessage == "Agent name is required")
        #expect(store.savedSnapshots.isEmpty)
    }

    @Test("updates agent profile and persists snapshot")
    func updatesAgentProfileAndPersists() {
        let agent = AgentProfile(name: "UI Agent", skills: ["swiftui"], maxConcurrentTasks: 2)
        let store = SpyBoardStore()
        let viewModel = KanbanBoardViewModel(tasks: [], agents: [agent], boardStore: store)

        let updated = viewModel.updateAgent(
            agent.id,
            name: "Platform Agent",
            skillsText: "api, db, swiftui",
            maxConcurrentTasks: 4
        )

        #expect(updated)
        #expect(viewModel.agents.count == 1)
        #expect(viewModel.agents[0].name == "Platform Agent")
        #expect(viewModel.agents[0].skills == Set(["api", "db", "swiftui"]))
        #expect(viewModel.agents[0].maxConcurrentTasks == 4)
        #expect(store.savedSnapshots.count == 1)
    }

    @Test("updates agent runtime profile and can disable runtime")
    func updatesAgentRuntimeProfileAndCanDisable() {
        let agent = AgentProfile(
            name: "Ops Agent",
            skills: ["swiftui"],
            maxConcurrentTasks: 2,
            runtimeProfile: AgentRuntimeProfile(provider: .localMock, model: "mock-v2", tools: ["triage"])
        )
        let store = SpyBoardStore()
        let viewModel = KanbanBoardViewModel(tasks: [], agents: [agent], boardStore: store)

        let updatedWithRuntime = viewModel.updateAgent(
            agent.id,
            name: "Ops Agent",
            skillsText: "swiftui",
            maxConcurrentTasks: 2,
            runtimeProfile: AgentRuntimeProfile(
                provider: .openAICompatible,
                model: "gpt-4.1",
                endpoint: "https://proxy.example.com",
                tools: ["planner", "runner"]
            )
        )

        #expect(updatedWithRuntime)
        #expect(viewModel.agents[0].runtimeProfile?.provider == .openAICompatible)
        #expect(viewModel.agents[0].runtimeProfile?.model == "gpt-4.1")
        #expect(viewModel.agents[0].runtimeProfile?.endpoint == "https://proxy.example.com")
        #expect(viewModel.agents[0].runtimeProfile?.tools == Set(["planner", "runner"]))

        let disabledRuntime = viewModel.updateAgent(
            agent.id,
            name: "Ops Agent",
            skillsText: "swiftui",
            maxConcurrentTasks: 2,
            runtimeProfile: nil
        )

        #expect(disabledRuntime)
        #expect(viewModel.agents[0].runtimeProfile == nil)
        #expect(store.savedSnapshots.count == 2)
    }

    @Test("updating agent skills can unassign incompatible todo tasks")
    func updateAgentUnassignsIncompatibleTodoTasks() {
        let agent = AgentProfile(name: "UI Agent", skills: ["swiftui", "ui"], maxConcurrentTasks: 2)
        let task = WorkTask(
            title: "Build board",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 2,
            status: .todo,
            assignedAgentID: agent.id
        )
        let store = SpyBoardStore()
        let viewModel = KanbanBoardViewModel(tasks: [task], agents: [agent], boardStore: store)

        let updated = viewModel.updateAgent(
            agent.id,
            name: "UI Agent",
            skillsText: "backend",
            maxConcurrentTasks: 2
        )

        #expect(updated)
        #expect(viewModel.tasks[0].assignedAgentID == nil)
        #expect(viewModel.assignmentReason(for: task.id) == nil)
        #expect(viewModel.triageCandidates().contains(where: { $0.id == task.id }))
        #expect(store.savedSnapshots.count == 1)
    }

    @Test("rejects updating agent when name is empty")
    func rejectsUpdatingAgentWithEmptyName() {
        let agent = AgentProfile(name: "UI Agent", skills: ["swiftui"], maxConcurrentTasks: 2)
        let store = SpyBoardStore()
        let viewModel = KanbanBoardViewModel(tasks: [], agents: [agent], boardStore: store)

        let updated = viewModel.updateAgent(
            agent.id,
            name: "  ",
            skillsText: "swiftui",
            maxConcurrentTasks: 2
        )

        #expect(!updated)
        #expect(viewModel.agents[0].name == "UI Agent")
        #expect(viewModel.lastBoardMessage == "Agent name is required")
        #expect(store.savedSnapshots.isEmpty)
    }

    @Test("rejects reducing agent capacity below current active load")
    func rejectsReducingAgentCapacityBelowLoad() {
        let agent = AgentProfile(name: "UI Agent", skills: ["swiftui"], maxConcurrentTasks: 3)
        let activeA = WorkTask(
            title: "Task A",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 2,
            status: .inProgress,
            assignedAgentID: agent.id
        )
        let activeB = WorkTask(
            title: "Task B",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 1,
            status: .review,
            assignedAgentID: agent.id
        )
        let store = SpyBoardStore()
        let viewModel = KanbanBoardViewModel(tasks: [activeA, activeB], agents: [agent], boardStore: store)

        let updated = viewModel.updateAgent(
            agent.id,
            name: "UI Agent",
            skillsText: "swiftui",
            maxConcurrentTasks: 1
        )

        #expect(!updated)
        #expect(viewModel.agents[0].maxConcurrentTasks == 3)
        #expect(viewModel.lastBoardMessage == "Cannot set capacity below current load (2)")
        #expect(store.savedSnapshots.isEmpty)
    }

    @Test("newly added agent participates in auto assignment")
    func addedAgentCanReceiveAutoAssignedTask() {
        let task = WorkTask(
            title: "Build board",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 3,
            status: .todo,
            assignedAgentID: nil
        )
        let viewModel = KanbanBoardViewModel(tasks: [task], agents: [])
        _ = viewModel.addAgent(name: "UI Agent", skillsText: "swiftui, ui", maxConcurrentTasks: 2)

        viewModel.autoAssignTasks()

        #expect(viewModel.tasks.first?.assignedAgentID == viewModel.agents.first?.id)
    }

    @Test("removing agent unassigns their tasks and persists snapshot")
    func removesAgentUnassignsTasksAndPersists() {
        let agent = AgentProfile(name: "UI Agent", skills: ["swiftui"], maxConcurrentTasks: 2)
        let ownedTask = WorkTask(
            title: "Assigned work",
            details: "",
            requiredSkills: ["swiftui"],
            storyPoints: 2,
            status: .todo,
            assignedAgentID: agent.id
        )
        let store = SpyBoardStore()
        let viewModel = KanbanBoardViewModel(tasks: [ownedTask], agents: [agent], boardStore: store)

        let removed = viewModel.removeAgent(agent.id)

        #expect(removed)
        #expect(viewModel.agents.isEmpty)
        #expect(viewModel.tasks.first?.assignedAgentID == nil)
        #expect(viewModel.triageCandidates().count == 1)
        #expect(store.savedSnapshots.count == 1)
    }

    @Test("run task execution in background updates record and completion")
    func runTaskExecutionInBackgroundUpdatesRecord() {
        let agent = AgentProfile(name: "Executor", skills: ["swiftui"], maxConcurrentTasks: 2)
        let task = WorkTask(
            title: "Background run",
            details: "Do work",
            requiredSkills: ["swiftui"],
            storyPoints: 2,
            status: .todo,
            assignedAgentID: agent.id
        )
        let store = SpyBoardStore()
        let executor = StubTaskExecutor(
            outcomesByTaskID: [task.id: .success(summary: "Background succeeded")],
            progressUpdatesByTaskID: [task.id: ["step 1", "step 2"]]
        )
        let viewModel = KanbanBoardViewModel(
            tasks: [task],
            agents: [agent],
            taskExecutor: executor,
            boardStore: store,
            runOnBackground: { work in work() },
            runOnMain: { work in work() }
        )

        var completionValue: Bool?
        viewModel.runTaskExecutionInBackground(task.id) { didRun in
            completionValue = didRun
        }

        #expect(waitForMainQueue(timeout: 12.0) { completionValue != nil })
        #expect(completionValue == true)
        #expect(viewModel.tasks[0].status == .review)
        #expect(viewModel.tasks[0].executionRecord?.status == .succeeded)
        #expect(viewModel.executionEvents(for: agent.id).count >= 3)
    }

    @Test("run task execution in background rejects task without details")
    func runTaskExecutionInBackgroundRejectsMissingDetails() {
        let agent = AgentProfile(name: "Executor", skills: ["swiftui"], maxConcurrentTasks: 2)
        let task = WorkTask(
            title: "Missing details",
            details: "  ",
            requiredSkills: ["swiftui"],
            storyPoints: 1,
            status: .todo,
            assignedAgentID: agent.id
        )
        let viewModel = KanbanBoardViewModel(
            tasks: [task],
            agents: [agent],
            taskExecutor: StubTaskExecutor()
        )

        var completionValue: Bool?
        viewModel.runTaskExecutionInBackground(task.id) { didRun in
            completionValue = didRun
        }

        #expect(waitForMainQueue { completionValue != nil })
        #expect(completionValue == false)
        #expect(viewModel.lastBoardMessage == "Task details are required before running this task")
    }

    @Test("retry task execution in background reruns failed task")
    func retryTaskExecutionInBackgroundRerunsFailedTask() {
        let agent = AgentProfile(name: "Executor", skills: ["swiftui"], maxConcurrentTasks: 2)
        let task = WorkTask(
            title: "Retry me",
            details: "Allow retry",
            requiredSkills: ["swiftui"],
            storyPoints: 1,
            status: .inProgress,
            assignedAgentID: agent.id,
            executionRecord: TaskExecutionRecord(
                status: .failed,
                runCount: 1,
                lastError: "Initial failure"
            )
        )
        let executor = StubTaskExecutor(
            outcomesByTaskID: [task.id: .success(summary: "Retry success")],
            progressUpdatesByTaskID: [task.id: ["Retry step"]]
        )
        let viewModel = KanbanBoardViewModel(
            tasks: [task],
            agents: [agent],
            taskExecutor: executor,
            runOnBackground: { work in work() },
            runOnMain: { work in work() }
        )

        var completionValue: Bool?
        viewModel.retryTaskExecutionInBackground(task.id) { didRun in
            completionValue = didRun
        }

        #expect(waitForMainQueue(timeout: 12.0) { completionValue != nil })
        #expect(completionValue == true)
        #expect(viewModel.tasks[0].executionRecord?.status == .succeeded)
        #expect(viewModel.tasks[0].executionRecord?.runCount == 2)
        #expect(viewModel.executionEvents(for: agent.id).contains(where: { $0.message == "Retry step" }))
    }

    @Test("retry task execution in background rejects non-failed task")
    func retryTaskExecutionInBackgroundRejectsNonFailedTask() {
        let agent = AgentProfile(name: "Executor", skills: ["swiftui"], maxConcurrentTasks: 2)
        let task = WorkTask(
            title: "Not failed",
            details: "Already fine",
            requiredSkills: ["swiftui"],
            storyPoints: 1,
            status: .review,
            assignedAgentID: agent.id,
            executionRecord: TaskExecutionRecord(status: .succeeded, runCount: 1)
        )
        let viewModel = KanbanBoardViewModel(
            tasks: [task],
            agents: [agent],
            taskExecutor: StubTaskExecutor()
        )

        var completionValue: Bool?
        viewModel.retryTaskExecutionInBackground(task.id) { didRun in
            completionValue = didRun
        }

        #expect(waitForMainQueue { completionValue != nil })
        #expect(completionValue == false)
        #expect(viewModel.lastBoardMessage == "Only failed executions can be retried")
    }

    @Test("run assigned executions in background processes assigned queue")
    func runAssignedTaskExecutionsInBackgroundProcessesQueue() {
        let agent = AgentProfile(name: "Executor", skills: ["swiftui"], maxConcurrentTasks: 3)
        let successTask = WorkTask(
            title: "Background success",
            details: "Detailed task",
            requiredSkills: ["swiftui"],
            storyPoints: 3,
            status: .todo,
            assignedAgentID: agent.id
        )
        let failedTask = WorkTask(
            title: "Background fail",
            details: "Also detailed",
            requiredSkills: ["swiftui"],
            storyPoints: 2,
            status: .todo,
            assignedAgentID: agent.id
        )
        let executor = StubTaskExecutor(
            outcomesByTaskID: [
                successTask.id: .success(summary: "ok"),
                failedTask.id: .failure(message: "boom")
            ]
        )
        let viewModel = KanbanBoardViewModel(
            tasks: [successTask, failedTask],
            agents: [agent],
            taskExecutor: executor,
            runOnBackground: { work in work() },
            runOnMain: { work in work() }
        )

        var startedCount: Int?
        viewModel.runAssignedTaskExecutionsInBackground { started in
            startedCount = started
        }

        #expect(waitForMainQueue(timeout: 15.0) { startedCount != nil })
        #expect(startedCount == 2)
        #expect(viewModel.lastBoardMessage?.contains("Batch run finished") == true)
        #expect(viewModel.lastBoardMessage?.contains("2 started") == true)
        #expect(viewModel.lastBoardMessage?.contains("1 succeeded") == true)
        #expect(viewModel.lastBoardMessage?.contains("1 failed") == true)
    }

    @Test("run assigned executions in background warns when assigned tasks have empty details")
    func runAssignedTaskExecutionsInBackgroundWarnsForEmptyDetails() {
        let agent = AgentProfile(name: "Executor", skills: ["swiftui"], maxConcurrentTasks: 2)
        let task = WorkTask(
            title: "Blocked assigned",
            details: "  ",
            requiredSkills: ["swiftui"],
            storyPoints: 1,
            status: .todo,
            assignedAgentID: agent.id
        )
        let viewModel = KanbanBoardViewModel(
            tasks: [task],
            agents: [agent],
            taskExecutor: StubTaskExecutor()
        )

        var startedCount: Int?
        viewModel.runAssignedTaskExecutionsInBackground { started in
            startedCount = started
        }

        #expect(waitForMainQueue { startedCount != nil })
        #expect(startedCount == 0)
        #expect(viewModel.lastBoardMessage == "1 assigned task with empty details. Fill details before batch run.")
        #expect(viewModel.lastBoardMessageSeverity == .warning)
    }

    @Test("background batch run includes skipped count when assignment is invalid")
    func runAssignedTaskExecutionsInBackgroundCountsSkippedTasks() {
        let agent = AgentProfile(name: "Executor", skills: ["swiftui"], maxConcurrentTasks: 3)
        let runnableTask = WorkTask(
            title: "Background runnable",
            details: "Detailed task",
            requiredSkills: ["swiftui"],
            storyPoints: 3,
            status: .todo,
            assignedAgentID: agent.id
        )
        let invalidAssignmentTask = WorkTask(
            title: "Background ghost assignment",
            details: "Detailed but unknown assignee",
            requiredSkills: ["swiftui"],
            storyPoints: 2,
            status: .todo,
            assignedAgentID: UUID()
        )
        let executor = StubTaskExecutor(
            outcomesByTaskID: [runnableTask.id: .success(summary: "ok")]
        )
        let viewModel = KanbanBoardViewModel(
            tasks: [runnableTask, invalidAssignmentTask],
            agents: [agent],
            taskExecutor: executor,
            runOnBackground: { work in work() },
            runOnMain: { work in work() }
        )

        var startedCount: Int?
        viewModel.runAssignedTaskExecutionsInBackground { started in
            startedCount = started
        }

        #expect(waitForMainQueue(timeout: 15.0) { startedCount != nil })
        #expect(startedCount == 1)
        #expect(viewModel.lastBoardMessage?.contains("1 skipped") == true)
        #expect(viewModel.lastBoardMessageSeverity == .warning)
    }

    @Test("background batch run drains dependency chain in a single run")
    func runAssignedTaskExecutionsInBackgroundDrainsDependencyChain() {
        let agent = AgentProfile(name: "Executor", skills: ["swiftui"], maxConcurrentTasks: 3)
        let prerequisite = WorkTask(
            title: "API Spec",
            details: "Finalize API contract",
            requiredSkills: ["swiftui"],
            storyPoints: 3,
            status: .todo,
            assignedAgentID: agent.id
        )
        let dependent = WorkTask(
            title: "Client Integration",
            details: """
            Depends on: API Spec
            Integrate client flow.
            """,
            requiredSkills: ["swiftui"],
            storyPoints: 2,
            status: .todo,
            assignedAgentID: agent.id
        )
        let executor = StubTaskExecutor(
            outcomesByTaskID: [
                prerequisite.id: .success(summary: "spec done"),
                dependent.id: .success(summary: "integration done")
            ]
        )
        let viewModel = KanbanBoardViewModel(
            tasks: [dependent, prerequisite],
            agents: [agent],
            taskExecutor: executor,
            runOnBackground: { work in work() },
            runOnMain: { work in work() }
        )

        var startedCount: Int?
        viewModel.runAssignedTaskExecutionsInBackground { started in
            startedCount = started
        }

        #expect(waitForMainQueue(timeout: 15.0) { startedCount != nil })
        #expect(startedCount == 2)
        #expect(viewModel.tasks.first(where: { $0.id == prerequisite.id })?.executionRecord?.status == .succeeded)
        #expect(viewModel.tasks.first(where: { $0.id == dependent.id })?.executionRecord?.status == .succeeded)
    }

    @Test("background batch run can be cancelled between tasks")
    func runAssignedTaskExecutionsInBackgroundCanCancelQueue() {
        let agent = AgentProfile(name: "Executor", skills: ["swiftui"], maxConcurrentTasks: 3)
        let first = WorkTask(
            title: "First",
            details: "Detailed task",
            requiredSkills: ["swiftui"],
            storyPoints: 1,
            status: .todo,
            assignedAgentID: agent.id
        )
        let second = WorkTask(
            title: "Second",
            details: "Detailed task",
            requiredSkills: ["swiftui"],
            storyPoints: 1,
            status: .todo,
            assignedAgentID: agent.id
        )
        let executor = HookedTaskExecutor(
            outcomesByTaskID: [
                first.id: .success(summary: "ok"),
                second.id: .success(summary: "ok")
            ]
        )
        var viewModel: KanbanBoardViewModel!
        viewModel = KanbanBoardViewModel(
            tasks: [first, second],
            agents: [agent],
            taskExecutor: executor,
            runOnBackground: { work in work() },
            runOnMain: { work in work() }
        )
        executor.onExecute = { task in
            if task.id == first.id {
                viewModel.requestCancelAssignedTaskExecutions()
            }
        }

        var startedCount: Int?
        viewModel.runAssignedTaskExecutionsInBackground { started in
            startedCount = started
        }

        #expect(waitForMainQueue(timeout: 15.0) { startedCount != nil })
        #expect(startedCount == 1)
        #expect(viewModel.tasks.first(where: { $0.id == first.id })?.executionRecord?.status == .succeeded)
        #expect(viewModel.tasks.first(where: { $0.id == second.id })?.executionRecord == nil)
        #expect(viewModel.lastBoardMessage?.contains("Cancelled") == true)
        #expect(viewModel.lastBoardMessageSeverity == .warning)
        #expect(!viewModel.isBatchRunCancelRequested)
    }

    @Test("auto cycle runs multiple passes until assigned queue is drained")
    func runAutoDispatchCycleInBackgroundRunsUntilStable() {
        let agent = AgentProfile(name: "Executor", skills: ["swiftui"], maxConcurrentTasks: 2)
        let task = WorkTask(
            title: "Auto cycle task",
            details: "Run end to end",
            requiredSkills: ["swiftui"],
            storyPoints: 2,
            status: .todo,
            assignedAgentID: agent.id
        )
        let executor = StubTaskExecutor(
            outcomesByTaskID: [task.id: .success(summary: "ok")]
        )
        let viewModel = KanbanBoardViewModel(
            tasks: [task],
            agents: [agent],
            taskExecutor: executor,
            runOnBackground: { work in work() },
            runOnMain: { work in work() }
        )

        var totalStarted: Int?
        var passes: Int?
        viewModel.runAutoDispatchCycleInBackground { started, completedPasses in
            totalStarted = started
            passes = completedPasses
        }

        #expect(waitForMainQueue(timeout: 15.0) { totalStarted != nil && passes != nil })
        #expect(totalStarted == 1)
        #expect(passes == 2)
        #expect(viewModel.lastBoardMessage?.contains("Auto cycle finished") == true)
        #expect(viewModel.lastBoardMessageSeverity == .info)
    }

    @Test("auto cycle summary reports remaining dependency blockers after execution")
    func runAutoDispatchCycleInBackgroundSummaryIncludesDependencyBlockers() {
        let agent = AgentProfile(name: "Executor", skills: ["swiftui"], maxConcurrentTasks: 3)
        let runnable = WorkTask(
            title: "Design Spec",
            details: "Finalize spec",
            requiredSkills: ["swiftui"],
            storyPoints: 3,
            status: .todo,
            assignedAgentID: agent.id
        )
        let blocked = WorkTask(
            title: "Implementation",
            details: """
            Depends on: External API
            Build implementation.
            """,
            requiredSkills: ["swiftui"],
            storyPoints: 2,
            status: .todo,
            assignedAgentID: agent.id
        )
        let executor = StubTaskExecutor(
            outcomesByTaskID: [runnable.id: .success(summary: "done")]
        )
        let viewModel = KanbanBoardViewModel(
            tasks: [blocked, runnable],
            agents: [agent],
            taskExecutor: executor,
            runOnBackground: { work in work() },
            runOnMain: { work in work() }
        )

        var totalStarted: Int?
        var passes: Int?
        viewModel.runAutoDispatchCycleInBackground { started, completedPasses in
            totalStarted = started
            passes = completedPasses
        }

        #expect(waitForMainQueue(timeout: 15.0) { totalStarted != nil && passes != nil })
        #expect(totalStarted == 1)
        #expect(passes == 2)
        #expect(viewModel.lastBoardMessage?.contains("Auto cycle finished") == true)
        #expect(viewModel.lastBoardMessage?.contains("1 blocked by dependencies") == true)
        #expect(viewModel.lastBoardMessageSeverity == .warning)
    }

    @Test("auto cycle honors max pass limit")
    func runAutoDispatchCycleInBackgroundHonorsMaxPasses() {
        let agent = AgentProfile(name: "Executor", skills: ["swiftui"], maxConcurrentTasks: 2)
        let task = WorkTask(
            title: "Auto cycle limited",
            details: "Run once",
            requiredSkills: ["swiftui"],
            storyPoints: 1,
            status: .todo,
            assignedAgentID: agent.id
        )
        let executor = StubTaskExecutor(
            outcomesByTaskID: [task.id: .success(summary: "ok")]
        )
        let viewModel = KanbanBoardViewModel(
            tasks: [task],
            agents: [agent],
            taskExecutor: executor,
            runOnBackground: { work in work() },
            runOnMain: { work in work() }
        )

        var totalStarted: Int?
        var passes: Int?
        viewModel.runAutoDispatchCycleInBackground(maxPasses: 1) { started, completedPasses in
            totalStarted = started
            passes = completedPasses
        }

        #expect(waitForMainQueue(timeout: 15.0) { totalStarted != nil && passes != nil })
        #expect(totalStarted == 1)
        #expect(passes == 1)
    }

    @Test("auto cycle auto-assigns eligible todo work before executing")
    func runAutoDispatchCycleInBackgroundAutoAssignsBeforeRun() {
        let agent = AgentProfile(name: "Executor", skills: ["swiftui"], maxConcurrentTasks: 2)
        let task = WorkTask(
            title: "Unassigned auto cycle",
            details: "Needs assignment first",
            requiredSkills: ["swiftui"],
            storyPoints: 1,
            status: .todo,
            assignedAgentID: nil
        )
        let executor = StubTaskExecutor(
            outcomesByTaskID: [task.id: .success(summary: "done")]
        )
        let viewModel = KanbanBoardViewModel(
            tasks: [task],
            agents: [agent],
            taskExecutor: executor,
            runOnBackground: { work in work() },
            runOnMain: { work in work() }
        )

        var totalStarted: Int?
        viewModel.runAutoDispatchCycleInBackground { started, _ in
            totalStarted = started
        }

        #expect(waitForMainQueue(timeout: 15.0) { totalStarted != nil })
        #expect(totalStarted == 1)
        #expect(viewModel.tasks.first?.assignedAgentID == agent.id)
        #expect(viewModel.tasks.first?.executionRecord?.status == .succeeded)
    }

    @Test("auto cycle can auto-create missing dependency tasks and unblock execution")
    func runAutoDispatchCycleInBackgroundAutoCreatesMissingDependencies() {
        let agent = AgentProfile(name: "Executor", skills: ["swiftui"], maxConcurrentTasks: 3)
        let blocked = WorkTask(
            title: "Implementation",
            details: """
            Depends on: External API
            Build implementation.
            """,
            requiredSkills: ["swiftui"],
            storyPoints: 3,
            status: .todo,
            assignedAgentID: agent.id
        )
        let viewModel = KanbanBoardViewModel(
            tasks: [blocked],
            agents: [agent],
            taskExecutor: StubTaskExecutor(),
            runOnBackground: { work in work() },
            runOnMain: { work in work() }
        )

        var totalStarted: Int?
        var passes: Int?
        viewModel.runAutoDispatchCycleInBackground(
            autoCreateMissingDependencies: true
        ) { started, completedPasses in
            totalStarted = started
            passes = completedPasses
        }

        #expect(waitForMainQueue(timeout: 15.0) { totalStarted != nil && passes != nil })
        #expect(totalStarted == 2)
        #expect(passes == 2)
        let dependencyTask = viewModel.tasks.first(where: { $0.title == "External API" })
        #expect(dependencyTask != nil)
        #expect(dependencyTask?.executionRecord?.status == .succeeded)
        #expect(viewModel.tasks.first(where: { $0.title == "Implementation" })?.executionRecord?.status == .succeeded)
        #expect(viewModel.lastAutoCycleCreatedDependencyTaskCount == 1)
        #expect(viewModel.lastBoardMessage?.contains("Created 1 dependency placeholder task(s)") == true)
        #expect(viewModel.lastBoardMessageSeverity == .info)
    }

    @Test("auto cycle preserves warning when no runnable assigned tasks exist")
    func runAutoDispatchCycleInBackgroundReportsNoRunnableTasks() {
        let agent = AgentProfile(name: "Executor", skills: ["swiftui"], maxConcurrentTasks: 2)
        let blockedTask = WorkTask(
            title: "Blocked",
            details: "  ",
            requiredSkills: ["swiftui"],
            storyPoints: 1,
            status: .todo,
            assignedAgentID: agent.id
        )
        let viewModel = KanbanBoardViewModel(
            tasks: [blockedTask],
            agents: [agent],
            taskExecutor: StubTaskExecutor(),
            runOnBackground: { work in work() },
            runOnMain: { work in work() }
        )

        var totalStarted: Int?
        var passes: Int?
        viewModel.runAutoDispatchCycleInBackground { started, completedPasses in
            totalStarted = started
            passes = completedPasses
        }

        #expect(waitForMainQueue(timeout: 15.0) { totalStarted != nil && passes != nil })
        #expect(totalStarted == 0)
        #expect(passes == 1)
        #expect(viewModel.lastBoardMessage == "1 assigned task with empty details. Fill details before batch run.")
        #expect(viewModel.lastBoardMessageSeverity == .warning)
    }

    @Test("auto cycle can be cancelled during active execution")
    func runAutoDispatchCycleInBackgroundCanCancel() {
        let agent = AgentProfile(name: "Executor", skills: ["swiftui"], maxConcurrentTasks: 2)
        let task = WorkTask(
            title: "Auto cycle cancellable",
            details: "Run once",
            requiredSkills: ["swiftui"],
            storyPoints: 1,
            status: .todo,
            assignedAgentID: agent.id
        )
        let executor = HookedTaskExecutor(
            outcomesByTaskID: [task.id: .success(summary: "ok")]
        )
        var viewModel: KanbanBoardViewModel!
        viewModel = KanbanBoardViewModel(
            tasks: [task],
            agents: [agent],
            taskExecutor: executor,
            runOnBackground: { work in work() },
            runOnMain: { work in work() }
        )
        executor.onExecute = { _ in
            viewModel.requestCancelAutoDispatchCycle()
        }

        var totalStarted: Int?
        var passes: Int?
        viewModel.runAutoDispatchCycleInBackground { started, completedPasses in
            totalStarted = started
            passes = completedPasses
        }

        #expect(waitForMainQueue(timeout: 15.0) { totalStarted != nil && passes != nil })
        #expect(totalStarted == 1)
        #expect(passes == 1)
        #expect(viewModel.lastBoardMessage?.contains("Cancelled") == true)
        #expect(viewModel.lastBoardMessageSeverity == .warning)
        #expect(!viewModel.isAutoCycleCancelRequested)
    }

    @Test("pm autopilot bootstraps agents, creates tickets, and runs auto cycle")
    func runPMAutopilotInBackgroundEndToEnd() {
        let plannedTickets = [
            PMPlannedTicket(
                title: "Core UI",
                details: "Implement views",
                requiredSkills: ["swiftui"],
                storyPoints: 3
            )
        ]
        let executor = StubTaskExecutor()
        let viewModel = KanbanBoardViewModel(
            tasks: [],
            agents: [],
            taskExecutor: executor,
            runOnBackground: { work in work() },
            runOnMain: { work in work() }
        )

        var createdAgents: Int?
        var createdTickets: Int?
        var startedExecutions: Int?
        var completedPasses: Int?
        viewModel.runPMAutopilotInBackground(plannedTickets: plannedTickets) { agents, tickets, executions, passes in
            createdAgents = agents
            createdTickets = tickets
            startedExecutions = executions
            completedPasses = passes
        }

        #expect(waitForMainQueue(timeout: 15.0) {
            createdAgents != nil &&
                createdTickets != nil &&
                startedExecutions != nil &&
                completedPasses != nil
        })
        #expect(createdAgents == 1)
        #expect(createdTickets == 1)
        #expect(startedExecutions == 1)
        #expect(completedPasses == 2)
        #expect(viewModel.agents.count == 1)
        #expect(viewModel.tasks.count == 1)
        #expect(viewModel.tasks.first?.executionRecord?.status == .succeeded)
        #expect(viewModel.lastBoardMessage?.contains("PM autopilot finished") == true)
    }

    @Test("pm autopilot summary reports dependency blockers left in backlog")
    func runPMAutopilotInBackgroundSummaryIncludesDependencyBlockers() {
        let plannedTickets = [
            PMPlannedTicket(
                title: "Design Spec",
                details: "Finalize UI spec",
                requiredSkills: ["swiftui"],
                storyPoints: 2
            ),
            PMPlannedTicket(
                title: "Implementation",
                details: """
                Depends on: External API
                Build implementation.
                """,
                requiredSkills: ["swiftui"],
                storyPoints: 3
            )
        ]
        let viewModel = KanbanBoardViewModel(
            tasks: [],
            agents: [],
            wipLimits: [.inProgress: 8, .review: 8],
            taskExecutor: StubTaskExecutor(),
            runOnBackground: { work in work() },
            runOnMain: { work in work() }
        )

        var startedExecutions: Int?
        viewModel.runPMAutopilotInBackground(
            plannedTickets: plannedTickets,
            autoAssign: true,
            autoCreateMissingDependenciesDuringCycle: false
        ) { _, _, executions, _ in
            startedExecutions = executions
        }

        #expect(waitForMainQueue(timeout: 15.0) { startedExecutions != nil })
        #expect(startedExecutions == 1)
        #expect(viewModel.lastBoardMessage?.contains("PM autopilot finished") == true)
        #expect(viewModel.lastBoardMessage?.contains("1 blocked by dependencies") == true)
        #expect(viewModel.lastBoardMessageSeverity == .warning)
    }

    @Test("pm autopilot auto-creates missing dependencies to unblock chained tickets")
    func runPMAutopilotInBackgroundAutoCreatesDependencies() {
        let plannedTickets = [
            PMPlannedTicket(
                title: "Design Spec",
                details: "Finalize UI spec",
                requiredSkills: ["swiftui"],
                storyPoints: 2
            ),
            PMPlannedTicket(
                title: "Implementation",
                details: """
                Depends on: External API
                Build implementation.
                """,
                requiredSkills: ["swiftui"],
                storyPoints: 3
            )
        ]
        let viewModel = KanbanBoardViewModel(
            tasks: [],
            agents: [],
            wipLimits: [.inProgress: 8, .review: 8],
            taskExecutor: StubTaskExecutor(),
            runOnBackground: { work in work() },
            runOnMain: { work in work() }
        )

        var startedExecutions: Int?
        viewModel.runPMAutopilotInBackground(
            plannedTickets: plannedTickets,
            autoAssign: true,
            autoCreateMissingDependenciesDuringCycle: true
        ) { _, _, executions, _ in
            startedExecutions = executions
        }

        #expect(waitForMainQueue(timeout: 15.0) { startedExecutions != nil })
        #expect(startedExecutions.map { $0 >= 3 } == true)
        #expect(viewModel.tasks.contains(where: { $0.title == "External API" }))
        #expect(viewModel.lastBoardMessage?.contains("PM autopilot finished") == true)
        #expect(viewModel.lastBoardMessage?.contains("Created 1 dependency placeholder task(s)") == true)
        #expect(viewModel.lastBoardMessage?.contains("blocked by dependencies") == false)
        #expect(viewModel.lastAutoCycleCreatedDependencyTaskCount == 1)
        #expect(viewModel.lastBoardMessageSeverity == BoardMessageSeverity.info)
    }

    @Test("pm autopilot forwards max pass limit to auto cycle")
    func runPMAutopilotInBackgroundHonorsMaxPasses() {
        let plannedTickets = [
            PMPlannedTicket(
                title: "Core UI",
                details: "Implement views",
                requiredSkills: ["swiftui"],
                storyPoints: 3
            )
        ]
        let viewModel = KanbanBoardViewModel(
            tasks: [],
            agents: [],
            taskExecutor: StubTaskExecutor(),
            runOnBackground: { work in work() },
            runOnMain: { work in work() }
        )

        var completedPasses: Int?
        viewModel.runPMAutopilotInBackground(
            plannedTickets: plannedTickets,
            autoAssign: true,
            maxAutoCyclePasses: 1
        ) { _, _, _, passes in
            completedPasses = passes
        }

        #expect(waitForMainQueue(timeout: 15.0) { completedPasses != nil })
        #expect(completedPasses == 1)
    }

    @Test("pm autopilot warns when no planned tickets are provided")
    func runPMAutopilotInBackgroundRequiresTickets() {
        let viewModel = KanbanBoardViewModel(
            tasks: [],
            agents: [],
            taskExecutor: StubTaskExecutor(),
            runOnBackground: { work in work() },
            runOnMain: { work in work() }
        )

        var createdAgents: Int?
        var createdTickets: Int?
        var startedExecutions: Int?
        var completedPasses: Int?
        viewModel.runPMAutopilotInBackground(plannedTickets: []) { agents, tickets, executions, passes in
            createdAgents = agents
            createdTickets = tickets
            startedExecutions = executions
            completedPasses = passes
        }

        #expect(waitForMainQueue(timeout: 15.0) {
            createdAgents != nil &&
                createdTickets != nil &&
                startedExecutions != nil &&
                completedPasses != nil
        })
        #expect(createdAgents == 0)
        #expect(createdTickets == 0)
        #expect(startedExecutions == 0)
        #expect(completedPasses == 0)
        #expect(viewModel.lastBoardMessage == "PM autopilot requires at least one planned ticket")
        #expect(viewModel.lastBoardMessageSeverity == .warning)
    }

    @Test("workspace import preview from file URL supports success and read failure")
    func workspaceImportPreviewFromURL() throws {
        let task = WorkTask(
            title: "Imported Task",
            details: "from file",
            requiredSkills: ["swiftui"],
            storyPoints: 2,
            status: .todo,
            assignedAgentID: nil
        )
        let viewModel = KanbanBoardViewModel(tasks: [task], agents: [])

        let tempFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("openmac-preview-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: tempFile) }

        let data = try #require(viewModel.workspaceExportData())
        try data.write(to: tempFile, options: .atomic)

        let preview = viewModel.workspaceImportPreview(from: tempFile)
        #expect(preview?.boardCount == 1)
        #expect(preview?.taskCount == 1)

        let missingFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("openmac-missing-\(UUID().uuidString).json")
        let missingPreview = viewModel.workspaceImportPreview(from: missingFile)
        #expect(missingPreview == nil)
        #expect(viewModel.lastBoardMessage == "Failed to read workspace file")
    }

    @Test("demo board exposes seeded tasks and agents")
    func demoBoardExposesSeedData() {
        let viewModel = KanbanBoardViewModel.demoBoard()

        #expect(viewModel.tasks.count == 3)
        #expect(viewModel.agents.count == 3)
        #expect(viewModel.tasks.contains(where: { $0.status == .inProgress }))
        #expect(viewModel.tasks.contains(where: { $0.status == .review }))
        #expect(viewModel.tasks.contains(where: { $0.status == .todo }))
    }

    @Test("removing unknown agent returns false and does not persist")
    func rejectsRemovingUnknownAgent() {
        let agent = AgentProfile(name: "UI Agent", skills: ["swiftui"], maxConcurrentTasks: 2)
        let store = SpyBoardStore()
        let viewModel = KanbanBoardViewModel(tasks: [], agents: [agent], boardStore: store)

        let removed = viewModel.removeAgent(UUID())

        #expect(!removed)
        #expect(viewModel.agents.count == 1)
        #expect(store.savedSnapshots.isEmpty)
    }
}

struct AppLanguageResolverTests {
    private static let userDefaultsMutationLock = NSLock()
    private static let runtimeLocaleMutationLock = NSLock()

    private func withLanguageOverrideInDefaults<T>(_ value: String?, run body: () throws -> T) rethrows -> T {
        Self.userDefaultsMutationLock.lock()
        defer { Self.userDefaultsMutationLock.unlock() }

        let defaults = UserDefaults.standard
        let key = AppLanguageSettings.userDefaultsKey
        let previousValue = defaults.object(forKey: key)

        if let value {
            defaults.set(value, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }

        defer {
            if let previousValue {
                defaults.set(previousValue, forKey: key)
            } else {
                defaults.removeObject(forKey: key)
            }
        }

        return try body()
    }

    private func resolve(_ preferredLanguages: [String]) -> AppLanguage {
        AppLanguageResolver.resolvedLanguage(
            preferredLanguages: preferredLanguages,
            overrideRawValue: AppLanguageSettings.systemValue
        )
    }

    @Test("maps traditional Chinese locales to zh-Hant")
    func mapsTraditionalChineseLocales() {
        #expect(resolve(["zh-TW"]).rawValue == "zh-Hant")
        #expect(resolve(["zh-HK"]).rawValue == "zh-Hant")
        #expect(resolve(["zh-Hant"]).rawValue == "zh-Hant")
        #expect(resolve(["zh"]).rawValue == "zh-Hant")
    }

    @Test("maps simplified Chinese locales to zh-Hans")
    func mapsSimplifiedChineseLocales() {
        #expect(resolve(["zh-CN"]).rawValue == "zh-Hans")
        #expect(resolve(["zh-SG"]).rawValue == "zh-Hans")
        #expect(resolve(["zh-Hans"]).rawValue == "zh-Hans")
    }

    @Test("maps supported non-Chinese locales")
    func mapsSupportedLocales() {
        #expect(resolve(["en-US"]).rawValue == "en")
        #expect(resolve(["fr-FR"]).rawValue == "fr")
        #expect(resolve(["es-ES"]).rawValue == "es")
        #expect(resolve(["ja-JP"]).rawValue == "ja")
        #expect(resolve(["ko-KR"]).rawValue == "ko")
    }

    @Test("falls back to English when no preferred language is supported")
    func fallsBackToEnglishForUnsupportedLocales() {
        #expect(resolve(["de-DE", "it-IT"]).rawValue == "en")
    }

    @Test("uses first supported preferred language in order")
    func picksFirstSupportedPreferredLanguage() {
        #expect(resolve(["de-DE", "ja-JP", "fr-FR"]).rawValue == "ja")
    }

    @Test("uses explicit language override when provided")
    func usesExplicitOverrideLanguage() {
        #expect(
            AppLanguageResolver.resolvedLanguage(
                preferredLanguages: ["en-US"],
                overrideRawValue: "ja"
            ).rawValue == "ja"
        )
    }

    @Test("system override follows preferred languages")
    func systemOverrideUsesPreferredLanguages() {
        #expect(
            AppLanguageResolver.resolvedLanguage(
                preferredLanguages: ["fr-FR"],
                overrideRawValue: AppLanguageSettings.systemValue
            ).rawValue == "fr"
        )
    }

    @Test("invalid override falls back to preferred language matching")
    func invalidOverrideFallsBackToPreferredLanguages() {
        #expect(
            AppLanguageResolver.resolvedLanguage(
                preferredLanguages: ["es-ES"],
                overrideRawValue: "invalid-language-code"
            ).rawValue == "es"
        )
    }

    @Test("app language preference raw value getter returns stable storage values")
    func appLanguagePreferenceRawValueGetter() {
        #expect(AppLanguagePreference.system.rawValue == AppLanguageSettings.systemValue)
        #expect(AppLanguagePreference.language(.japanese).rawValue == AppLanguage.japanese.rawValue)
    }

    @Test("app language preference initializer normalizes nil/empty/system/invalid and valid values")
    func appLanguagePreferenceInitializerNormalization() {
        #expect(AppLanguagePreference(rawValue: nil).rawValue == AppLanguageSettings.systemValue)
        #expect(AppLanguagePreference(rawValue: "").rawValue == AppLanguageSettings.systemValue)
        #expect(AppLanguagePreference(rawValue: " system ").rawValue == AppLanguageSettings.systemValue)
        #expect(AppLanguagePreference(rawValue: "ja").rawValue == AppLanguage.japanese.rawValue)
        #expect(AppLanguagePreference(rawValue: "unknown-language").rawValue == AppLanguageSettings.systemValue)
    }

    @Test("resolved language defaults to English in test host when no explicit override is provided")
    func resolvedLanguageDefaultArgumentsInTests() {
        #expect(AppLanguageResolver.resolvedLanguage() == .english)
    }

    @Test("resolved language reads persisted override when overrideRawValue is nil and preferred list is explicit")
    func resolvedLanguageReadsPersistedOverrideFromDefaults() {
        let resolved = withLanguageOverrideInDefaults(AppLanguage.japanese.rawValue) {
            AppLanguageResolver.resolvedLanguage(
                preferredLanguages: ["fr-FR"],
                overrideRawValue: nil
            )
        }

        #expect(resolved == .japanese)
    }

    @Test("resolved default locale keeps runtime locale when language matches override")
    func resolvedDefaultLocaleKeepsMatchingRuntimeLanguage() {
        let resolved = L10n.resolvedDefaultLocale(
            overrideRawValue: AppLanguage.english.rawValue,
            runtimeLocale: Locale(identifier: "en-US")
        )

        #expect(resolved.identifier == "en-US")
    }

    @Test("resolved default locale falls back to override locale when runtime language mismatches")
    func resolvedDefaultLocaleFallsBackWhenRuntimeLanguageDiffers() {
        let resolved = L10n.resolvedDefaultLocale(
            overrideRawValue: AppLanguage.english.rawValue,
            runtimeLocale: Locale(identifier: "zh-Hant")
        )

        #expect(AppLanguage.resolve(preferredLanguages: [resolved.identifier]) == .english)
    }

    @Test("resolved default locale returns configured locale when runtime locale is nil")
    func resolvedDefaultLocaleUsesConfiguredLocaleWhenRuntimeIsMissing() {
        let resolved = L10n.resolvedDefaultLocale(
            overrideRawValue: AppLanguage.french.rawValue,
            runtimeLocale: nil
        )

        #expect(AppLanguage.resolve(preferredLanguages: [resolved.identifier]) == .french)
    }

    @Test("L10n test-host detection covers environment class and bundle fallbacks")
    func l10nIsRunningTestsDetectionCoverage() {
        #expect(
            AppLanguageTestHooks.l10nIsRunningTests(
                environment: ["XCTestConfigurationFilePath": "/tmp/test.xctestconfiguration"],
                xctestClassExists: false,
                bundlePaths: []
            )
        )
        #expect(
            AppLanguageTestHooks.l10nIsRunningTests(
                environment: [:],
                xctestClassExists: true,
                bundlePaths: []
            )
        )
        #expect(
            AppLanguageTestHooks.l10nIsRunningTests(
                environment: [:],
                xctestClassExists: false,
                bundlePaths: ["/tmp/OpenMacTests.xctest"]
            )
        )
        #expect(
            !AppLanguageTestHooks.l10nIsRunningTests(
                environment: [:],
                xctestClassExists: false,
                bundlePaths: ["/tmp/OpenMac.app"]
            )
        )
    }

    @Test("L10n active runtime locale getter tracks set and clear operations")
    func l10nActiveRuntimeLocaleCoverage() {
        Self.runtimeLocaleMutationLock.lock()
        defer {
            _ = AppLanguageTestHooks.l10nSetAndReadActiveRuntimeLocale(nil)
            Self.runtimeLocaleMutationLock.unlock()
        }

        let assignedIdentifier = AppLanguageTestHooks.l10nSetAndReadActiveRuntimeLocale("fr-FR")
        #expect(assignedIdentifier == "fr-FR")

        let clearedIdentifier = AppLanguageTestHooks.l10nSetAndReadActiveRuntimeLocale(nil)
        #expect(clearedIdentifier == nil)
    }

    @Test("L10n internal default locale resolver normalizes overrides and runtime matching")
    func l10nInternalResolvedDefaultLocaleCoverage() {
        let forcedEnglish = AppLanguageTestHooks.l10nResolvedDefaultLocale(
            storedOverride: nil,
            runtimeLocaleIdentifier: "ja-JP",
            runningTests: true
        )
        #expect(AppLanguage.resolve(preferredLanguages: [forcedEnglish.identifier]) == .english)

        let systemNormalized = AppLanguageTestHooks.l10nResolvedDefaultLocale(
            storedOverride: " system ",
            runtimeLocaleIdentifier: nil,
            runningTests: false
        )
        #expect(AppLanguage.resolve(preferredLanguages: [systemNormalized.identifier]) == .english)

        let matchedRuntime = AppLanguageTestHooks.l10nResolvedDefaultLocale(
            storedOverride: AppLanguage.japanese.rawValue,
            runtimeLocaleIdentifier: "ja-JP",
            runningTests: false
        )
        #expect(matchedRuntime.identifier == "ja-JP")

        let mismatchedRuntime = AppLanguageTestHooks.l10nResolvedDefaultLocale(
            storedOverride: AppLanguage.japanese.rawValue,
            runtimeLocaleIdentifier: "fr-FR",
            runningTests: false
        )
        #expect(AppLanguage.resolve(preferredLanguages: [mismatchedRuntime.identifier]) == .japanese)
    }

    @Test("L10n string resolves localized value for explicit locale and falls back to key for unknown key")
    func localizedStringLookupAndUnknownKeyFallback() {
        let localized = L10n.string("New Task", locale: Locale(identifier: "zh-Hant"))
        #expect(localized == "新增任務")

        let unknownKey = "UNIT_TEST_UNKNOWN_LOCALIZATION_KEY_\(UUID().uuidString)"
        let fallback = L10n.string(unknownKey, locale: Locale(identifier: "zh-Hant"))
        #expect(fallback == unknownKey)
    }
}

struct LocalizationCatalogTests {
    private static let supportedLocaleCodes = ["en", "zh-Hant", "zh-Hans", "fr", "es", "ja", "ko"]

    @Test("supported localization files share the same key set as English")
    func localizationKeysMatchEnglishBaseline() {
        let englishTable = localizationTable(for: "en")
        #expect(!englishTable.isEmpty)
        let englishKeys = Set(englishTable.keys)

        for locale in Self.supportedLocaleCodes where locale != "en" {
            let localizedTable = localizationTable(for: locale)
            let localizedKeys = Set(localizedTable.keys)
            let missingKeys = englishKeys.subtracting(localizedKeys)
            let extraKeys = localizedKeys.subtracting(englishKeys)

            #expect(missingKeys.isEmpty, "\(locale) is missing \(missingKeys.count) localization keys")
            #expect(extraKeys.isEmpty, "\(locale) has \(extraKeys.count) extra localization keys")
        }
    }

    @Test("supported localization files do not contain empty values")
    func localizationValuesAreNonEmpty() {
        for locale in Self.supportedLocaleCodes {
            let localizedTable = localizationTable(for: locale)
            let emptyValueKeys = localizedTable.keys.filter { key in
                let value = localizedTable[key] ?? ""
                return value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
            #expect(emptyValueKeys.isEmpty, "\(locale) contains \(emptyValueKeys.count) empty localization values")
        }
    }

    @Test("localized format placeholders match English baseline")
    func localizationFormatPlaceholdersMatchEnglishBaseline() {
        let englishTable = localizationTable(for: "en")
        #expect(!englishTable.isEmpty)

        let formattedEnglishKeys = englishTable.keys.filter { key in
            let value = englishTable[key] ?? ""
            return value.contains("%")
        }

        for locale in Self.supportedLocaleCodes where locale != "en" {
            let localizedTable = localizationTable(for: locale)

            for key in formattedEnglishKeys {
                guard let englishValue = englishTable[key],
                      let localizedValue = localizedTable[key] else {
                    continue
                }

                let englishTokens = formatTokens(in: englishValue)
                let localizedTokens = formatTokens(in: localizedValue)
                #expect(
                    englishTokens == localizedTokens,
                    "\(locale) placeholder mismatch for key '\(key)'"
                )
            }
        }
    }

    @Test("Chinese localizations avoid leftover English kanban terms")
    func chineseLocalizationsAvoidEnglishKanbanTerms() {
        let chineseLocales = ["zh-Hant", "zh-Hans"]
        let forbiddenPatterns = [#"\bAgent\b"#, #"\bBoard\b"#]

        for locale in chineseLocales {
            let localizedTable = localizationTable(for: locale)
            let offendingKeys = localizedTable
                .filter { _, value in
                    forbiddenPatterns.contains { pattern in
                        value.range(of: pattern, options: .regularExpression) != nil
                    }
                }
                .keys
                .sorted()

            #expect(
                offendingKeys.isEmpty,
                "\(locale) contains untranslated terms in \(offendingKeys.count) key(s)"
            )
        }
    }

    private func localizationTable(for localeCode: String) -> [String: String] {
        let fileURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("OpenMac/\(localeCode).lproj/Localizable.strings")

        guard let dictionary = NSDictionary(contentsOf: fileURL) as? [String: String] else {
            Issue.record("Failed to load localization file: \(fileURL.path)")
            return [:]
        }
        return dictionary
    }

    private func formatTokens(in value: String) -> [String] {
        let characters = Array(value)
        var tokens: [String] = []
        var index = 0

        while index < characters.count {
            guard characters[index] == "%" else {
                index += 1
                continue
            }

            let start = index
            index += 1

            if index < characters.count, characters[index] == "%" {
                tokens.append("%%")
                index += 1
                continue
            }

            while index < characters.count {
                let character = characters[index]
                if character == "@" || character.isLetter {
                    index += 1
                    tokens.append(String(characters[start..<index]))
                    break
                }
                index += 1
            }
        }

        return tokens
    }
}

private struct StubTaskExecutor: AgentTaskExecuting {
    let outcomesByTaskID: [UUID: AgentTaskExecutionOutcome]
    let progressUpdatesByTaskID: [UUID: [String]]
    let fallbackOutcome: AgentTaskExecutionOutcome

    init(
        outcomesByTaskID: [UUID: AgentTaskExecutionOutcome] = [:],
        progressUpdatesByTaskID: [UUID: [String]] = [:],
        fallbackOutcome: AgentTaskExecutionOutcome = .success(summary: "ok")
    ) {
        self.outcomesByTaskID = outcomesByTaskID
        self.progressUpdatesByTaskID = progressUpdatesByTaskID
        self.fallbackOutcome = fallbackOutcome
    }

    func execute(task: WorkTask, agent: AgentProfile) -> AgentTaskExecutionOutcome {
        outcomesByTaskID[task.id] ?? fallbackOutcome
    }

    func execute(
        task: WorkTask,
        agent: AgentProfile,
        onProgress: @escaping (_ update: String) -> Void
    ) -> AgentTaskExecutionOutcome {
        let updates = progressUpdatesByTaskID[task.id] ?? []
        for update in updates {
            onProgress(update)
        }
        return execute(task: task, agent: agent)
    }
}

private final class HookedTaskExecutor: AgentTaskExecuting {
    let outcomesByTaskID: [UUID: AgentTaskExecutionOutcome]
    let fallbackOutcome: AgentTaskExecutionOutcome
    var onExecute: ((WorkTask) -> Void)?

    init(
        outcomesByTaskID: [UUID: AgentTaskExecutionOutcome] = [:],
        fallbackOutcome: AgentTaskExecutionOutcome = .success(summary: "ok"),
        onExecute: ((WorkTask) -> Void)? = nil
    ) {
        self.outcomesByTaskID = outcomesByTaskID
        self.fallbackOutcome = fallbackOutcome
        self.onExecute = onExecute
    }

    func execute(task: WorkTask, agent: AgentProfile) -> AgentTaskExecutionOutcome {
        onExecute?(task)
        return outcomesByTaskID[task.id] ?? fallbackOutcome
    }

    func execute(
        task: WorkTask,
        agent: AgentProfile,
        onProgress: @escaping (_ update: String) -> Void
    ) -> AgentTaskExecutionOutcome {
        execute(task: task, agent: agent)
    }
}

private final class SpyBoardStore: KanbanBoardStore {
    private let loadSnapshot: KanbanBoardSnapshot?
    private(set) var savedSnapshots: [KanbanBoardSnapshot] = []

    init(loadSnapshot: KanbanBoardSnapshot? = nil) {
        self.loadSnapshot = loadSnapshot
    }

    func load() throws -> KanbanBoardSnapshot? {
        loadSnapshot
    }

    func save(_ snapshot: KanbanBoardSnapshot) throws {
        savedSnapshots.append(snapshot)
    }
}
