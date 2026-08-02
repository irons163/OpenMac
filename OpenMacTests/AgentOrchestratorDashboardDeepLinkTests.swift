import Foundation
import Testing
@testable import OpenMac

private final class AgentOrchestratorDashboardRequestBox:
    @unchecked Sendable
{
    private let lock = NSLock()
    private var storedValue: URLRequest?

    var value: URLRequest? {
        lock.lock()
        defer { lock.unlock() }
        return storedValue
    }

    func set(_ value: URLRequest) {
        lock.lock()
        storedValue = value
        lock.unlock()
    }
}

private struct AgentOrchestratorDashboardStubTransport:
    AgentOrchestratorHTTPTransport
{
    let response: AgentOrchestratorHTTPResponse
    let capture: @Sendable (URLRequest) -> Void

    func send(
        _ request: URLRequest
    ) async throws -> AgentOrchestratorHTTPResponse {
        capture(request)
        return response
    }
}

private struct AgentOrchestratorDashboardConnectionBackend: ExecutionBackend {
    let backendID = "agent-orchestrator"

    func health() async throws -> ExecutionBackendHealth {
        ExecutionBackendHealth(
            state: .ready,
            backendName: "Agent Orchestrator",
            version: AgentOrchestratorBackendConfiguration.capturedAPIVersion
        )
    }

    func listProjects() async throws -> [ExecutionProject] {
        [ExecutionProject(id: ExecutionProjectID("project-1"), name: "Project")]
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

    func stop(executionID: ExecutionID) async throws -> ExecutionStopReceipt {
        throw ExecutionBackendError.rejected("Probe only")
    }
}

@Suite("Agent Orchestrator dashboard deep-links")
struct AgentOrchestratorDashboardDeepLinkTests {
    @Test("builds the official hash-history project and session routes")
    func buildsHashRoutes() throws {
        let configuration = try AgentOrchestratorDashboardConfiguration(
            baseURL: URL(string: "http://127.0.0.1:3000/")!
        )

        #expect(
            try configuration.projectURL(projectID: "openmac-ao-fixture")
                .absoluteString
                == "http://127.0.0.1:3000/#/projects/openmac-ao-fixture"
        )
        #expect(
            try configuration.sessionURL(
                projectID: "openmac-ao-fixture",
                sessionID: "session-001"
            ).absoluteString
                == "http://127.0.0.1:3000/#/projects/openmac-ao-fixture/sessions/session-001"
        )
    }

    @Test("rejects remote roots and unsafe route identifiers")
    func rejectsUnsafeInputs() throws {
        do {
            _ = try AgentOrchestratorDashboardConfiguration(
                baseURL: URL(string: "https://ao.example.com")!
            )
            Issue.record("Expected a non-loopback dashboard root to fail")
        } catch let error as AgentOrchestratorDashboardDeepLinkError {
            #expect(
                error
                    == .nonLoopbackBaseURL(
                        URL(string: "https://ao.example.com")!
                    )
            )
        }

        let configuration = try AgentOrchestratorDashboardConfiguration(
            baseURL: URL(string: "http://localhost:3000")!
        )
        do {
            _ = try configuration.sessionURL(
                projectID: "project/escape",
                sessionID: "session-001"
            )
            Issue.record("Expected a path traversal identifier to fail")
        } catch let error as AgentOrchestratorDashboardDeepLinkError {
            #expect(error == .invalidIdentifier("project/escape"))
        }
    }

    @Test("verifies HTML before a dashboard route can be opened")
    func verifiesHTMLResponse() async throws {
        let capturedRequest = AgentOrchestratorDashboardRequestBox()
        let transport = AgentOrchestratorDashboardStubTransport(
            response: AgentOrchestratorHTTPResponse(
                data: Data("<html><body>AO</body></html>".utf8),
                statusCode: 200,
                headers: ["content-type": "text/html; charset=utf-8"]
            ),
            capture: { capturedRequest.set($0) }
        )
        let verifier = AgentOrchestratorDashboardRouteVerifier(
            transport: transport
        )
        let configuration = try AgentOrchestratorDashboardConfiguration(
            baseURL: URL(string: "http://127.0.0.1:3000")!
        )

        let verifiedURL = try await verifier.verify(
            configuration: configuration,
            projectID: "project-1",
            sessionID: "session-1"
        )

        #expect(verifiedURL.absoluteString == "http://127.0.0.1:3000/#/projects/project-1/sessions/session-1")
        #expect(capturedRequest.value?.httpMethod == "GET")
        #expect(capturedRequest.value?.url == verifiedURL)
    }

    @Test("fails closed for the AO daemon JSON response")
    func rejectsDaemonJSON() async throws {
        let verifier = AgentOrchestratorDashboardRouteVerifier(
            transport: AgentOrchestratorDashboardStubTransport(
                response: AgentOrchestratorHTTPResponse(
                    data: Data("{\"state\":\"ready\"}".utf8),
                    statusCode: 200,
                    headers: ["content-type": "application/json"]
                ),
                capture: { _ in }
            )
        )
        let configuration = try AgentOrchestratorDashboardConfiguration(
            baseURL: URL(string: "http://127.0.0.1:3001")!
        )

        do {
            _ = try await verifier.verify(
                configuration: configuration,
                projectID: "project-1"
            )
            Issue.record("Expected the daemon JSON root to be rejected")
        } catch let error as AgentOrchestratorDashboardDeepLinkError {
            #expect(
                error
                    == .unexpectedContentType(
                        URL(string: "http://127.0.0.1:3001/#/projects/project-1")!,
                        "application/json"
                    )
            )
        }
    }

    @Test("connection screen persists only a verified dashboard root")
    @MainActor
    func connectionPersistsVerifiedDashboard() async throws {
        let suiteName = "OpenMacTests.AODashboard.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let transport = AgentOrchestratorDashboardStubTransport(
            response: AgentOrchestratorHTTPResponse(
                data: Data("<html>AO dashboard</html>".utf8),
                statusCode: 200,
                headers: ["content-type": "text/html"]
            ),
            capture: { _ in }
        )
        let missingRunFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("openmac-no-ao-\(UUID().uuidString)")
        let model = DeliveryAgentOrchestratorConnectionViewModel(
            defaults: defaults,
            discovery: AgentOrchestratorDaemonDiscovery(
                runFileURL: missingRunFile
            ),
            dashboardTransport: transport,
            backendFactory: { _, _ in
                AgentOrchestratorDashboardConnectionBackend()
            }
        )
        model.baseURLText = "http://127.0.0.1:3001"
        await model.connect()
        model.dashboardURLText = "http://127.0.0.1:3000"

        await model.verifyDashboard()

        #expect(
            model.dashboardState
                == .verified(
                    URL(string: "http://127.0.0.1:3000/#/projects/project-1")!
                )
        )
        #expect(
            defaults.string(
                forKey: AgentOrchestratorDashboardConfiguration.defaultsKey
            ) == "http://127.0.0.1:3000/"
        )
    }
}
