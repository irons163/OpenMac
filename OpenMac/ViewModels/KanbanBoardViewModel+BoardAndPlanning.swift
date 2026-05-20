import Combine
import Foundation

extension KanbanBoardViewModel {
    func createBoard(name: String) -> Bool {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            lastBoardMessage = message("Board name is required")
            return false
        }

        if boards.contains(where: { $0.name.localizedCaseInsensitiveCompare(trimmedName) == .orderedSame }) {
            lastBoardMessage = message("Board name already exists")
            return false
        }

        syncCurrentBoardRecord()
        let board = KanbanBoardRecord(
            name: trimmedName,
            executionRealArtifactVerificationPolicy: nil
        )
        boards.append(board)
        loadBoard(board.id)
        persistBoardState()
        lastBoardMessage = nil
        return true
    }

    @discardableResult
    func switchBoard(to boardID: UUID) -> Bool {
        guard boards.contains(where: { $0.id == boardID }) else { return false }
        guard boardID != selectedBoardID else { return true }

        syncCurrentBoardRecord()
        loadBoard(boardID)
        persistBoardState()
        lastBoardMessage = nil
        return true
    }

    @discardableResult
    func renameBoard(_ boardID: UUID, to name: String) -> Bool {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            lastBoardMessage = message("Board name is required")
            return false
        }

        guard let index = boards.firstIndex(where: { $0.id == boardID }) else {
            lastBoardMessage = message("Board not found")
            return false
        }

        if boards.contains(where: {
            $0.id != boardID && $0.name.localizedCaseInsensitiveCompare(trimmedName) == .orderedSame
        }) {
            lastBoardMessage = message("Board name already exists")
            return false
        }

        syncCurrentBoardRecord()
        boards[index].name = trimmedName
        persistBoardState()
        lastBoardMessage = nil
        return true
    }

    @discardableResult
    func removeBoard(_ boardID: UUID) -> Bool {
        guard boards.count > 1 else {
            lastBoardMessage = message("At least one board is required")
            return false
        }

        guard let removeIndex = boards.firstIndex(where: { $0.id == boardID }) else {
            lastBoardMessage = message("Board not found")
            return false
        }

        syncCurrentBoardRecord()
        let wasSelectedBoard = boards[removeIndex].id == selectedBoardID
        boards.remove(at: removeIndex)

        if wasSelectedBoard {
            let fallbackIndex = min(removeIndex, boards.count - 1)
            loadBoard(boards[fallbackIndex].id)
        }

        persistBoardState()
        lastBoardMessage = nil
        return true
    }

    @discardableResult
    func duplicateBoard(_ boardID: UUID, name: String? = nil) -> Bool {
        guard let sourceIndex = boards.firstIndex(where: { $0.id == boardID }) else {
            lastBoardMessage = message("Board not found")
            return false
        }

        syncCurrentBoardRecord()
        let sourceBoard = boards[sourceIndex]

        let resolvedName: String
        if let name {
            let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedName.isEmpty else {
                lastBoardMessage = message("Board name is required")
                return false
            }
            resolvedName = trimmedName
        } else {
            resolvedName = uniqueBoardCopyName(for: sourceBoard.name)
        }

        if boards.contains(where: { $0.name.localizedCaseInsensitiveCompare(resolvedName) == .orderedSame }) {
            lastBoardMessage = message("Board name already exists")
            return false
        }

        let copiedBoard = KanbanBoardRecord(
            name: resolvedName,
            tasks: sourceBoard.tasks,
            agents: sourceBoard.agents,
            wipLimits: sourceBoard.wipLimits,
            executionRealArtifactVerificationPolicy: sourceBoard.executionRealArtifactVerificationPolicy
        )
        boards.append(copiedBoard)
        loadBoard(copiedBoard.id)
        persistBoardState()
        lastBoardMessage = nil
        return true
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
        let queryTerms = normalizedQuery
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)

        return tasks(in: status).filter { task in
            let matchesQuery: Bool
            if queryTerms.isEmpty {
                matchesQuery = true
            } else {
                let searchableValues = [
                    task.title.lowercased(),
                    task.details.lowercased(),
                    agentName(for: task.assignedAgentID).lowercased()
                ] + task.requiredSkills.map { $0.lowercased() }

                matchesQuery = queryTerms.allSatisfy { term in
                    searchableValues.contains { value in
                        value.contains(term)
                    }
                }
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

    func globalTaskSearchResults(query: String) -> [GlobalTaskSearchResult] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedQuery.isEmpty else { return [] }

        syncCurrentBoardRecord()
        let queryTerms = normalizedQuery
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)

        var results: [GlobalTaskSearchResult] = []
        for board in boards {
            let agentsByID = Dictionary(uniqueKeysWithValues: board.agents.map { ($0.id, $0.name) })
            let boardMatches: [GlobalTaskSearchResult] = board.tasks.compactMap { task -> GlobalTaskSearchResult? in
                let assigneeName: String
                if let assignedAgentID = task.assignedAgentID, let resolvedName = agentsByID[assignedAgentID] {
                    assigneeName = resolvedName
                } else {
                    assigneeName = message("Unassigned")
                }
                let searchableValues = [
                    board.name.lowercased(),
                    task.title.lowercased(),
                    task.details.lowercased(),
                    assigneeName.lowercased()
                ] + task.requiredSkills.map { $0.lowercased() }

                let matches = queryTerms.allSatisfy { term in
                    searchableValues.contains { value in value.contains(term) }
                }
                guard matches else { return nil }

                return GlobalTaskSearchResult(
                    taskID: task.id,
                    taskTitle: task.title,
                    taskDetails: task.details,
                    status: task.status,
                    boardID: board.id,
                    boardName: board.name,
                    assigneeName: assigneeName
                )
            }
            results.append(contentsOf: boardMatches)
        }

        return results.sorted { lhs, rhs in
            if lhs.boardName.localizedCaseInsensitiveCompare(rhs.boardName) != .orderedSame {
                return lhs.boardName.localizedCaseInsensitiveCompare(rhs.boardName) == .orderedAscending
            }
            return lhs.taskTitle.localizedCaseInsensitiveCompare(rhs.taskTitle) == .orderedAscending
        }
    }

    @discardableResult
    func openTask(_ taskID: UUID, in boardID: UUID) -> Bool {
        syncCurrentBoardRecord()
        guard let boardIndex = boards.firstIndex(where: { $0.id == boardID }) else {
            lastBoardMessage = message("Board not found")
            return false
        }

        guard boards[boardIndex].tasks.contains(where: { $0.id == taskID }) else {
            lastBoardMessage = message("Task not found")
            return false
        }

        if boardID != selectedBoardID {
            loadBoard(boardID)
            persistBoardState()
        }
        lastBoardMessage = nil
        return true
    }

    func workspaceExportData() -> Data? {
        syncCurrentBoardRecord()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .secondsSince1970
        do {
            return try encoder.encode(
                KanbanBoardSnapshot(
                    tasks: tasks,
                    agents: agents,
                    wipLimits: wipLimits,
                    boards: boards,
                    selectedBoardID: selectedBoardID,
                    taskTemplates: taskTemplates,
                    executionAutoRetryConfiguration: executionAutoRetryConfiguration,
                    executionCheckpoint: executionCheckpoint,
                    executionApprovalPolicy: executionApprovalPolicy,
                    taskExecutionApprovalsByTaskID: taskExecutionApprovalsByTaskID,
                    executionQuotaPolicy: executionQuotaPolicy,
                    executionQuotaUsage: executionQuotaUsage,
                    executionParallelizationPolicy: executionParallelizationPolicy,
                    gitHubPRQualityGatePolicy: gitHubPRQualityGatePolicy,
                    dagExecutionPolicy: dagExecutionPolicy,
                    executionQualitySafetyGatePolicy: executionQualitySafetyGatePolicy,
                    executionRealArtifactVerificationPolicy: executionRealArtifactVerificationDefaultPolicy,
                    mcpServerPolicy: mcpServerPolicy,
                    pmPlannerEngineMode: pmPlannerEngineMode,
                    pmPlanningPluginPolicy: pmPlanningPluginPolicy
                )
            )
        } catch {
            lastBoardMessage = message("Failed to export workspace")
            return nil
        }
    }

    func selectedBoardExportData() -> Data? {
        syncCurrentBoardRecord()
        guard let selectedBoard = boards.first(where: { $0.id == selectedBoardID }) else {
            lastBoardMessage = message("Board not found")
            return nil
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .secondsSince1970
        do {
            return try encoder.encode(
                KanbanBoardSnapshot(
                    tasks: selectedBoard.tasks,
                    agents: selectedBoard.agents,
                    wipLimits: selectedBoard.wipLimits,
                    boards: [selectedBoard],
                    selectedBoardID: selectedBoard.id,
                    taskTemplates: taskTemplates,
                    executionAutoRetryConfiguration: executionAutoRetryConfiguration,
                    executionCheckpoint: executionCheckpoint?.boardID == selectedBoard.id ? executionCheckpoint : nil,
                    executionApprovalPolicy: executionApprovalPolicy,
                    taskExecutionApprovalsByTaskID: taskExecutionApprovalsByTaskID.filter { approvalEntry in
                        selectedBoard.tasks.contains(where: { $0.id == approvalEntry.key })
                    },
                    executionQuotaPolicy: executionQuotaPolicy,
                    executionQuotaUsage: executionQuotaUsage,
                    executionParallelizationPolicy: executionParallelizationPolicy,
                    gitHubPRQualityGatePolicy: gitHubPRQualityGatePolicy,
                    dagExecutionPolicy: dagExecutionPolicy,
                    executionQualitySafetyGatePolicy: executionQualitySafetyGatePolicy,
                    executionRealArtifactVerificationPolicy: executionRealArtifactVerificationDefaultPolicy,
                    mcpServerPolicy: mcpServerPolicy,
                    pmPlannerEngineMode: pmPlannerEngineMode,
                    pmPlanningPluginPolicy: pmPlanningPluginPolicy
                )
            )
        } catch {
            lastBoardMessage = message("Failed to export board")
            return nil
        }
    }

    func executionReportDocumentForSelectedBoard() -> ExecutionReportDocument? {
        syncCurrentBoardRecord()
        guard let selectedBoard = boards.first(where: { $0.id == selectedBoardID }) else {
            lastBoardMessage = message("Board not found")
            lastBoardMessageSeverity = .warning
            return nil
        }

        let agentsByID = Dictionary(uniqueKeysWithValues: selectedBoard.agents.map { ($0.id, $0.name) })
        let entries = selectedBoard.tasks.map { task in
            let assignee: String
            if let assignedAgentID = task.assignedAgentID,
               let resolvedName = agentsByID[assignedAgentID] {
                assignee = resolvedName
            } else {
                assignee = message("Unassigned")
            }

            return ExecutionReportTaskEntry(
                id: task.id,
                title: task.title,
                status: task.status.rawValue,
                assignee: assignee,
                storyPoints: task.storyPoints,
                runCount: task.executionRecord?.runCount ?? 0,
                executionStatus: task.executionRecord?.status.rawValue,
                lastStartedAt: task.executionRecord?.lastStartedAt,
                lastFinishedAt: task.executionRecord?.lastFinishedAt,
                lastSummary: task.executionRecord?.lastOutputSummary,
                lastError: task.executionRecord?.lastError
            )
        }

        let executedTasks = entries.filter { $0.executionStatus != nil }.count
        let succeededTasks = entries.filter { $0.executionStatus == TaskExecutionStatus.succeeded.rawValue }.count
        let failedTasks = entries.filter { $0.executionStatus == TaskExecutionStatus.failed.rawValue }.count
        let runningTasks = entries.filter { $0.executionStatus == TaskExecutionStatus.running.rawValue }.count
        let notRunTasks = max(0, entries.count - executedTasks)

        return ExecutionReportDocument(
            generatedAt: Date(),
            boardID: selectedBoard.id,
            boardName: selectedBoard.name,
            totalTasks: entries.count,
            executedTasks: executedTasks,
            succeededTasks: succeededTasks,
            failedTasks: failedTasks,
            runningTasks: runningTasks,
            notRunTasks: notRunTasks,
            tasks: entries
        )
    }

    func executionReportJSONDataForSelectedBoard() -> Data? {
        guard let report = executionReportDocumentForSelectedBoard() else { return nil }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .secondsSince1970
        return try? encoder.encode(report)
    }

    func executionReportMarkdownForSelectedBoard() -> String? {
        guard let report = executionReportDocumentForSelectedBoard() else { return nil }

        var lines: [String] = []
        lines.append("# Execution Report")
        lines.append("")
        lines.append("- Generated At: \(ISO8601DateFormatter().string(from: report.generatedAt))")
        lines.append("- Board: \(report.boardName)")
        lines.append("- Total Tasks: \(report.totalTasks)")
        lines.append("- Executed: \(report.executedTasks)")
        lines.append("- Succeeded: \(report.succeededTasks)")
        lines.append("- Failed: \(report.failedTasks)")
        lines.append("- Running: \(report.runningTasks)")
        lines.append("- Not Run: \(report.notRunTasks)")
        lines.append("")
        lines.append("| Task | Status | Assignee | SP | Runs | Execution |")
        lines.append("| --- | --- | --- | ---: | ---: | --- |")
        for task in report.tasks {
            let execution = task.executionStatus ?? "not-run"
            lines.append(
                "| \(task.title.replacingOccurrences(of: "|", with: "\\|")) | \(task.status) | \(task.assignee.replacingOccurrences(of: "|", with: "\\|")) | \(task.storyPoints) | \(task.runCount) | \(execution) |"
            )
        }

        return lines.joined(separator: "\n")
    }

    func githubPRBody(
        boardName: String,
        executionReportMarkdown: String,
        dependencyInsights: DependencyGraphInsights
    ) -> String {
        var lines: [String] = []
        lines.append("## OpenMac Board Summary")
        lines.append("")
        lines.append("- Board: \(boardName)")
        lines.append("- Blocked Tasks: \(dependencyInsights.blockedTaskCount)")
        lines.append("- Dependencies: \(dependencyInsights.totalTaskDependencies) (external: \(dependencyInsights.externalDependencyCount))")
        lines.append("- Critical Path: \(dependencyInsights.criticalPathStoryPoints) SP")
        if !dependencyInsights.criticalPathTaskTitles.isEmpty {
            lines.append("- Critical Path Tasks: \(dependencyInsights.criticalPathTaskTitles.joined(separator: " -> "))")
        }
        if !dependencyInsights.cycleTaskTitles.isEmpty {
            lines.append("- Dependency Cycles: \(dependencyInsights.cycleTaskTitles.joined(separator: ", "))")
        }
        lines.append("")
        lines.append("## Execution Report")
        lines.append("")
        lines.append(executionReportMarkdown)
        return lines.joined(separator: "\n")
    }

    func failExecutionReportExport() -> Bool {
        lastBoardMessage = message("Failed to export execution report")
        lastBoardMessageSeverity = .warning
        return false
    }

    @discardableResult
    func writeExportedData(
        _ data: Data,
        to url: URL,
        fallbackFileName: String,
        successMessageKey: String,
        failureMessageKey: String,
        failureSeverity: BoardMessageSeverity? = nil
    ) -> Bool {
        do {
            try data.write(to: url, options: .atomic)
            let fileName = url.lastPathComponent.isEmpty ? fallbackFileName : url.lastPathComponent
            lastBoardMessage = message(successMessageKey, fileName)
            lastBoardMessageSeverity = .info
            return true
        } catch {
            lastBoardMessage = message(failureMessageKey)
            if let failureSeverity {
                lastBoardMessageSeverity = failureSeverity
            }
            return false
        }
    }

    @discardableResult
    func exportExecutionReportJSONForSelectedBoard(to url: URL) -> Bool {
        guard let data = executionReportJSONDataForSelectedBoard() else {
            return failExecutionReportExport()
        }
        return writeExportedData(
            data,
            to: url,
            fallbackFileName: "execution-report.json",
            successMessageKey: "Exported execution report to %@",
            failureMessageKey: "Failed to export execution report",
            failureSeverity: .warning
        )
    }

    @discardableResult
    func exportExecutionReportMarkdownForSelectedBoard(to url: URL) -> Bool {
        guard let markdown = executionReportMarkdownForSelectedBoard() else {
            return failExecutionReportExport()
        }
        guard let data = markdown.data(using: .utf8) else {
            return failExecutionReportExport()
        }
        return writeExportedData(
            data,
            to: url,
            fallbackFileName: "execution-report.md",
            successMessageKey: "Exported execution report to %@",
            failureMessageKey: "Failed to export execution report",
            failureSeverity: .warning
        )
    }

    func workspaceImportPreview(from data: Data) -> WorkspaceImportPreview? {
        guard let snapshot = decodeWorkspaceSnapshot(from: data) else {
            lastBoardMessage = message("Invalid workspace JSON")
            return nil
        }

        let importedWorkspace = importedWorkspaceBoards(from: snapshot)
        let importedBoards = importedWorkspace.boards

        let taskCount = importedBoards.reduce(0) { partialResult, board in
            partialResult + board.tasks.count
        }
        let agentCount = importedBoards.reduce(0) { partialResult, board in
            partialResult + board.agents.count
        }
        return WorkspaceImportPreview(
            boardCount: importedBoards.count,
            taskCount: taskCount,
            agentCount: agentCount
        )
    }

    func workspaceImportPreview(from url: URL) -> WorkspaceImportPreview? {
        guard let data = try? Data(contentsOf: url) else {
            lastBoardMessage = message("Failed to read workspace file")
            return nil
        }
        return workspaceImportPreview(from: data)
    }

    @discardableResult
    func exportWorkspace(to url: URL) -> Bool {
        guard let data = workspaceExportData() else { return false }
        return writeExportedData(
            data,
            to: url,
            fallbackFileName: "workspace.json",
            successMessageKey: "Exported workspace to %@",
            failureMessageKey: "Failed to write workspace file"
        )
    }

    @discardableResult
    func exportSelectedBoard(to url: URL) -> Bool {
        guard let data = selectedBoardExportData() else { return false }
        return writeExportedData(
            data,
            to: url,
            fallbackFileName: "board.json",
            successMessageKey: "Exported board to %@",
            failureMessageKey: "Failed to write board file"
        )
    }

    @discardableResult
    func importWorkspaceData(_ data: Data, strategy: WorkspaceImportStrategy = .replace) -> Bool {
        guard let snapshot = decodeWorkspaceSnapshot(from: data) else {
            lastBoardMessage = message("Invalid workspace JSON")
            return false
        }

        let importedWorkspace = importedWorkspaceBoards(from: snapshot)
        let importedBoards = importedWorkspace.boards
        let preferredSelectedBoardID = importedWorkspace.preferredSelectedBoardID

        guard !importedBoards.isEmpty else {
            lastBoardMessage = message("Workspace has no boards")
            return false
        }

        let importResult: WorkspaceImportExecutionResult
        switch strategy {
        case .replace:
            importResult = executeWorkspaceReplaceImport(
                snapshot: snapshot,
                importedBoards: importedBoards,
                preferredSelectedBoardID: preferredSelectedBoardID,
            )
        case .merge:
            importResult = executeWorkspaceMergeImport(
                snapshot: snapshot,
                importedBoards: importedBoards,
                preferredSelectedBoardID: preferredSelectedBoardID,
            )
        }

        loadBoard(importResult.resolvedSelectedBoardID)
        persistBoardState()
        lastBoardMessage = importResult.message
        lastBoardMessageSeverity = .info
        return true
    }

    @discardableResult
    func importWorkspace(from url: URL, strategy: WorkspaceImportStrategy = .replace) -> Bool {
        guard let data = try? Data(contentsOf: url) else {
            lastBoardMessage = message("Failed to read workspace file")
            return false
        }

        return importWorkspaceData(data, strategy: strategy)
    }

    @discardableResult
    func moveTask(_ taskID: UUID, to status: KanbanStatus) -> Bool {
        guard let index = tasks.firstIndex(where: { $0.id == taskID }) else { return false }
        let sourceStatus = tasks[index].status

        guard sourceStatus != status else { return false }
        guard sourceStatus.canMove(to: status) else {
            lastBoardMessage = message("Invalid move: %@ -> %@", message(sourceStatus.title), message(status.title))
            return false
        }
        guard !isWIPLimitReached(for: status, excluding: taskID) else {
            let limit = wipLimits[status] ?? 0
            lastBoardMessage = message("WIP limit reached for %@ (%d)", message(status.title), limit)
            return false
        }

        tasks[index].status = status
        if sourceStatus.previous == status,
           tasks[index].executionRecord?.status == .succeeded {
            tasks[index].executionRecord = nil
        }

        if status == .done || status == .todo {
            tasks[index].assignedAgentID = nil
            lastAssignmentReasons[taskID] = nil
        }

        if status == .review {
            triggerPMExtensionHooks(event: .reviewEntered, task: tasks[index])
        }

        persistBoardState()
        lastBoardMessage = nil
        return true
    }

    @discardableResult
    func moveTask(_ taskID: UUID, toBoard targetBoardID: UUID) -> Bool {
        guard let sourceBoardIndex = selectedBoardIndex else { return false }
        guard let targetBoardIndex = boards.firstIndex(where: { $0.id == targetBoardID }) else {
            lastBoardMessage = message("Board not found")
            return false
        }
        guard sourceBoardIndex != targetBoardIndex else {
            lastBoardMessage = message("Select a different board")
            return false
        }

        syncCurrentBoardRecord()
        guard let taskIndex = boards[sourceBoardIndex].tasks.firstIndex(where: { $0.id == taskID }) else {
            lastBoardMessage = message("Task not found")
            return false
        }

        var movedTask = boards[sourceBoardIndex].tasks.remove(at: taskIndex)
        if let assignedAgentID = movedTask.assignedAgentID,
           !boards[targetBoardIndex].agents.contains(where: { $0.id == assignedAgentID }) {
            movedTask.assignedAgentID = nil
        }
        boards[targetBoardIndex].tasks.append(movedTask)

        loadBoard(boards[sourceBoardIndex].id)
        persistBoardState()
        lastBoardMessage = nil
        return true
    }

    @discardableResult
    func copyTask(_ taskID: UUID, toBoard targetBoardID: UUID) -> Bool {
        guard let sourceBoardIndex = selectedBoardIndex else { return false }
        guard let targetBoardIndex = boards.firstIndex(where: { $0.id == targetBoardID }) else {
            lastBoardMessage = message("Board not found")
            return false
        }
        guard sourceBoardIndex != targetBoardIndex else {
            lastBoardMessage = message("Select a different board")
            return false
        }

        syncCurrentBoardRecord()
        guard let sourceTask = boards[sourceBoardIndex].tasks.first(where: { $0.id == taskID }) else {
            lastBoardMessage = message("Task not found")
            return false
        }

        var copiedTask = WorkTask(
            title: sourceTask.title,
            details: sourceTask.details,
            requiredSkills: Array(sourceTask.requiredSkills),
            storyPoints: sourceTask.storyPoints,
            status: sourceTask.status,
            assignedAgentID: sourceTask.assignedAgentID,
            deliveryContract: sourceTask.deliveryContract
        )
        if let assignedAgentID = copiedTask.assignedAgentID,
           !boards[targetBoardIndex].agents.contains(where: { $0.id == assignedAgentID }) {
            copiedTask.assignedAgentID = nil
        }
        boards[targetBoardIndex].tasks.append(copiedTask)

        loadBoard(boards[sourceBoardIndex].id)
        persistBoardState()
        lastBoardMessage = nil
        return true
    }

    @discardableResult
    func handleDrop(_ taskID: UUID, to status: KanbanStatus) -> Bool {
        moveTask(taskID, to: status)
    }

    func autoAssignTasks(allowFallbackWithoutSkillMatch: Bool = false) {
        let result = assignmentEngine.assign(
            tasks: tasks,
            agents: agents,
            allowFallbackWithoutSkillMatch: allowFallbackWithoutSkillMatch
        )
        tasks = result.tasks
        lastUnassignedTaskIDs = result.unassignedTaskIDs
        lastAssignmentReasons = result.decisions.reduce(into: [:]) { partialResult, pair in
            partialResult[pair.key] = pair.value.reason
        }
        persistBoardState()
        lastBoardMessage = nil
    }

    @discardableResult
    func autoAssignTask(
        _ taskID: UUID,
        allowFallbackWithoutSkillMatch: Bool = false
    ) -> Bool {
        guard let taskIndex = tasks.firstIndex(where: { $0.id == taskID }) else { return false }
        guard tasks[taskIndex].status == .todo else {
            lastBoardMessage = message("Only To Do tasks can be auto-assigned")
            lastBoardMessageSeverity = .warning
            return false
        }
        guard tasks[taskIndex].assignedAgentID == nil else {
            lastBoardMessage = message("Task already assigned")
            lastBoardMessageSeverity = .warning
            return false
        }

        guard let decision = assignmentEngine.bestAgent(
            for: tasks[taskIndex],
            among: tasks,
            agents: agents,
            allowFallbackWithoutSkillMatch: allowFallbackWithoutSkillMatch
        ) else {
            lastUnassignedTaskIDs.insert(taskID)
            lastBoardMessage = message("No eligible agent for task")
            lastBoardMessageSeverity = .warning
            return false
        }

        tasks[taskIndex].assignedAgentID = decision.agentID
        lastAssignmentReasons[taskID] = decision.reason
        lastUnassignedTaskIDs.remove(taskID)
        persistBoardState()
        lastBoardMessage = nil
        return true
    }

    @discardableResult
    func addTask(
        title: String,
        details: String,
        requiredSkillsText: String,
        storyPoints: Int = 1,
        deliveryContract: TaskDeliveryContract? = nil,
        autoAssign: Bool = false
    ) -> Bool {
        let skills = requiredSkillsText
            .split(separator: ",")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else {
            lastBoardMessage = message("Task title is required")
            return false
        }

        let task = WorkTask(
            title: trimmedTitle,
            details: details,
            requiredSkills: skills,
            storyPoints: storyPoints,
            status: .todo,
            assignedAgentID: nil,
            deliveryContract: (deliveryContract ?? Self.inferredDeliveryContract(
                title: trimmedTitle,
                details: details,
                requiredSkills: skills
            )).normalized
        )
        tasks.append(task)

        if autoAssign {
            if let decision = assignmentEngine.bestAgent(
                for: task,
                among: tasks,
                agents: agents
            ),
               let taskIndex = tasks.firstIndex(where: { $0.id == task.id }) {
                tasks[taskIndex].assignedAgentID = decision.agentID
                lastAssignmentReasons[task.id] = decision.reason
                lastUnassignedTaskIDs.remove(task.id)
            } else {
                lastUnassignedTaskIDs.insert(task.id)
            }
        }

        persistBoardState()
        lastBoardMessage = nil
        triggerPMExtensionHooks(event: .ticketCreated, task: task)
        return true
    }

    func taskTemplate(_ templateID: UUID) -> TaskTemplate? {
        taskTemplates.first(where: { $0.id == templateID })
    }

    static func inferredDeliveryContract(
        title: String,
        details: String,
        requiredSkills: [String]
    ) -> TaskDeliveryContract {
        let outputType = inferredDeliveryOutputType(title: title, details: details, requiredSkills: requiredSkills)
        let gateMode: TaskDeliveryGateMode
        switch outputType {
        case .app, .codeModule, .data:
            gateMode = .strict
        case .document, .image, .mixed:
            gateMode = .flexible
        }
        return TaskDeliveryContract(outputType: outputType, gateMode: gateMode)
    }

    static func inferredDeliveryOutputType(
        title: String,
        details: String,
        requiredSkills: [String]
    ) -> TaskDeliveryOutputType {
        let skillTokens = requiredSkills.joined(separator: " ")
        let lowered = "\(title) \(details) \(skillTokens)".lowercased()
        if lowered.contains("screenshot") ||
            lowered.contains("image") ||
            lowered.contains("圖") ||
            lowered.contains("圖片") ||
            lowered.contains(".png") ||
            lowered.contains(".jpg") {
            return .image
        }
        if lowered.contains("document") ||
            lowered.contains("readme") ||
            lowered.contains("spec") ||
            lowered.contains("proposal") ||
            lowered.contains("report") ||
            lowered.contains("文件") ||
            lowered.contains("說明") {
            return .document
        }
        if lowered.contains("dataset") ||
            lowered.contains("csv") ||
            lowered.contains("json") ||
            lowered.contains("etl") ||
            lowered.contains("analytics") ||
            lowered.contains("資料集") ||
            lowered.contains("數據") {
            return .data
        }
        if lowered.contains("app") ||
            lowered.contains("ios") ||
            lowered.contains("android") ||
            lowered.contains("macos") ||
            lowered.contains("swiftui") ||
            lowered.contains("uikit") ||
            lowered.contains("frontend") ||
            lowered.contains("backend") ||
            lowered.contains("api") ||
            lowered.contains("web") ||
            lowered.contains("產品") {
            return .app
        }
        if lowered.contains("module") ||
            lowered.contains("library") ||
            lowered.contains("package") ||
            lowered.contains("sdk") ||
            lowered.contains("函式庫") {
            return .codeModule
        }
        return .mixed
    }

    @discardableResult
    func addTaskTemplate(
        name: String,
        title: String,
        details: String,
        requiredSkillsText: String,
        storyPoints: Int
    ) -> Bool {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            lastBoardMessage = message("Task template name is required")
            lastBoardMessageSeverity = .warning
            return false
        }

        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else {
            lastBoardMessage = message("Task template title is required")
            lastBoardMessageSeverity = .warning
            return false
        }

        let skills = requiredSkillsText
            .split(separator: ",")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let template = TaskTemplate(
            name: trimmedName,
            title: trimmedTitle,
            details: details,
            requiredSkills: skills,
            storyPoints: storyPoints
        )
        taskTemplates.append(template)
        taskTemplates.sort { lhs, rhs in
            lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
        persistBoardState()
        lastBoardMessage = message("Added task template: %@", template.name)
        lastBoardMessageSeverity = .info
        return true
    }

    @discardableResult
    func updateTaskTemplate(
        _ templateID: UUID,
        name: String,
        title: String,
        details: String,
        requiredSkillsText: String,
        storyPoints: Int
    ) -> Bool {
        guard let index = taskTemplates.firstIndex(where: { $0.id == templateID }) else {
            lastBoardMessage = message("Task template not found")
            lastBoardMessageSeverity = .warning
            return false
        }

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            lastBoardMessage = message("Task template name is required")
            lastBoardMessageSeverity = .warning
            return false
        }
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else {
            lastBoardMessage = message("Task template title is required")
            lastBoardMessageSeverity = .warning
            return false
        }

        let skills = requiredSkillsText
            .split(separator: ",")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        taskTemplates[index].name = trimmedName
        taskTemplates[index].title = trimmedTitle
        taskTemplates[index].details = details.trimmingCharacters(in: .whitespacesAndNewlines)
        taskTemplates[index].requiredSkills = Array(Set(skills.map { $0.lowercased() })).sorted()
        taskTemplates[index].storyPoints = max(1, min(13, storyPoints))
        taskTemplates.sort { lhs, rhs in
            lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
        persistBoardState()
        lastBoardMessage = message("Updated task template: %@", trimmedName)
        lastBoardMessageSeverity = .info
        return true
    }

    @discardableResult
    func removeTaskTemplate(_ templateID: UUID) -> Bool {
        guard let index = taskTemplates.firstIndex(where: { $0.id == templateID }) else {
            lastBoardMessage = message("Task template not found")
            lastBoardMessageSeverity = .warning
            return false
        }
        let removedName = taskTemplates[index].name
        taskTemplates.remove(at: index)
        persistBoardState()
        lastBoardMessage = message("Deleted task template: %@", removedName)
        lastBoardMessageSeverity = .info
        return true
    }

    @discardableResult
    func createTask(
        fromTemplate templateID: UUID,
        autoAssign: Bool = false
    ) -> Bool {
        guard let template = taskTemplate(templateID) else {
            lastBoardMessage = message("Task template not found")
            lastBoardMessageSeverity = .warning
            return false
        }
        return addTask(
            title: template.title,
            details: template.details,
            requiredSkillsText: template.requiredSkillsText,
            storyPoints: template.storyPoints,
            autoAssign: autoAssign
        )
    }

    func updateExecutionAutoRetryConfiguration(
        isEnabled: Bool,
        maxRetryCount: Int,
        backoffSeconds: Double,
        retryableErrorTypes: Set<RetryableExecutionErrorType>
    ) {
        executionAutoRetryConfiguration = ExecutionAutoRetryConfiguration(
            isEnabled: isEnabled,
            maxRetryCount: maxRetryCount,
            backoffSeconds: backoffSeconds,
            retryableErrorTypes: retryableErrorTypes
        )
        persistBoardState()
        lastBoardMessage = message("Updated execution auto-retry settings")
        lastBoardMessageSeverity = .info
    }

    func previewProjectPlan(
        projectName: String,
        projectBrief: String
    ) -> PMProjectPlan? {
        let trimmedBrief = projectBrief.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedBrief.isEmpty else {
            lastBoardMessage = message("Project brief is required")
            lastBoardMessageSeverity = .warning
            return nil
        }

        let generatedPlan: PMProjectPlan?
        if let configurablePlanner = projectPlanner as? any ConfigurableProjectPlanning {
            generatedPlan = configurablePlanner.generatePlan(
                projectName: projectName,
                projectBrief: trimmedBrief,
                availableAgents: agents,
                mode: pmPlannerEngineMode,
                pluginPolicy: pmPlanningPluginPolicy
            )
        } else {
            generatedPlan = projectPlanner.generatePlan(
                projectName: projectName,
                projectBrief: trimmedBrief,
                availableAgents: agents
            )
        }

        guard let plan = generatedPlan,
            !plan.tickets.isEmpty else {
            lastBoardMessage = message("PM planner could not generate actionable tickets")
            lastBoardMessageSeverity = .warning
            return nil
        }

        lastBoardMessage = nil
        return plan
    }

    func runPMBrainstormRoundInBackground(
        projectName: String,
        projectBrief: String,
        focus: String,
        previousTranscript: String,
        onProgress: @escaping (_ update: String) -> Void,
        completion: @escaping (_ output: String?, _ errorMessage: String?) -> Void
    ) {
        let trimmedBrief = projectBrief.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedBrief.isEmpty else {
            lastBoardMessage = message("Project brief is required")
            lastBoardMessageSeverity = .warning
            completion(nil, message("PM brainstorm requires a non-empty project brief"))
            return
        }

        let resolvedProjectName = {
            let trimmedName = projectName.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmedName.isEmpty ? selectedBoardName : trimmedName
        }()
        let agent = preferredPMBrainstormAgent()
        let brainstormTask = pmBrainstormTask(
            projectName: resolvedProjectName,
            projectBrief: trimmedBrief,
            focus: focus,
            previousTranscript: previousTranscript,
            agent: agent
        )

        runOnBackground {
            let outcome = self.executeTaskWithBoardScopedProjectsDirectory(
                task: brainstormTask,
                agent: agent
            ) { update in
                self.runOnMain {
                    onProgress(update)
                }
            }

            self.runOnMain {
                switch outcome {
                case let .success(summary):
                    self.lastBoardMessage = self.message("PM brainstorm completed with %@", agent.name)
                    self.lastBoardMessageSeverity = .info
                    completion(summary, nil)
                case let .failure(errorMessage):
                    self.lastBoardMessage = self.message("PM brainstorm failed: %@", errorMessage)
                    self.lastBoardMessageSeverity = .warning
                    completion(nil, errorMessage)
                }
            }
        }
    }

    func previewProjectBlueprint(
        projectName: String,
        projectBrief: String
    ) -> PMProjectBlueprint? {
        let trimmedBrief = projectBrief.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedBrief.isEmpty else {
            lastBoardMessage = message("Project brief is required")
            lastBoardMessageSeverity = .warning
            return nil
        }

        let generatedBlueprint: PMProjectBlueprint?
        if let configurablePlanner = projectPlanner as? any ConfigurableProjectPlanning {
            generatedBlueprint = configurablePlanner.generateBlueprint(
                projectName: projectName,
                projectBrief: trimmedBrief,
                availableAgents: agents,
                mode: pmPlannerEngineMode,
                pluginPolicy: pmPlanningPluginPolicy
            )
        } else if let blueprintPlanner = projectPlanner as? any ProjectBlueprintPlanning {
            generatedBlueprint = blueprintPlanner.generateBlueprint(
                projectName: projectName,
                projectBrief: trimmedBrief,
                availableAgents: agents
            )
        } else {
            generatedBlueprint = nil
        }

        guard let blueprint = generatedBlueprint,
              !blueprint.tickets.isEmpty else {
            lastBoardMessage = message("PM planner could not generate actionable tickets")
            lastBoardMessageSeverity = .warning
            return nil
        }

        lastBoardMessage = nil
        return blueprint
    }

    func preferredPMBrainstormAgent() -> AgentProfile {
        let prioritizedSkills: Set<String> = ["planning", "research", "product", "architecture", "analysis", "pm"]
        let runtimeAgents = agents.filter { resolvedPMBrainstormRuntimeProfile(for: $0).provider == .openAICompatible }

        if let prioritizedAgent = runtimeAgents.first(where: { !$0.skills.isDisjoint(with: prioritizedSkills) }) {
            return resolvingPMBrainstormRuntime(for: prioritizedAgent)
        }
        if let runtimeAgent = runtimeAgents.first {
            return resolvingPMBrainstormRuntime(for: runtimeAgent)
        }
        if let firstAgent = agents.first {
            return resolvingPMBrainstormRuntime(for: firstAgent)
        }
        return AgentProfile(
            name: message("PM Brainstorm Agent"),
            skills: ["planning", "research"],
            maxConcurrentTasks: 1,
            runtimeProfile: .defaultCodexBridge
        )
    }

    func resolvingPMBrainstormRuntime(for agent: AgentProfile) -> AgentProfile {
        AgentProfile(
            id: agent.id,
            name: agent.name,
            skills: Array(agent.skills),
            maxConcurrentTasks: agent.maxConcurrentTasks,
            runtimeProfile: resolvedPMBrainstormRuntimeProfile(for: agent)
        )
    }

    func resolvedPMBrainstormRuntimeProfile(for agent: AgentProfile) -> AgentRuntimeProfile {
        agent.runtimeProfile ?? .defaultCodexBridge
    }

    func pmBrainstormTask(
        projectName: String,
        projectBrief: String,
        focus: String,
        previousTranscript: String,
        agent: AgentProfile
    ) -> WorkTask {
        let trimmedFocus = focus.trimmingCharacters(in: .whitespacesAndNewlines)
        let recentTranscript = previousTranscript
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .suffix(4_000)
        let details = """
        You are OpenMac's built-in brainstorm extension.
        Help refine this product brief into an execution-ready PM input.

        Project: \(projectName)
        Current brief:
        \(projectBrief)

        Focus:
        \(trimmedFocus.isEmpty ? "General product + delivery brainstorming." : trimmedFocus)

        Prior brainstorm transcript (latest context):
        \(recentTranscript.isEmpty ? "(none)" : recentTranscript)

        Return plain text using EXACT tags:
        [UPDATED_BRIEF]
        ...
        [/UPDATED_BRIEF]
        [DECISIONS]
        - ...
        [/DECISIONS]
        [OPEN_QUESTIONS]
        - ...
        [/OPEN_QUESTIONS]
        [NEXT_EXPERIMENTS]
        - ...
        [/NEXT_EXPERIMENTS]

        Rules:
        - Keep UPDATED_BRIEF concise and directly actionable.
        - Preserve user intent and avoid unnecessary scope expansion.
        - Output only those tagged sections.
        """

        return WorkTask(
            title: message("PM Brainstorm: %@", projectName),
            details: details,
            requiredSkills: ["planning", "research"],
            storyPoints: 1,
            status: .todo,
            assignedAgentID: agent.id
        )
    }

    func projectBlueprintExportData(
        projectName: String,
        projectBrief: String
    ) -> Data? {
        guard let blueprint = previewProjectBlueprint(
            projectName: projectName,
            projectBrief: projectBrief
        ) else {
            return nil
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .secondsSince1970
        do {
            return try encoder.encode(blueprint)
        } catch {
            lastBoardMessage = message("Failed to export blueprint")
            lastBoardMessageSeverity = .warning
            return nil
        }
    }

    @discardableResult
    func addPlannedTickets(
        _ plannedTickets: [PMPlannedTicket],
        autoAssign: Bool,
        deliveryContract: TaskDeliveryContract = .defaultContract,
        generateAcceptanceE2ETasks: Bool = false
    ) -> Int {
        let normalizedTickets = plannedTickets.compactMap(Self.normalizedPlannedTicket(from:))
        guard !normalizedTickets.isEmpty else {
            lastBoardMessage = message("PM planner could not generate actionable tickets")
            lastBoardMessageSeverity = .warning
            return 0
        }
        let createdTaskDescriptors = addNormalizedPlannedTickets(
            normalizedTickets,
            autoAssign: autoAssign,
            deliveryContract: deliveryContract
        )
        if generateAcceptanceE2ETasks {
            let sourceTaskIDs = Set(createdTaskDescriptors.map(\.taskID))
            let createdAcceptanceTasks = createAcceptanceE2ETasks(
                autoAssign: autoAssign,
                sourceTaskIDs: sourceTaskIDs,
                updateBoardMessage: false
            )
            lastBoardMessage = message(
                "PM planner created %d ticket(s) + %d acceptance E2E task(s)",
                createdTaskDescriptors.count,
                createdAcceptanceTasks
            )
            lastBoardMessageSeverity = .info
        }
        return createdTaskDescriptors.count
    }

    func addNormalizedPlannedTickets(
        _ normalizedTickets: [PMPlannedTicket],
        autoAssign: Bool,
        deliveryContract: TaskDeliveryContract = .defaultContract
    ) -> [PMCreatedTaskDescriptor] {
        var createdTasks: [PMCreatedTaskDescriptor] = []
        createdTasks.reserveCapacity(normalizedTickets.count)
        let resolvedDeliveryContract = deliveryContract.normalized

        for plannedTicket in normalizedTickets {
            let task = WorkTask(
                title: plannedTicket.title,
                details: Self.planningMetadataAugmentedDetails(for: plannedTicket),
                requiredSkills: plannedTicket.requiredSkills,
                storyPoints: plannedTicket.storyPoints,
                status: .todo,
                assignedAgentID: nil,
                deliveryContract: resolvedDeliveryContract
            )
            tasks.append(task)
            let milestone = plannedTicket.milestone.trimmingCharacters(in: .whitespacesAndNewlines)
            let resolvedMilestone = milestone.isEmpty ? message("Unscheduled") : milestone
            let epic = plannedTicket.epic.trimmingCharacters(in: .whitespacesAndNewlines)
            createdTasks.append(
                PMCreatedTaskDescriptor(
                    taskID: task.id,
                    milestone: resolvedMilestone,
                    epic: epic
                )
            )
            lastUnassignedTaskIDs.insert(task.id)
            lastAssignmentReasons[task.id] = nil
        }

        if autoAssign {
            for createdTask in createdTasks {
                let taskID = createdTask.taskID
                guard let taskIndex = tasks.firstIndex(where: { $0.id == taskID }) else {
                    continue
                }
                guard tasks[taskIndex].assignedAgentID == nil else {
                    continue
                }

                if let decision = assignmentEngine.bestAgent(
                    for: tasks[taskIndex],
                    among: tasks,
                    agents: agents
                ) {
                    tasks[taskIndex].assignedAgentID = decision.agentID
                    lastAssignmentReasons[taskID] = decision.reason
                    lastUnassignedTaskIDs.remove(taskID)
                }
            }
        }

        for createdTask in createdTasks {
            if let task = tasks.first(where: { $0.id == createdTask.taskID }) {
                triggerPMExtensionHooks(event: .ticketCreated, task: task)
            }
        }

        persistBoardState()
        lastBoardMessage = message("PM planner created %d ticket(s)", createdTasks.count)
        lastBoardMessageSeverity = .info
        return createdTasks
    }

    @discardableResult
    func createAcceptanceE2ETasks(
        autoAssign: Bool = true,
        sourceTaskIDs: Set<UUID>? = nil,
        updateBoardMessage: Bool = true
    ) -> Int {
        let normalizedExistingTitles = Set(tasks.map { $0.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() })
        var generatedTasks: [WorkTask] = []
        generatedTasks.reserveCapacity(tasks.count)

        for sourceTask in tasks {
            if let sourceTaskIDs, !sourceTaskIDs.contains(sourceTask.id) {
                continue
            }

            let sourceTitle = sourceTask.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !sourceTitle.isEmpty else { continue }
            guard !sourceTitle.localizedCaseInsensitiveContains("e2e verify ·") else { continue }

            let acceptanceCriteria = Self.acceptanceCriteriaLines(from: sourceTask.details)
            guard !acceptanceCriteria.isEmpty else { continue }

            let generatedTitle = "E2E Verify · \(sourceTitle)"
            guard !normalizedExistingTitles.contains(generatedTitle.lowercased()) else { continue }
            guard !generatedTasks.contains(where: { $0.title.localizedCaseInsensitiveCompare(generatedTitle) == .orderedSame }) else {
                continue
            }

            let generatedDetails = Self.acceptanceE2EDetails(
                sourceTitle: sourceTitle,
                acceptanceCriteria: acceptanceCriteria
            )
            let qaBaselineSkills: Set<String> = ["qa", "testing"]
            let requiredSkills = qaBaselineSkills.union(sourceTask.requiredSkills.intersection(qaBaselineSkills))
            let generatedTask = WorkTask(
                title: generatedTitle,
                details: generatedDetails,
                requiredSkills: requiredSkills.sorted(),
                storyPoints: max(1, min(5, max(1, sourceTask.storyPoints / 2))),
                status: .todo,
                assignedAgentID: nil,
                deliveryContract: TaskDeliveryContract(
                    outputType: .codeModule,
                    gateMode: .strict
                )
            )
            generatedTasks.append(generatedTask)
        }

        guard !generatedTasks.isEmpty else {
            if updateBoardMessage {
                lastBoardMessage = message("No acceptance criteria found for E2E task generation")
                lastBoardMessageSeverity = .warning
            }
            return 0
        }

        for generatedTask in generatedTasks {
            tasks.append(generatedTask)
            lastUnassignedTaskIDs.insert(generatedTask.id)
            lastAssignmentReasons[generatedTask.id] = nil
        }

        if autoAssign {
            for generatedTask in generatedTasks {
                guard let taskIndex = tasks.firstIndex(where: { $0.id == generatedTask.id }) else { continue }
                if let decision = assignmentEngine.bestAgent(
                    for: tasks[taskIndex],
                    among: tasks,
                    agents: agents
                ) {
                    tasks[taskIndex].assignedAgentID = decision.agentID
                    lastAssignmentReasons[generatedTask.id] = decision.reason
                    lastUnassignedTaskIDs.remove(generatedTask.id)
                }
            }
        }

        persistBoardState()
        if updateBoardMessage {
            lastBoardMessage = message("Created %d acceptance E2E task(s)", generatedTasks.count)
            lastBoardMessageSeverity = .info
        }
        return generatedTasks.count
    }

    @discardableResult
    func createMissingAgentsForPlannedTickets(
        _ plannedTickets: [PMPlannedTicket],
        maxSkillsPerAgent: Int = 3,
        defaultMaxConcurrentTasks: Int = 3,
        availableCodexSkillNames: [String]? = nil
    ) -> Int {
        let requiredSkills = Set(
            plannedTickets
                .flatMap(\.requiredSkills)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                .filter { !$0.isEmpty }
        )

        guard !requiredSkills.isEmpty else {
            lastBoardMessage = message("No required skills found in PM tickets")
            lastBoardMessageSeverity = .warning
            return 0
        }

        let coveredSkills = Set(agents.flatMap(\.skills))
        let missingSkills = requiredSkills.subtracting(coveredSkills).sorted()

        guard !missingSkills.isEmpty else {
            lastBoardMessage = message("All required PM skills are already covered by existing agents")
            lastBoardMessageSeverity = .info
            return 0
        }

        let chunkSize = max(1, maxSkillsPerAgent)
        let maxTasks = max(1, defaultMaxConcurrentTasks)
        let discoveredCodexSkillNames = (availableCodexSkillNames ?? Self.discoverLocalCodexSkillNamesForPMBootstrap())
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        var createdCount = 0
        var existingAgentNames = Set(agents.map { $0.name.lowercased() })
        var nextAutoIndex = 1

        for start in stride(from: 0, to: missingSkills.count, by: chunkSize) {
            let end = min(missingSkills.count, start + chunkSize)
            let skillsChunk = Array(missingSkills[start..<end])
            let agentName = Self.uniqueAutoAgentName(
                existingLowercasedNames: &existingAgentNames,
                nextIndex: &nextAutoIndex
            ) { index in
                self.message("Auto Agent %d", index)
            }

            let codexToolTokens = Self.recommendedCodexSkillToolTokens(
                forRequiredSkills: skillsChunk,
                availableCodexSkillNames: discoveredCodexSkillNames
            )
            var runtimeProfile = AgentRuntimeProfile.defaultCodexBridge
            if !codexToolTokens.isEmpty {
                runtimeProfile.tools = Set(codexToolTokens)
            }

            let created = addAgent(
                name: agentName,
                skillsText: skillsChunk.joined(separator: ", "),
                maxConcurrentTasks: maxTasks,
                runtimeProfile: runtimeProfile
            )
            if created {
                createdCount += 1
            }
        }

        if createdCount > 0 {
            lastBoardMessage = message("Created %d PM bootstrap agent(s) for missing skills", createdCount)
            lastBoardMessageSeverity = .info
        } else {
            lastBoardMessage = message("No required skills found in PM tickets")
            lastBoardMessageSeverity = .warning
        }

        return createdCount
    }

    static func uniqueAutoAgentName(
        existingLowercasedNames: inout Set<String>,
        nextIndex: inout Int,
        localizedName: (Int) -> String
    ) -> String {
        while true {
            let currentIndex = nextIndex
            nextIndex += 1
            let rawCandidate = localizedName(currentIndex).trimmingCharacters(in: .whitespacesAndNewlines)
            let candidate = rawCandidate.isEmpty ? "Auto Agent \(currentIndex)" : rawCandidate
            let normalizedCandidate = candidate.lowercased()
            if !existingLowercasedNames.contains(normalizedCandidate) {
                existingLowercasedNames.insert(normalizedCandidate)
                return candidate
            }
        }
    }

    static func discoverLocalCodexSkillNamesForPMBootstrap(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> [String] {
        CodexSkillCatalog.discoverSkillNames(
            environment: environment,
            fallbackHomeDirectoryPath: NSHomeDirectory()
        )
    }

    static func recommendedCodexSkillToolTokens(
        forRequiredSkills requiredSkills: [String],
        availableCodexSkillNames: [String]
    ) -> [String] {
        guard !requiredSkills.isEmpty else { return [] }
        guard !availableCodexSkillNames.isEmpty else { return [] }

        let indexed = availableCodexSkillNames.map { name in
            (
                name: name,
                normalizedName: name.lowercased(),
                tokens: codexSkillSearchTokens(for: name)
            )
        }

        var selected = Set<String>()
        for rawSkill in requiredSkills {
            let normalizedRequired = rawSkill
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            guard !normalizedRequired.isEmpty else { continue }

            if let exactMatch = indexed.first(where: { $0.tokens.contains(normalizedRequired) }) {
                selected.insert(exactMatch.normalizedName)
                continue
            }

            let keywordHints = codexSkillKeywordHints(for: normalizedRequired)
            guard !keywordHints.isEmpty else { continue }

            if let fuzzyMatch = indexed.first(where: { !$0.tokens.isDisjoint(with: keywordHints) }) {
                selected.insert(fuzzyMatch.normalizedName)
            }
        }

        return selected.sorted().map { "skill:\($0)" }
    }

    static func codexSkillSearchTokens(for rawSkillName: String) -> Set<String> {
        let normalized = rawSkillName
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !normalized.isEmpty else { return [] }

        var tokens = Set<String>()
        tokens.insert(normalized)

        for token in normalized.split(whereSeparator: { !$0.isLetter && !$0.isNumber }) {
            let fragment = String(token).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !fragment.isEmpty else { continue }
            tokens.insert(fragment)
        }

        if let separator = normalized.firstIndex(of: ":") {
            let trailing = String(normalized[normalized.index(after: separator)...])
            for token in trailing.split(whereSeparator: { !$0.isLetter && !$0.isNumber }) {
                let fragment = String(token).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !fragment.isEmpty else { continue }
                tokens.insert(fragment)
            }
        }

        return tokens
    }

    static func codexSkillKeywordHints(for requiredSkill: String) -> Set<String> {
        let builtInHints = pmRequiredSkillToCodexHintMap[requiredSkill] ?? []
        let merged = Set(builtInHints + [requiredSkill])
        return Set(merged.filter { !$0.isEmpty })
    }

    static let pmRequiredSkillToCodexHintMap: [String: [String]] = [
        "android": ["android", "mobile"],
        "api": ["api", "backend", "integration", "network"],
        "app": ["app", "ios", "swiftui"],
        "architecture": ["architecture", "refactor", "plan", "planning"],
        "backend": ["backend", "api", "integration", "database"],
        "build": ["build", "xcode", "ios"],
        "database": ["database", "data", "storage"],
        "design": ["design", "ui", "ux", "stitch"],
        "documentation": ["docs", "documentation", "readme"],
        "i18n": ["i18n", "localization", "l10n"],
        "integration": ["integration", "api", "backend"],
        "ios": ["ios", "xcode", "swiftui"],
        "macos": ["macos", "swiftui", "xcode"],
        "planning": ["planning", "plan", "brainstorm"],
        "qa": ["qa", "testing", "test", "audit"],
        "release": ["release", "deploy", "build"],
        "security": ["security", "compliance"],
        "swift": ["swift", "ios", "swiftui"],
        "swiftui": ["swiftui", "ui", "ios"],
        "tdd": ["tdd", "testing", "test"],
        "test": ["test", "testing", "qa", "audit"],
        "testing": ["testing", "test", "qa", "audit"],
        "ui": ["ui", "ux", "swiftui", "stitch"],
        "ux": ["ux", "ui", "design", "stitch"],
        "xcode": ["xcode", "ios", "build"]
    ]

    @discardableResult
    func updateTask(
        _ taskID: UUID,
        title: String,
        details: String,
        requiredSkillsText: String,
        storyPoints: Int,
        deliveryContract: TaskDeliveryContract? = nil
    ) -> Bool {
        guard let taskIndex = tasks.firstIndex(where: { $0.id == taskID }) else { return false }

        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else {
            lastBoardMessage = message("Task title is required")
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
        if let deliveryContract {
            tasks[taskIndex].deliveryContract = deliveryContract.normalized
        } else if tasks[taskIndex].deliveryContract == nil {
            tasks[taskIndex].deliveryContract = Self.inferredDeliveryContract(
                title: trimmedTitle,
                details: details,
                requiredSkills: skills
            )
        }
        taskExecutionApprovalsByTaskID[taskID] = nil

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
    func duplicateTask(_ taskID: UUID) -> Bool {
        guard let sourceTask = tasks.first(where: { $0.id == taskID }) else { return false }

        let duplicatedTask = WorkTask(
            title: uniqueTaskCopyTitle(for: sourceTask.title),
            details: sourceTask.details,
            requiredSkills: Array(sourceTask.requiredSkills),
            storyPoints: sourceTask.storyPoints,
            status: .todo,
            assignedAgentID: nil,
            deliveryContract: sourceTask.deliveryContract
        )
        tasks.append(duplicatedTask)
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
        taskExecutionApprovalsByTaskID[taskID] = nil
        executionTimelineByTaskID[taskID] = nil
        persistBoardState()
        lastBoardMessage = nil
        return true
    }

    @discardableResult
    func unassignTask(_ taskID: UUID) -> Bool {
        guard let taskIndex = tasks.firstIndex(where: { $0.id == taskID }) else { return false }
        guard tasks[taskIndex].assignedAgentID != nil else {
            lastBoardMessage = message("Task is already unassigned")
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
            lastBoardMessage = message("No todo tasks assigned to selected agent")
            lastBoardMessageSeverity = .warning
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
            lastBoardMessage = message("No done tasks to archive")
            lastBoardMessageSeverity = .warning
            return 0
        }

        tasks.removeAll { $0.status == .done }
        for taskID in doneTaskIDs {
            lastUnassignedTaskIDs.remove(taskID)
            lastAssignmentReasons[taskID] = nil
            taskExecutionApprovalsByTaskID[taskID] = nil
            executionTimelineByTaskID[taskID] = nil
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
            lastBoardMessage = message("No todo rebalancing needed")
            lastBoardMessageSeverity = .warning
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
        addAgent(
            name: name,
            skillsText: skillsText,
            maxConcurrentTasks: maxConcurrentTasks,
            runtimeProfile: .defaultCodexBridge
        )
    }

    @discardableResult
    func addAgent(
        name: String,
        skillsText: String,
        maxConcurrentTasks: Int = 3,
        runtimeProfile: AgentRuntimeProfile? = nil
    ) -> Bool {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            lastBoardMessage = message("Agent name is required")
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
                maxConcurrentTasks: maxConcurrentTasks,
                runtimeProfile: runtimeProfile
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
        agentExecutionEventsByAgentID[agentID] = nil

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
        updateAgent(
            agentID,
            name: name,
            skillsText: skillsText,
            maxConcurrentTasks: maxConcurrentTasks,
            runtimeProfile: nil
        )
    }

    @discardableResult
    func updateAgent(
        _ agentID: UUID,
        name: String,
        skillsText: String,
        maxConcurrentTasks: Int,
        runtimeProfile: AgentRuntimeProfile? = nil
    ) -> Bool {
        guard let agentIndex = agents.firstIndex(where: { $0.id == agentID }) else { return false }

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            lastBoardMessage = message("Agent name is required")
            return false
        }

        let normalizedCapacity = max(1, maxConcurrentTasks)
        let currentLoad = activeTaskCount(for: agentID)
        guard normalizedCapacity >= currentLoad else {
            lastBoardMessage = message("Cannot set capacity below current load (%d)", currentLoad)
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
            maxConcurrentTasks: normalizedCapacity,
            runtimeProfile: runtimeProfile
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

        let missingDependencyReferences = missingDependencyReferences()
        if !missingDependencyReferences.isEmpty {
            recommendations.append(
                BoardHealthRecommendation(
                    action: .createMissingDependencyTasks,
                    title: message("Create Missing Dependency Tasks"),
                    detail: message(
                        "%d missing dependency task(s) can be generated from blockers",
                        missingDependencyReferences.count
                    )
                )
            )
        }

        if unassignedTodoTaskCount > 0 {
            if !agents.isEmpty {
                recommendations.append(
                    BoardHealthRecommendation(
                        action: .autoAssignUnassignedTodo,
                        title: message("Auto-Assign Unowned To Do"),
                        detail: message("%d unassigned task(s) can be dispatched automatically", unassignedTodoTaskCount)
                    )
                )

                recommendations.append(
                    BoardHealthRecommendation(
                        action: .openManualTriage,
                        title: message("Run Manual Triage"),
                        detail: message("Open triage sheet to manually assign pending To Do tasks")
                    )
                )
            } else {
                recommendations.append(
                    BoardHealthRecommendation(
                        action: .openNewAgent,
                        title: message("Create First Agent"),
                        detail: message("Add an agent profile so pending To Do tasks can be assigned")
                    )
                )
            }
        }

        if canRebalanceTodoAssignments() {
            recommendations.append(
                BoardHealthRecommendation(
                    action: .rebalanceTodoLoad,
                    title: message("Rebalance Overloaded Agents"),
                    detail: message("Move eligible To Do tasks away from overloaded agents")
                )
            )
        }

        if wipPressurePercent(for: .inProgress) >= 100, wipLimit(for: .inProgress) != nil {
            recommendations.append(
                BoardHealthRecommendation(
                    action: .increaseWIPLimit(.inProgress),
                    title: message("Increase In Progress WIP"),
                    detail: message("In Progress is at or above its WIP limit")
                )
            )
        }

        if wipPressurePercent(for: .review) >= 100, wipLimit(for: .review) != nil {
            recommendations.append(
                BoardHealthRecommendation(
                    action: .increaseWIPLimit(.review),
                    title: message("Increase Review WIP"),
                    detail: message("Review is at or above its WIP limit")
                )
            )
        }

        if doneTaskCount > 0 {
            recommendations.append(
                BoardHealthRecommendation(
                    action: .archiveDone,
                    title: message("Archive Done Tasks"),
                    detail: message("%d completed task(s) can be archived", doneTaskCount)
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

        case .createMissingDependencyTasks:
            return createMissingDependencyTasks() > 0

        case .rebalanceTodoLoad:
            return rebalanceTodoAssignments() > 0

        case .openManualTriage:
            return !triageCandidates().isEmpty

        case .openNewAgent:
            return agents.isEmpty

        case let .increaseWIPLimit(status):
            guard let currentLimit = wipLimit(for: status) else {
                lastBoardMessage = message("%@ has no configured WIP limit", message(status.title))
                return false
            }
            return updateWIPLimit(for: status, limit: currentLimit + 1)

        case .archiveDone:
            return clearDoneTasks() > 0
        }
    }

    @discardableResult
    func createMissingDependencyTasks(storyPoints: Int = 1) -> Int {
        let missingDependencies = missingDependencyDescriptors()
        guard !missingDependencies.isEmpty else {
            lastBoardMessage = message("No missing dependency tasks were found")
            lastBoardMessageSeverity = .warning
            return 0
        }

        let normalizedStoryPoints = max(1, storyPoints)
        var createdTaskIDs: [UUID] = []
        createdTaskIDs.reserveCapacity(missingDependencies.count)

        for dependency in missingDependencies {
            var detailLines = [
                message(
                    "Auto-generated dependency task. Created because other tasks reference this dependency: %@",
                    dependency.reference.displayTitle
                )
            ]
            if !dependency.dependentTaskTitles.isEmpty {
                detailLines.append(
                    message("Referenced by tasks: %@", dependency.dependentTaskTitles.joined(separator: ", "))
                )
            }
            if !dependency.inferredSkills.isEmpty {
                detailLines.append(
                    message("Inferred required skills: %@", dependency.inferredSkills.joined(separator: ", "))
                )
            }

            let task = WorkTask(
                title: dependency.reference.displayTitle,
                details: detailLines.joined(separator: "\n"),
                requiredSkills: dependency.inferredSkills,
                storyPoints: normalizedStoryPoints,
                status: .todo,
                assignedAgentID: nil
            )
            tasks.append(task)
            createdTaskIDs.append(task.id)
            lastUnassignedTaskIDs.insert(task.id)
            lastAssignmentReasons[task.id] = nil
        }

        persistBoardState()
        lastBoardMessage = message("Created %d dependency placeholder task(s)", createdTaskIDs.count)
        lastBoardMessageSeverity = .info
        return createdTaskIDs.count
    }

    @discardableResult
    func applyAllHealthRecommendations() -> Int {
        var appliedCount = 0
        let maxPassCount = 5
        var pass = 0

        while pass < maxPassCount {
            pass += 1
            let actions = healthRecommendations().map(\.action).filter(\.isAutoFixable)
            guard !actions.isEmpty else { break }

            var advancedThisPass = false
            for action in actions {
                let before = HealthAutoFixSnapshot(
                    tasks: tasks,
                    agents: agents,
                    wipLimits: wipLimits,
                    unassignedTaskIDs: lastUnassignedTaskIDs,
                    assignmentReasons: lastAssignmentReasons
                )
                let applied = applyHealthRecommendation(action)
                let after = HealthAutoFixSnapshot(
                    tasks: tasks,
                    agents: agents,
                    wipLimits: wipLimits,
                    unassignedTaskIDs: lastUnassignedTaskIDs,
                    assignmentReasons: lastAssignmentReasons
                )
                let changed = before != after
                if applied && changed {
                    appliedCount += 1
                    advancedThisPass = true
                }
            }

            if !advancedThisPass {
                break
            }
        }

        if appliedCount > 0 {
            lastBoardMessage = message("Applied %d health recommendation(s)", appliedCount)
            lastBoardMessageSeverity = .info
        } else if !healthRecommendations().isEmpty {
            lastBoardMessage = message("No automatic fixes available for current recommendations")
            lastBoardMessageSeverity = .warning
        } else {
            lastBoardMessage = message("Board health already stable")
            lastBoardMessageSeverity = .info
        }

        return appliedCount
    }

    func agentName(for id: UUID?) -> String {
        guard let id else { return message("Unassigned") }
        return agents.first(where: { $0.id == id })?.name ?? message("Unknown")
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
                lastBoardMessage = message(
                    "Cannot set %@ WIP below current count (%d)",
                    message(status.title),
                    currentCount
                )
                return false
            }
        }

        wipLimits = candidateLimits
        persistBoardState()
        lastBoardMessage = nil
        return true
    }

    @discardableResult
    func autoRelaxWIPLimitsForAutoCycle() -> Int {
        var limitUpdates: [KanbanStatus: Int?] = [:]

        if let inProgressLimit = wipLimit(for: .inProgress),
           wipPressurePercent(for: .inProgress) >= 100,
           hasRunnableTodoBlockedByInProgressWIP() {
            limitUpdates[.inProgress] = inProgressLimit + 1
        }

        if let reviewLimit = wipLimit(for: .review),
           wipPressurePercent(for: .review) >= 100,
           tasks.contains(where: { $0.status == .inProgress }) {
            limitUpdates[.review] = reviewLimit + 1
        }

        guard !limitUpdates.isEmpty else { return 0 }
        guard updateWIPLimits(limitUpdates) else { return 0 }
        lastBoardMessage = message("Auto-relaxed WIP limits this pass: +%d", limitUpdates.count)
        lastBoardMessageSeverity = .info
        return limitUpdates.count
    }

    func hasRunnableTodoBlockedByInProgressWIP() -> Bool {
        tasks.contains { task in
            guard task.status == .todo else { return false }
            guard task.assignedAgentID != nil else { return false }
            guard !task.details.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
            guard unresolvedDependencies(for: task.id).isEmpty else { return false }
            guard !(requiresHumanApproval(for: task.id) && !isTaskApprovedForExecution(task.id)) else { return false }
            guard quotaCheckMessage(for: task) == nil else { return false }
            guard qualitySafetyGateBlockReason(for: task) == nil else { return false }
            return true
        }
    }

    func assignmentReason(for taskID: UUID) -> String? {
        lastAssignmentReasons[taskID]
    }

    func executionRecord(for taskID: UUID) -> TaskExecutionRecord? {
        tasks.first(where: { $0.id == taskID })?.executionRecord
    }

    func executionEvents(for agentID: UUID, limit: Int = 80) -> [AgentExecutionEvent] {
        let events = agentExecutionEventsByAgentID[agentID] ?? []
        guard limit > 0, events.count > limit else {
            return events.reversed()
        }
        return events.suffix(limit).reversed()
    }

    func executionTimeline(for taskID: UUID, limit: Int = 200) -> [AgentExecutionEvent] {
        let events = executionTimelineByTaskID[taskID] ?? []
        guard limit > 0, events.count > limit else {
            return events
        }
        return Array(events.suffix(limit))
    }

    func replayExecutionTimeline(for taskID: UUID, limit: Int = 200) -> String? {
        let events = executionTimeline(for: taskID, limit: limit)
        guard !events.isEmpty else { return nil }

        let formatter = ISO8601DateFormatter()
        return events.map { event in
            var lines: [String] = []
            lines.append(
                "[\(formatter.string(from: event.timestamp))] [\(event.phase.rawValue)] [\(event.status.rawValue)] \(event.message)"
            )
            if let details = normalizeExecutionText(event.details) {
                lines.append(details)
            }
            return lines.joined(separator: "\n")
        }
        .joined(separator: "\n\n")
    }

    func hasExecutionTimeline(for taskID: UUID) -> Bool {
        !(executionTimelineByTaskID[taskID] ?? []).isEmpty
    }

    func clearExecutionEvents(for agentID: UUID) {
        guard let removedEvents = agentExecutionEventsByAgentID[agentID], !removedEvents.isEmpty else {
            agentExecutionEventsByAgentID[agentID] = []
            return
        }
        agentExecutionEventsByAgentID[agentID] = []

        let removedEventIDs = Set(removedEvents.map(\.id))
        for (taskID, timelineEvents) in executionTimelineByTaskID {
            let filtered = timelineEvents.filter { !removedEventIDs.contains($0.id) }
            executionTimelineByTaskID[taskID] = filtered
        }
        executionTimelineByTaskID = executionTimelineByTaskID.filter { !$0.value.isEmpty }
    }

    func clearExecutionTimeline(for taskID: UUID) {
        executionTimelineByTaskID[taskID] = []
    }

    func addSharedAgentMemoryNote(_ note: String) -> Bool {
        let normalizedNote = normalizeExecutionText(note)
        guard let normalizedNote else {
            lastBoardMessage = message("Shared memory note is empty")
            lastBoardMessageSeverity = .warning
            return false
        }
        appendSharedAgentMemoryEntry(
            SharedAgentMemoryEntry(
                source: .manual,
                agentID: nil,
                agentName: message("Human"),
                taskID: nil,
                taskTitle: message("Manual note"),
                summary: normalizedNote
            )
        )
        persistBoardState()
        lastBoardMessage = message("Shared memory note added")
        lastBoardMessageSeverity = .info
        return true
    }

    func removeSharedAgentMemoryEntry(_ entryID: UUID) {
        sharedAgentMemory.removeAll { $0.id == entryID }
        persistBoardState()
    }

    func clearSharedAgentMemory() {
        sharedAgentMemory = []
        persistBoardState()
        lastBoardMessage = message("Cleared shared memory")
        lastBoardMessageSeverity = .warning
    }

    func updateSharedAgentMemoryProviderMode(_ mode: SharedAgentMemoryProviderMode) {
        guard sharedAgentMemoryProviderMode != mode else { return }
        sharedAgentMemoryProviderMode = mode
        persistBoardState()
        lastBoardMessage = message("Updated shared memory mode: %@", mode.title)
        lastBoardMessageSeverity = .info
    }

    func updateSharedAgentMemoryPreferredProviderID(_ providerID: String?) {
        let normalized = Self.normalizedProviderDescriptorID(providerID)
        guard sharedAgentMemoryPreferredProviderID != normalized else { return }
        sharedAgentMemoryPreferredProviderID = normalized
        persistBoardState()
        if let normalized {
            lastBoardMessage = message("Preferred shared memory provider: %@", normalized)
        } else {
            lastBoardMessage = message("Preferred shared memory provider: Auto")
        }
        lastBoardMessageSeverity = .info
    }

    func updateSharedAgentMemoryProviderEnabled(_ providerID: String, isEnabled: Bool) {
        guard let normalized = Self.normalizedProviderDescriptorID(providerID) else { return }
        let changed: Bool
        if isEnabled {
            changed = sharedAgentMemoryMutedProviderIDs.remove(normalized) != nil
        } else {
            let (inserted, _) = sharedAgentMemoryMutedProviderIDs.insert(normalized)
            changed = inserted
            if sharedAgentMemoryPreferredProviderID == normalized {
                sharedAgentMemoryPreferredProviderID = nil
            }
        }
        guard changed else { return }
        persistBoardState()
        lastBoardMessage = isEnabled
            ? message("Enabled shared memory provider: %@", normalized)
            : message("Disabled shared memory provider: %@", normalized)
        lastBoardMessageSeverity = .info
    }

    func sharedMemoryProviders() -> [SharedAgentMemoryProviderDescriptor] {
        detectedLocalPMPlannerPluginRecords(in: pmPlanningPluginPolicy.pluginsDirectoryPath)
            .flatMap { record -> [SharedAgentMemoryProviderDescriptor] in
                let pluginID = (record.manifest.id ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                guard !pluginID.isEmpty else { return [] }
                guard !pmPlanningPluginPolicy.disabledPluginIDs.contains(pluginID.lowercased()) else { return [] }
                let pluginName = resolvedPMExtensionPluginName(from: record)
                let commandIDs = Set(
                    (record.manifest.commands ?? [])
                        .filter { $0.enabled ?? true }
                        .compactMap { ($0.id ?? "").trimmingCharacters(in: .whitespacesAndNewlines) }
                )
                return (record.manifest.memoryProviders ?? []).compactMap { provider in
                    guard provider.enabled ?? true else { return nil }
                    let providerID = (provider.id ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    let commandID = (provider.commandID ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !providerID.isEmpty, !commandID.isEmpty else { return nil }
                    guard commandIDs.contains(commandID) else { return nil }
                    let title = {
                        let trimmed = (provider.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                        return trimmed.isEmpty ? providerID : trimmed
                    }()
                    let strategy = {
                        let trimmed = (provider.strategy ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                        return trimmed.isEmpty ? "context.injector" : trimmed
                    }()
                    return SharedAgentMemoryProviderDescriptor(
                        id: "\(pluginID).\(providerID)",
                        pluginID: pluginID,
                        pluginName: pluginName,
                        providerID: providerID,
                        title: title,
                        commandID: commandID,
                        strategy: strategy,
                        priority: provider.priority ?? 0
                    )
                }
            }
            .sorted { lhs, rhs in
                if lhs.priority == rhs.priority {
                    if lhs.pluginName.localizedCaseInsensitiveCompare(rhs.pluginName) == .orderedSame {
                        return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
                    }
                    return lhs.pluginName.localizedCaseInsensitiveCompare(rhs.pluginName) == .orderedAscending
                }
                return lhs.priority > rhs.priority
            }
    }

    func sharedMemoryExecutionProviders() -> [SharedAgentMemoryProviderDescriptor] {
        let available = sharedMemoryProviders().filter { descriptor in
            !sharedAgentMemoryMutedProviderIDs.contains(descriptor.id)
        }
        guard !available.isEmpty else { return [] }
        guard let preferredID = sharedAgentMemoryPreferredProviderID,
              let preferred = available.first(where: { $0.id == preferredID }) else {
            return available
        }
        let remaining = available.filter { $0.id != preferred.id }
        return [preferred] + remaining
    }

    func sharedAgentMemoryText(limit: Int = 80) -> String {
        let entries = sharedAgentMemoryEntries(limit: limit)
        guard !entries.isEmpty else { return "-" }
        return entries
            .map { entry in
                let timestamp = Self.iso8601Formatter.string(from: entry.createdAt)
                return "[\(timestamp)] \(entry.source.rawValue) \(entry.agentName) · \(entry.taskTitle): \(entry.summary)"
            }
            .joined(separator: "\n")
    }

    func clearLocalizedTransientBoardMessage() {
        lastBoardMessage = nil
        lastBoardMessageSeverity = nil
    }

    func showXcodeDeveloperDirectoryWarningIfNeeded(
        activeDeveloperDirectoryPath: String? = nil,
        installedXcodeDeveloperDirectoryPath: String? = nil,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) {
        let activePath = activeDeveloperDirectoryPath
            ?? Self.activeDeveloperDirectoryPath(environment: environment)
        let xcodeDeveloperPath = installedXcodeDeveloperDirectoryPath
            ?? Self.installedXcodeDeveloperDirectoryPath(fileManager: fileManager)
        guard let command = Self.xcodeSelectRepairCommandIfNeeded(
            activeDeveloperDirectoryPath: activePath,
            installedXcodeDeveloperDirectoryPath: xcodeDeveloperPath
        ) else {
            return
        }

        if let existingMessage = lastBoardMessage,
           !existingMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return
        }

        lastBoardMessage = message(
            "Xcode is installed, but active developer directory is CommandLineTools. Switch to full Xcode for app build/test: %@",
            command
        )
        lastBoardMessageSeverity = .warning
    }

    func isAgentExecutionRunning(_ agentID: UUID) -> Bool {
        tasks.contains { task in
            guard task.executionRecord?.status == .running else { return false }
            return task.executionRecord?.lastAgentID == agentID || task.assignedAgentID == agentID
        }
    }

    func requiresHumanApproval(for taskID: UUID) -> Bool {
        guard executionApprovalPolicy.isEnabled,
              let task = tasks.first(where: { $0.id == taskID }) else {
            return false
        }
        guard task.status == .todo || task.status == .inProgress else { return false }
        return task.storyPoints >= executionApprovalPolicy.minimumStoryPoints
    }

    func isTaskApprovedForExecution(_ taskID: UUID) -> Bool {
        taskExecutionApprovalsByTaskID[taskID] != nil
    }

    @discardableResult
    func approveTaskExecution(_ taskID: UUID, approvedBy: String = "Human") -> Bool {
        guard requiresHumanApproval(for: taskID) else { return false }
        taskExecutionApprovalsByTaskID[taskID] = TaskExecutionApproval(approvedBy: approvedBy)
        persistBoardState()
        if let task = tasks.first(where: { $0.id == taskID }) {
            lastBoardMessage = message("Approved run for %@", task.title)
            lastBoardMessageSeverity = .info
        }
        return true
    }

    @discardableResult
    func revokeTaskExecutionApproval(_ taskID: UUID) -> Bool {
        guard taskExecutionApprovalsByTaskID[taskID] != nil else { return false }
        taskExecutionApprovalsByTaskID[taskID] = nil
        persistBoardState()
        if let task = tasks.first(where: { $0.id == taskID }) {
            lastBoardMessage = message("Revoked run approval for %@", task.title)
            lastBoardMessageSeverity = .warning
        }
        return true
    }

    @discardableResult
    func approveAllPendingTaskExecutions(approvedBy: String = "Human") -> Int {
        let pendingTaskIDs = tasks
            .filter { requiresHumanApproval(for: $0.id) && !isTaskApprovedForExecution($0.id) }
            .map(\.id)
        guard !pendingTaskIDs.isEmpty else { return 0 }

        let approval = TaskExecutionApproval(approvedBy: approvedBy)
        for taskID in pendingTaskIDs {
            taskExecutionApprovalsByTaskID[taskID] = approval
        }
        persistBoardState()
        lastBoardMessage = message("Approved %d pending run(s)", pendingTaskIDs.count)
        lastBoardMessageSeverity = .info
        return pendingTaskIDs.count
    }

    func updateExecutionApprovalPolicy(
        isEnabled: Bool,
        minimumStoryPoints: Int
    ) {
        executionApprovalPolicy = ExecutionApprovalPolicy(
            isEnabled: isEnabled,
            minimumStoryPoints: minimumStoryPoints
        )
        if !executionApprovalPolicy.isEnabled {
            taskExecutionApprovalsByTaskID = [:]
        } else {
            taskExecutionApprovalsByTaskID = taskExecutionApprovalsByTaskID.filter { requiresHumanApproval(for: $0.key) }
        }
        persistBoardState()
        lastBoardMessage = message("Updated approval gate settings")
        lastBoardMessageSeverity = .info
    }

    func updateExecutionQuotaPolicy(
        isEnabled: Bool,
        maxEstimatedTokens: Int,
        maxEstimatedCostUSD: Double,
        costPer1KTokensUSD: Double
    ) {
        executionQuotaPolicy = ExecutionQuotaPolicy(
            isEnabled: isEnabled,
            maxEstimatedTokens: maxEstimatedTokens,
            maxEstimatedCostUSD: maxEstimatedCostUSD,
            costPer1KTokensUSD: costPer1KTokensUSD
        )
        persistBoardState()
        lastBoardMessage = message("Updated quota governance settings")
        lastBoardMessageSeverity = .info
    }

    func updateExecutionParallelizationPolicy(
        isEnabled: Bool,
        maxConcurrentAgents: Int
    ) {
        executionParallelizationPolicy = ExecutionParallelizationPolicy(
            isEnabled: isEnabled,
            maxConcurrentAgents: maxConcurrentAgents
        )
        persistBoardState()
        lastBoardMessage = message("Updated parallel scheduler settings")
        lastBoardMessageSeverity = .info
    }

    func updateGitHubPRQualityGatePolicy(
        isEnabled: Bool,
        commands: [String]? = nil
    ) {
        let resolvedCommands = commands ?? gitHubPRQualityGatePolicy.commands
        gitHubPRQualityGatePolicy = GitHubPRQualityGatePolicy(
            isEnabled: isEnabled,
            commands: resolvedCommands
        )
        persistBoardState()
        lastBoardMessage = message("Updated PR quality gate settings")
        lastBoardMessageSeverity = .info
    }

    func gitHubPRQualityGateSummaryText() -> String {
        message("PR quality gate commands: %d", gitHubPRQualityGatePolicy.commands.count)
    }

    func updateDAGExecutionPolicy(
        isEnabled: Bool,
        autoAssignBeforeRun: Bool,
        autoAssignFallbackWithoutSkillMatch: Bool,
        autoRelaxWIPLimitsDuringRun: Bool = true,
        autoCreateMissingDependenciesDuringRun: Bool,
        maxPasses: Int
    ) {
        dagExecutionPolicy = DAGExecutionPolicy(
            isEnabled: isEnabled,
            autoAssignBeforeRun: autoAssignBeforeRun,
            autoAssignFallbackWithoutSkillMatch: autoAssignFallbackWithoutSkillMatch,
            autoRelaxWIPLimitsDuringRun: autoRelaxWIPLimitsDuringRun,
            autoCreateMissingDependenciesDuringRun: autoCreateMissingDependenciesDuringRun,
            maxPasses: maxPasses
        )
        persistBoardState()
        lastBoardMessage = message("Updated DAG scheduler settings")
        lastBoardMessageSeverity = .info
    }

    func updateExecutionQualitySafetyGatePolicy(
        isEnabled: Bool,
        requireAcceptanceCriteria: Bool,
        requireTestCoverageIntent: Bool,
        requireSecurityPrivacyForSensitiveTasks: Bool
    ) {
        executionQualitySafetyGatePolicy = ExecutionQualitySafetyGatePolicy(
            isEnabled: isEnabled,
            requireAcceptanceCriteria: requireAcceptanceCriteria,
            requireTestCoverageIntent: requireTestCoverageIntent,
            requireSecurityPrivacyForSensitiveTasks: requireSecurityPrivacyForSensitiveTasks,
            sensitiveKeywords: executionQualitySafetyGatePolicy.sensitiveKeywords
        )
        persistBoardState()
        lastBoardMessage = message("Updated quality & safety gate settings")
        lastBoardMessageSeverity = .info
    }

    func executionQualitySafetyGateSummaryText() -> String {
        guard executionQualitySafetyGatePolicy.isEnabled else {
            return message("Quality/safety gate is off")
        }
        return message("Quality/safety gate is on")
    }

    func updateExecutionRealArtifactVerificationPolicy(
        isEnabled: Bool,
        requireInfoPlistExecutableKey: Bool,
        requireXcodeBuild: Bool
    ) {
        let updatedPolicy = ExecutionRealArtifactVerificationPolicy(
            isEnabled: isEnabled,
            requireInfoPlistExecutableKey: requireInfoPlistExecutableKey,
            requireXcodeBuild: requireXcodeBuild
        )
        executionRealArtifactVerificationDefaultPolicy = updatedPolicy
        if selectedBoardUsesDefaultRealArtifactVerificationPolicy {
            executionRealArtifactVerificationPolicy = updatedPolicy
        }
        commitRealArtifactVerificationPolicyChange(
            announcementKey: "Updated real artifact verification defaults"
        )
    }

    func updateSelectedBoardExecutionRealArtifactVerificationPolicy(
        isEnabled: Bool,
        requireInfoPlistExecutableKey: Bool,
        requireXcodeBuild: Bool,
        announce: Bool = true
    ) {
        updateSelectedBoardExecutionRealArtifactVerificationPolicy(
            ExecutionRealArtifactVerificationPolicy(
                isEnabled: isEnabled,
                requireInfoPlistExecutableKey: requireInfoPlistExecutableKey,
                requireXcodeBuild: requireXcodeBuild
            ),
            announce: announce
        )
    }

    func updateSelectedBoardExecutionRealArtifactVerificationPolicy(
        _ policy: ExecutionRealArtifactVerificationPolicy,
        announce: Bool = true
    ) {
        selectedBoardUsesDefaultRealArtifactVerificationPolicy = false
        executionRealArtifactVerificationPolicy = policy
        commitRealArtifactVerificationPolicyChange(
            announcementKey: "Updated board real artifact verification settings",
            announce: announce
        )
    }

    func useDefaultRealArtifactVerificationPolicyForSelectedBoard(
        announce: Bool = true
    ) {
        selectedBoardUsesDefaultRealArtifactVerificationPolicy = true
        executionRealArtifactVerificationPolicy = executionRealArtifactVerificationDefaultPolicy
        commitRealArtifactVerificationPolicyChange(
            announcementKey: "Using developer default real artifact verification for this board",
            announce: announce
        )
    }

    func executionRealArtifactVerificationSummaryText() -> String {
        executionRealArtifactVerificationSummaryText(for: executionRealArtifactVerificationPolicy)
    }

    func executionRealArtifactVerificationDefaultSummaryText() -> String {
        executionRealArtifactVerificationSummaryText(for: executionRealArtifactVerificationDefaultPolicy)
    }

    func commitRealArtifactVerificationPolicyChange(
        announcementKey: String,
        announce: Bool = true
    ) {
        _ = syncSystemRealArtifactVerificationBoardHookBinding()
        syncCurrentBoardRecord()
        persistBoardState()
        guard announce else { return }
        lastBoardMessage = message(announcementKey)
        lastBoardMessageSeverity = .info
    }

    func executionRealArtifactVerificationSummaryText(
        for policy: ExecutionRealArtifactVerificationPolicy
    ) -> String {
        guard policy.isEnabled else {
            return message("Real artifact verification is off")
        }
        let executionMode = policy.runVerificationOnlyOnTerminalTask
            ? message("Final task only")
            : message("Any strict app task")
        return message(
            "Real artifact verification is on (Info.plist: %@, xcodebuild: %@, mode: %@)",
            policy.requireInfoPlistExecutableKey ? message("On") : message("Off"),
            policy.requireXcodeBuild ? message("On") : message("Off"),
            executionMode
        )
    }

    func updatePMPlannerEngineMode(_ mode: PMPlannerEngineMode, announce: Bool = true) {
        pmPlannerEngineMode = mode
        persistBoardState()
        guard announce else { return }
        lastBoardMessage = message("Updated PM planning engine mode")
        lastBoardMessageSeverity = .info
    }

}
