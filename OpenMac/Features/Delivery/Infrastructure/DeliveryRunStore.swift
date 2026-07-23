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
}

extension FileDeliveryRunStore: DeliveryPlanReviewPersisting {}

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
