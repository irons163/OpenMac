import Foundation
import Testing
@testable import OpenMac

private enum DeliveryFoundationFixture {
    static let date = Date(timeIntervalSince1970: 1_784_371_200)
    static let runID = UUID(uuidString: "10000000-0000-0000-0000-000000000001")!
    static let planID = UUID(uuidString: "20000000-0000-0000-0000-000000000001")!
    static let firstTaskID = UUID(uuidString: "30000000-0000-0000-0000-000000000001")!
    static let secondTaskID = UUID(uuidString: "30000000-0000-0000-0000-000000000002")!
    static let thirdTaskID = UUID(uuidString: "30000000-0000-0000-0000-000000000003")!
    static let firstCriterionID = UUID(uuidString: "40000000-0000-0000-0000-000000000001")!
    static let secondCriterionID = UUID(uuidString: "40000000-0000-0000-0000-000000000002")!
    static let thirdCriterionID = UUID(uuidString: "40000000-0000-0000-0000-000000000003")!
    static let firstRequirementID = UUID(uuidString: "50000000-0000-0000-0000-000000000001")!
    static let secondRequirementID = UUID(uuidString: "50000000-0000-0000-0000-000000000002")!
    static let thirdRequirementID = UUID(uuidString: "50000000-0000-0000-0000-000000000003")!
    static let firstAttemptID = UUID(uuidString: "60000000-0000-0000-0000-000000000001")!
    static let requestID = UUID(uuidString: "70000000-0000-0000-0000-000000000001")!

    static func task(
        id: UUID,
        title: String,
        criterionID: UUID,
        criterion: String = "The requested behavior is observable.",
        requirementID: UUID,
        evidence: String = "The Xcode test suite passes."
    ) -> DeliveryTask {
        DeliveryTask(
            id: id,
            title: title,
            workerPrompt: "Implement \(title) without changing unrelated files.",
            acceptanceCriteria: [
                AcceptanceCriterion(id: criterionID, statement: criterion)
            ],
            riskLevel: .medium,
            evidenceRequirements: [
                EvidenceRequirement(
                    id: requirementID,
                    kind: .xcodeTest,
                    description: evidence,
                    coveredCriterionIDs: [criterionID]
                )
            ],
            targetHints: ["OpenMac"],
            schemeHints: ["OpenMac"]
        )
    }

    static func validPlan(approved: Bool = false) -> DeliveryPlan {
        let first = task(
            id: firstTaskID,
            title: "Build delivery domain",
            criterionID: firstCriterionID,
            requirementID: firstRequirementID
        )
        let second = task(
            id: secondTaskID,
            title: "Verify delivery domain",
            criterionID: secondCriterionID,
            requirementID: secondRequirementID
        )
        let third = task(
            id: thirdTaskID,
            title: "Persist delivery domain",
            criterionID: thirdCriterionID,
            requirementID: thirdRequirementID
        )
        var plan = DeliveryPlan(
            id: planID,
            revision: 1,
            tasks: [first, second, third],
            dependencyEdges: [
                DependencyEdge(
                    prerequisiteTaskID: firstTaskID,
                    dependentTaskID: secondTaskID
                ),
                DependencyEdge(
                    prerequisiteTaskID: secondTaskID,
                    dependentTaskID: thirdTaskID
                )
            ],
            createdAt: date,
            updatedAt: date
        )
        if approved {
            let fingerprint = DeliveryPlanFingerprint.make(for: plan) ?? ""
            let scopeFingerprint = DeliveryApprovalScopeFingerprint.make(
                runID: runID,
                runCreatedAt: date,
                brief: brief(),
                repositoryIdentity: repositoryIdentity(),
                planFingerprint: fingerprint,
                approvedAt: date,
                approvedBy: "fixture-user"
            ) ?? ""
            plan.approval = DeliveryPlanApproval(
                planID: plan.id,
                planRevision: plan.revision,
                planFingerprint: fingerprint,
                scopeFingerprint: scopeFingerprint,
                approvedAt: date,
                approvedBy: "fixture-user"
            )
        }
        return plan
    }

    static func brief() -> FeatureBrief {
        FeatureBrief(
            id: UUID(uuidString: "80000000-0000-0000-0000-000000000001")!,
            title: "Delivery foundation",
            body: "Create the isolated v2 delivery domain.",
            repository: DeliveryRepositoryReference(
                rootPath: "/fixture/OpenMac",
                baseBranch: "main",
                xcodeContainerRelativePath: "OpenMac.xcodeproj"
            ),
            createdAt: date
        )
    }

    static func repositoryIdentity() -> DeliveryRepositoryIdentitySnapshot {
        DeliveryRepositoryIdentitySnapshot(
            repositoryRootPath: "/fixture/OpenMac",
            resolvedRepositoryRootPath: "/fixture/OpenMac",
            repositoryFileIdentity: "fixture-device:fixture-repository",
            containerKind: .xcodeProject,
            containerRelativePath: "OpenMac.xcodeproj",
            resolvedContainerPath: "/fixture/OpenMac/OpenMac.xcodeproj",
            containerFileIdentity: "fixture-device:fixture-container",
            gitCommonDirectoryPath: "/fixture/OpenMac/.git",
            gitCommonDirectoryFileIdentity: "fixture-device:fixture-git",
            baseCommitIdentifier: String(repeating: "a", count: 40)
        )
    }

    static func attempt(
        id: UUID = firstAttemptID,
        taskID: UUID = firstTaskID,
        sequence: Int = 1,
        status: ExecutionAttemptStatus = .running,
        session: ExternalSessionRef? = ExternalSessionRef(
            backendID: "fixture",
            projectID: "fixture-project",
            sessionID: "fixture-session-1"
        )
    ) -> ExecutionAttempt {
        ExecutionAttempt(
            id: id,
            taskID: taskID,
            planID: planID,
            planRevision: 1,
            sequence: sequence,
            backendID: "fixture",
            idempotencyKey: requestID,
            status: status,
            externalSession: session,
            createdAt: date,
            dispatchRequestedAt: date,
            startedAt: date
        )
    }

    static func startRequest(
        requestID: UUID = requestID,
        projectID: ExecutionProjectID = ExecutionProjectID("fixture-project"),
        taskID: UUID = firstTaskID,
        title: String = "Build delivery domain"
    ) -> ExecutionStartRequest {
        ExecutionStartRequest(
            requestID: requestID,
            projectID: projectID,
            deliveryRunID: runID,
            taskID: taskID,
            planID: planID,
            planRevision: 1,
            approvalFingerprint: "fixture-plan-sha256",
            title: title,
            instructions: "Implement the approved task and return facts.",
            baseBranch: "main"
        )
    }
}

private nonisolated enum DeliveryStoreSaveOutcome: Equatable, Sendable {
    case saved
    case revisionConflict
    case unexpected(String)
}

private nonisolated func saveOutcome(
    _ snapshot: DeliveryRunSnapshot,
    using store: FileDeliveryRunStore
) async -> DeliveryStoreSaveOutcome {
    do {
        try await store.save(snapshot)
        return .saved
    } catch let error as DeliveryRunStoreError {
        if case .revisionConflict = error {
            return .revisionConflict
        }
        return .unexpected(String(describing: error))
    } catch {
        return .unexpected(String(describing: error))
    }
}

@Suite("Delivery v2 foundation")
struct DeliveryFoundationTests {
    @Test("valid typed dependency plan passes validation")
    func validPlanPassesValidation() {
        let issues = DeliveryPlanValidator.validate(
            DeliveryFoundationFixture.validPlan()
        )

        #expect(issues.isEmpty)
    }

    @Test("plan revisions start at one")
    func invalidPlanRevisionIsRejected() {
        var plan = DeliveryFoundationFixture.validPlan()
        plan.revision = 0

        let codes = DeliveryPlanValidator.validate(plan).map(\.code)

        #expect(codes.contains(.invalidRevision))
    }

    @Test("dependency edge referencing a missing task is rejected")
    func missingDependencyTaskIsRejected() {
        var plan = DeliveryFoundationFixture.validPlan()
        plan.dependencyEdges.append(
            DependencyEdge(
                prerequisiteTaskID: DeliveryFoundationFixture.firstTaskID,
                dependentTaskID: UUID()
            )
        )

        let codes = DeliveryPlanValidator.validate(plan).map(\.code)

        #expect(codes.contains(.missingDependencyTask))
    }

    @Test("dependency cycles are rejected")
    func dependencyCycleIsRejected() {
        var plan = DeliveryFoundationFixture.validPlan()
        plan.dependencyEdges.append(
            DependencyEdge(
                prerequisiteTaskID: DeliveryFoundationFixture.secondTaskID,
                dependentTaskID: DeliveryFoundationFixture.firstTaskID
            )
        )

        let codes = DeliveryPlanValidator.validate(plan).map(\.code)

        #expect(codes.contains(.cyclicDependency))
    }

    @Test("duplicate dependency edges are rejected")
    func duplicateDependencyIsRejected() {
        var plan = DeliveryFoundationFixture.validPlan()
        plan.dependencyEdges.append(plan.dependencyEdges[0])

        let codes = DeliveryPlanValidator.validate(plan).map(\.code)

        #expect(codes.contains(.duplicateDependency))
    }

    @Test("blank acceptance and missing evidence are rejected")
    func blankAcceptanceAndMissingEvidenceAreRejected() {
        var plan = DeliveryFoundationFixture.validPlan()
        plan.tasks[0].acceptanceCriteria[0].statement = "  \n "
        plan.tasks[0].evidenceRequirements = []

        let codes = DeliveryPlanValidator.validate(plan).map(\.code)

        #expect(codes.contains(.emptyAcceptanceCriterion))
        #expect(codes.contains(.emptyEvidenceRequirement))
    }

    @Test("evidence must cover criteria from the same task")
    func evidenceCoverageIsValidated() {
        var plan = DeliveryFoundationFixture.validPlan()
        plan.tasks[0].evidenceRequirements[0].coveredCriterionIDs = [UUID()]

        let codes = DeliveryPlanValidator.validate(plan).map(\.code)

        #expect(codes.contains(.unknownAcceptanceCriterionReference))
        #expect(codes.contains(.uncoveredAcceptanceCriterion))
    }

    @Test("approval for a different plan revision is stale")
    func staleApprovalIsRejected() {
        var plan = DeliveryFoundationFixture.validPlan(approved: true)
        plan.revision = 2

        let codes = DeliveryPlanValidator.validate(plan).map(\.code)

        #expect(codes.contains(.staleApproval))
    }

    @Test("approval fingerprint rejects changed plan content")
    func changedApprovedContentIsRejected() {
        var plan = DeliveryFoundationFixture.validPlan(approved: true)
        #expect(DeliveryPlanValidator.isValid(plan))

        plan.tasks[0].workerPrompt = "Execute instructions that were never approved."

        let codes = DeliveryPlanValidator.validate(plan).map(\.code)
        #expect(codes.contains(.staleApproval))
    }

    @Test("run rejects attempts before plan approval")
    func runRejectsAttemptWithoutApproval() {
        let run = DeliveryRun(
            id: DeliveryFoundationFixture.runID,
            brief: DeliveryFoundationFixture.brief(),
            plan: DeliveryFoundationFixture.validPlan(),
            attempts: [DeliveryFoundationFixture.attempt()],
            createdAt: DeliveryFoundationFixture.date,
            updatedAt: DeliveryFoundationFixture.date
        )

        let codes = DeliveryRunValidator.validate(run).map(\.code)

        #expect(codes.contains(.attemptWithoutApproval))
    }

    @Test("run rejects duplicate active attempts and session ownership")
    func runRejectsDuplicateActiveAttemptsAndSession() {
        let secondAttempt = DeliveryFoundationFixture.attempt(
            id: UUID(uuidString: "60000000-0000-0000-0000-000000000002")!,
            sequence: 2
        )
        let run = DeliveryRun(
            id: DeliveryFoundationFixture.runID,
            brief: DeliveryFoundationFixture.brief(),
            repositoryIdentity: DeliveryFoundationFixture.repositoryIdentity(),
            plan: DeliveryFoundationFixture.validPlan(approved: true),
            attempts: [DeliveryFoundationFixture.attempt(), secondAttempt],
            createdAt: DeliveryFoundationFixture.date,
            updatedAt: DeliveryFoundationFixture.date
        )

        let codes = DeliveryRunValidator.validate(run).map(\.code)

        #expect(codes.contains(.multipleActiveAttempts))
        #expect(codes.contains(.reusedExternalSession))
        #expect(codes.contains(.duplicateAttemptIdempotencyKey))
    }

    @Test("evidence supersession rejects cycles")
    func evidenceSupersessionRejectsCycles() {
        let firstFactID = UUID(uuidString: "91000000-0000-0000-0000-000000000001")!
        let secondFactID = UUID(uuidString: "91000000-0000-0000-0000-000000000002")!
        let attempt = DeliveryFoundationFixture.attempt(status: .succeeded)
        let first = EvidenceFact(
            id: firstFactID,
            taskID: DeliveryFoundationFixture.firstTaskID,
            attemptID: attempt.id,
            requirementID: DeliveryFoundationFixture.firstRequirementID,
            result: .failed,
            source: .xcodeVerifier,
            summary: "First observation",
            observedAt: DeliveryFoundationFixture.date,
            receivedAt: DeliveryFoundationFixture.date,
            supersedesFactID: secondFactID
        )
        let second = EvidenceFact(
            id: secondFactID,
            taskID: DeliveryFoundationFixture.firstTaskID,
            attemptID: attempt.id,
            requirementID: DeliveryFoundationFixture.firstRequirementID,
            result: .passed,
            source: .xcodeVerifier,
            summary: "Second observation",
            observedAt: DeliveryFoundationFixture.date,
            receivedAt: DeliveryFoundationFixture.date,
            supersedesFactID: firstFactID
        )
        let run = DeliveryRun(
            id: DeliveryFoundationFixture.runID,
            brief: DeliveryFoundationFixture.brief(),
            repositoryIdentity: DeliveryFoundationFixture.repositoryIdentity(),
            plan: DeliveryFoundationFixture.validPlan(approved: true),
            attempts: [attempt],
            evidenceFacts: [first, second],
            createdAt: DeliveryFoundationFixture.date,
            updatedAt: DeliveryFoundationFixture.date
        )

        let codes = DeliveryRunValidator.validate(run).map(\.code)
        #expect(codes.contains(.cyclicEvidenceSupersession))
    }

    @Test("attempt and evidence chronology is fail closed")
    func runRejectsInvalidFactChronology() {
        let later = DeliveryFoundationFixture.date.addingTimeInterval(30)
        let attempt = DeliveryFoundationFixture.attempt(
            status: .succeeded
        )
        var invalidAttempt = attempt
        invalidAttempt.dispatchRequestedAt = later
        invalidAttempt.startedAt = DeliveryFoundationFixture.date
            .addingTimeInterval(10)
        let fact = EvidenceFact(
            taskID: DeliveryFoundationFixture.firstTaskID,
            attemptID: invalidAttempt.id,
            requirementID: DeliveryFoundationFixture.firstRequirementID,
            result: .passed,
            source: .xcodeVerifier,
            summary: "Out-of-order observation",
            observedAt: later,
            receivedAt: DeliveryFoundationFixture.date.addingTimeInterval(20)
        )
        let run = DeliveryRun(
            id: DeliveryFoundationFixture.runID,
            brief: DeliveryFoundationFixture.brief(),
            repositoryIdentity: DeliveryFoundationFixture.repositoryIdentity(),
            plan: DeliveryFoundationFixture.validPlan(approved: true),
            attempts: [invalidAttempt],
            evidenceFacts: [fact],
            createdAt: DeliveryFoundationFixture.date,
            updatedAt: later
        )

        let codes = DeliveryRunValidator.validate(run).map(\.code)
        #expect(codes.contains(.invalidAttemptChronology))
        #expect(codes.contains(.invalidEvidenceChronology))
    }

    @Test("snapshot time cannot precede persisted attempt facts")
    func fileStoreRejectsSnapshotOlderThanAttempt() async throws {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "openmac-delivery-future-attempt-\(UUID().uuidString)",
                isDirectory: true
            )
        defer { try? FileManager.default.removeItem(at: directoryURL) }
        let eventTime = DeliveryFoundationFixture.date.addingTimeInterval(10)
        var attempt = DeliveryFoundationFixture.attempt(status: .running)
        attempt.dispatchRequestedAt = eventTime
        attempt.startedAt = eventTime
        let run = DeliveryRun(
            id: DeliveryFoundationFixture.runID,
            brief: DeliveryFoundationFixture.brief(),
            repositoryIdentity: DeliveryFoundationFixture.repositoryIdentity(),
            plan: DeliveryFoundationFixture.validPlan(approved: true),
            attempts: [attempt],
            createdAt: DeliveryFoundationFixture.date,
            updatedAt: eventTime
        )
        let store = FileDeliveryRunStore(
            fileURL: directoryURL.appendingPathComponent("delivery-store.json")
        )
        let snapshot = DeliveryRunSnapshot(
            storeRevision: 0,
            savedAt: DeliveryFoundationFixture.date,
            runs: [run],
            selectedRunID: run.id
        )
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        try encoder.encode(snapshot).write(
            to: store.fileURL,
            options: .atomic
        )

        do {
            _ = try await store.load()
            Issue.record("Expected snapshot time to cover attempt facts")
        } catch let error as DeliveryRunStoreError {
            #expect(error == .snapshotTimestampPrecedesRunState(run.id))
        }
    }

    @Test("delivery snapshot encodes and decodes without derived status")
    func snapshotRoundTripDoesNotPersistDerivedStatus() throws {
        let attempt = DeliveryFoundationFixture.attempt(status: .succeeded)
        let fact = EvidenceFact(
            id: UUID(uuidString: "90000000-0000-0000-0000-000000000001")!,
            taskID: DeliveryFoundationFixture.firstTaskID,
            attemptID: attempt.id,
            requirementID: DeliveryFoundationFixture.firstRequirementID,
            result: .passed,
            source: .xcodeVerifier,
            summary: "Tests passed",
            sourceReference: "xcodebuild test",
            observedAt: DeliveryFoundationFixture.date,
            receivedAt: DeliveryFoundationFixture.date,
            rawObservationID: "fixture-observation-1"
        )
        let run = DeliveryRun(
            id: DeliveryFoundationFixture.runID,
            brief: DeliveryFoundationFixture.brief(),
            repositoryIdentity: DeliveryFoundationFixture.repositoryIdentity(),
            plan: DeliveryFoundationFixture.validPlan(approved: true),
            attempts: [attempt],
            evidenceFacts: [fact],
            createdAt: DeliveryFoundationFixture.date,
            updatedAt: DeliveryFoundationFixture.date
        )
        let snapshot = DeliveryRunSnapshot(
            storeRevision: 3,
            savedAt: DeliveryFoundationFixture.date,
            runs: [run],
            selectedRunID: run.id
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        let data = try encoder.encode(snapshot)
        let encoded = String(decoding: data, as: UTF8.self)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970

        let decoded = try decoder.decode(DeliveryRunSnapshot.self, from: data)

        #expect(decoded == snapshot)
        #expect(!encoded.contains("derivedState"))
        #expect(!encoded.contains("KanbanStatus"))
    }

    @Test("file delivery store round trips its versioned envelope")
    func fileStoreRoundTrip() async throws {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("openmac-delivery-store-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directoryURL) }
        let fileURL = directoryURL.appendingPathComponent("delivery-store.json")
        let snapshot = DeliveryRunSnapshot(
            storeRevision: 0,
            savedAt: DeliveryFoundationFixture.date,
            runs: [
                DeliveryRun(
                    id: DeliveryFoundationFixture.runID,
                    brief: DeliveryFoundationFixture.brief(),
                    plan: DeliveryFoundationFixture.validPlan(),
                    createdAt: DeliveryFoundationFixture.date,
                    updatedAt: DeliveryFoundationFixture.date
                )
            ],
            selectedRunID: DeliveryFoundationFixture.runID
        )
        let store = FileDeliveryRunStore(fileURL: fileURL)

        try await store.save(snapshot)
        let loaded = try await store.load()

        #expect(loaded == snapshot)
        #expect(FileDeliveryRunStore.defaultFileURL.path.hasSuffix("OpenMac/v2/delivery-store.json"))
        #expect(!FileDeliveryRunStore.defaultFileURL.path.hasSuffix("kanban-board.json"))
    }

    @Test("file delivery store returns nil for a missing snapshot")
    func fileStoreReturnsNilWhenMissing() async throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("missing-delivery-store.json")
        let store = FileDeliveryRunStore(fileURL: fileURL)

        #expect(try await store.load() == nil)
    }

    @Test("file delivery store refuses a future schema")
    func fileStoreRejectsFutureSchema() async throws {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("openmac-delivery-schema-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directoryURL) }
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let fileURL = directoryURL.appendingPathComponent("delivery-store.json")
        let futureSnapshot = DeliveryRunSnapshot(
            schemaVersion: DeliveryRunSnapshot.currentSchemaVersion + 1,
            savedAt: DeliveryFoundationFixture.date,
            runs: []
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        try encoder.encode(futureSnapshot).write(to: fileURL, options: .atomic)
        let store = FileDeliveryRunStore(fileURL: fileURL)

        do {
            _ = try await store.load()
            Issue.record("Expected the future schema to be rejected")
        } catch let error as DeliveryRunStoreError {
            #expect(
                error == .unsupportedSchemaVersion(
                    found: DeliveryRunSnapshot.currentSchemaVersion + 1,
                    supported: DeliveryRunSnapshot.currentSchemaVersion
                )
            )
        }
    }

    @Test("file delivery store serializes concurrent compare-and-swap saves")
    func fileStoreRejectsConcurrentLostUpdate() async throws {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("openmac-delivery-cas-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directoryURL) }
        let fileURL = directoryURL.appendingPathComponent("delivery-store.json")
        let firstStore = FileDeliveryRunStore(fileURL: fileURL)
        let secondStore = FileDeliveryRunStore(fileURL: fileURL)
        let firstSnapshot = DeliveryRunSnapshot(
            storeRevision: 0,
            savedAt: DeliveryFoundationFixture.date,
            runs: []
        )
        let secondSnapshot = DeliveryRunSnapshot(
            storeRevision: 0,
            savedAt: DeliveryFoundationFixture.date.addingTimeInterval(1),
            runs: []
        )

        async let first = saveOutcome(firstSnapshot, using: firstStore)
        async let second = saveOutcome(secondSnapshot, using: secondStore)
        let pair = await (first, second)
        let outcomes = [pair.0, pair.1]

        #expect(outcomes.filter { $0 == .saved }.count == 1)
        #expect(outcomes.filter { $0 == .revisionConflict }.count == 1)
        #expect(try await firstStore.load()?.storeRevision == 0)
    }

    @Test("file delivery store rejects invalid snapshot relationships")
    func fileStoreRejectsInvalidSnapshotRelationships() async {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("openmac-delivery-integrity-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directoryURL) }
        let store = FileDeliveryRunStore(
            fileURL: directoryURL.appendingPathComponent("delivery-store.json")
        )
        let validRun = DeliveryRun(
            id: DeliveryFoundationFixture.runID,
            brief: DeliveryFoundationFixture.brief(),
            createdAt: DeliveryFoundationFixture.date,
            updatedAt: DeliveryFoundationFixture.date
        )

        do {
            try await store.save(
                DeliveryRunSnapshot(
                    storeRevision: 0,
                    savedAt: DeliveryFoundationFixture.date,
                    runs: [validRun, validRun]
                )
            )
            Issue.record("Expected duplicate run IDs to be rejected")
        } catch let error as DeliveryRunStoreError {
            #expect(error == .duplicateRunID(validRun.id))
        } catch {
            Issue.record("Unexpected error: \(error)")
        }

        let missingRunID = UUID(uuidString: "92000000-0000-0000-0000-000000000001")!
        do {
            try await store.save(
                DeliveryRunSnapshot(
                    storeRevision: 0,
                    savedAt: DeliveryFoundationFixture.date,
                    runs: [validRun],
                    selectedRunID: missingRunID
                )
            )
            Issue.record("Expected a dangling selected run to be rejected")
        } catch let error as DeliveryRunStoreError {
            #expect(error == .danglingSelectedRunID(missingRunID))
        } catch {
            Issue.record("Unexpected error: \(error)")
        }

        let invalidRun = DeliveryRun(
            id: missingRunID,
            brief: DeliveryFoundationFixture.brief(),
            attempts: [DeliveryFoundationFixture.attempt()],
            createdAt: DeliveryFoundationFixture.date,
            updatedAt: DeliveryFoundationFixture.date
        )
        do {
            try await store.save(
                DeliveryRunSnapshot(
                    storeRevision: 0,
                    savedAt: DeliveryFoundationFixture.date,
                    runs: [invalidRun]
                )
            )
            Issue.record("Expected an invalid run to be rejected")
        } catch let error as DeliveryRunStoreError {
            guard case let .invalidRun(runID, issueCodes) = error else {
                Issue.record("Unexpected store error: \(error)")
                return
            }
            #expect(runID == invalidRun.id)
            #expect(issueCodes.contains(.invalidPlan))
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("fixture health and projects are deterministic")
    func fixtureHealthAndProjectsAreDeterministic() async throws {
        let backend = DeterministicFixtureExecutionBackend()

        let health = try await backend.health()
        let projects = try await backend.listProjects()

        #expect(health == FixtureExecutionBackendConfiguration.standard.health)
        #expect(projects == FixtureExecutionBackendConfiguration.standard.projects)
    }

    @Test("fixture start is idempotent under concurrent calls")
    func fixtureStartIsIdempotent() async throws {
        let backend = DeterministicFixtureExecutionBackend()
        let request = DeliveryFoundationFixture.startRequest()

        async let first = backend.start(request)
        async let second = backend.start(request)
        let receipts = try await (first, second)
        let executionCount = await backend.executionCount()

        #expect(receipts.0 == receipts.1)
        #expect(executionCount == 1)
    }

    @Test("fixture rejects an unknown project without a ghost execution")
    func fixtureRejectsUnknownProjectWithoutMutation() async {
        let backend = DeterministicFixtureExecutionBackend()
        let request = DeliveryFoundationFixture.startRequest(
            projectID: ExecutionProjectID("missing-project")
        )

        do {
            _ = try await backend.start(request)
            Issue.record("Expected an unknown project error")
        } catch let error as ExecutionBackendError {
            #expect(error == .projectNotFound(ExecutionProjectID("missing-project")))
        } catch {
            Issue.record("Unexpected error: \(error)")
        }

        #expect(await backend.executionCount() == 0)
    }

    @Test("fixture facts paginate, replay, and exhaust deterministically")
    func fixtureFactsAreReplayable() async throws {
        let backend = DeterministicFixtureExecutionBackend()
        let receipt = try await backend.start(
            DeliveryFoundationFixture.startRequest()
        )

        let first = try await backend.facts(for: receipt.executionID, after: nil)
        let replay = try await backend.facts(for: receipt.executionID, after: nil)
        let second = try await backend.facts(
            for: receipt.executionID,
            after: first.nextCursor
        )

        #expect(first == replay)
        #expect(first.facts.map(\.sequence) == [1])
        #expect(second.facts.map(\.sequence) == [2])
        #expect(first.facts[0].executionID == receipt.executionID)
        #expect(first.facts[0].id == replay.facts[0].id)

        var page = second
        while page.hasMore {
            page = try await backend.facts(
                for: receipt.executionID,
                after: page.nextCursor
            )
        }
        let exhausted = try await backend.facts(
            for: receipt.executionID,
            after: page.nextCursor
        )

        #expect(exhausted.facts.isEmpty)
        #expect(!exhausted.hasMore)
    }

    @Test("fixture malformed cursor does not advance facts")
    func fixtureMalformedCursorDoesNotAdvance() async throws {
        let backend = DeterministicFixtureExecutionBackend()
        let receipt = try await backend.start(
            DeliveryFoundationFixture.startRequest()
        )

        do {
            _ = try await backend.facts(
                for: receipt.executionID,
                after: ExecutionFactCursor("another-execution:3")
            )
            Issue.record("Expected malformed cursor error")
        } catch let error as ExecutionBackendError {
            #expect(
                error == .malformedResponse(
                    operation: .facts,
                    reason: "The fixture cursor is invalid for this execution."
                )
            )
        }

        let first = try await backend.facts(for: receipt.executionID, after: nil)
        #expect(first.facts.map(\.sequence) == [1])
    }

    @Test("fixture operation fault happens before start mutation")
    func fixtureFaultDoesNotCreateExecution() async throws {
        var configuration = FixtureExecutionBackendConfiguration.standard
        configuration.faultsByOperationAndInvocation = [
            .start: [
                1: .malformedResponse(
                    operation: .start,
                    reason: "fixture malformed response"
                )
            ]
        ]
        let backend = DeterministicFixtureExecutionBackend(configuration: configuration)
        let request = DeliveryFoundationFixture.startRequest()

        do {
            _ = try await backend.start(request)
            Issue.record("Expected injected start fault")
        } catch let error as ExecutionBackendError {
            #expect(
                error == .malformedResponse(
                    operation: .start,
                    reason: "fixture malformed response"
                )
            )
        }
        #expect(await backend.executionCount() == 0)

        _ = try await backend.start(request)
        #expect(await backend.executionCount() == 1)
    }

    @Test("fixture preserves unknown backend facts")
    func fixturePreservesUnknownFact() async throws {
        var configuration = FixtureExecutionBackendConfiguration.standard
        configuration.scriptsByTaskID = [
            DeliveryFoundationFixture.firstTaskID: .unknownFact
        ]
        let backend = DeterministicFixtureExecutionBackend(configuration: configuration)
        let receipt = try await backend.start(
            DeliveryFoundationFixture.startRequest()
        )
        let first = try await backend.facts(for: receipt.executionID, after: nil)
        let second = try await backend.facts(
            for: receipt.executionID,
            after: first.nextCursor
        )

        #expect(
            second.facts.map(\.body) == [
                .unknown(
                    kind: "fixture.unrecognized-state",
                    rawPayload: #"{"state":"future","detail":"preserved"}"#
                )
            ]
        )
    }

    @Test("fixture rejects a cursor that was never issued")
    func fixtureRejectsUnissuedCursor() async throws {
        let backend = DeterministicFixtureExecutionBackend()
        let receipt = try await backend.start(
            DeliveryFoundationFixture.startRequest()
        )

        do {
            _ = try await backend.facts(
                for: receipt.executionID,
                after: ExecutionFactCursor("\(receipt.executionID.rawValue):5")
            )
            Issue.record("Expected an unissued cursor error")
        } catch let error as ExecutionBackendError {
            #expect(
                error == .malformedResponse(
                    operation: .facts,
                    reason: "The fixture cursor was not issued for this execution."
                )
            )
        }

        let first = try await backend.facts(for: receipt.executionID, after: nil)
        #expect(first.facts.map(\.body) == [.phase(.accepted)])
    }

    @Test("fixture stop emits stopping facts and is idempotent")
    func fixtureStopIsIdempotent() async throws {
        let backend = DeterministicFixtureExecutionBackend()
        let receipt = try await backend.start(
            DeliveryFoundationFixture.startRequest()
        )
        let acceptedPage = try await backend.facts(
            for: receipt.executionID,
            after: nil
        )

        let firstStop = try await backend.stop(executionID: receipt.executionID)
        let stoppedPage = try await backend.facts(
            for: receipt.executionID,
            after: acceptedPage.nextCursor
        )
        let secondStop = try await backend.stop(executionID: receipt.executionID)

        #expect(firstStop.disposition == .accepted)
        #expect(
            stoppedPage.facts.map(\.body) == [
                .phase(.stopping),
                .phase(.stopped)
            ]
        )
        #expect(secondStop.disposition == .alreadyStopped)
    }

    @Test("fixture reports a scripted stopped phase as already stopped")
    func fixtureRecognizesScriptedStoppedPhase() async throws {
        var configuration = FixtureExecutionBackendConfiguration.standard
        configuration.scriptsByTaskID = [
            DeliveryFoundationFixture.firstTaskID: FixtureExecutionScript(
                factBatches: [[.phase(.stopped)]]
            )
        ]
        let backend = DeterministicFixtureExecutionBackend(configuration: configuration)
        let receipt = try await backend.start(
            DeliveryFoundationFixture.startRequest()
        )
        _ = try await backend.facts(for: receipt.executionID, after: nil)

        let stop = try await backend.stop(executionID: receipt.executionID)
        #expect(stop.disposition == .alreadyStopped)
    }

    @Test("fixture propagates cancellation without a ghost execution")
    func fixtureCancellationDoesNotCreateExecution() async {
        let backend = DeterministicFixtureExecutionBackend { operation, _ in
            if operation == .start {
                throw CancellationError()
            }
        }

        do {
            _ = try await backend.start(
                DeliveryFoundationFixture.startRequest()
            )
            Issue.record("Expected cancellation")
        } catch is CancellationError {
            // Expected: cancellation must not be translated into a backend error.
        } catch {
            Issue.record("Unexpected error: \(error)")
        }

        #expect(await backend.executionCount() == 0)
    }
}
