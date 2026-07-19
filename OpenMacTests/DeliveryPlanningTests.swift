import Foundation
import Testing
@testable import OpenMac

private enum DeliveryPlanningFixture {
    static let date = Date(timeIntervalSince1970: 1_784_457_600)
    static let requestID = UUID(uuidString: "a0000000-0000-0000-0000-000000000001")!
    static let planID = UUID(uuidString: "b0000000-0000-0000-0000-000000000001")!
    static let briefID = UUID(uuidString: "c0000000-0000-0000-0000-000000000001")!
    static let repositoryRootPath = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .standardizedFileURL.path

    static func brief(
        title: String = "Add offline draft sync",
        body: String = "Add an offline-capable SwiftUI draft flow with deterministic conflict handling.",
        rootPath: String = repositoryRootPath
    ) -> FeatureBrief {
        FeatureBrief(
            id: briefID,
            title: title,
            body: body,
            repository: DeliveryRepositoryReference(
                rootPath: rootPath,
                baseBranch: "main",
                xcodeContainerRelativePath: "OpenMac.xcodeproj"
            ),
            createdAt: date
        )
    }

    static func context(
        rootPath: String = repositoryRootPath,
        kind: DeliveryContainerKind = .xcodeProject,
        containerPath: String = "OpenMac.xcodeproj",
        targets: [String] = ["OpenMac"],
        schemes: [String] = ["OpenMac"]
    ) -> DeliveryPlanningRepositoryContext {
        do {
            return try DeliveryPlanningRepositoryContext.resolving(
                repositoryRootPath: rootPath,
                containerKind: kind,
                containerRelativePath: containerPath,
                targetNames: targets,
                schemeNames: schemes
            )
        } catch {
            preconditionFailure("Unable to create planning fixture context: \(error)")
        }
    }

    static func request(
        requestID: UUID = requestID,
        planID: UUID = planID,
        baseStoreRevision: Int = 0,
        brief: FeatureBrief = brief(),
        context: DeliveryPlanningRepositoryContext = context()
    ) -> DeliveryPlanGenerationRequest {
        DeliveryPlanGenerationRequest(
            requestID: requestID,
            planID: planID,
            baseStoreRevision: baseStoreRevision,
            brief: brief,
            repositoryContext: context,
            generatedAt: date
        )
    }

    static func structuredResponse(
        taskCount: Int = 3,
        includeTaskLevelDependency: Bool = false
    ) -> StructuredDeliveryPlanResponse {
        let tasks = (0 ..< taskCount).map { index in
            let taskKey = "task-\(index + 1)"
            let criterionKey = "criterion-\(index + 1)"
            return StructuredDeliveryTask(
                key: taskKey,
                title: "Task \(index + 1)",
                workerPrompt: "Implement task \(index + 1) with focused changes.",
                acceptanceCriteria: [
                    StructuredAcceptanceCriterion(
                        key: criterionKey,
                        statement: "Task \(index + 1) behavior is observable."
                    )
                ],
                riskLevel: DeliveryRiskLevel.medium.rawValue,
                evidenceRequirements: [
                    StructuredEvidenceRequirement(
                        key: "evidence-\(index + 1)",
                        kind: EvidenceKind.xcodeTest.rawValue,
                        description: "Task \(index + 1) tests pass.",
                        coveredCriterionKeys: [criterionKey]
                    )
                ],
                targetHints: ["OpenMac"],
                schemeHints: ["OpenMac"],
                dependsOn: includeTaskLevelDependency && index == 1
                    ? ["task-1"]
                    : nil
            )
        }
        let dependencies = (1 ..< taskCount).map { index in
            StructuredDeliveryDependency(
                prerequisiteTaskKey: "task-\(index)",
                dependentTaskKey: "task-\(index + 1)"
            )
        }
        return StructuredDeliveryPlanResponse(
            tasks: tasks,
            dependencies: dependencies
        )
    }

    static func encoded(_ response: StructuredDeliveryPlanResponse) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(response)
    }
}

private enum PlanningProviderStubError: Error, Sendable {
    case failed
}

private actor RecordingPlanningResponseProvider: DeliveryPlanStructuredResponseProviding {
    nonisolated let providerID: String
    private let responseData: Data
    private let shouldFail: Bool
    private var invocationCountValue = 0

    init(
        providerID: String = "recording.provider",
        responseData: Data,
        shouldFail: Bool = false
    ) {
        self.providerID = providerID
        self.responseData = responseData
        self.shouldFail = shouldFail
    }

    func response(for request: DeliveryPlanGenerationRequest) async throws -> Data {
        invocationCountValue += 1
        if shouldFail {
            throw PlanningProviderStubError.failed
        }
        return responseData
    }

    func invocationCount() -> Int {
        invocationCountValue
    }
}

@Suite("Delivery v2 planning")
struct DeliveryPlanningTests {
    @Test("fixture produces a reviewable Xcode-aware typed plan")
    func fixtureProducesReviewablePlan() async throws {
        let planner = DeterministicFixtureDeliveryPlanner()
        let request = DeliveryPlanningFixture.request()

        let result = try await planner.generate(request)

        #expect(result.requestID == request.requestID)
        #expect(result.plan.id == request.planID)
        #expect(result.plan.revision == 1)
        #expect(result.plan.approval == nil)
        #expect(result.plan.createdAt == request.generatedAt)
        #expect(result.plan.updatedAt == request.generatedAt)
        #expect(result.plan.tasks.count == 5)
        #expect(result.generationIssues.isEmpty)
        #expect(result.isApprovalEligible)
        #expect(DeliveryPlanValidator.validate(result.plan).isEmpty)

        for task in result.plan.tasks {
            #expect(!task.title.isEmpty)
            #expect(!task.workerPrompt.isEmpty)
            #expect(!task.acceptanceCriteria.isEmpty)
            #expect(!task.evidenceRequirements.isEmpty)
            #expect(!task.targetHints.isEmpty || !task.schemeHints.isEmpty)
            let criterionIDs = Set(task.acceptanceCriteria.map(\.id))
            let coveredIDs = Set(task.evidenceRequirements.flatMap(\.coveredCriterionIDs))
            #expect(criterionIDs.isSubset(of: coveredIDs))
        }
    }

    @Test("fixture graph has parallel roots and a typed join")
    func fixtureGraphSupportsParallelWork() async throws {
        let result = try await DeterministicFixtureDeliveryPlanner().generate(
            DeliveryPlanningFixture.request()
        )
        let taskIDs = Set(result.plan.tasks.map(\.id))
        let dependentIDs = Set(result.plan.dependencyEdges.map(\.dependentTaskID))
        let rootIDs = taskIDs.subtracting(dependentIDs)
        let verificationTask = try #require(
            result.plan.tasks.first { $0.title.hasPrefix("Verify ") }
        )
        let verificationPrerequisites = result.plan.dependencyEdges.filter {
            $0.dependentTaskID == verificationTask.id
        }

        #expect(rootIDs.count == 2)
        #expect(verificationPrerequisites.count == 3)
        #expect(result.plan.dependencyEdges.allSatisfy {
            taskIDs.contains($0.prerequisiteTaskID) && taskIDs.contains($0.dependentTaskID)
        })
    }

    @Test("fixture verification requires separate build and test evidence")
    func fixtureVerificationRequiresBuildAndTestEvidence() async throws {
        let result = try await DeterministicFixtureDeliveryPlanner().generate(
            DeliveryPlanningFixture.request()
        )
        let verificationTask = try #require(
            result.plan.tasks.first { $0.title.hasPrefix("Verify ") }
        )
        let evidenceKinds = Set(verificationTask.evidenceRequirements.map(\.kind))
        let criterionIDs = Set(verificationTask.acceptanceCriteria.map(\.id))
        let coveredIDs = Set(
            verificationTask.evidenceRequirements.flatMap(\.coveredCriterionIDs)
        )

        #expect(evidenceKinds == [.xcodeBuild, .xcodeTest])
        #expect(criterionIDs == coveredIDs)
    }

    @Test("fixture generation is deterministic and idempotent")
    func fixtureIsDeterministicAndIdempotent() async throws {
        let planner = DeterministicFixtureDeliveryPlanner()
        let request = DeliveryPlanningFixture.request()

        async let first = planner.generate(request)
        async let second = planner.generate(request)
        let results = try await (first, second)

        #expect(results.0 == results.1)
        #expect(await planner.invocationCount() == 2)
        #expect(await planner.generationCount() == 1)

        let independent = try await DeterministicFixtureDeliveryPlanner().generate(request)
        #expect(independent == results.0)
    }

    @Test("fixture rejects a reused request ID with changed input")
    func fixtureRejectsConflictingRequestID() async throws {
        let planner = DeterministicFixtureDeliveryPlanner()
        let first = DeliveryPlanningFixture.request()
        _ = try await planner.generate(first)
        let changed = DeliveryPlanningFixture.request(
            brief: DeliveryPlanningFixture.brief(
                body: "A different feature brief reusing the same request identity."
            )
        )

        do {
            _ = try await planner.generate(changed)
            Issue.record("Expected a request identity conflict")
        } catch let error as DeliveryPlanGenerationError {
            #expect(error == .conflictingRequestID(first.requestID))
        }
    }

    @Test("brief dependency prose never changes typed edges")
    func dependencyProseIsNotSourceOfTruth() async throws {
        let baseRequest = DeliveryPlanningFixture.request()
        let misleadingRequest = DeliveryPlanningFixture.request(
            brief: DeliveryPlanningFixture.brief(
                body: "Add draft sync. Depends on: Missing Legacy Ticket."
            )
        )

        let base = try await DeterministicFixtureDeliveryPlanner().generate(baseRequest)
        let misleading = try await DeterministicFixtureDeliveryPlanner().generate(misleadingRequest)

        #expect(misleading.plan.dependencyEdges == base.plan.dependencyEdges)
        #expect(misleading.isApprovalEligible)
    }

    @Test("risk signals create a high-risk task with a human action hint")
    func riskSignalsArePreserved() async throws {
        let request = DeliveryPlanningFixture.request(
            brief: DeliveryPlanningFixture.brief(
                body: "Migrate encrypted offline data and change account permissions safely."
            )
        )
        let result = try await DeterministicFixtureDeliveryPlanner().generate(request)
        let coreTask = try #require(
            result.plan.tasks.first { $0.title.hasPrefix("Implement ") }
        )

        #expect(coreTask.riskLevel == .high)
        #expect(coreTask.humanActionHint != nil)
        #expect(result.isApprovalEligible)
    }

    @Test("invalid input is rejected before calling a provider")
    func invalidInputSkipsProvider() async throws {
        let data = try DeliveryPlanningFixture.encoded(
            DeliveryPlanningFixture.structuredResponse()
        )
        let provider = RecordingPlanningResponseProvider(responseData: data)
        let planner = StructuredResponseDeliveryPlanner(
            plannerID: "structured.test",
            provider: provider
        )
        let request = DeliveryPlanningFixture.request(
            brief: DeliveryPlanningFixture.brief(title: "   ")
        )

        do {
            _ = try await planner.generate(request)
            Issue.record("Expected invalid input")
        } catch let error as DeliveryPlanGenerationError {
            guard case let .invalidInput(fieldPath, _) = error else {
                Issue.record("Unexpected planning error: \(error)")
                return
            }
            #expect(fieldPath == "brief.title")
        }
        #expect(await provider.invocationCount() == 0)
    }

    @Test("container path escapes are rejected before calling a provider")
    func containerPathEscapesSkipProvider() async throws {
        let data = try DeliveryPlanningFixture.encoded(
            DeliveryPlanningFixture.structuredResponse()
        )
        let provider = RecordingPlanningResponseProvider(responseData: data)

        for path in [
            "/tmp/Other.xcodeproj",
            "  /tmp/Other.xcodeproj  ",
            "../Other.xcodeproj"
        ] {
            do {
                _ = try DeliveryPlanningRepositoryContext.resolving(
                    repositoryRootPath: DeliveryPlanningFixture.repositoryRootPath,
                    containerKind: .xcodeProject,
                    containerRelativePath: path,
                    targetNames: ["OpenMac"],
                    schemeNames: ["OpenMac"]
                )
                Issue.record("Expected container path '\(path)' to be rejected")
            } catch let error as DeliveryPlanningRepositoryContextResolutionError {
                #expect(error == .invalidContainerRelativePath)
            }
        }

        #expect(await provider.invocationCount() == 0)
    }

    @Test("a resolved symlink target outside the repository is rejected")
    func resolvedContainerEscapeSkipsProvider() async throws {
        let data = try DeliveryPlanningFixture.encoded(
            DeliveryPlanningFixture.structuredResponse()
        )
        let provider = RecordingPlanningResponseProvider(responseData: data)
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("openmac-planning-symlink-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directoryURL) }
        let repositoryURL = directoryURL.appendingPathComponent("Repository", isDirectory: true)
        let outsideProjectURL = directoryURL
            .appendingPathComponent("Outside", isDirectory: true)
            .appendingPathComponent("Other.xcodeproj", isDirectory: true)
        let linkedProjectURL = repositoryURL
            .appendingPathComponent("Linked.xcodeproj", isDirectory: true)
        try FileManager.default.createDirectory(
            at: outsideProjectURL,
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: repositoryURL,
            withIntermediateDirectories: true
        )
        try FileManager.default.createSymbolicLink(
            at: linkedProjectURL,
            withDestinationURL: outsideProjectURL
        )

        do {
            _ = try DeliveryPlanningRepositoryContext.resolving(
                repositoryRootPath: repositoryURL.path,
                containerKind: .xcodeProject,
                containerRelativePath: "Linked.xcodeproj",
                targetNames: ["OpenMac"],
                schemeNames: ["OpenMac"]
            )
            Issue.record("Expected the resolved container escape to be rejected")
        } catch let error as DeliveryPlanningRepositoryContextResolutionError {
            #expect(error == .resolvedContainerEscapesRepository)
        }
        #expect(await provider.invocationCount() == 0)
    }

    @Test("repository symlink retargeting is rejected before calling a provider")
    func repositoryIdentityChangeSkipsProvider() async throws {
        let data = try DeliveryPlanningFixture.encoded(
            DeliveryPlanningFixture.structuredResponse()
        )
        let provider = RecordingPlanningResponseProvider(responseData: data)
        let planner = StructuredResponseDeliveryPlanner(
            plannerID: "structured.test",
            provider: provider
        )
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("openmac-planning-root-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directoryURL) }
        let firstRepositoryURL = directoryURL.appendingPathComponent("First", isDirectory: true)
        let secondRepositoryURL = directoryURL.appendingPathComponent("Second", isDirectory: true)
        let selectedRepositoryURL = directoryURL.appendingPathComponent("Selected", isDirectory: true)
        for repositoryURL in [firstRepositoryURL, secondRepositoryURL] {
            try FileManager.default.createDirectory(
                at: repositoryURL.appendingPathComponent("OpenMac.xcodeproj", isDirectory: true),
                withIntermediateDirectories: true
            )
        }
        try FileManager.default.createSymbolicLink(
            at: selectedRepositoryURL,
            withDestinationURL: firstRepositoryURL
        )
        let context = try DeliveryPlanningRepositoryContext.resolving(
            repositoryRootPath: selectedRepositoryURL.path,
            containerKind: .xcodeProject,
            containerRelativePath: "OpenMac.xcodeproj",
            targetNames: ["OpenMac"],
            schemeNames: ["OpenMac"]
        )
        let request = DeliveryPlanningFixture.request(
            brief: DeliveryPlanningFixture.brief(rootPath: selectedRepositoryURL.path),
            context: context
        )

        try FileManager.default.removeItem(at: selectedRepositoryURL)
        try FileManager.default.createSymbolicLink(
            at: selectedRepositoryURL,
            withDestinationURL: secondRepositoryURL
        )

        do {
            _ = try await planner.generate(request)
            Issue.record("Expected the repository identity change to be rejected")
        } catch let error as DeliveryPlanGenerationError {
            guard case let .invalidInput(fieldPath, _) = error else {
                Issue.record("Unexpected planning error: \(error)")
                return
            }
            #expect(fieldPath == "repositoryContext.resolvedRepositoryRootPath")
        }
        #expect(await provider.invocationCount() == 0)
    }

    @Test("input limits are measured in UTF-8 bytes")
    func combiningCharacterInputSkipsProvider() async throws {
        let data = try DeliveryPlanningFixture.encoded(
            DeliveryPlanningFixture.structuredResponse()
        )
        let provider = RecordingPlanningResponseProvider(responseData: data)
        let planner = StructuredResponseDeliveryPlanner(
            plannerID: "structured.test",
            provider: provider
        )
        let oversizedTitle = "e" + String(
            repeating: "\u{0301}",
            count: StructuredDeliveryPlanParser.maximumBriefTitleByteCount
        )
        let request = DeliveryPlanningFixture.request(
            brief: DeliveryPlanningFixture.brief(title: oversizedTitle)
        )

        do {
            _ = try await planner.generate(request)
            Issue.record("Expected an input byte limit error")
        } catch let error as DeliveryPlanGenerationError {
            guard case let .invalidInput(fieldPath, _) = error else {
                Issue.record("Unexpected planning error: \(error)")
                return
            }
            #expect(fieldPath == "brief.title")
        }
        #expect(await provider.invocationCount() == 0)
    }

    @Test("malformed structured response returns a typed error")
    func malformedResponseIsTyped() async {
        let provider = RecordingPlanningResponseProvider(
            responseData: Data("not-json".utf8)
        )
        let planner = StructuredResponseDeliveryPlanner(
            plannerID: "structured.test",
            provider: provider
        )

        do {
            _ = try await planner.generate(DeliveryPlanningFixture.request())
            Issue.record("Expected malformed response")
        } catch let error as DeliveryPlanGenerationError {
            guard case .malformedResponse = error else {
                Issue.record("Unexpected planning error: \(error)")
                return
            }
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("misspelled dependency field is rejected instead of becoming an empty graph")
    func misspelledDependencyFieldIsRejected() async {
        let response = #"{"format":"openmac.delivery-plan","schemaVersion":1,"revision":1,"tasks":[],"dependencyEdges":[]}"#
        let provider = RecordingPlanningResponseProvider(
            responseData: Data(response.utf8)
        )
        let planner = StructuredResponseDeliveryPlanner(
            plannerID: "structured.test",
            provider: provider
        )

        do {
            _ = try await planner.generate(DeliveryPlanningFixture.request())
            Issue.record("Expected a strict top-level schema error")
        } catch let error as DeliveryPlanGenerationError {
            guard case .malformedResponse = error else {
                Issue.record("Unexpected planning error: \(error)")
                return
            }
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("nested dependency typos are rejected instead of being ignored")
    func nestedDependencyTypoIsRejected() async {
        let response = #"{"format":"openmac.delivery-plan","schemaVersion":1,"revision":1,"tasks":[{"key":"one","title":"One","workerPrompt":"Do one","acceptanceCriteria":[],"riskLevel":"low","evidenceRequirements":[],"targetHints":["OpenMac"],"depends_on":["two"]}],"dependencies":[]}"#
        let provider = RecordingPlanningResponseProvider(
            responseData: Data(response.utf8)
        )
        let planner = StructuredResponseDeliveryPlanner(
            plannerID: "structured.test",
            provider: provider
        )

        do {
            _ = try await planner.generate(DeliveryPlanningFixture.request())
            Issue.record("Expected a nested strict-schema error")
        } catch let error as DeliveryPlanGenerationError {
            guard case .malformedResponse = error else {
                Issue.record("Unexpected planning error: \(error)")
                return
            }
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("duplicate JSON keys are rejected before decoding typed dependencies")
    func duplicateJSONKeysAreRejected() throws {
        let response = #"{"format":"openmac.delivery-plan","schemaVersion":1,"revision":1,"tasks":[],"dependencies":[],"dependencies":[{"prerequisiteTaskKey":"one","dependentTaskKey":"two"}]}"#

        do {
            _ = try StructuredDeliveryPlanParser.parse(
                Data(response.utf8),
                request: DeliveryPlanningFixture.request(),
                plannerID: "parser.test"
            )
            Issue.record("Expected duplicate JSON keys to be rejected")
        } catch let error as DeliveryPlanGenerationError {
            guard case .malformedResponse = error else {
                Issue.record("Unexpected planning error: \(error)")
                return
            }
        }
    }

    @Test("dependency element key typos are rejected")
    func dependencyElementTypoIsRejected() throws {
        let response = #"{"format":"openmac.delivery-plan","schemaVersion":1,"revision":1,"tasks":[],"dependencies":[{"prerequisite_task_key":"one","dependentTaskKey":"two"}]}"#

        do {
            _ = try StructuredDeliveryPlanParser.parse(
                Data(response.utf8),
                request: DeliveryPlanningFixture.request(),
                plannerID: "parser.test"
            )
            Issue.record("Expected a dependency element schema error")
        } catch let error as DeliveryPlanGenerationError {
            guard case .malformedResponse = error else {
                Issue.record("Unexpected planning error: \(error)")
                return
            }
        }
    }

    @Test("structured response collection limits stop compile amplification")
    func responseCollectionLimitIsEnforced() throws {
        let response = DeliveryPlanningFixture.structuredResponse(
            taskCount: StructuredDeliveryPlanParser.maximumTaskCount + 1
        )

        do {
            _ = try StructuredDeliveryPlanParser.parse(
                DeliveryPlanningFixture.encoded(response),
                request: DeliveryPlanningFixture.request(),
                plannerID: "parser.test"
            )
            Issue.record("Expected the task collection limit to be enforced")
        } catch let error as DeliveryPlanGenerationError {
            #expect(
                error == .responseCollectionLimitExceeded(
                    fieldPath: "tasks",
                    maximum: StructuredDeliveryPlanParser.maximumTaskCount
                )
            )
        }
    }

    @Test("provider failure is typed and does not fall back")
    func providerFailureIsTyped() async {
        let provider = RecordingPlanningResponseProvider(
            responseData: Data(),
            shouldFail: true
        )
        let planner = StructuredResponseDeliveryPlanner(
            plannerID: "structured.test",
            provider: provider
        )

        do {
            _ = try await planner.generate(DeliveryPlanningFixture.request())
            Issue.record("Expected provider failure")
        } catch let error as DeliveryPlanGenerationError {
            #expect(
                error == .providerFailure(
                    providerID: "recording.provider",
                    reason: "failed"
                )
            )
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
        #expect(await provider.invocationCount() == 1)
    }

    @Test("semantic response errors preserve an editable candidate")
    func semanticErrorsPreserveCandidate() throws {
        var response = DeliveryPlanningFixture.structuredResponse(taskCount: 2)
        let duplicatedKey = response.tasks[0].key
        response.tasks[1].key = duplicatedKey
        response.tasks[0].title = ""
        response.dependencies = [
            StructuredDeliveryDependency(
                prerequisiteTaskKey: "missing-task",
                dependentTaskKey: "task-1"
            )
        ]
        let result = try StructuredDeliveryPlanParser.parse(
            DeliveryPlanningFixture.encoded(response),
            request: DeliveryPlanningFixture.request(),
            plannerID: "parser.test"
        )
        let codes = result.generationIssues.map(\.code)

        #expect(result.plan.tasks.count == 2)
        #expect(result.plan.id == DeliveryPlanningFixture.planID)
        #expect(result.plan.approval == nil)
        #expect(codes.contains(.taskCountOutOfRange))
        #expect(codes.contains(.duplicateTaskKey))
        #expect(codes.contains(.unknownDependencyTaskKey))
        #expect(codes.contains(.invalidPlan))
        #expect(!result.isApprovalEligible)
    }

    @Test("unknown evidence coverage stays visible as a field issue")
    func unknownEvidenceCoverageIsVisible() throws {
        var response = DeliveryPlanningFixture.structuredResponse()
        response.tasks[0].evidenceRequirements?[0].coveredCriterionKeys = ["missing"]
        let result = try StructuredDeliveryPlanParser.parse(
            DeliveryPlanningFixture.encoded(response),
            request: DeliveryPlanningFixture.request(),
            plannerID: "parser.test"
        )

        #expect(result.generationIssues.map(\.code).contains(.unknownAcceptanceCriterionKey))
        #expect(result.generationIssues.map(\.code).contains(.invalidPlan))
        #expect(!result.isApprovalEligible)
    }

    @Test("task-level dependency fields are rejected, not parsed")
    func taskLevelDependencyIsRejected() throws {
        let response = DeliveryPlanningFixture.structuredResponse(
            includeTaskLevelDependency: true
        )
        let result = try StructuredDeliveryPlanParser.parse(
            DeliveryPlanningFixture.encoded(response),
            request: DeliveryPlanningFixture.request(),
            plannerID: "parser.test"
        )

        #expect(result.plan.dependencyEdges.count == 2)
        #expect(result.generationIssues.map(\.code).contains(.textualDependencyNotAllowed))
        #expect(result.isApprovalEligible)
    }

    @Test("six-task output is a generation deviation but a valid editable plan")
    func sixTasksRemainEditable() throws {
        let response = DeliveryPlanningFixture.structuredResponse(taskCount: 6)
        let result = try StructuredDeliveryPlanParser.parse(
            DeliveryPlanningFixture.encoded(response),
            request: DeliveryPlanningFixture.request(),
            plannerID: "parser.test"
        )

        #expect(result.plan.tasks.count == 6)
        #expect(DeliveryPlanValidator.isValid(result.plan))
        #expect(result.generationIssues.map(\.code) == [.taskCountOutOfRange])
        #expect(result.isApprovalEligible)
    }

    @Test("approval eligibility recomputes from the edited typed plan")
    func approvalEligibilityRecomputesAfterEditing() async throws {
        var result = try await DeterministicFixtureDeliveryPlanner().generate(
            DeliveryPlanningFixture.request()
        )
        let originalTargets = result.plan.tasks[0].targetHints
        let originalSchemes = result.plan.tasks[0].schemeHints

        result.plan.tasks[0].targetHints = []
        result.plan.tasks[0].schemeHints = []
        #expect(!result.isApprovalEligible)
        #expect(result.validationIssues.map(\.code).contains(.missingPlanningHint))

        result.plan.tasks[0].targetHints = originalTargets
        result.plan.tasks[0].schemeHints = originalSchemes
        #expect(result.isApprovalEligible)
        #expect(result.generationIssues.isEmpty)
    }

    @Test("unknown provider hints stay visible without corrupting the typed candidate")
    func unknownProviderHintsAreVisible() throws {
        var response = DeliveryPlanningFixture.structuredResponse()
        response.tasks[0].targetHints = ["HallucinatedTarget"]
        response.tasks[0].schemeHints = ["HallucinatedScheme"]
        let result = try StructuredDeliveryPlanParser.parse(
            DeliveryPlanningFixture.encoded(response),
            request: DeliveryPlanningFixture.request(),
            plannerID: "parser.test"
        )
        let codes = result.generationIssues.map(\.code)

        #expect(codes.contains(.unknownTargetHint))
        #expect(codes.contains(.unknownSchemeHint))
        #expect(result.plan.tasks[0].targetHints == ["OpenMac"])
        #expect(result.plan.tasks[0].schemeHints == ["OpenMac"])
        #expect(
            result.plan.unresolvedGenerationBlockers.map(\.code)
                == [.unknownTargetHint, .unknownSchemeHint]
        )
        #expect(!result.isApprovalEligible)
    }

    @Test("repository hints fill structured tasks without filesystem access")
    func repositoryHintsFillTasks() throws {
        var response = DeliveryPlanningFixture.structuredResponse()
        for index in response.tasks.indices {
            response.tasks[index].targetHints = nil
            response.tasks[index].schemeHints = nil
        }
        let result = try StructuredDeliveryPlanParser.parse(
            DeliveryPlanningFixture.encoded(response),
            request: DeliveryPlanningFixture.request(),
            plannerID: "parser.test"
        )

        #expect(result.plan.tasks.allSatisfy { $0.targetHints == ["OpenMac"] })
        #expect(result.plan.tasks.allSatisfy { $0.schemeHints == ["OpenMac"] })
        #expect(result.isApprovalEligible)
    }

    @Test("ambiguous repository inventory requires explicit task scope")
    func ambiguousRepositoryInventoryDoesNotBecomeAllTargets() throws {
        var response = DeliveryPlanningFixture.structuredResponse()
        for index in response.tasks.indices {
            response.tasks[index].targetHints = nil
            response.tasks[index].schemeHints = nil
        }
        let request = DeliveryPlanningFixture.request(
            context: DeliveryPlanningFixture.context(
                targets: ["OpenMac", "OpenMacKit"],
                schemes: ["OpenMac", "OpenMacKit"]
            )
        )
        let result = try StructuredDeliveryPlanParser.parse(
            DeliveryPlanningFixture.encoded(response),
            request: request,
            plannerID: "parser.test"
        )

        #expect(result.plan.tasks.allSatisfy {
            $0.targetHints.isEmpty && $0.schemeHints.isEmpty
        })
        #expect(result.validationIssues.map(\.code).contains(.missingPlanningHint))
        #expect(!result.isApprovalEligible)
    }

    @Test("fixture cancellation leaves no cached generation")
    func fixtureCancellationLeavesNoResult() async {
        let planner = DeterministicFixtureDeliveryPlanner { _ in
            throw CancellationError()
        }

        do {
            _ = try await planner.generate(DeliveryPlanningFixture.request())
            Issue.record("Expected cancellation")
        } catch is CancellationError {
            // Expected: cancellation must not become a planner failure.
        } catch {
            Issue.record("Unexpected error: \(error)")
        }

        #expect(await planner.generationCount() == 0)
    }

    @Test("valid generated IDs and edges survive the delivery store")
    func generatedPlanRoundTripsThroughStore() async throws {
        let request = DeliveryPlanningFixture.request()
        let result = try await DeterministicFixtureDeliveryPlanner().generate(request)
        let run = DeliveryRun(
            brief: request.brief,
            createdAt: request.generatedAt,
            updatedAt: request.generatedAt
        )
        let snapshot = DeliveryRunSnapshot(
            storeRevision: 0,
            savedAt: request.generatedAt,
            runs: [run],
            selectedRunID: run.id
        )
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("openmac-planning-store-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directoryURL) }
        let store = FileDeliveryRunStore(
            fileURL: directoryURL.appendingPathComponent("delivery-store.json")
        )

        try await store.save(snapshot)
        let applied = try await store.applyGeneratedPlanDraft(
            result,
            toRunID: run.id,
            repositoryContext: request.repositoryContext,
            activeRequestID: request.requestID,
            appliedAt: request.generatedAt.addingTimeInterval(1)
        )
        let loaded = try await store.load()

        #expect(loaded == applied)
        #expect(loaded?.storeRevision == 1)
        #expect(loaded?.runs.first?.plan?.dependencyEdges == result.plan.dependencyEdges)
    }

    @Test("late planning results cannot overwrite a changed brief")
    func stalePlanningResultIsRejectedWithoutMutation() async throws {
        let request = DeliveryPlanningFixture.request(baseStoreRevision: 3)
        let result = try await DeterministicFixtureDeliveryPlanner().generate(request)
        var run = DeliveryRun(
            brief: request.brief,
            createdAt: request.generatedAt,
            updatedAt: request.generatedAt
        )
        run.brief.body = "The user replaced the brief while generation was running."
        let before = run

        do {
            _ = try DeliveryPlanDraftApplicator.applying(
                result,
                to: run,
                repositoryContext: request.repositoryContext,
                activeRequestID: request.requestID,
                currentStoreRevision: 3,
                appliedAt: request.generatedAt.addingTimeInterval(1)
            )
            Issue.record("Expected the stale generation to be rejected")
        } catch let error as DeliveryPlanDraftApplicationError {
            #expect(error == .staleInput)
        }

        #expect(run == before)
    }

    @Test("a result is rejected after another plan advances the store revision")
    func staleStoreRevisionCannotOverwriteNewerPlan() async throws {
        let firstRequest = DeliveryPlanningFixture.request(
            requestID: UUID(),
            planID: UUID(),
            baseStoreRevision: 0
        )
        let secondRequest = DeliveryPlanningFixture.request(
            requestID: UUID(),
            planID: UUID(),
            baseStoreRevision: 0
        )
        let firstResult = try await DeterministicFixtureDeliveryPlanner().generate(firstRequest)
        let secondResult = try await DeterministicFixtureDeliveryPlanner().generate(secondRequest)
        let run = DeliveryRun(
            brief: firstRequest.brief,
            createdAt: firstRequest.generatedAt,
            updatedAt: firstRequest.generatedAt
        )
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("openmac-stale-plan-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directoryURL) }
        let store = FileDeliveryRunStore(
            fileURL: directoryURL.appendingPathComponent("delivery-store.json")
        )
        try await store.save(
            DeliveryRunSnapshot(
                storeRevision: 0,
                savedAt: firstRequest.generatedAt,
                runs: [run],
                selectedRunID: run.id
            )
        )
        _ = try await store.applyGeneratedPlanDraft(
            secondResult,
            toRunID: run.id,
            repositoryContext: secondRequest.repositoryContext,
            activeRequestID: secondRequest.requestID,
            appliedAt: secondRequest.generatedAt.addingTimeInterval(1)
        )

        do {
            _ = try await store.applyGeneratedPlanDraft(
                firstResult,
                toRunID: run.id,
                repositoryContext: firstRequest.repositoryContext,
                activeRequestID: firstRequest.requestID,
                appliedAt: firstRequest.generatedAt.addingTimeInterval(2)
            )
            Issue.record("Expected a stale store revision error")
        } catch let error as DeliveryPlanDraftApplicationError {
            #expect(error == .storeRevisionChanged(expected: 0, current: 1))
        }

        let loaded = try #require(try await store.load())
        #expect(loaded.storeRevision == 1)
        #expect(loaded.runs.first?.plan?.id == secondResult.plan.id)
    }

    @Test("cancelled atomic draft application leaves the store unchanged")
    func cancelledDraftApplicationDoesNotCommit() async throws {
        let request = DeliveryPlanningFixture.request()
        let result = try await DeterministicFixtureDeliveryPlanner().generate(request)
        let run = DeliveryRun(
            brief: request.brief,
            createdAt: request.generatedAt,
            updatedAt: request.generatedAt
        )
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("openmac-cancelled-plan-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directoryURL) }
        let store = FileDeliveryRunStore(
            fileURL: directoryURL.appendingPathComponent("delivery-store.json")
        )
        try await store.save(
            DeliveryRunSnapshot(
                storeRevision: 0,
                savedAt: request.generatedAt,
                runs: [run],
                selectedRunID: run.id
            )
        )

        let application = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await store.applyGeneratedPlanDraft(
                result,
                toRunID: run.id,
                repositoryContext: request.repositoryContext,
                activeRequestID: request.requestID,
                appliedAt: request.generatedAt.addingTimeInterval(1)
            )
        }
        do {
            _ = try await application.value
            Issue.record("Expected draft application cancellation")
        } catch is CancellationError {
            // Expected before the atomic commit point.
        }

        let loaded = try #require(try await store.load())
        #expect(loaded.storeRevision == 0)
        #expect(loaded.runs.first?.plan == nil)
    }

    @Test("lossy generation blockers survive persistence until explicitly resolved")
    func lossyGenerationBlockerSurvivesRoundTrip() async throws {
        let request = DeliveryPlanningFixture.request()
        var response = DeliveryPlanningFixture.structuredResponse()
        response.tasks[0].riskLevel = "extreme"
        let result = try StructuredDeliveryPlanParser.parse(
            DeliveryPlanningFixture.encoded(response),
            request: request,
            plannerID: "parser.test"
        )
        #expect(result.generationIssues.contains {
            $0.code == .unknownRiskLevel && $0.severity == .blocking
        })
        #expect(result.plan.unresolvedGenerationBlockers.map(\.code) == [.unknownRiskLevel])
        #expect(!result.isApprovalEligible)

        let run = DeliveryRun(
            brief: request.brief,
            createdAt: request.generatedAt,
            updatedAt: request.generatedAt
        )
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("openmac-lossy-draft-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directoryURL) }
        let store = FileDeliveryRunStore(
            fileURL: directoryURL.appendingPathComponent("delivery-store.json")
        )
        try await store.save(
            DeliveryRunSnapshot(
                storeRevision: 0,
                savedAt: request.generatedAt,
                runs: [run],
                selectedRunID: run.id
            )
        )
        _ = try await store.applyGeneratedPlanDraft(
            result,
            toRunID: run.id,
            repositoryContext: request.repositoryContext,
            activeRequestID: request.requestID,
            appliedAt: request.generatedAt.addingTimeInterval(1)
        )

        var persistedPlan = try #require(try await store.load()?.runs.first?.plan)
        #expect(
            DeliveryPlanValidator.validate(persistedPlan)
                .map(\.code)
                .contains(.unresolvedGenerationIssue)
        )
        persistedPlan.tasks[0].riskLevel = .high
        persistedPlan.unresolvedGenerationBlockers.removeAll()
        #expect(DeliveryPlanValidator.isValid(persistedPlan))
    }

    @Test("invalid generated drafts persist, remain editable, and cannot bypass approval validation")
    func invalidDraftRoundTripsAndCanBeRepaired() async throws {
        let request = DeliveryPlanningFixture.request()
        let invalidResult = try StructuredDeliveryPlanParser.parse(
            DeliveryPlanningFixture.encoded(
                DeliveryPlanningFixture.structuredResponse(taskCount: 2)
            ),
            request: request,
            plannerID: "parser.test"
        )
        let run = DeliveryRun(
            brief: request.brief,
            createdAt: request.generatedAt,
            updatedAt: request.generatedAt
        )
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("openmac-invalid-draft-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directoryURL) }
        let store = FileDeliveryRunStore(
            fileURL: directoryURL.appendingPathComponent("delivery-store.json")
        )
        try await store.save(
            DeliveryRunSnapshot(
                storeRevision: 0,
                savedAt: request.generatedAt,
                runs: [run],
                selectedRunID: run.id
            )
        )
        let applied = try await store.applyGeneratedPlanDraft(
            invalidResult,
            toRunID: run.id,
            repositoryContext: request.repositoryContext,
            activeRequestID: request.requestID,
            appliedAt: request.generatedAt.addingTimeInterval(1)
        )
        #expect(applied.storeRevision == 1)
        #expect(!DeliveryPlanValidator.isValid(try #require(applied.runs.first?.plan)))
        #expect(DeliveryRunValidator.isValid(try #require(applied.runs.first)))

        var loaded = try #require(try await store.load())
        var loadedRun = try #require(loaded.runs.first)
        var editedPlan = try #require(loadedRun.plan)
        let validCandidate = try StructuredDeliveryPlanParser.parse(
            DeliveryPlanningFixture.encoded(
                DeliveryPlanningFixture.structuredResponse(taskCount: 3)
            ),
            request: request,
            plannerID: "parser.test"
        ).plan
        editedPlan.tasks.append(validCandidate.tasks[2])
        editedPlan.dependencyEdges.append(validCandidate.dependencyEdges[1])
        #expect(DeliveryPlanValidator.isValid(editedPlan))

        let fingerprint = try #require(DeliveryPlanFingerprint.make(for: editedPlan))
        editedPlan.approval = DeliveryPlanApproval(
            planID: editedPlan.id,
            planRevision: editedPlan.revision,
            planFingerprint: fingerprint,
            approvedAt: request.generatedAt.addingTimeInterval(2),
            approvedBy: "fixture-reviewer"
        )
        loadedRun.plan = editedPlan
        loaded.runs = [loadedRun]
        loaded = DeliveryRunSnapshot(
            storeRevision: 2,
            savedAt: request.generatedAt.addingTimeInterval(2),
            runs: loaded.runs,
            selectedRunID: loaded.selectedRunID
        )
        try await store.save(loaded)

        let repaired = try #require(try await store.load()?.runs.first?.plan)
        #expect(DeliveryPlanValidator.isValid(repaired))
        #expect(repaired.approval?.approvedBy == "fixture-reviewer")
    }
}
