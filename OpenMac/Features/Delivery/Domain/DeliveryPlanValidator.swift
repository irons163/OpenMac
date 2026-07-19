import Foundation

nonisolated enum DeliveryPlanValidationIssueCode: String, Equatable, Sendable {
    case invalidRevision
    case noTasks
    case taskCountOutOfRange
    case duplicateTaskID
    case emptyTaskTitle
    case emptyWorkerPrompt
    case emptyAcceptanceCriterion
    case duplicateAcceptanceCriterionID
    case emptyEvidenceRequirement
    case duplicateEvidenceRequirementID
    case unknownAcceptanceCriterionReference
    case uncoveredAcceptanceCriterion
    case missingPlanningHint
    case emptyHumanActionHint
    case unresolvedGenerationIssue
    case missingDependencyTask
    case selfDependency
    case duplicateDependency
    case cyclicDependency
    case staleApproval
}

nonisolated struct DeliveryPlanValidationIssue: Equatable, Sendable {
    let code: DeliveryPlanValidationIssueCode
    let message: String
    let taskID: UUID?
    let dependencyEdge: DependencyEdge?

    nonisolated init(
        code: DeliveryPlanValidationIssueCode,
        message: String,
        taskID: UUID? = nil,
        dependencyEdge: DependencyEdge? = nil
    ) {
        self.code = code
        self.message = message
        self.taskID = taskID
        self.dependencyEdge = dependencyEdge
    }
}

nonisolated enum DeliveryPlanValidator {
    nonisolated static func validate(_ plan: DeliveryPlan) -> [DeliveryPlanValidationIssue] {
        var issues: [DeliveryPlanValidationIssue] = []

        if plan.revision < 1 {
            issues.append(
                DeliveryPlanValidationIssue(
                    code: .invalidRevision,
                    message: "A delivery plan revision must be at least one."
                )
            )
        }

        if plan.tasks.isEmpty {
            issues.append(
                DeliveryPlanValidationIssue(
                    code: .noTasks,
                    message: "A delivery plan must contain at least one task."
                )
            )
        }

        if !(3 ... 7).contains(plan.tasks.count) {
            issues.append(
                DeliveryPlanValidationIssue(
                    code: .taskCountOutOfRange,
                    message: "A delivery plan must contain between three and seven tasks."
                )
            )
        }

        for generationIssue in plan.unresolvedGenerationBlockers {
            issues.append(
                DeliveryPlanValidationIssue(
                    code: .unresolvedGenerationIssue,
                    message: "Resolve generated plan issue at \(generationIssue.fieldPath): \(generationIssue.message)"
                )
            )
        }

        var seenTaskIDs: Set<UUID> = []
        for task in plan.tasks {
            if !seenTaskIDs.insert(task.id).inserted {
                issues.append(
                    DeliveryPlanValidationIssue(
                        code: .duplicateTaskID,
                        message: "Task IDs must be unique.",
                        taskID: task.id
                    )
                )
            }

            if isBlank(task.title) {
                issues.append(
                    DeliveryPlanValidationIssue(
                        code: .emptyTaskTitle,
                        message: "A delivery task title cannot be empty.",
                        taskID: task.id
                    )
                )
            }

            if isBlank(task.workerPrompt) {
                issues.append(
                    DeliveryPlanValidationIssue(
                        code: .emptyWorkerPrompt,
                        message: "A delivery task worker prompt cannot be empty.",
                        taskID: task.id
                    )
                )
            }

            validateAcceptanceCriteria(for: task, issues: &issues)
            validateEvidenceRequirements(for: task, issues: &issues)
            validatePlanningHints(for: task, issues: &issues)
        }

        let taskIDs = Set(plan.tasks.map(\.id))
        var seenEdges: Set<DependencyEdge> = []
        var validGraphEdges: Set<DependencyEdge> = []

        for edge in plan.dependencyEdges {
            if !seenEdges.insert(edge).inserted {
                issues.append(
                    DeliveryPlanValidationIssue(
                        code: .duplicateDependency,
                        message: "Dependency edges must be unique.",
                        dependencyEdge: edge
                    )
                )
            }

            let hasPrerequisite = taskIDs.contains(edge.prerequisiteTaskID)
            let hasDependent = taskIDs.contains(edge.dependentTaskID)
            guard hasPrerequisite, hasDependent else {
                issues.append(
                    DeliveryPlanValidationIssue(
                        code: .missingDependencyTask,
                        message: "A dependency edge references a task that is not in the plan.",
                        dependencyEdge: edge
                    )
                )
                continue
            }

            guard edge.prerequisiteTaskID != edge.dependentTaskID else {
                issues.append(
                    DeliveryPlanValidationIssue(
                        code: .selfDependency,
                        message: "A task cannot depend on itself.",
                        taskID: edge.dependentTaskID,
                        dependencyEdge: edge
                    )
                )
                continue
            }

            validGraphEdges.insert(edge)
        }

        if hasCycle(taskIDs: taskIDs, edges: validGraphEdges) {
            issues.append(
                DeliveryPlanValidationIssue(
                    code: .cyclicDependency,
                    message: "The delivery plan contains a dependency cycle."
                )
            )
        }

        if let approval = plan.approval {
            let currentFingerprint = DeliveryPlanFingerprint.make(for: plan)
            if approval.planID != plan.id
                || approval.planRevision != plan.revision
                || isBlank(approval.planFingerprint)
                || currentFingerprint == nil
                || approval.planFingerprint != currentFingerprint {
                issues.append(
                    DeliveryPlanValidationIssue(
                        code: .staleApproval,
                        message: "The approval does not match the current plan content."
                    )
                )
            }
        }

        return issues
    }

    nonisolated private static func validatePlanningHints(
        for task: DeliveryTask,
        issues: inout [DeliveryPlanValidationIssue]
    ) {
        let hasTargetHint = task.targetHints.contains { !isBlank($0) }
        let hasSchemeHint = task.schemeHints.contains { !isBlank($0) }
        if !hasTargetHint && !hasSchemeHint {
            issues.append(
                DeliveryPlanValidationIssue(
                    code: .missingPlanningHint,
                    message: "A delivery task needs at least one target or scheme hint.",
                    taskID: task.id
                )
            )
        }

        if let humanActionHint = task.humanActionHint,
           isBlank(humanActionHint) {
            issues.append(
                DeliveryPlanValidationIssue(
                    code: .emptyHumanActionHint,
                    message: "A human action hint cannot be blank when present.",
                    taskID: task.id
                )
            )
        }
    }

    nonisolated static func isValid(_ plan: DeliveryPlan) -> Bool {
        validate(plan).isEmpty
    }

    nonisolated private static func validateAcceptanceCriteria(
        for task: DeliveryTask,
        issues: inout [DeliveryPlanValidationIssue]
    ) {
        if task.acceptanceCriteria.isEmpty {
            issues.append(
                DeliveryPlanValidationIssue(
                    code: .emptyAcceptanceCriterion,
                    message: "A delivery task needs at least one acceptance criterion.",
                    taskID: task.id
                )
            )
            return
        }

        var seenIDs: Set<UUID> = []
        for criterion in task.acceptanceCriteria {
            if !seenIDs.insert(criterion.id).inserted {
                issues.append(
                    DeliveryPlanValidationIssue(
                        code: .duplicateAcceptanceCriterionID,
                        message: "Acceptance criterion IDs must be unique within a task.",
                        taskID: task.id
                    )
                )
            }
            if isBlank(criterion.statement) {
                issues.append(
                    DeliveryPlanValidationIssue(
                        code: .emptyAcceptanceCriterion,
                        message: "Acceptance criteria cannot be blank.",
                        taskID: task.id
                    )
                )
            }
        }
    }

    nonisolated private static func validateEvidenceRequirements(
        for task: DeliveryTask,
        issues: inout [DeliveryPlanValidationIssue]
    ) {
        if task.evidenceRequirements.isEmpty {
            issues.append(
                DeliveryPlanValidationIssue(
                    code: .emptyEvidenceRequirement,
                    message: "A delivery task needs at least one evidence requirement.",
                    taskID: task.id
                )
            )
            return
        }

        var seenIDs: Set<UUID> = []
        let criterionIDs = Set(task.acceptanceCriteria.map(\.id))
        var coveredCriterionIDs: Set<UUID> = []
        for requirement in task.evidenceRequirements {
            if !seenIDs.insert(requirement.id).inserted {
                issues.append(
                    DeliveryPlanValidationIssue(
                        code: .duplicateEvidenceRequirementID,
                        message: "Evidence requirement IDs must be unique within a task.",
                        taskID: task.id
                    )
                )
            }
            if isBlank(requirement.description) {
                issues.append(
                    DeliveryPlanValidationIssue(
                        code: .emptyEvidenceRequirement,
                        message: "Evidence requirements cannot be blank.",
                        taskID: task.id
                    )
                )
            }

            for criterionID in requirement.coveredCriterionIDs {
                guard criterionIDs.contains(criterionID) else {
                    issues.append(
                        DeliveryPlanValidationIssue(
                            code: .unknownAcceptanceCriterionReference,
                            message: "Evidence can cover only acceptance criteria from the same task.",
                            taskID: task.id
                        )
                    )
                    continue
                }
                coveredCriterionIDs.insert(criterionID)
            }
        }

        for criterionID in criterionIDs where !coveredCriterionIDs.contains(criterionID) {
            issues.append(
                DeliveryPlanValidationIssue(
                    code: .uncoveredAcceptanceCriterion,
                    message: "Every acceptance criterion must be covered by required evidence.",
                    taskID: task.id
                )
            )
        }
    }

    nonisolated private static func hasCycle(
        taskIDs: Set<UUID>,
        edges: Set<DependencyEdge>
    ) -> Bool {
        guard !taskIDs.isEmpty else { return false }

        var indegree = Dictionary(uniqueKeysWithValues: taskIDs.map { ($0, 0) })
        var dependentsByPrerequisite: [UUID: [UUID]] = [:]

        for edge in edges {
            indegree[edge.dependentTaskID, default: 0] += 1
            dependentsByPrerequisite[edge.prerequisiteTaskID, default: []]
                .append(edge.dependentTaskID)
        }

        var queue = indegree
            .filter { $0.value == 0 }
            .map(\.key)
        var visitedCount = 0

        while let taskID = queue.popLast() {
            visitedCount += 1
            for dependentID in dependentsByPrerequisite[taskID, default: []] {
                guard let currentIndegree = indegree[dependentID] else { continue }
                let nextIndegree = currentIndegree - 1
                indegree[dependentID] = nextIndegree
                if nextIndegree == 0 {
                    queue.append(dependentID)
                }
            }
        }

        return visitedCount != taskIDs.count
    }

    nonisolated private static func isBlank(_ value: String) -> Bool {
        value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
