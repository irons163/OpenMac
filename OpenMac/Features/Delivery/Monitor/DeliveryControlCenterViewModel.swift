import Combine
import Foundation

@MainActor
final class DeliveryControlCenterViewModel: ObservableObject {
    enum Activity: Equatable {
        case idle
        case runningFixture
        case reconciling
        case verifyingXcode
        case retrying
        case stopping
    }

    typealias BackendFactory = @Sendable (DeliveryRun) throws -> any ExecutionBackend

    @Published private(set) var run: DeliveryRun?
    @Published private(set) var dashboard: DeliveryAttentionDashboard?
    @Published private(set) var activity: Activity = .idle
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var statusMessage: String?

    private let persistence: FileDeliveryRunStore
    private let backendFactory: BackendFactory
    private let now: @Sendable () -> Date
    private let xcodeVerificationCoordinator:
        DeliveryXcodeVerificationCoordinator
    private var configuredRunID: UUID?
    private var dispatcher: DeliveryDispatcher?
    private var reconciler: DeliveryExecutionReconciler?
    private var supportsPersistedSessionReconciliation = false

    init(
        persistence: FileDeliveryRunStore = FileDeliveryRunStore(),
        backendFactory: @escaping BackendFactory = {
            try DeliveryControlCenterViewModel.makeFixtureBackend(for: $0)
        },
        xcodeVerifier: XcodeVerifier = XcodeVerifier(),
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.persistence = persistence
        self.backendFactory = backendFactory
        self.now = now
        xcodeVerificationCoordinator =
            DeliveryXcodeVerificationCoordinator(
                store: persistence,
                verifier: xcodeVerifier,
                now: now
            )
    }

    var isBusy: Bool {
        isLoading || activity != .idle
    }

    var canRunFixture: Bool {
        guard !isBusy, let run else { return false }
        let state = DeliveryDispatchStateReducer.state(for: run)
        return run.plan?.approval != nil
            && state != .readyToMerge
            && state != .done
            && state != .stopped
    }

    var canStop: Bool {
        guard !isBusy, let run else { return false }
        return run.plan?.approval != nil && run.stoppedAt == nil
    }

    var canReconcile: Bool {
        guard !isBusy, supportsPersistedSessionReconciliation, let run else {
            return false
        }
        return run.attempts.contains {
            $0.externalSession != nil
                && !$0.isFactStreamExhausted
                && [.queued, .running, .blocked, .unknown].contains($0.status)
        }
    }

    var canVerifyXcode: Bool {
        !isBusy && nextXcodeVerificationTarget() != nil
    }

    func load() async {
        guard !isBusy else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            try await reloadSelectedRun()
            guard run != nil else { return }
            try configureServicesIfNeeded()
            if supportsPersistedSessionReconciliation,
               let runID = run?.id,
               run?.attempts.contains(where: {
                   $0.externalSession != nil
                       && !$0.isFactStreamExhausted
                       && [.queued, .running, .blocked, .unknown]
                           .contains($0.status)
               }) == true {
                try await reconcileSelectedRun(runID: runID)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func reconcile() async {
        guard canReconcile, let runID = run?.id else { return }
        activity = .reconciling
        errorMessage = nil
        statusMessage = nil
        defer { activity = .idle }
        do {
            try configureServicesIfNeeded()
            try await reconcileSelectedRun(runID: runID)
        } catch {
            errorMessage = error.localizedDescription
            try? await reloadSelectedRun()
        }
    }

    func verifyXcode() async {
        guard canVerifyXcode,
              let runID = run?.id,
              let target = nextXcodeVerificationTarget() else {
            return
        }
        activity = .verifyingXcode
        errorMessage = nil
        statusMessage = nil
        defer { activity = .idle }
        do {
            let report = try await xcodeVerificationCoordinator.verify(
                runID: runID,
                taskID: target.taskID,
                kind: target.kind
            )
            try await apply(snapshot: report.snapshot)
            statusMessage =
                "Xcode \(target.kind.rawValue) for \(target.title) "
                + (report.record.exitCode == 0
                    && !report.record.timedOut
                    ? "passed."
                    : "failed with exit \(report.record.exitCode).")
        } catch {
            errorMessage = error.localizedDescription
            try? await reloadSelectedRun()
        }
    }

    func runFixture() async {
        guard canRunFixture, let runID = run?.id else { return }
        activity = .runningFixture
        errorMessage = nil
        statusMessage = nil
        defer { activity = .idle }

        do {
            try configureServicesIfNeeded()
            guard let dispatcher, let reconciler else {
                throw DeliveryDispatchError.missingRun(runID)
            }

            var previousRevision = -1
            var importedFacts = 0
            for _ in 0..<64 {
                let dispatch = try await dispatcher.dispatchReadyWave(
                    runID: runID
                )
                let reconcile = try await reconciler.reconcileOnce(
                    runID: runID
                )
                importedFacts += reconcile.importedFactCount
                if !reconcile.failuresByAttemptID.isEmpty {
                    let failures = reconcile.failuresByAttemptID.values
                        .sorted()
                        .joined(separator: " · ")
                    throw DeliveryExecutionReconcileError.malformedFactPage(
                        attemptID: reconcile.failuresByAttemptID.keys
                            .sorted { $0.uuidString < $1.uuidString }
                            .first ?? UUID(),
                        reason: failures
                    )
                }
                try await apply(snapshot: reconcile.snapshot)
                guard let currentRun = run else { break }
                let state = DeliveryDispatchStateReducer.state(for: currentRun)
                if state == .readyToMerge
                    || state == .needsYou
                    || state == .stopped {
                    break
                }
                let currentRevision = reconcile.snapshot.storeRevision
                let madeProgress = currentRevision != previousRevision
                    || !dispatch.requestedTaskIDs.isEmpty
                    || reconcile.importedFactCount > 0
                if !madeProgress {
                    break
                }
                previousRevision = currentRevision
            }
            statusMessage = "Fixture reconciled \(importedFacts) backend fact(s)."
        } catch {
            errorMessage = error.localizedDescription
            try? await reloadSelectedRun()
        }
    }

    func retryDispatch(taskID: UUID) async {
        guard dashboard?.needsYou.contains(where: {
            $0.taskID == taskID && $0.canRetryDispatch
        }) == true else {
            return
        }
        activity = .retrying
        defer { activity = .idle }
        errorMessage = nil
        statusMessage = nil
        guard let runID = run?.id else { return }
        do {
            try configureServicesIfNeeded()
            guard let dispatcher else {
                throw DeliveryDispatchError.missingRun(runID)
            }
            let report = try await dispatcher.dispatchReadyWave(runID: runID)
            try await apply(snapshot: report.snapshot)
            statusMessage = report.failedTaskIDs.isEmpty
                ? "The persisted dispatch reservation was retried."
                : "The backend still cannot bind the persisted reservation."
        } catch {
            errorMessage = error.localizedDescription
            try? await reloadSelectedRun()
        }
    }

    func stop() async {
        guard canStop, let runID = run?.id else { return }
        activity = .stopping
        defer { activity = .idle }
        errorMessage = nil
        statusMessage = nil
        do {
            try configureServicesIfNeeded()
            guard let dispatcher, let reconciler else {
                throw DeliveryDispatchError.missingRun(runID)
            }
            _ = try await dispatcher.stopFutureDispatch(
                runID: runID
            )
            let report = try await reconciler.stopActiveExecutions(
                runID: runID
            )
            try await apply(snapshot: report.snapshot)
            if report.failuresByAttemptID.isEmpty {
                statusMessage =
                    "Future dispatch stopped; "
                    + "\(report.acknowledgedAttemptIDs.count) session stop request(s) "
                    + "acknowledged. Termination remains pending until backend "
                    + "facts confirm it."
            } else {
                errorMessage = report.failuresByAttemptID.values
                    .sorted()
                    .joined(separator: " · ")
            }
        } catch {
            errorMessage = error.localizedDescription
            try? await reloadSelectedRun()
        }
    }

    private func reloadSelectedRun() async throws {
        guard let snapshot = try await persistence.load(),
              let selectedRunID = snapshot.selectedRunID,
              let selectedRun = snapshot.runs.first(where: {
                  $0.id == selectedRunID
              }) else {
            run = nil
            dashboard = nil
            statusMessage = "Approve and select a delivery plan before opening the control center."
            return
        }
        try await apply(snapshot: snapshot, runID: selectedRun.id)
    }

    private func apply(
        snapshot: DeliveryRunSnapshot,
        runID: UUID? = nil
    ) async throws {
        let targetRunID = runID ?? run?.id ?? snapshot.selectedRunID
        guard let targetRunID,
              let updatedRun = snapshot.runs.first(where: {
                  $0.id == targetRunID
              }) else {
            throw DeliveryDispatchError.missingRun(targetRunID ?? UUID())
        }
        run = updatedRun
        dashboard = DeliveryAttentionDashboard.make(for: updatedRun)
    }

    private func reconcileSelectedRun(runID: UUID) async throws {
        guard let reconciler else {
            throw DeliveryDispatchError.missingRun(runID)
        }
        let report = try await reconciler.reconcileOnce(runID: runID)
        try await apply(snapshot: report.snapshot)
        if report.failuresByAttemptID.isEmpty {
            statusMessage =
                "Reconciled \(report.reconciledAttemptIDs.count) persisted "
                + "session(s) and imported \(report.importedFactCount) fact(s)."
        } else {
            statusMessage =
                "Reconcile completed with "
                + "\(report.failuresByAttemptID.count) session(s) needing attention."
        }
    }

    private struct XcodeVerificationTarget {
        let taskID: UUID
        let title: String
        let kind: XcodeVerificationKind
    }

    private func nextXcodeVerificationTarget()
        -> XcodeVerificationTarget?
    {
        guard let run, let plan = run.plan else { return nil }
        let attempts = DeliveryDispatchStateReducer
            .latestAttemptsByTaskID(in: run)
        var latestEvidence: [String: EvidenceFact] = [:]
        for fact in run.evidenceFacts {
            let key =
                "\(fact.attemptID.uuidString):\(fact.requirementID.uuidString)"
            if let current = latestEvidence[key],
               current.receivedAt > fact.receivedAt
                    || (current.receivedAt == fact.receivedAt
                        && current.id.uuidString > fact.id.uuidString) {
                continue
            }
            latestEvidence[key] = fact
        }
        for task in plan.tasks {
            guard let attempt = attempts[task.id],
                  attempt.status == .succeeded else {
                continue
            }
            for kind in [
                XcodeVerificationKind.build,
                XcodeVerificationKind.test
            ] {
                let requirements = task.evidenceRequirements.filter {
                    $0.kind == kind.evidenceKind
                }
                guard !requirements.isEmpty,
                      requirements.contains(where: { requirement in
                          latestEvidence[
                              "\(attempt.id.uuidString):\(requirement.id.uuidString)"
                          ]?.result != .passed
                      }) else {
                    continue
                }
                return XcodeVerificationTarget(
                    taskID: task.id,
                    title: task.title,
                    kind: kind
                )
            }
        }
        return nil
    }

    private func configureServicesIfNeeded() throws {
        guard let run else {
            throw DeliveryDispatchError.missingRun(UUID())
        }
        guard configuredRunID != run.id else { return }
        let backend = try backendFactory(run)
        let persistedProjectIDs = Set(
            run.attempts.compactMap { attempt -> String? in
                guard attempt.backendID == backend.backendID else {
                    return nil
                }
                return attempt.projectID ?? attempt.externalSession?.projectID
            }
        )
        guard persistedProjectIDs.count <= 1 else {
            throw ExecutionBackendError.conflict(
                "The persisted run contains sessions from multiple backend projects."
            )
        }
        let projectID = persistedProjectIDs.first.map(ExecutionProjectID.init)
            ?? Self.fixtureProjectID(for: run.id)
        dispatcher = DeliveryDispatcher(
            store: persistence,
            backend: backend,
            projectID: projectID,
            now: now
        )
        reconciler = DeliveryExecutionReconciler(
            store: persistence,
            backend: backend,
            now: now
        )
        supportsPersistedSessionReconciliation =
            backend.supportsPersistedSessionReconciliation
        configuredRunID = run.id
    }

    nonisolated static func fixtureProjectID(for runID: UUID) -> ExecutionProjectID {
        ExecutionProjectID("fixture-\(runID.uuidString.lowercased())")
    }

    nonisolated private static func makeFixtureBackend(
        for run: DeliveryRun
    ) throws -> any ExecutionBackend {
        guard let identity = run.repositoryIdentity else {
            throw DeliveryDispatchError.missingRepositoryIdentity(run.id)
        }
        let baseTime = max(Date(), run.updatedAt)
        var configuration = FixtureExecutionBackendConfiguration.standard
        configuration.baseTime = baseTime
        configuration.timestampMode = .wallClock
        configuration.health = ExecutionBackendHealth(
            state: .ready,
            backendName: "Deterministic Fixture",
            version: "1",
            checkedAt: baseTime
        )
        configuration.projects = [
            ExecutionProject(
                id: fixtureProjectID(for: run.id),
                name: run.brief.title,
                repositoryURL: URL(
                    fileURLWithPath: identity.resolvedRepositoryRootPath,
                    isDirectory: true
                ),
                isolation: .isolatedWorkspace
            )
        ]
        return DeterministicFixtureExecutionBackend(
            configuration: configuration
        )
    }
}
