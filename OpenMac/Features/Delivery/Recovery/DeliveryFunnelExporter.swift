import Foundation

nonisolated struct DeliveryFunnelReport: Equatable, Codable, Sendable {
    nonisolated static let formatIdentifier = "com.openmac.delivery-funnel"
    nonisolated static let currentSchemaVersion = 1

    let format: String
    let schemaVersion: Int
    let exportedAt: Date
    let currentState: DerivedDeliveryState
    let taskCount: Int
    let approved: Bool
    let startedSessionCount: Int
    let succeededTaskCount: Int
    let verifiedTaskCount: Int
    let attemptCount: Int
    let retryAttemptCount: Int
    let passedEvidenceCount: Int
    let failedEvidenceCount: Int
    let pullRequestCount: Int
    let readyPullRequestCount: Int
    let needsAttentionCount: Int
    let briefToApprovalSeconds: TimeInterval?
    let briefToFirstSessionSeconds: TimeInterval?
    let briefToThreeSessionsSeconds: TimeInterval?
    let excludedSensitiveFields: [String]
}

nonisolated enum DeliveryFunnelExportError:
    Error,
    Equatable,
    LocalizedError,
    Sendable
{
    case invalidDestination

    nonisolated var errorDescription: String? {
        switch self {
        case .invalidDestination:
            return "The funnel export destination must be a local JSON file."
        }
    }
}

nonisolated struct DeliveryFunnelExporter: Sendable {
    nonisolated init() {}

    nonisolated func report(
        for run: DeliveryRun,
        exportedAt: Date = Date()
    ) -> DeliveryFunnelReport {
        let plan = run.plan
        let latestAttempts = DeliveryDispatchStateReducer
            .latestAttemptsByTaskID(in: run)
        let latestEvidence = latestEvidenceByRequirement(in: run)
        let startedDates = run.attempts
            .compactMap(\.startedAt)
            .sorted()
        let succeededTaskCount = latestAttempts.values.filter {
            $0.status == .succeeded
        }.count
        let verifiedTaskCount = plan?.tasks.filter { task in
            guard let attempt = latestAttempts[task.id] else {
                return false
            }
            return !task.evidenceRequirements.isEmpty
                && task.evidenceRequirements.allSatisfy { requirement in
                    latestEvidence[
                        evidenceKey(
                            attemptID: attempt.id,
                            requirementID: requirement.id
                        )
                    ]?.result == .passed
                }
        }.count ?? 0
        let attemptsByTaskID = Dictionary(
            grouping: run.attempts,
            by: \.taskID
        )
        let retryAttemptCount = attemptsByTaskID.values.reduce(0) {
            $0 + max(0, $1.count - 1)
        }
        let approvalDate = plan?.approval?.approvedAt
        let readyPullRequestCount = run.pullRequests.filter {
            ($0.state == .open || $0.state == .merged)
                && $0.checksState == .passed
                && ($0.reviewState == .approved
                    || $0.reviewState == .notRequired)
        }.count

        return DeliveryFunnelReport(
            format: DeliveryFunnelReport.formatIdentifier,
            schemaVersion: DeliveryFunnelReport.currentSchemaVersion,
            exportedAt: exportedAt,
            currentState: DeliveryDispatchStateReducer.state(for: run),
            taskCount: plan?.tasks.count ?? 0,
            approved: approvalDate != nil,
            startedSessionCount: run.attempts.filter {
                $0.externalSession != nil
            }.count,
            succeededTaskCount: succeededTaskCount,
            verifiedTaskCount: verifiedTaskCount,
            attemptCount: run.attempts.count,
            retryAttemptCount: retryAttemptCount,
            passedEvidenceCount: latestEvidence.values.filter {
                $0.result == .passed
            }.count,
            failedEvidenceCount: latestEvidence.values.filter {
                $0.result == .failed || $0.result == .unavailable
            }.count,
            pullRequestCount: run.pullRequests.count,
            readyPullRequestCount: readyPullRequestCount,
            needsAttentionCount: DeliveryAttentionDashboard
                .make(for: run)
                .needsYou
                .count,
            briefToApprovalSeconds: duration(
                from: run.brief.createdAt,
                to: approvalDate
            ),
            briefToFirstSessionSeconds: duration(
                from: run.brief.createdAt,
                to: startedDates.first
            ),
            briefToThreeSessionsSeconds: duration(
                from: run.brief.createdAt,
                to: startedDates.count >= 3 ? startedDates[2] : nil
            ),
            excludedSensitiveFields: [
                "acceptanceCriteria",
                "backendMessages",
                "branchAndCommitIdentifiers",
                "briefText",
                "commandsAndLogs",
                "filePaths",
                "pullRequestURLs",
                "repositoryIdentity",
                "taskTitlesAndPrompts"
            ]
        )
    }

    @discardableResult
    nonisolated func export(
        run: DeliveryRun,
        to destinationURL: URL,
        exportedAt: Date = Date()
    ) throws -> DeliveryFunnelReport {
        guard destinationURL.isFileURL,
              destinationURL.pathExtension.lowercased() == "json",
              !destinationURL.hasDirectoryPath else {
            throw DeliveryFunnelExportError.invalidDestination
        }
        let report = report(for: run, exportedAt: exportedAt)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(report)
        try data.write(to: destinationURL, options: .atomic)
        return report
    }

    nonisolated private func latestEvidenceByRequirement(
        in run: DeliveryRun
    ) -> [String: EvidenceFact] {
        var result: [String: EvidenceFact] = [:]
        for fact in run.evidenceFacts {
            let key = evidenceKey(
                attemptID: fact.attemptID,
                requirementID: fact.requirementID
            )
            guard let current = result[key] else {
                result[key] = fact
                continue
            }
            if fact.receivedAt > current.receivedAt
                || (fact.receivedAt == current.receivedAt
                    && fact.id.uuidString > current.id.uuidString) {
                result[key] = fact
            }
        }
        return result
    }

    nonisolated private func evidenceKey(
        attemptID: UUID,
        requirementID: UUID
    ) -> String {
        "\(attemptID.uuidString):\(requirementID.uuidString)"
    }

    nonisolated private func duration(
        from start: Date,
        to end: Date?
    ) -> TimeInterval? {
        end.map { max(0, $0.timeIntervalSince(start)) }
    }
}
