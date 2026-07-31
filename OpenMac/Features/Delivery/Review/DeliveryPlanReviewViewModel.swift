import Combine
import Foundation

nonisolated enum DeliveryPlanReviewPresentationError:
    Error,
    Equatable,
    LocalizedError,
    Sendable
{
    case selectedRunMissing
    case reviewedRunMissing(UUID)
    case reviewedPlanMissing(UUID)

    nonisolated var errorDescription: String? {
        switch self {
        case .selectedRunMissing:
            return "Select a delivery run with a generated plan before opening review."
        case let .reviewedRunMissing(runID):
            return "Delivery run \(runID.uuidString) is no longer available."
        case let .reviewedPlanMissing(runID):
            return "Delivery run \(runID.uuidString) no longer has a plan."
        }
    }
}

@MainActor
final class DeliveryPlanReviewViewModel: ObservableObject {
    enum Activity: Equatable {
        case idle
        case creating
        case saving
        case approving
    }

    @Published private(set) var draft: DeliveryPlanReviewDraft?
    @Published private(set) var activity: Activity = .idle
    @Published private(set) var isLoading = false
    @Published private(set) var emptyStateMessage: String?
    @Published private(set) var errorMessage: String?
    @Published private(set) var readOnlyReason: String?
    @Published private(set) var reviewedBrief: FeatureBrief?
    @Published private(set) var repositoryIdentity:
        DeliveryRepositoryIdentitySnapshot?
    @Published var reviewerName = ""

    private(set) var runID: UUID?
    private(set) var storeRevision = 0
    private var persistedPlan: DeliveryPlan?
    private let persistence: any DeliveryPlanReviewPersisting
    private let fixtureBootstrapper: DeliveryFixtureReviewBootstrapper

    init(
        persistence: any DeliveryPlanReviewPersisting = FileDeliveryRunStore(),
        fixturePlanner: any DeliveryPlanning = DeterministicFixtureDeliveryPlanner(),
        fixtureNow: @escaping @Sendable () -> Date = Date.init
    ) {
        self.persistence = persistence
        fixtureBootstrapper = DeliveryFixtureReviewBootstrapper(
            persistence: persistence,
            planner: fixturePlanner,
            now: fixtureNow
        )
    }

    var plan: DeliveryPlan? {
        draft?.plan
    }

    var tasks: [DeliveryTask] {
        plan?.tasks ?? []
    }

    var validationIssues: [DeliveryPlanValidationIssue] {
        plan.map(DeliveryPlanValidator.validate) ?? []
    }

    var summary: DeliveryPlanReviewSummary? {
        plan.map(DeliveryPlanReviewAnalyzer.summarize)
    }

    var isReadOnly: Bool {
        readOnlyReason != nil
    }

    var isApproved: Bool {
        plan?.approval != nil
    }

    var isBusy: Bool {
        isLoading || activity != .idle
    }

    var hasUnsavedChanges: Bool {
        guard let proposedPlan = plan,
              let persistedPlan else {
            return false
        }
        return DeliveryPlanReviewApplicator.hasContentChanges(
            proposedPlan: proposedPlan,
            persistedPlan: persistedPlan
        )
    }

    var canSaveDraft: Bool {
        !isBusy && !isReadOnly && hasUnsavedChanges
    }

    var canApprove: Bool {
        guard !isBusy,
              !isReadOnly,
              plan != nil,
              validationIssues.isEmpty else {
            return false
        }
        let reviewer = reviewerName.trimmingCharacters(in: .whitespacesAndNewlines)
        return !reviewer.isEmpty
            && reviewer.utf8.count <= DeliveryPlanReviewApplicator.maximumReviewerByteCount
    }

    func load() async {
        guard !isBusy else { return }
        isLoading = true
        errorMessage = nil
        emptyStateMessage = nil
        defer { isLoading = false }

        do {
            guard let snapshot = try await persistence.load() else {
                clearReview(
                    message: "No delivery runs are available for review yet."
                )
                return
            }
            guard let selectedRunID = snapshot.selectedRunID else {
                clearReview(
                    message: DeliveryPlanReviewPresentationError
                        .selectedRunMissing.localizedDescription
                )
                return
            }
            try apply(snapshot: snapshot, runID: selectedRunID)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func reloadDiscardingLocalChanges() async {
        guard !isBusy else { return }
        await load()
    }

    func createFixtureReview(repositoryRootURL: URL) async {
        guard !isBusy else { return }
        activity = .creating
        errorMessage = nil
        emptyStateMessage = nil
        defer { activity = .idle }

        do {
            let snapshot = try await fixtureBootstrapper.createFixtureReview(
                repositoryRootURL: repositoryRootURL
            )
            guard let selectedRunID = snapshot.selectedRunID else {
                throw DeliveryPlanReviewPresentationError.selectedRunMissing
            }
            try apply(snapshot: snapshot, runID: selectedRunID)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func presentFixtureSelectionError(_ error: any Error) {
        errorMessage = error.localizedDescription
    }

    func saveDraft() async {
        guard canSaveDraft,
              let proposedPlan = plan,
              let persistedPlan,
              let runID else {
            return
        }

        activity = .saving
        errorMessage = nil
        defer { activity = .idle }
        do {
            let snapshot = try await persistence.saveReviewedPlanDraft(
                proposedPlan,
                toRunID: runID,
                expectedStoreRevision: storeRevision,
                expectedPlanRevision: persistedPlan.revision
            )
            try apply(snapshot: snapshot, runID: runID)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func approve() async {
        guard canApprove,
              let proposedPlan = plan,
              let persistedPlan,
              let runID else {
            return
        }

        activity = .approving
        errorMessage = nil
        defer { activity = .idle }
        do {
            let snapshot = try await persistence.approveReviewedPlan(
                proposedPlan,
                inRunID: runID,
                expectedStoreRevision: storeRevision,
                expectedPlanRevision: persistedPlan.revision,
                approvedBy: reviewerName
            )
            try apply(snapshot: snapshot, runID: runID)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func updateTaskTitle(taskID: UUID, title: String) {
        mutateDraft { $0.updateTaskTitle(taskID: taskID, title: title) }
    }

    func updateWorkerPrompt(taskID: UUID, prompt: String) {
        mutateDraft { $0.updateWorkerPrompt(taskID: taskID, prompt: prompt) }
    }

    func updateRiskLevel(taskID: UUID, riskLevel: DeliveryRiskLevel) {
        mutateDraft { $0.updateRiskLevel(taskID: taskID, riskLevel: riskLevel) }
    }

    func updateHumanActionHint(taskID: UUID, hint: String) {
        mutateDraft {
            $0.updateHumanActionHint(
                taskID: taskID,
                hint: hint.isEmpty ? nil : hint
            )
        }
    }

    func updateAcceptanceCriterion(
        taskID: UUID,
        criterionID: UUID,
        statement: String
    ) {
        mutateDraft {
            $0.updateAcceptanceCriterion(
                taskID: taskID,
                criterionID: criterionID,
                statement: statement
            )
        }
    }

    func addTask() {
        guard let plan,
              plan.tasks.count < 7 else {
            return
        }
        let criterion = AcceptanceCriterion(statement: "")
        let requirement = EvidenceRequirement(
            kind: .custom,
            description: "",
            coveredCriterionIDs: [criterion.id]
        )
        let task = DeliveryTask(
            title: "",
            workerPrompt: "",
            acceptanceCriteria: [criterion],
            riskLevel: .medium,
            evidenceRequirements: [requirement],
            targetHints: plan.tasks.first?.targetHints ?? [],
            schemeHints: plan.tasks.first?.schemeHints ?? []
        )
        mutateDraft { $0.addTask(task) }
    }

    func removeTask(taskID: UUID) {
        mutateDraft { $0.removeTask(taskID: taskID) }
    }

    func addAcceptanceCriterion(taskID: UUID) {
        mutateDraft {
            $0.addAcceptanceCriterion(
                taskID: taskID,
                criterion: AcceptanceCriterion(statement: "")
            )
        }
    }

    func removeAcceptanceCriterion(taskID: UUID, criterionID: UUID) {
        mutateDraft {
            $0.removeAcceptanceCriterion(
                taskID: taskID,
                criterionID: criterionID
            )
        }
    }

    func addEvidenceRequirement(taskID: UUID) {
        guard let task = tasks.first(where: { $0.id == taskID }) else { return }
        let requirement = EvidenceRequirement(
            kind: .custom,
            description: "",
            coveredCriterionIDs: task.acceptanceCriteria.map(\.id)
        )
        mutateDraft {
            $0.addEvidenceRequirement(
                taskID: taskID,
                requirement: requirement
            )
        }
    }

    func removeEvidenceRequirement(taskID: UUID, requirementID: UUID) {
        mutateDraft {
            $0.removeEvidenceRequirement(
                taskID: taskID,
                requirementID: requirementID
            )
        }
    }

    func updateEvidenceKind(
        taskID: UUID,
        requirementID: UUID,
        kind: EvidenceKind
    ) {
        mutateDraft {
            $0.updateEvidenceKind(
                taskID: taskID,
                requirementID: requirementID,
                kind: kind
            )
        }
    }

    func updateEvidenceDescription(
        taskID: UUID,
        requirementID: UUID,
        description: String
    ) {
        mutateDraft {
            $0.updateEvidenceDescription(
                taskID: taskID,
                requirementID: requirementID,
                description: description
            )
        }
    }

    func setEvidenceCoverage(
        taskID: UUID,
        requirementID: UUID,
        criterionID: UUID,
        isCovered: Bool
    ) {
        mutateDraft {
            $0.setEvidenceCoverage(
                taskID: taskID,
                requirementID: requirementID,
                criterionID: criterionID,
                isCovered: isCovered
            )
        }
    }

    func setDependency(
        prerequisiteTaskID: UUID,
        dependentTaskID: UUID,
        isEnabled: Bool
    ) {
        mutateDraft {
            $0.setDependency(
                prerequisiteTaskID: prerequisiteTaskID,
                dependentTaskID: dependentTaskID,
                isEnabled: isEnabled
            )
        }
    }

    func hasDependency(
        prerequisiteTaskID: UUID,
        dependentTaskID: UUID
    ) -> Bool {
        draft?.hasDependency(
            prerequisiteTaskID: prerequisiteTaskID,
            dependentTaskID: dependentTaskID
        ) ?? false
    }

    func removeDependency(_ edge: DependencyEdge) {
        mutateDraft { $0.removeDependency(edge) }
    }

    func resolveGenerationIssue(_ issue: DeliveryPlanGenerationIssue) {
        mutateDraft { $0.resolveGenerationIssue(issue) }
    }

    private func mutateDraft(
        _ mutation: (inout DeliveryPlanReviewDraft) -> Bool
    ) {
        guard !isBusy,
              !isReadOnly,
              var updatedDraft = draft,
              mutation(&updatedDraft) else {
            return
        }
        draft = updatedDraft
        errorMessage = nil
    }

    private func apply(
        snapshot: DeliveryRunSnapshot,
        runID: UUID
    ) throws {
        guard let run = snapshot.runs.first(where: { $0.id == runID }) else {
            throw DeliveryPlanReviewPresentationError.reviewedRunMissing(runID)
        }
        guard let plan = run.plan else {
            throw DeliveryPlanReviewPresentationError.reviewedPlanMissing(runID)
        }

        self.runID = runID
        storeRevision = snapshot.storeRevision
        persistedPlan = plan
        reviewedBrief = run.brief
        repositoryIdentity = run.repositoryIdentity
        draft = DeliveryPlanReviewDraft(plan: plan)
        if plan.approval != nil {
            readOnlyReason = L10n.string("This plan is approved and cannot be edited.")
        } else if run.stoppedAt != nil {
            readOnlyReason = L10n.string("This delivery run is stopped and cannot be reviewed.")
        } else if !run.attempts.isEmpty
            || !run.executionObservations.isEmpty
            || !run.evidenceFacts.isEmpty
            || !run.pullRequests.isEmpty {
            readOnlyReason = L10n.string("Delivery facts already exist, so this plan is locked.")
        } else {
            readOnlyReason = nil
        }
        emptyStateMessage = nil
        errorMessage = nil
    }

    private func clearReview(message: String) {
        runID = nil
        storeRevision = 0
        persistedPlan = nil
        reviewedBrief = nil
        repositoryIdentity = nil
        draft = nil
        readOnlyReason = nil
        emptyStateMessage = message
    }

}
