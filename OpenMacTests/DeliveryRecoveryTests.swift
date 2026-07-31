import Foundation
import Testing
@testable import OpenMac

@Suite("Delivery v2 recovery and local funnel export", .serialized)
struct DeliveryRecoveryTests {
    @Test("terminal failure retry creates one new isolated attempt")
    func terminalFailureCreatesNewAttempt() async throws {
        let (store, directoryURL) = try await DeliveryDispatchFixture.makeStore(
            label: "recovery-retry"
        )
        defer { try? FileManager.default.removeItem(at: directoryURL) }
        var configuration = DeliveryDispatchFixture.backendConfiguration(
            scriptsByTaskID: [
                DeliveryDispatchFixture.taskA: .buildFailure
            ]
        )
        configuration.timestampMode = .wallClock
        let backend = DeterministicFixtureExecutionBackend(
            configuration: configuration
        )
        let clock = DeliveryDispatchTestClock(
            startingAt: Date()
        )
        let dispatcher = DeliveryDispatchFixture.dispatcher(
            store: store,
            backend: backend,
            clock: clock
        )
        let reconciler = DeliveryExecutionReconciler(
            store: store,
            backend: backend,
            now: clock.now
        )

        let failedAttempt = try await advanceUntilFailed(
            store: store,
            dispatcher: dispatcher,
            reconciler: reconciler
        )
        let retry = try await dispatcher.retryTask(
            runID: DeliveryDispatchFixture.runID,
            taskID: DeliveryDispatchFixture.taskA,
            expectedAttemptID: failedAttempt.id
        )
        let run = try #require(retry.snapshot.runs.first)
        let attempts = run.attempts
            .filter { $0.taskID == DeliveryDispatchFixture.taskA }
            .sorted { $0.sequence < $1.sequence }

        #expect(attempts.count == 2)
        #expect(attempts[0].id == failedAttempt.id)
        #expect(attempts[0].status == .failed)
        #expect(attempts[1].sequence == 2)
        #expect(attempts[1].status == .running)
        #expect(attempts[1].idempotencyKey != attempts[0].idempotencyKey)
        #expect(
            attempts[1].externalSession?.sessionID
                != attempts[0].externalSession?.sessionID
        )
        #expect(retry.startedTaskIDs == [DeliveryDispatchFixture.taskA])
        #expect(DeliveryRunValidator.isValid(run))
    }

    @Test("stale retry cannot create a third attempt")
    func staleRetryFailsClosed() async throws {
        let (store, directoryURL) = try await DeliveryDispatchFixture.makeStore(
            label: "recovery-stale"
        )
        defer { try? FileManager.default.removeItem(at: directoryURL) }
        var configuration = DeliveryDispatchFixture.backendConfiguration(
            scriptsByTaskID: [
                DeliveryDispatchFixture.taskA: .buildFailure
            ]
        )
        configuration.timestampMode = .wallClock
        let backend = DeterministicFixtureExecutionBackend(
            configuration: configuration
        )
        let clock = DeliveryDispatchTestClock(
            startingAt: Date()
        )
        let dispatcher = DeliveryDispatchFixture.dispatcher(
            store: store,
            backend: backend,
            clock: clock
        )
        let reconciler = DeliveryExecutionReconciler(
            store: store,
            backend: backend,
            now: clock.now
        )
        let failedAttempt = try await advanceUntilFailed(
            store: store,
            dispatcher: dispatcher,
            reconciler: reconciler
        )
        _ = try await dispatcher.retryTask(
            runID: DeliveryDispatchFixture.runID,
            taskID: DeliveryDispatchFixture.taskA,
            expectedAttemptID: failedAttempt.id
        )

        do {
            _ = try await dispatcher.retryTask(
                runID: DeliveryDispatchFixture.runID,
                taskID: DeliveryDispatchFixture.taskA,
                expectedAttemptID: failedAttempt.id
            )
            Issue.record("Expected stale retry identity to fail")
        } catch let error as DeliveryDispatchError {
            guard case let .retryAttemptMismatch(expected, latest) = error else {
                Issue.record("Unexpected retry error: \(error)")
                return
            }
            #expect(expected == failedAttempt.id)
            #expect(latest != nil)
            #expect(latest != failedAttempt.id)
        }

        let run = try #require(try await store.load()?.runs.first)
        #expect(
            run.attempts.filter {
                $0.taskID == DeliveryDispatchFixture.taskA
            }.count == 2
        )
        #expect(await backend.invocationCount(for: .start) == 3)
    }

    @Test("unknown or danger-full-access permission fails before reservation")
    func unsafePermissionFailsBeforeReservation() async throws {
        for permission in [
            ExecutionPermissionScope.unknown,
            .dangerFullAccess
        ] {
            let (store, directoryURL) =
                try await DeliveryDispatchFixture.makeStore(
                    label: "permission-\(permission.rawValue)"
                )
            defer { try? FileManager.default.removeItem(at: directoryURL) }
            let backend = DeterministicFixtureExecutionBackend(
                configuration: DeliveryDispatchFixture.backendConfiguration(
                    permissionScope: permission
                )
            )
            let clock = DeliveryDispatchTestClock(startingAt: Date())
            let dispatcher = DeliveryDispatchFixture.dispatcher(
                store: store,
                backend: backend,
                clock: clock
            )

            do {
                _ = try await dispatcher.dispatchReadyWave(
                    runID: DeliveryDispatchFixture.runID
                )
                Issue.record("Expected unsafe permission scope to fail")
            } catch let error as DeliveryDispatchError {
                #expect(
                    error == .permissionScopeUnavailable(
                        DeliveryDispatchFixture.projectID,
                        reported: permission
                    )
                )
            }

            #expect(try await store.load()?.runs.first?.attempts.isEmpty == true)
            #expect(await backend.invocationCount(for: .start) == 0)
        }
    }

    @Test("local funnel export contains metrics without delivery content")
    func funnelExportOmitsSensitiveContent() async throws {
        let (store, directoryURL) = try await DeliveryDispatchFixture.makeStore(
            label: "funnel-export"
        )
        defer { try? FileManager.default.removeItem(at: directoryURL) }
        var configuration = DeliveryDispatchFixture.backendConfiguration()
        configuration.timestampMode = .wallClock
        let backend = DeterministicFixtureExecutionBackend(
            configuration: configuration
        )
        let dispatcher = DeliveryDispatcher(
            store: store,
            backend: backend,
            projectID: DeliveryDispatchFixture.projectID
        )
        let reconciler = DeliveryExecutionReconciler(
            store: store,
            backend: backend
        )
        let run = try await advanceToReady(
            store: store,
            dispatcher: dispatcher,
            reconciler: reconciler
        )
        let destinationURL = directoryURL
            .appendingPathComponent("funnel.json")
        let exportedAt = Date()
        let report = try DeliveryFunnelExporter().export(
            run: run,
            to: destinationURL,
            exportedAt: exportedAt
        )
        let data = try Data(contentsOf: destinationURL)
        let raw = try #require(String(data: data, encoding: .utf8))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(
            DeliveryFunnelReport.self,
            from: data
        )

        #expect(decoded.format == report.format)
        #expect(decoded.schemaVersion == report.schemaVersion)
        #expect(
            abs(decoded.exportedAt.timeIntervalSince(report.exportedAt)) < 1
        )
        #expect(decoded.currentState == report.currentState)
        #expect(decoded.taskCount == report.taskCount)
        #expect(decoded.startedSessionCount == report.startedSessionCount)
        #expect(decoded.excludedSensitiveFields == report.excludedSensitiveFields)
        #expect(report.currentState == .readyToMerge)
        #expect(report.taskCount == 3)
        #expect(report.startedSessionCount == 3)
        #expect(report.succeededTaskCount == 3)
        #expect(report.verifiedTaskCount == 3)
        #expect(report.briefToThreeSessionsSeconds != nil)
        #expect(!raw.contains(run.brief.title))
        #expect(!raw.contains(run.brief.body))
        #expect(!raw.contains(run.brief.repository.rootPath))
        #expect(!raw.contains(run.brief.repository.baseBranch))
        #expect(!raw.contains("xcodebuild"))
        #expect(!raw.contains("github.com/example/openmac"))
    }

    private func advanceUntilFailed(
        store: FileDeliveryRunStore,
        dispatcher: DeliveryDispatcher,
        reconciler: DeliveryExecutionReconciler
    ) async throws -> ExecutionAttempt {
        for _ in 0..<40 {
            _ = try await dispatcher.dispatchReadyWave(
                runID: DeliveryDispatchFixture.runID
            )
            let snapshot = try await reconciler.reconcileOnce(
                runID: DeliveryDispatchFixture.runID
            ).snapshot
            let run = try #require(snapshot.runs.first)
            if let attempt = DeliveryDispatchStateReducer
                .latestAttemptsByTaskID(in: run)[
                    DeliveryDispatchFixture.taskA
                ],
               attempt.status == .failed {
                return attempt
            }
        }
        throw ExecutionBackendError.rejected(
            "Fixture did not reach a failed attempt."
        )
    }

    private func advanceToReady(
        store: FileDeliveryRunStore,
        dispatcher: DeliveryDispatcher,
        reconciler: DeliveryExecutionReconciler
    ) async throws -> DeliveryRun {
        var latestRun: DeliveryRun?
        for _ in 0..<64 {
            _ = try await dispatcher.dispatchReadyWave(
                runID: DeliveryDispatchFixture.runID
            )
            let snapshot = try await reconciler.reconcileOnce(
                runID: DeliveryDispatchFixture.runID
            ).snapshot
            let run = try #require(snapshot.runs.first)
            latestRun = run
            if DeliveryDispatchStateReducer.state(for: run) == .readyToMerge {
                return run
            }
        }
        let summary = latestRun.map {
            "state=\(DeliveryDispatchStateReducer.state(for: $0).rawValue), "
                + "attempts=\($0.attempts.map(\.status.rawValue)), "
                + "reconcile=\($0.attempts.compactMap(\.lastReconcileFailureReason)), "
                + "evidence=\($0.evidenceFacts.count), prs=\($0.pullRequests.count)"
        } ?? "missing run"
        throw ExecutionBackendError.rejected(
            "Fixture did not reach Ready to Merge: \(summary)"
        )
    }
}
