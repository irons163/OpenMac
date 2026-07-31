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
            backendFactory: { _, _ in DeliveryAOProbeBackend() }
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

    @Test("AO connection auto-discovers and binds the daemon PID")
    @MainActor
    func connectionProbeDiscoversDaemonIdentity() async throws {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "openmac-ao-connect-\(UUID().uuidString)",
                isDirectory: true
            )
        defer { try? FileManager.default.removeItem(at: directoryURL) }
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        let runFileURL = directoryURL
            .appendingPathComponent("running.json")
        try Data(
            """
            {
              "pid": 777,
              "port": 33001,
              "startedAt": "2026-07-31T07:51:06.090125Z"
            }
            """.utf8
        ).write(to: runFileURL)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: runFileURL.path
        )
        let discovery = AgentOrchestratorDaemonDiscovery(
            runFileURL: runFileURL,
            processIsAlive: { $0 == 777 }
        )
        let suiteName = "OpenMacTests.AODiscovery.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let model = DeliveryAgentOrchestratorConnectionViewModel(
            defaults: defaults,
            discovery: discovery,
            backendFactory: { baseURL, expectedPID in
                guard baseURL.absoluteString
                        == "http://127.0.0.1:33001",
                      expectedPID == 777 else {
                    throw ExecutionBackendError.rejected(
                        "The discovered AO identity was not forwarded."
                    )
                }
                return DeliveryAOProbeBackend()
            }
        )

        #expect(model.baseURLText == "http://127.0.0.1:33001")
        #expect(model.discoveryMessage?.contains("33001") == true)

        await model.connect()

        #expect(
            model.state == .connected(
                version:
                    AgentOrchestratorBackendConfiguration.capturedAPIVersion,
                projectCount: 2
            )
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
