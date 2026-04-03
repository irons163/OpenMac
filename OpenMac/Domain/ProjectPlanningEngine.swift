import Foundation

struct PMPlannedTicket: Equatable, Codable {
    var title: String
    var details: String
    var requiredSkills: [String]
    var storyPoints: Int
    var epic: String
    var milestone: String

    nonisolated init(
        title: String,
        details: String,
        requiredSkills: [String],
        storyPoints: Int,
        epic: String = "",
        milestone: String = ""
    ) {
        self.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        self.details = details.trimmingCharacters(in: .whitespacesAndNewlines)
        self.requiredSkills = Array(
            Set(
                requiredSkills
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                    .filter { !$0.isEmpty }
            )
        ).sorted()
        self.storyPoints = max(1, min(13, storyPoints))
        self.epic = epic.trimmingCharacters(in: .whitespacesAndNewlines)
        self.milestone = milestone.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct PMProjectPlan: Equatable, Codable {
    var projectName: String
    var summary: String
    var tickets: [PMPlannedTicket]
}

struct PMBlueprintDependencyEdge: Equatable, Codable {
    var fromTicketTitle: String
    var toTicketTitle: String
}

struct PMQualitySafetyGate: Equatable, Codable {
    var name: String
    var focus: String
    var checklist: [String]
}

struct PMProjectBlueprint: Equatable, Codable {
    var projectName: String
    var summary: String
    var productRequirements: [String]
    var architectureModules: [String]
    var epics: [String]
    var milestones: [String]
    var dependencyEdges: [PMBlueprintDependencyEdge]
    var qualitySafetyGates: [PMQualitySafetyGate]
    var tickets: [PMPlannedTicket]
}

protocol ProjectPlanning {
    func generatePlan(
        projectName: String,
        projectBrief: String,
        availableAgents: [AgentProfile]
    ) -> PMProjectPlan?
}

protocol ProjectBlueprintPlanning {
    func generateBlueprint(
        projectName: String,
        projectBrief: String,
        availableAgents: [AgentProfile]
    ) -> PMProjectBlueprint?
}

struct RuleBasedProjectPlanner: ProjectPlanning, ProjectBlueprintPlanning {
    private static let domainSkillMap: [(keywords: [String], skills: [String])] = [
        (["swiftui", "ui", "ux", "frontend", "view"], ["swiftui", "ui", "ux"]),
        (["backend", "api", "server", "database", "db"], ["backend", "api", "database"]),
        (["ai", "agent", "llm", "prompt", "automation"], ["ai", "agent", "automation"]),
        (["test", "qa", "tdd", "coverage"], ["testing", "tdd", "qa"]),
        (["deploy", "release", "ops", "monitor"], ["devops", "release", "monitoring"]),
        (["doc", "handoff", "guide", "spec"], ["documentation", "planning"])
    ]

    func generatePlan(
        projectName: String,
        projectBrief: String,
        availableAgents: [AgentProfile]
    ) -> PMProjectPlan? {
        let normalizedBrief = projectBrief.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedBrief.isEmpty else { return nil }

        let resolvedProjectName = resolvedName(explicitName: projectName, from: normalizedBrief)
        let summarySnippet = summarizedBrief(normalizedBrief)
        let complexity = complexityScore(for: normalizedBrief)
        let suggestedCoreSkills = inferredCoreSkills(from: normalizedBrief)
        let availableSkills = Set(availableAgents.flatMap(\.skills))
        let scopedSkills = normalizedSkills(
            suggested: suggestedCoreSkills,
            availableSkills: availableSkills
        )

        var tickets: [PMPlannedTicket] = [
            PMPlannedTicket(
                title: "\(resolvedProjectName) · Scope & Success Criteria",
                details: """
                Clarify project scope and acceptance outcomes for "\(resolvedProjectName)".
                Source brief: \(summarySnippet)
                Acceptance:
                Depends on: none
                - Define in-scope/out-of-scope boundaries.
                - List measurable success criteria.
                - Confirm milestone sequence for execution tracking.
                """,
                requiredSkills: scopedSkills + ["planning"],
                storyPoints: 2 + (complexity / 2),
                epic: "Planning",
                milestone: "M1 Scope Locked"
            ),
            PMPlannedTicket(
                title: "\(resolvedProjectName) · Architecture & Delivery Plan",
                details: """
                Create an implementation blueprint for "\(resolvedProjectName)".
                Source brief: \(summarySnippet)
                Acceptance:
                Depends on: \(resolvedProjectName) · Scope & Success Criteria
                - Document core modules and integration points.
                - Identify dependencies, risks, and fallback paths.
                - Define execution order and ownership boundaries.
                """,
                requiredSkills: scopedSkills + ["architecture"],
                storyPoints: 3 + (complexity / 2),
                epic: "Planning",
                milestone: "M1 Scope Locked"
            ),
            PMPlannedTicket(
                title: "\(resolvedProjectName) · Core Implementation",
                details: """
                Build the primary product capabilities described in the project brief.
                Source brief: \(summarySnippet)
                Acceptance:
                Depends on: \(resolvedProjectName) · Architecture & Delivery Plan
                - Implement end-to-end core user workflow.
                - Handle expected edge cases and state transitions.
                - Keep changes reviewable in incremental checkpoints.
                """,
                requiredSkills: scopedSkills,
                storyPoints: 5 + complexity,
                epic: "Core Product",
                milestone: "M2 MVP Complete"
            ),
            PMPlannedTicket(
                title: "\(resolvedProjectName) · Integration & Quality Gate",
                details: """
                Stabilize behavior and verify expected outcomes.
                Source brief: \(summarySnippet)
                Acceptance:
                Depends on: \(resolvedProjectName) · Core Implementation
                - Add/extend automated tests for critical paths.
                - Validate integration contracts and data flow.
                - Record unresolved issues and mitigation plan.
                """,
                requiredSkills: scopedSkills + ["testing", "tdd"],
                storyPoints: 3 + (complexity / 2),
                epic: "Quality",
                milestone: "M3 Quality Gate"
            ),
            PMPlannedTicket(
                title: "\(resolvedProjectName) · Release, Docs, and Handoff",
                details: """
                Prepare final release readiness and team handoff.
                Source brief: \(summarySnippet)
                Acceptance:
                Depends on: \(resolvedProjectName) · Integration & Quality Gate
                - Document setup, operations, and known limits.
                - Define rollout/checklist and rollback notes.
                - Provide concise next-step recommendations.
                """,
                requiredSkills: ["documentation", "release"] + scopedSkills,
                storyPoints: 2 + (complexity / 2),
                epic: "Release",
                milestone: "M4 Release Ready"
            )
        ]

        if complexity >= 4 {
            tickets.append(
                PMPlannedTicket(
                    title: "\(resolvedProjectName) · Risk Spike & Mitigation",
                    details: """
                    Run a focused spike on highest-uncertainty areas before full rollout.
                    Source brief: \(summarySnippet)
                    Acceptance:
                    Depends on: \(resolvedProjectName) · Architecture & Delivery Plan
                    - Identify top technical and schedule risks.
                    - Produce mitigation tasks with owners and trigger conditions.
                    - Update plan assumptions based on spike results.
                    """,
                    requiredSkills: scopedSkills + ["planning"],
                    storyPoints: 2,
                    epic: "Risk",
                    milestone: "M1 Scope Locked"
                )
            )
        }

        let summary = """
        PM plan generated for "\(resolvedProjectName)" with \(tickets.count) ticket(s), complexity level \(complexity).
        Focus: scope, architecture, implementation, quality, and release.
        """

        return PMProjectPlan(
            projectName: resolvedProjectName,
            summary: summary,
            tickets: tickets
        )
    }

    func generateBlueprint(
        projectName: String,
        projectBrief: String,
        availableAgents: [AgentProfile]
    ) -> PMProjectBlueprint? {
        guard let plan = generatePlan(
            projectName: projectName,
            projectBrief: projectBrief,
            availableAgents: availableAgents
        ) else {
            return nil
        }

        let compactBrief = projectBrief
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: " ")

        let productRequirements = inferredRequirements(from: compactBrief)
        let architectureModules = inferredArchitectureModules(from: plan.tickets)
        let dependencyEdges = inferredDependencyEdges(from: plan.tickets)
        let epics = uniqueNonEmptyValues(from: plan.tickets.map(\.epic))
        let milestones = uniqueNonEmptyValues(from: plan.tickets.map(\.milestone))

        let qualitySafetyGates = [
            PMQualitySafetyGate(
                name: "Definition of Ready",
                focus: "Execution quality baseline",
                checklist: [
                    "Every ticket contains acceptance criteria.",
                    "Dependencies are explicit via 'Depends on:'.",
                    "Story points and skills are set."
                ]
            ),
            PMQualitySafetyGate(
                name: "Coverage and Regression",
                focus: "Test confidence",
                checklist: [
                    "Critical user path includes automated tests.",
                    "Regression tests cover failure paths.",
                    "E2E acceptance verification tasks are present."
                ]
            ),
            PMQualitySafetyGate(
                name: "Security and Privacy",
                focus: "Risk controls for sensitive flows",
                checklist: [
                    "Sensitive scope has security notes.",
                    "Privacy/PII handling is documented.",
                    "No secret/token material appears in task details."
                ]
            ),
            PMQualitySafetyGate(
                name: "Release Readiness",
                focus: "Operational handoff",
                checklist: [
                    "Rollback and monitoring notes are included.",
                    "Known risks and mitigations are tracked.",
                    "Handoff docs are attached."
                ]
            )
        ]

        return PMProjectBlueprint(
            projectName: plan.projectName,
            summary: plan.summary,
            productRequirements: productRequirements,
            architectureModules: architectureModules,
            epics: epics,
            milestones: milestones,
            dependencyEdges: dependencyEdges,
            qualitySafetyGates: qualitySafetyGates,
            tickets: plan.tickets
        )
    }

    private func resolvedName(explicitName: String, from brief: String) -> String {
        let trimmed = explicitName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            return trimmed
        }

        let tokens = brief
            .split(whereSeparator: { $0.isWhitespace || $0.isNewline })
            .prefix(5)
            .map(String.init)
        let fallback = tokens.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        return fallback.isEmpty ? "New Project" : fallback
    }

    private func summarizedBrief(_ brief: String) -> String {
        let compact = brief.replacingOccurrences(of: "\n", with: " ")
        if compact.count <= 180 {
            return compact
        }
        let index = compact.index(compact.startIndex, offsetBy: 180)
        return String(compact[..<index]) + "..."
    }

    private func complexityScore(for brief: String) -> Int {
        let normalized = brief.lowercased()
        let wordCount = brief
            .split(whereSeparator: { $0.isWhitespace || $0.isNewline })
            .count

        var score = 1
        if wordCount > 25 { score += 1 }

        let riskSignals = [
            "auth", "oauth", "security", "permission", "payment", "billing",
            "realtime", "real-time", "sync", "socket", "migration",
            "multi-tenant", "compliance", "offline", "encryption",
            "權限", "安全", "金流", "同步", "多租戶", "離線"
        ]
        for signal in riskSignals where normalized.contains(signal) {
            score += 1
        }

        let scaleSignals = ["ai", "agent", "workflow", "automation", "integration", "api", "平台", "自動化"]
        for signal in scaleSignals where normalized.contains(signal) {
            score += 1
        }

        return min(5, max(1, score))
    }

    private func inferredCoreSkills(from brief: String) -> [String] {
        let normalized = brief.lowercased()
        var skills = Set<String>()

        for entry in Self.domainSkillMap where entry.keywords.contains(where: { normalized.contains($0) }) {
            entry.skills.forEach { skills.insert($0) }
        }

        if skills.isEmpty {
            return ["planning"]
        }
        return Array(skills).sorted()
    }

    private func normalizedSkills(suggested: [String], availableSkills: Set<String>) -> [String] {
        let normalizedSuggested = Array(
            Set(
                suggested
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                    .filter { !$0.isEmpty }
            )
        ).sorted()

        guard !availableSkills.isEmpty else {
            return normalizedSuggested
        }

        let filtered = normalizedSuggested.filter { availableSkills.contains($0) }
        return filtered.isEmpty ? [] : filtered
    }

    private func inferredRequirements(from compactBrief: String) -> [String] {
        let sentences = compactBrief
            .split(whereSeparator: { $0 == "." || $0 == ";" || $0 == "。" || $0 == "；" })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if !sentences.isEmpty {
            return Array(sentences.prefix(6))
        }
        if compactBrief.isEmpty {
            return []
        }
        return [compactBrief]
    }

    private func inferredArchitectureModules(from tickets: [PMPlannedTicket]) -> [String] {
        var modules = Set<String>()
        for ticket in tickets {
            for skill in ticket.requiredSkills {
                switch skill {
                case "swiftui", "ui", "ux":
                    modules.insert("Client Experience Layer")
                case "backend", "api", "database":
                    modules.insert("Service and Data Layer")
                case "testing", "tdd", "qa":
                    modules.insert("Automated Validation Layer")
                case "documentation", "planning", "release":
                    modules.insert("Delivery and Operations Layer")
                default:
                    modules.insert("\(skill.uppercased()) Capability Layer")
                }
            }
        }

        if modules.isEmpty {
            modules.insert("Core Product Layer")
        }
        return modules.sorted()
    }

    private func inferredDependencyEdges(from tickets: [PMPlannedTicket]) -> [PMBlueprintDependencyEdge] {
        let ticketTitles = Set(tickets.map { normalizedDependencyTitle($0.title) }.filter { !$0.isEmpty })
        var edges: [PMBlueprintDependencyEdge] = []
        var seen = Set<String>()

        for ticket in tickets {
            let fromTitle = ticket.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !fromTitle.isEmpty else { continue }
            let dependencies = parsedDependencyTitles(from: ticket.details)
            for dependency in dependencies {
                let normalized = normalizedDependencyTitle(dependency)
                guard ticketTitles.contains(normalized) else { continue }
                let dedupeKey = "\(normalized.lowercased())->\(fromTitle.lowercased())"
                guard seen.insert(dedupeKey).inserted else { continue }
                edges.append(
                    PMBlueprintDependencyEdge(
                        fromTicketTitle: dependency,
                        toTicketTitle: fromTitle
                    )
                )
            }
        }
        return edges
    }

    private func parsedDependencyTitles(from details: String) -> [String] {
        let lines = details.split(whereSeparator: \.isNewline).map(String.init)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            let lowercased = trimmed.lowercased()
            guard lowercased.hasPrefix("depends on:") else { continue }
            let suffix = trimmed.dropFirst("depends on:".count)
            return suffix
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty && $0.lowercased() != "none" }
        }
        return []
    }

    private func normalizedDependencyTitle(_ rawTitle: String) -> String {
        rawTitle
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    private func uniqueNonEmptyValues(from values: [String]) -> [String] {
        var seen = Set<String>()
        var unique: [String] = []
        for value in values {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let key = trimmed.lowercased()
            guard seen.insert(key).inserted else { continue }
            unique.append(trimmed)
        }
        return unique
    }
}

protocol ConfigurableProjectPlanning {
    func generatePlan(
        projectName: String,
        projectBrief: String,
        availableAgents: [AgentProfile],
        mode: PMPlannerEngineMode,
        pluginPolicy: PMPlanningPluginPolicy
    ) -> PMProjectPlan?

    func generateBlueprint(
        projectName: String,
        projectBrief: String,
        availableAgents: [AgentProfile],
        mode: PMPlannerEngineMode,
        pluginPolicy: PMPlanningPluginPolicy
    ) -> PMProjectBlueprint?
}

struct ExtensibleProjectPlanner: ProjectPlanning, ProjectBlueprintPlanning, ConfigurableProjectPlanning {
    typealias PluginCommandRunner = (
        _ command: String,
        _ workingDirectoryPath: String,
        _ stdin: String,
        _ timeoutSeconds: TimeInterval
    ) throws -> (code: Int32, stdout: String, stderr: String)

    private let fallbackPlanner: any ProjectPlanning & ProjectBlueprintPlanning
    private let pluginCommandRunner: PluginCommandRunner
    private let commandTimeoutSeconds: TimeInterval
    private let fileManager: FileManager

    init(
        fallbackPlanner: any ProjectPlanning & ProjectBlueprintPlanning = RuleBasedProjectPlanner(),
        pluginCommandRunner: @escaping PluginCommandRunner = Self.defaultPluginCommandRunner,
        commandTimeoutSeconds: TimeInterval = 45,
        fileManager: FileManager = .default
    ) {
        self.fallbackPlanner = fallbackPlanner
        self.pluginCommandRunner = pluginCommandRunner
        self.commandTimeoutSeconds = max(5, commandTimeoutSeconds)
        self.fileManager = fileManager
    }

    func generatePlan(
        projectName: String,
        projectBrief: String,
        availableAgents: [AgentProfile]
    ) -> PMProjectPlan? {
        fallbackPlanner.generatePlan(
            projectName: projectName,
            projectBrief: projectBrief,
            availableAgents: availableAgents
        )
    }

    func generateBlueprint(
        projectName: String,
        projectBrief: String,
        availableAgents: [AgentProfile]
    ) -> PMProjectBlueprint? {
        fallbackPlanner.generateBlueprint(
            projectName: projectName,
            projectBrief: projectBrief,
            availableAgents: availableAgents
        )
    }

    func generatePlan(
        projectName: String,
        projectBrief: String,
        availableAgents: [AgentProfile],
        mode: PMPlannerEngineMode,
        pluginPolicy: PMPlanningPluginPolicy
    ) -> PMProjectPlan? {
        switch mode {
        case .builtIn:
            return fallbackPlanner.generatePlan(
                projectName: projectName,
                projectBrief: projectBrief,
                availableAgents: availableAgents
            )
        case .brainstormPluginPreferred:
            if let pluginPlan = runLocalBrainstormPlugin(
                projectName: projectName,
                projectBrief: projectBrief,
                availableAgents: availableAgents,
                pluginPolicy: pluginPolicy
            ) {
                return pluginPlan
            }

            guard let basePlan = fallbackPlanner.generatePlan(
                projectName: projectName,
                projectBrief: projectBrief,
                availableAgents: availableAgents
            ) else {
                return nil
            }
            return builtInBrainstormPlan(
                basePlan: basePlan,
                projectBrief: projectBrief
            )
        }
    }

    func generateBlueprint(
        projectName: String,
        projectBrief: String,
        availableAgents: [AgentProfile],
        mode: PMPlannerEngineMode,
        pluginPolicy: PMPlanningPluginPolicy
    ) -> PMProjectBlueprint? {
        guard var blueprint = fallbackPlanner.generateBlueprint(
            projectName: projectName,
            projectBrief: projectBrief,
            availableAgents: availableAgents
        ) else {
            return nil
        }

        guard mode == .brainstormPluginPreferred,
              let pluginPlan = generatePlan(
                  projectName: projectName,
                  projectBrief: projectBrief,
                  availableAgents: availableAgents,
                  mode: mode,
                  pluginPolicy: pluginPolicy
              ) else {
            return blueprint
        }

        blueprint.projectName = pluginPlan.projectName
        blueprint.summary = pluginPlan.summary
        blueprint.tickets = pluginPlan.tickets
        blueprint.epics = uniqueNonEmptyValues(pluginPlan.tickets.map(\.epic))
        blueprint.milestones = uniqueNonEmptyValues(pluginPlan.tickets.map(\.milestone))
        blueprint.dependencyEdges = inferredDependencyEdges(from: pluginPlan.tickets)
        return blueprint
    }

    private func runLocalBrainstormPlugin(
        projectName: String,
        projectBrief: String,
        availableAgents: [AgentProfile],
        pluginPolicy: PMPlanningPluginPolicy
    ) -> PMProjectPlan? {
        guard pluginPolicy.autoDiscoverLocalPlugins else {
            return nil
        }

        let pluginsDirectoryPath = pluginPolicy.pluginsDirectoryPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !pluginsDirectoryPath.isEmpty else {
            return nil
        }
        let pluginsDirectoryURL = URL(fileURLWithPath: pluginsDirectoryPath, isDirectory: true)
        guard let pluginEntries = try? discoverPluginEntries(in: pluginsDirectoryURL), !pluginEntries.isEmpty else {
            return nil
        }

        let request = LocalPMPlanningPluginRequest(
            projectName: projectName,
            projectBrief: projectBrief,
            availableAgents: availableAgents.map { agent in
                LocalPMPlanningAgentDescriptor(
                    name: agent.name,
                    skills: Array(agent.skills).sorted(),
                    maxConcurrentTasks: agent.maxConcurrentTasks
                )
            }
        )
        guard let requestData = try? JSONEncoder().encode(request),
              let requestJSON = String(data: requestData, encoding: .utf8) else {
            return nil
        }

        for plugin in pluginEntries {
            do {
                let result = try pluginCommandRunner(
                    plugin.entrypoint,
                    plugin.directoryURL.path,
                    requestJSON,
                    commandTimeoutSeconds
                )
                guard result.code == 0 else { continue }
                let output = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !output.isEmpty else { continue }
                guard let response = decodedPluginResponse(from: output) else { continue }
                guard let normalized = normalizedPlan(
                    from: response,
                    fallbackProjectName: projectName
                ) else {
                    continue
                }
                return PMProjectPlan(
                    projectName: normalized.projectName,
                    summary: normalized.summary + "\nPlanning engine: \(plugin.name)",
                    tickets: normalized.tickets
                )
            } catch {
                continue
            }
        }

        return nil
    }

    private func discoverPluginEntries(in directoryURL: URL) throws -> [LocalPMPlanningPluginEntry] {
        guard fileManager.fileExists(atPath: directoryURL.path) else {
            return []
        }

        let childEntries = try fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        let candidateDirectories = [directoryURL] + childEntries
        var discovered: [LocalPMPlanningPluginEntry] = []

        for entryURL in candidateDirectories {
            let resourceValues = try entryURL.resourceValues(forKeys: [.isDirectoryKey])
            guard resourceValues.isDirectory == true else { continue }

            let pluginManifestCandidates = [
                entryURL.appendingPathComponent("plugin.json"),
                entryURL.appendingPathComponent("manifest.json")
            ]

            let manifestURL = pluginManifestCandidates.first { fileManager.fileExists(atPath: $0.path) }
            guard let manifestURL else { continue }
            guard let data = try? Data(contentsOf: manifestURL),
                  let manifest = try? JSONDecoder().decode(LocalPMPlanningPluginManifest.self, from: data) else {
                continue
            }

            let isEnabled = manifest.enabled ?? true
            guard isEnabled else { continue }
            let capabilities = Set(manifest.capabilities ?? [])
            guard capabilities.contains(LocalPMPlanningPluginManifest.planCapability) else { continue }

            let rawEntrypoint = manifest.entrypoint?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !rawEntrypoint.isEmpty else { continue }
            let resolvedEntrypoint: String
            if rawEntrypoint.hasPrefix("/") || rawEntrypoint.hasPrefix("~") {
                resolvedEntrypoint = Self.shellQuoted((rawEntrypoint as NSString).expandingTildeInPath)
            } else {
                resolvedEntrypoint = Self.shellQuoted(entryURL.appendingPathComponent(rawEntrypoint).path)
            }

            let entry = LocalPMPlanningPluginEntry(
                id: manifest.id.trimmingCharacters(in: .whitespacesAndNewlines),
                name: manifest.name.trimmingCharacters(in: .whitespacesAndNewlines),
                entrypoint: resolvedEntrypoint,
                directoryURL: entryURL
            )
            guard !entry.id.isEmpty, !entry.name.isEmpty else { continue }
            discovered.append(entry)
        }

        return discovered.sorted { lhs, rhs in
            lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    private func decodedPluginResponse(from rawOutput: String) -> LocalPMPlanningPluginResponse? {
        if let data = rawOutput.data(using: .utf8),
           let direct = try? JSONDecoder().decode(LocalPMPlanningPluginResponse.self, from: data) {
            return direct
        }

        guard let start = rawOutput.firstIndex(of: "{"),
              let end = rawOutput.lastIndex(of: "}"),
              start <= end else {
            return nil
        }
        let slice = String(rawOutput[start ... end])
        guard let data = slice.data(using: .utf8) else {
            return nil
        }
        return try? JSONDecoder().decode(LocalPMPlanningPluginResponse.self, from: data)
    }

    private func normalizedPlan(
        from response: LocalPMPlanningPluginResponse,
        fallbackProjectName: String
    ) -> PMProjectPlan? {
        let normalizedTickets = (response.tickets ?? [])
            .map { ticket in
                PMPlannedTicket(
                    title: ticket.title,
                    details: ticket.details,
                    requiredSkills: ticket.requiredSkills ?? [],
                    storyPoints: ticket.storyPoints ?? 1,
                    epic: ticket.epic ?? "",
                    milestone: ticket.milestone ?? ""
                )
            }
            .filter { !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

        guard !normalizedTickets.isEmpty else { return nil }
        let resolvedProjectName = {
            let fromResponse = response.projectName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !fromResponse.isEmpty {
                return fromResponse
            }
            let fallback = fallbackProjectName.trimmingCharacters(in: .whitespacesAndNewlines)
            return fallback.isEmpty ? "PM Project" : fallback
        }()
        let resolvedSummary = {
            let fromResponse = response.summary?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return fromResponse.isEmpty
                ? "Plugin-generated PM plan with \(normalizedTickets.count) ticket(s)."
                : fromResponse
        }()

        return PMProjectPlan(
            projectName: resolvedProjectName,
            summary: resolvedSummary,
            tickets: normalizedTickets
        )
    }

    private func builtInBrainstormPlan(basePlan: PMProjectPlan, projectBrief: String) -> PMProjectPlan {
        let trimmedProjectName = basePlan.projectName.trimmingCharacters(in: .whitespacesAndNewlines)
        let projectName = trimmedProjectName.isEmpty ? "PM Project" : trimmedProjectName
        let brainstormTitle = "\(projectName) · Brainstorm & Option Scan"

        var tickets = basePlan.tickets
        if !tickets.contains(where: { $0.title.localizedCaseInsensitiveContains("brainstorm") }) {
            let ideas = brainstormIdeaLines(from: projectBrief)
            let details = """
            Generate concrete solution options before implementation starts.
            Source brief: \(projectBrief.trimmingCharacters(in: .whitespacesAndNewlines))
            Acceptance:
            Depends on: none
            - Produce at least 3 feasible solution options.
            - Document trade-offs (cost, complexity, delivery risk).
            - Recommend one primary path plus fallback.
            \(ideas.joined(separator: "\n"))
            """
            let brainstormTicket = PMPlannedTicket(
                title: brainstormTitle,
                details: details,
                requiredSkills: ["planning", "research"],
                storyPoints: 2,
                epic: "Planning",
                milestone: "M0 Ideation"
            )
            tickets.insert(brainstormTicket, at: 0)

            if tickets.indices.contains(1) {
                tickets[1] = PMPlannedTicket(
                    title: tickets[1].title,
                    details: replacingDependsOnNone(
                        in: tickets[1].details,
                        with: brainstormTitle
                    ),
                    requiredSkills: tickets[1].requiredSkills,
                    storyPoints: tickets[1].storyPoints,
                    epic: tickets[1].epic,
                    milestone: tickets[1].milestone
                )
            }
        }

        return PMProjectPlan(
            projectName: basePlan.projectName,
            summary: basePlan.summary + "\nPlanning engine: Built-in Brainstorm plugin",
            tickets: tickets
        )
    }

    private func brainstormIdeaLines(from brief: String) -> [String] {
        let compact = brief
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: " ")
        guard !compact.isEmpty else {
            return []
        }

        let fragments = compact
            .split(whereSeparator: { $0 == "." || $0 == "。" || $0 == ";" || $0 == "；" })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        return fragments
            .prefix(3)
            .enumerated()
            .map { index, fragment in
                "- Idea \(index + 1): \(fragment)"
            }
    }

    private func replacingDependsOnNone(in details: String, with dependencyTitle: String) -> String {
        let lines = details.split(whereSeparator: \.isNewline).map(String.init)
        var updated: [String] = []
        var replaced = false
        for line in lines {
            if !replaced, line.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "depends on: none" {
                updated.append("Depends on: \(dependencyTitle)")
                replaced = true
            } else {
                updated.append(line)
            }
        }
        if replaced {
            return updated.joined(separator: "\n")
        }
        return details
    }

    private func uniqueNonEmptyValues(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var output: [String] = []
        for value in values {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let key = trimmed.lowercased()
            guard seen.insert(key).inserted else { continue }
            output.append(trimmed)
        }
        return output
    }

    private func inferredDependencyEdges(from tickets: [PMPlannedTicket]) -> [PMBlueprintDependencyEdge] {
        let knownTitles = Set(
            tickets
                .map(\.title)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                .filter { !$0.isEmpty }
        )

        var edges: [PMBlueprintDependencyEdge] = []
        var seen = Set<String>()
        for ticket in tickets {
            let toTitle = ticket.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !toTitle.isEmpty else { continue }
            for dependency in parsedDependencyTitles(from: ticket.details) {
                let normalized = dependency.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                guard knownTitles.contains(normalized) else { continue }
                let key = "\(normalized)->\(toTitle.lowercased())"
                guard seen.insert(key).inserted else { continue }
                edges.append(PMBlueprintDependencyEdge(fromTicketTitle: dependency, toTicketTitle: toTitle))
            }
        }
        return edges
    }

    private func parsedDependencyTitles(from details: String) -> [String] {
        let lines = details.split(whereSeparator: \.isNewline).map(String.init)
        guard let dependencyLine = lines.first(where: {
            $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().hasPrefix("depends on:")
        }) else {
            return []
        }
        let suffix = dependencyLine.dropFirst("depends on:".count)
        return suffix
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0.lowercased() != "none" }
    }

    nonisolated private static func defaultPluginCommandRunner(
        command: String,
        workingDirectoryPath: String,
        stdin: String,
        timeoutSeconds: TimeInterval
    ) throws -> (code: Int32, stdout: String, stderr: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", command]
        process.currentDirectoryURL = URL(fileURLWithPath: workingDirectoryPath, isDirectory: true)

        let inputPipe = Pipe()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        try process.run()
        if let data = stdin.data(using: .utf8) {
            inputPipe.fileHandleForWriting.write(data)
        }
        inputPipe.fileHandleForWriting.closeFile()

        let timeout = DispatchTime.now() + timeoutSeconds
        if process.isRunning {
            let waitGroup = DispatchGroup()
            waitGroup.enter()
            DispatchQueue.global(qos: .utility).async {
                process.waitUntilExit()
                waitGroup.leave()
            }
            if waitGroup.wait(timeout: timeout) == .timedOut {
                process.terminate()
                throw PluginCommandError.timeout
            }
        }

        let stdoutData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = errorPipe.fileHandleForReading.readDataToEndOfFile()
        let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
        let stderr = String(data: stderrData, encoding: .utf8) ?? ""
        return (process.terminationStatus, stdout, stderr)
    }

    private struct LocalPMPlanningPluginEntry {
        var id: String
        var name: String
        var entrypoint: String
        var directoryURL: URL
    }

    private struct LocalPMPlanningPluginManifest: Decodable {
        static let planCapability = "pm.plan.generate"

        var id: String
        var name: String
        var capabilities: [String]?
        var entrypoint: String?
        var enabled: Bool?
    }

    private struct LocalPMPlanningPluginRequest: Encodable {
        var projectName: String
        var projectBrief: String
        var availableAgents: [LocalPMPlanningAgentDescriptor]
    }

    private struct LocalPMPlanningAgentDescriptor: Encodable {
        var name: String
        var skills: [String]
        var maxConcurrentTasks: Int
    }

    private struct LocalPMPlanningPluginResponse: Decodable {
        var projectName: String?
        var summary: String?
        var tickets: [LocalPMPlanningPluginTicket]?
    }

    private struct LocalPMPlanningPluginTicket: Decodable {
        var title: String
        var details: String
        var requiredSkills: [String]?
        var storyPoints: Int?
        var epic: String?
        var milestone: String?
    }

    private enum PluginCommandError: LocalizedError {
        case timeout

        var errorDescription: String? {
            switch self {
            case .timeout:
                return "Plugin command timed out"
            }
        }
    }

    nonisolated private static func shellQuoted(_ value: String) -> String {
        let escaped = value.replacingOccurrences(of: "'", with: "'\\''")
        return "'\(escaped)'"
    }
}
