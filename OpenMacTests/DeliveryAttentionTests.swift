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
