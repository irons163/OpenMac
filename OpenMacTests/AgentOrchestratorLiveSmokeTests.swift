import Foundation
import Testing
@testable import OpenMac

private enum AgentOrchestratorLiveSmokeEnvironment {
    static let baseURLKey = "OPENMAC_AO_LIVE_URL"
    static let projectIDKey = "OPENMAC_AO_LIVE_PROJECT_ID"
    static let harnessKey = "OPENMAC_AO_LIVE_HARNESS"
    static let baseBranchKey = "OPENMAC_AO_LIVE_BASE_BRANCH"
    static let baseCommitKey = "OPENMAC_AO_LIVE_BASE_COMMIT"

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
        #expect(
            receipt.verificationWorkspaceURL?.path.contains(
                "/.ao/data/worktrees/openmac-ao-fixture/"
            ) == true
        )
        #expect(!facts.facts.isEmpty)
        #expect(stop.executionID == receipt.executionID)
        #expect(stop.disposition == .accepted)
    }
}
