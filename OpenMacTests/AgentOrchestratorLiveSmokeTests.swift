import Foundation
import Testing
@testable import OpenMac

private enum AgentOrchestratorLiveSmokeEnvironment {
    static let baseURLKey = "OPENMAC_AO_LIVE_URL"
    static let projectIDKey = "OPENMAC_AO_LIVE_PROJECT_ID"
    static let harnessKey = "OPENMAC_AO_LIVE_HARNESS"
    static let baseBranchKey = "OPENMAC_AO_LIVE_BASE_BRANCH"
    static let baseCommitKey = "OPENMAC_AO_LIVE_BASE_COMMIT"
    static let xcodeKey = "OPENMAC_AO_LIVE_XCODE"
    static let repositoryRootKey = "OPENMAC_AO_LIVE_REPOSITORY_ROOT"
    static let xcodeSchemeKey = "OPENMAC_AO_LIVE_XCODE_SCHEME"
    static let workspaceRootKey = "OPENMAC_AO_LIVE_WORKSPACE_ROOT"
    static let prURLKey = "OPENMAC_AO_LIVE_PR_URL"
    static let e2eKey = "OPENMAC_AO_LIVE_E2E"
    static let e2eExportDirectoryKey = "OPENMAC_AO_LIVE_E2E_EXPORT_DIRECTORY"

    static var baseURLText: String? {
        ProcessInfo.processInfo.environment[baseURLKey]
    }

    static var projectID: String? {
        ProcessInfo.processInfo.environment[projectIDKey]
    }

    static var harness: String {
        ProcessInfo.processInfo.environment[harnessKey] ?? "fake"
    }

    static var baseBranch: String? {
        ProcessInfo.processInfo.environment[baseBranchKey]
    }

    static var baseCommit: String? {
        ProcessInfo.processInfo.environment[baseCommitKey]
    }

    static var xcodeEnabled: Bool {
        guard let rawValue = ProcessInfo.processInfo.environment[xcodeKey]
        else {
            return false
        }
        let value = rawValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return ["1", "true", "yes"].contains(value)
    }

    static var repositoryRoot: String? {
        ProcessInfo.processInfo.environment[repositoryRootKey]
    }

    static var xcodeScheme: String {
        ProcessInfo.processInfo.environment[xcodeSchemeKey]
            ?? "OpenMacAOFixture"
    }

    static var workspaceRoot: String? {
        ProcessInfo.processInfo.environment[workspaceRootKey]
    }

    static var prURL: String? {
        ProcessInfo.processInfo.environment[prURLKey]
    }

    static var e2eEnabled: Bool {
        guard let rawValue = ProcessInfo.processInfo.environment[e2eKey]
        else {
            return false
        }
        let value = rawValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return ["1", "true", "yes"].contains(value)
    }

    static var e2eExportDirectory: URL? {
        guard let path = ProcessInfo.processInfo.environment[
            e2eExportDirectoryKey
        ] else {
            return nil
        }
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return URL(fileURLWithPath: trimmed, isDirectory: true)
    }

    static func claimPR(
        _ prURL: String,
        for executionID: ExecutionID
    ) async throws {
        let baseURLText = try #require(baseURLText)
        let baseURL = try #require(URL(string: baseURLText))
        var url = baseURL
        for component in [
            "api", "v1", "sessions", executionID.rawValue, "pr", "claim"
        ] {
            url.appendPathComponent(component)
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(
            "application/json",
            forHTTPHeaderField: "Content-Type"
        )
        request.httpBody = try JSONEncoder().encode(
            ClaimPRRequest(pr: prURL)
        )
        let (data, response) = try await URLSession.shared.data(
            for: request
        )
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ExecutionBackendError.malformedResponse(
                operation: .facts,
                reason: "AO PR claim did not return an HTTP response."
            )
        }
        guard httpResponse.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw ExecutionBackendError.malformedResponse(
                operation: .facts,
                reason: "AO PR claim returned HTTP \(httpResponse.statusCode): \(body)"
            )
        }
        let claim = try JSONDecoder().decode(
            ClaimPRResponse.self,
            from: data
        )
        guard claim.ok,
              claim.sessionID == executionID.rawValue,
              claim.prs.contains(where: { $0.url == prURL }) else {
            throw ExecutionBackendError.malformedResponse(
                operation: .facts,
                reason: "AO PR claim did not return the requested PR identity."
            )
        }
    }

    private struct ClaimPRRequest: Encodable {
        let pr: String
    }

    private struct ClaimPRResponse: Decodable {
        let ok: Bool
        let sessionID: String
        let prs: [ClaimPR]

        enum CodingKeys: String, CodingKey {
            case ok
            case sessionID = "sessionId"
            case prs
        }
    }

    private struct ClaimPR: Decodable {
        let url: String
    }

    static func backend() throws -> AgentOrchestratorExecutionBackend {
        let baseURLText = try #require(baseURLText)
        let baseURL = try #require(URL(string: baseURLText))
        let configuration = try AgentOrchestratorBackendConfiguration(
            baseURL: baseURL,
            harness: harness
        )
        return AgentOrchestratorExecutionBackend(
            configuration: configuration
        )
    }
}

private enum AgentOrchestratorLiveE2EFixture {
    static func makeStore(
        repositoryRoot: String,
        baseBranch: String,
        scheme: String
    ) async throws -> (FileDeliveryRunStore, URL, UUID, [UUID]) {
        let repositoryURL = URL(
            fileURLWithPath: repositoryRoot,
            isDirectory: true
        )
        let context = try DeliveryPlanningRepositoryContext.resolving(
            repositoryRootPath: repositoryRoot,
            containerKind: .swiftPackage,
            containerRelativePath: "Package.swift",
            targetNames: [scheme],
            schemeNames: [scheme]
        )
        let identity = try context.identitySnapshot(
            validatingBaseBranch: baseBranch
        )
        let runID = UUID()
        let planID = UUID()
        let taskIDs = [UUID(), UUID(), UUID()]
        let createdAt = Date()
        let tasks = [
            task(
                id: taskIDs[0],
                title: "Prepare fixture model",
                scheme: scheme,
                evidenceKinds: [.xcodeBuild]
            ),
            task(
                id: taskIDs[1],
                title: "Prepare fixture store",
                scheme: scheme,
                evidenceKinds: [.xcodeBuild]
            ),
            task(
                id: taskIDs[2],
                title: "Integrate fixture delivery",
                scheme: scheme,
                evidenceKinds: [.xcodeBuild, .pullRequest, .ciChecks]
            )
        ]
        let plan = DeliveryPlan(
            id: planID,
            revision: 1,
            tasks: tasks,
            dependencyEdges: [
                DependencyEdge(
                    prerequisiteTaskID: taskIDs[0],
                    dependentTaskID: taskIDs[2]
                ),
                DependencyEdge(
                    prerequisiteTaskID: taskIDs[1],
                    dependentTaskID: taskIDs[2]
                )
            ],
            createdAt: createdAt,
            updatedAt: createdAt
        )
        let brief = FeatureBrief(
            id: UUID(),
            title: "Run a real AO delivery wave",
            body: "Exercise two parallel implementation tasks, a typed join, verification, and a read-only PR fact claim.",
            repository: DeliveryRepositoryReference(
                rootPath: repositoryURL.path,
                baseBranch: baseBranch,
                xcodeContainerRelativePath: "Package.swift"
            ),
            createdAt: createdAt
        )
        let run = DeliveryRun(
            id: runID,
            brief: brief,
            repositoryIdentity: identity,
            plan: plan,
            createdAt: createdAt,
            updatedAt: createdAt
        )
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "openmac-ao-live-e2e-\(UUID().uuidString)",
                isDirectory: true
            )
        let store = FileDeliveryRunStore(
            fileURL: directoryURL.appendingPathComponent(
                "delivery-store.json"
            )
        )
        try await store.save(
            DeliveryRunSnapshot(
                storeRevision: 0,
                savedAt: createdAt,
                runs: [run],
                selectedRunID: runID
            )
        )
        _ = try await store.approveReviewedPlan(
            plan,
            inRunID: runID,
            expectedStoreRevision: 0,
            expectedPlanRevision: 1,
            approvedBy: "live-e2e"
        )
        return (store, directoryURL, runID, taskIDs)
    }

    static func markSucceeded(
        in store: FileDeliveryRunStore,
        runID: UUID,
        taskIDs: [UUID]
    ) async throws -> DeliveryRunSnapshot {
        guard let current = try await store.load(),
              let runIndex = current.runs.firstIndex(where: {
                  $0.id == runID
              }) else {
            throw DeliveryDispatchError.missingRun(runID)
        }
        let completedAt = max(Date(), current.savedAt)
        var runs = current.runs
        var changed = false
        for attemptIndex in runs[runIndex].attempts.indices
        where taskIDs.contains(runs[runIndex].attempts[attemptIndex].taskID) {
            guard runs[runIndex].attempts[attemptIndex].status
                    == .running else {
                continue
            }
            runs[runIndex].attempts[attemptIndex].status = .succeeded
            runs[runIndex].attempts[attemptIndex].startedAt =
                runs[runIndex].attempts[attemptIndex].startedAt
                ?? completedAt.addingTimeInterval(-0.001)
            runs[runIndex].attempts[attemptIndex].endedAt = completedAt
            changed = true
        }
        guard changed else {
            return current
        }
        runs[runIndex].updatedAt = completedAt
        let updated = DeliveryRunSnapshot(
            format: current.format,
            schemaVersion: current.schemaVersion,
            storeRevision: current.storeRevision + 1,
            savedAt: completedAt,
            runs: runs,
            selectedRunID: current.selectedRunID
        )
        try await store.save(updated)
        return updated
    }

    static func task(
        id: UUID,
        title: String,
        scheme: String,
        evidenceKinds: [EvidenceKind]
    ) -> DeliveryTask {
        let criterionID = UUID()
        return DeliveryTask(
            id: id,
            title: title,
            workerPrompt: "Complete \(title) in the isolated AO workspace.",
            acceptanceCriteria: [
                AcceptanceCriterion(
                    id: criterionID,
                    statement: "\(title) is observable and verified."
                )
            ],
            riskLevel: .medium,
            evidenceRequirements: evidenceKinds.map { kind in
                EvidenceRequirement(
                    kind: kind,
                    description: "Live AO \(kind.rawValue) evidence.",
                    coveredCriterionIDs: [criterionID]
                )
            },
            targetHints: [scheme],
            schemeHints: [scheme]
        )
    }
}

@Suite(
    "Agent Orchestrator opt-in live smoke",
    .serialized,
    .enabled(
        if: AgentOrchestratorLiveSmokeEnvironment.baseURLText != nil,
        "Run through tools/test-agent-orchestrator-live.sh."
    )
)
struct AgentOrchestratorLiveSmokeTests {
    @Test("served API and project discovery match the OpenMac adapter")
    func healthAndProjectDiscovery() async throws {
        let backend = try AgentOrchestratorLiveSmokeEnvironment.backend()

        let health = try await backend.health()
        let projects = try await backend.listProjects()

        #expect(health.state == .ready)
        #expect(
            health.version
                == AgentOrchestratorBackendConfiguration.capturedAPIVersion
        )
        #expect(!projects.isEmpty)
        #expect(
            projects.allSatisfy {
                !$0.id.rawValue.isEmpty && !$0.name.isEmpty
            }
        )
        if let projectID =
            AgentOrchestratorLiveSmokeEnvironment.projectID {
            #expect(
                projects.contains {
                    $0.id == ExecutionProjectID(projectID)
                }
            )
        }
    }

    @Test(
        "explicit live session start returns facts and a stop acknowledgement",
        .enabled(
            if: AgentOrchestratorLiveSmokeEnvironment.projectID != nil,
            "Pass --start-project to authorize an isolated AO session."
        )
    )
    func explicitSessionLifecycle() async throws {
        let projectID = try #require(
            AgentOrchestratorLiveSmokeEnvironment.projectID
        )
        let baseBranch = try #require(
            AgentOrchestratorLiveSmokeEnvironment.baseBranch
        )
        let baseCommit = try #require(
            AgentOrchestratorLiveSmokeEnvironment.baseCommit
        )
        let backend = try AgentOrchestratorLiveSmokeEnvironment.backend()
        // Live smoke runs are intentionally repeatable against a disposable
        // project. A fresh id avoids recovering a prior terminated session,
        // so the test exercises a real start -> facts -> stop lifecycle every
        // time it is opted in.
        let requestID = UUID()
        let request = ExecutionStartRequest(
            requestID: requestID,
            projectID: ExecutionProjectID(projectID),
            deliveryRunID: UUID(
                uuidString: "E2E00002-0000-4000-8000-000000000002"
            )!,
            taskID: UUID(
                uuidString: "E2E00003-0000-4000-8000-000000000003"
            )!,
            planID: UUID(
                uuidString: "E2E00004-0000-4000-8000-000000000004"
            )!,
            planRevision: 1,
            approvalFingerprint: "opt-in-live-smoke",
            title: "OpenMac AO smoke",
            instructions:
                "Exercise the isolated Agent Orchestrator session lifecycle.",
            baseBranch: baseBranch,
            baseCommitIdentifier: baseCommit
        )

        _ = try await backend.health()
        let receipt = try await backend.start(request)
        let facts: ExecutionFactPage
        let stop: ExecutionStopReceipt
        do {
            facts = try await backend.facts(
                for: receipt.executionID,
                after: nil
            )
            stop = try await backend.stop(
                executionID: receipt.executionID
            )
        } catch {
            _ = try? await backend.stop(
                executionID: receipt.executionID
            )
            throw error
        }

        #expect(receipt.requestID == requestID)
        #expect(!receipt.executionID.rawValue.isEmpty)
        #expect(
            receipt.branch?.contains(
                requestID.uuidString.lowercased()
            ) == true
        )
        #expect(receipt.verificationWorkspaceURL?.isFileURL == true)
        if let workspaceRoot =
            AgentOrchestratorLiveSmokeEnvironment.workspaceRoot {
            let normalizedWorkspaceRoot = workspaceRoot.hasSuffix("/")
                ? workspaceRoot
                : workspaceRoot + "/"
            #expect(
                receipt.verificationWorkspaceURL?.path.hasPrefix(
                    normalizedWorkspaceRoot
                ) == true
            )
        } else {
            #expect(
                receipt.verificationWorkspaceURL?.path.contains(
                    "/.ao/data/worktrees/\(projectID)/"
                ) == true
            )
        }
        #expect(!facts.facts.isEmpty)
        #expect(stop.executionID == receipt.executionID)
        #expect(stop.disposition == .accepted)
    }

    @Test(
        "real AO workspace runs the Xcode verifier",
        .enabled(
            if: AgentOrchestratorLiveSmokeEnvironment.xcodeEnabled
                && AgentOrchestratorLiveSmokeEnvironment.projectID != nil
                && AgentOrchestratorLiveSmokeEnvironment.baseBranch != nil
                && AgentOrchestratorLiveSmokeEnvironment.baseCommit != nil
                && AgentOrchestratorLiveSmokeEnvironment.repositoryRoot != nil,
            "Pass --xcode-repository-root with an authorized disposable AO project."
        )
    )
    func realAOWorkspaceRunsXcodeVerifier() async throws {
        let projectID = try #require(
            AgentOrchestratorLiveSmokeEnvironment.projectID
        )
        let baseBranch = try #require(
            AgentOrchestratorLiveSmokeEnvironment.baseBranch
        )
        let baseCommit = try #require(
            AgentOrchestratorLiveSmokeEnvironment.baseCommit
        )
        let repositoryRoot = try #require(
            AgentOrchestratorLiveSmokeEnvironment.repositoryRoot
        )
        let backend = try AgentOrchestratorLiveSmokeEnvironment.backend()
        let requestID = UUID()
        let request = ExecutionStartRequest(
            requestID: requestID,
            projectID: ExecutionProjectID(projectID),
            deliveryRunID: UUID(
                uuidString: "E2E00005-0000-4000-8000-000000000005"
            )!,
            taskID: UUID(
                uuidString: "E2E00006-0000-4000-8000-000000000006"
            )!,
            planID: UUID(
                uuidString: "E2E00007-0000-4000-8000-000000000007"
            )!,
            planRevision: 1,
            approvalFingerprint: "opt-in-live-xcode",
            title: "OpenMac AO Xcode smoke",
            instructions:
                "Exercise the backend-confirmed workspace through xcodebuild.",
            baseBranch: baseBranch,
            baseCommitIdentifier: baseCommit
        )
        let repositoryURL = URL(
            fileURLWithPath: repositoryRoot,
            isDirectory: true
        )
        let commonDirectoryURL = repositoryURL
            .appendingPathComponent(".git", isDirectory: true)
        let artifactRootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "OpenMac-AO-Live-Xcode-Artifacts-\(requestID.uuidString)",
                isDirectory: true
            )
        let derivedDataRootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "OpenMac-AO-Live-Xcode-DerivedData-\(requestID.uuidString)",
                isDirectory: true
            )
        defer {
            try? FileManager.default.removeItem(at: artifactRootURL)
            try? FileManager.default.removeItem(at: derivedDataRootURL)
        }

        let receipt = try await backend.start(request)
        do {
            let workspaceURL = try #require(receipt.verificationWorkspaceURL)
            let branch = try #require(receipt.branch)
            let verifier = XcodeVerifier(
                artifactRootURL: artifactRootURL,
                derivedDataRootURL: derivedDataRootURL
            )
            let record = try await verifier.verify(
                XcodeVerificationRequest(
                    kind: .build,
                    scheme: AgentOrchestratorLiveSmokeEnvironment.xcodeScheme,
                    workspaceURL: workspaceURL,
                    expectedGitCommonDirectoryURL: commonDirectoryURL,
                    expectedBranch: branch,
                    containerKind: .swiftPackage,
                    containerRelativePath: "Package.swift",
                    timeout: 120
                )
            )
            let stop = try await backend.stop(
                executionID: receipt.executionID
            )

            #expect(record.exitCode == 0)
            #expect(!record.timedOut)
            #expect(record.resultBundlePath != nil)
            #expect(record.summary.contains("passed"))
            #expect(
                record.workingDirectoryPath
                    == workspaceURL.standardizedFileURL
                        .resolvingSymlinksInPath()
                        .path
            )
            #expect(stop.executionID == receipt.executionID)
            #expect(stop.disposition == .accepted)
        } catch {
            _ = try? await backend.stop(
                executionID: receipt.executionID
            )
            throw error
        }
    }

    @Test(
        "real AO session consumes live pull request facts",
        .enabled(
            if: AgentOrchestratorLiveSmokeEnvironment.prURL != nil
                && AgentOrchestratorLiveSmokeEnvironment.projectID != nil
                && AgentOrchestratorLiveSmokeEnvironment.baseBranch != nil
                && AgentOrchestratorLiveSmokeEnvironment.baseCommit != nil,
            "Pass --pr-url with a disposable AO project and public GitHub PR."
        )
    )
    func realAOSessionConsumesLivePullRequestFacts() async throws {
        let projectID = try #require(
            AgentOrchestratorLiveSmokeEnvironment.projectID
        )
        let baseBranch = try #require(
            AgentOrchestratorLiveSmokeEnvironment.baseBranch
        )
        let baseCommit = try #require(
            AgentOrchestratorLiveSmokeEnvironment.baseCommit
        )
        let prURL = try #require(
            AgentOrchestratorLiveSmokeEnvironment.prURL
        )
        let backend = try AgentOrchestratorLiveSmokeEnvironment.backend()
        let requestID = UUID()
        let request = ExecutionStartRequest(
            requestID: requestID,
            projectID: ExecutionProjectID(projectID),
            deliveryRunID: UUID(
                uuidString: "E2E00008-0000-4000-8000-000000000008"
            )!,
            taskID: UUID(
                uuidString: "E2E00009-0000-4000-8000-000000000009"
            )!,
            planID: UUID(
                uuidString: "E2E0000A-0000-4000-8000-00000000000A"
            )!,
            planRevision: 1,
            approvalFingerprint: "opt-in-live-pr",
            title: "OpenMac AO PR smoke",
            instructions:
                "Consume live pull request identity and CI/review facts.",
            baseBranch: baseBranch,
            baseCommitIdentifier: baseCommit
        )

        let receipt = try await backend.start(request)
        do {
            try await AgentOrchestratorLiveSmokeEnvironment.claimPR(
                prURL,
                for: receipt.executionID
            )
            let facts = try await backend.facts(
                for: receipt.executionID,
                after: nil
            )
            let pullRequests = facts.facts.compactMap { fact ->
                ExecutionPullRequestEvidence? in
                guard case let .pullRequestEvidence(evidence) = fact.body
                else {
                    return nil
                }
                return evidence
            }
            let matching = pullRequests.first {
                $0.url.absoluteString == prURL
            }
            #expect(matching != nil)
            #expect(matching?.state == .open)
            #expect(matching?.checks == .passing)
            #expect(matching?.review == .required)

            let stop = try await backend.stop(
                executionID: receipt.executionID
            )
            #expect(stop.executionID == receipt.executionID)
            #expect(stop.disposition == .accepted)
        } catch {
            _ = try? await backend.stop(
                executionID: receipt.executionID
            )
            throw error
        }
    }

    @Test(
        "real AO typed plan dispatches two parallel roots, verifies a join, and exports evidence",
        .enabled(
            if: AgentOrchestratorLiveSmokeEnvironment.e2eEnabled
                && AgentOrchestratorLiveSmokeEnvironment.xcodeEnabled
                && AgentOrchestratorLiveSmokeEnvironment.projectID != nil
                && AgentOrchestratorLiveSmokeEnvironment.baseBranch != nil
                && AgentOrchestratorLiveSmokeEnvironment.baseCommit != nil
                && AgentOrchestratorLiveSmokeEnvironment.repositoryRoot != nil
                && AgentOrchestratorLiveSmokeEnvironment.prURL != nil,
            "Pass --e2e with a disposable AO project, Xcode fixture, and public PR."
        )
    )
    func realAOTypedPlanRunsFullE2E() async throws {
        let projectID = try #require(
            AgentOrchestratorLiveSmokeEnvironment.projectID
        )
        let baseBranch = try #require(
            AgentOrchestratorLiveSmokeEnvironment.baseBranch
        )
        let baseCommit = try #require(
            AgentOrchestratorLiveSmokeEnvironment.baseCommit
        )
        let repositoryRoot = try #require(
            AgentOrchestratorLiveSmokeEnvironment.repositoryRoot
        )
        let prURL = try #require(
            AgentOrchestratorLiveSmokeEnvironment.prURL
        )
        let scheme = AgentOrchestratorLiveSmokeEnvironment.xcodeScheme
        let backend = try AgentOrchestratorLiveSmokeEnvironment.backend()
        let (store, directoryURL, runID, taskIDs) = try await
            AgentOrchestratorLiveE2EFixture.makeStore(
                repositoryRoot: repositoryRoot,
                baseBranch: baseBranch,
                scheme: scheme
            )
        defer {
            try? FileManager.default.removeItem(at: directoryURL)
        }

        let exportDirectory =
            AgentOrchestratorLiveSmokeEnvironment.e2eExportDirectory
            ?? directoryURL.appendingPathComponent(
                "evidence",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: exportDirectory,
            withIntermediateDirectories: true
        )
        let artifactRootURL = directoryURL.appendingPathComponent(
            "verification-artifacts",
            isDirectory: true
        )
        let derivedDataRootURL = directoryURL.appendingPathComponent(
            "derived-data",
            isDirectory: true
        )
        let executionProjectID = ExecutionProjectID(projectID)
        let reconciler = DeliveryExecutionReconciler(
            store: store,
            backend: backend
        )
        var executionIDs: [ExecutionID] = []

        do {
            _ = try await backend.health()
            guard let initialRun = try await store.load()?.runs.first else {
                throw DeliveryDispatchError.missingRun(runID)
            }
            #expect(
                initialRun.repositoryIdentity?.baseCommitIdentifier
                    == baseCommit
            )
            #expect(
                DeliveryDispatchStateReducer.readyTaskIDs(in: initialRun)
                    == [taskIDs[0], taskIDs[1]]
            )

            // The current AO project summary does not expose a permission
            // scope. The production dispatcher therefore remains fail-closed
            // at its preflight boundary. This live E2E intentionally exercises
            // the already-approved store reservations and the real AO backend
            // directly, while deterministic tests cover the dispatcher gate.
            let firstPreparation = try await store.prepareReadyDispatch(
                runID: runID,
                backendID: backend.backendID,
                projectID: executionProjectID,
                requestedAt: Date()
            )
            #expect(firstPreparation.reservations.count == 2)
            let firstReceipts = try await start(
                firstPreparation.reservations,
                with: backend
            )
            executionIDs.append(contentsOf: firstReceipts.map(\.executionID))
            let firstOutcomes = firstReceipts.map { receipt in
                DeliveryDispatchAttemptOutcome.started(
                    attemptID: receipt.attemptID,
                    requestID: receipt.requestID,
                    receipt: receipt.receipt,
                    recordedAt: Date()
                )
            }
            let firstSnapshot = try await store.recordDispatchOutcomes(
                firstOutcomes,
                runID: runID
            )
            let firstAttempts = firstSnapshot.runs
                .first(where: { $0.id == runID })?.attempts ?? []
            #expect(firstAttempts.count == 2)
            #expect(
                Set(firstAttempts.compactMap { $0.externalSession?.sessionID })
                    .count == 2
            )
            #expect(
                Set(firstAttempts.compactMap {
                    $0.externalSession?.verificationWorkspacePath
                }).count == 2
            )
            _ = try await reconciler.reconcileOnce(runID: runID)
            _ = try await AgentOrchestratorLiveE2EFixture.markSucceeded(
                in: store,
                runID: runID,
                taskIDs: [taskIDs[0], taskIDs[1]]
            )

            let secondPreparation = try await store.prepareReadyDispatch(
                runID: runID,
                backendID: backend.backendID,
                projectID: executionProjectID,
                requestedAt: Date()
            )
            #expect(secondPreparation.reservations.count == 1)
            #expect(
                secondPreparation.reservations[0].request.taskID == taskIDs[2]
            )
            let secondReceipts = try await start(
                secondPreparation.reservations,
                with: backend
            )
            executionIDs.append(contentsOf: secondReceipts.map(\.executionID))
            let secondOutcomes = secondReceipts.map { receipt in
                DeliveryDispatchAttemptOutcome.started(
                    attemptID: receipt.attemptID,
                    requestID: receipt.requestID,
                    receipt: receipt.receipt,
                    recordedAt: Date()
                )
            }
            _ = try await store.recordDispatchOutcomes(
                secondOutcomes,
                runID: runID
            )
            let joinReceipt = try #require(secondReceipts.first?.receipt)
            try await AgentOrchestratorLiveSmokeEnvironment.claimPR(
                prURL,
                for: joinReceipt.executionID
            )
            var secondFacts = try await reconciler.reconcileOnce(
                runID: runID
            )
            for _ in 0 ..< 3
            where !secondFacts.snapshot.runs.contains(where: { run in
                run.id == runID && run.pullRequests.contains(where: {
                    $0.url.absoluteString == prURL
                })
            }) {
                secondFacts = try await reconciler.reconcileOnce(
                    runID: runID
                )
            }
            #expect(
                secondFacts.snapshot.runs
                    .first(where: { $0.id == runID })?.pullRequests
                    .contains(where: { $0.url.absoluteString == prURL })
                    == true
            )
            _ = try await AgentOrchestratorLiveE2EFixture.markSucceeded(
                in: store,
                runID: runID,
                taskIDs: [taskIDs[2]]
            )

            let verifier = XcodeVerifier(
                artifactRootURL: artifactRootURL,
                derivedDataRootURL: derivedDataRootURL
            )
            let coordinator = DeliveryXcodeVerificationCoordinator(
                store: store,
                verifier: verifier
            )
            for taskID in taskIDs {
                let verification = try await coordinator.verify(
                    runID: runID,
                    taskID: taskID,
                    kind: .build
                )
                #expect(verification.record.exitCode == 0)
                #expect(!verification.record.timedOut)
                #expect(verification.record.resultBundlePath != nil)
                #expect(verification.record.summary.contains("passed"))
            }

            guard let finalRun = try await store.load()?.runs.first(where: {
                $0.id == runID
            }) else {
                throw DeliveryDispatchError.missingRun(runID)
            }
            let exportURL = exportDirectory.appendingPathComponent(
                "ao-live-e2e-funnel.json"
            )
            let funnel = try DeliveryFunnelExporter().export(
                run: finalRun,
                to: exportURL
            )
            #expect(funnel.taskCount == 3)
            #expect(funnel.startedSessionCount == 3)
            #expect(funnel.verifiedTaskCount == 3)
            #expect(funnel.pullRequestCount == 1)
            #expect(funnel.passedEvidenceCount >= 5)
            #expect(
                finalRun.executionObservations.isEmpty == false
            )
            #expect(
                finalRun.pullRequests.contains {
                    $0.url.absoluteString == prURL
                }
            )
            #expect(FileManager.default.fileExists(atPath: exportURL.path))

            for executionID in executionIDs {
                let stop = try await backend.stop(executionID: executionID)
                #expect(
                    stop.disposition == .accepted
                        || stop.disposition == .alreadyStopped
                        || stop.disposition == .alreadyTerminal
                )
            }
        } catch {
            for executionID in executionIDs {
                _ = try? await backend.stop(executionID: executionID)
            }
            throw error
        }
    }

    private struct StartedReceipt: Sendable {
        let attemptID: UUID
        let requestID: UUID
        let receipt: ExecutionStartReceipt

        var executionID: ExecutionID { receipt.executionID }
    }

    private func start(
        _ reservations: [DeliveryDispatchReservation],
        with backend: any ExecutionBackend
    ) async throws -> [StartedReceipt] {
        try await withThrowingTaskGroup(of: StartedReceipt.self) { group in
            for reservation in reservations {
                group.addTask {
                    let receipt = try await backend.start(reservation.request)
                    guard receipt.requestID == reservation.request.requestID else {
                        throw DeliveryDispatchError.malformedStartReceipt(
                            reservation.attemptID
                        )
                    }
                    return StartedReceipt(
                        attemptID: reservation.attemptID,
                        requestID: reservation.request.requestID,
                        receipt: receipt
                    )
                }
            }
            var results: [StartedReceipt] = []
            for try await receipt in group {
                results.append(receipt)
            }
            return results.sorted {
                $0.attemptID.uuidString < $1.attemptID.uuidString
            }
        }
    }
}
