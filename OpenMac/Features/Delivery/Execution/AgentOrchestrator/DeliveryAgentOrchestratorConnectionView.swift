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

@MainActor
final class DeliveryAgentOrchestratorConnectionViewModel: ObservableObject {
    typealias BackendFactory =
        @Sendable (URL, Int?) throws -> any ExecutionBackend

    static let baseURLDefaultsKey =
        "delivery.agentOrchestrator.baseURL"
    static let defaultBaseURL = "http://127.0.0.1:3001"

    @Published var baseURLText: String
    @Published private(set) var state:
        DeliveryAgentOrchestratorConnectionState = .idle
    @Published private(set) var projectNames: [String] = []
    @Published private(set) var discoveryMessage: String?

    private let backendFactory: BackendFactory
    private let defaults: UserDefaults
    private let discovery: AgentOrchestratorDaemonDiscovery
    private var discoveredEndpoint: AgentOrchestratorDaemonEndpoint?

    init(
        defaults: UserDefaults = .standard,
        discovery: AgentOrchestratorDaemonDiscovery = .init(),
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

        let savedBaseURL = defaults.string(
            forKey: Self.baseURLDefaultsKey
        )
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

    func discoverDaemon() {
        state = .idle
        projectNames = []
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

            Spacer()

            Text(
                L10n.string(
                    "Connection success does not enable dispatch by itself. The captured AO contract still lacks a verifiable workspace permission and verification path, so OpenMac continues to fail closed."
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
}
