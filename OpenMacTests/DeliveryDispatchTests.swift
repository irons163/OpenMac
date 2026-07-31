import Foundation
import Testing
@testable import OpenMac

final class DeliveryDispatchTestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Date

    init(startingAt value: Date) {
        self.value = value
    }

    func now() -> Date {
        lock.lock()
        defer { lock.unlock() }
        value = value.addingTimeInterval(1)
        return value
    }
}

private actor DeliveryDispatchConcurrencyProbe {
    private var activeStarts = 0
    private var maximumActiveStarts = 0

    func begin() {
        activeStarts += 1
        maximumActiveStarts = max(maximumActiveStarts, activeStarts)
    }

    func end() {
        activeStarts -= 1
    }

    func maximum() -> Int {
        maximumActiveStarts
    }
}

enum DeliveryDispatchFixture {
    static let createdAt = Date(timeIntervalSince1970: 1_784_371_200)
    static let approvedAt = createdAt.addingTimeInterval(10)
    static let runID = UUID(uuidString: "91000000-0000-0000-0000-000000000001")!
    static let planID = UUID(uuidString: "92000000-0000-0000-0000-000000000001")!
    static let taskA = UUID(uuidString: "93000000-0000-0000-0000-000000000001")!
    static let taskB = UUID(uuidString: "93000000-0000-0000-0000-000000000002")!
    static let taskC = UUID(uuidString: "93000000-0000-0000-0000-000000000003")!
    static let projectID = ExecutionProjectID("fixture-project")

    static func makeDraftRun() throws -> DeliveryRun {
        let repository = DeliveryGitTestRepository.shared
        let context = try DeliveryPlanningRepositoryContext.resolving(
            repositoryRootPath: repository.rootURL.path,
            containerKind: .xcodeProject,
            containerRelativePath: repository.containerRelativePath,
            targetNames: ["OpenMac"],
            schemeNames: ["OpenMac"]
        )
        let identity = try context.identitySnapshot(
            validatingBaseBranch: repository.baseBranch
        )
        let brief = FeatureBrief(
            title: "Dispatch a dependency wave",
            body: "Start two independent tasks before their dependent task.",
            repository: DeliveryRepositoryReference(
                rootPath: repository.rootURL.path,
                baseBranch: repository.baseBranch,
                xcodeContainerRelativePath: repository.containerRelativePath
            ),
            createdAt: createdAt
        )
        let plan = DeliveryPlan(
            id: planID,
            revision: 1,
            tasks: [
                task(id: taskA, title: "Implement model"),
                task(id: taskB, title: "Implement store"),
                task(id: taskC, title: "Integrate feature")
            ],
            dependencyEdges: [
                DependencyEdge(
                    prerequisiteTaskID: taskA,
                    dependentTaskID: taskC
                ),
                DependencyEdge(
                    prerequisiteTaskID: taskB,
                    dependentTaskID: taskC
                )
            ],
            createdAt: createdAt,
            updatedAt: createdAt
        )
        return DeliveryRun(
            id: runID,
            brief: brief,
            repositoryIdentity: identity,
            plan: plan,
            createdAt: createdAt,
            updatedAt: createdAt
        )
    }

    static func makeStore(
        label: String
    ) async throws -> (FileDeliveryRunStore, URL) {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "openmac-dispatch-\(label)-\(UUID().uuidString)",
                isDirectory: true
            )
        let store = FileDeliveryRunStore(
            fileURL: directoryURL.appendingPathComponent("delivery-store.json"),
            reviewNow: { approvedAt }
        )
        let run = try makeDraftRun()
        try await store.save(
            DeliveryRunSnapshot(
                storeRevision: 0,
                savedAt: createdAt,
                runs: [run],
                selectedRunID: run.id
            )
        )
        _ = try await store.approveReviewedPlan(
            try #require(run.plan),
            inRunID: run.id,
            expectedStoreRevision: 0,
            expectedPlanRevision: 1,
            approvedBy: "dispatch-reviewer"
        )
        return (store, directoryURL)
    }

    static func backendConfiguration(
        isolation: ExecutionProjectIsolation = .isolatedWorkspace,
        scriptsByTaskID: [UUID: FixtureExecutionScript] = [:]
    ) -> FixtureExecutionBackendConfiguration {
        var configuration = FixtureExecutionBackendConfiguration.standard
        configuration.projects = [
            ExecutionProject(
                id: projectID,
                name: "Dispatch Fixture",
                repositoryURL: DeliveryGitTestRepository.shared.rootURL,
                isolation: isolation
            )
        ]
        configuration.scriptsByTaskID = scriptsByTaskID
        return configuration
    }

    static func dispatcher(
        store: FileDeliveryRunStore,
        backend: any ExecutionBackend,
        clock: DeliveryDispatchTestClock
    ) -> DeliveryDispatcher {
        DeliveryDispatcher(
            store: store,
            backend: backend,
            projectID: projectID,
            now: clock.now
        )
    }

    static func markCurrentAttemptsSucceeded(
        in store: FileDeliveryRunStore,
        at completedAt: Date
    ) async throws -> DeliveryRunSnapshot {
        let current = try #require(try await store.load())
        var runs = current.runs
        let runIndex = try #require(runs.firstIndex(where: { $0.id == runID }))
        for attemptIndex in runs[runIndex].attempts.indices
        where runs[runIndex].attempts[attemptIndex].status == .running {
            runs[runIndex].attempts[attemptIndex].status = .succeeded
            runs[runIndex].attempts[attemptIndex].endedAt = completedAt
        }
        runs[runIndex].updatedAt = completedAt
        let updated = DeliveryRunSnapshot(
            format: current.format,
            schemaVersion: current.schemaVersion,
            storeRevision: current.storeRevision + 1,
            savedAt: completedAt,
            runs: runs,
            selectedRunID: current.selectedRunID
        )
        try await store.save(updated)
        return try #require(try await store.load())
    }

    private static func task(id: UUID, title: String) -> DeliveryTask {
        let criterionID = UUID()
        return DeliveryTask(
            id: id,
            title: title,
            workerPrompt: "Complete \(title) in the isolated backend workspace.",
            acceptanceCriteria: [
                AcceptanceCriterion(
                    id: criterionID,
                    statement: "\(title) is implemented and covered."
                )
            ],
            riskLevel: .medium,
            evidenceRequirements: [
                EvidenceRequirement(
                    kind: .xcodeTest,
                    description: "The OpenMac tests pass.",
                    coveredCriterionIDs: [criterionID]
                )
            ],
            targetHints: ["OpenMac"],
            schemeHints: ["OpenMac"]
        )
    }
}

@Suite("Delivery v2 idempotent dispatch", .serialized)
struct DeliveryDispatchTests {
    @Test("three-task DAG dispatches two tasks in parallel before its dependent")
    func readyWavesDispatchInDependencyOrder() async throws {
        let (store, directoryURL) = try await DeliveryDispatchFixture.makeStore(
            label: "waves"
        )
        defer { try? FileManager.default.removeItem(at: directoryURL) }
        let probe = DeliveryDispatchConcurrencyProbe()
        let backend = DeterministicFixtureExecutionBackend(
            configuration: DeliveryDispatchFixture.backendConfiguration()
        ) { operation, _ in
            guard operation == .start else { return }
            await probe.begin()
            try await Task.sleep(nanoseconds: 40_000_000)
            await probe.end()
        }
        let clock = DeliveryDispatchTestClock(
            startingAt: DeliveryDispatchFixture.approvedAt
        )
        let dispatcher = DeliveryDispatchFixture.dispatcher(
            store: store,
            backend: backend,
            clock: clock
        )
        let initialRun = try #require(
            try await store.load()?.runs.first
        )
        #expect(
            DeliveryDispatchStateReducer.readyTaskIDs(in: initialRun)
                == [DeliveryDispatchFixture.taskA, DeliveryDispatchFixture.taskB]
        )
        #expect(DeliveryDispatchStateReducer.state(for: initialRun) == .queued)

        let firstWave = try await dispatcher.dispatchReadyWave(
            runID: DeliveryDispatchFixture.runID
        )
        #expect(
            Set(firstWave.startedTaskIDs)
                == Set([
                    DeliveryDispatchFixture.taskA,
                    DeliveryDispatchFixture.taskB
                ])
        )
        #expect(await probe.maximum() == 2)
        #expect(await backend.executionCount() == 2)
        let firstRun = try #require(
            firstWave.snapshot.runs.first(where: {
                $0.id == DeliveryDispatchFixture.runID
            })
        )
        #expect(firstRun.attempts.count == 2)
        #expect(firstRun.attempts.allSatisfy { $0.externalSession != nil })
        #expect(firstRun.attempts.allSatisfy { $0.projectID == "fixture-project" })
        #expect(DeliveryRunValidator.isValid(firstRun))
        #expect(DeliveryDispatchStateReducer.state(for: firstRun) == .running)
        let firstRequests = await backend.recordedStartRequests()
        #expect(
            firstRequests.allSatisfy {
                $0.deliveryRunID == DeliveryDispatchFixture.runID
                    && $0.planID == DeliveryDispatchFixture.planID
                    && $0.approvalFingerprint
                        == firstRun.plan?.approval?.scopeFingerprint
                    && $0.baseCommitIdentifier
                        == firstRun.repositoryIdentity?.baseCommitIdentifier
            }
        )

        let duplicate = try await dispatcher.dispatchReadyWave(
            runID: DeliveryDispatchFixture.runID
        )
        #expect(duplicate.requestedTaskIDs.isEmpty)
        #expect(await backend.executionCount() == 2)

        let completed = try await DeliveryDispatchFixture
            .markCurrentAttemptsSucceeded(in: store, at: clock.now())
        let completedRun = try #require(completed.runs.first)
        #expect(
            DeliveryDispatchStateReducer.readyTaskIDs(in: completedRun)
                == [DeliveryDispatchFixture.taskC]
        )

        let secondWave = try await dispatcher.dispatchReadyWave(
            runID: DeliveryDispatchFixture.runID
        )
        #expect(secondWave.startedTaskIDs == [DeliveryDispatchFixture.taskC])
        #expect(await backend.executionCount() == 3)
        #expect(secondWave.snapshot.runs.first?.attempts.count == 3)
        let verified = try await DeliveryDispatchFixture
            .markCurrentAttemptsSucceeded(in: store, at: clock.now())
        #expect(
            verified.runs.first.map(DeliveryDispatchStateReducer.state)
                == .verifying
        )
    }

    @Test("restart replays an unbound reservation without creating another session")
    func restartRecoversReservedAttemptsIdempotently() async throws {
        let (store, directoryURL) = try await DeliveryDispatchFixture.makeStore(
            label: "restart"
        )
        defer { try? FileManager.default.removeItem(at: directoryURL) }
        let backend = DeterministicFixtureExecutionBackend(
            configuration: DeliveryDispatchFixture.backendConfiguration()
        )
        let clock = DeliveryDispatchTestClock(
            startingAt: DeliveryDispatchFixture.approvedAt
        )

        let preparation = try await store.prepareReadyDispatch(
            runID: DeliveryDispatchFixture.runID,
            backendID: backend.backendID,
            projectID: DeliveryDispatchFixture.projectID,
            requestedAt: clock.now()
        )
        #expect(preparation.reservations.count == 2)
        for reservation in preparation.reservations {
            _ = try await backend.start(reservation.request)
        }
        #expect(await backend.executionCount() == 2)
        #expect(
            preparation.snapshot.runs.first?.attempts
                .allSatisfy { $0.externalSession == nil } == true
        )

        let restartedStore = FileDeliveryRunStore(fileURL: store.fileURL)
        let restartedDispatcher = DeliveryDispatchFixture.dispatcher(
            store: restartedStore,
            backend: backend,
            clock: clock
        )
        let recovered = try await restartedDispatcher.dispatchReadyWave(
            runID: DeliveryDispatchFixture.runID
        )

        #expect(await backend.executionCount() == 2)
        #expect(recovered.snapshot.runs.first?.attempts.count == 2)
        #expect(
            recovered.snapshot.runs.first?.attempts
                .allSatisfy { $0.externalSession != nil } == true
        )
        let requests = await backend.recordedStartRequests()
        #expect(
            Set(requests.map(\.requestID))
                == Set(preparation.reservations.map(\.request.requestID))
        )
    }

    @Test("concurrent dispatch clicks share reservations and backend sessions")
    func concurrentDispatchIsIdempotent() async throws {
        let (firstStore, directoryURL) = try await DeliveryDispatchFixture.makeStore(
            label: "concurrent"
        )
        defer { try? FileManager.default.removeItem(at: directoryURL) }
        let probe = DeliveryDispatchConcurrencyProbe()
        let backend = DeterministicFixtureExecutionBackend(
            configuration: DeliveryDispatchFixture.backendConfiguration()
        ) { operation, _ in
            guard operation == .start else { return }
            await probe.begin()
            try await Task.sleep(nanoseconds: 40_000_000)
            await probe.end()
        }
        let clock = DeliveryDispatchTestClock(
            startingAt: DeliveryDispatchFixture.approvedAt
        )
        let secondStore = FileDeliveryRunStore(fileURL: firstStore.fileURL)
        let firstDispatcher = DeliveryDispatchFixture.dispatcher(
            store: firstStore,
            backend: backend,
            clock: clock
        )
        let secondDispatcher = DeliveryDispatchFixture.dispatcher(
            store: secondStore,
            backend: backend,
            clock: clock
        )

        async let first = firstDispatcher.dispatchReadyWave(
            runID: DeliveryDispatchFixture.runID
        )
        async let second = secondDispatcher.dispatchReadyWave(
            runID: DeliveryDispatchFixture.runID
        )
        _ = try await (first, second)

        let persisted = try #require(try await firstStore.load())
        let run = try #require(persisted.runs.first)
        #expect(run.attempts.count == 2)
        #expect(Set(run.attempts.compactMap(\.externalSession)).count == 2)
        #expect(await backend.executionCount() == 2)
        #expect(await probe.maximum() >= 2)
    }

    @Test("stopping a run prevents later dependency waves")
    func stopPreventsFutureDispatch() async throws {
        let (store, directoryURL) = try await DeliveryDispatchFixture.makeStore(
            label: "stop"
        )
        defer { try? FileManager.default.removeItem(at: directoryURL) }
        let backend = DeterministicFixtureExecutionBackend(
            configuration: DeliveryDispatchFixture.backendConfiguration()
        )
        let clock = DeliveryDispatchTestClock(
            startingAt: DeliveryDispatchFixture.approvedAt
        )
        let dispatcher = DeliveryDispatchFixture.dispatcher(
            store: store,
            backend: backend,
            clock: clock
        )
        _ = try await dispatcher.dispatchReadyWave(
            runID: DeliveryDispatchFixture.runID
        )
        _ = try await DeliveryDispatchFixture.markCurrentAttemptsSucceeded(
            in: store,
            at: clock.now()
        )

        let stopped = try await dispatcher.stopFutureDispatch(
            runID: DeliveryDispatchFixture.runID
        )
        let stoppedRevision = stopped.storeRevision
        let repeatedStop = try await dispatcher.stopFutureDispatch(
            runID: DeliveryDispatchFixture.runID
        )
        #expect(repeatedStop.storeRevision == stoppedRevision)

        do {
            _ = try await dispatcher.dispatchReadyWave(
                runID: DeliveryDispatchFixture.runID
            )
            Issue.record("Expected stopped dispatch to fail closed")
        } catch let error as DeliveryDispatchError {
            #expect(error == .runStopped(DeliveryDispatchFixture.runID))
        }
        #expect(await backend.executionCount() == 2)
        #expect(repeatedStop.runs.first?.attempts.count == 2)
        #expect(
            repeatedStop.runs.first.map(DeliveryDispatchStateReducer.state)
                == .stopped
        )
    }

    @Test("shared workspace projects fail before an attempt is reserved")
    func missingIsolationFailsClosed() async throws {
        let (store, directoryURL) = try await DeliveryDispatchFixture.makeStore(
            label: "isolation"
        )
        defer { try? FileManager.default.removeItem(at: directoryURL) }
        let backend = DeterministicFixtureExecutionBackend(
            configuration: DeliveryDispatchFixture.backendConfiguration(
                isolation: .sharedWorkspace
            )
        )
        let clock = DeliveryDispatchTestClock(
            startingAt: DeliveryDispatchFixture.approvedAt
        )
        let dispatcher = DeliveryDispatchFixture.dispatcher(
            store: store,
            backend: backend,
            clock: clock
        )

        do {
            _ = try await dispatcher.dispatchReadyWave(
                runID: DeliveryDispatchFixture.runID
            )
            Issue.record("Expected isolation preflight to fail")
        } catch let error as DeliveryDispatchError {
            #expect(
                error == .isolationUnavailable(
                    DeliveryDispatchFixture.projectID
                )
            )
        }

        #expect(await backend.invocationCount(for: .start) == 0)
        #expect(try await store.load()?.runs.first?.attempts.isEmpty == true)
    }

    @Test("backend start failures retain one retryable reservation per task")
    func backendFailureDoesNotCreateGhostAttempts() async throws {
        let (store, directoryURL) = try await DeliveryDispatchFixture.makeStore(
            label: "failure"
        )
        defer { try? FileManager.default.removeItem(at: directoryURL) }
        let failureScript = FixtureExecutionScript(
            factBatches: [],
            startError: .unavailable("fixture backend unavailable")
        )
        let backend = DeterministicFixtureExecutionBackend(
            configuration: DeliveryDispatchFixture.backendConfiguration(
                scriptsByTaskID: [
                    DeliveryDispatchFixture.taskA: failureScript,
                    DeliveryDispatchFixture.taskB: failureScript
                ]
            )
        )
        let clock = DeliveryDispatchTestClock(
            startingAt: DeliveryDispatchFixture.approvedAt
        )
        let dispatcher = DeliveryDispatchFixture.dispatcher(
            store: store,
            backend: backend,
            clock: clock
        )

        let first = try await dispatcher.dispatchReadyWave(
            runID: DeliveryDispatchFixture.runID
        )
        #expect(first.failedTaskIDs.count == 2)
        #expect(await backend.executionCount() == 0)
        let failedRun = try #require(first.snapshot.runs.first)
        #expect(failedRun.attempts.count == 2)
        #expect(failedRun.attempts.allSatisfy { $0.externalSession == nil })
        #expect(
            failedRun.attempts.allSatisfy {
                $0.dispatchFailureReason == "fixture backend unavailable"
            }
        )
        #expect(DeliveryDispatchStateReducer.state(for: failedRun) == .needsYou)

        let originalKeys = Set(failedRun.attempts.map(\.idempotencyKey))
        let second = try await dispatcher.dispatchReadyWave(
            runID: DeliveryDispatchFixture.runID
        )
        let retriedRun = try #require(second.snapshot.runs.first)
        #expect(retriedRun.attempts.count == 2)
        #expect(Set(retriedRun.attempts.map(\.idempotencyKey)) == originalKeys)
        #expect(await backend.executionCount() == 0)
        #expect(await backend.invocationCount(for: .start) == 4)
    }
}
