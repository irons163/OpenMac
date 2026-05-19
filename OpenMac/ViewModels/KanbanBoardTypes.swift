import Foundation

enum TaskAssigneeFilter: Equatable {
    case all
    case unassigned
    case assigned(UUID)
}

enum BoardHealthAction: Equatable {
    case autoAssignUnassignedTodo
    case createMissingDependencyTasks
    case openManualTriage
    case openNewAgent
    case rebalanceTodoLoad
    case increaseWIPLimit(KanbanStatus)
    case archiveDone

    var isAutoFixable: Bool {
        switch self {
        case .openManualTriage, .openNewAgent:
            return false
        case .autoAssignUnassignedTodo, .createMissingDependencyTasks, .rebalanceTodoLoad, .increaseWIPLimit, .archiveDone:
            return true
        }
    }
}

enum BoardMessageSeverity: String, Equatable {
    case info
    case warning
    case error
}

enum WorkspaceImportStrategy: Equatable {
    case replace
    case merge
}

struct WorkspaceImportPreview: Equatable {
    let boardCount: Int
    let taskCount: Int
    let agentCount: Int
}

enum CodexProjectsDirectorySettings {
    static let userDefaultsKey = "codexProjectsDirectoryPath"
    static let environmentOverrideKey = "OPENMAC_PROJECTS_DIR"
    private static let defaultRelativePath = "Library/Application Support/OpenMac/Projects"

    static func defaultProjectsDirectoryURL(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        homeDirectory.appendingPathComponent(defaultRelativePath, isDirectory: true)
    }

    static func resolvedProjectsDirectoryPath(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        userDefaults: UserDefaults = .standard
    ) -> String {
        if let override = environment[environmentOverrideKey]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !override.isEmpty {
            return (override as NSString).expandingTildeInPath
        }

        if let stored = userDefaults.string(forKey: userDefaultsKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !stored.isEmpty {
            return (stored as NSString).expandingTildeInPath
        }

        return defaultProjectsDirectoryURL().path
    }

    @discardableResult
    static func ensureProjectsDirectoryExists(
        at path: String,
        fileManager: FileManager = .default
    ) throws -> URL {
        let expandedPath = (path as NSString).expandingTildeInPath
        let url = URL(fileURLWithPath: expandedPath, isDirectory: true)
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func boardScopedProjectsDirectoryPath(
        baseDirectoryPath: String,
        boardName: String
    ) -> String {
        let expandedBasePath = (baseDirectoryPath as NSString).expandingTildeInPath
        let baseURL = URL(fileURLWithPath: expandedBasePath, isDirectory: true)
        let folderName = normalizedBoardDirectoryName(boardName)
        return baseURL.appendingPathComponent(folderName, isDirectory: true).path
    }

    private static func normalizedBoardDirectoryName(_ boardName: String) -> String {
        let trimmed = boardName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "board" }

        let allowedCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        var scalars: [UnicodeScalar] = []
        var previousWasSeparator = false

        for scalar in trimmed.unicodeScalars {
            if allowedCharacters.contains(scalar) {
                scalars.append(scalar)
                previousWasSeparator = false
            } else if !previousWasSeparator {
                scalars.append("-")
                previousWasSeparator = true
            }
        }

        let collapsed = String(String.UnicodeScalarView(scalars))
            .trimmingCharacters(in: CharacterSet(charactersIn: "-_"))
        return collapsed.isEmpty ? "board" : collapsed
    }
}

enum WorktreeExecutionSettings {
    static let enabledUserDefaultsKey = "worktreeExecutionEnabled"
    static let repositoryPathUserDefaultsKey = "worktreeRepositoryPath"
    static let branchPrefixUserDefaultsKey = "worktreeBranchPrefix"
    private static let fallbackRepositoryPathUserDefaultsKey = "githubRepositoryPath"
    private static let fallbackBranchPrefixUserDefaultsKey = "githubBranchPrefix"

    static func isEnabled(userDefaults: UserDefaults = .standard) -> Bool {
        userDefaults.bool(forKey: enabledUserDefaultsKey)
    }

    static func resolvedRepositoryPath(userDefaults: UserDefaults = .standard) -> String {
        let explicitPath = userDefaults.string(forKey: repositoryPathUserDefaultsKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !explicitPath.isEmpty {
            return (explicitPath as NSString).expandingTildeInPath
        }
        let fallbackPath = userDefaults.string(forKey: fallbackRepositoryPathUserDefaultsKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return (fallbackPath as NSString).expandingTildeInPath
    }

    static func resolvedBranchPrefix(userDefaults: UserDefaults = .standard) -> String {
        let explicitPrefix = userDefaults.string(forKey: branchPrefixUserDefaultsKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !explicitPrefix.isEmpty {
            return normalizedBranchPrefix(explicitPrefix)
        }
        let fallbackPrefix = userDefaults.string(forKey: fallbackBranchPrefixUserDefaultsKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return normalizedBranchPrefix(fallbackPrefix)
    }

    static func normalizedBranchPrefix(_ rawValue: String) -> String {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "openmac" }
        let normalized = trimmed
            .split(separator: "/")
            .compactMap { rawSegment -> String? in
                let segment = rawSegment.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !segment.isEmpty else { return nil }
                let words = segment.split(whereSeparator: { $0.isWhitespace })
                let joined = words.joined(separator: "-").lowercased()
                let cleaned = joined.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
                return cleaned.isEmpty ? nil : cleaned
            }
            .joined(separator: "/")
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return normalized.isEmpty ? "openmac" : normalized
    }
}

struct BoardHealthRecommendation: Identifiable, Equatable {
    let action: BoardHealthAction
    let title: String
    let detail: String

    var id: String {
        switch action {
        case .autoAssignUnassignedTodo:
            return "auto-assign-unassigned-todo"
        case .createMissingDependencyTasks:
            return "create-missing-dependency-tasks"
        case .openManualTriage:
            return "open-manual-triage"
        case .openNewAgent:
            return "open-new-agent"
        case .rebalanceTodoLoad:
            return "rebalance-todo-load"
        case let .increaseWIPLimit(status):
            return "increase-wip-\(status.rawValue)"
        case .archiveDone:
            return "archive-done"
        }
    }
}

struct GlobalTaskSearchResult: Identifiable, Equatable {
    let taskID: UUID
    let taskTitle: String
    let taskDetails: String
    let status: KanbanStatus
    let boardID: UUID
    let boardName: String
    let assigneeName: String

    var id: String {
        "\(boardID.uuidString)-\(taskID.uuidString)"
    }
}
