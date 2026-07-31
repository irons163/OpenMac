import Foundation
import Testing
@testable import OpenMac

@Suite("Agent Orchestrator daemon discovery", .serialized)
struct AgentOrchestratorDaemonDiscoveryTests {
    @Test("valid owned run file discovers only its loopback port and PID")
    func discoversValidRunFile() throws {
        let fixture = try RunFileFixture()
        defer { fixture.remove() }
        try fixture.write(
            """
            {
              "pid": 4242,
              "port": 33001,
              "startedAt": "2026-07-31T07:51:06.090125Z",
              "owner": "desktop",
              "browserRuntimeToken": "must-not-leave-the-file",
              "browserRuntimeAddress": "attacker.example:443"
            }
            """
        )
        let discovery = AgentOrchestratorDaemonDiscovery(
            runFileURL: fixture.runFileURL,
            processIsAlive: { $0 == 4242 }
        )

        let discoveredEndpoint = try discovery.discover()
        let endpoint = try #require(discoveredEndpoint)

        #expect(endpoint.baseURL.absoluteString == "http://127.0.0.1:33001")
        #expect(endpoint.pid == 4242)
        #expect(endpoint.runFileURL == fixture.runFileURL)
        #expect(
            abs(
                endpoint.startedAt.timeIntervalSince1970
                    - 1_785_484_266.090_125
            ) < 0.001
        )
    }

    @Test("missing run file is a normal no-discovery result")
    func missingRunFile() throws {
        let fixture = try RunFileFixture()
        defer { fixture.remove() }
        let discovery = AgentOrchestratorDaemonDiscovery(
            runFileURL: fixture.runFileURL,
            processIsAlive: { _ in true }
        )

        #expect(try discovery.discover() == nil)
    }

    @Test("stale process identity is rejected")
    func rejectsStaleProcess() throws {
        let fixture = try RunFileFixture()
        defer { fixture.remove() }
        try fixture.write(validPayload)
        let discovery = AgentOrchestratorDaemonDiscovery(
            runFileURL: fixture.runFileURL,
            processIsAlive: { _ in false }
        )

        do {
            _ = try discovery.discover()
            Issue.record("Expected stale AO process rejection")
        } catch let error as AgentOrchestratorDaemonDiscoveryError {
            #expect(error == .staleProcess(4242))
        }
    }

    @Test("invalid PID and port values are rejected")
    func rejectsInvalidIdentityValues() throws {
        let fixture = try RunFileFixture()
        defer { fixture.remove() }
        try fixture.write(
            """
            {
              "pid": 0,
              "port": 33001,
              "startedAt": "2026-07-31T07:51:06Z"
            }
            """
        )
        let discovery = AgentOrchestratorDaemonDiscovery(
            runFileURL: fixture.runFileURL,
            processIsAlive: { _ in true }
        )

        do {
            _ = try discovery.discover()
            Issue.record("Expected invalid AO PID rejection")
        } catch let error as AgentOrchestratorDaemonDiscoveryError {
            #expect(error == .invalidPID(0))
        }

        try fixture.write(
            """
            {
              "pid": 4242,
              "port": 70000,
              "startedAt": "2026-07-31T07:51:06Z"
            }
            """
        )
        do {
            _ = try discovery.discover()
            Issue.record("Expected invalid AO port rejection")
        } catch let error as AgentOrchestratorDaemonDiscoveryError {
            #expect(error == .invalidPort(70_000))
        }
    }

    @Test("group-writable run file is rejected")
    func rejectsWritableRunFile() throws {
        let fixture = try RunFileFixture()
        defer { fixture.remove() }
        try fixture.write(validPayload, permissions: 0o660)
        let discovery = AgentOrchestratorDaemonDiscovery(
            runFileURL: fixture.runFileURL,
            processIsAlive: { _ in true }
        )

        do {
            _ = try discovery.discover()
            Issue.record("Expected unsafe AO run file rejection")
        } catch let error as AgentOrchestratorDaemonDiscoveryError {
            #expect(error == .unsafeRunFile(fixture.runFileURL))
        }
    }

    @Test("oversized run file is rejected before JSON decoding")
    func rejectsOversizedRunFile() throws {
        let fixture = try RunFileFixture()
        defer { fixture.remove() }
        let oversizedData = Data(
            repeating: 0x20,
            count:
                Int(
                    AgentOrchestratorDaemonDiscovery
                        .maximumRunFileSize
                ) + 1
        )
        try oversizedData.write(to: fixture.runFileURL)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: fixture.runFileURL.path
        )
        let discovery = AgentOrchestratorDaemonDiscovery(
            runFileURL: fixture.runFileURL,
            processIsAlive: { _ in true }
        )

        do {
            _ = try discovery.discover()
            Issue.record("Expected oversized AO run file rejection")
        } catch let error as AgentOrchestratorDaemonDiscoveryError {
            #expect(
                error == .oversizedRunFile(
                    AgentOrchestratorDaemonDiscovery
                        .maximumRunFileSize + 1
                )
            )
        }
    }

    @Test("malformed timestamp is rejected")
    func rejectsMalformedTimestamp() throws {
        let fixture = try RunFileFixture()
        defer { fixture.remove() }
        try fixture.write(
            """
            {
              "pid": 4242,
              "port": 33001,
              "startedAt": "not-a-date"
            }
            """
        )
        let discovery = AgentOrchestratorDaemonDiscovery(
            runFileURL: fixture.runFileURL,
            processIsAlive: { _ in true }
        )

        do {
            _ = try discovery.discover()
            Issue.record("Expected malformed AO run file rejection")
        } catch let error as AgentOrchestratorDaemonDiscoveryError {
            #expect(error == .malformedRunFile)
        }
    }

    @Test("symbolic-link run file is rejected")
    func rejectsSymbolicLink() throws {
        let fixture = try RunFileFixture()
        defer { fixture.remove() }
        let targetURL = fixture.directoryURL
            .appendingPathComponent("actual.json")
        try Data(validPayload.utf8).write(to: targetURL)
        try FileManager.default.createSymbolicLink(
            at: fixture.runFileURL,
            withDestinationURL: targetURL
        )
        let discovery = AgentOrchestratorDaemonDiscovery(
            runFileURL: fixture.runFileURL,
            processIsAlive: { _ in true }
        )

        do {
            _ = try discovery.discover()
            Issue.record("Expected AO run-file symlink rejection")
        } catch let error as AgentOrchestratorDaemonDiscoveryError {
            #expect(error == .unsafeRunFile(fixture.runFileURL))
        }
    }

    private var validPayload: String {
        """
        {
          "pid": 4242,
          "port": 33001,
          "startedAt": "2026-07-31T07:51:06Z"
        }
        """
    }
}

private struct RunFileFixture {
    let directoryURL: URL
    let runFileURL: URL

    init() throws {
        directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "openmac-ao-discovery-\(UUID().uuidString)",
                isDirectory: true
            )
        runFileURL = directoryURL.appendingPathComponent("running.json")
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
    }

    func write(
        _ json: String,
        permissions: Int = 0o600
    ) throws {
        try Data(json.utf8).write(to: runFileURL, options: .atomic)
        try FileManager.default.setAttributes(
            [.posixPermissions: permissions],
            ofItemAtPath: runFileURL.path
        )
    }

    func remove() {
        try? FileManager.default.removeItem(at: directoryURL)
    }
}
