import Foundation

nonisolated struct DeliveryPlanGraphWave: Identifiable, Equatable, Sendable {
    let number: Int
    let taskIDs: [UUID]

    nonisolated var id: Int {
        number
    }
}

nonisolated struct DeliveryPlanGraphAnalysis: Equatable, Sendable {
    let waves: [DeliveryPlanGraphWave]
    let unavailableIssueCodes: [DeliveryPlanValidationIssueCode]

    nonisolated var isAvailable: Bool {
        unavailableIssueCodes.isEmpty
    }

    nonisolated var maximumParallelTaskCount: Int? {
        guard isAvailable else { return nil }
        return waves.map(\.taskIDs.count).max() ?? 0
    }

    nonisolated func waveNumber(for taskID: UUID) -> Int? {
        guard isAvailable else { return nil }
        return waves.first(where: { $0.taskIDs.contains(taskID) })?.number
    }
}

nonisolated enum DeliveryPlanGraphAnalyzer {
    nonisolated static func analyze(_ plan: DeliveryPlan) -> DeliveryPlanGraphAnalysis {
        var issueCodes: [DeliveryPlanValidationIssueCode] = []
        var issueCodeSet: Set<DeliveryPlanValidationIssueCode> = []
        func appendIssue(_ code: DeliveryPlanValidationIssueCode) {
            guard issueCodeSet.insert(code).inserted else { return }
            issueCodes.append(code)
        }

        var taskOrder: [UUID] = []
        var taskIDs: Set<UUID> = []
        for task in plan.tasks {
            guard taskIDs.insert(task.id).inserted else {
                appendIssue(.duplicateTaskID)
                continue
            }
            taskOrder.append(task.id)
        }

        var validEdges: Set<DependencyEdge> = []
        var seenEdges: Set<DependencyEdge> = []
        for edge in plan.dependencyEdges {
            guard seenEdges.insert(edge).inserted else {
                appendIssue(.duplicateDependency)
                continue
            }
            guard taskIDs.contains(edge.prerequisiteTaskID),
                  taskIDs.contains(edge.dependentTaskID) else {
                appendIssue(.missingDependencyTask)
                continue
            }
            guard edge.prerequisiteTaskID != edge.dependentTaskID else {
                appendIssue(.selfDependency)
                continue
            }
            validEdges.insert(edge)
        }

        var indegree = Dictionary(uniqueKeysWithValues: taskOrder.map { ($0, 0) })
        var dependentsByPrerequisite: [UUID: [UUID]] = [:]
        for edge in validEdges {
            indegree[edge.dependentTaskID, default: 0] += 1
            dependentsByPrerequisite[edge.prerequisiteTaskID, default: []]
                .append(edge.dependentTaskID)
        }

        var remaining = taskIDs
        var waves: [DeliveryPlanGraphWave] = []
        while !remaining.isEmpty {
            let taskIDsInWave = taskOrder.filter {
                remaining.contains($0) && indegree[$0, default: 0] == 0
            }
            guard !taskIDsInWave.isEmpty else {
                appendIssue(.cyclicDependency)
                break
            }

            waves.append(
                DeliveryPlanGraphWave(
                    number: waves.count + 1,
                    taskIDs: taskIDsInWave
                )
            )
            for taskID in taskIDsInWave {
                remaining.remove(taskID)
                for dependentID in dependentsByPrerequisite[taskID, default: []] {
                    indegree[dependentID, default: 0] -= 1
                }
            }
        }

        guard issueCodes.isEmpty else {
            return DeliveryPlanGraphAnalysis(
                waves: [],
                unavailableIssueCodes: issueCodes
            )
        }
        return DeliveryPlanGraphAnalysis(
            waves: waves,
            unavailableIssueCodes: []
        )
    }
}
