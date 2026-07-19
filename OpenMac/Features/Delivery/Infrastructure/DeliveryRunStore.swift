import Foundation

nonisolated struct DeliveryRunSnapshot: Equatable, Codable, Sendable {
    nonisolated static let formatIdentifier = "openmac.delivery-store"
    nonisolated static let currentSchemaVersion = 1

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
        }
    }
}

nonisolated protocol DeliveryRunStoring: Sendable {
    func load() async throws -> DeliveryRunSnapshot?
    func save(_ snapshot: DeliveryRunSnapshot) async throws
}

nonisolated struct FileDeliveryRunStore: DeliveryRunStoring, Sendable {
    let fileURL: URL
    nonisolated private static let coordinator = DeliveryRunFileCoordinator()

    nonisolated init(fileURL: URL = FileDeliveryRunStore.defaultFileURL) {
        self.fileURL = fileURL
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
        repositoryContext: DeliveryPlanningRepositoryContext,
        activeRequestID: UUID,
        appliedAt: Date = Date()
    ) async throws -> DeliveryRunSnapshot {
        try await Self.coordinator.applyGeneratedPlanDraft(
            result,
            toRunID: runID,
            repositoryContext: repositoryContext,
            activeRequestID: activeRequestID,
            appliedAt: appliedAt,
            fileURL: fileURL
        )
    }
}

private actor DeliveryRunFileCoordinator {
    func load(from fileURL: URL) throws -> DeliveryRunSnapshot? {
        try DeliveryRunSnapshotFileCodec.load(from: fileURL)
    }

    func save(_ snapshot: DeliveryRunSnapshot, to fileURL: URL) throws {
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

        try DeliveryRunSnapshotFileCodec.write(snapshot, to: fileURL)
    }

    func applyGeneratedPlanDraft(
        _ result: DeliveryPlanGenerationResult,
        toRunID runID: UUID,
        repositoryContext: DeliveryPlanningRepositoryContext,
        activeRequestID: UUID,
        appliedAt: Date,
        fileURL: URL
    ) throws -> DeliveryRunSnapshot {
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

        var runs = latest.runs
        runs[runIndex] = try DeliveryPlanDraftApplicator.applying(
            result,
            to: runs[runIndex],
            repositoryContext: repositoryContext,
            activeRequestID: activeRequestID,
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
}

nonisolated private enum DeliveryRunSnapshotFileCodec {
    nonisolated static func load(from fileURL: URL) throws -> DeliveryRunSnapshot? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return nil
        }

        let data = try Data(contentsOf: fileURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let snapshot = try decoder.decode(DeliveryRunSnapshot.self, from: data)
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
        }

        if let selectedRunID = snapshot.selectedRunID,
           !runIDs.contains(selectedRunID) {
            throw DeliveryRunStoreError.danglingSelectedRunID(selectedRunID)
        }
    }
}
