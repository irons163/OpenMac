import Foundation

nonisolated struct StructuredResponseDeliveryPlanner: DeliveryPlanning, Sendable {
    nonisolated let plannerID: String
    private let provider: any DeliveryPlanStructuredResponseProviding

    nonisolated init(
        plannerID: String,
        provider: any DeliveryPlanStructuredResponseProviding
    ) {
        self.plannerID = plannerID
        self.provider = provider
    }

    nonisolated func generate(
        _ request: DeliveryPlanGenerationRequest
    ) async throws -> DeliveryPlanGenerationResult {
        try StructuredDeliveryPlanParser.validateInput(request)
        do {
            try DeliveryPlanningRepositoryContext.validateCurrentResolvedIdentity(
                request.repositoryIdentity,
                baseBranch: request.brief.repository.baseBranch
            )
        } catch let error as DeliveryPlanningRepositoryContextResolutionError {
            throw DeliveryPlanGenerationError.invalidInput(
                fieldPath: error.fieldPath,
                reason: error.errorDescription ?? "Repository identity validation failed."
            )
        }

        let data: Data
        do {
            data = try await provider.response(for: request)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as DeliveryPlanGenerationError {
            throw error
        } catch {
            throw DeliveryPlanGenerationError.providerFailure(
                providerID: provider.providerID,
                reason: String(describing: error)
            )
        }

        try Task.checkCancellation()

        let result = try StructuredDeliveryPlanParser.parse(
            data,
            request: request,
            plannerID: plannerID
        )
        do {
            try DeliveryPlanningRepositoryContext.validateCurrentResolvedIdentity(
                request.repositoryIdentity,
                baseBranch: request.brief.repository.baseBranch
            )
        } catch let error as DeliveryPlanningRepositoryContextResolutionError {
            throw DeliveryPlanGenerationError.invalidInput(
                fieldPath: error.fieldPath,
                reason: error.errorDescription ?? "Repository identity validation failed."
            )
        }
        try Task.checkCancellation()
        return result
    }
}
