import Combine
import Foundation

enum TaskAssigneeFilter: Equatable {
    case all
    case unassigned
    case assigned(UUID)
}

enum BoardHealthAction: Equatable {
    case autoAssignUnassignedTodo
    case openManualTriage
    case openNewAgent
    case rebalanceTodoLoad
    case increaseWIPLimit(KanbanStatus)
    case archiveDone

    var isAutoFixable: Bool {
        switch self {
        case .openManualTriage, .openNewAgent:
            return false
        case .autoAssignUnassignedTodo, .rebalanceTodoLoad, .increaseWIPLimit, .archiveDone:
            return true
        }
    }
}

struct BoardHealthRecommendation: Identifiable, Equatable {
    let action: BoardHealthAction
    let title: String
    let detail: String

    var id: String {
        switch action {
        case .autoAssignUnassignedTodo:
            return "auto-assign-unassigned-todo"
        case .openManualTriage:
            return "open-manual-triage"
        case .openNewAgent:
            return "open-new-agent"
        case .rebalanceTodoLoad:
            return "rebalance-todo-load"
        case let .increaseWIPLimit(status):
            return "increase-wip-\(status.rawValue)"
        case .archiveDone:
            return "archive-done"
        }
    }
}

final class KanbanBoardViewModel: ObservableObject {
    @Published private(set) var tasks: [WorkTask]
    @Published private(set) var lastUnassignedTaskIDs: Set<UUID> = []
    @Published private(set) var lastAssignmentReasons: [UUID: String] = [:]
    @Published private(set) var lastBoardMessage: String?
    @Published private(set) var wipLimits: [KanbanStatus: Int]
    @Published var agents: [AgentProfile]

    private let assignmentEngine: AutoAssignmentEngine
    private let boardStore: KanbanBoardStore?

    var totalTaskCount: Int { tasks.count }
    var todoTaskCount: Int { tasks.filter { $0.status == .todo }.count }
    var unassignedTodoTaskCount: Int { tasks.filter { $0.status == .todo && $0.assignedAgentID == nil }.count }
    var hasPendingManualTriage: Bool { !agents.isEmpty && unassignedTodoTaskCount > 0 }
    var doneTaskCount: Int { tasks.filter { $0.status == .done }.count }
    var overloadedAgentCount: Int { agents.filter { isAgentOverloaded($0.id) }.count }
    var boardHealthScore: Int {
        var penalty = 0
        penalty += min(30, unassignedTodoTaskCount * 10)
        penalty += min(30, overloadedAgentCount * 10)
        if wipPressurePercent(for: .inProgress) >= 100 { penalty += 10 }
        if wipPressurePercent(for: .review) >= 100 { penalty += 10 }
        if doneTaskCount > 0 { penalty += 5 }
        return max(0, 100 - penalty)
    }
    var boardHealthLabel: String {
        if boardHealthScore >= 85 { return "Excellent" }
        if boardHealthScore >= 60 { return "Watch" }
        return "Critical"
    }
    var boardHealthBreakdownText: String {
        let penalties = boardHealthPenaltyItems()
        guard !penalties.isEmpty else { return "No active penalties" }
        return penalties
            .map { "\($0.label): -\($0.points)" }
            .joined(separator: "\n")
    }
    var autoFixableHealthRecommendationCount: Int {
        healthRecommendations().filter { $0.action.isAutoFixable }.count
    }
    var hasAutoFixableHealthRecommendations: Bool {
        autoFixableHealthRecommendationCount > 0
    }

    init(
        tasks: [WorkTask],
        agents: [AgentProfile],
        wipLimits: [KanbanStatus: Int] = [.inProgress: 3, .review: 2],
        assignmentEngine: AutoAssignmentEngine = AutoAssignmentEngine(),
        boardStore: KanbanBoardStore? = nil
    ) {
        self.tasks = tasks
        self.agents = agents
        self.wipLimits = wipLimits.reduce(into: [:]) { partialResult, pair in
            partialResult[pair.key] = max(1, pair.value)
        }
        self.assignmentEngine = assignmentEngine
        self.boardStore = boardStore
    }

    func tasks(in status: KanbanStatus) -> [WorkTask] {
        tasks
            .filter { $0.status == status }
            .sorted {
                if $0.storyPoints != $1.storyPoints {
                    return $0.storyPoints > $1.storyPoints
                }
                return $0.createdAt < $1.createdAt
            }
    }

    func filteredTasks(in status: KanbanStatus, query: String, assigneeFilter: TaskAssigneeFilter) -> [WorkTask] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        return tasks(in: status).filter { task in
            let matchesQuery: Bool
            if normalizedQuery.isEmpty {
                matchesQuery = true
            } else {
                let titleMatch = task.title.lowercased().contains(normalizedQuery)
                let detailsMatch = task.details.lowercased().contains(normalizedQuery)
                let skillsMatch = task.requiredSkills.contains { $0.lowercased().contains(normalizedQuery) }
                matchesQuery = titleMatch || detailsMatch || skillsMatch
            }

            let matchesAssignee: Bool
            switch assigneeFilter {
            case .all:
                matchesAssignee = true
            case .unassigned:
                matchesAssignee = task.assignedAgentID == nil
            case let .assigned(agentID):
                matchesAssignee = task.assignedAgentID == agentID
            }

            return matchesQuery && matchesAssignee
        }
    }

    @discardableResult
    func moveTask(_ taskID: UUID, to status: KanbanStatus) -> Bool {
        guard let index = tasks.firstIndex(where: { $0.id == taskID }) else { return false }
        let sourceStatus = tasks[index].status

        guard sourceStatus != status else { return false }
        guard sourceStatus.canMove(to: status) else {
            lastBoardMessage = "Invalid move: \(sourceStatus.title) -> \(status.title)"
            return false
        }
        guard !isWIPLimitReached(for: status, excluding: taskID) else {
            let limit = wipLimits[status] ?? 0
            lastBoardMessage = "WIP limit reached for \(status.title) (\(limit))"
            return false
        }

        tasks[index].status = status

        if status == .done || status == .todo {
            tasks[index].assignedAgentID = nil
            lastAssignmentReasons[taskID] = nil
        }

        persistBoardState()
        lastBoardMessage = nil
        return true
    }

    @discardableResult
    func handleDrop(_ taskID: UUID, to status: KanbanStatus) -> Bool {
        moveTask(taskID, to: status)
    }

    func autoAssignTasks() {
        let result = assignmentEngine.assign(tasks: tasks, agents: agents)
        tasks = result.tasks
        lastUnassignedTaskIDs = result.unassignedTaskIDs
        lastAssignmentReasons = result.decisions.reduce(into: [:]) { partialResult, pair in
            partialResult[pair.key] = pair.value.reason
        }
        persistBoardState()
        lastBoardMessage = nil
    }

    @discardableResult
    func addTask(
        title: String,
        details: String,
        requiredSkillsText: String,
        storyPoints: Int = 1
    ) -> Bool {
        let skills = requiredSkillsText
            .split(separator: ",")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else {
            lastBoardMessage = "Task title is required"
            return false
        }

        tasks.append(
            WorkTask(
                title: trimmedTitle,
                details: details,
                requiredSkills: skills,
                storyPoints: storyPoints,
                status: .todo,
                assignedAgentID: nil
            )
        )
        persistBoardState()
        lastBoardMessage = nil
        return true
    }

    @discardableResult
    func updateTask(
        _ taskID: UUID,
        title: String,
        details: String,
        requiredSkillsText: String,
        storyPoints: Int
    ) -> Bool {
        guard let taskIndex = tasks.firstIndex(where: { $0.id == taskID }) else { return false }

        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else {
            lastBoardMessage = "Task title is required"
            return false
        }

        let skills = requiredSkillsText
            .split(separator: ",")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        tasks[taskIndex].title = trimmedTitle
        tasks[taskIndex].details = details
        tasks[taskIndex].requiredSkills = Set(skills.map { $0.lowercased() })
        tasks[taskIndex].storyPoints = max(1, storyPoints)

        if let agentID = tasks[taskIndex].assignedAgentID {
            guard let agent = agents.first(where: { $0.id == agentID }) else {
                tasks[taskIndex].assignedAgentID = nil
                lastAssignmentReasons[taskID] = nil
                if tasks[taskIndex].status == .todo {
                    lastUnassignedTaskIDs.insert(taskID)
                }
                persistBoardState()
                lastBoardMessage = nil
                return true
            }

            if !agent.hasSkills(for: tasks[taskIndex]) {
                tasks[taskIndex].assignedAgentID = nil
                lastAssignmentReasons[taskID] = nil
                if tasks[taskIndex].status == .todo {
                    lastUnassignedTaskIDs.insert(taskID)
                }
            }
        } else if tasks[taskIndex].status == .todo {
            lastUnassignedTaskIDs.insert(taskID)
        }

        persistBoardState()
        lastBoardMessage = nil
        return true
    }

    @discardableResult
    func removeTask(_ taskID: UUID) -> Bool {
        guard let taskIndex = tasks.firstIndex(where: { $0.id == taskID }) else { return false }
        tasks.remove(at: taskIndex)
        lastUnassignedTaskIDs.remove(taskID)
        lastAssignmentReasons[taskID] = nil
        persistBoardState()
        lastBoardMessage = nil
        return true
    }

    @discardableResult
    func unassignTask(_ taskID: UUID) -> Bool {
        guard let taskIndex = tasks.firstIndex(where: { $0.id == taskID }) else { return false }
        guard tasks[taskIndex].assignedAgentID != nil else {
            lastBoardMessage = "Task is already unassigned"
            return false
        }

        tasks[taskIndex].assignedAgentID = nil
        lastAssignmentReasons[taskID] = nil
        if tasks[taskIndex].status == .todo {
            lastUnassignedTaskIDs.insert(taskID)
        }
        persistBoardState()
        lastBoardMessage = nil
        return true
    }

    @discardableResult
    func unassignTodoTasks(for agentID: UUID) -> Int {
        var count = 0

        for index in tasks.indices where tasks[index].status == .todo && tasks[index].assignedAgentID == agentID {
            let taskID = tasks[index].id
            tasks[index].assignedAgentID = nil
            lastAssignmentReasons[taskID] = nil
            lastUnassignedTaskIDs.insert(taskID)
            count += 1
        }

        guard count > 0 else {
            lastBoardMessage = "No todo tasks assigned to selected agent"
            return 0
        }

        persistBoardState()
        lastBoardMessage = nil
        return count
    }

    @discardableResult
    func clearDoneTasks() -> Int {
        let doneTaskIDs = Set(tasks.filter { $0.status == .done }.map { $0.id })
        guard !doneTaskIDs.isEmpty else {
            lastBoardMessage = "No done tasks to archive"
            return 0
        }

        tasks.removeAll { $0.status == .done }
        for taskID in doneTaskIDs {
            lastUnassignedTaskIDs.remove(taskID)
            lastAssignmentReasons[taskID] = nil
        }

        persistBoardState()
        lastBoardMessage = nil
        return doneTaskIDs.count
    }

    @discardableResult
    func rebalanceTodoAssignments() -> Int {
        var loads = Dictionary(uniqueKeysWithValues: agents.map { ($0.id, activeTaskCount(for: $0.id)) })
        let agentsByID = Dictionary(uniqueKeysWithValues: agents.map { ($0.id, $0) })
        var movedCount = 0

        let candidateIndices = tasks.indices
            .filter { index in
                guard tasks[index].status == .todo, let assignedID = tasks[index].assignedAgentID else { return false }
                guard let agent = agentsByID[assignedID] else { return false }
                let currentLoad = loads[assignedID, default: 0]
                return currentLoad > agent.maxConcurrentTasks
            }
            .sorted { lhs, rhs in
                if tasks[lhs].storyPoints != tasks[rhs].storyPoints {
                    return tasks[lhs].storyPoints < tasks[rhs].storyPoints
                }
                return tasks[lhs].createdAt < tasks[rhs].createdAt
            }

        for index in candidateIndices {
            guard let currentAgentID = tasks[index].assignedAgentID,
                  let currentAgent = agentsByID[currentAgentID] else {
                continue
            }

            let currentLoad = loads[currentAgentID, default: 0]
            guard currentLoad > currentAgent.maxConcurrentTasks else { continue }

            let eligibleTargets = agents
                .filter { agent in
                    guard agent.id != currentAgentID else { return false }
                    guard agent.hasSkills(for: tasks[index]) else { return false }
                    return loads[agent.id, default: 0] < agent.maxConcurrentTasks
                }
                .sorted { lhs, rhs in
                    let leftLoad = loads[lhs.id, default: 0]
                    let rightLoad = loads[rhs.id, default: 0]
                    if leftLoad != rightLoad {
                        return leftLoad < rightLoad
                    }
                    return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
                }

            guard let target = eligibleTargets.first else { continue }

            tasks[index].assignedAgentID = target.id
            loads[currentAgentID, default: 0] -= 1
            loads[target.id, default: 0] += 1
            lastAssignmentReasons[tasks[index].id] = "rebalance[\(currentAgent.name)->\(target.name)] load[\(loads[target.id, default: 0])/\(target.maxConcurrentTasks)]"
            movedCount += 1
        }

        guard movedCount > 0 else {
            lastBoardMessage = "No todo rebalancing needed"
            return 0
        }

        persistBoardState()
        lastBoardMessage = nil
        return movedCount
    }

    func canRebalanceTodoAssignments() -> Bool {
        guard agents.count >= 2 else { return false }

        let loads = Dictionary(uniqueKeysWithValues: agents.map { ($0.id, activeTaskCount(for: $0.id)) })
        let agentsByID = Dictionary(uniqueKeysWithValues: agents.map { ($0.id, $0) })

        for task in tasks where task.status == .todo {
            guard let currentAgentID = task.assignedAgentID,
                  let currentAgent = agentsByID[currentAgentID] else {
                continue
            }

            let currentLoad = loads[currentAgentID, default: 0]
            guard currentLoad > currentAgent.maxConcurrentTasks else { continue }

            let hasTarget = agents.contains { agent in
                guard agent.id != currentAgentID else { return false }
                guard agent.hasSkills(for: task) else { return false }
                return loads[agent.id, default: 0] < agent.maxConcurrentTasks
            }
            if hasTarget {
                return true
            }
        }

        return false
    }

    @discardableResult
    func addAgent(
        name: String,
        skillsText: String,
        maxConcurrentTasks: Int = 3
    ) -> Bool {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            lastBoardMessage = "Agent name is required"
            return false
        }

        let skills = skillsText
            .split(separator: ",")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        agents.append(
            AgentProfile(
                name: trimmedName,
                skills: skills,
                maxConcurrentTasks: maxConcurrentTasks
            )
        )
        persistBoardState()
        lastBoardMessage = nil
        return true
    }

    @discardableResult
    func removeAgent(_ agentID: UUID) -> Bool {
        guard agents.contains(where: { $0.id == agentID }) else { return false }

        agents.removeAll { $0.id == agentID }

        for index in tasks.indices where tasks[index].assignedAgentID == agentID {
            tasks[index].assignedAgentID = nil
            lastAssignmentReasons[tasks[index].id] = nil

            if tasks[index].status == .todo {
                lastUnassignedTaskIDs.insert(tasks[index].id)
            }
        }

        persistBoardState()
        lastBoardMessage = nil
        return true
    }

    @discardableResult
    func updateAgent(
        _ agentID: UUID,
        name: String,
        skillsText: String,
        maxConcurrentTasks: Int
    ) -> Bool {
        guard let agentIndex = agents.firstIndex(where: { $0.id == agentID }) else { return false }

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            lastBoardMessage = "Agent name is required"
            return false
        }

        let normalizedCapacity = max(1, maxConcurrentTasks)
        let currentLoad = activeTaskCount(for: agentID)
        guard normalizedCapacity >= currentLoad else {
            lastBoardMessage = "Cannot set capacity below current load (\(currentLoad))"
            return false
        }

        let skills = skillsText
            .split(separator: ",")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        agents[agentIndex] = AgentProfile(
            id: agentID,
            name: trimmedName,
            skills: skills,
            maxConcurrentTasks: normalizedCapacity
        )

        for index in tasks.indices where tasks[index].assignedAgentID == agentID && tasks[index].status == .todo {
            if !agents[agentIndex].hasSkills(for: tasks[index]) {
                tasks[index].assignedAgentID = nil
                lastAssignmentReasons[tasks[index].id] = nil
                lastUnassignedTaskIDs.insert(tasks[index].id)
            }
        }

        persistBoardState()
        lastBoardMessage = nil
        return true
    }

    func activeTaskCount(for agentID: UUID) -> Int {
        tasks.filter { $0.assignedAgentID == agentID && $0.status != .done }.count
    }

    func loadRatio(for agentID: UUID) -> Double {
        guard let agent = agents.first(where: { $0.id == agentID }) else { return 0 }
        let load = activeTaskCount(for: agentID)
        return Double(load) / Double(max(1, agent.maxConcurrentTasks))
    }

    func loadPercent(for agentID: UUID) -> Int {
        Int((loadRatio(for: agentID) * 100).rounded())
    }

    func isAgentOverloaded(_ agentID: UUID) -> Bool {
        loadRatio(for: agentID) > 1.0
    }

    func wipPressurePercent(for status: KanbanStatus) -> Int {
        guard let limit = wipLimit(for: status), limit > 0 else { return 0 }
        let currentCount = tasks.filter { $0.status == status }.count
        return Int((Double(currentCount) / Double(limit) * 100).rounded())
    }

    func healthRecommendations() -> [BoardHealthRecommendation] {
        var recommendations: [BoardHealthRecommendation] = []

        if unassignedTodoTaskCount > 0 {
            if !agents.isEmpty {
                recommendations.append(
                    BoardHealthRecommendation(
                        action: .autoAssignUnassignedTodo,
                        title: "Auto-Assign Unowned To Do",
                        detail: "\(unassignedTodoTaskCount) unassigned task(s) can be dispatched automatically"
                    )
                )

                recommendations.append(
                    BoardHealthRecommendation(
                        action: .openManualTriage,
                        title: "Run Manual Triage",
                        detail: "Open triage sheet to manually assign pending To Do tasks"
                    )
                )
            } else {
                recommendations.append(
                    BoardHealthRecommendation(
                        action: .openNewAgent,
                        title: "Create First Agent",
                        detail: "Add an agent profile so pending To Do tasks can be assigned"
                    )
                )
            }
        }

        if canRebalanceTodoAssignments() {
            recommendations.append(
                BoardHealthRecommendation(
                    action: .rebalanceTodoLoad,
                    title: "Rebalance Overloaded Agents",
                    detail: "Move eligible To Do tasks away from overloaded agents"
                )
            )
        }

        if wipPressurePercent(for: .inProgress) >= 100, wipLimit(for: .inProgress) != nil {
            recommendations.append(
                BoardHealthRecommendation(
                    action: .increaseWIPLimit(.inProgress),
                    title: "Increase In Progress WIP",
                    detail: "In Progress is at or above its WIP limit"
                )
            )
        }

        if wipPressurePercent(for: .review) >= 100, wipLimit(for: .review) != nil {
            recommendations.append(
                BoardHealthRecommendation(
                    action: .increaseWIPLimit(.review),
                    title: "Increase Review WIP",
                    detail: "Review is at or above its WIP limit"
                )
            )
        }

        if doneTaskCount > 0 {
            recommendations.append(
                BoardHealthRecommendation(
                    action: .archiveDone,
                    title: "Archive Done Tasks",
                    detail: "\(doneTaskCount) completed task(s) can be archived"
                )
            )
        }

        return recommendations
    }

    @discardableResult
    func applyHealthRecommendation(_ action: BoardHealthAction) -> Bool {
        switch action {
        case .autoAssignUnassignedTodo:
            let beforeTasks = tasks
            autoAssignTasks()
            return tasks != beforeTasks || hasPendingManualTriage

        case .rebalanceTodoLoad:
            return rebalanceTodoAssignments() > 0

        case .openManualTriage:
            return !triageCandidates().isEmpty

        case .openNewAgent:
            return agents.isEmpty

        case let .increaseWIPLimit(status):
            guard let currentLimit = wipLimit(for: status) else {
                lastBoardMessage = "\(status.title) has no configured WIP limit"
                return false
            }
            return updateWIPLimit(for: status, limit: currentLimit + 1)

        case .archiveDone:
            return clearDoneTasks() > 0
        }
    }

    @discardableResult
    func applyAllHealthRecommendations() -> Int {
        let actions = healthRecommendations().map(\.action)
        var appliedCount = 0

        for action in actions where action.isAutoFixable {
            if applyHealthRecommendation(action) {
                appliedCount += 1
            }
        }

        if appliedCount > 0 {
            lastBoardMessage = "Applied \(appliedCount) health recommendation(s)"
        } else if !actions.isEmpty {
            lastBoardMessage = "No automatic fixes available for current recommendations"
        } else {
            lastBoardMessage = "Board health already stable"
        }

        return appliedCount
    }

    func agentName(for id: UUID?) -> String {
        guard let id else { return "Unassigned" }
        return agents.first(where: { $0.id == id })?.name ?? "Unknown"
    }

    func wipLimit(for status: KanbanStatus) -> Int? {
        wipLimits[status]
    }

    @discardableResult
    func updateWIPLimit(for status: KanbanStatus, limit: Int?) -> Bool {
        updateWIPLimits([status: limit])
    }

    @discardableResult
    func updateWIPLimits(_ limits: [KanbanStatus: Int?]) -> Bool {
        var candidateLimits = wipLimits

        for (status, limit) in limits {
            if let limit {
                candidateLimits[status] = max(1, limit)
            } else {
                candidateLimits[status] = nil
            }
        }

        for (status, limit) in candidateLimits {
            let currentCount = tasks.filter { $0.status == status }.count
            guard limit >= currentCount else {
                lastBoardMessage = "Cannot set \(status.title) WIP below current count (\(currentCount))"
                return false
            }
        }

        wipLimits = candidateLimits
        persistBoardState()
        lastBoardMessage = nil
        return true
    }

    func assignmentReason(for taskID: UUID) -> String? {
        lastAssignmentReasons[taskID]
    }

    func triageCandidates() -> [WorkTask] {
        tasks
            .filter { $0.status == .todo && $0.assignedAgentID == nil }
            .sorted {
                if $0.storyPoints != $1.storyPoints {
                    return $0.storyPoints > $1.storyPoints
                }
                return $0.createdAt < $1.createdAt
            }
    }

    func assignableAgents(for taskID: UUID) -> [AgentProfile] {
        guard let task = tasks.first(where: { $0.id == taskID }) else { return [] }
        guard task.status == .todo, task.assignedAgentID == nil else { return [] }

        return agents
            .filter { agent in
                agent.hasSkills(for: task) && activeTaskCount(for: agent.id) < agent.maxConcurrentTasks
            }
            .sorted { lhs, rhs in
                let leftLoad = activeTaskCount(for: lhs.id)
                let rightLoad = activeTaskCount(for: rhs.id)

                if leftLoad != rightLoad {
                    return leftLoad < rightLoad
                }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
    }

    @discardableResult
    func manuallyAssignTask(_ taskID: UUID, to agentID: UUID) -> Bool {
        guard let taskIndex = tasks.firstIndex(where: { $0.id == taskID }) else { return false }
        guard let agent = agents.first(where: { $0.id == agentID }) else { return false }

        guard tasks[taskIndex].status == .todo else {
            lastBoardMessage = "Only To Do tasks can be manually triaged"
            return false
        }
        guard tasks[taskIndex].assignedAgentID == nil else {
            lastBoardMessage = "Task is already assigned"
            return false
        }

        guard agent.hasSkills(for: tasks[taskIndex]) else {
            lastBoardMessage = "Agent \(agent.name) does not match required skills"
            return false
        }

        let currentLoad = activeTaskCount(for: agentID)
        guard currentLoad < agent.maxConcurrentTasks else {
            lastBoardMessage = "Agent \(agent.name) is at max load (\(agent.maxConcurrentTasks))"
            return false
        }

        tasks[taskIndex].assignedAgentID = agentID
        lastUnassignedTaskIDs.remove(taskID)
        lastAssignmentReasons[taskID] = "manual[\(agent.name)] load[\(currentLoad + 1)/\(agent.maxConcurrentTasks)]"
        persistBoardState()
        lastBoardMessage = nil
        return true
    }

    @discardableResult
    func bulkAssignTriageTasks() -> Int {
        let candidates = triageCandidates()
        var assignedCount = 0

        for task in candidates {
            guard let agentID = assignableAgents(for: task.id).first?.id else { continue }
            guard let taskIndex = tasks.firstIndex(where: { $0.id == task.id }) else { continue }
            guard let agent = agents.first(where: { $0.id == agentID }) else { continue }

            let currentLoad = activeTaskCount(for: agentID)
            tasks[taskIndex].assignedAgentID = agentID
            lastUnassignedTaskIDs.remove(task.id)
            lastAssignmentReasons[task.id] = "manual-bulk[\(agent.name)] load[\(currentLoad + 1)/\(agent.maxConcurrentTasks)]"
            assignedCount += 1
        }

        guard assignedCount > 0 else {
            if !candidates.isEmpty {
                lastBoardMessage = "No eligible agents available for pending triage tasks"
            }
            return 0
        }

        persistBoardState()
        lastBoardMessage = nil
        return assignedCount
    }

    private func isWIPLimitReached(for destination: KanbanStatus, excluding taskID: UUID) -> Bool {
        guard let limit = wipLimits[destination] else { return false }
        let currentCount = tasks.filter { $0.status == destination && $0.id != taskID }.count
        return currentCount >= limit
    }

    private func boardHealthPenaltyItems() -> [(label: String, points: Int)] {
        var items: [(label: String, points: Int)] = []

        let unassignedPenalty = min(30, unassignedTodoTaskCount * 10)
        if unassignedPenalty > 0 {
            items.append(("Unassigned To Do", unassignedPenalty))
        }

        let overloadedPenalty = min(30, overloadedAgentCount * 10)
        if overloadedPenalty > 0 {
            items.append(("Overloaded Agents", overloadedPenalty))
        }

        if wipPressurePercent(for: .inProgress) >= 100 {
            items.append(("In Progress WIP Pressure", 10))
        }

        if wipPressurePercent(for: .review) >= 100 {
            items.append(("Review WIP Pressure", 10))
        }

        if doneTaskCount > 0 {
            items.append(("Done Backlog", 5))
        }

        return items
    }

    private func persistBoardState() {
        guard let boardStore else { return }
        let snapshot = KanbanBoardSnapshot(tasks: tasks, agents: agents, wipLimits: wipLimits)
        try? boardStore.save(snapshot)
    }
}

extension KanbanBoardViewModel {
    static func persistentBoard(boardStore: KanbanBoardStore = FileKanbanBoardStore()) -> KanbanBoardViewModel {
        if let snapshot = try? boardStore.load() {
            return KanbanBoardViewModel(
                tasks: snapshot.tasks,
                agents: snapshot.agents,
                wipLimits: snapshot.wipLimits,
                boardStore: boardStore
            )
        }
        return demoBoard(boardStore: boardStore)
    }

    static func demoBoard(boardStore: KanbanBoardStore? = nil) -> KanbanBoardViewModel {
        let demoData = demoSeedData()
        return KanbanBoardViewModel(
            tasks: demoData.tasks,
            agents: demoData.agents,
            boardStore: boardStore
        )
    }

    private static func demoSeedData() -> (tasks: [WorkTask], agents: [AgentProfile]) {
        let designAgent = AgentProfile(
            name: "Design Agent",
            skills: ["ui", "ux", "prototype"],
            maxConcurrentTasks: 2
        )
        let frontendAgent = AgentProfile(
            name: "Frontend Agent",
            skills: ["swiftui", "ui", "animation"],
            maxConcurrentTasks: 3
        )
        let qualityAgent = AgentProfile(
            name: "QA Agent",
            skills: ["testing", "tdd", "automation"],
            maxConcurrentTasks: 2
        )

        let demoTasks = [
            WorkTask(
                title: "Plan Sprint Backlog",
                details: "Break roadmap into kanban-ready stories",
                requiredSkills: ["ux"],
                storyPoints: 2,
                status: .todo,
                assignedAgentID: nil
            ),
            WorkTask(
                title: "Build Kanban Column UI",
                details: "Create responsive macOS board columns",
                requiredSkills: ["swiftui", "ui"],
                storyPoints: 5,
                status: .inProgress,
                assignedAgentID: frontendAgent.id
            ),
            WorkTask(
                title: "Write Assignment Tests",
                details: "Cover load balancing and skill matching",
                requiredSkills: ["testing", "tdd"],
                storyPoints: 3,
                status: .review,
                assignedAgentID: qualityAgent.id
            )
        ]

        return (demoTasks, [designAgent, frontendAgent, qualityAgent])
    }
}
