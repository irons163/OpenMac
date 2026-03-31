import Foundation

struct DependencyGraphInsights: Equatable {
    let totalTaskDependencies: Int
    let externalDependencyCount: Int
    let blockedTaskCount: Int
    let criticalPathStoryPoints: Int
    let criticalPathTaskIDs: [UUID]
    let criticalPathTaskTitles: [String]
    let cycleTaskTitles: [String]
}

enum DependencyGraphInsightsUseCase {
    private struct DependencyReference {
        let normalizedTitle: String
        let displayTitle: String
    }

    private struct TaskNode {
        let task: WorkTask
        let normalizedTitle: String
        let dependencies: [DependencyReference]
    }

    static func build(tasks: [WorkTask]) -> DependencyGraphInsights {
        let activeTasks = tasks.filter { $0.status != .done }
        guard !activeTasks.isEmpty else {
            return DependencyGraphInsights(
                totalTaskDependencies: 0,
                externalDependencyCount: 0,
                blockedTaskCount: 0,
                criticalPathStoryPoints: 0,
                criticalPathTaskIDs: [],
                criticalPathTaskTitles: [],
                cycleTaskTitles: []
            )
        }

        let nodes: [UUID: TaskNode] = Dictionary(
            uniqueKeysWithValues: activeTasks.map { task in
                (
                    task.id,
                    TaskNode(
                        task: task,
                        normalizedTitle: normalizedDependencyTitle(task.title),
                        dependencies: parsedDependencyReferences(from: task.details)
                    )
                )
            }
        )
        let nodeIDs = Set(nodes.keys)
        let titleToTaskID = preferredTaskIDByNormalizedTitle(tasks: activeTasks)
        let completionByTitle = dependencyCompletionMap(tasks: tasks)

        var adjacency: [UUID: Set<UUID>] = [:]
        var indegree: [UUID: Int] = [:]
        var internalEdgeCount = 0
        var externalDependencies = Set<String>()
        var blockedTaskIDs = Set<UUID>()

        for nodeID in nodeIDs {
            indegree[nodeID] = 0
            adjacency[nodeID] = []
        }

        for node in nodes.values {
            guard !node.dependencies.isEmpty else { continue }

            var isBlocked = false
            for dependency in node.dependencies {
                guard let dependencyTaskID = titleToTaskID[dependency.normalizedTitle],
                      nodeIDs.contains(dependencyTaskID),
                      dependencyTaskID != node.task.id else {
                    externalDependencies.insert(dependency.normalizedTitle)
                    isBlocked = true
                    continue
                }

                if adjacency[dependencyTaskID]?.insert(node.task.id).inserted == true {
                    internalEdgeCount += 1
                    indegree[node.task.id, default: 0] += 1
                }

                let resolvedCompleted = completionByTitle[dependency.normalizedTitle] ?? false
                if !resolvedCompleted {
                    isBlocked = true
                }
            }

            if isBlocked {
                blockedTaskIDs.insert(node.task.id)
            }
        }

        let topological = topologicalLongestPath(
            nodeIDs: nodeIDs,
            indegree: indegree,
            adjacency: adjacency,
            storyPointsByTaskID: Dictionary(
                uniqueKeysWithValues: activeTasks.map { ($0.id, max(1, $0.storyPoints)) }
            )
        )

        let criticalPathTitles = topological.path.compactMap { nodes[$0]?.task.title }
        let cycleTitles = topological.cycleNodeIDs.compactMap { nodes[$0]?.task.title }.sorted {
            $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        }

        return DependencyGraphInsights(
            totalTaskDependencies: internalEdgeCount + externalDependencies.count,
            externalDependencyCount: externalDependencies.count,
            blockedTaskCount: blockedTaskIDs.count,
            criticalPathStoryPoints: topological.pathWeight,
            criticalPathTaskIDs: topological.path,
            criticalPathTaskTitles: criticalPathTitles,
            cycleTaskTitles: cycleTitles
        )
    }

    private static func preferredTaskIDByNormalizedTitle(tasks: [WorkTask]) -> [String: UUID] {
        var result: [String: (id: UUID, createdAt: Date)] = [:]

        for task in tasks {
            let normalizedTitle = normalizedDependencyTitle(task.title)
            guard !normalizedTitle.isEmpty else { continue }

            if let current = result[normalizedTitle] {
                if task.createdAt < current.createdAt {
                    result[normalizedTitle] = (task.id, task.createdAt)
                }
            } else {
                result[normalizedTitle] = (task.id, task.createdAt)
            }
        }

        return result.reduce(into: [String: UUID]()) { partialResult, pair in
            partialResult[pair.key] = pair.value.id
        }
    }

    private static func topologicalLongestPath(
        nodeIDs: Set<UUID>,
        indegree sourceIndegree: [UUID: Int],
        adjacency: [UUID: Set<UUID>],
        storyPointsByTaskID: [UUID: Int]
    ) -> (path: [UUID], pathWeight: Int, cycleNodeIDs: [UUID]) {
        var indegree = sourceIndegree
        var queue = Array(nodeIDs.filter { indegree[$0, default: 0] == 0 })
        var processed = Set<UUID>()
        var distance = Dictionary(
            uniqueKeysWithValues: nodeIDs.map { nodeID in
                (nodeID, storyPointsByTaskID[nodeID] ?? 1)
            }
        )
        var parent: [UUID: UUID] = [:]

        while !queue.isEmpty {
            let node = queue.removeFirst()
            processed.insert(node)

            for next in adjacency[node, default: []] {
                let candidateDistance = (distance[node] ?? 0) + (storyPointsByTaskID[next] ?? 1)
                if candidateDistance > (distance[next] ?? 0) {
                    distance[next] = candidateDistance
                    parent[next] = node
                }

                indegree[next, default: 0] -= 1
                if indegree[next, default: 0] == 0 {
                    queue.append(next)
                }
            }
        }

        let cycleNodeIDs = nodeIDs.filter { !processed.contains($0) }.sorted {
            $0.uuidString < $1.uuidString
        }
        let candidateNodes = processed.isEmpty ? Array(nodeIDs) : Array(processed)
        guard let pathEnd = candidateNodes.max(by: {
            let leftDistance = distance[$0] ?? 0
            let rightDistance = distance[$1] ?? 0
            if leftDistance == rightDistance {
                return $0.uuidString > $1.uuidString
            }
            return leftDistance < rightDistance
        }) else {
            return ([], 0, cycleNodeIDs)
        }

        var reversedPath: [UUID] = []
        var cursor: UUID? = pathEnd
        while let current = cursor {
            reversedPath.append(current)
            cursor = parent[current]
        }

        return (reversedPath.reversed(), distance[pathEnd] ?? 0, cycleNodeIDs)
    }

    private static func normalizedDependencyTitle(_ raw: String) -> String {
        raw
            .trimmingCharacters(
                in: CharacterSet.whitespacesAndNewlines.union(
                    CharacterSet(charactersIn: "\"'`•-")
                )
            )
            .lowercased()
    }

    private static func parsedDependencyReferences(from details: String) -> [DependencyReference] {
        let lines = details
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var dependencies: [DependencyReference] = []
        for line in lines {
            guard let separatorIndex = line.firstIndex(where: { $0 == ":" || $0 == "：" }) else {
                continue
            }

            let prefix = line[..<separatorIndex]
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            let matchesPrefix =
                prefix == "depends on" ||
                prefix == "dependency" ||
                prefix == "dependencies" ||
                prefix == "依賴" ||
                prefix == "依赖"
            guard matchesPrefix else { continue }

            let payload = line[line.index(after: separatorIndex)...]
                .replacingOccurrences(of: "，", with: ",")
            let parsed = payload
                .split(separator: ",")
                .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                .map { rawDependency in
                    let normalized = normalizedDependencyTitle(rawDependency)
                    return DependencyReference(
                        normalizedTitle: normalized,
                        displayTitle: rawDependency.trimmingCharacters(
                            in: CharacterSet.whitespacesAndNewlines.union(
                                CharacterSet(charactersIn: "\"'`•-")
                            )
                        )
                    )
                }
                .filter {
                    !$0.normalizedTitle.isEmpty &&
                        $0.normalizedTitle != "none" &&
                        $0.normalizedTitle != "無" &&
                        $0.normalizedTitle != "无"
                }

            dependencies.append(contentsOf: parsed)
        }

        var uniqueByNormalized: [String: String] = [:]
        for dependency in dependencies where uniqueByNormalized[dependency.normalizedTitle] == nil {
            uniqueByNormalized[dependency.normalizedTitle] = dependency.displayTitle
        }
        return uniqueByNormalized.keys.sorted().compactMap { normalizedTitle in
            guard let displayTitle = uniqueByNormalized[normalizedTitle] else { return nil }
            return DependencyReference(normalizedTitle: normalizedTitle, displayTitle: displayTitle)
        }
    }

    private static func dependencyCompletionMap(tasks: [WorkTask]) -> [String: Bool] {
        tasks.reduce(into: [String: Bool]()) { partialResult, task in
            let normalizedTitle = normalizedDependencyTitle(task.title)
            guard !normalizedTitle.isEmpty else { return }
            let existing = partialResult[normalizedTitle] ?? false
            partialResult[normalizedTitle] = existing || isDependencyCompleted(task)
        }
    }

    private static func isDependencyCompleted(_ task: WorkTask) -> Bool {
        if task.status == .review || task.status == .done {
            return true
        }
        if task.executionRecord?.status == .succeeded {
            return true
        }
        return false
    }
}
