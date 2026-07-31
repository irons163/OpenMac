import SwiftUI
import UniformTypeIdentifiers

enum DeliveryPlanReviewSceneConfiguration {
    static let windowID = "delivery-plan-review"
}

struct DeliveryPlanReviewCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandMenu(L10n.string("Delivery")) {
            Button(L10n.string("Open Delivery Control Center")) {
                openWindow(id: DeliveryControlCenterSceneConfiguration.windowID)
            }
            .keyboardShortcut("d", modifiers: [.command, .option])

            Divider()

            Button(L10n.string("Open Plan Review")) {
                openWindow(id: DeliveryPlanReviewSceneConfiguration.windowID)
            }
            .keyboardShortcut("r", modifiers: [.command, .option])

            Divider()

            Button(L10n.string("Agent Orchestrator Connection…")) {
                openWindow(
                    id: DeliveryAgentOrchestratorConnectionSceneConfiguration
                        .windowID
                )
            }
        }
    }
}

struct DeliveryPlanReviewScene: View {
    @StateObject private var model: DeliveryPlanReviewViewModel
    @State private var isChoosingFixtureRepository = false

    init(
        persistence: any DeliveryPlanReviewPersisting = FileDeliveryRunStore()
    ) {
        _model = StateObject(
            wrappedValue: DeliveryPlanReviewViewModel(persistence: persistence)
        )
    }

    var body: some View {
        Group {
            if model.isLoading || (model.isBusy && model.plan == nil) {
                ProgressView(L10n.string("Loading delivery plan…"))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if model.plan != nil {
                DeliveryPlanReviewView(
                    model: model,
                    onCreateFixtureReview: {
                        isChoosingFixtureRepository = true
                    }
                )
            } else {
                ContentUnavailableView {
                    Label(
                        L10n.string("No Plan to Review"),
                        systemImage: "doc.text.magnifyingglass"
                    )
                } description: {
                    Text(
                        model.errorMessage
                            ?? model.emptyStateMessage
                            ?? L10n.string("Generate and select a delivery plan first.")
                    )
                } actions: {
                    Button(L10n.string("Create Fixture Review…")) {
                        isChoosingFixtureRepository = true
                    }
                    Button(L10n.string("Reload")) {
                        Task { await model.reloadDiscardingLocalChanges() }
                    }
                }
            }
        }
        .frame(minWidth: 980, minHeight: 680)
        .task {
            await model.load()
        }
        .fileImporter(
            isPresented: $isChoosingFixtureRepository,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case let .success(urls):
                guard let repositoryURL = urls.first else { return }
                Task {
                    let hasAccess = repositoryURL.startAccessingSecurityScopedResource()
                    defer {
                        if hasAccess {
                            repositoryURL.stopAccessingSecurityScopedResource()
                        }
                    }
                    await model.createFixtureReview(
                        repositoryRootURL: repositoryURL
                    )
                }
            case let .failure(error):
                model.presentFixtureSelectionError(error)
            }
        }
    }
}

struct DeliveryPlanReviewView: View {
    @ObservedObject var model: DeliveryPlanReviewViewModel
    let onCreateFixtureReview: () -> Void
    @State private var selectedTaskID: UUID?
    @State private var isConfirmingReload = false
    @State private var isConfirmingNewFixture = false
    @State private var isBriefExpanded = true

    var body: some View {
        VStack(spacing: 0) {
            reviewHeader
            Divider()
            HSplitView {
                reviewSidebar
                    .frame(minWidth: 280, idealWidth: 320, maxWidth: 380)
                taskDetail
                    .frame(minWidth: 560, maxWidth: .infinity, maxHeight: .infinity)
            }
            Divider()
            reviewFooter
        }
        .navigationTitle(L10n.string("Delivery Plan Review"))
        .onAppear {
            selectFirstTaskIfNeeded()
        }
        .onChange(of: model.tasks.map(\.id)) { _, _ in
            selectFirstTaskIfNeeded()
        }
        .confirmationDialog(
            L10n.string("Discard unsaved review changes?"),
            isPresented: $isConfirmingReload,
            titleVisibility: .visible
        ) {
            Button(L10n.string("Discard and Reload"), role: .destructive) {
                Task { await model.reloadDiscardingLocalChanges() }
            }
            Button(L10n.string("Cancel"), role: .cancel) {}
        } message: {
            Text(
                L10n.string(
                    "Reloading replaces this local draft with the latest saved plan."
                )
            )
        }
        .confirmationDialog(
            L10n.string("Discard unsaved changes and create another fixture?"),
            isPresented: $isConfirmingNewFixture,
            titleVisibility: .visible
        ) {
            Button(L10n.string("Discard and Choose Repository"), role: .destructive) {
                onCreateFixtureReview()
            }
            Button(L10n.string("Cancel"), role: .cancel) {}
        } message: {
            Text(
                L10n.string(
                    "Creating another fixture selects a new review run; unsaved edits in this draft will be lost."
                )
            )
        }
    }

    private var reviewHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(L10n.string("Plan Review"))
                        .font(.title2.weight(.semibold))
                    if let plan = model.plan {
                        Text(
                            L10n.format(
                                "Plan %@ · revision %d",
                                plan.id.uuidString.prefix(8).uppercased(),
                                plan.revision
                            )
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if model.isApproved {
                    Label(L10n.string("Approved"), systemImage: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                        .font(.headline)
                } else if model.isReadOnly {
                    Label(L10n.string("Review locked"), systemImage: "lock.fill")
                        .foregroundStyle(.secondary)
                        .font(.headline)
                } else if model.validationIssues.isEmpty {
                    Label(L10n.string("Ready for approval"), systemImage: "checkmark.circle")
                        .foregroundStyle(.green)
                } else {
                    Label(
                        L10n.format("%d issues", model.validationIssues.count),
                        systemImage: "exclamationmark.triangle"
                    )
                    .foregroundStyle(.orange)
                }
            }

            if let brief = model.reviewedBrief {
                VStack(alignment: .leading, spacing: 5) {
                    DisclosureGroup(
                        isExpanded: $isBriefExpanded
                    ) {
                        ScrollView {
                            Text(brief.body)
                                .frame(
                                    maxWidth: .infinity,
                                    alignment: .leading
                                )
                                .textSelection(.enabled)
                        }
                        .frame(maxHeight: 90)
                    } label: {
                        Text(brief.title)
                            .font(.subheadline.weight(.medium))
                    }
                    Label(
                        brief.repository.rootPath,
                        systemImage: "folder"
                    )
                    HStack(spacing: 14) {
                        Label(
                            brief.repository.baseBranch,
                            systemImage: "arrow.triangle.branch"
                        )
                        if let container =
                            brief.repository.xcodeContainerRelativePath {
                            Label(container, systemImage: "shippingbox")
                        }
                        if let commit = model.repositoryIdentity?
                            .baseCommitIdentifier {
                            Label(
                                String(commit.prefix(12)),
                                systemImage: "number"
                            )
                            .help(commit)
                        }
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            }

            if let summary = model.summary {
                HStack(spacing: 10) {
                    DeliveryReviewMetric(
                        title: L10n.string("Tasks"),
                        value: "\(summary.taskCount)",
                        systemImage: "checklist"
                    )
                    DeliveryReviewMetric(
                        title: L10n.string("Waves"),
                        value: summary.isGraphFullyScheduled
                            ? "\(summary.waves.count)"
                            : L10n.string("Unavailable"),
                        systemImage: "square.stack.3d.up"
                    )
                    DeliveryReviewMetric(
                        title: L10n.string("Planned sessions"),
                        value: "\(summary.estimatedSessionCount)",
                        systemImage: "terminal"
                    )
                    DeliveryReviewMetric(
                        title: L10n.string("Peak parallel"),
                        value: summary.isGraphFullyScheduled
                            ? "\(summary.maximumParallelSessionCount)"
                            : "—",
                        systemImage: "arrow.triangle.branch"
                    )
                    DeliveryReviewMetric(
                        title: L10n.string("High risk"),
                        value: "\(summary.highRiskTaskCount)",
                        systemImage: "exclamationmark.shield",
                        tint: summary.highRiskTaskCount > 0 ? .orange : .secondary
                    )
                }
            }
        }
        .padding(18)
    }

    private var reviewSidebar: some View {
        VStack(spacing: 0) {
            HStack {
                Text(L10n.string("Tasks"))
                    .font(.headline)
                Spacer()
                Button {
                    model.addTask()
                    selectedTaskID = model.tasks.last?.id
                } label: {
                    Label(L10n.string("Add Task"), systemImage: "plus")
                }
                .labelStyle(.iconOnly)
                .disabled(model.isReadOnly || model.isBusy || model.tasks.count >= 7)
            }
            .padding(12)

            List(selection: $selectedTaskID) {
                ForEach(model.tasks) { task in
                    DeliveryReviewTaskRow(
                        task: task,
                        waveNumber: model.summary?.waveNumber(for: task.id),
                        issueCount: model.validationIssues.count {
                            $0.taskID == task.id
                        }
                    )
                    .tag(task.id)
                }
            }

            if !model.validationIssues.isEmpty {
                Divider()
                validationPanel
                    .frame(maxHeight: 190)
            }

            if let blockers = model.plan?.unresolvedGenerationBlockers,
               !blockers.isEmpty {
                Divider()
                generationBlockerPanel(blockers)
                    .frame(maxHeight: 180)
            }
        }
    }

    private var validationPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Label(
                    L10n.string("Approval blockers"),
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.headline)
                .foregroundStyle(.orange)

                ForEach(Array(model.validationIssues.enumerated()), id: \.offset) { _, issue in
                    HStack(alignment: .top, spacing: 8) {
                        Button {
                            if let taskID = issue.taskID {
                                selectedTaskID = taskID
                            }
                        } label: {
                            HStack(alignment: .top, spacing: 6) {
                                Image(systemName: "circle.fill")
                                    .font(.system(size: 5))
                                    .padding(.top, 6)
                                Text(issue.message)
                                    .multilineTextAlignment(.leading)
                                Spacer(minLength: 0)
                            }
                        }
                        .buttonStyle(.plain)
                        .disabled(issue.taskID == nil)

                        if let edge = issue.dependencyEdge {
                            Button(L10n.string("Remove Edge"), role: .destructive) {
                                model.removeDependency(edge)
                            }
                            .controlSize(.small)
                            .disabled(model.isReadOnly || model.isBusy)
                        }
                    }
                }
            }
            .padding(12)
        }
    }

    private func generationBlockerPanel(
        _ blockers: [DeliveryPlanGenerationIssue]
    ) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text(L10n.string("Generated values requiring confirmation"))
                    .font(.headline)
                ForEach(Array(blockers.enumerated()), id: \.offset) { _, blocker in
                    VStack(alignment: .leading, spacing: 5) {
                        Text(blocker.message)
                            .font(.caption)
                        HStack {
                            Text(blocker.fieldPath)
                                .font(.caption2.monospaced())
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button(L10n.string("Mark Resolved")) {
                                model.resolveGenerationIssue(blocker)
                            }
                            .controlSize(.small)
                            .disabled(model.isReadOnly || model.isBusy)
                        }
                    }
                }
            }
            .padding(12)
        }
    }

    @ViewBuilder
    private var taskDetail: some View {
        if let selectedTaskID,
           let task = model.tasks.first(where: { $0.id == selectedTaskID }) {
            taskEditor(task)
        } else {
            ContentUnavailableView(
                L10n.string("Select a Task"),
                systemImage: "checklist",
                description: Text(L10n.string("Choose a task to review its execution contract."))
            )
        }
    }

    private func taskEditor(_ task: DeliveryTask) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text(L10n.string("Task Contract"))
                        .font(.title3.weight(.semibold))
                    Spacer()
                    if !model.isReadOnly {
                        Button(role: .destructive) {
                            model.removeTask(taskID: task.id)
                        } label: {
                            Label(L10n.string("Delete Task"), systemImage: "trash")
                        }
                        .disabled(model.isBusy)
                    }
                }

                GroupBox(L10n.string("Instructions")) {
                    VStack(alignment: .leading, spacing: 10) {
                        TextField(
                            L10n.string("Task title"),
                            text: taskTitleBinding(task.id)
                        )
                        Text(L10n.string("Worker prompt"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextEditor(text: workerPromptBinding(task.id))
                            .font(.body)
                            .frame(minHeight: 110)
                            .padding(5)
                            .background(.background, in: RoundedRectangle(cornerRadius: 6))
                            .overlay {
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(.separator)
                            }
                    }
                    .padding(.top, 5)
                }

                GroupBox(L10n.string("Risk and Planning Hints")) {
                    VStack(alignment: .leading, spacing: 10) {
                        Picker(
                            L10n.string("Risk"),
                            selection: riskBinding(task.id)
                        ) {
                            ForEach(DeliveryRiskLevel.allCases, id: \.self) { risk in
                                Text(riskLabel(risk)).tag(risk)
                            }
                        }
                        .pickerStyle(.segmented)

                        LabeledContent(L10n.string("Targets")) {
                            Text(
                                task.targetHints.isEmpty
                                    ? "—"
                                    : task.targetHints.joined(separator: ", ")
                            )
                            .textSelection(.enabled)
                        }
                        LabeledContent(L10n.string("Schemes")) {
                            Text(
                                task.schemeHints.isEmpty
                                    ? "—"
                                    : task.schemeHints.joined(separator: ", ")
                            )
                            .textSelection(.enabled)
                        }
                        TextField(
                            L10n.string("Human action, if required"),
                            text: humanActionBinding(task.id)
                        )
                    }
                    .padding(.top, 5)
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(task.acceptanceCriteria) { criterion in
                            HStack(alignment: .firstTextBaseline) {
                                TextField(
                                    L10n.string("Observable acceptance criterion"),
                                    text: criterionBinding(
                                        taskID: task.id,
                                        criterionID: criterion.id
                                    )
                                )
                                Button(role: .destructive) {
                                    model.removeAcceptanceCriterion(
                                        taskID: task.id,
                                        criterionID: criterion.id
                                    )
                                } label: {
                                    Image(systemName: "minus.circle")
                                }
                                .buttonStyle(.plain)
                                .disabled(model.isReadOnly || model.isBusy)
                            }
                        }
                        Button {
                            model.addAcceptanceCriterion(taskID: task.id)
                        } label: {
                            Label(L10n.string("Add Criterion"), systemImage: "plus")
                        }
                        .disabled(model.isReadOnly || model.isBusy)
                    }
                    .padding(.top, 5)
                } label: {
                    Label(
                        L10n.string("Acceptance Criteria"),
                        systemImage: "checkmark.square"
                    )
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(task.evidenceRequirements) { requirement in
                            evidenceEditor(requirement, task: task)
                            if requirement.id != task.evidenceRequirements.last?.id {
                                Divider()
                            }
                        }
                        Button {
                            model.addEvidenceRequirement(taskID: task.id)
                        } label: {
                            Label(L10n.string("Add Evidence"), systemImage: "plus")
                        }
                        .disabled(model.isReadOnly || model.isBusy)
                    }
                    .padding(.top, 5)
                } label: {
                    Label(L10n.string("Required Evidence"), systemImage: "doc.badge.checkmark")
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        let otherTasks = model.tasks.filter { $0.id != task.id }
                        if otherTasks.isEmpty {
                            Text(L10n.string("No other tasks are available."))
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(otherTasks) { prerequisite in
                                Toggle(
                                    L10n.format("Depends on: %@", prerequisite.title),
                                    isOn: dependencyBinding(
                                        prerequisiteTaskID: prerequisite.id,
                                        dependentTaskID: task.id
                                    )
                                )
                            }
                        }
                    }
                    .padding(.top, 5)
                } label: {
                    Label(L10n.string("Typed Dependencies"), systemImage: "arrow.triangle.branch")
                }
            }
            .padding(18)
            .disabled(model.isReadOnly || model.isBusy)
        }
    }

    private func evidenceEditor(
        _ requirement: EvidenceRequirement,
        task: DeliveryTask
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Picker(
                    L10n.string("Evidence kind"),
                    selection: evidenceKindBinding(
                        taskID: task.id,
                        requirementID: requirement.id
                    )
                ) {
                    ForEach(EvidenceKind.allCases, id: \.self) { kind in
                        Text(kind.rawValue).tag(kind)
                    }
                }
                Spacer()
                Button(role: .destructive) {
                    model.removeEvidenceRequirement(
                        taskID: task.id,
                        requirementID: requirement.id
                    )
                } label: {
                    Image(systemName: "minus.circle")
                }
                .buttonStyle(.plain)
                .disabled(model.isReadOnly || model.isBusy)
            }
            TextField(
                L10n.string("Evidence description"),
                text: evidenceDescriptionBinding(
                    taskID: task.id,
                    requirementID: requirement.id
                )
            )
            if !task.acceptanceCriteria.isEmpty {
                Text(L10n.string("Covers"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(task.acceptanceCriteria) { criterion in
                    Toggle(
                        criterion.statement.isEmpty
                            ? L10n.string("Untitled criterion")
                            : criterion.statement,
                        isOn: evidenceCoverageBinding(
                            taskID: task.id,
                            requirementID: requirement.id,
                            criterionID: criterion.id
                        )
                    )
                    .controlSize(.small)
                }
            }
        }
    }

    private var reviewFooter: some View {
        HStack(spacing: 12) {
            if let errorMessage = model.errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.octagon.fill")
                    .foregroundStyle(.red)
                    .lineLimit(2)
            } else if model.hasUnsavedChanges {
                Label(L10n.string("Unsaved review changes"), systemImage: "pencil.circle")
                    .foregroundStyle(.orange)
            } else if let approval = model.plan?.approval {
                Text(
                    "\(L10n.format("Approved by %@", approval.approvedBy)) · "
                        + "\(approval.approvedAt.formatted(date: .abbreviated, time: .shortened)) · "
                        + "plan \(approval.planFingerprint.prefix(10)) · "
                        + "scope \(approval.scopeFingerprint.prefix(10))"
                )
                .foregroundStyle(.secondary)
            } else if let readOnlyReason = model.readOnlyReason {
                Label(readOnlyReason, systemImage: "lock.fill")
                    .foregroundStyle(.secondary)
            } else {
                Text(L10n.string("Approval persists locally and does not dispatch sessions."))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button(L10n.string("New Fixture Review…")) {
                if model.hasUnsavedChanges {
                    isConfirmingNewFixture = true
                } else {
                    onCreateFixtureReview()
                }
            }
            .disabled(model.isBusy)

            Button(L10n.string("Reload")) {
                if model.hasUnsavedChanges {
                    isConfirmingReload = true
                } else {
                    Task { await model.reloadDiscardingLocalChanges() }
                }
            }
            .disabled(model.isBusy)

            Button(
                model.activity == .saving
                    ? L10n.string("Saving…")
                    : L10n.string("Save Draft")
            ) {
                Task { await model.saveDraft() }
            }
            .disabled(!model.canSaveDraft)

            TextField(L10n.string("Reviewer"), text: $model.reviewerName)
                .textFieldStyle(.roundedBorder)
                .frame(width: 170)
                .disabled(model.isReadOnly || model.isBusy)

            Button(
                model.activity == .approving
                    ? L10n.string("Approving…")
                    : L10n.string("Approve Plan")
            ) {
                Task { await model.approve() }
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .disabled(!model.canApprove)
        }
        .padding(14)
    }

    private func taskTitleBinding(_ taskID: UUID) -> Binding<String> {
        Binding(
            get: {
                model.tasks.first(where: { $0.id == taskID })?.title ?? ""
            },
            set: { model.updateTaskTitle(taskID: taskID, title: $0) }
        )
    }

    private func workerPromptBinding(_ taskID: UUID) -> Binding<String> {
        Binding(
            get: {
                model.tasks.first(where: { $0.id == taskID })?.workerPrompt ?? ""
            },
            set: { model.updateWorkerPrompt(taskID: taskID, prompt: $0) }
        )
    }

    private func riskBinding(_ taskID: UUID) -> Binding<DeliveryRiskLevel> {
        Binding(
            get: {
                model.tasks.first(where: { $0.id == taskID })?.riskLevel ?? .medium
            },
            set: { model.updateRiskLevel(taskID: taskID, riskLevel: $0) }
        )
    }

    private func humanActionBinding(_ taskID: UUID) -> Binding<String> {
        Binding(
            get: {
                model.tasks.first(where: { $0.id == taskID })?.humanActionHint ?? ""
            },
            set: { model.updateHumanActionHint(taskID: taskID, hint: $0) }
        )
    }

    private func criterionBinding(
        taskID: UUID,
        criterionID: UUID
    ) -> Binding<String> {
        Binding(
            get: {
                model.tasks.first(where: { $0.id == taskID })?
                    .acceptanceCriteria.first(where: { $0.id == criterionID })?
                    .statement ?? ""
            },
            set: {
                model.updateAcceptanceCriterion(
                    taskID: taskID,
                    criterionID: criterionID,
                    statement: $0
                )
            }
        )
    }

    private func evidenceKindBinding(
        taskID: UUID,
        requirementID: UUID
    ) -> Binding<EvidenceKind> {
        Binding(
            get: {
                model.tasks.first(where: { $0.id == taskID })?
                    .evidenceRequirements.first(where: { $0.id == requirementID })?
                    .kind ?? .custom
            },
            set: {
                model.updateEvidenceKind(
                    taskID: taskID,
                    requirementID: requirementID,
                    kind: $0
                )
            }
        )
    }

    private func evidenceDescriptionBinding(
        taskID: UUID,
        requirementID: UUID
    ) -> Binding<String> {
        Binding(
            get: {
                model.tasks.first(where: { $0.id == taskID })?
                    .evidenceRequirements.first(where: { $0.id == requirementID })?
                    .description ?? ""
            },
            set: {
                model.updateEvidenceDescription(
                    taskID: taskID,
                    requirementID: requirementID,
                    description: $0
                )
            }
        )
    }

    private func evidenceCoverageBinding(
        taskID: UUID,
        requirementID: UUID,
        criterionID: UUID
    ) -> Binding<Bool> {
        Binding(
            get: {
                model.tasks.first(where: { $0.id == taskID })?
                    .evidenceRequirements.first(where: { $0.id == requirementID })?
                    .coveredCriterionIDs.contains(criterionID) ?? false
            },
            set: {
                model.setEvidenceCoverage(
                    taskID: taskID,
                    requirementID: requirementID,
                    criterionID: criterionID,
                    isCovered: $0
                )
            }
        )
    }

    private func dependencyBinding(
        prerequisiteTaskID: UUID,
        dependentTaskID: UUID
    ) -> Binding<Bool> {
        Binding(
            get: {
                model.hasDependency(
                    prerequisiteTaskID: prerequisiteTaskID,
                    dependentTaskID: dependentTaskID
                )
            },
            set: {
                model.setDependency(
                    prerequisiteTaskID: prerequisiteTaskID,
                    dependentTaskID: dependentTaskID,
                    isEnabled: $0
                )
            }
        )
    }

    private func selectFirstTaskIfNeeded() {
        let taskIDs = Set(model.tasks.map(\.id))
        if let selectedTaskID, taskIDs.contains(selectedTaskID) {
            return
        }
        selectedTaskID = model.tasks.first?.id
    }

    private func riskLabel(_ risk: DeliveryRiskLevel) -> String {
        switch risk {
        case .low:
            return L10n.string("Low")
        case .medium:
            return L10n.string("Medium")
        case .high:
            return L10n.string("High")
        }
    }
}

private struct DeliveryReviewMetric: View {
    let title: String
    let value: String
    let systemImage: String
    var tint: Color = .secondary

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.headline.monospacedDigit())
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct DeliveryReviewTaskRow: View {
    let task: DeliveryTask
    let waveNumber: Int?
    let issueCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(task.title.isEmpty ? L10n.string("Untitled task") : task.title)
                    .lineLimit(2)
                Spacer()
                Circle()
                    .fill(riskColor)
                    .frame(width: 8, height: 8)
            }
            HStack(spacing: 8) {
                if let waveNumber {
                    Text(L10n.format("Wave %d", waveNumber))
                } else {
                    Text(L10n.string("Wave unavailable"))
                }
                if issueCount > 0 {
                    Text(L10n.format("%d issues", issueCount))
                        .foregroundStyle(.orange)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    private var riskColor: Color {
        switch task.riskLevel {
        case .low:
            return .green
        case .medium:
            return .yellow
        case .high:
            return .orange
        }
    }
}
