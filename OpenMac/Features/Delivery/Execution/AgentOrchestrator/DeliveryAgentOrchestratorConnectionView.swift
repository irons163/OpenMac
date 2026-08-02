import Combine
import Foundation
import SwiftUI

enum DeliveryAgentOrchestratorConnectionSceneConfiguration {
    static let windowID = "delivery-agent-orchestrator-connection"
}

nonisolated enum DeliveryAgentOrchestratorConnectionState:
    Equatable,
    Sendable
{
    case idle
    case connecting
    case connected(version: String?, projectCount: Int)
    case failed(String)
}

nonisolated enum DeliveryAgentOrchestratorDashboardState:
    Equatable,
    Sendable
{
    case unconfigured
    case checking
    case verified(URL)
    case failed(String)
}

@MainActor
final class DeliveryAgentOrchestratorConnectionViewModel: ObservableObject {
    typealias BackendFactory =
        @Sendable (URL, Int?) throws -> any ExecutionBackend

    static let baseURLDefaultsKey =
        "delivery.agentOrchestrator.baseURL"
    static let dashboardURLDefaultsKey =
        AgentOrchestratorDashboardConfiguration.defaultsKey
    static let defaultBaseURL = "http://127.0.0.1:3001"

    @Published var baseURLText: String
    @Published var dashboardURLText: String
    @Published private(set) var state:
        DeliveryAgentOrchestratorConnectionState = .idle
    @Published private(set) var dashboardState:
        DeliveryAgentOrchestratorDashboardState = .unconfigured
    @Published private(set) var projectNames: [String] = []
    @Published private(set) var discoveryMessage: String?

    private let backendFactory: BackendFactory
    private let defaults: UserDefaults
    private let discovery: AgentOrchestratorDaemonDiscovery
    private let dashboardVerifier: AgentOrchestratorDashboardRouteVerifier
    private var discoveredEndpoint: AgentOrchestratorDaemonEndpoint?
    private var projectIDs: [String] = []

    init(
        defaults: UserDefaults = .standard,
        discovery: AgentOrchestratorDaemonDiscovery = .init(),
        dashboardTransport: any AgentOrchestratorHTTPTransport =
            URLSessionAgentOrchestratorHTTPTransport(),
        backendFactory: @escaping BackendFactory = {
            baseURL,
            expectedDaemonPID in
            let configuration = try AgentOrchestratorBackendConfiguration(
                baseURL: baseURL,
                expectedDaemonPID: expectedDaemonPID
            )
            return AgentOrchestratorExecutionBackend(
                configuration: configuration
            )
        }
    ) {
        self.defaults = defaults
        self.backendFactory = backendFactory
        self.discovery = discovery
        self.dashboardVerifier = AgentOrchestratorDashboardRouteVerifier(
            transport: dashboardTransport
        )

        let savedBaseURL = defaults.string(
            forKey: Self.baseURLDefaultsKey
        )
        dashboardURLText = defaults.string(
            forKey: Self.dashboardURLDefaultsKey
        ) ?? ""
        do {
            let endpoint = try discovery.discover()
            discoveredEndpoint = endpoint
            baseURLText = savedBaseURL
                ?? endpoint?.baseURL.absoluteString
                ?? Self.defaultBaseURL
            if let endpoint {
                if let savedBaseURL,
                   let savedURL = URL(string: savedBaseURL),
                   !Self.sameEndpoint(savedURL, endpoint.baseURL) {
                    discoveryMessage =
                        "Discovered a running AO daemon on port \(endpoint.baseURL.port ?? 0). Choose Discover Running AO to use it."
                } else {
                    discoveryMessage =
                        "Discovered a running AO daemon on port \(endpoint.baseURL.port ?? 0)."
                }
            }
        } catch {
            discoveredEndpoint = nil
            baseURLText = savedBaseURL ?? Self.defaultBaseURL
            discoveryMessage = Self.errorMessage(error)
        }
    }

    var isConnecting: Bool {
        state == .connecting
    }

    var statusMessage: String {
        switch state {
        case .idle:
            return "Enter the loopback URL served by Agent Orchestrator."
        case .connecting:
            return "Checking health, API compatibility, and projects…"
        case let .connected(version, projectCount):
            return "Connected to compatible AO API \(version ?? "unknown") with \(projectCount) project(s)."
        case let .failed(message):
            return message
        }
    }

    var dashboardStatusMessage: String {
        switch dashboardState {
        case .unconfigured:
            return "Optional: enter the AO web dashboard root, then verify it before opening deep-links."
        case .checking:
            return "Checking the dashboard HTML route…"
        case let .verified(url):
            return "Verified AO dashboard route at " + url.absoluteString + "."
        case let .failed(message):
            return message
        }
    }

    func discoverDaemon() {
        state = .idle
        projectNames = []
        projectIDs = []
        do {
            guard let endpoint = try discovery.discover() else {
                discoveredEndpoint = nil
                discoveryMessage =
                    "No running AO daemon was discovered. Start AO or enter its loopback URL."
                return
            }
            discoveredEndpoint = endpoint
            baseURLText = endpoint.baseURL.absoluteString
            discoveryMessage =
                "Discovered a running AO daemon on port \(endpoint.baseURL.port ?? 0)."
        } catch {
            discoveredEndpoint = nil
            discoveryMessage = Self.errorMessage(error)
        }
    }

    func connect() async {
        guard !isConnecting else { return }
        state = .connecting
        projectNames = []
        projectIDs = []
        do {
            let trimmedURL = baseURLText.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            guard let baseURL = URL(string: trimmedURL) else {
                throw AgentOrchestratorAdapterConfigurationError
                    .invalidBaseURL(
                        URL(fileURLWithPath: trimmedURL)
                    )
            }
            let expectedPID: Int?
            if let discoveredEndpoint,
               Self.sameEndpoint(
                   baseURL,
                   discoveredEndpoint.baseURL
               ) {
                expectedPID = discoveredEndpoint.pid
            } else {
                expectedPID = nil
            }
            let backend = try backendFactory(baseURL, expectedPID)
            let health = try await backend.health()
            guard health.state == .ready else {
                throw ExecutionBackendError.unavailable(
                    health.message
                        ?? "Agent Orchestrator is not ready."
                )
            }
            let projects = try await backend.listProjects()
            projectIDs = projects.map { $0.id.rawValue }
            projectNames = projects
                .map(\.name)
                .sorted {
                    $0.localizedCaseInsensitiveCompare($1)
                        == .orderedAscending
                }
            defaults.set(
                baseURL.absoluteString,
                forKey: Self.baseURLDefaultsKey
            )
            baseURLText = baseURL.absoluteString
            state = .connected(
                version: health.version,
                projectCount: projects.count
            )
        } catch {
            state = .failed(
                (error as? any LocalizedError)?.errorDescription
                    ?? error.localizedDescription
            )
        }
    }

    func verifyDashboard() async {
        guard !isConnecting else { return }
        dashboardState = .checking
        do {
            let trimmedURL = dashboardURLText.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            guard let dashboardURL = URL(string: trimmedURL) else {
                throw AgentOrchestratorDashboardDeepLinkError.invalidBaseURL(
                    URL(fileURLWithPath: trimmedURL)
                )
            }
            guard let projectID = projectIDs.first else {
                throw AgentOrchestratorDashboardDeepLinkError.noProject
            }
            let configuration = try AgentOrchestratorDashboardConfiguration(
                baseURL: dashboardURL
            )
            let verifiedURL = try await dashboardVerifier.verify(
                configuration: configuration,
                projectID: projectID
            )
            defaults.set(
                configuration.baseURL.absoluteString,
                forKey: Self.dashboardURLDefaultsKey
            )
            dashboardURLText = configuration.baseURL.absoluteString
            dashboardState = .verified(verifiedURL)
        } catch {
            dashboardState = .failed(Self.errorMessage(error))
        }
    }

    private static func sameEndpoint(_ lhs: URL, _ rhs: URL) -> Bool {
        func normalized(_ url: URL) -> String {
            url.absoluteString.hasSuffix("/")
                ? String(url.absoluteString.dropLast())
                : url.absoluteString
        }
        return normalized(lhs) == normalized(rhs)
    }

    private static func errorMessage(_ error: any Error) -> String {
        (error as? any LocalizedError)?.errorDescription
            ?? error.localizedDescription
    }
}

struct DeliveryAgentOrchestratorConnectionScene: View {
    @StateObject private var model =
        DeliveryAgentOrchestratorConnectionViewModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label(
                L10n.string("Agent Orchestrator"),
                systemImage: "point.3.connected.trianglepath.dotted"
            )
            .font(.title2.weight(.semibold))

            Text(
                L10n.string(
                    "OpenMac connects only to a loopback AO daemon and verifies its served API version before reading projects."
                )
            )
            .foregroundStyle(.secondary)

            TextField(
                L10n.string("Agent Orchestrator URL"),
                text: $model.baseURLText
            )
            .textFieldStyle(.roundedBorder)
            .disabled(model.isConnecting)

            HStack {
                Button(L10n.string("Discover Running AO")) {
                    model.discoverDaemon()
                }
                .buttonStyle(.bordered)
                .disabled(model.isConnecting)

                Button(
                    model.isConnecting
                        ? L10n.string("Connecting…")
                        : L10n.string("Connect")
                ) {
                    Task { await model.connect() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.isConnecting)

                Text(model.statusMessage)
                    .foregroundStyle(statusColor)
                    .textSelection(.enabled)
            }

            if let discoveryMessage = model.discoveryMessage {
                Text(discoveryMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            if !model.projectNames.isEmpty {
                GroupBox(L10n.string("AO Projects")) {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(model.projectNames, id: \.self) {
                            Text($0)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            GroupBox(L10n.string("AO Dashboard (optional)")) {
                VStack(alignment: .leading, spacing: 8) {
                    TextField(
                        L10n.string("Dashboard root URL"),
                        text: $model.dashboardURLText
                    )
                    .textFieldStyle(.roundedBorder)
                    .disabled(model.isConnecting)

                    HStack {
                        Button(L10n.string("Verify Dashboard Route")) {
                            Task { await model.verifyDashboard() }
                        }
                        .buttonStyle(.bordered)
                        .disabled(
                            model.isConnecting
                                || model.projectNames.isEmpty
                                || model.dashboardURLText
                                    .trimmingCharacters(in: .whitespacesAndNewlines)
                                    .isEmpty
                        )

                        Text(model.dashboardStatusMessage)
                            .font(.caption)
                            .foregroundStyle(dashboardStatusColor)
                            .textSelection(.enabled)
                    }
                }
            }

            Spacer()

            Text(
                L10n.string(
                    "Connection success does not enable dispatch by itself. OpenMac requires workspace-scoped permission and a backend-confirmed verification workspace; if either is unavailable, it fails closed."
                )
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(24)
    }

    private var statusColor: Color {
        switch model.state {
        case .failed:
            return .red
        case .connected:
            return .green
        case .idle, .connecting:
            return .secondary
        }
    }

    private var dashboardStatusColor: Color {
        switch model.dashboardState {
        case .failed:
            return .red
        case .verified:
            return .green
        case .unconfigured, .checking:
            return .secondary
        }
    }
}
