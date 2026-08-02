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
            let normalizedRoot = workspaceRoot.hasSuffix("/")
                ? workspaceRoot
                : workspaceRoot + "/"
            #expect(
                receipt.verificationWorkspaceURL?.path.hasPrefix(
                    normalizedRoot
                ) == true
            )
        } else {
            #expect(
                receipt.verificationWorkspaceURL?.path.contains(
                    "/.ao/data/worktrees/openmac-ao-fixture/"
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
}
