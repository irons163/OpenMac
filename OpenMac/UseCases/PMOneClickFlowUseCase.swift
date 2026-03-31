import Foundation

enum PMOneClickFlowAction: Equatable {
    case startedAutopilot
    case openedPlanner
}

enum PMOneClickFlowUseCase {
    @discardableResult
    static func run(
        plannedTicketsCount: Int,
        projectBrief: String,
        runAutopilot: () -> Void,
        openPlanner: () -> Void
    ) -> PMOneClickFlowAction {
        let hasPlannedTickets = plannedTicketsCount > 0
        let hasProjectBrief = !projectBrief.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        if hasPlannedTickets || hasProjectBrief {
            runAutopilot()
            return .startedAutopilot
        }

        openPlanner()
        return .openedPlanner
    }
}
