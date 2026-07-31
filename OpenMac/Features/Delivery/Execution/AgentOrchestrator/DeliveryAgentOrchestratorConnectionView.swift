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
        @Sendable (URL) throws -> any ExecutionBackend

    static let baseURLDefaultsKey =
        "delivery.agentOrchestrator.baseURL"
    static let defaultBaseURL = "http://127.0.0.1:3001"

    @Published var baseURLText: String
    @Published private(set) var state:
        DeliveryAgentOrchestratorConnectionState = .idle
    @Published private(set) var projectNames: [String] = []

    private let backendFactory: BackendFactory
    private let defaults: UserDefaults

    init(
        defaults: UserDefaults = .standard,
        backendFactory: @escaping BackendFactory = { baseURL in
            let configuration = try AgentOrchestratorBackendConfiguration(
                baseURL: baseURL
            )
            return AgentOrchestratorExecutionBackend(
                configuration: configuration
            )
        }
    ) {
        self.defaults = defaults
        self.backendFactory = backendFactory
        baseURLText = defaults.string(
            forKey: Self.baseURLDefaultsKey
        ) ?? Self.defaultBaseURL
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
            let backend = try backendFactory(baseURL)
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
