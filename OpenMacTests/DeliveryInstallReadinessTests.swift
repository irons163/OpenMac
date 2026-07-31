import Foundation
import Testing
@testable import OpenMac

private struct DeliveryAOProbeBackend: ExecutionBackend {
    let backendID = "ao-probe"

    func health() async throws -> ExecutionBackendHealth {
        ExecutionBackendHealth(
            state: .ready,
            backendName: "Agent Orchestrator",
            version: AgentOrchestratorBackendConfiguration.capturedAPIVersion
        )
    }

    func listProjects() async throws -> [ExecutionProject] {
        [
            ExecutionProject(
                id: ExecutionProjectID("second"),
                name: "Zeta"
            ),
            ExecutionProject(
                id: ExecutionProjectID("first"),
                name: "Alpha"
            )
        ]
    }

    func start(
        _ request: ExecutionStartRequest
    ) async throws -> ExecutionStartReceipt {
        throw ExecutionBackendError.rejected("Probe only")
    }

    func facts(
        for executionID: ExecutionID,
        after cursor: ExecutionFactCursor?
    ) async throws -> ExecutionFactPage {
        throw ExecutionBackendError.rejected("Probe only")
    }

    func stop(
        executionID: ExecutionID
    ) async throws -> ExecutionStopReceipt {
        throw ExecutionBackendError.rejected("Probe only")
    }
}

@Suite("Delivery v2 install readiness", .serialized)
struct DeliveryInstallReadinessTests {
    @Test("AO connection probe saves a compatible loopback endpoint")
    @MainActor
    func connectionProbePersistsCompatibleEndpoint() async throws {
        let suiteName = "OpenMacTests.AOProbe.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let model = DeliveryAgentOrchestratorConnectionViewModel(
            defaults: defaults,
            backendFactory: { _ in DeliveryAOProbeBackend() }
        )
        model.baseURLText = "http://127.0.0.1:3001"

        await model.connect()

        #expect(
            model.state == .connected(
                version:
                    AgentOrchestratorBackendConfiguration.capturedAPIVersion,
                projectCount: 2
            )
        )
        #expect(model.projectNames == ["Alpha", "Zeta"])
        #expect(
            defaults.string(
                forKey:
                    DeliveryAgentOrchestratorConnectionViewModel
                        .baseURLDefaultsKey
            ) == "http://127.0.0.1:3001"
        )
    }

    @Test("AO connection rejects a non-loopback endpoint without network access")
    @MainActor
    func connectionProbeRejectsRemoteEndpoint() async throws {
        let suiteName = "OpenMacTests.AORemote.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let model = DeliveryAgentOrchestratorConnectionViewModel(
            defaults: defaults
        )
        model.baseURLText = "https://ao.example.com"

        await model.connect()

        guard case let .failed(message) = model.state else {
            Issue.record("Expected a failed connection state")
            return
        }
        #expect(message.contains("loopback"))
        #expect(
            defaults.string(
                forKey:
                    DeliveryAgentOrchestratorConnectionViewModel
                        .baseURLDefaultsKey
            ) == nil
        )
    }
}
