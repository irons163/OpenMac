import Darwin
import Foundation

nonisolated struct DeliveryRunSnapshot: Equatable, Codable, Sendable {
    nonisolated static let formatIdentifier = "openmac.delivery-store"
    nonisolated static let currentSchemaVersion = 2

    let format: String
    let schemaVersion: Int
    let storeRevision: Int
    let savedAt: Date
    var runs: [DeliveryRun]
    var selectedRunID: UUID?

    nonisolated init(
        format: String = DeliveryRunSnapshot.formatIdentifier,
        schemaVersion: Int = DeliveryRunSnapshot.currentSchemaVersion,
        storeRevision: Int = 0,
        savedAt: Date = Date(),
        runs: [DeliveryRun],
        selectedRunID: UUID? = nil
    ) {
        self.format = format
        self.schemaVersion = schemaVersion
        self.storeRevision = storeRevision
        self.savedAt = savedAt
        self.runs = runs
        self.selectedRunID = selectedRunID
    }
}

nonisolated enum DeliveryRunStoreError: Error, Equatable, LocalizedError, Sendable {
    case unsupportedFormat(found: String, supported: String)
    case unsupportedSchemaVersion(found: Int, supported: Int)
    case revisionConflict(proposed: Int, latest: Int?)
    case revisionExhausted(current: Int)
    case missingSnapshot
    case missingRunID(UUID)
    case duplicateRunID(UUID)
    case danglingSelectedRunID(UUID)
    case invalidRun(runID: UUID, issueCodes: [DeliveryRunValidationIssueCode])
    case snapshotTimestampPrecedesRunState(UUID)
    case approvalMutationRequiresReview(UUID)
    case legacyRepositoryIdentityUnavailable(UUID)
    case legacyApprovedRunRequiresMigration(UUID)

    nonisolated var errorDescription: String? {
        switch self {
        case let .unsupportedFormat(found, supported):
            return "Unsupported delivery snapshot format \(found); this build supports \(supported)."
        case let .unsupportedSchemaVersion(found, supported):
            return "Unsupported delivery snapshot schema version \(found); this build supports version \(supported)."
        case let .revisionConflict(proposed, latest):
            let latestDescription = latest.map(String.init) ?? "none"
            return "Delivery snapshot revision \(proposed) cannot replace latest revision \(latestDescription)."
        case let .revisionExhausted(current):
            return "Delivery snapshot revision \(current) cannot be incremented."
        case .missingSnapshot:
            return "A generated plan draft requires an existing delivery snapshot."
        case let .missingRunID(runID):
            return "Delivery run \(runID.uuidString) is not present in the snapshot."
        case let .duplicateRunID(runID):
            return "Delivery snapshot contains duplicate run ID \(runID.uuidString)."
        case let .danglingSelectedRunID(runID):
            return "Selected delivery run \(runID.uuidString) is not present in the snapshot."
        case let .invalidRun(runID, issueCodes):
            let codes = issueCodes.map(\.rawValue).joined(separator: ", ")
            return "Delivery run \(runID.uuidString) is invalid: \(codes)."
        case let .snapshotTimestampPrecedesRunState(runID):
            return "Delivery snapshot time precedes persisted state for run \(runID.uuidString)."
        case let .approvalMutationRequiresReview(runID):
            return "Approval for delivery run \(runID.uuidString) can change only through atomic plan review."
        case let .legacyRepositoryIdentityUnavailable(runID):
            return "Legacy delivery run \(runID.uuidString) cannot migrate until its clean repository and selected base branch are available."
        case let .legacyApprovedRunRequiresMigration(runID):
            return "Legacy approval for delivery run \(runID.uuidString) has delivery facts or is stopped and cannot be migrated automatically."
        }
    }
}

nonisolated protocol DeliveryRunStoring: Sendable {
    func load() async throws -> DeliveryRunSnapshot?
    func save(_ snapshot: DeliveryRunSnapshot) async throws
}

nonisolated struct FileDeliveryRunStore: DeliveryRunStoring, Sendable {
    let fileURL: URL
    private let reviewNow: @Sendable () -> Date
    nonisolated private static let coordinator = DeliveryRunFileCoordinator()

    nonisolated init(
        fileURL: URL = FileDeliveryRunStore.defaultFileURL,
        reviewNow: @escaping @Sendable () -> Date = Date.init
    ) {
        self.fileURL = fileURL
        self.reviewNow = reviewNow
    }

    nonisolated static var defaultFileURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return appSupport
            .appendingPathComponent("OpenMac", isDirectory: true)
            .appendingPathComponent("v2", isDirectory: true)
            .appendingPathComponent("delivery-store.json")
    }

    nonisolated func load() async throws -> DeliveryRunSnapshot? {
        try await Self.coordinator.load(from: fileURL)
    }

    nonisolated func save(_ snapshot: DeliveryRunSnapshot) async throws {
        try await Self.coordinator.save(snapshot, to: fileURL)
    }

    nonisolated func applyGeneratedPlanDraft(
        _ result: DeliveryPlanGenerationResult,
        toRunID runID: UUID,
        request: DeliveryPlanGenerationRequest,
        appliedAt: Date = Date()
    ) async throws -> DeliveryRunSnapshot {
        try await Self.coordinator.applyGeneratedPlanDraft(
            result,
            toRunID: runID,
            request: request,
            appliedAt: appliedAt,
            fileURL: fileURL
        )
    }

    nonisolated func createGeneratedFixtureReviewRun(
        _ result: DeliveryPlanGenerationResult,
        request: DeliveryPlanGenerationRequest,
        expectedStoreRevision: Int?
    ) async throws -> DeliveryRunSnapshot {
        try await Self.coordinator.createGeneratedFixtureReviewRun(
            result,
            request: request,
            expectedStoreRevision: expectedStoreRevision,
            createdAt: reviewNow(),
            fileURL: fileURL
        )
    }

    nonisolated func saveReviewedPlanDraft(
        _ proposedPlan: DeliveryPlan,
        toRunID runID: UUID,
        expectedStoreRevision: Int,
        expectedPlanRevision: Int
    ) async throws -> DeliveryRunSnapshot {
        try await Self.coordinator.saveReviewedPlanDraft(
            proposedPlan,
            toRunID: runID,
            expectedStoreRevision: expectedStoreRevision,
            expectedPlanRevision: expectedPlanRevision,
            savedAt: reviewNow(),
            fileURL: fileURL
        )
    }

    nonisolated func approveReviewedPlan(
        _ proposedPlan: DeliveryPlan,
        inRunID runID: UUID,
        expectedStoreRevision: Int,
        expectedPlanRevision: Int,
        approvedBy: String
    ) async throws -> DeliveryRunSnapshot {
        try await Self.coordinator.approveReviewedPlan(
            proposedPlan,
            inRunID: runID,
            expectedStoreRevision: expectedStoreRevision,
            expectedPlanRevision: expectedPlanRevision,
            approvedBy: approvedBy,
            approvedAt: reviewNow(),
            fileURL: fileURL
        )
    }

    nonisolated func prepareReadyDispatch(
        runID: UUID,
        backendID: String,
        projectID: ExecutionProjectID,
        requestedAt: Date
    ) async throws -> DeliveryDispatchPreparation {
        try await Self.coordinator.prepareReadyDispatch(
            runID: runID,
            backendID: backendID,
            projectID: projectID,
            requestedAt: requestedAt,
            fileURL: fileURL
        )
    }

    nonisolated func recordDispatchOutcomes(
        _ outcomes: [DeliveryDispatchAttemptOutcome],
        runID: UUID
    ) async throws -> DeliveryRunSnapshot {
        try await Self.coordinator.recordDispatchOutcomes(
            outcomes,
            runID: runID,
            fileURL: fileURL
        )
    }

    nonisolated func recordExecutionFactPage(
        _ page: ExecutionFactPage,
        runID: UUID,
        attemptID: UUID,
        expectedCursor: ExecutionFactCursor?,
        receivedAt: Date
    ) async throws -> DeliveryRunSnapshot {
        try await Self.coordinator.recordExecutionFactPage(
            page,
            runID: runID,
            attemptID: attemptID,
            expectedCursor: expectedCursor,
            receivedAt: receivedAt,
            fileURL: fileURL
        )
    }

    nonisolated func stopFutureDispatch(
        runID: UUID,
        stoppedAt: Date
    ) async throws -> DeliveryRunSnapshot {
        try await Self.coordinator.stopFutureDispatch(
            runID: runID,
            stoppedAt: stoppedAt,
            fileURL: fileURL
        )
    }
}

extension FileDeliveryRunStore: DeliveryPlanReviewPersisting {}
extension FileDeliveryRunStore: DeliveryDispatchPersisting {}
extension FileDeliveryRunStore: DeliveryExecutionFactPersisting {}

private actor DeliveryRunFileCoordinator {
    func load(from fileURL: URL) throws -> DeliveryRunSnapshot? {
        let fileLock = try DeliveryRunInterprocessLock(fileURL: fileURL)
        defer { fileLock.unlock() }
        return try DeliveryRunSnapshotFileCodec.load(from: fileURL)
    }

    func save(_ snapshot: DeliveryRunSnapshot, to fileURL: URL) throws {
        let fileLock = try DeliveryRunInterprocessLock(fileURL: fileURL)
        defer { fileLock.unlock() }
        let latest = try DeliveryRunSnapshotFileCodec.load(from: fileURL)
        let latestRevision = latest?.storeRevision

        if latestRevision == Int.max {
            throw DeliveryRunStoreError.revisionExhausted(current: Int.max)
        }

        let expectedRevision = latestRevision.map { $0 + 1 } ?? 0
        guard snapshot.storeRevision == expectedRevision else {
            throw DeliveryRunStoreError.revisionConflict(
                proposed: snapshot.storeRevision,
                latest: latestRevision
            )
        }
        if let latest {
            guard snapshot.savedAt >= latest.savedAt else {
                throw DeliveryPlanReviewError.reviewTimestampPrecedesPersistedState
            }
        }

        try validateApprovalTransition(from: latest, to: snapshot)
        try DeliveryRunSnapshotFileCodec.write(snapshot, to: fileURL)
    }

    func applyGeneratedPlanDraft(
        _ result: DeliveryPlanGenerationResult,
        toRunID runID: UUID,
        request: DeliveryPlanGenerationRequest,
        appliedAt: Date,
        fileURL: URL
    ) throws -> DeliveryRunSnapshot {
        let fileLock = try DeliveryRunInterprocessLock(fileURL: fileURL)
        defer { fileLock.unlock() }
        try Task.checkCancellation()
        guard let latest = try DeliveryRunSnapshotFileCodec.load(from: fileURL) else {
            throw DeliveryRunStoreError.missingSnapshot
        }
        guard latest.storeRevision < Int.max else {
            throw DeliveryRunStoreError.revisionExhausted(current: latest.storeRevision)
        }
        guard let runIndex = latest.runs.firstIndex(where: { $0.id == runID }) else {
            throw DeliveryRunStoreError.missingRunID(runID)
        }
        guard appliedAt >= latest.savedAt else {
            throw DeliveryPlanReviewError.reviewTimestampPrecedesPersistedState
        }
        guard result.requestID == request.requestID else {
            throw DeliveryPlanDraftApplicationError.inactiveRequest(
                expected: request.requestID,
                received: result.requestID
            )
        }
        guard result.plan.id == request.planID,
              result.inputFingerprint == request.inputFingerprint,
              result.repositoryIdentity == request.repositoryIdentity else {
            throw DeliveryPlanDraftApplicationError.staleInput
        }

        var runs = latest.runs
        runs[runIndex] = try DeliveryPlanDraftApplicator.applying(
            result,
            to: runs[runIndex],
            repositoryContext: request.repositoryContext,
            activeRequestID: request.requestID,
            currentStoreRevision: latest.storeRevision,
            appliedAt: appliedAt
        )
        let updated = DeliveryRunSnapshot(
            format: latest.format,
            schemaVersion: latest.schemaVersion,
            storeRevision: latest.storeRevision + 1,
            savedAt: appliedAt,
            runs: runs,
            selectedRunID: latest.selectedRunID
        )
        try Task.checkCancellation()
        try DeliveryRunSnapshotFileCodec.write(updated, to: fileURL)
        return updated
    }

    func saveReviewedPlanDraft(
        _ proposedPlan: DeliveryPlan,
        toRunID runID: UUID,
        expectedStoreRevision: Int,
        expectedPlanRevision: Int,
        savedAt: Date,
        fileURL: URL
    ) throws -> DeliveryRunSnapshot {
        let fileLock = try DeliveryRunInterprocessLock(fileURL: fileURL)
        defer { fileLock.unlock() }
        try Task.checkCancellation()
        let latest = try loadReviewSnapshot(
            from: fileURL,
            expectedStoreRevision: expectedStoreRevision
        )
        guard let runIndex = latest.runs.firstIndex(where: { $0.id == runID }) else {
            throw DeliveryRunStoreError.missingRunID(runID)
        }

        var runs = latest.runs
        runs[runIndex] = try DeliveryPlanReviewApplicator.savingDraft(
            proposedPlan,
            to: runs[runIndex],
            expectedPlanRevision: expectedPlanRevision,
            savedAt: savedAt
        )
        return try writeReviewSnapshot(
            replacing: latest,
            runs: runs,
            savedAt: savedAt,
            fileURL: fileURL
        )
    }

    func approveReviewedPlan(
        _ proposedPlan: DeliveryPlan,
        inRunID runID: UUID,
        expectedStoreRevision: Int,
        expectedPlanRevision: Int,
        approvedBy: String,
        approvedAt: Date,
        fileURL: URL
    ) throws -> DeliveryRunSnapshot {
        let fileLock = try DeliveryRunInterprocessLock(fileURL: fileURL)
        defer { fileLock.unlock() }
        try Task.checkCancellation()
        let latest = try loadReviewSnapshot(
            from: fileURL,
            expectedStoreRevision: expectedStoreRevision
        )
        guard let runIndex = latest.runs.firstIndex(where: { $0.id == runID }) else {
            throw DeliveryRunStoreError.missingRunID(runID)
        }

        var runs = latest.runs
        guard let repositoryIdentity = runs[runIndex].repositoryIdentity else {
            throw DeliveryPlanReviewError.missingRepositoryIdentity
        }
        try DeliveryPlanningRepositoryContext.validateCurrentResolvedIdentity(
            repositoryIdentity,
            baseBranch: runs[runIndex].brief.repository.baseBranch
        )
        runs[runIndex] = try DeliveryPlanReviewApplicator.approving(
            proposedPlan,
            in: runs[runIndex],
            expectedPlanRevision: expectedPlanRevision,
            approvedBy: approvedBy,
            approvedAt: approvedAt
        )
        return try writeReviewSnapshot(
            replacing: latest,
            runs: runs,
            savedAt: approvedAt,
            fileURL: fileURL
        )
    }

    func prepareReadyDispatch(
        runID: UUID,
        backendID: String,
        projectID: ExecutionProjectID,
        requestedAt: Date,
        fileURL: URL
    ) throws -> DeliveryDispatchPreparation {
        let fileLock = try DeliveryRunInterprocessLock(fileURL: fileURL)
        defer { fileLock.unlock() }
        try Task.checkCancellation()
        guard let latest = try DeliveryRunSnapshotFileCodec.load(from: fileURL) else {
            throw DeliveryRunStoreError.missingSnapshot
        }
        guard latest.storeRevision < Int.max else {
            throw DeliveryRunStoreError.revisionExhausted(
                current: latest.storeRevision
            )
        }
        guard requestedAt >= latest.savedAt else {
            throw DeliveryDispatchError.dispatchTimestampPrecedesPersistedState
        }
        guard let runIndex = latest.runs.firstIndex(where: { $0.id == runID }) else {
            throw DeliveryDispatchError.missingRun(runID)
        }

        let trimmedBackendID = backendID.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        let trimmedProjectID = projectID.rawValue.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !trimmedBackendID.isEmpty, !trimmedProjectID.isEmpty else {
            throw DeliveryDispatchError.backendIdentifierUnavailable
        }

        var run = latest.runs[runIndex]
        guard run.stoppedAt == nil else {
            throw DeliveryDispatchError.runStopped(runID)
        }
        guard let plan = run.plan,
              let approval = plan.approval else {
            throw DeliveryDispatchError.planNotApproved(runID)
        }
        let validationIssues = DeliveryRunValidator.validate(run)
        guard validationIssues.isEmpty else {
            throw DeliveryDispatchError.invalidRun(
                runID: runID,
                issueCodes: validationIssues.map(\.code)
            )
        }
        guard let repositoryIdentity = run.repositoryIdentity else {
            throw DeliveryDispatchError.missingRepositoryIdentity(runID)
        }
        try DeliveryPlanningRepositoryContext.validateCurrentResolvedIdentity(
            repositoryIdentity,
            baseBranch: run.brief.repository.baseBranch
        )

        let resumableAttempts = run.attempts.filter {
            $0.externalSession == nil
                && ($0.status == .queued || $0.status == .unknown)
        }
        if !resumableAttempts.isEmpty {
            let reservations = try resumableAttempts.map { attempt in
                guard attempt.backendID == trimmedBackendID,
                      attempt.projectID == trimmedProjectID,
                      let task = plan.tasks.first(where: {
                          $0.id == attempt.taskID
                      }) else {
                    throw DeliveryDispatchError.attemptReservationConflict(
                        attempt.id
                    )
                }
                return DeliveryDispatchReservation(
                    runID: runID,
                    attemptID: attempt.id,
                    request: makeStartRequest(
                        run: run,
                        plan: plan,
                        approval: approval,
                        repositoryIdentity: repositoryIdentity,
                        task: task,
                        attempt: attempt,
                        projectID: projectID
                    )
                )
            }
            return DeliveryDispatchPreparation(
                snapshot: latest,
                reservations: reservations.sorted {
                    taskOrder(
                        $0.request.taskID,
                        in: plan
                    ) < taskOrder(
                        $1.request.taskID,
                        in: plan
                    )
                }
            )
        }

        let readyTaskIDs = DeliveryDispatchStateReducer.readyTaskIDs(in: run)
        guard !readyTaskIDs.isEmpty else {
            return DeliveryDispatchPreparation(
                snapshot: latest,
                reservations: []
            )
        }

        var reservations: [DeliveryDispatchReservation] = []
        for taskID in readyTaskIDs {
            guard let task = plan.tasks.first(where: { $0.id == taskID }) else {
                continue
            }
            let sequence = run.attempts
                .filter { $0.taskID == taskID }
                .map(\.sequence)
                .max()
                .map { $0 + 1 } ?? 1
            let attempt = ExecutionAttempt(
                taskID: taskID,
                planID: plan.id,
                planRevision: plan.revision,
                sequence: sequence,
                backendID: trimmedBackendID,
                projectID: trimmedProjectID,
                status: .queued,
                createdAt: requestedAt,
                dispatchRequestedAt: requestedAt
            )
            run.attempts.append(attempt)
            reservations.append(
                DeliveryDispatchReservation(
                    runID: runID,
                    attemptID: attempt.id,
                    request: makeStartRequest(
                        run: run,
                        plan: plan,
                        approval: approval,
                        repositoryIdentity: repositoryIdentity,
                        task: task,
                        attempt: attempt,
                        projectID: projectID
                    )
                )
            )
        }
        run.updatedAt = requestedAt

        var runs = latest.runs
        runs[runIndex] = run
        let updated = DeliveryRunSnapshot(
            format: latest.format,
            schemaVersion: latest.schemaVersion,
            storeRevision: latest.storeRevision + 1,
            savedAt: requestedAt,
            runs: runs,
            selectedRunID: latest.selectedRunID
        )
        try Task.checkCancellation()
        try DeliveryRunSnapshotFileCodec.write(updated, to: fileURL)
        return DeliveryDispatchPreparation(
            snapshot: updated,
            reservations: reservations
        )
    }

    func recordDispatchOutcomes(
        _ outcomes: [DeliveryDispatchAttemptOutcome],
        runID: UUID,
        fileURL: URL
    ) throws -> DeliveryRunSnapshot {
        let fileLock = try DeliveryRunInterprocessLock(fileURL: fileURL)
        defer { fileLock.unlock() }
        try Task.checkCancellation()
        guard let latest = try DeliveryRunSnapshotFileCodec.load(from: fileURL) else {
            throw DeliveryRunStoreError.missingSnapshot
        }
        guard latest.storeRevision < Int.max else {
            throw DeliveryRunStoreError.revisionExhausted(
                current: latest.storeRevision
            )
        }
        guard let runIndex = latest.runs.firstIndex(where: { $0.id == runID }) else {
            throw DeliveryDispatchError.missingRun(runID)
        }
        guard !outcomes.isEmpty else {
            return latest
        }

        var seenAttemptIDs: Set<UUID> = []
        for outcome in outcomes
        where !seenAttemptIDs.insert(outcome.attemptID).inserted {
            throw DeliveryDispatchError.duplicateOutcome(outcome.attemptID)
        }

        var run = latest.runs[runIndex]
        var changed = false
        var latestOutcomeAt = latest.savedAt
        for outcome in outcomes {
            guard let attemptIndex = run.attempts.firstIndex(where: {
                $0.id == outcome.attemptID
            }) else {
                throw DeliveryDispatchError.missingAttempt(outcome.attemptID)
            }
            var attempt = run.attempts[attemptIndex]
            guard attempt.idempotencyKey == outcome.requestID else {
                throw DeliveryDispatchError.attemptReservationConflict(
                    attempt.id
                )
            }
            guard outcome.recordedAt >= attempt.createdAt,
                  outcome.recordedAt >= (attempt.dispatchRequestedAt
                      ?? attempt.createdAt) else {
                throw DeliveryDispatchError
                    .dispatchTimestampPrecedesPersistedState
            }
            latestOutcomeAt = max(latestOutcomeAt, outcome.recordedAt)

            switch outcome {
            case let .started(_, _, receipt, recordedAt):
                guard receipt.requestID == attempt.idempotencyKey,
                      !receipt.executionID.rawValue.trimmingCharacters(
                          in: .whitespacesAndNewlines
                      ).isEmpty,
                      let projectID = attempt.projectID else {
                    throw DeliveryDispatchError.malformedStartReceipt(
                        attempt.id
                    )
                }
                let session = ExternalSessionRef(
                    backendID: attempt.backendID,
                    projectID: projectID,
                    sessionID: receipt.executionID.rawValue
                )
                if let existingSession = attempt.externalSession {
                    guard existingSession == session else {
                        throw DeliveryDispatchError.attemptReservationConflict(
                            attempt.id
                        )
                    }
                    continue
                }
                attempt.externalSession = session
                attempt.status = .running
                attempt.dispatchFailureReason = nil
                attempt.startedAt = recordedAt
                changed = true
            case let .failed(_, _, reason, _):
                guard attempt.externalSession == nil else {
                    continue
                }
                let normalizedReason = normalizedDispatchFailure(reason)
                if attempt.dispatchFailureReason != normalizedReason
                    || attempt.status != .queued {
                    attempt.status = .queued
                    attempt.dispatchFailureReason = normalizedReason
                    changed = true
                }
            }
            run.attempts[attemptIndex] = attempt
        }

        guard changed else {
            return latest
        }
        run.updatedAt = max(run.updatedAt, latestOutcomeAt)
        var runs = latest.runs
        runs[runIndex] = run
        let updated = DeliveryRunSnapshot(
            format: latest.format,
            schemaVersion: latest.schemaVersion,
            storeRevision: latest.storeRevision + 1,
            savedAt: latestOutcomeAt,
            runs: runs,
            selectedRunID: latest.selectedRunID
        )
        try Task.checkCancellation()
        try DeliveryRunSnapshotFileCodec.write(updated, to: fileURL)
        return updated
    }

    func recordExecutionFactPage(
        _ page: ExecutionFactPage,
        runID: UUID,
        attemptID: UUID,
        expectedCursor: ExecutionFactCursor?,
        receivedAt: Date,
        fileURL: URL
    ) throws -> DeliveryRunSnapshot {
        let fileLock = try DeliveryRunInterprocessLock(fileURL: fileURL)
        defer { fileLock.unlock() }
        try Task.checkCancellation()
        guard let latest = try DeliveryRunSnapshotFileCodec.load(from: fileURL) else {
            throw DeliveryRunStoreError.missingSnapshot
        }
        guard latest.storeRevision < Int.max else {
            throw DeliveryRunStoreError.revisionExhausted(
                current: latest.storeRevision
            )
        }
        guard receivedAt >= latest.savedAt else {
            throw DeliveryExecutionReconcileError
                .timestampPrecedesPersistedState
        }
        guard let runIndex = latest.runs.firstIndex(where: { $0.id == runID }) else {
            throw DeliveryDispatchError.missingRun(runID)
        }

        var runs = latest.runs
        runs[runIndex] = try DeliveryExecutionFactReducer.applying(
            page,
            to: runs[runIndex],
            attemptID: attemptID,
            expectedCursor: expectedCursor,
            receivedAt: receivedAt
        )
        let updated = DeliveryRunSnapshot(
            format: latest.format,
            schemaVersion: latest.schemaVersion,
            storeRevision: latest.storeRevision + 1,
            savedAt: receivedAt,
            runs: runs,
            selectedRunID: latest.selectedRunID
        )
        try Task.checkCancellation()
        try DeliveryRunSnapshotFileCodec.write(updated, to: fileURL)
        return updated
    }

    func stopFutureDispatch(
        runID: UUID,
        stoppedAt: Date,
        fileURL: URL
    ) throws -> DeliveryRunSnapshot {
        let fileLock = try DeliveryRunInterprocessLock(fileURL: fileURL)
        defer { fileLock.unlock() }
        try Task.checkCancellation()
        guard let latest = try DeliveryRunSnapshotFileCodec.load(from: fileURL) else {
            throw DeliveryRunStoreError.missingSnapshot
        }
        guard latest.storeRevision < Int.max else {
            throw DeliveryRunStoreError.revisionExhausted(
                current: latest.storeRevision
            )
        }
        guard let runIndex = latest.runs.firstIndex(where: { $0.id == runID }) else {
            throw DeliveryDispatchError.missingRun(runID)
        }
        if latest.runs[runIndex].stoppedAt != nil {
            return latest
        }
        guard stoppedAt >= latest.savedAt else {
            throw DeliveryDispatchError.dispatchTimestampPrecedesPersistedState
        }

        var runs = latest.runs
        runs[runIndex].stoppedAt = stoppedAt
        runs[runIndex].updatedAt = stoppedAt
        let updated = DeliveryRunSnapshot(
            format: latest.format,
            schemaVersion: latest.schemaVersion,
            storeRevision: latest.storeRevision + 1,
            savedAt: stoppedAt,
            runs: runs,
            selectedRunID: latest.selectedRunID
        )
        try Task.checkCancellation()
        try DeliveryRunSnapshotFileCodec.write(updated, to: fileURL)
        return updated
    }

    private func makeStartRequest(
        run: DeliveryRun,
        plan: DeliveryPlan,
        approval: DeliveryPlanApproval,
        repositoryIdentity: DeliveryRepositoryIdentitySnapshot,
        task: DeliveryTask,
        attempt: ExecutionAttempt,
        projectID: ExecutionProjectID
    ) -> ExecutionStartRequest {
        ExecutionStartRequest(
            requestID: attempt.idempotencyKey,
            projectID: projectID,
            deliveryRunID: run.id,
            taskID: task.id,
            planID: plan.id,
            planRevision: plan.revision,
            approvalFingerprint: approval.scopeFingerprint,
            title: task.title,
            instructions: task.workerPrompt,
            baseBranch: run.brief.repository.baseBranch,
            baseCommitIdentifier: repositoryIdentity.baseCommitIdentifier
        )
    }

    private func taskOrder(_ taskID: UUID, in plan: DeliveryPlan) -> Int {
        plan.tasks.firstIndex(where: { $0.id == taskID }) ?? Int.max
    }

    private func normalizedDispatchFailure(_ reason: String) -> String {
        let trimmed = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return "Unknown backend start failure."
        }
        return String(trimmed.prefix(2_048))
    }

    private func loadReviewSnapshot(
        from fileURL: URL,
        expectedStoreRevision: Int
    ) throws -> DeliveryRunSnapshot {
        guard let latest = try DeliveryRunSnapshotFileCodec.load(from: fileURL) else {
            throw DeliveryRunStoreError.missingSnapshot
        }
        guard latest.storeRevision == expectedStoreRevision else {
            throw DeliveryPlanReviewError.storeRevisionChanged(
                expected: expectedStoreRevision,
                current: latest.storeRevision
            )
        }
        guard latest.storeRevision < Int.max else {
            throw DeliveryRunStoreError.revisionExhausted(current: latest.storeRevision)
        }
        return latest
    }

    private func writeReviewSnapshot(
        replacing latest: DeliveryRunSnapshot,
        runs: [DeliveryRun],
        savedAt: Date,
        fileURL: URL
    ) throws -> DeliveryRunSnapshot {
        guard savedAt >= latest.savedAt else {
            throw DeliveryPlanReviewError.reviewTimestampPrecedesPersistedState
        }
        let updated = DeliveryRunSnapshot(
            format: latest.format,
            schemaVersion: latest.schemaVersion,
            storeRevision: latest.storeRevision + 1,
            savedAt: savedAt,
            runs: runs,
            selectedRunID: latest.selectedRunID
        )
        try Task.checkCancellation()
        try DeliveryRunSnapshotFileCodec.write(updated, to: fileURL)
        return updated
    }

    func createGeneratedFixtureReviewRun(
        _ result: DeliveryPlanGenerationResult,
        request: DeliveryPlanGenerationRequest,
        expectedStoreRevision: Int?,
        createdAt: Date,
        fileURL: URL
    ) throws -> DeliveryRunSnapshot {
        let fileLock = try DeliveryRunInterprocessLock(fileURL: fileURL)
        defer { fileLock.unlock() }
        try Task.checkCancellation()
        let latest = try DeliveryRunSnapshotFileCodec.load(from: fileURL)
        guard latest?.storeRevision == expectedStoreRevision else {
            throw DeliveryFixtureReviewBootstrapError.storeRevisionChanged(
                expected: expectedStoreRevision,
                current: latest?.storeRevision
            )
        }
        if let latest {
            guard latest.storeRevision < Int.max else {
                throw DeliveryRunStoreError.revisionExhausted(
                    current: latest.storeRevision
                )
            }
            guard createdAt >= latest.savedAt else {
                throw DeliveryPlanReviewError.reviewTimestampPrecedesPersistedState
            }
        }
        guard result.requestID == request.requestID else {
            throw DeliveryPlanDraftApplicationError.inactiveRequest(
                expected: request.requestID,
                received: result.requestID
            )
        }
        guard result.plan.id == request.planID,
              result.inputFingerprint == request.inputFingerprint,
              result.repositoryIdentity == request.repositoryIdentity else {
            throw DeliveryPlanDraftApplicationError.staleInput
        }

        let currentRevision = latest?.storeRevision ?? 0
        let initialRun = DeliveryRun(
            brief: request.brief,
            createdAt: request.brief.createdAt,
            updatedAt: request.brief.createdAt
        )
        let generatedRun = try DeliveryPlanDraftApplicator.applying(
            result,
            to: initialRun,
            repositoryContext: request.repositoryContext,
            activeRequestID: request.requestID,
            currentStoreRevision: currentRevision,
            appliedAt: createdAt
        )
        var runs = latest?.runs ?? []
        runs.append(generatedRun)
        let updated = DeliveryRunSnapshot(
            format: latest?.format ?? DeliveryRunSnapshot.formatIdentifier,
            schemaVersion: latest?.schemaVersion
                ?? DeliveryRunSnapshot.currentSchemaVersion,
            storeRevision: latest.map { $0.storeRevision + 1 } ?? 0,
            savedAt: createdAt,
            runs: runs,
            selectedRunID: generatedRun.id
        )
        try Task.checkCancellation()
        try DeliveryRunSnapshotFileCodec.write(updated, to: fileURL)
        return updated
    }

    private func validateApprovalTransition(
        from latest: DeliveryRunSnapshot?,
        to proposed: DeliveryRunSnapshot
    ) throws {
        var latestRunsByID: [UUID: DeliveryRun] = [:]
        for run in latest?.runs ?? [] where latestRunsByID[run.id] == nil {
            latestRunsByID[run.id] = run
        }
        var proposedRunsByID: [UUID: DeliveryRun] = [:]
        for run in proposed.runs where proposedRunsByID[run.id] == nil {
            proposedRunsByID[run.id] = run
        }
        let runIDs = Set(latestRunsByID.keys).union(proposedRunsByID.keys)

        for runID in runIDs {
            let latestApproval = latestRunsByID[runID]?.plan?.approval
            let proposedApproval = proposedRunsByID[runID]?.plan?.approval
            guard latestApproval == proposedApproval else {
                throw DeliveryRunStoreError.approvalMutationRequiresReview(runID)
            }
        }
    }
}

nonisolated private final class DeliveryRunInterprocessLock {
    private var descriptor: Int32

    nonisolated init(fileURL: URL) throws {
        let directoryURL = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        let lockURL = fileURL.appendingPathExtension("lock")
        let openedDescriptor = lockURL.path.withCString {
            Darwin.open($0, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        }
        guard openedDescriptor >= 0 else {
            throw NSError(
                domain: NSPOSIXErrorDomain,
                code: Int(errno),
                userInfo: [NSFilePathErrorKey: lockURL.path]
            )
        }
        descriptor = openedDescriptor
        guard flock(descriptor, LOCK_EX) == 0 else {
            let code = errno
            Darwin.close(descriptor)
            descriptor = -1
            throw NSError(
                domain: NSPOSIXErrorDomain,
                code: Int(code),
                userInfo: [NSFilePathErrorKey: lockURL.path]
            )
        }
    }

    nonisolated func unlock() {
        guard descriptor >= 0 else { return }
        _ = flock(descriptor, LOCK_UN)
        _ = Darwin.close(descriptor)
        descriptor = -1
    }

    deinit {
        unlock()
    }
}

nonisolated private enum DeliveryRunSnapshotFileCodec {
    nonisolated static func load(from fileURL: URL) throws -> DeliveryRunSnapshot? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return nil
        }

        let data = try Data(contentsOf: fileURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let decoded = try decoder.decode(DeliveryRunSnapshot.self, from: data)
        var snapshot = try migrateIfNeeded(decoded)
        if snapshot.schemaVersion != decoded.schemaVersion {
            guard snapshot.storeRevision < Int.max else {
                throw DeliveryRunStoreError.revisionExhausted(
                    current: snapshot.storeRevision
                )
            }
            snapshot = DeliveryRunSnapshot(
                format: snapshot.format,
                schemaVersion: snapshot.schemaVersion,
                storeRevision: snapshot.storeRevision + 1,
                savedAt: snapshot.savedAt,
                runs: snapshot.runs,
                selectedRunID: snapshot.selectedRunID
            )
            try write(snapshot, to: fileURL)
        }
        try validate(snapshot)
        return snapshot
    }

    nonisolated static func write(
        _ snapshot: DeliveryRunSnapshot,
        to fileURL: URL
    ) throws {
        try validate(snapshot)

        let directoryURL = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .secondsSince1970
        let data = try encoder.encode(snapshot)
        try data.write(to: fileURL, options: .atomic)
    }

    nonisolated private static func validate(_ snapshot: DeliveryRunSnapshot) throws {
        guard snapshot.format == DeliveryRunSnapshot.formatIdentifier else {
            throw DeliveryRunStoreError.unsupportedFormat(
                found: snapshot.format,
                supported: DeliveryRunSnapshot.formatIdentifier
            )
        }
        guard snapshot.schemaVersion == DeliveryRunSnapshot.currentSchemaVersion else {
            throw DeliveryRunStoreError.unsupportedSchemaVersion(
                found: snapshot.schemaVersion,
                supported: DeliveryRunSnapshot.currentSchemaVersion
            )
        }

        var runIDs: Set<UUID> = []
        for run in snapshot.runs {
            guard runIDs.insert(run.id).inserted else {
                throw DeliveryRunStoreError.duplicateRunID(run.id)
            }

            let issueCodes = DeliveryRunValidator.validate(run).map(\.code)
            guard issueCodes.isEmpty else {
                throw DeliveryRunStoreError.invalidRun(
                    runID: run.id,
                    issueCodes: issueCodes
                )
            }
            var runStateDates = [
                run.updatedAt,
                run.plan?.updatedAt,
                run.stoppedAt
            ].compactMap { $0 }
            for attempt in run.attempts {
                runStateDates.append(attempt.createdAt)
                runStateDates.append(
                    contentsOf: [
                        attempt.dispatchRequestedAt,
                        attempt.startedAt,
                        attempt.endedAt,
                        attempt.stopRequestedAt
                    ].compactMap { $0 }
                )
            }
            for observation in run.executionObservations {
                runStateDates.append(observation.occurredAt)
                runStateDates.append(observation.receivedAt)
            }
            for fact in run.evidenceFacts {
                runStateDates.append(fact.observedAt)
                runStateDates.append(fact.receivedAt)
            }
            let latestRunState = runStateDates.max() ?? run.createdAt
            guard snapshot.savedAt >= latestRunState else {
                throw DeliveryRunStoreError.snapshotTimestampPrecedesRunState(
                    run.id
                )
            }
        }

        if let selectedRunID = snapshot.selectedRunID,
           !runIDs.contains(selectedRunID) {
            throw DeliveryRunStoreError.danglingSelectedRunID(selectedRunID)
        }
    }

    nonisolated private static func migrateIfNeeded(
        _ snapshot: DeliveryRunSnapshot
    ) throws -> DeliveryRunSnapshot {
        guard snapshot.schemaVersion == 1 else {
            return snapshot
        }
        guard snapshot.format == DeliveryRunSnapshot.formatIdentifier else {
            throw DeliveryRunStoreError.unsupportedFormat(
                found: snapshot.format,
                supported: DeliveryRunSnapshot.formatIdentifier
            )
        }

        var runs = snapshot.runs
        for index in runs.indices {
            let originalIdentity = runs[index].repositoryIdentity
            let identityWasIncomplete = originalIdentity == nil || originalIdentity.map {
                $0.repositoryFileIdentity
                    .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || $0.containerFileIdentity
                        .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || $0.gitCommonDirectoryPath
                        .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || $0.gitCommonDirectoryFileIdentity
                        .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || $0.baseCommitIdentifier
                        .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            } == true

            if identityWasIncomplete {
                guard let refreshedIdentity = refreshedLegacyIdentity(
                    for: runs[index],
                    originalIdentity: originalIdentity
                ) else {
                    throw DeliveryRunStoreError
                        .legacyRepositoryIdentityUnavailable(runs[index].id)
                }
                runs[index].repositoryIdentity = refreshedIdentity
            }

            guard let approval = runs[index].plan?.approval else {
                continue
            }
            let isLegacyApproval = approval.scopeFingerprint
                .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || identityWasIncomplete
            guard isLegacyApproval else {
                continue
            }
            guard runs[index].attempts.isEmpty,
                  runs[index].executionObservations.isEmpty,
                  runs[index].evidenceFacts.isEmpty,
                  runs[index].pullRequests.isEmpty,
                  runs[index].stoppedAt == nil else {
                throw DeliveryRunStoreError.legacyApprovedRunRequiresMigration(
                    runs[index].id
                )
            }
            runs[index].plan?.approval = nil
        }

        return DeliveryRunSnapshot(
            format: snapshot.format,
            schemaVersion: DeliveryRunSnapshot.currentSchemaVersion,
            storeRevision: snapshot.storeRevision,
            savedAt: snapshot.savedAt,
            runs: runs,
            selectedRunID: snapshot.selectedRunID
        )
    }

    nonisolated private static func refreshedLegacyIdentity(
        for run: DeliveryRun,
        originalIdentity: DeliveryRepositoryIdentitySnapshot?
    ) -> DeliveryRepositoryIdentitySnapshot? {
        let relativePath = originalIdentity?.containerRelativePath
            ?? run.brief.repository.xcodeContainerRelativePath
        guard let relativePath,
              let containerKind = originalIdentity?.containerKind
                ?? inferredContainerKind(from: relativePath) else {
            return nil
        }
        let repositoryRootPath = originalIdentity?.repositoryRootPath
            ?? run.brief.repository.rootPath
        guard let context = try? DeliveryPlanningRepositoryContext.resolving(
            repositoryRootPath: repositoryRootPath,
            containerKind: containerKind,
            containerRelativePath: relativePath,
            targetNames: [],
            schemeNames: []
        ) else {
            return nil
        }
        return try? context.identitySnapshot(
            validatingBaseBranch: run.brief.repository.baseBranch
        )
    }

    nonisolated private static func inferredContainerKind(
        from relativePath: String
    ) -> DeliveryContainerKind? {
        let lowercased = relativePath.lowercased()
        if lowercased.hasSuffix(".xcodeproj") {
            return .xcodeProject
        }
        if lowercased.hasSuffix(".xcworkspace") {
            return .xcodeWorkspace
        }
        if (relativePath as NSString).lastPathComponent.lowercased()
            == "package.swift" {
            return .swiftPackage
        }
        return nil
    }
}
