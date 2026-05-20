import Combine
import Foundation

extension KanbanBoardViewModel {
    struct RestoredSnapshotState {
        let executionAutoRetryConfiguration: ExecutionAutoRetryConfiguration
        let executionCheckpoint: ExecutionCheckpoint?
        let executionApprovalPolicy: ExecutionApprovalPolicy
        let taskExecutionApprovalsByTaskID: [UUID: TaskExecutionApproval]
        let executionQuotaPolicy: ExecutionQuotaPolicy
        let executionQuotaUsage: ExecutionQuotaUsage
        let executionParallelizationPolicy: ExecutionParallelizationPolicy
        let gitHubPRQualityGatePolicy: GitHubPRQualityGatePolicy
        let dagExecutionPolicy: DAGExecutionPolicy
        let executionQualitySafetyGatePolicy: ExecutionQualitySafetyGatePolicy
        let executionRealArtifactVerificationPolicy: ExecutionRealArtifactVerificationPolicy
        let mcpServerPolicy: MCPServerPolicy
        let pmPlannerEngineMode: PMPlannerEngineMode
        let pmPlanningPluginPolicy: PMPlanningPluginPolicy
        let sharedAgentMemory: [SharedAgentMemoryEntry]
        let sharedAgentMemoryProviderMode: SharedAgentMemoryProviderMode
        let normalizedSharedAgentMemoryPreferredProviderID: String?
        let sharedAgentMemoryMutedProviderIDs: Set<String>
    }

    static func restoredSnapshotState(from snapshot: KanbanBoardSnapshot) -> RestoredSnapshotState {
        RestoredSnapshotState(
            executionAutoRetryConfiguration: snapshot.executionAutoRetryConfiguration ?? .init(),
            executionCheckpoint: snapshot.executionCheckpoint,
            executionApprovalPolicy: snapshot.executionApprovalPolicy ?? .init(),
            taskExecutionApprovalsByTaskID: snapshot.taskExecutionApprovalsByTaskID ?? [:],
            executionQuotaPolicy: snapshot.executionQuotaPolicy ?? .init(),
            executionQuotaUsage: snapshot.executionQuotaUsage ?? .init(),
            executionParallelizationPolicy: snapshot.executionParallelizationPolicy ?? .init(),
            gitHubPRQualityGatePolicy: snapshot.gitHubPRQualityGatePolicy ?? .init(),
            dagExecutionPolicy: snapshot.dagExecutionPolicy ?? .init(),
            executionQualitySafetyGatePolicy: snapshot.executionQualitySafetyGatePolicy ?? .init(),
            executionRealArtifactVerificationPolicy: snapshot.executionRealArtifactVerificationPolicy ?? .init(),
            mcpServerPolicy: snapshot.mcpServerPolicy ?? .init(),
            pmPlannerEngineMode: snapshot.pmPlannerEngineMode ?? .builtIn,
            pmPlanningPluginPolicy: snapshot.pmPlanningPluginPolicy ?? .init(),
            sharedAgentMemory: snapshot.sharedAgentMemory ?? [],
            sharedAgentMemoryProviderMode: snapshot.sharedAgentMemoryProviderMode ?? .coreOnly,
            normalizedSharedAgentMemoryPreferredProviderID: Self.normalizedProviderDescriptorID(
                snapshot.sharedAgentMemoryPreferredProviderID
            ),
            sharedAgentMemoryMutedProviderIDs: Set(
                (snapshot.sharedAgentMemoryMutedProviderIDs ?? []).compactMap(Self.normalizedProviderDescriptorID)
            )
        )
    }

    static func persistentBoard(
        boardStore: KanbanBoardStore = FileKanbanBoardStore(),
        assignmentEngine: AutoAssignmentEngine = AutoAssignmentEngine(),
        projectPlanner: any ProjectPlanning = ExtensibleProjectPlanner(),
        taskExecutor: any AgentTaskExecuting = DefaultAgentTaskExecutor(),
        projectsDirectoryPathProvider: @escaping () -> String = {
            CodexProjectsDirectorySettings.resolvedProjectsDirectoryPath()
        },
        gitCommandRunner: @escaping GitCommandRunner = GitHubPRFlowUseCase.runSystemCommand,
        runOnBackground: @escaping ExecutionDispatcher = { work in
            DispatchQueue.global(qos: .userInitiated).async(execute: work)
        },
        runOnMain: @escaping ExecutionDispatcher = { work in
            DispatchQueue.main.async(execute: work)
        }
    ) -> KanbanBoardViewModel {
        if let snapshot = try? boardStore.load() {
            let restoredState = restoredSnapshotState(from: snapshot)
            if let boards = snapshot.boards, !boards.isEmpty {
                let resolvedSelectedBoardID = snapshot.selectedBoardID ?? boards[0].id
                return KanbanBoardViewModel(
                    boards: boards,
                    selectedBoardID: resolvedSelectedBoardID,
                    taskTemplates: snapshot.taskTemplates,
                    executionAutoRetryConfiguration: restoredState.executionAutoRetryConfiguration,
                    executionCheckpoint: restoredState.executionCheckpoint,
                    executionApprovalPolicy: restoredState.executionApprovalPolicy,
                    taskExecutionApprovalsByTaskID: restoredState.taskExecutionApprovalsByTaskID,
                    executionQuotaPolicy: restoredState.executionQuotaPolicy,
                    executionQuotaUsage: restoredState.executionQuotaUsage,
                    executionParallelizationPolicy: restoredState.executionParallelizationPolicy,
                    gitHubPRQualityGatePolicy: restoredState.gitHubPRQualityGatePolicy,
                    dagExecutionPolicy: restoredState.dagExecutionPolicy,
                    executionQualitySafetyGatePolicy: restoredState.executionQualitySafetyGatePolicy,
                    executionRealArtifactVerificationPolicy: restoredState.executionRealArtifactVerificationPolicy,
                    mcpServerPolicy: restoredState.mcpServerPolicy,
                    pmPlannerEngineMode: restoredState.pmPlannerEngineMode,
                    pmPlanningPluginPolicy: restoredState.pmPlanningPluginPolicy,
                    sharedAgentMemoryProviderMode: restoredState.sharedAgentMemoryProviderMode,
                    sharedAgentMemoryPreferredProviderID: restoredState.normalizedSharedAgentMemoryPreferredProviderID,
                    sharedAgentMemoryMutedProviderIDs: restoredState.sharedAgentMemoryMutedProviderIDs,
                    projectsDirectoryPathProvider: projectsDirectoryPathProvider,
                    assignmentEngine: assignmentEngine,
                    projectPlanner: projectPlanner,
                    taskExecutor: taskExecutor,
                    boardStore: boardStore,
                    gitCommandRunner: gitCommandRunner,
                    runOnBackground: runOnBackground,
                    runOnMain: runOnMain
                )
            }
            return KanbanBoardViewModel(
                tasks: snapshot.tasks,
                agents: snapshot.agents,
                wipLimits: snapshot.wipLimits,
                taskTemplates: snapshot.taskTemplates,
                executionAutoRetryConfiguration: restoredState.executionAutoRetryConfiguration,
                executionCheckpoint: restoredState.executionCheckpoint,
                executionApprovalPolicy: restoredState.executionApprovalPolicy,
                taskExecutionApprovalsByTaskID: restoredState.taskExecutionApprovalsByTaskID,
                executionQuotaPolicy: restoredState.executionQuotaPolicy,
                executionQuotaUsage: restoredState.executionQuotaUsage,
                executionParallelizationPolicy: restoredState.executionParallelizationPolicy,
                gitHubPRQualityGatePolicy: restoredState.gitHubPRQualityGatePolicy,
                dagExecutionPolicy: restoredState.dagExecutionPolicy,
                executionQualitySafetyGatePolicy: restoredState.executionQualitySafetyGatePolicy,
                executionRealArtifactVerificationPolicy: restoredState.executionRealArtifactVerificationPolicy,
                mcpServerPolicy: restoredState.mcpServerPolicy,
                pmPlannerEngineMode: restoredState.pmPlannerEngineMode,
                pmPlanningPluginPolicy: restoredState.pmPlanningPluginPolicy,
                sharedAgentMemory: restoredState.sharedAgentMemory,
                sharedAgentMemoryProviderMode: restoredState.sharedAgentMemoryProviderMode,
                sharedAgentMemoryPreferredProviderID: restoredState.normalizedSharedAgentMemoryPreferredProviderID,
                sharedAgentMemoryMutedProviderIDs: restoredState.sharedAgentMemoryMutedProviderIDs,
                projectsDirectoryPathProvider: projectsDirectoryPathProvider,
                assignmentEngine: assignmentEngine,
                projectPlanner: projectPlanner,
                taskExecutor: taskExecutor,
                boardStore: boardStore,
                gitCommandRunner: gitCommandRunner,
                runOnBackground: runOnBackground,
                runOnMain: runOnMain
            )
        }
        return demoBoard(
            boardStore: boardStore,
            assignmentEngine: assignmentEngine,
            projectPlanner: projectPlanner,
            taskExecutor: taskExecutor,
            projectsDirectoryPathProvider: projectsDirectoryPathProvider,
            gitCommandRunner: gitCommandRunner,
            runOnBackground: runOnBackground,
            runOnMain: runOnMain
        )
    }

    static func demoBoard(
        boardStore: KanbanBoardStore? = nil,
        assignmentEngine: AutoAssignmentEngine = AutoAssignmentEngine(),
        projectPlanner: any ProjectPlanning = ExtensibleProjectPlanner(),
        taskExecutor: any AgentTaskExecuting = DefaultAgentTaskExecutor(),
        projectsDirectoryPathProvider: @escaping () -> String = {
            CodexProjectsDirectorySettings.resolvedProjectsDirectoryPath()
        },
        gitCommandRunner: @escaping GitCommandRunner = GitHubPRFlowUseCase.runSystemCommand,
        runOnBackground: @escaping ExecutionDispatcher = { work in
            DispatchQueue.global(qos: .userInitiated).async(execute: work)
        },
        runOnMain: @escaping ExecutionDispatcher = { work in
            DispatchQueue.main.async(execute: work)
        }
    ) -> KanbanBoardViewModel {
        let demoData = demoSeedData()
        return KanbanBoardViewModel(
            tasks: demoData.tasks,
            agents: demoData.agents,
            projectsDirectoryPathProvider: projectsDirectoryPathProvider,
            assignmentEngine: assignmentEngine,
            projectPlanner: projectPlanner,
            taskExecutor: taskExecutor,
            boardStore: boardStore,
            gitCommandRunner: gitCommandRunner,
            runOnBackground: runOnBackground,
            runOnMain: runOnMain
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
