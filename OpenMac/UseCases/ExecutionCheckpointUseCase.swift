import Foundation

enum ExecutionCheckpointResumeAction: Equatable {
    case assignedBatch
    case autoCycle(maxPasses: Int, autoCreateMissingDependencies: Bool, autoAssignBeforeRun: Bool)
}

enum ExecutionCheckpointUseCase {
    static func makeAssignedBatchCheckpoint(
        boardID: UUID,
        startedAt: Date = Date()
    ) -> ExecutionCheckpoint {
        ExecutionCheckpoint(
            boardID: boardID,
            mode: .assignedBatch,
            startedAt: startedAt,
            maxAutoCyclePasses: 1,
            autoCreateMissingDependencies: false,
            autoAssignBeforeRun: false
        )
    }

    static func makeAutoCycleCheckpoint(
        boardID: UUID,
        maxPasses: Int,
        autoCreateMissingDependencies: Bool,
        autoAssignBeforeRun: Bool,
        startedAt: Date = Date()
    ) -> ExecutionCheckpoint {
        ExecutionCheckpoint(
            boardID: boardID,
            mode: .autoCycle,
            startedAt: startedAt,
            maxAutoCyclePasses: max(1, maxPasses),
            autoCreateMissingDependencies: autoCreateMissingDependencies,
            autoAssignBeforeRun: autoAssignBeforeRun
        )
    }

    static func resumeAction(
        for checkpoint: ExecutionCheckpoint?,
        selectedBoardID: UUID
    ) -> ExecutionCheckpointResumeAction? {
        guard let checkpoint, checkpoint.boardID == selectedBoardID else {
            return nil
        }

        switch checkpoint.mode {
        case .assignedBatch:
            return .assignedBatch
        case .autoCycle:
            return .autoCycle(
                maxPasses: max(1, checkpoint.maxAutoCyclePasses),
                autoCreateMissingDependencies: checkpoint.autoCreateMissingDependencies,
                autoAssignBeforeRun: checkpoint.autoAssignBeforeRun
            )
        }
    }
}
