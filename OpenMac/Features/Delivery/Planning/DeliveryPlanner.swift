import CryptoKit
import Foundation

nonisolated enum DeliveryContainerKind: String, Codable, Sendable {
    case xcodeProject
    case xcodeWorkspace
    case swiftPackage
}

nonisolated enum DeliveryPlanningRepositoryContextResolutionError:
    Error,
    Equatable,
    LocalizedError,
    Sendable
{
    case invalidRepositoryRootPath
    case repositoryRootUnavailable
    case invalidContainerRelativePath
    case containerUnavailable
    case resolvedContainerEscapesRepository
    case repositoryIdentityChanged
    case containerIdentityChanged

    nonisolated var fieldPath: String {
        switch self {
        case .invalidRepositoryRootPath, .repositoryRootUnavailable:
            return "repositoryContext.repositoryRootPath"
        case .invalidContainerRelativePath, .containerUnavailable:
            return "repositoryContext.containerRelativePath"
        case .resolvedContainerEscapesRepository, .containerIdentityChanged:
            return "repositoryContext.resolvedContainerPath"
        case .repositoryIdentityChanged:
            return "repositoryContext.resolvedRepositoryRootPath"
        }
    }

    nonisolated var errorDescription: String? {
        switch self {
        case .invalidRepositoryRootPath:
            return "The repository root must be an absolute path."
        case .repositoryRootUnavailable:
            return "The repository root is not an available directory."
        case .invalidContainerRelativePath:
            return "The container must be a supported relative path inside the repository."
        case .containerUnavailable:
            return "The declared Xcode or Swift package container is unavailable or has the wrong type."
        case .resolvedContainerEscapesRepository:
            return "The resolved container escapes the resolved repository root."
        case .repositoryIdentityChanged:
            return "The repository symlink identity changed after discovery."
        case .containerIdentityChanged:
            return "The container symlink identity changed after discovery."
        }
    }
}

nonisolated struct DeliveryPlanningRepositoryContext: Equatable, Sendable {
    let repositoryRootPath: String
    let resolvedRepositoryRootPath: String
    let containerKind: DeliveryContainerKind
    let containerRelativePath: String
    let resolvedContainerPath: String
    let targetNames: [String]
    let schemeNames: [String]

    nonisolated private init(
        repositoryRootPath: String,
        resolvedRepositoryRootPath: String,
        containerKind: DeliveryContainerKind,
        containerRelativePath: String,
        resolvedContainerPath: String,
        targetNames: [String],
        schemeNames: [String]
    ) {
        self.repositoryRootPath = repositoryRootPath
        self.resolvedRepositoryRootPath = resolvedRepositoryRootPath
        self.containerKind = containerKind
        self.containerRelativePath = containerRelativePath
        self.resolvedContainerPath = resolvedContainerPath
        self.targetNames = targetNames
        self.schemeNames = schemeNames
    }

    nonisolated static func resolving(
        repositoryRootPath: String,
        containerKind: DeliveryContainerKind,
        containerRelativePath: String,
        targetNames: [String],
        schemeNames: [String]
    ) throws -> DeliveryPlanningRepositoryContext {
        let identity = try resolveIdentity(
            repositoryRootPath: repositoryRootPath,
            containerKind: containerKind,
            containerRelativePath: containerRelativePath
        )
        return DeliveryPlanningRepositoryContext(
            repositoryRootPath: identity.repositoryRootPath,
            resolvedRepositoryRootPath: identity.resolvedRepositoryRootPath,
            containerKind: containerKind,
            containerRelativePath: identity.containerRelativePath,
            resolvedContainerPath: identity.resolvedContainerPath,
            targetNames: targetNames,
            schemeNames: schemeNames
        )
    }

    /// Re-resolves the logical paths before a non-fixture consumer uses them.
    /// A later verifier must perform the same check immediately before process launch.
    nonisolated func validateCurrentResolvedIdentity() throws {
        let current = try Self.resolveIdentity(
            repositoryRootPath: repositoryRootPath,
            containerKind: containerKind,
            containerRelativePath: containerRelativePath
        )
        guard current.resolvedRepositoryRootPath == resolvedRepositoryRootPath else {
            throw DeliveryPlanningRepositoryContextResolutionError.repositoryIdentityChanged
        }
        guard current.resolvedContainerPath == resolvedContainerPath else {
            throw DeliveryPlanningRepositoryContextResolutionError.containerIdentityChanged
        }
    }

    nonisolated private struct ResolvedIdentity {
        let repositoryRootPath: String
        let resolvedRepositoryRootPath: String
        let containerRelativePath: String
        let resolvedContainerPath: String
    }

    nonisolated private static func resolveIdentity(
        repositoryRootPath: String,
        containerKind: DeliveryContainerKind,
        containerRelativePath: String
    ) throws -> ResolvedIdentity {
        let rootPath = (repositoryRootPath.trimmingCharacters(in: .whitespacesAndNewlines)
            as NSString).standardizingPath
        guard (rootPath as NSString).isAbsolutePath else {
            throw DeliveryPlanningRepositoryContextResolutionError.invalidRepositoryRootPath
        }

        let relativePath = (containerRelativePath.trimmingCharacters(in: .whitespacesAndNewlines)
            as NSString).standardizingPath
        guard !(relativePath as NSString).isAbsolutePath,
              relativePath != ".",
              relativePath != "..",
              !relativePath.hasPrefix("../"),
              isSupportedContainerPath(relativePath, kind: containerKind) else {
            throw DeliveryPlanningRepositoryContextResolutionError.invalidContainerRelativePath
        }

        var rootIsDirectory = ObjCBool(false)
        guard FileManager.default.fileExists(atPath: rootPath, isDirectory: &rootIsDirectory),
              rootIsDirectory.boolValue else {
            throw DeliveryPlanningRepositoryContextResolutionError.repositoryRootUnavailable
        }

        let logicalRootURL = URL(fileURLWithPath: rootPath, isDirectory: true)
            .standardizedFileURL
        let resolvedRootURL = logicalRootURL
            .resolvingSymlinksInPath()
            .standardizedFileURL
        let logicalContainerURL = logicalRootURL
            .appendingPathComponent(relativePath)
            .standardizedFileURL
        let resolvedContainerURL = logicalContainerURL
            .resolvingSymlinksInPath()
            .standardizedFileURL

        let confirmedRootURL = logicalRootURL
            .resolvingSymlinksInPath()
            .standardizedFileURL
        guard confirmedRootURL.path == resolvedRootURL.path else {
            throw DeliveryPlanningRepositoryContextResolutionError.repositoryIdentityChanged
        }
        guard isContained(resolvedContainerURL, by: resolvedRootURL) else {
            throw DeliveryPlanningRepositoryContextResolutionError.resolvedContainerEscapesRepository
        }

        var containerIsDirectory = ObjCBool(false)
        guard FileManager.default.fileExists(
            atPath: resolvedContainerURL.path,
            isDirectory: &containerIsDirectory
        ) else {
            throw DeliveryPlanningRepositoryContextResolutionError.containerUnavailable
        }
        let hasExpectedType: Bool
        switch containerKind {
        case .xcodeProject, .xcodeWorkspace:
            hasExpectedType = containerIsDirectory.boolValue
        case .swiftPackage:
            hasExpectedType = !containerIsDirectory.boolValue
        }
        guard hasExpectedType else {
            throw DeliveryPlanningRepositoryContextResolutionError.containerUnavailable
        }

        return ResolvedIdentity(
            repositoryRootPath: logicalRootURL.path,
            resolvedRepositoryRootPath: resolvedRootURL.path,
            containerRelativePath: relativePath,
            resolvedContainerPath: resolvedContainerURL.path
        )
    }

    nonisolated private static func isContained(_ candidate: URL, by root: URL) -> Bool {
        let rootComponents = root.pathComponents
        let candidateComponents = candidate.pathComponents
        return candidateComponents.count > rootComponents.count
            && candidateComponents.starts(with: rootComponents)
    }

    nonisolated private static func isSupportedContainerPath(
        _ path: String,
        kind: DeliveryContainerKind
    ) -> Bool {
        let lowercased = path.lowercased()
        switch kind {
        case .xcodeProject:
            return lowercased.hasSuffix(".xcodeproj")
        case .xcodeWorkspace:
            return lowercased.hasSuffix(".xcworkspace")
        case .swiftPackage:
            return (path as NSString).lastPathComponent.lowercased() == "package.swift"
        }
    }
}

nonisolated struct DeliveryPlanGenerationRequest: Equatable, Sendable {
    let requestID: UUID
    let planID: UUID
    let baseStoreRevision: Int
    let brief: FeatureBrief
    let repositoryContext: DeliveryPlanningRepositoryContext
    let generatedAt: Date

    nonisolated init(
        requestID: UUID = UUID(),
        planID: UUID = UUID(),
        baseStoreRevision: Int,
        brief: FeatureBrief,
        repositoryContext: DeliveryPlanningRepositoryContext,
        generatedAt: Date = Date()
    ) {
        self.requestID = requestID
        self.planID = planID
        self.baseStoreRevision = baseStoreRevision
        self.brief = brief
        self.repositoryContext = repositoryContext
        self.generatedAt = generatedAt
    }

    nonisolated var inputFingerprint: String {
        DeliveryPlanGenerationInputFingerprint.make(
            planID: planID,
            baseStoreRevision: baseStoreRevision,
            brief: brief,
            repositoryContext: repositoryContext
        )
    }
}

nonisolated struct DeliveryPlanGenerationResult: Equatable, Sendable {
    let plannerID: String
    let requestID: UUID
    let baseStoreRevision: Int
    let inputFingerprint: String
    var plan: DeliveryPlan
    let generationIssues: [DeliveryPlanGenerationIssue]

    nonisolated var validationIssues: [DeliveryPlanValidationIssue] {
        DeliveryPlanValidator.validate(plan)
    }

    nonisolated var isApprovalEligible: Bool {
        validationIssues.isEmpty
    }

    nonisolated init(
        plannerID: String,
        requestID: UUID,
        baseStoreRevision: Int,
        inputFingerprint: String,
        plan: DeliveryPlan,
        generationIssues: [DeliveryPlanGenerationIssue]
    ) {
        self.plannerID = plannerID
        self.requestID = requestID
        self.baseStoreRevision = baseStoreRevision
        self.inputFingerprint = inputFingerprint
        self.plan = plan
        self.generationIssues = generationIssues
    }
}

nonisolated enum DeliveryPlanGenerationError: Error, Equatable, LocalizedError, Sendable {
    case invalidInput(fieldPath: String, reason: String)
    case responseTooLarge(maximumBytes: Int)
    case invalidUTF8
    case malformedResponse(reason: String)
    case responseCollectionLimitExceeded(fieldPath: String, maximum: Int)
    case unsupportedFormat(found: String?, supported: String)
    case unsupportedSchema(found: Int?, supported: Int)
    case providerFailure(providerID: String, reason: String)
    case conflictingRequestID(UUID)

    nonisolated var errorDescription: String? {
        switch self {
        case let .invalidInput(fieldPath, reason):
            return "Invalid planning input at \(fieldPath): \(reason)"
        case let .responseTooLarge(maximumBytes):
            return "The structured planning response exceeds \(maximumBytes) bytes."
        case .invalidUTF8:
            return "The structured planning response is not valid UTF-8."
        case let .malformedResponse(reason):
            return "The structured planning response is malformed: \(reason)"
        case let .responseCollectionLimitExceeded(fieldPath, maximum):
            return "The structured planning response exceeds the \(fieldPath) limit of \(maximum)."
        case let .unsupportedFormat(found, supported):
            return "Unsupported planning response format \(found ?? "missing"); expected \(supported)."
        case let .unsupportedSchema(found, supported):
            return "Unsupported planning response schema \(found.map(String.init) ?? "missing"); expected \(supported)."
        case let .providerFailure(providerID, reason):
            return "Planning provider \(providerID) failed: \(reason)"
        case let .conflictingRequestID(requestID):
            return "Planning request ID \(requestID.uuidString) was reused with different input."
        }
    }
}

nonisolated enum DeliveryPlanDraftApplicationError: Error, Equatable, LocalizedError, Sendable {
    case inactiveRequest(expected: UUID, received: UUID)
    case staleInput
    case storeRevisionChanged(expected: Int, current: Int)
    case approvedPlanCannotBeReplaced
    case deliveryFactsAlreadyExist
    case generatedPlanAlreadyApproved

    nonisolated var errorDescription: String? {
        switch self {
        case let .inactiveRequest(expected, received):
            return "Planning result \(received.uuidString) is stale; active request is \(expected.uuidString)."
        case .staleInput:
            return "The brief or repository context changed while the plan was being generated."
        case let .storeRevisionChanged(expected, current):
            return "Delivery store revision changed from \(expected) to \(current)."
        case .approvedPlanCannotBeReplaced:
            return "An approved plan cannot be replaced by a generated draft."
        case .deliveryFactsAlreadyExist:
            return "A plan cannot be replaced after delivery facts exist."
        case .generatedPlanAlreadyApproved:
            return "A generated draft cannot carry an approval."
        }
    }
}

nonisolated enum DeliveryPlanDraftApplicator {
    nonisolated static func applying(
        _ result: DeliveryPlanGenerationResult,
        to run: DeliveryRun,
        repositoryContext: DeliveryPlanningRepositoryContext,
        activeRequestID: UUID,
        currentStoreRevision: Int,
        appliedAt: Date = Date()
    ) throws -> DeliveryRun {
        guard result.requestID == activeRequestID else {
            throw DeliveryPlanDraftApplicationError.inactiveRequest(
                expected: activeRequestID,
                received: result.requestID
            )
        }
        guard result.baseStoreRevision == currentStoreRevision else {
            throw DeliveryPlanDraftApplicationError.storeRevisionChanged(
                expected: result.baseStoreRevision,
                current: currentStoreRevision
            )
        }
        let currentFingerprint = DeliveryPlanGenerationInputFingerprint.make(
            planID: result.plan.id,
            baseStoreRevision: result.baseStoreRevision,
            brief: run.brief,
            repositoryContext: repositoryContext
        )
        guard currentFingerprint == result.inputFingerprint else {
            throw DeliveryPlanDraftApplicationError.staleInput
        }
        guard run.plan?.approval == nil else {
            throw DeliveryPlanDraftApplicationError.approvedPlanCannotBeReplaced
        }
        guard run.attempts.isEmpty,
              run.evidenceFacts.isEmpty,
              run.pullRequests.isEmpty else {
            throw DeliveryPlanDraftApplicationError.deliveryFactsAlreadyExist
        }
        guard result.plan.approval == nil else {
            throw DeliveryPlanDraftApplicationError.generatedPlanAlreadyApproved
        }

        var updatedRun = run
        updatedRun.plan = result.plan
        updatedRun.updatedAt = appliedAt
        return updatedRun
    }
}

nonisolated private enum DeliveryPlanGenerationInputFingerprint {
    nonisolated static func make(
        planID: UUID,
        baseStoreRevision: Int,
        brief: FeatureBrief,
        repositoryContext: DeliveryPlanningRepositoryContext
    ) -> String {
        var data = Data()
        append(planID.uuidString.lowercased(), to: &data)
        append(baseStoreRevision, to: &data)
        append(brief.id.uuidString.lowercased(), to: &data)
        append(brief.title, to: &data)
        append(brief.body, to: &data)
        append(brief.repository.rootPath, to: &data)
        append(brief.repository.baseBranch, to: &data)
        append(brief.repository.xcodeContainerRelativePath ?? "", to: &data)
        append(String(brief.createdAt.timeIntervalSince1970.bitPattern), to: &data)
        append(repositoryContext.repositoryRootPath, to: &data)
        append(repositoryContext.resolvedRepositoryRootPath, to: &data)
        append(repositoryContext.containerKind.rawValue, to: &data)
        append(repositoryContext.containerRelativePath, to: &data)
        append(repositoryContext.resolvedContainerPath, to: &data)
        append(repositoryContext.targetNames.count, to: &data)
        repositoryContext.targetNames.forEach { append($0, to: &data) }
        append(repositoryContext.schemeNames.count, to: &data)
        repositoryContext.schemeNames.forEach { append($0, to: &data) }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    nonisolated private static func append(_ value: Int, to data: inout Data) {
        append(String(value), to: &data)
    }

    nonisolated private static func append(_ value: String, to data: inout Data) {
        let bytes = Data(value.utf8)
        var count = UInt64(bytes.count).bigEndian
        withUnsafeBytes(of: &count) { data.append(contentsOf: $0) }
        data.append(bytes)
    }
}

nonisolated protocol DeliveryPlanning: Sendable {
    var plannerID: String { get }

    func generate(
        _ request: DeliveryPlanGenerationRequest
    ) async throws -> DeliveryPlanGenerationResult
}

nonisolated protocol DeliveryPlanStructuredResponseProviding: Sendable {
    var providerID: String { get }

    func response(
        for request: DeliveryPlanGenerationRequest
    ) async throws -> Data
}
