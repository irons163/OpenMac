import AppKit
import SwiftUI
import UniformTypeIdentifiers

enum DeliveryControlCenterSceneConfiguration {
    static let windowID = "delivery-control-center"
}

struct DeliveryControlCenterScene: View {
    @StateObject private var model: DeliveryControlCenterViewModel
    @Environment(\.scenePhase) private var scenePhase

    init(persistence: FileDeliveryRunStore = FileDeliveryRunStore()) {
        _model = StateObject(
            wrappedValue: DeliveryControlCenterViewModel(
                persistence: persistence
            )
        )
    }

    var body: some View {
        Group {
            if model.isLoading && model.run == nil {
                ProgressView(L10n.string("Loading delivery run…"))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if model.run != nil, model.dashboard != nil {
                DeliveryControlCenterView(model: model)
            } else {
                ContentUnavailableView {
                    Label(
                        L10n.string("No Approved Delivery Run"),
                        systemImage: "shippingbox"
                    )
                } description: {
                    Text(
                        model.errorMessage
                            ?? model.statusMessage
                            ?? L10n.string(
                                "Approve and select a plan before opening the delivery control center."
                            )
                    )
                } actions: {
                    Button(L10n.string("Reload")) {
                        Task { await model.load() }
                    }
                }
            }
        }
        .frame(minWidth: 1040, minHeight: 700)
        .task {
            await model.load()
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            Task { await model.load() }
        }
    }
}

struct DeliveryControlCenterView: View {
    @ObservedObject var model: DeliveryControlCenterViewModel

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            dashboard
            Divider()
            footer
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(model.run?.brief.title ?? L10n.string("Delivery"))
                    .font(.title2.weight(.semibold))
                Text(model.run?.brief.body ?? "")
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                if let run = model.run {
                    Text(
                        "\(run.brief.repository.rootPath) · "
                            + "\(run.brief.repository.baseBranch) · "
                            + "\(run.repositoryIdentity?.baseCommitIdentifier.prefix(10) ?? "")"
                    )
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                }
            }

            Spacer()

            if let dashboard = model.dashboard {
                Label(
                    stateTitle(dashboard.state),
                    systemImage: stateIcon(dashboard.state)
                )
                .font(.headline)
                .foregroundStyle(stateColor(dashboard.state))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    stateColor(dashboard.state).opacity(0.12),
                    in: Capsule()
                )
            }
        }
        .padding(18)
    }

    private var dashboard: some View {
        ScrollView {
            if let dashboard = model.dashboard {
                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: 12),
                        GridItem(.flexible(), spacing: 12)
                    ],
                    alignment: .leading,
                    spacing: 12
                ) {
                    DeliveryAttentionSectionView(
                        title: L10n.string("Needs You"),
                        icon: "person.crop.circle.badge.exclamationmark",
                        color: .orange,
                        items: dashboard.needsYou,
                        emptyMessage: L10n.string("No task needs intervention."),
                        onRetry: retry,
                        onOpenDashboard: openDashboard
                    )
                    DeliveryAttentionSectionView(
                        title: L10n.string("Running"),
                        icon: "bolt.horizontal.circle",
                        color: .blue,
                        items: dashboard.running,
                        emptyMessage: dashboard.queuedTaskCount > 0
                            ? L10n.format(
                                "%d task(s) are queued by dependency order.",
                                dashboard.queuedTaskCount
                            )
                            : L10n.string("No session is running."),
                        onRetry: retry,
                        onOpenDashboard: openDashboard
                    )
                    DeliveryAttentionSectionView(
                        title: L10n.string("Verifying"),
                        icon: "checkmark.seal",
                        color: .purple,
                        items: dashboard.verifying,
                        emptyMessage: L10n.string("No task is waiting for evidence."),
                        onRetry: retry,
                        onOpenDashboard: openDashboard
                    )
                    DeliveryAttentionSectionView(
                        title: L10n.string("Ready to Merge"),
                        icon: "arrow.triangle.merge",
                        color: .green,
                        items: dashboard.readyToMerge,
                        emptyMessage: L10n.string(
                            "Required evidence and pull request checks are not complete yet."
                        ),
                        onRetry: retry,
                        onOpenDashboard: openDashboard
                    )
                }
                .padding(16)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            if let errorMessage = model.errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.octagon.fill")
                    .foregroundStyle(.red)
                    .lineLimit(2)
            } else if let statusMessage = model.statusMessage {
                Text(statusMessage)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            } else {
                Text(
                    L10n.string(
                        "State is derived from persisted backend facts; fixture actions never merge."
                    )
                )
                .foregroundStyle(.secondary)
            }

            Spacer()

            Button(L10n.string("Reload")) {
                Task { await model.load() }
            }
            .disabled(model.isBusy)

            Button(
                model.activity == .exportingFunnel
                    ? L10n.string("Exporting…")
                    : L10n.string("Export Funnel")
            ) {
                exportFunnel()
            }
            .disabled(model.isBusy)

            Button(
                model.activity == .reconciling
                    ? L10n.string("Reconciling…")
                    : L10n.string("Reconcile")
            ) {
                Task { await model.reconcile() }
            }
            .disabled(!model.canReconcile)

            Button(
                model.activity == .verifyingXcode
                    ? L10n.string("Verifying Xcode…")
                    : L10n.string("Verify Xcode")
            ) {
                Task { await model.verifyXcode() }
            }
            .disabled(!model.canVerifyXcode)

            Button(
                model.activity == .stopping
                    ? L10n.string("Stopping…")
                    : L10n.string("Stop")
            ) {
                Task { await model.stop() }
            }
            .disabled(!model.canStop)

            Button(
                model.activity == .runningFixture
                    ? L10n.string("Running Fixture…")
                    : L10n.string("Run Fixture")
            ) {
                Task { await model.runFixture() }
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .disabled(!model.canRunFixture)
        }
        .padding(14)
    }

    private func retry(_ item: DeliveryAttentionItem) {
        guard let taskID = item.taskID else { return }
        Task { await model.retryDispatch(taskID: taskID) }
    }

    private func openDashboard(_ item: DeliveryAttentionItem) {
        Task { await model.openDashboard(for: item) }
    }

    private func exportFunnel() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = "openmac-delivery-funnel.json"
        panel.title = L10n.string("Export Funnel")
        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }
        model.exportFunnel(to: url)
    }

    private func stateTitle(_ state: DerivedDeliveryState) -> String {
        switch state {
        case .draft:
            return L10n.string("Draft")
        case .awaitingApproval:
            return L10n.string("Awaiting Approval")
        case .queued:
            return L10n.string("Queued")
        case .running:
            return L10n.string("Running")
        case .needsYou:
            return L10n.string("Needs You")
        case .verifying:
            return L10n.string("Verifying")
        case .readyToMerge:
            return L10n.string("Ready to Merge")
        case .done:
            return L10n.string("Done")
        case .stopped:
            return L10n.string("Stopped")
        }
    }

    private func stateIcon(_ state: DerivedDeliveryState) -> String {
        switch state {
        case .draft, .awaitingApproval:
            return "doc.text"
        case .queued:
            return "clock"
        case .running:
            return "bolt.horizontal.circle"
        case .needsYou:
            return "person.crop.circle.badge.exclamationmark"
        case .verifying:
            return "checkmark.seal"
        case .readyToMerge:
            return "arrow.triangle.merge"
        case .done:
            return "checkmark.circle.fill"
        case .stopped:
            return "stop.circle"
        }
    }

    private func stateColor(_ state: DerivedDeliveryState) -> Color {
        switch state {
        case .needsYou:
            return .orange
        case .running:
            return .blue
        case .verifying:
            return .purple
        case .readyToMerge, .done:
            return .green
        case .stopped:
            return .red
        case .draft, .awaitingApproval, .queued:
            return .secondary
        }
    }
}

private struct DeliveryAttentionSectionView: View {
    let title: String
    let icon: String
    let color: Color
    let items: [DeliveryAttentionItem]
    let emptyMessage: String
    let onRetry: (DeliveryAttentionItem) -> Void
    let onOpenDashboard: (DeliveryAttentionItem) -> Void

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                if items.isEmpty {
                    Text(emptyMessage)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 74)
                } else {
                    ForEach(items) { item in
                        itemView(item)
                        if item.id != items.last?.id {
                            Divider()
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 4)
        } label: {
            Label("\(title) · \(items.count)", systemImage: icon)
                .font(.headline)
                .foregroundStyle(color)
        }
    }

    private func itemView(_ item: DeliveryAttentionItem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(item.title)
                .font(.headline)
            Text(item.detail)
                .foregroundStyle(.secondary)
            Text(item.nextStep)
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                if item.canRetryDispatch {
                    Button(L10n.string("Retry")) {
                        onRetry(item)
                    }
                }
                if let sourceURL = item.sourceURL {
                    Link(
                        L10n.string("Open Source"),
                        destination: sourceURL
                    )
                }
                if item.sessionRef?.backendID == "agent-orchestrator" {
                    Button(L10n.string("Open AO Dashboard")) {
                        onOpenDashboard(item)
                    }
                }
            }
            .controlSize(.small)
        }
        .padding(.vertical, 4)
    }
}
