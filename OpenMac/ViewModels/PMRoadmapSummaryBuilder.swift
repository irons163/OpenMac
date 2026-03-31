import Foundation

@MainActor
enum PMRoadmapSummaryBuilder {
    private static func message(_ key: String) -> String {
        L10n.string(key)
    }

    private static func message(_ key: String, _ arguments: CVarArg...) -> String {
        L10n.format(key, locale: nil, arguments: arguments)
    }

    static func buildSections<Descriptor>(
        createdTasks: [Descriptor],
        tasks: [WorkTask],
        taskID: (Descriptor) -> UUID,
        milestone: (Descriptor) -> String,
        epic: (Descriptor) -> String
    ) -> [String] {
        let statusByTaskID = Dictionary(uniqueKeysWithValues: tasks.map { ($0.id, $0.status) })
        let assignedByTaskID = Dictionary(uniqueKeysWithValues: tasks.map { ($0.id, $0.assignedAgentID) })
        let executionByTaskID: [UUID: TaskExecutionStatus] = Dictionary(
            uniqueKeysWithValues: tasks.compactMap { task in
                guard let executionStatus = task.executionRecord?.status else {
                    return nil
                }
                return (task.id, executionStatus)
            }
        )

        var sections: [String] = []
        if let overall = overallProgressSummary(
            createdTasks: createdTasks,
            statusByTaskID: statusByTaskID,
            taskID: taskID
        ) {
            sections.append(overall)
        }
        if let unassigned = unassignedSummary(
            createdTasks: createdTasks,
            assignedByTaskID: assignedByTaskID,
            taskID: taskID
        ) {
            sections.append(unassigned)
        }
        if let distribution = statusDistributionSummary(
            createdTasks: createdTasks,
            statusByTaskID: statusByTaskID,
            taskID: taskID
        ) {
            sections.append(distribution)
        }
        if let outcomes = executionOutcomeSummary(
            createdTasks: createdTasks,
            executionByTaskID: executionByTaskID,
            taskID: taskID
        ) {
            sections.append(outcomes)
        }
        if let milestoneSummary = milestoneProgressSummary(
            createdTasks: createdTasks,
            statusByTaskID: statusByTaskID,
            taskID: taskID,
            milestone: milestone
        ) {
            sections.append(milestoneSummary)
        }
        if let epicSummary = epicProgressSummary(
            createdTasks: createdTasks,
            statusByTaskID: statusByTaskID,
            taskID: taskID,
            epic: epic
        ) {
            sections.append(epicSummary)
        }
        return sections
    }

    private static func milestoneProgressSummary<Descriptor>(
        createdTasks: [Descriptor],
        statusByTaskID: [UUID: KanbanStatus],
        taskID: (Descriptor) -> UUID,
        milestone: (Descriptor) -> String
    ) -> String? {
        guard !createdTasks.isEmpty else { return nil }

        let groupedByMilestone = Dictionary(grouping: createdTasks, by: milestone)
        guard !groupedByMilestone.isEmpty else { return nil }

        let sortedMilestones = groupedByMilestone.keys.sorted {
            $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        }

        var segments: [String] = []
        segments.reserveCapacity(sortedMilestones.count)

        for currentMilestone in sortedMilestones {
            let entries = groupedByMilestone[currentMilestone] ?? []
            let total = entries.count
            guard total > 0 else { continue }

            let advanced = entries.reduce(0) { partialResult, entry in
                guard let status = statusByTaskID[taskID(entry)] else {
                    return partialResult
                }
                return partialResult + (status == .todo ? 0 : 1)
            }
            segments.append("\(message("Milestone: %@", currentMilestone)) \(advanced)/\(total)")
        }

        guard !segments.isEmpty else { return nil }
        return "\(message("Roadmap")) [\(message("Milestone"))]: \(segments.joined(separator: " | "))"
    }

    private static func epicProgressSummary<Descriptor>(
        createdTasks: [Descriptor],
        statusByTaskID: [UUID: KanbanStatus],
        taskID: (Descriptor) -> UUID,
        epic: (Descriptor) -> String
    ) -> String? {
        let tasksWithEpic = createdTasks.filter {
            !epic($0).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        guard !tasksWithEpic.isEmpty else { return nil }

        let groupedByEpic = Dictionary(grouping: tasksWithEpic) { descriptor in
            epic(descriptor).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard !groupedByEpic.isEmpty else { return nil }

        let sortedEpics = groupedByEpic.keys.sorted {
            $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        }

        var segments: [String] = []
        segments.reserveCapacity(sortedEpics.count)

        for currentEpic in sortedEpics {
            let entries = groupedByEpic[currentEpic] ?? []
            let total = entries.count
            guard total > 0 else { continue }

            let advanced = entries.reduce(0) { partialResult, entry in
                guard let status = statusByTaskID[taskID(entry)] else {
                    return partialResult
                }
                return partialResult + (status == .todo ? 0 : 1)
            }
            segments.append("\(message("Epic: %@", currentEpic)) \(advanced)/\(total)")
        }

        guard !segments.isEmpty else { return nil }
        return "\(message("Roadmap")) [\(message("Epic"))]: \(segments.joined(separator: " | "))"
    }

    private static func overallProgressSummary<Descriptor>(
        createdTasks: [Descriptor],
        statusByTaskID: [UUID: KanbanStatus],
        taskID: (Descriptor) -> UUID
    ) -> String? {
        guard !createdTasks.isEmpty else { return nil }
        let total = createdTasks.count
        guard total > 0 else { return nil }

        let advanced = createdTasks.reduce(0) { partialResult, descriptor in
            guard let status = statusByTaskID[taskID(descriptor)] else {
                return partialResult
            }
            return partialResult + (status == .todo ? 0 : 1)
        }
        let percent = Int(((Double(advanced) / Double(total)) * 100).rounded())
        return "\(message("Roadmap")) [\(message("Total"))]: \(advanced)/\(total) (\(percent)%)"
    }

    private static func statusDistributionSummary<Descriptor>(
        createdTasks: [Descriptor],
        statusByTaskID: [UUID: KanbanStatus],
        taskID: (Descriptor) -> UUID
    ) -> String? {
        guard !createdTasks.isEmpty else { return nil }
        var countsByStatus: [KanbanStatus: Int] = Dictionary(
            uniqueKeysWithValues: KanbanStatus.allCases.map { ($0, 0) }
        )

        for descriptor in createdTasks {
            guard let status = statusByTaskID[taskID(descriptor)] else { continue }
            if status == .review {
                countsByStatus[.done, default: 0] += 1
            } else {
                countsByStatus[status, default: 0] += 1
            }
        }

        let todo = countsByStatus[.todo, default: 0]
        let inProgress = countsByStatus[.inProgress, default: 0]
        let review = countsByStatus[.review, default: 0]
        let done = countsByStatus[.done, default: 0]
        return "\(message("Roadmap")) [\(message("To Do"))/\(message("In Progress"))/\(message("Review"))/\(message("Done"))]: \(todo)/\(inProgress)/\(review)/\(done)"
    }

    private static func executionOutcomeSummary<Descriptor>(
        createdTasks: [Descriptor],
        executionByTaskID: [UUID: TaskExecutionStatus],
        taskID: (Descriptor) -> UUID
    ) -> String? {
        guard !createdTasks.isEmpty else { return nil }

        var succeeded = 0
        var failed = 0
        var running = 0

        for descriptor in createdTasks {
            guard let status = executionByTaskID[taskID(descriptor)] else {
                continue
            }
            switch status {
            case .succeeded:
                succeeded += 1
            case .failed:
                failed += 1
            case .running:
                running += 1
            }
        }

        guard (succeeded + failed + running) > 0 else { return nil }
        return "\(message("Roadmap")) [\(message("Succeeded"))/\(message("Failed"))/\(message("Running"))]: \(succeeded)/\(failed)/\(running)"
    }

    private static func unassignedSummary<Descriptor>(
        createdTasks: [Descriptor],
        assignedByTaskID: [UUID: UUID?],
        taskID: (Descriptor) -> UUID
    ) -> String? {
        let total = createdTasks.count
        guard total > 0 else { return nil }
        let unassigned = createdTasks.reduce(0) { partialResult, descriptor in
            guard let assignedAgentID = assignedByTaskID[taskID(descriptor)] else {
                return partialResult + 1
            }
            return partialResult + (assignedAgentID == nil ? 1 : 0)
        }
        return "\(message("Roadmap")) [\(message("Unassigned"))]: \(unassigned)/\(total)"
    }
}
