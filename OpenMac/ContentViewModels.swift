import Foundation
import SwiftUI
import UniformTypeIdentifiers

struct TaskDragPayload: Codable, Transferable {
    let taskID: UUID

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .openMACTaskDragPayload)
    }
}

extension UTType {
    // Internal drag payload for in-app transfers; no exported UTI registration needed.
    static let openMACTaskDragPayload = UTType(importedAs: "com.irons.openmac.task-drag-payload")
}

struct PMBriefTemplateOption: Identifiable, Equatable {
    let id: String
    let title: String
}

struct PMBriefTemplateDefinition: Equatable {
    let id: String
    let optionTitleKey: String
    let defaultProjectNameKey: String
    let briefKey: String
}

struct CodexSkillTemplateOption: Identifiable, Equatable {
    let id: String
    let skillName: String
    let title: String
    let suggestedTaskTitle: String
    let suggestedTaskDetails: String
    let capabilityLabels: [String]
    let storyPoints: Int

    var requiredSkillsText: String {
        capabilityLabels.joined(separator: ", ")
    }
}

struct AssigneeFilterOption: Identifiable, Hashable {
    let key: String
    let label: String

    var id: String { key }
}
