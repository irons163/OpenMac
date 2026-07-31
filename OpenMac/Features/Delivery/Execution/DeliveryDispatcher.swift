import Foundation

nonisolated struct DeliveryDispatchReservation: Equatable, Sendable {
    let runID: UUID
    let attemptID: UUID
    let request: ExecutionStartRequest
}

nonisolated struct DeliveryDispatchPreparation: Equatable, Sendable {
    let snapshot: DeliveryRunSnapshot
    let reservations: [DeliveryDispatchReservation]
}

nonisolated enum DeliveryDispatchAttemptOutcome: Equatable, Sendable {
    case started(
        attemptID: UUID,
        requestID: UUID,
        receipt: ExecutionStartReceipt,
        recordedAt: Date
    )
    case failed(
        attemptID: UUID,
        requestID: UUID,
        reason: String,
        recordedAt: Date
    )

    nonisolated var attemptID: UUID {
        switch self {
        case let .started(attemptID, _, _, _),
             let .failed(attemptID, _, _, _):
            return attemptID
        }
    }

    nonisolated var requestID: UUID {
        switch self {
        case let .started(_, requestID, _, _),
             let .failed(_, requestID, _, _):
            return requestID
        }
    }

    nonisolated var recordedAt: Date {
        switch self {
        case let .started(_, _, _, recordedAt),
             let .failed(_, _, _, recordedAt):
            return recordedAt
        }
    }
}

nonisolated struct DeliveryDispatchReport: Equatable, Sendable {
    let runID: UUID
    let requestedTaskIDs: [UUID]
    let startedTaskIDs: [UUID]
    let failedTaskIDs: [UUID]
    let snapshot: DeliveryRunSnapshot
}

nonisolated enum DeliveryDispatchError:
    Error,
    Equatable,
    LocalizedError,
    Sendable
{
    case missingRun(UUID)
    case planNotApproved(UUID)
    case runStopped(UUID)
    case invalidRun(runID: UUID, issueCodes: [DeliveryRunValidationIssueCode])
    case missingRepositoryIdentity(UUID)
    case backendIdentifierUnavailable
    case backendNotReady(String?)
    case projectUnavailable(ExecutionProjectID)
    case isolationUnavailable(ExecutionProjectID)
    case permissionScopeUnavailable(
        ExecutionProjectID,
        reported: ExecutionPermissionScope
    )
    case projectRepositoryMismatch(ExecutionProjectID)
    case dispatchTimestampPrecedesPersistedState
    case duplicateOutcome(UUID)
    case missingAttempt(UUID)
    case attemptReservationConflict(UUID)
    case taskUnavailable(UUID)
    case retryAttemptMismatch(expected: UUID, latest: UUID?)
    case attemptNotRetryable(UUID)
    case attemptSequenceExhausted(UUID)
    case dependentTaskAlreadyAttempted(UUID)
    case malformedStartReceipt(UUID)

    nonisolated var errorDescription: String? {
        switch self {
        case let .missingRun(runID):
            return "Delivery run \(runID.uuidString) is unavailable."
        case let .planNotApproved(runID):
            return "Delivery run \(runID.uuidString) must have a valid approval before dispatch."
        case let .runStopped(runID):
            return "Delivery run \(runID.uuidString) has stopped future dispatch."
        case let .invalidRun(runID, issueCodes):
            let codes = issueCodes.map(\.rawValue).joined(separator: ", ")
            return "Delivery run \(runID.uuidString) is invalid for dispatch: \(codes)."
        case let .missingRepositoryIdentity(runID):
            return "Delivery run \(runID.uuidString) has no trusted repository identity."
        case .backendIdentifierUnavailable:
            return "The execution backend did not provide a stable identifier."
        case let .backendNotReady(message):
            return message ?? "The execution backend is not ready."
        case let .projectUnavailable(projectID):
            return "Execution project \(projectID.rawValue) is unavailable."
        case let .isolationUnavailable(projectID):
            return "Execution project \(projectID.rawValue) does not guarantee an isolated workspace."
        case let .permissionScopeUnavailable(projectID, reported):
            return "Execution project \(projectID.rawValue) reported \(reported.rawValue) permissions; OpenMac requires workspace-scoped read/write access."
        case let .projectRepositoryMismatch(projectID):
            return "Execution project \(projectID.rawValue) does not match the approved repository."
        case .dispatchTimestampPrecedesPersistedState:
            return "The dispatch timestamp precedes persisted delivery state."
        case let .duplicateOutcome(attemptID):
            return "Dispatch attempt \(attemptID.uuidString) produced more than one outcome."
        case let .missingAttempt(attemptID):
            return "Dispatch attempt \(attemptID.uuidString) is unavailable."
        case let .attemptReservationConflict(attemptID):
            return "Dispatch attempt \(attemptID.uuidString) no longer matches its persisted reservation."
        case let .taskUnavailable(taskID):
            return "Delivery task \(taskID.uuidString) is unavailable."
        case let .retryAttemptMismatch(expected, latest):
            return "Retry expected attempt \(expected.uuidString), but the latest attempt is \(latest?.uuidString ?? "missing")."
        case let .attemptNotRetryable(attemptID):
            return "Execution attempt \(attemptID.uuidString) is not terminal and retryable."
        case let .attemptSequenceExhausted(taskID):
            return "Delivery task \(taskID.uuidString) exhausted its attempt sequence."
        case let .dependentTaskAlreadyAttempted(taskID):
            return "Delivery task \(taskID.uuidString) cannot be retried after a dependent task has started."
        case let .malformedStartReceipt(attemptID):
            return "The backend returned an invalid start receipt for attempt \(attemptID.uuidString)."
        }
    }
}

nonisolated protocol DeliveryDispatchPersisting: DeliveryRunStoring {
    func prepareReadyDispatch(
        runID: UUID,
        backendID: String,
        projectID: ExecutionProjectID,
        requestedAt: Date
    ) async throws -> DeliveryDispatchPreparation

    func recordDispatchOutcomes(
        _ outcomes: [DeliveryDispatchAttemptOutcome],
        runID: UUID
    ) async throws -> DeliveryRunSnapshot

    func prepareRetryDispatch(
        runID: UUID,
        taskID: UUID,
        expectedAttemptID: UUID,
        backendID: String,
        projectID: ExecutionProjectID,
        requestedAt: Date
    ) async throws -> DeliveryDispatchPreparation

    func stopFutureDispatch(
        runID: UUID,
        stoppedAt: Date
    ) async throws -> DeliveryRunSnapshot
}

actor DeliveryDispatcher {
    private let store: any DeliveryDispatchPersisting
    private let backend: any ExecutionBackend
    private let projectID: ExecutionProjectID
    private let now: @Sendable () -> Date

    init(
        store: any DeliveryDispatchPersisting,
        backend: any ExecutionBackend,
        projectID: ExecutionProjectID,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.store = store
        self.backend = backend
        self.projectID = projectID
        self.now = now
    }

    func dispatchReadyWave(runID: UUID) async throws -> DeliveryDispatchReport {
        let backendID = try await preflight(runID: runID)
        let preparation = try await store.prepareReadyDispatch(
            runID: runID,
            backendID: backendID,
            projectID: projectID,
            requestedAt: now()
        )
        return try await execute(preparation, runID: runID)
    }

    func retryTask(
        runID: UUID,
        taskID: UUID,
        expectedAttemptID: UUID
    ) async throws -> DeliveryDispatchReport {
        let backendID = try await preflight(runID: runID)
        let preparation = try await store.prepareRetryDispatch(
            runID: runID,
            taskID: taskID,
            expectedAttemptID: expectedAttemptID,
            backendID: backendID,
            projectID: projectID,
            requestedAt: now()
        )
        return try await execute(preparation, runID: runID)
    }

    func stopFutureDispatch(runID: UUID) async throws -> DeliveryRunSnapshot {
        try await store.stopFutureDispatch(
            runID: runID,
            stoppedAt: now()
        )
    }

    private func preflight(runID: UUID) async throws -> String {
        let initialSnapshot = try await store.load()
        guard let initialRun = initialSnapshot?.runs.first(where: {
            $0.id == runID
        }) else {
            throw DeliveryDispatchError.missingRun(runID)
        }
        try validateRepositoryIdentity(for: initialRun)

        let backendID = backend.backendID.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !backendID.isEmpty else {
            throw DeliveryDispatchError.backendIdentifierUnavailable
        }
        let health = try await backend.health()
        guard health.state == .ready else {
            throw DeliveryDispatchError.backendNotReady(health.message)
        }
        let projects = try await backend.listProjects()
        guard let project = projects.first(where: { $0.id == projectID }) else {
            throw DeliveryDispatchError.projectUnavailable(projectID)
        }
        guard project.isolation == .isolatedWorkspace else {
            throw DeliveryDispatchError.isolationUnavailable(projectID)
        }
        guard project.permissionScope == .workspaceReadWrite else {
            throw DeliveryDispatchError.permissionScopeUnavailable(
                projectID,
                reported: project.permissionScope
            )
        }
        guard projectMatchesApprovedRepository(project, run: initialRun) else {
            throw DeliveryDispatchError.projectRepositoryMismatch(projectID)
        }
        return backendID
    }

    private func execute(
        _ preparation: DeliveryDispatchPreparation,
        runID: UUID
    ) async throws -> DeliveryDispatchReport {
        guard !preparation.reservations.isEmpty else {
            return DeliveryDispatchReport(
                runID: runID,
                requestedTaskIDs: [],
                startedTaskIDs: [],
                failedTaskIDs: [],
                snapshot: preparation.snapshot
            )
        }

        let outcomes = await withTaskGroup(
            of: DeliveryDispatchAttemptOutcome.self,
            returning: [DeliveryDispatchAttemptOutcome].self
        ) { group in
            for reservation in preparation.reservations {
                group.addTask { [backend, now] in
                    do {
                        let receipt = try await backend.start(reservation.request)
                        guard receipt.requestID == reservation.request.requestID,
                              !receipt.executionID.rawValue.trimmingCharacters(
                                  in: .whitespacesAndNewlines
                              ).isEmpty else {
                            return .failed(
                                attemptID: reservation.attemptID,
                                requestID: reservation.request.requestID,
                                reason: DeliveryDispatchError.malformedStartReceipt(
                                    reservation.attemptID
                                ).localizedDescription,
                                recordedAt: now()
                            )
                        }
                        return .started(
                            attemptID: reservation.attemptID,
                            requestID: reservation.request.requestID,
                            receipt: receipt,
                            recordedAt: now()
                        )
                    } catch {
                        return .failed(
                            attemptID: reservation.attemptID,
                            requestID: reservation.request.requestID,
                            reason: Self.failureDescription(for: error),
                            recordedAt: now()
                        )
                    }
                }
            }

            var collected: [DeliveryDispatchAttemptOutcome] = []
            for await outcome in group {
                collected.append(outcome)
            }
            return collected.sorted {
                $0.attemptID.uuidString < $1.attemptID.uuidString
            }
        }

        let snapshot = try await store.recordDispatchOutcomes(
            outcomes,
            runID: runID
        )
        let taskIDByAttemptID = Dictionary(
            uniqueKeysWithValues: preparation.reservations.map {
                ($0.attemptID, $0.request.taskID)
            }
        )
        let startedTaskIDs = outcomes.compactMap { outcome -> UUID? in
            guard case .started = outcome else { return nil }
            return taskIDByAttemptID[outcome.attemptID]
        }
        let failedTaskIDs = outcomes.compactMap { outcome -> UUID? in
            guard case .failed = outcome else { return nil }
            return taskIDByAttemptID[outcome.attemptID]
        }
        return DeliveryDispatchReport(
            runID: runID,
            requestedTaskIDs: preparation.reservations.map(\.request.taskID),
            startedTaskIDs: startedTaskIDs,
            failedTaskIDs: failedTaskIDs,
            snapshot: snapshot
        )
    }

    private func validateRepositoryIdentity(for run: DeliveryRun) throws {
        guard run.stoppedAt == nil else {
            throw DeliveryDispatchError.runStopped(run.id)
        }
        guard run.plan?.approval != nil else {
            throw DeliveryDispatchError.planNotApproved(run.id)
        }
        let issues = DeliveryRunValidator.validate(run)
        guard issues.isEmpty else {
            throw DeliveryDispatchError.invalidRun(
                runID: run.id,
                issueCodes: issues.map(\.code)
            )
        }
        guard let identity = run.repositoryIdentity else {
            throw DeliveryDispatchError.missingRepositoryIdentity(run.id)
        }
        try DeliveryPlanningRepositoryContext.validateCurrentResolvedIdentity(
            identity,
            baseBranch: run.brief.repository.baseBranch
        )
    }

    private func projectMatchesApprovedRepository(
        _ project: ExecutionProject,
        run: DeliveryRun
    ) -> Bool {
        guard let repositoryURL = project.repositoryURL,
              repositoryURL.isFileURL,
              let identity = run.repositoryIdentity else {
            return false
        }
        let resolvedProjectPath = repositoryURL
            .standardizedFileURL
            .resolvingSymlinksInPath()
            .path
        return resolvedProjectPath == identity.resolvedRepositoryRootPath
    }

    nonisolated private static func failureDescription(for error: Error) -> String {
        let description: String
        if let localized = error as? any LocalizedError,
           let errorDescription = localized.errorDescription {
            description = errorDescription
        } else {
            description = String(describing: error)
        }
        let trimmed = description.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.utf8.count <= 2_048 {
            return trimmed.isEmpty ? "Unknown backend start failure." : trimmed
        }
        return String(trimmed.prefix(2_048))
    }
}
