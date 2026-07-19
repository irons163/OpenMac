import Foundation

typealias FixtureDeliveryPlannerDelayHook = @Sendable (Int) async throws -> Void

nonisolated struct FixtureDeliveryPlannerConfiguration: Sendable {
    var plannerID: String
    var errorsByInvocation: [Int: DeliveryPlanGenerationError]

    nonisolated init(
        plannerID: String = "fixture.delivery-planner",
        errorsByInvocation: [Int: DeliveryPlanGenerationError] = [:]
    ) {
        self.plannerID = plannerID
        self.errorsByInvocation = errorsByInvocation
    }
}

actor DeterministicFixtureDeliveryPlanner: DeliveryPlanning {
    nonisolated let plannerID: String

    private struct CachedResult: Sendable {
        let request: DeliveryPlanGenerationRequest
        let result: DeliveryPlanGenerationResult
    }

    private let configuration: FixtureDeliveryPlannerConfiguration
    private let delayHook: FixtureDeliveryPlannerDelayHook
    private var invocationCountValue = 0
    private var cachedResultsByRequestID: [UUID: CachedResult] = [:]

    init(
        configuration: FixtureDeliveryPlannerConfiguration = FixtureDeliveryPlannerConfiguration(),
        delayHook: @escaping FixtureDeliveryPlannerDelayHook = { _ in }
    ) {
        self.plannerID = configuration.plannerID
        self.configuration = configuration
        self.delayHook = delayHook
    }

    func generate(
        _ request: DeliveryPlanGenerationRequest
    ) async throws -> DeliveryPlanGenerationResult {
        try StructuredDeliveryPlanParser.validateInput(request)

        invocationCountValue += 1
        let invocation = invocationCountValue
        if let cached = cachedResultsByRequestID[request.requestID] {
            guard cached.request == request else {
                throw DeliveryPlanGenerationError.conflictingRequestID(request.requestID)
            }
            return cached.result
        }

        try await delayHook(invocation)
        try Task.checkCancellation()

        if let error = configuration.errorsByInvocation[invocation] {
            throw error
        }

        if let cached = cachedResultsByRequestID[request.requestID] {
            guard cached.request == request else {
                throw DeliveryPlanGenerationError.conflictingRequestID(request.requestID)
            }
            return cached.result
        }

        let response = Self.makeResponse(for: request)
        let data: Data
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            data = try encoder.encode(response)
        } catch {
            throw DeliveryPlanGenerationError.providerFailure(
                providerID: plannerID,
                reason: String(describing: error)
            )
        }

        let result = try StructuredDeliveryPlanParser.parse(
            data,
            request: request,
            plannerID: plannerID
        )
        try Task.checkCancellation()
        cachedResultsByRequestID[request.requestID] = CachedResult(
            request: request,
            result: result
        )
        return result
    }

    func invocationCount() -> Int {
        invocationCountValue
    }

    func generationCount() -> Int {
        cachedResultsByRequestID.count
    }

    func recordedRequests() -> [DeliveryPlanGenerationRequest] {
        cachedResultsByRequestID.values
            .map(\.request)
            .sorted { $0.requestID.uuidString < $1.requestID.uuidString }
    }

    nonisolated private static func makeResponse(
        for request: DeliveryPlanGenerationRequest
    ) -> StructuredDeliveryPlanResponse {
        let title = compactWhitespace(request.brief.title)
        let brief = compactedBrief(request.brief.body)
        let container = request.repositoryContext.containerRelativePath
        let targets = normalizedHints(request.repositoryContext.targetNames)
        let schemes = normalizedHints(request.repositoryContext.schemeNames)
        let elevatedRisk = hasElevatedRiskSignal(request.brief.body)

        let tasks = [
            makeTask(
                key: "scope",
                title: "Establish \(title) shared implementation seams",
                prompt: "Implement the shared domain and protocol seams for \(title) in \(container), following the already approved scope and keeping changes limited to this brief: \(brief)",
                criterionKey: "shared-seams-compile",
                criterion: "The shared contracts needed by core and Apple-platform integration compile and are ready for isolated implementation work.",
                risk: .low,
                evidenceKey: "shared-seam-build",
                evidenceKind: .xcodeBuild,
                evidenceDescription: "The target containing the shared implementation seams builds successfully.",
                targets: targets,
                schemes: schemes
            ),
            makeTask(
                key: "verification-contract",
                title: "Define \(title) verification coverage",
                prompt: "Define executable acceptance coverage for \(title), including success and failure paths, before implementation is treated as complete.",
                criterionKey: "coverage-is-executable",
                criterion: "Critical success and failure paths have executable verification coverage.",
                risk: .low,
                evidenceKey: "test-artifacts",
                evidenceKind: .changedFiles,
                evidenceDescription: "Test or fixture artifacts encode the required verification paths.",
                targets: targets,
                schemes: schemes
            ),
            makeTask(
                key: "core",
                title: "Implement \(title) core behavior",
                prompt: "Implement the core behavior for \(title) from the approved scope, preserve existing contracts, and avoid unrelated repository changes.",
                criterionKey: "core-builds",
                criterion: "The core behavior is implemented and its affected target builds successfully.",
                risk: elevatedRisk ? .high : .medium,
                evidenceKey: "core-build",
                evidenceKind: .xcodeBuild,
                evidenceDescription: "The affected Xcode target completes a successful build.",
                targets: targets,
                schemes: schemes,
                humanActionHint: elevatedRisk
                    ? "Confirm migration, permission, or rollback assumptions before dispatch."
                    : nil
            ),
            makeTask(
                key: "apple-integration",
                title: "Integrate \(title) into the Apple-platform experience",
                prompt: "Connect \(title) to the intended Apple-platform entry points and state flow while preserving accessibility and existing navigation behavior.",
                criterionKey: "integration-is-observable",
                criterion: "The feature is observable through its intended Apple-platform entry point.",
                risk: .medium,
                evidenceKey: "integration-test",
                evidenceKind: .xcodeTest,
                evidenceDescription: "Automated tests exercise the integrated user-visible behavior.",
                targets: targets,
                schemes: schemes
            ),
            StructuredDeliveryTask(
                key: "verification",
                title: "Verify \(title) and delivery evidence",
                workerPrompt: "Run the required Xcode build and test verification for \(title), preserve command outcomes, and prepare traceable delivery evidence.",
                acceptanceCriteria: [
                    StructuredAcceptanceCriterion(
                        key: "verification-build-passes",
                        statement: "The required Xcode build completes successfully with a traceable result."
                    ),
                    StructuredAcceptanceCriterion(
                        key: "verification-tests-pass",
                        statement: "The required Xcode tests complete successfully with traceable results."
                    )
                ],
                riskLevel: DeliveryRiskLevel.low.rawValue,
                evidenceRequirements: [
                    StructuredEvidenceRequirement(
                        key: "verification-build",
                        kind: EvidenceKind.xcodeBuild.rawValue,
                        description: "The required Xcode build command exits successfully.",
                        coveredCriterionKeys: ["verification-build-passes"]
                    ),
                    StructuredEvidenceRequirement(
                        key: "verification-tests",
                        kind: EvidenceKind.xcodeTest.rawValue,
                        description: "The required Xcode test command exits successfully.",
                        coveredCriterionKeys: ["verification-tests-pass"]
                    )
                ],
                targetHints: targets,
                schemeHints: schemes
            )
        ]

        return StructuredDeliveryPlanResponse(
            tasks: tasks,
            dependencies: [
                StructuredDeliveryDependency(
                    prerequisiteTaskKey: "scope",
                    dependentTaskKey: "core"
                ),
                StructuredDeliveryDependency(
                    prerequisiteTaskKey: "scope",
                    dependentTaskKey: "apple-integration"
                ),
                StructuredDeliveryDependency(
                    prerequisiteTaskKey: "verification-contract",
                    dependentTaskKey: "verification"
                ),
                StructuredDeliveryDependency(
                    prerequisiteTaskKey: "core",
                    dependentTaskKey: "verification"
                ),
                StructuredDeliveryDependency(
                    prerequisiteTaskKey: "apple-integration",
                    dependentTaskKey: "verification"
                )
            ]
        )
    }

    nonisolated private static func makeTask(
        key: String,
        title: String,
        prompt: String,
        criterionKey: String,
        criterion: String,
        risk: DeliveryRiskLevel,
        evidenceKey: String,
        evidenceKind: EvidenceKind,
        evidenceDescription: String,
        targets: [String],
        schemes: [String],
        humanActionHint: String? = nil
    ) -> StructuredDeliveryTask {
        StructuredDeliveryTask(
            key: key,
            title: title,
            workerPrompt: prompt,
            acceptanceCriteria: [
                StructuredAcceptanceCriterion(
                    key: criterionKey,
                    statement: criterion
                )
            ],
            riskLevel: risk.rawValue,
            evidenceRequirements: [
                StructuredEvidenceRequirement(
                    key: evidenceKey,
                    kind: evidenceKind.rawValue,
                    description: evidenceDescription,
                    coveredCriterionKeys: [criterionKey]
                )
            ],
            targetHints: targets,
            schemeHints: schemes,
            humanActionHint: humanActionHint
        )
    }

    nonisolated private static func compactedBrief(_ value: String) -> String {
        let compact = compactWhitespace(value)
        guard compact.count > 320 else { return compact }
        let end = compact.index(compact.startIndex, offsetBy: 320)
        return String(compact[..<end]) + "…"
    }

    nonisolated private static func compactWhitespace(_ value: String) -> String {
        value
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    nonisolated private static func normalizedHints(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []
        for value in values {
            let candidate = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !candidate.isEmpty else { continue }
            guard seen.insert(candidate.lowercased()).inserted else { continue }
            result.append(candidate)
        }
        return result
    }

    nonisolated private static func hasElevatedRiskSignal(_ value: String) -> Bool {
        let normalized = value.lowercased()
        let signals = [
            "auth", "oauth", "security", "permission", "payment", "billing",
            "migration", "sync", "encryption", "privacy", "entitlement",
            "權限", "安全", "金流", "遷移", "同步", "隱私"
        ]
        return signals.contains { normalized.contains($0) }
    }
}
