import Foundation

struct AssignmentDecision {
    let agentID: UUID
    let score: Double
    let reason: String
}

struct AssignmentResult {
    var tasks: [WorkTask]
    var unassignedTaskIDs: Set<UUID>
    var decisions: [UUID: AssignmentDecision]
}

struct AutoAssignmentEngine {
    func assign(tasks: [WorkTask], agents: [AgentProfile]) -> AssignmentResult {
        var updatedTasks = tasks
        var workload = currentWorkload(for: tasks)
        var unassigned = Set<UUID>()
        var decisions: [UUID: AssignmentDecision] = [:]

        let candidateIndexes = updatedTasks.indices.sorted { lhs, rhs in
            let left = updatedTasks[lhs]
            let right = updatedTasks[rhs]

            if left.storyPoints != right.storyPoints {
                return left.storyPoints > right.storyPoints
            }
            return left.createdAt < right.createdAt
        }

        for index in candidateIndexes {
            guard updatedTasks[index].isAssignable else { continue }
            let task = updatedTasks[index]
            let contextTokens = tokenize("\(task.title) \(task.details)")

            let scoredCandidates = agents
                .filter {
                    $0.hasSkills(for: task)
                    && workload[$0.id, default: 0] < $0.maxConcurrentTasks
                }
                .map { agent in
                    let load = workload[agent.id, default: 0]
                    let score = score(task: task, agent: agent, currentLoad: load, contextTokens: contextTokens)
                    return (agent: agent, score: score)
                }
                .sorted {
                    if $0.score != $1.score {
                        return $0.score > $1.score
                    }

                    let leftLoad = workload[$0.agent.id, default: 0]
                    let rightLoad = workload[$1.agent.id, default: 0]

                    if leftLoad != rightLoad {
                        return leftLoad < rightLoad
                    }
                    return $0.agent.name.localizedCaseInsensitiveCompare($1.agent.name) == .orderedAscending
                }

            guard let selected = scoredCandidates.first else {
                unassigned.insert(updatedTasks[index].id)
                continue
            }

            updatedTasks[index].assignedAgentID = selected.agent.id
            workload[selected.agent.id, default: 0] += 1
            decisions[task.id] = AssignmentDecision(
                agentID: selected.agent.id,
                score: selected.score,
                reason: buildReason(
                    task: task,
                    agent: selected.agent,
                    currentLoad: workload[selected.agent.id, default: 0],
                    contextTokens: contextTokens,
                    score: selected.score
                )
            )
        }

        return AssignmentResult(tasks: updatedTasks, unassignedTaskIDs: unassigned, decisions: decisions)
    }

    func bestAgent(
        for task: WorkTask,
        among tasks: [WorkTask],
        agents: [AgentProfile]
    ) -> AssignmentDecision? {
        let workload = currentWorkload(for: tasks)
        let contextTokens = tokenize("\(task.title) \(task.details)")

        let scoredCandidates = agents
            .filter {
                $0.hasSkills(for: task)
                && workload[$0.id, default: 0] < $0.maxConcurrentTasks
            }
            .map { agent in
                let load = workload[agent.id, default: 0]
                let score = score(task: task, agent: agent, currentLoad: load, contextTokens: contextTokens)
                return (agent: agent, score: score)
            }
            .sorted {
                if $0.score != $1.score {
                    return $0.score > $1.score
                }

                let leftLoad = workload[$0.agent.id, default: 0]
                let rightLoad = workload[$1.agent.id, default: 0]

                if leftLoad != rightLoad {
                    return leftLoad < rightLoad
                }
                return $0.agent.name.localizedCaseInsensitiveCompare($1.agent.name) == .orderedAscending
            }

        guard let selected = scoredCandidates.first else { return nil }
        let projectedLoad = workload[selected.agent.id, default: 0] + 1
        return AssignmentDecision(
            agentID: selected.agent.id,
            score: selected.score,
            reason: buildReason(
                task: task,
                agent: selected.agent,
                currentLoad: projectedLoad,
                contextTokens: contextTokens,
                score: selected.score
            )
        )
    }

    private func currentWorkload(for tasks: [WorkTask]) -> [UUID: Int] {
        var workload: [UUID: Int] = [:]
        for task in tasks where task.status != .done {
            guard let agentID = task.assignedAgentID else { continue }
            workload[agentID, default: 0] += 1
        }
        return workload
    }

    private func tokenize(_ text: String) -> Set<String> {
        let lowercase = text.lowercased()
        let rawTokens = lowercase.split { character in
            !(character.isLetter || character.isNumber)
        }
        return Set(rawTokens.map(String.init))
    }

    private func score(
        task: WorkTask,
        agent: AgentProfile,
        currentLoad: Int,
        contextTokens: Set<String>
    ) -> Double {
        let loadRatio = Double(currentLoad) / Double(max(1, agent.maxConcurrentTasks))
        let contextMatchCount = Double(agent.skills.intersection(contextTokens).count)
        let remainingCapacity = Double(max(0, agent.maxConcurrentTasks - currentLoad))

        return 100
            + (contextMatchCount * 4.0)
            + (remainingCapacity * 0.5)
            - (loadRatio * 35.0)
    }

    private func buildReason(
        task: WorkTask,
        agent: AgentProfile,
        currentLoad: Int,
        contextTokens: Set<String>,
        score: Double
    ) -> String {
        let matchedRequired = task.requiredSkills.intersection(agent.skills).sorted().joined(separator: ", ")
        let contextMatches = agent.skills.intersection(contextTokens).sorted().joined(separator: ", ")

        let contextText = contextMatches.isEmpty ? "none" : contextMatches
        return "skills[\(matchedRequired)] context[\(contextText)] load[\(currentLoad)/\(agent.maxConcurrentTasks)] score[\(String(format: "%.1f", score))]"
    }
}
