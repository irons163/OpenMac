import Foundation

struct PMPlannedTicket: Equatable {
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

struct PMProjectPlan: Equatable {
    var projectName: String
    var summary: String
    var tickets: [PMPlannedTicket]
}

protocol ProjectPlanning {
    func generatePlan(
        projectName: String,
        projectBrief: String,
        availableAgents: [AgentProfile]
    ) -> PMProjectPlan?
}

struct RuleBasedProjectPlanner: ProjectPlanning {
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
}
