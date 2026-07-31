import Foundation
import Testing
@testable import OpenMac

private enum DeliveryAttentionTestSupport {
    static func backend(
        scriptsByTaskID: [UUID: FixtureExecutionScript] = [:],
        projectID: ExecutionProjectID = DeliveryDispatchFixture.projectID
    ) -> DeterministicFixtureExecutionBackend {
        var configuration = DeliveryDispatchFixture.backendConfiguration(
            scriptsByTaskID: scriptsByTaskID
        )
        configuration.projects = [
            ExecutionProject(
                id: projectID,
                name: "Attention Fixture",
                repositoryURL: DeliveryGitTestRepository.shared.rootURL,
                isolation: .isolatedWorkspace
            )
        ]
        configuration.timestampMode = .wallClock
        return DeterministicFixtureExecutionBackend(
            configuration: configuration
        )
    }

    static func services(
        store: FileDeliveryRunStore,
        backend: DeterministicFixtureExecutionBackend
    ) -> (DeliveryDispatcher, DeliveryExecutionReconciler) {
        (
            DeliveryDispatcher(
                store: store,
                backend: backend,
                projectID: DeliveryDispatchFixture.projectID
            ),
            DeliveryExecutionReconciler(
                store: store,
                backend: backend
            )
        )
    }

    static func advance(
        store: FileDeliveryRunStore,
        dispatcher: DeliveryDispatcher,
        reconciler: DeliveryExecutionReconciler,
        maximumSteps: Int = 40,
        until predicate: (DeliveryRun) -> Bool
    ) async throws -> DeliveryRun {
        var latestRun = try #require(try await store.load()?.runs.first)
        for _ in 0..<maximumSteps {
            _ = try await dispatcher.dispatchReadyWave(
                runID: DeliveryDispatchFixture.runID
            )
            let report = try await reconciler.reconcileOnce(
                runID: DeliveryDispatchFixture.runID
            )
            latestRun = try #require(
                report.snapshot.runs.first(where: {
                    $0.id == DeliveryDispatchFixture.runID
                })
            )
            if predicate(latestRun) {
                return latestRun
            }
        }
        return latestRun
    }
}

private struct UnavailableFactsExecutionBackend: ExecutionBackend {
    let backendID: String

    func health() async throws -> ExecutionBackendHealth {
        throw ExecutionBackendError.unavailable("AO is offline.")
    }

    func listProjects() async throws -> [ExecutionProject] {
        throw ExecutionBackendError.unavailable("AO is offline.")
    }

    func start(
        _ request: ExecutionStartRequest
    ) async throws -> ExecutionStartReceipt {
        throw ExecutionBackendError.unavailable("AO is offline.")
    }

    func facts(
        for executionID: ExecutionID,
        after cursor: ExecutionFactCursor?
    ) async throws -> ExecutionFactPage {
        throw ExecutionBackendError.unavailable("AO is offline.")
    }

    func stop(
        executionID: ExecutionID
    ) async throws -> ExecutionStopReceipt {
        throw ExecutionBackendError.unavailable("AO is offline.")
    }
}

private struct PersistedReconcileExecutionBackend: ExecutionBackend {
    nonisolated let backendID: String
    nonisolated let supportsPersistedSessionReconciliation = true
    let backend: DeterministicFixtureExecutionBackend

    init(_ backend: DeterministicFixtureExecutionBackend) {
        self.backend = backend
        backendID = backend.backendID
    }

    func health() async throws -> ExecutionBackendHealth {
        try await backend.health()
    }

    func listProjects() async throws -> [ExecutionProject] {
        try await backend.listProjects()
    }

    func start(
        _ request: ExecutionStartRequest
    ) async throws -> ExecutionStartReceipt {
        try await backend.start(request)
    }

    func facts(
        for executionID: ExecutionID,
        after cursor: ExecutionFactCursor?
    ) async throws -> ExecutionFactPage {
        try await backend.facts(for: executionID, after: cursor)
    }

    func stop(
        executionID: ExecutionID
    ) async throws -> ExecutionStopReceipt {
        try await backend.stop(executionID: executionID)
    }
}

@Suite("Delivery v2 attention-first fixture loop", .serialized)
struct DeliveryAttentionTests {
    @Test("fixture facts advance dependency waves to ready to merge")
    func happyFixtureReachesReadyToMerge() async throws {
        let (store, directoryURL) = try await DeliveryDispatchFixture.makeStore(
            label: "attention-happy"
        )
        defer { try? FileManager.default.removeItem(at: directoryURL) }
        let backend = DeliveryAttentionTestSupport.backend()
        let (dispatcher, reconciler) = DeliveryAttentionTestSupport.services(
            store: store,
            backend: backend
        )

        let run = try await DeliveryAttentionTestSupport.advance(
            store: store,
            dispatcher: dispatcher,
            reconciler: reconciler
        ) {
            DeliveryDispatchStateReducer.state(for: $0) == .readyToMerge
        }

        #expect(DeliveryDispatchStateReducer.state(for: run) == .readyToMerge)
        #expect(run.attempts.count == 3)
        #expect(run.attempts.allSatisfy { $0.status == .succeeded })
        #expect(run.attempts.allSatisfy { $0.isFactStreamExhausted })
        #expect(!run.executionObservations.isEmpty)
        #expect(!run.evidenceFacts.isEmpty)
        #expect(!run.pullRequests.isEmpty)
        #expect(DeliveryRunValidator.isValid(run))
        let dashboard = DeliveryAttentionDashboard.make(for: run)
        #expect(dashboard.needsYou.isEmpty)
        #expect(dashboard.running.isEmpty)
        #expect(dashboard.verifying.isEmpty)
        #expect(dashboard.readyToMerge.count == 1)
    }

    @Test("persisted cursor resumes on a new reconciler without replay")
    func persistedCursorResumesWithoutDuplicates() async throws {
        let (store, directoryURL) = try await DeliveryDispatchFixture.makeStore(
            label: "attention-cursor"
        )
        defer { try? FileManager.default.removeItem(at: directoryURL) }
        let backend = DeliveryAttentionTestSupport.backend()
        let dispatcher = DeliveryDispatcher(
            store: store,
            backend: backend,
            projectID: DeliveryDispatchFixture.projectID
        )
        _ = try await dispatcher.dispatchReadyWave(
            runID: DeliveryDispatchFixture.runID
        )
        let firstReconciler = DeliveryExecutionReconciler(
            store: store,
            backend: backend
        )
        let first = try await firstReconciler.reconcileOnce(
            runID: DeliveryDispatchFixture.runID
        )
        let firstRun = try #require(first.snapshot.runs.first)
        #expect(firstRun.executionObservations.count == 2)
        #expect(firstRun.attempts.allSatisfy { $0.lastFactSequence == 1 })
        let firstAttempt = try #require(firstRun.attempts.first)
        let persistedCursor = try #require(firstAttempt.nextFactCursor)
        let idle = try await store.recordExecutionFactPage(
            ExecutionFactPage(
                facts: [],
                nextCursor: ExecutionFactCursor(persistedCursor),
                hasMore: true
            ),
            runID: DeliveryDispatchFixture.runID,
            attemptID: firstAttempt.id,
            expectedCursor: ExecutionFactCursor(persistedCursor),
            receivedAt: Date()
        )
        #expect(idle.storeRevision == first.snapshot.storeRevision)

        let restartedReconciler = DeliveryExecutionReconciler(
            store: FileDeliveryRunStore(fileURL: store.fileURL),
            backend: backend
        )
        let second = try await restartedReconciler.reconcileOnce(
            runID: DeliveryDispatchFixture.runID
        )
        let secondRun = try #require(second.snapshot.runs.first)
        #expect(secondRun.executionObservations.count == 4)
        #expect(secondRun.attempts.allSatisfy { $0.lastFactSequence == 2 })
        #expect(
            Set(secondRun.executionObservations.map(\.id)).count
                == secondRun.executionObservations.count
        )
    }

    @Test("backend outage persists Unknown attention and recovery clears it")
    func reconcileFailureFailsClosedUntilRecovery() async throws {
        let (store, directoryURL) = try await DeliveryDispatchFixture.makeStore(
            label: "attention-reconcile-outage"
        )
        defer { try? FileManager.default.removeItem(at: directoryURL) }
        let backend = DeliveryAttentionTestSupport.backend()
        let dispatcher = DeliveryDispatcher(
            store: store,
            backend: backend,
            projectID: DeliveryDispatchFixture.projectID
        )
        _ = try await dispatcher.dispatchReadyWave(
            runID: DeliveryDispatchFixture.runID
        )
        let outageReconciler = DeliveryExecutionReconciler(
            store: store,
            backend: UnavailableFactsExecutionBackend(
                backendID: backend.backendID
            )
        )

        let outage = try await outageReconciler.reconcileOnce(
            runID: DeliveryDispatchFixture.runID
        )
        let outageRun = try #require(outage.snapshot.runs.first)
        let outageDashboard = DeliveryAttentionDashboard.make(for: outageRun)

        #expect(outage.failuresByAttemptID.count == 2)
        #expect(outageRun.attempts.allSatisfy { $0.status == .running })
        #expect(
            outageRun.attempts.allSatisfy {
                $0.lastReconcileFailureReason == "AO is offline."
                    && $0.lastReconcileFailedAt != nil
            }
        )
        #expect(DeliveryDispatchStateReducer.state(for: outageRun) == .needsYou)
        #expect(outageDashboard.needsYou.count == 2)
        #expect(
            outageDashboard.needsYou.allSatisfy {
                $0.detail == "AO is offline."
            }
        )

        let recovery = try await DeliveryExecutionReconciler(
            store: store,
            backend: backend
        ).reconcileOnce(runID: DeliveryDispatchFixture.runID)
        let recoveredRun = try #require(recovery.snapshot.runs.first)

        #expect(recovery.failuresByAttemptID.isEmpty)
        #expect(
            recoveredRun.attempts.allSatisfy {
                $0.lastReconcileFailureReason == nil
                    && $0.lastReconcileFailedAt == nil
            }
        )
        #expect(DeliveryDispatchStateReducer.state(for: recoveredRun) == .running)
    }

    @Test("stop acknowledgement remains pending until stopped facts arrive")
    func stopRequiresFactConfirmation() async throws {
        let (store, directoryURL) = try await DeliveryDispatchFixture.makeStore(
            label: "attention-stop-confirmation"
        )
        defer { try? FileManager.default.removeItem(at: directoryURL) }
        let backend = DeliveryAttentionTestSupport.backend()
        let (dispatcher, reconciler) = DeliveryAttentionTestSupport.services(
            store: store,
            backend: backend
        )
        _ = try await dispatcher.dispatchReadyWave(
            runID: DeliveryDispatchFixture.runID
        )
        _ = try await dispatcher.stopFutureDispatch(
            runID: DeliveryDispatchFixture.runID
        )

        let stop = try await reconciler.stopActiveExecutions(
            runID: DeliveryDispatchFixture.runID
        )
        let acknowledgedRun = try #require(stop.snapshot.runs.first)

        #expect(stop.acknowledgedAttemptIDs.count == 2)
        #expect(stop.alreadyTerminalAttemptIDs.isEmpty)
        #expect(stop.failuresByAttemptID.isEmpty)
        #expect(
            acknowledgedRun.attempts.allSatisfy {
                $0.stopRequestedAt != nil && $0.status == .running
            }
        )

        let confirmation = try await reconciler.reconcileOnce(
            runID: DeliveryDispatchFixture.runID
        )
        let confirmedRun = try #require(confirmation.snapshot.runs.first)

        #expect(
            confirmedRun.attempts.allSatisfy {
                $0.status == .stopped && $0.isFactStreamExhausted
            }
        )
    }

    @Test("control center restart automatically reconciles persisted sessions")
    @MainActor
    func controlCenterRestartReconcilesPersistedSessions() async throws {
        let (store, directoryURL) = try await DeliveryDispatchFixture.makeStore(
            label: "attention-control-center-restart"
        )
        defer { try? FileManager.default.removeItem(at: directoryURL) }
        let backend = DeliveryAttentionTestSupport.backend()
        let dispatcher = DeliveryDispatcher(
            store: store,
            backend: backend,
            projectID: DeliveryDispatchFixture.projectID
        )
        _ = try await dispatcher.dispatchReadyWave(
            runID: DeliveryDispatchFixture.runID
        )
        let model = DeliveryControlCenterViewModel(
            persistence: store,
            backendFactory: { _ in
                PersistedReconcileExecutionBackend(backend)
            }
        )

        await model.load()

        #expect(model.errorMessage == nil)
        #expect(model.run?.executionObservations.count == 2)
        #expect(
            model.run?.attempts.allSatisfy {
                $0.lastFactSequence == 1 && $0.nextFactCursor != nil
            } == true
        )
        #expect(model.dashboard?.state == .running)
        #expect(model.canReconcile)
    }

    @Test("waiting for input appears in Needs You with an actionable reason")
    func blockedFixtureProducesAttention() async throws {
        let (store, directoryURL) = try await DeliveryDispatchFixture.makeStore(
            label: "attention-blocked"
        )
        defer { try? FileManager.default.removeItem(at: directoryURL) }
        let backend = DeliveryAttentionTestSupport.backend(
            scriptsByTaskID: [
                DeliveryDispatchFixture.taskA: .waitingForInput
            ]
        )
        let (dispatcher, reconciler) = DeliveryAttentionTestSupport.services(
            store: store,
            backend: backend
        )

        let run = try await DeliveryAttentionTestSupport.advance(
            store: store,
            dispatcher: dispatcher,
            reconciler: reconciler
        ) {
            DeliveryDispatchStateReducer.state(for: $0) == .needsYou
        }
        let dashboard = DeliveryAttentionDashboard.make(for: run)
        let item = try #require(
            dashboard.needsYou.first(where: {
                $0.taskID == DeliveryDispatchFixture.taskA
            })
        )

        #expect(DeliveryDispatchStateReducer.state(for: run) == .needsYou)
        #expect(item.detail.contains("Choose the intended Xcode scheme"))
        #expect(!item.nextStep.isEmpty)
        #expect(dashboard.readyToMerge.isEmpty)
    }

    @Test("failed backend phase cannot become ready to merge")
    func failedFixtureProducesAttention() async throws {
        let (store, directoryURL) = try await DeliveryDispatchFixture.makeStore(
            label: "attention-failed"
        )
        defer { try? FileManager.default.removeItem(at: directoryURL) }
        let backend = DeliveryAttentionTestSupport.backend(
            scriptsByTaskID: [
                DeliveryDispatchFixture.taskA: .buildFailure
            ]
        )
        let (dispatcher, reconciler) = DeliveryAttentionTestSupport.services(
            store: store,
            backend: backend
        )

        let run = try await DeliveryAttentionTestSupport.advance(
            store: store,
            dispatcher: dispatcher,
            reconciler: reconciler
        ) {
            DeliveryDispatchStateReducer.state(for: $0) == .needsYou
        }
        let dashboard = DeliveryAttentionDashboard.make(for: run)

        #expect(DeliveryDispatchStateReducer.state(for: run) == .needsYou)
        #expect(
            dashboard.needsYou.contains(where: {
                $0.taskID == DeliveryDispatchFixture.taskA
            })
        )
        #expect(dashboard.readyToMerge.isEmpty)
    }

    @Test("successful task without required evidence stays Verifying")
    func missingEvidenceStaysVerifying() async throws {
        let (store, directoryURL) = try await DeliveryDispatchFixture.makeStore(
            label: "attention-missing-evidence"
        )
        defer { try? FileManager.default.removeItem(at: directoryURL) }
        let noEvidence = FixtureExecutionScript(
            factBatches: [
                [.phase(.accepted)],
                [.phase(.running)],
                [.phase(.succeeded)]
            ]
        )
        let backend = DeliveryAttentionTestSupport.backend(
            scriptsByTaskID: [
                DeliveryDispatchFixture.taskA: noEvidence
            ]
        )
        let (dispatcher, reconciler) = DeliveryAttentionTestSupport.services(
            store: store,
            backend: backend
        )

        let run = try await DeliveryAttentionTestSupport.advance(
            store: store,
            dispatcher: dispatcher,
            reconciler: reconciler
        ) {
            $0.attempts.count == 3
                && $0.attempts.allSatisfy { $0.status == .succeeded }
        }
        let dashboard = DeliveryAttentionDashboard.make(for: run)
        let item = try #require(
            dashboard.verifying.first(where: {
                $0.taskID == DeliveryDispatchFixture.taskA
            })
        )

        #expect(DeliveryDispatchStateReducer.state(for: run) == .verifying)
        #expect(item.detail.contains("Missing evidence"))
        #expect(dashboard.readyToMerge.isEmpty)
    }

    @Test("control-center view model completes the happy fixture loop")
    @MainActor
    func controlCenterViewModelCompletesFixture() async throws {
        let (store, directoryURL) = try await DeliveryDispatchFixture.makeStore(
            label: "attention-view-model"
        )
        defer { try? FileManager.default.removeItem(at: directoryURL) }
        let backend = DeliveryAttentionTestSupport.backend(
            projectID: DeliveryControlCenterViewModel.fixtureProjectID(
                for: DeliveryDispatchFixture.runID
            )
        )
        let model = DeliveryControlCenterViewModel(
            persistence: store,
            backendFactory: { _ in backend }
        )

        await model.load()
        #expect(model.dashboard?.state == .queued)
        #expect(model.canRunFixture)

        await model.runFixture()

        #expect(model.errorMessage == nil)
        #expect(model.dashboard?.state == .readyToMerge)
        #expect(model.dashboard?.readyToMerge.count == 1)
        #expect(!model.canRunFixture)
    }
}
