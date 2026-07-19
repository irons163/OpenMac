import Foundation

nonisolated struct StructuredDeliveryPlanResponse: Equatable, Codable, Sendable {
    nonisolated static let formatIdentifier = "openmac.delivery-plan"
    nonisolated static let currentSchemaVersion = 1

    var format: String
    var schemaVersion: Int
    var revision: Int
    var tasks: [StructuredDeliveryTask]
    var dependencies: [StructuredDeliveryDependency]

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case format
        case schemaVersion
        case revision
        case tasks
        case dependencies
    }

    nonisolated init(
        format: String = StructuredDeliveryPlanResponse.formatIdentifier,
        schemaVersion: Int = StructuredDeliveryPlanResponse.currentSchemaVersion,
        revision: Int = 1,
        tasks: [StructuredDeliveryTask],
        dependencies: [StructuredDeliveryDependency] = []
    ) {
        self.format = format
        self.schemaVersion = schemaVersion
        self.revision = revision
        self.tasks = tasks
        self.dependencies = dependencies
    }

    nonisolated init(from decoder: any Decoder) throws {
        try decoder.rejectUnknownKeys(CodingKeys.self)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        format = try container.decode(String.self, forKey: .format)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        revision = try container.decode(Int.self, forKey: .revision)
        tasks = try container.decode([StructuredDeliveryTask].self, forKey: .tasks)
        dependencies = try container.decode(
            [StructuredDeliveryDependency].self,
            forKey: .dependencies
        )
    }
}

private nonisolated struct DynamicCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int?

    nonisolated init?(stringValue: String) {
        self.stringValue = stringValue
        self.intValue = nil
    }

    nonisolated init?(intValue: Int) {
        self.stringValue = String(intValue)
        self.intValue = intValue
    }
}

nonisolated struct StructuredDeliveryTask: Equatable, Codable, Sendable {
    var key: String?
    var title: String?
    var workerPrompt: String?
    var acceptanceCriteria: [StructuredAcceptanceCriterion]?
    var riskLevel: String?
    var evidenceRequirements: [StructuredEvidenceRequirement]?
    var targetHints: [String]?
    var schemeHints: [String]?
    var humanActionHint: String?
    var dependsOn: [String]?

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case key
        case title
        case workerPrompt
        case acceptanceCriteria
        case riskLevel
        case evidenceRequirements
        case targetHints
        case schemeHints
        case humanActionHint
        case dependsOn
    }

    nonisolated init(
        key: String?,
        title: String?,
        workerPrompt: String?,
        acceptanceCriteria: [StructuredAcceptanceCriterion]?,
        riskLevel: String?,
        evidenceRequirements: [StructuredEvidenceRequirement]?,
        targetHints: [String]? = nil,
        schemeHints: [String]? = nil,
        humanActionHint: String? = nil,
        dependsOn: [String]? = nil
    ) {
        self.key = key
        self.title = title
        self.workerPrompt = workerPrompt
        self.acceptanceCriteria = acceptanceCriteria
        self.riskLevel = riskLevel
        self.evidenceRequirements = evidenceRequirements
        self.targetHints = targetHints
        self.schemeHints = schemeHints
        self.humanActionHint = humanActionHint
        self.dependsOn = dependsOn
    }

    nonisolated init(from decoder: any Decoder) throws {
        try decoder.rejectUnknownKeys(CodingKeys.self)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        key = try container.decodeIfPresent(String.self, forKey: .key)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        workerPrompt = try container.decodeIfPresent(String.self, forKey: .workerPrompt)
        acceptanceCriteria = try container.decodeIfPresent(
            [StructuredAcceptanceCriterion].self,
            forKey: .acceptanceCriteria
        )
        riskLevel = try container.decodeIfPresent(String.self, forKey: .riskLevel)
        evidenceRequirements = try container.decodeIfPresent(
            [StructuredEvidenceRequirement].self,
            forKey: .evidenceRequirements
        )
        targetHints = try container.decodeIfPresent([String].self, forKey: .targetHints)
        schemeHints = try container.decodeIfPresent([String].self, forKey: .schemeHints)
        humanActionHint = try container.decodeIfPresent(
            String.self,
            forKey: .humanActionHint
        )
        dependsOn = try container.decodeIfPresent([String].self, forKey: .dependsOn)
    }
}

nonisolated struct StructuredAcceptanceCriterion: Equatable, Codable, Sendable {
    var key: String?
    var statement: String?

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case key
        case statement
    }

    nonisolated init(key: String?, statement: String?) {
        self.key = key
        self.statement = statement
    }

    nonisolated init(from decoder: any Decoder) throws {
        try decoder.rejectUnknownKeys(CodingKeys.self)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        key = try container.decodeIfPresent(String.self, forKey: .key)
        statement = try container.decodeIfPresent(String.self, forKey: .statement)
    }
}

nonisolated struct StructuredEvidenceRequirement: Equatable, Codable, Sendable {
    var key: String?
    var kind: String?
    var description: String?
    var coveredCriterionKeys: [String]?

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case key
        case kind
        case description
        case coveredCriterionKeys = "covers"
    }

    nonisolated init(
        key: String?,
        kind: String?,
        description: String?,
        coveredCriterionKeys: [String]?
    ) {
        self.key = key
        self.kind = kind
        self.description = description
        self.coveredCriterionKeys = coveredCriterionKeys
    }

    nonisolated init(from decoder: any Decoder) throws {
        try decoder.rejectUnknownKeys(CodingKeys.self)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        key = try container.decodeIfPresent(String.self, forKey: .key)
        kind = try container.decodeIfPresent(String.self, forKey: .kind)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        coveredCriterionKeys = try container.decodeIfPresent(
            [String].self,
            forKey: .coveredCriterionKeys
        )
    }
}

nonisolated struct StructuredDeliveryDependency: Equatable, Codable, Sendable {
    var prerequisiteTaskKey: String?
    var dependentTaskKey: String?

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case prerequisiteTaskKey
        case dependentTaskKey
    }

    nonisolated init(
        prerequisiteTaskKey: String?,
        dependentTaskKey: String?
    ) {
        self.prerequisiteTaskKey = prerequisiteTaskKey
        self.dependentTaskKey = dependentTaskKey
    }

    nonisolated init(from decoder: any Decoder) throws {
        try decoder.rejectUnknownKeys(CodingKeys.self)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        prerequisiteTaskKey = try container.decodeIfPresent(
            String.self,
            forKey: .prerequisiteTaskKey
        )
        dependentTaskKey = try container.decodeIfPresent(
            String.self,
            forKey: .dependentTaskKey
        )
    }
}

private extension Decoder {
    nonisolated func rejectUnknownKeys<Key>(_ keyType: Key.Type) throws
        where Key: CodingKey & CaseIterable, Key.AllCases.Element == Key {
        let dynamicContainer = try container(keyedBy: DynamicCodingKey.self)
        let allowedKeys = Set(Key.allCases.map(\.stringValue))
        let unknownKeys = dynamicContainer.allKeys
            .map(\.stringValue)
            .filter { !allowedKeys.contains($0) }
            .sorted()
        guard unknownKeys.isEmpty else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: codingPath,
                    debugDescription: "Unknown keys: \(unknownKeys.joined(separator: ", "))."
                )
            )
        }
    }
}
