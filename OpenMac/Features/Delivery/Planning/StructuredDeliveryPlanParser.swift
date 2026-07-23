import CryptoKit
import Foundation

nonisolated enum StructuredDeliveryPlanParser {
    nonisolated static let maximumResponseByteCount = 1_048_576
    nonisolated static let maximumTaskCount = 32
    nonisolated static let maximumDependencyCount = 128
    nonisolated static let maximumCriteriaPerTask = 64
    nonisolated static let maximumEvidenceRequirementsPerTask = 64
    nonisolated static let maximumCoverageReferencesPerRequirement = 64
    nonisolated static let maximumHintsPerTask = 64
    nonisolated static let maximumBriefTitleByteCount = 2_048
    nonisolated static let maximumBriefBodyByteCount = 65_536
    nonisolated static let maximumPathByteCount = 4_096
    nonisolated static let maximumBranchByteCount = 1_024
    nonisolated static let maximumRepositoryHintByteCount = 1_024
    nonisolated static let maximumRepositoryHintCount = 256
    nonisolated static let maximumPlanningInputByteCount = 131_072

    nonisolated private struct ResolvedTaskSource {
        let source: StructuredDeliveryTask
        let logicalKey: String
        let id: UUID
        let fieldPath: String
    }

    nonisolated static func validateInput(
        _ request: DeliveryPlanGenerationRequest
    ) throws {
        guard request.baseStoreRevision >= 0 else {
            throw DeliveryPlanGenerationError.invalidInput(
                fieldPath: "baseStoreRevision",
                reason: "A store revision cannot be negative."
            )
        }
        guard !isBlank(request.brief.title) else {
            throw DeliveryPlanGenerationError.invalidInput(
                fieldPath: "brief.title",
                reason: "A feature title is required."
            )
        }
        guard !isBlank(request.brief.body) else {
            throw DeliveryPlanGenerationError.invalidInput(
                fieldPath: "brief.body",
                reason: "A feature brief is required."
            )
        }
        try requireInputByteCount(
            request.brief.title,
            maximum: maximumBriefTitleByteCount,
            fieldPath: "brief.title"
        )
        try requireInputByteCount(
            request.brief.body,
            maximum: maximumBriefBodyByteCount,
            fieldPath: "brief.body"
        )
        guard !isBlank(request.brief.repository.rootPath) else {
            throw DeliveryPlanGenerationError.invalidInput(
                fieldPath: "brief.repository.rootPath",
                reason: "A repository root path is required."
            )
        }
        guard !isBlank(request.brief.repository.baseBranch) else {
            throw DeliveryPlanGenerationError.invalidInput(
                fieldPath: "brief.repository.baseBranch",
                reason: "A base branch is required."
            )
        }
        try requireInputByteCount(
            request.brief.repository.rootPath,
            maximum: maximumPathByteCount,
            fieldPath: "brief.repository.rootPath"
        )
        try requireInputByteCount(
            request.brief.repository.baseBranch,
            maximum: maximumBranchByteCount,
            fieldPath: "brief.repository.baseBranch"
        )
        if let briefContainerPath = request.brief.repository.xcodeContainerRelativePath {
            try requireInputByteCount(
                briefContainerPath,
                maximum: maximumPathByteCount,
                fieldPath: "brief.repository.xcodeContainerRelativePath"
            )
        }
        guard !isBlank(request.repositoryContext.repositoryRootPath) else {
            throw DeliveryPlanGenerationError.invalidInput(
                fieldPath: "repositoryContext.repositoryRootPath",
                reason: "A repository root path is required."
            )
        }
        try requireInputByteCount(
            request.repositoryContext.repositoryRootPath,
            maximum: maximumPathByteCount,
            fieldPath: "repositoryContext.repositoryRootPath"
        )
        try requireInputByteCount(
            request.repositoryContext.resolvedRepositoryRootPath,
            maximum: maximumPathByteCount,
            fieldPath: "repositoryContext.resolvedRepositoryRootPath"
        )
        try requireInputByteCount(
            request.repositoryContext.containerRelativePath,
            maximum: maximumPathByteCount,
            fieldPath: "repositoryContext.containerRelativePath"
        )
        try requireInputByteCount(
            request.repositoryContext.resolvedContainerPath,
            maximum: maximumPathByteCount,
            fieldPath: "repositoryContext.resolvedContainerPath"
        )

        let briefRoot = standardizedPath(request.brief.repository.rootPath)
        let contextRoot = standardizedPath(request.repositoryContext.repositoryRootPath)
        guard (contextRoot as NSString).isAbsolutePath else {
            throw DeliveryPlanGenerationError.invalidInput(
                fieldPath: "repositoryContext.repositoryRootPath",
                reason: "The repository root must be an absolute path."
            )
        }
        guard briefRoot == contextRoot else {
            throw DeliveryPlanGenerationError.invalidInput(
                fieldPath: "repositoryContext.repositoryRootPath",
                reason: "The repository context does not match the feature brief."
            )
        }

        let containerPath = trimmed(request.repositoryContext.containerRelativePath)
        guard !containerPath.isEmpty else {
            throw DeliveryPlanGenerationError.invalidInput(
                fieldPath: "repositoryContext.containerRelativePath",
                reason: "An Xcode or Swift package container is required."
            )
        }
        guard isSupportedContainerPath(
            containerPath,
            kind: request.repositoryContext.containerKind
        ) else {
            throw DeliveryPlanGenerationError.invalidInput(
                fieldPath: "repositoryContext.containerRelativePath",
                reason: "The path does not match its declared container kind."
            )
        }
        guard isContainedRelativePath(containerPath, repositoryRootPath: contextRoot) else {
            throw DeliveryPlanGenerationError.invalidInput(
                fieldPath: "repositoryContext.containerRelativePath",
                reason: "The container must be a relative path contained by the repository."
            )
        }

        let resolvedRoot = standardizedPath(
            request.repositoryContext.resolvedRepositoryRootPath
        )
        let resolvedContainer = standardizedPath(
            request.repositoryContext.resolvedContainerPath
        )
        guard (resolvedRoot as NSString).isAbsolutePath else {
            throw DeliveryPlanGenerationError.invalidInput(
                fieldPath: "repositoryContext.resolvedRepositoryRootPath",
                reason: "The resolved repository root must be an absolute path."
            )
        }
        guard (resolvedContainer as NSString).isAbsolutePath,
              isAbsolutePath(resolvedContainer, containedBy: resolvedRoot),
              isSupportedContainerPath(
                  resolvedContainer,
                  kind: request.repositoryContext.containerKind
              ) else {
            throw DeliveryPlanGenerationError.invalidInput(
                fieldPath: "repositoryContext.resolvedContainerPath",
                reason: "The resolved container must remain inside the resolved repository root."
            )
        }

        if let briefContainerPath = request.brief.repository.xcodeContainerRelativePath,
           standardizedRelativePath(briefContainerPath) != standardizedRelativePath(containerPath) {
            throw DeliveryPlanGenerationError.invalidInput(
                fieldPath: "repositoryContext.containerRelativePath",
                reason: "The repository context container does not match the feature brief."
            )
        }

        guard request.repositoryContext.targetNames.count <= maximumRepositoryHintCount else {
            throw DeliveryPlanGenerationError.invalidInput(
                fieldPath: "repositoryContext.targetNames",
                reason: "Repository target inventory exceeds \(maximumRepositoryHintCount) entries."
            )
        }
        guard request.repositoryContext.schemeNames.count <= maximumRepositoryHintCount else {
            throw DeliveryPlanGenerationError.invalidInput(
                fieldPath: "repositoryContext.schemeNames",
                reason: "Repository scheme inventory exceeds \(maximumRepositoryHintCount) entries."
            )
        }
        for (index, target) in request.repositoryContext.targetNames.enumerated() {
            try requireInputByteCount(
                target,
                maximum: maximumRepositoryHintByteCount,
                fieldPath: "repositoryContext.targetNames[\(index)]"
            )
        }
        for (index, scheme) in request.repositoryContext.schemeNames.enumerated() {
            try requireInputByteCount(
                scheme,
                maximum: maximumRepositoryHintByteCount,
                fieldPath: "repositoryContext.schemeNames[\(index)]"
            )
        }
        let totalInputByteCount = planningInputStrings(request).reduce(0) {
            $0 + $1.utf8.count
        }
        guard totalInputByteCount <= maximumPlanningInputByteCount else {
            throw DeliveryPlanGenerationError.invalidInput(
                fieldPath: "request",
                reason: "Planning input exceeds \(maximumPlanningInputByteCount) UTF-8 bytes."
            )
        }
    }

    nonisolated static func parse(
        _ data: Data,
        request: DeliveryPlanGenerationRequest,
        plannerID: String
    ) throws -> DeliveryPlanGenerationResult {
        try validateInput(request)
        guard data.count <= maximumResponseByteCount else {
            throw DeliveryPlanGenerationError.responseTooLarge(
                maximumBytes: maximumResponseByteCount
            )
        }
        guard let responseText = String(data: data, encoding: .utf8) else {
            throw DeliveryPlanGenerationError.invalidUTF8
        }

        let jsonData = try normalizedJSONData(from: responseText)
        do {
            try StrictJSONValidator.validate(jsonData)
        } catch {
            throw DeliveryPlanGenerationError.malformedResponse(
                reason: String(describing: error)
            )
        }
        let response: StructuredDeliveryPlanResponse
        do {
            response = try JSONDecoder().decode(
                StructuredDeliveryPlanResponse.self,
                from: jsonData
            )
        } catch {
            throw DeliveryPlanGenerationError.malformedResponse(
                reason: String(describing: error)
            )
        }

        guard response.format == StructuredDeliveryPlanResponse.formatIdentifier else {
            throw DeliveryPlanGenerationError.unsupportedFormat(
                found: response.format,
                supported: StructuredDeliveryPlanResponse.formatIdentifier
            )
        }
        guard response.schemaVersion == StructuredDeliveryPlanResponse.currentSchemaVersion else {
            throw DeliveryPlanGenerationError.unsupportedSchema(
                found: response.schemaVersion,
                supported: StructuredDeliveryPlanResponse.currentSchemaVersion
            )
        }

        try validateCollectionLimits(response)

        return compile(response, request: request, plannerID: plannerID)
    }

    nonisolated private static func compile(
        _ response: StructuredDeliveryPlanResponse,
        request: DeliveryPlanGenerationRequest,
        plannerID: String
    ) -> DeliveryPlanGenerationResult {
        let sourceTasks = response.tasks
        var issues: [DeliveryPlanGenerationIssue] = []

        if !(3 ... 5).contains(sourceTasks.count) {
            issues.append(
                DeliveryPlanGenerationIssue(
                    code: .taskCountOutOfRange,
                    fieldPath: "tasks",
                    message: "Initial generation must contain between three and five tasks."
                )
            )
        }
        if response.revision != 1 {
            issues.append(
                DeliveryPlanGenerationIssue(
                    code: .invalidRevision,
                    fieldPath: "revision",
                    message: "A newly generated plan always starts at revision one."
                )
            )
        }

        var taskKeyCounts: [String: Int] = [:]
        var taskIDsByKey: [String: [UUID]] = [:]
        var resolvedSources: [ResolvedTaskSource] = []
        for (index, source) in sourceTasks.enumerated() {
            let fieldPath = "tasks[\(index)]"
            let rawKey = normalizedKey(source.key)
            let logicalKey: String
            if rawKey.isEmpty {
                logicalKey = "__missing-task-\(index + 1)"
                issues.append(
                    DeliveryPlanGenerationIssue(
                        code: .missingTaskKey,
                        fieldPath: "\(fieldPath).key",
                        message: "Every structured task needs a non-empty local key."
                    )
                )
            } else {
                logicalKey = rawKey
            }

            let occurrence = taskKeyCounts[logicalKey, default: 0]
            taskKeyCounts[logicalKey] = occurrence + 1
            if occurrence > 0 {
                issues.append(
                    DeliveryPlanGenerationIssue(
                        code: .duplicateTaskKey,
                        fieldPath: "\(fieldPath).key",
                        message: "Task key '\(trimmed(source.key ?? ""))' is duplicated."
                    )
                )
            }

            let taskID = stableUUID(
                namespace: request.planID,
                value: "task:\(logicalKey):\(occurrence)"
            )
            taskIDsByKey[logicalKey, default: []].append(taskID)
            resolvedSources.append(
                ResolvedTaskSource(
                    source: source,
                    logicalKey: logicalKey,
                    id: taskID,
                    fieldPath: fieldPath
                )
            )
        }

        let repositoryTargets = normalizedHints(request.repositoryContext.targetNames)
        let repositorySchemes = normalizedHints(request.repositoryContext.schemeNames)
        let fallbackTargets = repositoryTargets.count == 1 ? repositoryTargets : []
        let fallbackSchemes = repositorySchemes.count == 1 ? repositorySchemes : []
        var taskFieldPathByID: [UUID: String] = [:]
        var tasks: [DeliveryTask] = []
        for resolved in resolvedSources {
            let compiled = compileTask(
                resolved,
                fallbackTargets: fallbackTargets,
                fallbackSchemes: fallbackSchemes,
                repositoryTargets: repositoryTargets,
                repositorySchemes: repositorySchemes,
                issues: &issues
            )
            tasks.append(compiled)
            taskFieldPathByID[compiled.id] = resolved.fieldPath
        }

        var dependencyFieldPathByEdge: [DependencyEdge: String] = [:]
        let dependencies = response.dependencies.enumerated().map { index, source in
            let fieldPath = "dependencies[\(index)]"
            let prerequisiteID = resolveTaskReference(
                source.prerequisiteTaskKey,
                fieldPath: "\(fieldPath).prerequisiteTaskKey",
                planID: request.planID,
                taskIDsByKey: taskIDsByKey,
                issues: &issues
            )
            let dependentID = resolveTaskReference(
                source.dependentTaskKey,
                fieldPath: "\(fieldPath).dependentTaskKey",
                planID: request.planID,
                taskIDsByKey: taskIDsByKey,
                issues: &issues
            )
            let edge = DependencyEdge(
                prerequisiteTaskID: prerequisiteID,
                dependentTaskID: dependentID
            )
            dependencyFieldPathByEdge[edge] = fieldPath
            return edge
        }

        let plan = DeliveryPlan(
            id: request.planID,
            revision: 1,
            tasks: tasks,
            dependencyEdges: dependencies,
            unresolvedGenerationBlockers: issues.filter { $0.severity == .blocking },
            approval: nil,
            createdAt: request.generatedAt,
            updatedAt: request.generatedAt
        )

        for validationIssue in DeliveryPlanValidator.validate(plan)
            where validationIssue.code != .unresolvedGenerationIssue {
            let fieldPath: String
            if let taskID = validationIssue.taskID,
               let taskPath = taskFieldPathByID[taskID] {
                fieldPath = taskPath
            } else if let edge = validationIssue.dependencyEdge,
                      let dependencyPath = dependencyFieldPathByEdge[edge] {
                fieldPath = dependencyPath
            } else {
                fieldPath = "plan"
            }
            issues.append(
                DeliveryPlanGenerationIssue(
                    code: .invalidPlan,
                    fieldPath: fieldPath,
                    message: "\(validationIssue.code.rawValue): \(validationIssue.message)"
                )
            )
        }

        return DeliveryPlanGenerationResult(
            plannerID: plannerID,
            requestID: request.requestID,
            baseStoreRevision: request.baseStoreRevision,
            inputFingerprint: request.inputFingerprint,
            repositoryIdentity: request.repositoryIdentity,
            plan: plan,
            generationIssues: issues
        )
    }

    nonisolated private static func compileTask(
        _ resolved: ResolvedTaskSource,
        fallbackTargets: [String],
        fallbackSchemes: [String],
        repositoryTargets: [String],
        repositorySchemes: [String],
        issues: inout [DeliveryPlanGenerationIssue]
    ) -> DeliveryTask {
        let source = resolved.source
        let textualDependencies = (source.dependsOn ?? []).filter { !isBlank($0) }
        if !textualDependencies.isEmpty {
            issues.append(
                DeliveryPlanGenerationIssue(
                    code: .textualDependencyNotAllowed,
                    fieldPath: "\(resolved.fieldPath).dependsOn",
                    message: "Dependencies must use the top-level typed dependency array."
                )
            )
        }

        var criterionKeyCounts: [String: Int] = [:]
        var criterionIDsByKey: [String: [UUID]] = [:]
        let criteria = (source.acceptanceCriteria ?? []).enumerated().map { index, criterion in
            let fieldPath = "\(resolved.fieldPath).acceptanceCriteria[\(index)]"
            let rawKey = normalizedKey(criterion.key)
            let logicalKey: String
            if rawKey.isEmpty {
                logicalKey = "__missing-criterion-\(index + 1)"
                issues.append(
                    DeliveryPlanGenerationIssue(
                        code: .missingAcceptanceCriterionKey,
                        fieldPath: "\(fieldPath).key",
                        message: "Every acceptance criterion needs a non-empty local key."
                    )
                )
            } else {
                logicalKey = rawKey
            }

            let occurrence = criterionKeyCounts[logicalKey, default: 0]
            criterionKeyCounts[logicalKey] = occurrence + 1
            if occurrence > 0 {
                issues.append(
                    DeliveryPlanGenerationIssue(
                        code: .duplicateAcceptanceCriterionKey,
                        fieldPath: "\(fieldPath).key",
                        message: "Acceptance criterion key '\(trimmed(criterion.key ?? ""))' is duplicated."
                    )
                )
            }

            let criterionID = stableUUID(
                namespace: resolved.id,
                value: "criterion:\(logicalKey):\(occurrence)"
            )
            criterionIDsByKey[logicalKey, default: []].append(criterionID)
            return AcceptanceCriterion(
                id: criterionID,
                statement: trimmed(criterion.statement ?? "")
            )
        }

        var evidenceKeyCounts: [String: Int] = [:]
        let evidence = (source.evidenceRequirements ?? []).enumerated().map { index, requirement in
            let fieldPath = "\(resolved.fieldPath).evidenceRequirements[\(index)]"
            let rawKey = normalizedKey(requirement.key)
            let logicalKey: String
            if rawKey.isEmpty {
                logicalKey = "__missing-evidence-\(index + 1)"
                issues.append(
                    DeliveryPlanGenerationIssue(
                        code: .missingEvidenceRequirementKey,
                        fieldPath: "\(fieldPath).key",
                        message: "Every evidence requirement needs a non-empty local key."
                    )
                )
            } else {
                logicalKey = rawKey
            }

            let occurrence = evidenceKeyCounts[logicalKey, default: 0]
            evidenceKeyCounts[logicalKey] = occurrence + 1
            if occurrence > 0 {
                issues.append(
                    DeliveryPlanGenerationIssue(
                        code: .duplicateEvidenceRequirementKey,
                        fieldPath: "\(fieldPath).key",
                        message: "Evidence requirement key '\(trimmed(requirement.key ?? ""))' is duplicated."
                    )
                )
            }

            let evidenceKind: EvidenceKind
            if let resolvedKind = resolvedEvidenceKind(requirement.kind) {
                evidenceKind = resolvedKind
            } else {
                evidenceKind = .custom
                issues.append(
                    DeliveryPlanGenerationIssue(
                        code: .unknownEvidenceKind,
                        fieldPath: "\(fieldPath).kind",
                        message: "Evidence kind '\(trimmed(requirement.kind ?? ""))' is not supported."
                    )
                )
            }

            let coveredCriterionIDs = (requirement.coveredCriterionKeys ?? []).map { criterionKey in
                let normalized = normalizedKey(criterionKey)
                if let matchingIDs = criterionIDsByKey[normalized],
                   let firstID = matchingIDs.first {
                    return firstID
                }

                issues.append(
                    DeliveryPlanGenerationIssue(
                        code: .unknownAcceptanceCriterionKey,
                        fieldPath: "\(fieldPath).covers",
                        message: "Evidence references unknown criterion key '\(trimmed(criterionKey))'."
                    )
                )
                return stableUUID(
                    namespace: resolved.id,
                    value: "missing-criterion:\(normalized)"
                )
            }

            return EvidenceRequirement(
                id: stableUUID(
                    namespace: resolved.id,
                    value: "evidence:\(logicalKey):\(occurrence)"
                ),
                kind: evidenceKind,
                description: trimmed(requirement.description ?? ""),
                coveredCriterionIDs: coveredCriterionIDs
            )
        }

        let riskLevel: DeliveryRiskLevel
        if let rawRisk = source.riskLevel,
           !isBlank(rawRisk),
           let resolvedRisk = DeliveryRiskLevel.allCases.first(where: {
               $0.rawValue.caseInsensitiveCompare(trimmed(rawRisk)) == .orderedSame
           }) {
            riskLevel = resolvedRisk
        } else if isBlank(source.riskLevel ?? "") {
            riskLevel = .medium
            issues.append(
                DeliveryPlanGenerationIssue(
                    code: .missingRiskLevel,
                    fieldPath: "\(resolved.fieldPath).riskLevel",
                    message: "Every task needs an explicit risk level."
                )
            )
        } else {
            riskLevel = .medium
            issues.append(
                DeliveryPlanGenerationIssue(
                    code: .unknownRiskLevel,
                    fieldPath: "\(resolved.fieldPath).riskLevel",
                    message: "Risk level '\(trimmed(source.riskLevel ?? ""))' is not supported."
                )
            )
        }

        let responseTargets = normalizedHints(source.targetHints ?? [])
        let responseSchemes = normalizedHints(source.schemeHints ?? [])
        appendUnknownHintIssues(
            responseTargets,
            knownHints: repositoryTargets,
            code: .unknownTargetHint,
            fieldPath: "\(resolved.fieldPath).targetHints",
            kind: "target",
            issues: &issues
        )
        appendUnknownHintIssues(
            responseSchemes,
            knownHints: repositorySchemes,
            code: .unknownSchemeHint,
            fieldPath: "\(resolved.fieldPath).schemeHints",
            kind: "scheme",
            issues: &issues
        )
        let acceptedTargets = hintsPresentInInventory(
            responseTargets,
            inventory: repositoryTargets
        )
        let acceptedSchemes = hintsPresentInInventory(
            responseSchemes,
            inventory: repositorySchemes
        )
        let targetHints = acceptedTargets.isEmpty ? fallbackTargets : acceptedTargets
        let schemeHints = acceptedSchemes.isEmpty ? fallbackSchemes : acceptedSchemes
        if targetHints.isEmpty && schemeHints.isEmpty {
            issues.append(
                DeliveryPlanGenerationIssue(
                    code: .missingPlanningHint,
                    fieldPath: resolved.fieldPath,
                    message: "Every generated task needs at least one target or scheme hint."
                )
            )
        }

        return DeliveryTask(
            id: resolved.id,
            title: trimmed(source.title ?? ""),
            workerPrompt: trimmed(source.workerPrompt ?? ""),
            acceptanceCriteria: criteria,
            riskLevel: riskLevel,
            evidenceRequirements: evidence,
            targetHints: targetHints,
            schemeHints: schemeHints,
            humanActionHint: source.humanActionHint.map(trimmed)
        )
    }

    nonisolated private static func resolveTaskReference(
        _ rawKey: String?,
        fieldPath: String,
        planID: UUID,
        taskIDsByKey: [String: [UUID]],
        issues: inout [DeliveryPlanGenerationIssue]
    ) -> UUID {
        let key = normalizedKey(rawKey)
        guard let matchingIDs = taskIDsByKey[key],
              let firstID = matchingIDs.first else {
            issues.append(
                DeliveryPlanGenerationIssue(
                    code: .unknownDependencyTaskKey,
                    fieldPath: fieldPath,
                    message: "Dependency references unknown task key '\(trimmed(rawKey ?? ""))'."
                )
            )
            return stableUUID(namespace: planID, value: "missing-task:\(key)")
        }

        if matchingIDs.count > 1 {
            issues.append(
                DeliveryPlanGenerationIssue(
                    code: .ambiguousDependencyTaskKey,
                    fieldPath: fieldPath,
                    message: "Dependency task key '\(trimmed(rawKey ?? ""))' is ambiguous."
                )
            )
        }
        return firstID
    }

    nonisolated private static func normalizedJSONData(from responseText: String) throws -> Data {
        let trimmedText = responseText.trimmingCharacters(in: .whitespacesAndNewlines)
        let jsonText: String
        if trimmedText.hasPrefix("```") {
            let lines = trimmedText.components(separatedBy: .newlines)
            guard let firstLine = lines.first,
                  firstLine == "```" || firstLine.lowercased() == "```json",
                  lines.last == "```",
                  lines.count >= 3 else {
                throw DeliveryPlanGenerationError.malformedResponse(
                    reason: "A fenced response must contain exactly one complete JSON document."
                )
            }
            jsonText = lines.dropFirst().dropLast().joined(separator: "\n")
        } else {
            jsonText = trimmedText
        }

        guard let data = jsonText.data(using: .utf8) else {
            throw DeliveryPlanGenerationError.invalidUTF8
        }
        return data
    }

    nonisolated private static func validateCollectionLimits(
        _ response: StructuredDeliveryPlanResponse
    ) throws {
        try requireCount(
            response.tasks.count,
            maximum: maximumTaskCount,
            fieldPath: "tasks"
        )
        try requireCount(
            response.dependencies.count,
            maximum: maximumDependencyCount,
            fieldPath: "dependencies"
        )
        for (taskIndex, task) in response.tasks.enumerated() {
            try requireCount(
                task.acceptanceCriteria?.count ?? 0,
                maximum: maximumCriteriaPerTask,
                fieldPath: "tasks[\(taskIndex)].acceptanceCriteria"
            )
            try requireCount(
                task.evidenceRequirements?.count ?? 0,
                maximum: maximumEvidenceRequirementsPerTask,
                fieldPath: "tasks[\(taskIndex)].evidenceRequirements"
            )
            try requireCount(
                task.targetHints?.count ?? 0,
                maximum: maximumHintsPerTask,
                fieldPath: "tasks[\(taskIndex)].targetHints"
            )
            try requireCount(
                task.schemeHints?.count ?? 0,
                maximum: maximumHintsPerTask,
                fieldPath: "tasks[\(taskIndex)].schemeHints"
            )
            for (requirementIndex, requirement) in (task.evidenceRequirements ?? []).enumerated() {
                try requireCount(
                    requirement.coveredCriterionKeys?.count ?? 0,
                    maximum: maximumCoverageReferencesPerRequirement,
                    fieldPath: "tasks[\(taskIndex)].evidenceRequirements[\(requirementIndex)].covers"
                )
            }
        }
    }

    nonisolated private static func requireCount(
        _ count: Int,
        maximum: Int,
        fieldPath: String
    ) throws {
        guard count <= maximum else {
            throw DeliveryPlanGenerationError.responseCollectionLimitExceeded(
                fieldPath: fieldPath,
                maximum: maximum
            )
        }
    }

    nonisolated private static func requireInputByteCount(
        _ value: String,
        maximum: Int,
        fieldPath: String
    ) throws {
        guard value.utf8.count <= maximum else {
            throw DeliveryPlanGenerationError.invalidInput(
                fieldPath: fieldPath,
                reason: "The value exceeds \(maximum) UTF-8 bytes."
            )
        }
    }

    nonisolated private static func planningInputStrings(
        _ request: DeliveryPlanGenerationRequest
    ) -> [String] {
        [
            request.brief.title,
            request.brief.body,
            request.brief.repository.rootPath,
            request.brief.repository.baseBranch,
            request.brief.repository.xcodeContainerRelativePath ?? "",
            request.repositoryContext.repositoryRootPath,
            request.repositoryContext.resolvedRepositoryRootPath,
            request.repositoryContext.containerRelativePath,
            request.repositoryContext.resolvedContainerPath
        ] + request.repositoryContext.targetNames + request.repositoryContext.schemeNames
    }

    nonisolated private static func appendUnknownHintIssues(
        _ hints: [String],
        knownHints: [String],
        code: DeliveryPlanGenerationIssueCode,
        fieldPath: String,
        kind: String,
        issues: inout [DeliveryPlanGenerationIssue]
    ) {
        let known = Set(knownHints.map { $0.lowercased() })
        for hint in hints where !known.contains(hint.lowercased()) {
            issues.append(
                DeliveryPlanGenerationIssue(
                    code: code,
                    fieldPath: fieldPath,
                    message: "The structured response references unknown \(kind) '\(hint)'."
                )
            )
        }
    }

    nonisolated private static func hintsPresentInInventory(
        _ hints: [String],
        inventory: [String]
    ) -> [String] {
        guard !inventory.isEmpty else { return hints }
        let known = Set(inventory.map { $0.lowercased() })
        return hints.filter { known.contains($0.lowercased()) }
    }

    nonisolated private static func resolvedEvidenceKind(_ rawKind: String?) -> EvidenceKind? {
        let candidate = trimmed(rawKind ?? "")
        guard !candidate.isEmpty else { return nil }
        return EvidenceKind.allCases.first {
            $0.rawValue.caseInsensitiveCompare(candidate) == .orderedSame
        }
    }

    nonisolated private static func normalizedHints(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []
        for value in values {
            let candidate = trimmed(value)
            guard !candidate.isEmpty else { continue }
            let key = candidate.lowercased()
            guard seen.insert(key).inserted else { continue }
            result.append(candidate)
        }
        return result
    }

    nonisolated private static func normalizedKey(_ value: String?) -> String {
        trimmed(value ?? "").lowercased()
    }

    nonisolated private static func trimmed(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    nonisolated private static func isBlank(_ value: String) -> Bool {
        trimmed(value).isEmpty
    }

    nonisolated private static func standardizedPath(_ value: String) -> String {
        (trimmed(value) as NSString).standardizingPath
    }

    nonisolated private static func standardizedRelativePath(_ value: String) -> String {
        (trimmed(value) as NSString).standardizingPath
    }

    nonisolated private static func isContainedRelativePath(
        _ path: String,
        repositoryRootPath: String
    ) -> Bool {
        let pathValue = trimmed(path)
        guard !(pathValue as NSString).isAbsolutePath else { return false }
        let standardized = standardizedRelativePath(pathValue)
        guard standardized != ".",
              standardized != "..",
              !standardized.hasPrefix("../") else {
            return false
        }

        let repositoryURL = URL(
            fileURLWithPath: repositoryRootPath,
            isDirectory: true
        ).standardizedFileURL
        let resolvedURL = repositoryURL
            .appendingPathComponent(standardized)
            .standardizedFileURL
        let rootPrefix = repositoryURL.path.hasSuffix("/")
            ? repositoryURL.path
            : repositoryURL.path + "/"
        return resolvedURL.path.hasPrefix(rootPrefix)
    }

    nonisolated private static func isAbsolutePath(
        _ path: String,
        containedBy rootPath: String
    ) -> Bool {
        let root = URL(fileURLWithPath: rootPath, isDirectory: true).standardizedFileURL
        let candidate = URL(fileURLWithPath: path).standardizedFileURL
        let rootPrefix = root.path.hasSuffix("/") ? root.path : root.path + "/"
        return candidate.path.hasPrefix(rootPrefix)
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

    nonisolated private static func stableUUID(namespace: UUID, value: String) -> UUID {
        var data = Data(namespace.uuidString.lowercased().utf8)
        data.append(0)
        data.append(contentsOf: value.utf8)
        var bytes = Array(SHA256.hash(data: data).prefix(16))
        bytes[6] = (bytes[6] & 0x0f) | 0x50
        bytes[8] = (bytes[8] & 0x3f) | 0x80
        return UUID(
            uuid: (
                bytes[0], bytes[1], bytes[2], bytes[3],
                bytes[4], bytes[5], bytes[6], bytes[7],
                bytes[8], bytes[9], bytes[10], bytes[11],
                bytes[12], bytes[13], bytes[14], bytes[15]
            )
        )
    }
}
