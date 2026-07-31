import Foundation

nonisolated struct DeliveryExecutionReconcileReport: Equatable, Sendable {
    let runID: UUID
    let reconciledAttemptIDs: [UUID]
    let importedFactCount: Int
    let failuresByAttemptID: [UUID: String]
    let snapshot: DeliveryRunSnapshot
}

nonisolated struct DeliveryExecutionStopReport: Equatable, Sendable {
    let runID: UUID
    let acknowledgedAttemptIDs: [UUID]
    let alreadyTerminalAttemptIDs: [UUID]
    let failuresByAttemptID: [UUID: String]
    let snapshot: DeliveryRunSnapshot
}

nonisolated enum DeliveryExecutionReconcileError:
    Error,
    Equatable,
    LocalizedError,
    Sendable
{
    case sessionUnavailable(UUID)
    case cursorChanged(attemptID: UUID, expected: String?, current: String?)
    case malformedFactPage(attemptID: UUID, reason: String)
    case timestampPrecedesPersistedState

    nonisolated var errorDescription: String? {
        switch self {
        case let .sessionUnavailable(attemptID):
            return "Attempt \(attemptID.uuidString) has no matching external session."
        case let .cursorChanged(attemptID, _, _):
            return "Attempt \(attemptID.uuidString) advanced while facts were being reconciled."
        case let .malformedFactPage(attemptID, reason):
            return "Attempt \(attemptID.uuidString) returned an invalid fact page: \(reason)"
        case .timestampPrecedesPersistedState:
            return "The fact receipt time precedes persisted delivery state."
        }
    }
}

nonisolated protocol DeliveryExecutionFactPersisting: DeliveryRunStoring {
    func recordExecutionFactPage(
        _ page: ExecutionFactPage,
        runID: UUID,
        attemptID: UUID,
        expectedCursor: ExecutionFactCursor?,
        receivedAt: Date
    ) async throws -> DeliveryRunSnapshot

    func recordExecutionReconcileFailure(
        runID: UUID,
        attemptID: UUID,
        reason: String,
        failedAt: Date
    ) async throws -> DeliveryRunSnapshot

    func recordExecutionStopAcknowledgements(
        runID: UUID,
        attemptIDs: [UUID],
        requestedAt: Date
    ) async throws -> DeliveryRunSnapshot
}

actor DeliveryExecutionReconciler {
    private let store: any DeliveryExecutionFactPersisting
    private let backend: any ExecutionBackend
    private let now: @Sendable () -> Date

    init(
        store: any DeliveryExecutionFactPersisting,
        backend: any ExecutionBackend,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.store = store
        self.backend = backend
        self.now = now
    }

    func reconcileOnce(runID: UUID) async throws -> DeliveryExecutionReconcileReport {
        guard let initialSnapshot = try await store.load(),
              let run = initialSnapshot.runs.first(where: { $0.id == runID }) else {
            throw DeliveryDispatchError.missingRun(runID)
        }
        let attempts = activeAttempts(in: run)
        guard !attempts.isEmpty else {
            return DeliveryExecutionReconcileReport(
                runID: runID,
                reconciledAttemptIDs: [],
                importedFactCount: 0,
                failuresByAttemptID: [:],
                snapshot: initialSnapshot
            )
        }

        var snapshot = initialSnapshot
        var reconciledAttemptIDs: [UUID] = []
        var importedFactCount = 0
        var failures: [UUID: String] = [:]

        for attempt in attempts {
            guard let session = attempt.externalSession else { continue }
            guard session.backendID == backend.backendID else {
                let reason =
                    "The persisted session belongs to a different execution backend."
                failures[attempt.id] = reason
                snapshot = try await store.recordExecutionReconcileFailure(
                    runID: runID,
                    attemptID: attempt.id,
                    reason: reason,
                    failedAt: now()
                )
                continue
            }
            let expectedCursor = attempt.nextFactCursor.map(
                ExecutionFactCursor.init
            )
            do {
                let page = try await backend.facts(
                    for: ExecutionID(session.sessionID),
                    after: expectedCursor
                )
                snapshot = try await store.recordExecutionFactPage(
                    page,
                    runID: runID,
                    attemptID: attempt.id,
                    expectedCursor: expectedCursor,
                    receivedAt: now()
                )
                reconciledAttemptIDs.append(attempt.id)
                importedFactCount += page.facts.count
            } catch {
                let reason = Self.failureDescription(for: error)
                failures[attempt.id] = reason
                snapshot = try await store.recordExecutionReconcileFailure(
                    runID: runID,
                    attemptID: attempt.id,
                    reason: reason,
                    failedAt: now()
                )
            }
        }

        return DeliveryExecutionReconcileReport(
            runID: runID,
            reconciledAttemptIDs: reconciledAttemptIDs,
            importedFactCount: importedFactCount,
            failuresByAttemptID: failures,
            snapshot: snapshot
        )
    }

    func stopActiveExecutions(
        runID: UUID
    ) async throws -> DeliveryExecutionStopReport {
        guard let initialSnapshot = try await store.load(),
              let run = initialSnapshot.runs.first(where: { $0.id == runID }) else {
            throw DeliveryDispatchError.missingRun(runID)
        }
        var failures: [UUID: String] = [:]
        var acknowledgedAttemptIDs: [UUID] = []
        var alreadyTerminalAttemptIDs: [UUID] = []
        for attempt in activeAttempts(in: run) {
            guard let session = attempt.externalSession else { continue }
            guard session.backendID == backend.backendID else {
                failures[attempt.id] =
                    "The persisted session belongs to a different execution backend."
                continue
            }
            do {
                let receipt = try await backend.stop(
                    executionID: ExecutionID(session.sessionID)
                )
                switch receipt.disposition {
                case .accepted, .alreadyStopped:
                    acknowledgedAttemptIDs.append(attempt.id)
                case .alreadyTerminal:
                    alreadyTerminalAttemptIDs.append(attempt.id)
                }
            } catch {
                failures[attempt.id] = Self.failureDescription(for: error)
            }
        }
        let recordedAttemptIDs =
            acknowledgedAttemptIDs + alreadyTerminalAttemptIDs
        let snapshot = try await store.recordExecutionStopAcknowledgements(
            runID: runID,
            attemptIDs: recordedAttemptIDs,
            requestedAt: now()
        )
        return DeliveryExecutionStopReport(
            runID: runID,
            acknowledgedAttemptIDs: acknowledgedAttemptIDs,
            alreadyTerminalAttemptIDs: alreadyTerminalAttemptIDs,
            failuresByAttemptID: failures,
            snapshot: snapshot
        )
    }

    private func activeAttempts(in run: DeliveryRun) -> [ExecutionAttempt] {
        let taskOrder = Dictionary(
            uniqueKeysWithValues: (run.plan?.tasks ?? []).enumerated().map {
                ($0.element.id, $0.offset)
            }
        )
        return run.attempts
            .filter {
                $0.externalSession != nil
                    && !$0.isFactStreamExhausted
                    && isReconciliable($0.status)
            }
            .sorted {
                let leftOrder = taskOrder[$0.taskID] ?? Int.max
                let rightOrder = taskOrder[$1.taskID] ?? Int.max
                if leftOrder != rightOrder {
                    return leftOrder < rightOrder
                }
                return $0.sequence < $1.sequence
            }
    }

    private func isReconciliable(_ status: ExecutionAttemptStatus) -> Bool {
        switch status {
        case .queued, .running, .blocked, .unknown:
            return true
        case .succeeded, .failed, .stopped:
            return false
        }
    }

    nonisolated private static func failureDescription(for error: Error) -> String {
        if let localized = error as? any LocalizedError,
           let description = localized.errorDescription {
            return description
        }
        return String(describing: error)
    }
}
