import Foundation
import Testing
@testable import OpenMac

private enum DeliveryPlanReviewFixture {
    static let createdAt = Date(timeIntervalSince1970: 1_784_544_000)
    static let changedAt = createdAt.addingTimeInterval(60)
    static let approvedAt = createdAt.addingTimeInterval(120)
    static let runID = UUID(uuidString: "a1000000-0000-0000-0000-000000000001")!
    static let planID = UUID(uuidString: "a2000000-0000-0000-0000-000000000001")!
    static let taskA = UUID(uuidString: "a3000000-0000-0000-0000-000000000001")!
    static let taskB = UUID(uuidString: "a3000000-0000-0000-0000-000000000002")!
    static let taskC = UUID(uuidString: "a3000000-0000-0000-0000-000000000003")!
    static let taskD = UUID(uuidString: "a3000000-0000-0000-0000-000000000004")!
    static let repositoryRootPath =
        DeliveryGitTestRepository.shared.rootURL.path
    static let repositoryIdentity: DeliveryRepositoryIdentitySnapshot = {
        do {
            return try context().identitySnapshot(validatingBaseBranch: "main")
        } catch {
            preconditionFailure(
                "Unable to capture shared review Git identity: \(error)"
            )
        }
    }()

    static func context() throws -> DeliveryPlanningRepositoryContext {
        try DeliveryPlanningRepositoryContext.resolving(
            repositoryRootPath: repositoryRootPath,
            containerKind: .xcodeProject,
            containerRelativePath: "OpenMac.xcodeproj",
            targetNames: ["OpenMac"],
            schemeNames: ["OpenMac"]
        )
    }

    static func brief(
        body: String = "Add a review gate before any delivery execution.",
        baseBranch: String = "main"
    ) -> FeatureBrief {
        FeatureBrief(
            id: UUID(uuidString: "a4000000-0000-0000-0000-000000000001")!,
            title: "Review an execution plan",
            body: body,
            repository: DeliveryRepositoryReference(
                rootPath: repositoryRootPath,
                baseBranch: baseBranch,
                xcodeContainerRelativePath: "OpenMac.xcodeproj"
            ),
            createdAt: createdAt
        )
    }

    static func task(
        id: UUID,
        index: Int,
        risk: DeliveryRiskLevel
    ) -> DeliveryTask {
        let criterionID = UUID(
            uuidString: String(
                format: "a5000000-0000-0000-0000-%012d",
                index
            )
        )!
        let evidenceID = UUID(
            uuidString: String(
                format: "a6000000-0000-0000-0000-%012d",
                index
            )
        )!
        return DeliveryTask(
            id: id,
            title: "Task \(index)",
            workerPrompt: "Implement task \(index) and preserve unrelated behavior.",
            acceptanceCriteria: [
                AcceptanceCriterion(
                    id: criterionID,
                    statement: "Task \(index) behavior is observable."
                )
            ],
            riskLevel: risk,
            evidenceRequirements: [
                EvidenceRequirement(
                    id: evidenceID,
                    kind: .xcodeTest,
                    description: "Task \(index) tests pass.",
                    coveredCriterionIDs: [criterionID]
                )
            ],
            targetHints: ["OpenMac"],
            schemeHints: ["OpenMac"]
        )
    }

    static func plan(
        blockers: [DeliveryPlanGenerationIssue] = []
    ) -> DeliveryPlan {
        DeliveryPlan(
            id: planID,
            revision: 1,
            tasks: [
                task(id: taskA, index: 1, risk: .low),
                task(id: taskB, index: 2, risk: .medium),
                task(id: taskC, index: 3, risk: .high),
                task(id: taskD, index: 4, risk: .medium)
            ],
            dependencyEdges: [
                DependencyEdge(
                    prerequisiteTaskID: taskA,
                    dependentTaskID: taskC
                ),
                DependencyEdge(
                    prerequisiteTaskID: taskB,
                    dependentTaskID: taskC
                ),
                DependencyEdge(
                    prerequisiteTaskID: taskC,
                    dependentTaskID: taskD
                )
            ],
            unresolvedGenerationBlockers: blockers,
            createdAt: createdAt,
            updatedAt: createdAt
        )
    }

    static func run(
        plan: DeliveryPlan = plan(),
        stoppedAt: Date? = nil,
        attempts: [ExecutionAttempt] = []
    ) throws -> DeliveryRun {
        let featureBrief = brief()
        return DeliveryRun(
            id: runID,
            brief: featureBrief,
            repositoryIdentity: repositoryIdentity,
            plan: plan,
            attempts: attempts,
            createdAt: createdAt,
            updatedAt: createdAt,
            stoppedAt: stoppedAt
        )
    }

    static func temporaryStore(
        label: String
    ) -> (directoryURL: URL, store: FileDeliveryRunStore) {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "openmac-\(label)-\(UUID().uuidString)",
                isDirectory: true
            )
        return (
            directoryURL,
            FileDeliveryRunStore(
                fileURL: directoryURL.appendingPathComponent("delivery-store.json"),
                reviewNow: { changedAt }
            )
        )
    }

    static func seed(
        _ store: FileDeliveryRunStore,
        run: DeliveryRun
    ) async throws {
        try await store.save(
            DeliveryRunSnapshot(
                storeRevision: 0,
                savedAt: createdAt,
                runs: [run],
                selectedRunID: run.id
            )
        )
    }

    static func writeLegacySchemaOneSnapshot(
        _ snapshot: DeliveryRunSnapshot,
        to fileURL: URL
    ) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        guard var object = try JSONSerialization.jsonObject(
            with: encoder.encode(snapshot)
        ) as? [String: Any],
        var runs = object["runs"] as? [[String: Any]],
        var run = runs.first,
        var plan = run["plan"] as? [String: Any],
        var approval = plan["approval"] as? [String: Any] else {
            throw NSError(
                domain: "DeliveryPlanReviewFixture",
                code: 1,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "Unable to construct a schema-one fixture."
                ]
            )
        }
        run.removeValue(forKey: "repositoryIdentity")
        approval.removeValue(forKey: "scopeFingerprint")
        plan["approval"] = approval
        run["plan"] = plan
        runs[0] = run
        object["runs"] = runs
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try JSONSerialization.data(
            withJSONObject: object,
            options: [.sortedKeys]
        )
        try data.write(to: fileURL, options: .atomic)
    }
}

@Suite("Delivery v2 plan review")
struct DeliveryPlanReviewTests {
    @Test("fixture bootstrap creates a selected review run without execution")
    func fixtureBootstrapCreatesReviewableRun() async throws {
        let fixture = DeliveryPlanReviewFixture.temporaryStore(
            label: "review-bootstrap"
        )
        defer { try? FileManager.default.removeItem(at: fixture.directoryURL) }
        let planner = DeterministicFixtureDeliveryPlanner()
        let executionBackend = DeterministicFixtureExecutionBackend()
        let bootstrapper = DeliveryFixtureReviewBootstrapper(
            persistence: fixture.store,
            planner: planner,
            now: { DeliveryPlanReviewFixture.createdAt }
        )

        let snapshot = try await bootstrapper.createFixtureReview(
            repositoryRootURL: URL(
                fileURLWithPath: DeliveryPlanReviewFixture.repositoryRootPath,
                isDirectory: true
            )
        )
        let run = try #require(snapshot.runs.first)
        let plan = try #require(run.plan)

        #expect(snapshot.schemaVersion == DeliveryRunSnapshot.currentSchemaVersion)
        #expect(snapshot.storeRevision == 0)
        #expect(snapshot.selectedRunID == run.id)
        #expect(plan.tasks.count == 5)
        #expect(DeliveryPlanValidator.isValid(plan))
        #expect(DeliveryRunValidator.isValid(run))
        #expect(plan.approval == nil)
        #expect(run.attempts.isEmpty)
        #expect(run.brief.repository.baseBranch == "main")
        #expect(await planner.invocationCount() == 1)
        #expect(await executionBackend.executionCount() == 0)
        #expect(
            await executionBackend.invocationCount(for: .start) == 0
        )
    }

    @Test("fixture bootstrap appends and selects a new review run")
    func fixtureBootstrapAppendsToExistingSnapshot() async throws {
        let fixture = DeliveryPlanReviewFixture.temporaryStore(
            label: "review-bootstrap-append"
        )
        defer { try? FileManager.default.removeItem(at: fixture.directoryURL) }
        let existingRun = try DeliveryPlanReviewFixture.run()
        try await DeliveryPlanReviewFixture.seed(
            fixture.store,
            run: existingRun
        )
        let bootstrapper = DeliveryFixtureReviewBootstrapper(
            persistence: fixture.store,
            now: { DeliveryPlanReviewFixture.createdAt }
        )

        let snapshot = try await bootstrapper.createFixtureReview(
            repositoryRootURL: DeliveryGitTestRepository.shared.rootURL
        )

        #expect(snapshot.storeRevision == 1)
        #expect(snapshot.runs.count == 2)
        #expect(snapshot.runs.first == existingRun)
        #expect(snapshot.selectedRunID == snapshot.runs.last?.id)
        #expect(snapshot.runs.last?.plan != nil)
    }

    @Test("review derives deterministic waves, risk counts, and planned sessions")
    func derivesStableReviewSummary() {
        let summary = DeliveryPlanReviewAnalyzer.summarize(
            DeliveryPlanReviewFixture.plan()
        )

        #expect(summary.waves.map(\.taskIDs) == [
            [DeliveryPlanReviewFixture.taskA, DeliveryPlanReviewFixture.taskB],
            [DeliveryPlanReviewFixture.taskC],
            [DeliveryPlanReviewFixture.taskD]
        ])
        #expect(summary.taskCount == 4)
        #expect(summary.estimatedSessionCount == 4)
        #expect(summary.maximumParallelSessionCount == 2)
        #expect(summary.lowRiskTaskCount == 1)
        #expect(summary.mediumRiskTaskCount == 2)
        #expect(summary.highRiskTaskCount == 1)
        #expect(summary.isGraphFullyScheduled)
    }

    @Test("invalid dependency graphs never expose partial waves")
    func invalidGraphsAreUnavailable() {
        var cycle = DeliveryPlanReviewFixture.plan()
        cycle.dependencyEdges.append(
            DependencyEdge(
                prerequisiteTaskID: DeliveryPlanReviewFixture.taskD,
                dependentTaskID: DeliveryPlanReviewFixture.taskA
            )
        )
        var dangling = DeliveryPlanReviewFixture.plan()
        dangling.dependencyEdges.append(
            DependencyEdge(
                prerequisiteTaskID: DeliveryPlanReviewFixture.taskA,
                dependentTaskID: UUID()
            )
        )
        var duplicateTask = DeliveryPlanReviewFixture.plan()
        duplicateTask.tasks.append(duplicateTask.tasks[0])

        let cycleAnalysis = DeliveryPlanGraphAnalyzer.analyze(cycle)
        let danglingAnalysis = DeliveryPlanGraphAnalyzer.analyze(dangling)
        let duplicateAnalysis = DeliveryPlanGraphAnalyzer.analyze(duplicateTask)

        #expect(cycleAnalysis.waves.isEmpty)
        #expect(cycleAnalysis.unavailableIssueCodes.contains(.cyclicDependency))
        #expect(danglingAnalysis.waves.isEmpty)
        #expect(danglingAnalysis.unavailableIssueCodes.contains(.missingDependencyTask))
        #expect(duplicateAnalysis.waves.isEmpty)
        #expect(duplicateAnalysis.unavailableIssueCodes.contains(.duplicateTaskID))
        #expect(!DeliveryPlanReviewAnalyzer.summarize(cycle).isGraphFullyScheduled)
    }

    @Test("draft editing preserves identities and cleans typed references")
    func draftEditingPreservesIdentity() {
        let original = DeliveryPlanReviewFixture.plan()
        var draft = DeliveryPlanReviewDraft(plan: original)
        let newCriterion = AcceptanceCriterion(statement: "A second observable result exists.")
        let newEvidence = EvidenceRequirement(
            kind: .screenshot,
            description: "The second result is visible.",
            coveredCriterionIDs: [newCriterion.id]
        )

        let updatedTitle = draft.updateTaskTitle(
            taskID: DeliveryPlanReviewFixture.taskA,
            title: "Edited task"
        )
        let addedCriterion = draft.addAcceptanceCriterion(
            taskID: DeliveryPlanReviewFixture.taskA,
            criterion: newCriterion
        )
        let addedEvidence = draft.addEvidenceRequirement(
            taskID: DeliveryPlanReviewFixture.taskA,
            requirement: newEvidence
        )
        let addedDependency = draft.setDependency(
            prerequisiteTaskID: DeliveryPlanReviewFixture.taskB,
            dependentTaskID: DeliveryPlanReviewFixture.taskD,
            isEnabled: true
        )
        let removedCriterion = draft.removeAcceptanceCriterion(
            taskID: DeliveryPlanReviewFixture.taskA,
            criterionID: newCriterion.id
        )
        let removedTask = draft.removeTask(taskID: DeliveryPlanReviewFixture.taskC)

        #expect(updatedTitle)
        #expect(addedCriterion)
        #expect(addedEvidence)
        #expect(addedDependency)
        #expect(removedCriterion)
        #expect(removedTask)
        #expect(draft.plan.id == original.id)
        #expect(draft.plan.revision == original.revision)
        #expect(draft.plan.createdAt == original.createdAt)
        #expect(
            draft.plan.tasks.first(where: {
                $0.id == DeliveryPlanReviewFixture.taskA
            })?.evidenceRequirements
                .first(where: { $0.id == newEvidence.id })?
                .coveredCriterionIDs.contains(newCriterion.id) == false
        )
        #expect(
            !draft.plan.dependencyEdges.contains {
                $0.prerequisiteTaskID == DeliveryPlanReviewFixture.taskC
                    || $0.dependentTaskID == DeliveryPlanReviewFixture.taskC
            }
        )

        var danglingPlan = original
        let danglingEdge = DependencyEdge(
            prerequisiteTaskID: DeliveryPlanReviewFixture.taskA,
            dependentTaskID: UUID()
        )
        danglingPlan.dependencyEdges.append(danglingEdge)
        var danglingDraft = DeliveryPlanReviewDraft(plan: danglingPlan)
        let removedDanglingEdge = danglingDraft.removeDependency(danglingEdge)
        #expect(removedDanglingEdge)
        #expect(
            !danglingDraft.plan.dependencyEdges.contains(danglingEdge)
        )
    }

    @Test("invalid drafts persist, while approval fails without mutation")
    func cycleDraftPersistsButCannotBeApproved() async throws {
        let fixture = DeliveryPlanReviewFixture.temporaryStore(label: "review-cycle")
        defer { try? FileManager.default.removeItem(at: fixture.directoryURL) }
        let run = try DeliveryPlanReviewFixture.run()
        try await DeliveryPlanReviewFixture.seed(fixture.store, run: run)
        var cycle = try #require(run.plan)
        cycle.dependencyEdges.append(
            DependencyEdge(
                prerequisiteTaskID: DeliveryPlanReviewFixture.taskD,
                dependentTaskID: DeliveryPlanReviewFixture.taskA
            )
        )

        let saved = try await fixture.store.saveReviewedPlanDraft(
            cycle,
            toRunID: run.id,
            expectedStoreRevision: 0,
            expectedPlanRevision: 1
        )
        let savedPlan = try #require(saved.runs.first?.plan)
        #expect(saved.storeRevision == 1)
        #expect(saved.savedAt == DeliveryPlanReviewFixture.changedAt)
        #expect(savedPlan.revision == 2)
        #expect(
            DeliveryPlanValidator.validate(savedPlan)
                .map(\.code).contains(.cyclicDependency)
        )

        do {
            _ = try await fixture.store.approveReviewedPlan(
                savedPlan,
                inRunID: run.id,
                expectedStoreRevision: saved.storeRevision,
                expectedPlanRevision: savedPlan.revision,
                approvedBy: "Reviewer"
            )
            Issue.record("Expected cyclic plan approval to fail")
        } catch let error as DeliveryPlanReviewError {
            guard case let .invalidPlan(issueCodes) = error else {
                Issue.record("Unexpected review error: \(error)")
                return
            }
            #expect(issueCodes.contains(.cyclicDependency))
        }

        #expect(try await fixture.store.load() == saved)
    }

    @Test("all required plan fields and typed references gate approval")
    func approvalBoundaryRejectsInvalidContent() throws {
        let run = try DeliveryPlanReviewFixture.run()
        let plan = try #require(run.plan)
        let cases: [
            (
                name: String,
                mutate: (inout DeliveryPlan) -> Void,
                expectedCode: DeliveryPlanValidationIssueCode
            )
        ] = [
            (
                "blank title",
                { $0.tasks[0].title = " \n " },
                .emptyTaskTitle
            ),
            (
                "blank worker prompt",
                { $0.tasks[0].workerPrompt = "\t" },
                .emptyWorkerPrompt
            ),
            (
                "blank acceptance",
                { $0.tasks[0].acceptanceCriteria[0].statement = " " },
                .emptyAcceptanceCriterion
            ),
            (
                "zero evidence",
                { $0.tasks[0].evidenceRequirements = [] },
                .emptyEvidenceRequirement
            ),
            (
                "dangling dependency",
                {
                    $0.dependencyEdges.append(
                        DependencyEdge(
                            prerequisiteTaskID: DeliveryPlanReviewFixture.taskA,
                            dependentTaskID: UUID()
                        )
                    )
                },
                .missingDependencyTask
            )
        ]

        for boundaryCase in cases {
            var proposed = plan
            boundaryCase.mutate(&proposed)
            do {
                _ = try DeliveryPlanReviewApplicator.approving(
                    proposed,
                    in: run,
                    expectedPlanRevision: plan.revision,
                    approvedBy: "Reviewer",
                    approvedAt: DeliveryPlanReviewFixture.approvedAt
                )
                Issue.record(
                    "Expected \(boundaryCase.name) to prevent approval"
                )
            } catch let error as DeliveryPlanReviewError {
                guard case let .invalidPlan(issueCodes) = error else {
                    Issue.record(
                        "Unexpected \(boundaryCase.name) error: \(error)"
                    )
                    continue
                }
                #expect(issueCodes.contains(boundaryCase.expectedCode))
            }
        }
    }

    @Test("generation blockers require individual explicit resolution")
    func generationBlockersRequireExplicitResolution() async throws {
        let first = DeliveryPlanGenerationIssue(
            code: .unknownRiskLevel,
            fieldPath: "tasks[0].riskLevel",
            message: "Confirm the fallback risk."
        )
        let second = DeliveryPlanGenerationIssue(
            code: .unknownEvidenceKind,
            fieldPath: "tasks[1].evidence[0].kind",
            message: "Confirm the fallback evidence kind."
        )
        let fixture = DeliveryPlanReviewFixture.temporaryStore(label: "review-blockers")
        defer { try? FileManager.default.removeItem(at: fixture.directoryURL) }
        let run = try DeliveryPlanReviewFixture.run(
            plan: DeliveryPlanReviewFixture.plan(blockers: [first, second])
        )
        try await DeliveryPlanReviewFixture.seed(fixture.store, run: run)
        var firstDraft = DeliveryPlanReviewDraft(plan: try #require(run.plan))

        let resolvedFirst = firstDraft.resolveGenerationIssue(first)
        let resolvedFirstAgain = firstDraft.resolveGenerationIssue(first)
        #expect(resolvedFirst)
        #expect(!resolvedFirstAgain)
        let saved = try await fixture.store.saveReviewedPlanDraft(
            firstDraft.plan,
            toRunID: run.id,
            expectedStoreRevision: 0,
            expectedPlanRevision: 1
        )
        let savedPlan = try #require(saved.runs.first?.plan)
        #expect(savedPlan.unresolvedGenerationBlockers == [second])

        do {
            _ = try await fixture.store.approveReviewedPlan(
                savedPlan,
                inRunID: run.id,
                expectedStoreRevision: 1,
                expectedPlanRevision: 2,
                approvedBy: "Reviewer"
            )
            Issue.record("Expected unresolved blocker approval to fail")
        } catch let error as DeliveryPlanReviewError {
            guard case let .invalidPlan(issueCodes) = error else {
                Issue.record("Unexpected review error: \(error)")
                return
            }
            #expect(issueCodes.contains(.unresolvedGenerationIssue))
        }

        var finalDraft = DeliveryPlanReviewDraft(plan: savedPlan)
        let resolvedSecond = finalDraft.resolveGenerationIssue(second)
        #expect(resolvedSecond)
        let approved = try await fixture.store.approveReviewedPlan(
            finalDraft.plan,
            inRunID: run.id,
            expectedStoreRevision: 1,
            expectedPlanRevision: 2,
            approvedBy: "Reviewer"
        )
        #expect(approved.runs.first?.plan?.revision == 3)
        #expect(approved.runs.first?.plan?.approval != nil)
    }

    @Test("save and approve bump a changed plan exactly once and preserve identity")
    func revisionAndFingerprintSemantics() throws {
        let run = try DeliveryPlanReviewFixture.run()
        let persisted = try #require(run.plan)
        var proposed = persisted
        proposed.tasks[0].title = "A reviewed task title"

        let savedRun = try DeliveryPlanReviewApplicator.savingDraft(
            proposed,
            to: run,
            expectedPlanRevision: persisted.revision,
            savedAt: DeliveryPlanReviewFixture.changedAt
        )
        let savedPlan = try #require(savedRun.plan)
        #expect(savedPlan.id == persisted.id)
        #expect(savedPlan.revision == persisted.revision + 1)
        #expect(savedPlan.createdAt == persisted.createdAt)
        #expect(savedPlan.updatedAt == DeliveryPlanReviewFixture.changedAt)
        #expect(savedRun.updatedAt == DeliveryPlanReviewFixture.changedAt)

        let approvedRun = try DeliveryPlanReviewApplicator.approving(
            proposed,
            in: run,
            expectedPlanRevision: persisted.revision,
            approvedBy: "  Reviewer  ",
            approvedAt: DeliveryPlanReviewFixture.approvedAt
        )
        let approvedPlan = try #require(approvedRun.plan)
        let approval = try #require(approvedPlan.approval)
        let expectedPlanFingerprint = try #require(
            DeliveryPlanFingerprint.make(for: approvedPlan)
        )
        let repositoryIdentity = try #require(approvedRun.repositoryIdentity)
        let expectedScopeFingerprint = try #require(
            DeliveryApprovalScopeFingerprint.make(
                runID: approvedRun.id,
                runCreatedAt: approvedRun.createdAt,
                brief: approvedRun.brief,
                repositoryIdentity: repositoryIdentity,
                planFingerprint: expectedPlanFingerprint,
                approvedAt: approval.approvedAt,
                approvedBy: approval.approvedBy
            )
        )

        #expect(approvedPlan.revision == persisted.revision + 1)
        #expect(approval.approvedBy == "Reviewer")
        #expect(approval.approvedAt == DeliveryPlanReviewFixture.approvedAt)
        #expect(approval.planFingerprint == expectedPlanFingerprint)
        #expect(approval.scopeFingerprint == expectedScopeFingerprint)
        #expect(DeliveryRunValidator.isValid(approvedRun))

        do {
            _ = try DeliveryPlanReviewApplicator.savingDraft(
                proposed,
                to: run,
                expectedPlanRevision: persisted.revision,
                savedAt: DeliveryPlanReviewFixture.createdAt.addingTimeInterval(-1)
            )
            Issue.record("Expected a backdated review to fail")
        } catch let error as DeliveryPlanReviewError {
            #expect(error == .reviewTimestampPrecedesPersistedState)
        }

        do {
            _ = try DeliveryPlanReviewApplicator.approving(
                persisted,
                in: run,
                expectedPlanRevision: persisted.revision,
                approvedBy: " ",
                approvedAt: DeliveryPlanReviewFixture.approvedAt
            )
            Issue.record("Expected an empty reviewer to fail")
        } catch let error as DeliveryPlanReviewError {
            #expect(error == .reviewerRequired)
        }
    }

    @Test("approval scope becomes stale after brief or repository mutation")
    func approvalScopeRejectsMutation() throws {
        let run = try DeliveryPlanReviewFixture.run()
        let plan = try #require(run.plan)
        let approved = try DeliveryPlanReviewApplicator.approving(
            plan,
            in: run,
            expectedPlanRevision: plan.revision,
            approvedBy: "Reviewer",
            approvedAt: DeliveryPlanReviewFixture.approvedAt
        )

        var changedBody = approved
        changedBody.brief.body = "A different requested outcome."
        var changedBranch = approved
        changedBranch.brief.repository.baseBranch = "release"
        var changedRoot = approved
        changedRoot.brief.repository.rootPath = "/tmp/another-repository"
        var changedIdentity = approved
        let identity = try #require(changedIdentity.repositoryIdentity)
        changedIdentity.repositoryIdentity = DeliveryRepositoryIdentitySnapshot(
            repositoryRootPath: identity.repositoryRootPath,
            resolvedRepositoryRootPath: identity.resolvedRepositoryRootPath + "-changed",
            repositoryFileIdentity: identity.repositoryFileIdentity,
            containerKind: identity.containerKind,
            containerRelativePath: identity.containerRelativePath,
            resolvedContainerPath: identity.resolvedContainerPath,
            containerFileIdentity: identity.containerFileIdentity,
            gitCommonDirectoryPath: identity.gitCommonDirectoryPath,
            gitCommonDirectoryFileIdentity:
                identity.gitCommonDirectoryFileIdentity,
            baseCommitIdentifier: identity.baseCommitIdentifier
        )
        var changedReviewer = approved
        let originalApproval = try #require(changedReviewer.plan?.approval)
        changedReviewer.plan?.approval = DeliveryPlanApproval(
            planID: originalApproval.planID,
            planRevision: originalApproval.planRevision,
            planFingerprint: originalApproval.planFingerprint,
            scopeFingerprint: originalApproval.scopeFingerprint,
            approvedAt: originalApproval.approvedAt,
            approvedBy: "Another reviewer"
        )

        for candidate in [
            changedBody,
            changedBranch,
            changedRoot,
            changedIdentity,
            changedReviewer
        ] {
            #expect(
                DeliveryRunValidator.validate(candidate)
                    .map(\.code).contains(.staleApprovalScope)
            )
        }
        #expect(
            DeliveryRunValidator.validate(changedRoot)
                .map(\.code).contains(.repositoryIdentityMismatch)
        )
    }

    @Test("generic store save cannot create or rewrite approval")
    func genericStoreCannotBypassReviewAuthority() async throws {
        let fixture = DeliveryPlanReviewFixture.temporaryStore(
            label: "review-authority"
        )
        defer { try? FileManager.default.removeItem(at: fixture.directoryURL) }
        let run = try DeliveryPlanReviewFixture.run()
        try await DeliveryPlanReviewFixture.seed(fixture.store, run: run)
        let plan = try #require(run.plan)
        let selfApprovedRun = try DeliveryPlanReviewApplicator.approving(
            plan,
            in: run,
            expectedPlanRevision: plan.revision,
            approvedBy: "Reviewer",
            approvedAt: DeliveryPlanReviewFixture.changedAt
        )

        do {
            try await fixture.store.save(
                DeliveryRunSnapshot(
                    storeRevision: 1,
                    savedAt: DeliveryPlanReviewFixture.changedAt,
                    runs: [selfApprovedRun],
                    selectedRunID: run.id
                )
            )
            Issue.record("Expected generic save to reject a new approval")
        } catch let error as DeliveryRunStoreError {
            #expect(error == .approvalMutationRequiresReview(run.id))
        }
        #expect(try await fixture.store.load()?.storeRevision == 0)

        let approvedSnapshot = try await fixture.store.approveReviewedPlan(
            plan,
            inRunID: run.id,
            expectedStoreRevision: 0,
            expectedPlanRevision: plan.revision,
            approvedBy: "Reviewer"
        )
        var rewrittenRun = try #require(approvedSnapshot.runs.first)
        let approval = try #require(rewrittenRun.plan?.approval)
        rewrittenRun.plan?.approval = DeliveryPlanApproval(
            planID: approval.planID,
            planRevision: approval.planRevision,
            planFingerprint: approval.planFingerprint,
            scopeFingerprint: approval.scopeFingerprint,
            approvedAt: approval.approvedAt,
            approvedBy: "Rewritten reviewer"
        )
        do {
            try await fixture.store.save(
                DeliveryRunSnapshot(
                    storeRevision: 2,
                    savedAt: DeliveryPlanReviewFixture.approvedAt,
                    runs: [rewrittenRun],
                    selectedRunID: run.id
                )
            )
            Issue.record("Expected generic save to reject approval rewriting")
        } catch let error as DeliveryRunStoreError {
            #expect(error == .approvalMutationRequiresReview(run.id))
        }
        #expect(try await fixture.store.load() == approvedSnapshot)

        var revokedRun = try #require(approvedSnapshot.runs.first)
        revokedRun.plan?.approval = nil
        do {
            try await fixture.store.save(
                DeliveryRunSnapshot(
                    storeRevision: 2,
                    savedAt: DeliveryPlanReviewFixture.approvedAt,
                    runs: [revokedRun],
                    selectedRunID: run.id
                )
            )
            Issue.record("Expected generic save to reject approval revocation")
        } catch let error as DeliveryRunStoreError {
            #expect(error == .approvalMutationRequiresReview(run.id))
        }
        #expect(try await fixture.store.load() == approvedSnapshot)
    }

    @Test("store clock rejects a review timestamp older than persisted state")
    func storeClockCannotBackdateReview() async throws {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "openmac-review-backdated-\(UUID().uuidString)",
                isDirectory: true
            )
        defer { try? FileManager.default.removeItem(at: directoryURL) }
        let store = FileDeliveryRunStore(
            fileURL: directoryURL.appendingPathComponent("delivery-store.json"),
            reviewNow: {
                DeliveryPlanReviewFixture.createdAt.addingTimeInterval(-1)
            }
        )
        let run = try DeliveryPlanReviewFixture.run()
        try await DeliveryPlanReviewFixture.seed(store, run: run)
        var proposed = try #require(run.plan)
        proposed.tasks[0].title = "A backdated edit"

        do {
            _ = try await store.saveReviewedPlanDraft(
                proposed,
                toRunID: run.id,
                expectedStoreRevision: 0,
                expectedPlanRevision: 1
            )
            Issue.record("Expected a backdated store clock to fail")
        } catch let error as DeliveryPlanReviewError {
            #expect(error == .reviewTimestampPrecedesPersistedState)
        }
        #expect(try await store.load()?.storeRevision == 0)
        #expect(try await store.load()?.runs.first?.plan == run.plan)
    }

    @Test("review time cannot move a multi-run snapshot backward")
    func reviewClockIsMonotonicAcrossRuns() async throws {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "openmac-review-cross-run-clock-\(UUID().uuidString)",
                isDirectory: true
            )
        defer { try? FileManager.default.removeItem(at: directoryURL) }
        let store = FileDeliveryRunStore(
            fileURL: directoryURL.appendingPathComponent("delivery-store.json"),
            reviewNow: { DeliveryPlanReviewFixture.changedAt }
        )
        let targetRun = try DeliveryPlanReviewFixture.run()
        var laterPlan = DeliveryPlanReviewFixture.plan()
        laterPlan.updatedAt = DeliveryPlanReviewFixture.approvedAt
        let laterRun = DeliveryRun(
            brief: DeliveryPlanReviewFixture.brief(),
            repositoryIdentity: targetRun.repositoryIdentity,
            plan: laterPlan,
            createdAt: DeliveryPlanReviewFixture.createdAt,
            updatedAt: DeliveryPlanReviewFixture.approvedAt
        )
        try await store.save(
            DeliveryRunSnapshot(
                storeRevision: 0,
                savedAt: DeliveryPlanReviewFixture.approvedAt,
                runs: [targetRun, laterRun],
                selectedRunID: targetRun.id
            )
        )
        var proposed = try #require(targetRun.plan)
        proposed.tasks[0].title = "This edit uses an older global clock"

        do {
            _ = try await store.saveReviewedPlanDraft(
                proposed,
                toRunID: targetRun.id,
                expectedStoreRevision: 0,
                expectedPlanRevision: 1
            )
            Issue.record("Expected the snapshot clock to remain monotonic")
        } catch let error as DeliveryPlanReviewError {
            #expect(error == .reviewTimestampPrecedesPersistedState)
        }

        let unchanged = try #require(try await store.load())
        #expect(unchanged.storeRevision == 0)
        #expect(unchanged.savedAt == DeliveryPlanReviewFixture.approvedAt)
    }

    @Test("approved, stopped, and fact-bearing runs are immutable")
    func immutableRunsRejectEditing() throws {
        let run = try DeliveryPlanReviewFixture.run()
        let plan = try #require(run.plan)
        var proposed = plan
        proposed.tasks[0].title = "Disallowed edit"
        let approved = try DeliveryPlanReviewApplicator.approving(
            plan,
            in: run,
            expectedPlanRevision: plan.revision,
            approvedBy: "Reviewer",
            approvedAt: DeliveryPlanReviewFixture.approvedAt
        )
        var stopped = run
        stopped.stoppedAt = DeliveryPlanReviewFixture.changedAt
        let attempt = ExecutionAttempt(
            taskID: DeliveryPlanReviewFixture.taskA,
            planID: plan.id,
            planRevision: plan.revision,
            sequence: 1,
            backendID: "fixture",
            status: .queued,
            createdAt: DeliveryPlanReviewFixture.createdAt
        )
        var factBearing = run
        factBearing.attempts = [attempt]

        do {
            _ = try DeliveryPlanReviewApplicator.savingDraft(
                proposed,
                to: approved,
                expectedPlanRevision: plan.revision,
                savedAt: DeliveryPlanReviewFixture.changedAt
            )
            Issue.record("Expected approved plan editing to fail")
        } catch let error as DeliveryPlanReviewError {
            #expect(error == .approvedPlanCannotBeEdited)
        }
        do {
            _ = try DeliveryPlanReviewApplicator.savingDraft(
                proposed,
                to: stopped,
                expectedPlanRevision: plan.revision,
                savedAt: DeliveryPlanReviewFixture.changedAt
            )
            Issue.record("Expected stopped run editing to fail")
        } catch let error as DeliveryPlanReviewError {
            #expect(error == .stoppedRunCannotBeEdited)
        }
        do {
            _ = try DeliveryPlanReviewApplicator.savingDraft(
                proposed,
                to: factBearing,
                expectedPlanRevision: plan.revision,
                savedAt: DeliveryPlanReviewFixture.changedAt
            )
            Issue.record("Expected fact-bearing run editing to fail")
        } catch let error as DeliveryPlanReviewError {
            #expect(error == .deliveryFactsAlreadyExist)
        }
    }

    @Test("stale edit and approval cannot overwrite a newer draft")
    func staleReviewCommandsDoNotOverwrite() async throws {
        let fixture = DeliveryPlanReviewFixture.temporaryStore(label: "review-cas")
        defer { try? FileManager.default.removeItem(at: fixture.directoryURL) }
        let run = try DeliveryPlanReviewFixture.run()
        try await DeliveryPlanReviewFixture.seed(fixture.store, run: run)
        let original = try #require(run.plan)
        var firstEdit = original
        firstEdit.tasks[0].title = "First editor wins"
        var staleEdit = original
        staleEdit.tasks[0].title = "Stale editor loses"

        let saved = try await fixture.store.saveReviewedPlanDraft(
            firstEdit,
            toRunID: run.id,
            expectedStoreRevision: 0,
            expectedPlanRevision: 1
        )
        do {
            _ = try await fixture.store.saveReviewedPlanDraft(
                staleEdit,
                toRunID: run.id,
                expectedStoreRevision: 0,
                expectedPlanRevision: 1
            )
            Issue.record("Expected stale draft save to fail")
        } catch let error as DeliveryPlanReviewError {
            #expect(
                error == .storeRevisionChanged(
                    expected: 0,
                    current: saved.storeRevision
                )
            )
        }
        do {
            _ = try await fixture.store.approveReviewedPlan(
                staleEdit,
                inRunID: run.id,
                expectedStoreRevision: 0,
                expectedPlanRevision: 1,
                approvedBy: "Reviewer"
            )
            Issue.record("Expected stale approval to fail")
        } catch let error as DeliveryPlanReviewError {
            #expect(
                error == .storeRevisionChanged(
                    expected: 0,
                    current: saved.storeRevision
                )
            )
        }

        let latest = try #require(try await fixture.store.load())
        #expect(latest == saved)
        #expect(latest.runs.first?.plan?.tasks[0].title == "First editor wins")
        #expect(latest.runs.first?.plan?.approval == nil)
    }

    @Test("file approval revalidates repository identity and round trips scope")
    func fileApprovalRevalidatesIdentity() async throws {
        let fixture = DeliveryPlanReviewFixture.temporaryStore(label: "review-identity")
        defer { try? FileManager.default.removeItem(at: fixture.directoryURL) }
        let run = try DeliveryPlanReviewFixture.run()
        try await DeliveryPlanReviewFixture.seed(fixture.store, run: run)
        let plan = try #require(run.plan)

        let approved = try await fixture.store.approveReviewedPlan(
            plan,
            inRunID: run.id,
            expectedStoreRevision: 0,
            expectedPlanRevision: plan.revision,
            approvedBy: "Reviewer"
        )
        let roundTrip = try #require(try await fixture.store.load())
        #expect(roundTrip == approved)
        #expect(roundTrip.runs.first?.plan?.approval?.scopeFingerprint.isEmpty == false)

        let badFixture = DeliveryPlanReviewFixture.temporaryStore(
            label: "review-bad-identity"
        )
        defer { try? FileManager.default.removeItem(at: badFixture.directoryURL) }
        var badRun = run
        let identity = try #require(badRun.repositoryIdentity)
        badRun.repositoryIdentity = DeliveryRepositoryIdentitySnapshot(
            repositoryRootPath: identity.repositoryRootPath,
            resolvedRepositoryRootPath: identity.resolvedRepositoryRootPath + "-stale",
            repositoryFileIdentity: identity.repositoryFileIdentity,
            containerKind: identity.containerKind,
            containerRelativePath: identity.containerRelativePath,
            resolvedContainerPath: identity.resolvedContainerPath,
            containerFileIdentity: identity.containerFileIdentity,
            gitCommonDirectoryPath: identity.gitCommonDirectoryPath,
            gitCommonDirectoryFileIdentity:
                identity.gitCommonDirectoryFileIdentity,
            baseCommitIdentifier: identity.baseCommitIdentifier
        )
        try await DeliveryPlanReviewFixture.seed(badFixture.store, run: badRun)

        do {
            _ = try await badFixture.store.approveReviewedPlan(
                plan,
                inRunID: badRun.id,
                expectedStoreRevision: 0,
                expectedPlanRevision: plan.revision,
                approvedBy: "Reviewer"
            )
            Issue.record("Expected stale repository identity to fail")
        } catch let error as DeliveryPlanningRepositoryContextResolutionError {
            #expect(error == .repositoryIdentityChanged)
        }
        #expect(try await badFixture.store.load()?.storeRevision == 0)
        #expect(try await badFixture.store.load()?.runs.first?.plan?.approval == nil)
    }

    @Test("approval fails atomically when the base branch moves")
    func baseBranchMovementInvalidatesApproval() async throws {
        let repository = try DeliveryGitTestRepository.make(
            label: "review-branch-move"
        )
        defer { try? FileManager.default.removeItem(at: repository.rootURL) }
        let fixture = DeliveryPlanReviewFixture.temporaryStore(
            label: "review-branch-move-store"
        )
        defer { try? FileManager.default.removeItem(at: fixture.directoryURL) }
        let context = try DeliveryPlanningRepositoryContext.resolving(
            repositoryRootPath: repository.rootURL.path,
            containerKind: .xcodeProject,
            containerRelativePath: repository.containerRelativePath,
            targetNames: ["OpenMac"],
            schemeNames: ["OpenMac"]
        )
        let brief = FeatureBrief(
            title: "Review a pinned base commit",
            body: "Approval must fail if the local base branch moves.",
            repository: DeliveryRepositoryReference(
                rootPath: repository.rootURL.path,
                baseBranch: repository.baseBranch,
                xcodeContainerRelativePath: repository.containerRelativePath
            ),
            createdAt: DeliveryPlanReviewFixture.createdAt
        )
        let run = DeliveryRun(
            brief: brief,
            repositoryIdentity: try context.identitySnapshot(
                validatingBaseBranch: repository.baseBranch
            ),
            plan: DeliveryPlanReviewFixture.plan(),
            createdAt: DeliveryPlanReviewFixture.createdAt,
            updatedAt: DeliveryPlanReviewFixture.createdAt
        )
        try await DeliveryPlanReviewFixture.seed(fixture.store, run: run)
        try repository.commitFile(
            named: "branch-moved.txt",
            contents: "new base\n"
        )

        do {
            _ = try await fixture.store.approveReviewedPlan(
                try #require(run.plan),
                inRunID: run.id,
                expectedStoreRevision: 0,
                expectedPlanRevision: 1,
                approvedBy: "Reviewer"
            )
            Issue.record("Expected a moved base branch to invalidate approval")
        } catch let error as DeliveryPlanningRepositoryContextResolutionError {
            #expect(error == .baseBranchIdentityChanged)
        }

        let unchanged = try #require(try await fixture.store.load())
        #expect(unchanged.storeRevision == 0)
        #expect(unchanged.runs.first?.plan?.approval == nil)
    }

    @Test("schema one draft migrates identity and requires fresh approval")
    func legacySchemaMigratesFailClosed() async throws {
        let fixture = DeliveryPlanReviewFixture.temporaryStore(
            label: "review-migration"
        )
        defer { try? FileManager.default.removeItem(at: fixture.directoryURL) }
        let run = try DeliveryPlanReviewFixture.run()
        let plan = try #require(run.plan)
        let approvedRun = try DeliveryPlanReviewApplicator.approving(
            plan,
            in: run,
            expectedPlanRevision: plan.revision,
            approvedBy: "Legacy Reviewer",
            approvedAt: DeliveryPlanReviewFixture.changedAt
        )
        let legacySnapshot = DeliveryRunSnapshot(
            schemaVersion: 1,
            storeRevision: 4,
            savedAt: DeliveryPlanReviewFixture.changedAt,
            runs: [approvedRun],
            selectedRunID: approvedRun.id
        )
        try DeliveryPlanReviewFixture.writeLegacySchemaOneSnapshot(
            legacySnapshot,
            to: fixture.store.fileURL
        )

        let migrated = try #require(try await fixture.store.load())
        let migratedRun = try #require(migrated.runs.first)
        let expectedIdentity = try DeliveryPlanReviewFixture.context()
            .identitySnapshot(validatingBaseBranch: "main")
        #expect(migrated.schemaVersion == DeliveryRunSnapshot.currentSchemaVersion)
        #expect(migrated.storeRevision == legacySnapshot.storeRevision + 1)
        #expect(migratedRun.plan?.approval == nil)
        #expect(migratedRun.repositoryIdentity == expectedIdentity)
        #expect(DeliveryRunValidator.isValid(migratedRun))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let persistedMigration = try decoder.decode(
            DeliveryRunSnapshot.self,
            from: Data(contentsOf: fixture.store.fileURL)
        )
        #expect(persistedMigration == migrated)

        let migratedPlan = try #require(migratedRun.plan)
        let reapproved = try await fixture.store.approveReviewedPlan(
            migratedPlan,
            inRunID: migratedRun.id,
            expectedStoreRevision: migrated.storeRevision,
            expectedPlanRevision: migratedPlan.revision,
            approvedBy: "Fresh Reviewer"
        )
        #expect(reapproved.runs.first?.plan?.approval != nil)
    }

    @Test("persisted migration prevents repository rebinding before approval")
    func migratedDraftCannotRebindToMovedBranch() async throws {
        let repository = try DeliveryGitTestRepository.make(
            label: "review-migration-branch"
        )
        defer { try? FileManager.default.removeItem(at: repository.rootURL) }
        let fixture = DeliveryPlanReviewFixture.temporaryStore(
            label: "review-migration-branch-store"
        )
        defer { try? FileManager.default.removeItem(at: fixture.directoryURL) }
        let context = try DeliveryPlanningRepositoryContext.resolving(
            repositoryRootPath: repository.rootURL.path,
            containerKind: .xcodeProject,
            containerRelativePath: repository.containerRelativePath,
            targetNames: ["OpenMac"],
            schemeNames: ["OpenMac"]
        )
        let brief = FeatureBrief(
            title: "Migrate a pinned legacy draft",
            body: "The migrated identity must become CAS-visible.",
            repository: DeliveryRepositoryReference(
                rootPath: repository.rootURL.path,
                baseBranch: repository.baseBranch,
                xcodeContainerRelativePath: repository.containerRelativePath
            ),
            createdAt: DeliveryPlanReviewFixture.createdAt
        )
        let run = DeliveryRun(
            brief: brief,
            repositoryIdentity: try context.identitySnapshot(
                validatingBaseBranch: repository.baseBranch
            ),
            plan: DeliveryPlanReviewFixture.plan(),
            createdAt: DeliveryPlanReviewFixture.createdAt,
            updatedAt: DeliveryPlanReviewFixture.createdAt
        )
        let approved = try DeliveryPlanReviewApplicator.approving(
            try #require(run.plan),
            in: run,
            expectedPlanRevision: 1,
            approvedBy: "Legacy Reviewer",
            approvedAt: DeliveryPlanReviewFixture.changedAt
        )
        try DeliveryPlanReviewFixture.writeLegacySchemaOneSnapshot(
            DeliveryRunSnapshot(
                schemaVersion: 1,
                storeRevision: 7,
                savedAt: DeliveryPlanReviewFixture.changedAt,
                runs: [approved],
                selectedRunID: approved.id
            ),
            to: fixture.store.fileURL
        )

        let migrated = try #require(try await fixture.store.load())
        #expect(migrated.storeRevision == 8)
        #expect(migrated.runs.first?.plan?.approval == nil)
        try repository.commitFile(
            named: "moved-after-migration.txt",
            contents: "new base\n"
        )

        do {
            _ = try await fixture.store.approveReviewedPlan(
                try #require(migrated.runs.first?.plan),
                inRunID: approved.id,
                expectedStoreRevision: migrated.storeRevision,
                expectedPlanRevision: 1,
                approvedBy: "Fresh Reviewer"
            )
            Issue.record("Expected migrated identity to remain pinned")
        } catch let error as DeliveryPlanningRepositoryContextResolutionError {
            #expect(error == .baseBranchIdentityChanged)
        }
        let unchanged = try #require(try await fixture.store.load())
        #expect(unchanged.storeRevision == migrated.storeRevision)
        #expect(unchanged.runs.first?.plan?.approval == nil)
    }

    @Test("failed legacy identity refresh remains retryable")
    func legacyMigrationRetriesAfterRepositoryRecovers() async throws {
        let repository = try DeliveryGitTestRepository.make(
            label: "review-migration-retry"
        )
        defer { try? FileManager.default.removeItem(at: repository.rootURL) }
        let fixture = DeliveryPlanReviewFixture.temporaryStore(
            label: "review-migration-retry-store"
        )
        defer { try? FileManager.default.removeItem(at: fixture.directoryURL) }
        let context = try DeliveryPlanningRepositoryContext.resolving(
            repositoryRootPath: repository.rootURL.path,
            containerKind: .xcodeProject,
            containerRelativePath: repository.containerRelativePath,
            targetNames: ["OpenMac"],
            schemeNames: ["OpenMac"]
        )
        let brief = FeatureBrief(
            title: "Retry a legacy migration",
            body: "A temporary repository problem must not consume migration.",
            repository: DeliveryRepositoryReference(
                rootPath: repository.rootURL.path,
                baseBranch: repository.baseBranch,
                xcodeContainerRelativePath: repository.containerRelativePath
            ),
            createdAt: DeliveryPlanReviewFixture.createdAt
        )
        let run = DeliveryRun(
            brief: brief,
            repositoryIdentity: try context.identitySnapshot(
                validatingBaseBranch: repository.baseBranch
            ),
            plan: DeliveryPlanReviewFixture.plan(),
            createdAt: DeliveryPlanReviewFixture.createdAt,
            updatedAt: DeliveryPlanReviewFixture.createdAt
        )
        let approved = try DeliveryPlanReviewApplicator.approving(
            try #require(run.plan),
            in: run,
            expectedPlanRevision: 1,
            approvedBy: "Legacy Reviewer",
            approvedAt: DeliveryPlanReviewFixture.changedAt
        )
        let legacy = DeliveryRunSnapshot(
            schemaVersion: 1,
            storeRevision: 2,
            savedAt: DeliveryPlanReviewFixture.changedAt,
            runs: [approved],
            selectedRunID: approved.id
        )
        try DeliveryPlanReviewFixture.writeLegacySchemaOneSnapshot(
            legacy,
            to: fixture.store.fileURL
        )
        let dirtyURL = repository.rootURL.appendingPathComponent("dirty.txt")
        try Data("temporary\n".utf8).write(to: dirtyURL, options: .atomic)

        do {
            _ = try await fixture.store.load()
            Issue.record("Expected dirty repository migration to remain pending")
        } catch let error as DeliveryRunStoreError {
            #expect(
                error == .legacyRepositoryIdentityUnavailable(approved.id)
            )
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let stillLegacy = try decoder.decode(
            DeliveryRunSnapshot.self,
            from: Data(contentsOf: fixture.store.fileURL)
        )
        #expect(stillLegacy.schemaVersion == 1)
        #expect(stillLegacy.storeRevision == legacy.storeRevision)

        try FileManager.default.removeItem(at: dirtyURL)
        let migrated = try #require(try await fixture.store.load())
        #expect(migrated.schemaVersion == DeliveryRunSnapshot.currentSchemaVersion)
        #expect(migrated.storeRevision == legacy.storeRevision + 1)
        #expect(migrated.runs.first?.repositoryIdentity != nil)
    }

    @Test("review and approval make zero execution backend calls")
    func reviewDoesNotDispatch() async throws {
        let backend = DeterministicFixtureExecutionBackend()
        let fixture = DeliveryPlanReviewFixture.temporaryStore(label: "review-no-dispatch")
        defer { try? FileManager.default.removeItem(at: fixture.directoryURL) }
        let run = try DeliveryPlanReviewFixture.run()
        try await DeliveryPlanReviewFixture.seed(fixture.store, run: run)
        var proposed = try #require(run.plan)
        proposed.tasks[0].title = "Reviewed without dispatch"
        let saved = try await fixture.store.saveReviewedPlanDraft(
            proposed,
            toRunID: run.id,
            expectedStoreRevision: 0,
            expectedPlanRevision: 1
        )
        let savedPlan = try #require(saved.runs.first?.plan)
        _ = try await fixture.store.approveReviewedPlan(
            savedPlan,
            inRunID: run.id,
            expectedStoreRevision: 1,
            expectedPlanRevision: 2,
            approvedBy: "Reviewer"
        )

        for operation in [
            ExecutionBackendOperation.health,
            .listProjects,
            .start,
            .facts,
            .stop
        ] {
            #expect(await backend.invocationCount(for: operation) == 0)
        }
        #expect(await backend.executionCount() == 0)
    }

    @MainActor
    @Test("view model keeps edits local, saves with CAS, and becomes read only")
    func viewModelReviewFlow() async throws {
        let fixture = DeliveryPlanReviewFixture.temporaryStore(label: "review-model")
        defer { try? FileManager.default.removeItem(at: fixture.directoryURL) }
        let run = try DeliveryPlanReviewFixture.run()
        try await DeliveryPlanReviewFixture.seed(fixture.store, run: run)
        let model = DeliveryPlanReviewViewModel(persistence: fixture.store)

        await model.load()
        #expect(model.plan?.id == DeliveryPlanReviewFixture.planID)
        #expect(model.canApprove == false)
        model.reviewerName = "Reviewer"
        #expect(model.canApprove)
        model.updateTaskTitle(
            taskID: DeliveryPlanReviewFixture.taskA,
            title: "Edited in the review window"
        )
        #expect(model.hasUnsavedChanges)
        await model.saveDraft()
        #expect(model.errorMessage == nil)
        #expect(!model.hasUnsavedChanges)
        #expect(model.plan?.revision == 2)

        await model.approve()
        #expect(model.errorMessage == nil)
        #expect(model.isApproved)
        #expect(model.isReadOnly)
        #expect(!model.canSaveDraft)
        #expect(!model.canApprove)
        #expect(model.plan?.approval?.approvedBy == "Reviewer")
    }
}
