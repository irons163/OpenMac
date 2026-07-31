import Foundation

nonisolated struct DeliveryXcodeVerificationReport: Equatable, Sendable {
    let runID: UUID
    let taskID: UUID
    let attemptID: UUID
    let requirementIDs: [UUID]
    let record: XcodeVerificationRecord
    let snapshot: DeliveryRunSnapshot
}

nonisolated enum DeliveryXcodeVerificationError:
    Error,
    Equatable,
    LocalizedError,
    Sendable
{
    case missingRun(UUID)
    case missingTask(UUID)
    case missingSucceededAttempt(UUID)
    case missingRequirement(taskID: UUID, kind: XcodeVerificationKind)
    case missingWorkspace(UUID)
    case missingBranch(UUID)
    case ambiguousScheme(UUID)
    case invalidRecord(String)

    nonisolated var errorDescription: String? {
        switch self {
        case let .missingRun(runID):
            return "Delivery run \(runID.uuidString) is unavailable for Xcode verification."
        case let .missingTask(taskID):
            return "Delivery task \(taskID.uuidString) is unavailable for Xcode verification."
        case let .missingSucceededAttempt(taskID):
            return "Delivery task \(taskID.uuidString) has no succeeded attempt to verify."
        case let .missingRequirement(taskID, kind):
            return "Delivery task \(taskID.uuidString) has no \(kind.rawValue) requirement."
        case let .missingWorkspace(attemptID):
            return "Attempt \(attemptID.uuidString) has no backend-confirmed verification workspace."
        case let .missingBranch(attemptID):
            return "Attempt \(attemptID.uuidString) has no backend-confirmed branch."
        case let .ambiguousScheme(taskID):
            return "Delivery task \(taskID.uuidString) must identify exactly one Xcode scheme before verification."
        case let .invalidRecord(reason):
            return "The Xcode verification record is invalid: \(reason)"
        }
    }
}

nonisolated protocol DeliveryXcodeVerificationPersisting:
    DeliveryRunStoring
{
    func recordXcodeVerification(
        _ record: XcodeVerificationRecord,
        runID: UUID,
        attemptID: UUID,
        requirementIDs: [UUID],
        receivedAt: Date
    ) async throws -> DeliveryRunSnapshot
}

actor DeliveryXcodeVerificationCoordinator {
    private let store: any DeliveryXcodeVerificationPersisting
    private let verifier: XcodeVerifier
    private let now: @Sendable () -> Date

    init(
        store: any DeliveryXcodeVerificationPersisting,
        verifier: XcodeVerifier,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.store = store
        self.verifier = verifier
        self.now = now
    }

    func verify(
        runID: UUID,
        taskID: UUID,
        kind: XcodeVerificationKind
    ) async throws -> DeliveryXcodeVerificationReport {
        guard let snapshot = try await store.load(),
              let run = snapshot.runs.first(where: { $0.id == runID }) else {
            throw DeliveryXcodeVerificationError.missingRun(runID)
        }
        guard let identity = run.repositoryIdentity,
              let task = run.plan?.tasks.first(where: { $0.id == taskID }) else {
            throw DeliveryXcodeVerificationError.missingTask(taskID)
        }
        let attempt = DeliveryDispatchStateReducer
            .latestAttemptsByTaskID(in: run)[taskID]
        guard let attempt, attempt.status == .succeeded else {
            throw DeliveryXcodeVerificationError
                .missingSucceededAttempt(taskID)
        }
        let requirementIDs = task.evidenceRequirements
            .filter { $0.kind == kind.evidenceKind }
            .map(\.id)
        guard !requirementIDs.isEmpty else {
            throw DeliveryXcodeVerificationError.missingRequirement(
                taskID: taskID,
                kind: kind
            )
        }
        guard let workspacePath = attempt.externalSession?
            .verificationWorkspacePath,
            !workspacePath.trimmingCharacters(
                in: .whitespacesAndNewlines
            ).isEmpty else {
            throw DeliveryXcodeVerificationError.missingWorkspace(attempt.id)
        }
        guard let branch = attempt.externalSession?.branch?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !branch.isEmpty else {
            throw DeliveryXcodeVerificationError.missingBranch(attempt.id)
        }
        let schemes = Array(
            Set(
                task.schemeHints
                    .map {
                        $0.trimmingCharacters(
                            in: .whitespacesAndNewlines
                        )
                    }
                    .filter { !$0.isEmpty }
            )
        ).sorted()
        guard schemes.count == 1, let scheme = schemes.first else {
            throw DeliveryXcodeVerificationError.ambiguousScheme(task.id)
        }

        let record = try await verifier.verify(
            XcodeVerificationRequest(
                kind: kind,
                scheme: scheme,
                workspaceURL: URL(
                    fileURLWithPath: workspacePath,
                    isDirectory: true
                ),
                expectedGitCommonDirectoryURL: URL(
                    fileURLWithPath: identity.gitCommonDirectoryPath,
                    isDirectory: true
                ),
                expectedBranch: branch,
                containerKind: identity.containerKind,
                containerRelativePath: identity.containerRelativePath
            )
        )
        let receivedAt = max(now(), record.endedAt)
        let updated = try await store.recordXcodeVerification(
            record,
            runID: runID,
            attemptID: attempt.id,
            requirementIDs: requirementIDs,
            receivedAt: receivedAt
        )
        return DeliveryXcodeVerificationReport(
            runID: runID,
            taskID: taskID,
            attemptID: attempt.id,
            requirementIDs: requirementIDs,
            record: record,
            snapshot: updated
        )
    }
}
