import Foundation

nonisolated enum DeliveryExecutionFactReducer {
    static func applying(
        _ page: ExecutionFactPage,
        to run: DeliveryRun,
        attemptID: UUID,
        expectedCursor: ExecutionFactCursor?,
        receivedAt: Date
    ) throws -> DeliveryRun {
        var updatedRun = run
        guard let plan = updatedRun.plan,
              let attemptIndex = updatedRun.attempts.firstIndex(where: {
                  $0.id == attemptID
              }),
              let task = plan.tasks.first(where: {
                  $0.id == updatedRun.attempts[attemptIndex].taskID
              }),
              let session = updatedRun.attempts[attemptIndex].externalSession else {
            throw DeliveryExecutionReconcileError.sessionUnavailable(
                attemptID
            )
        }

        var attempt = updatedRun.attempts[attemptIndex]
        guard attempt.nextFactCursor == expectedCursor?.rawValue else {
            throw DeliveryExecutionReconcileError.cursorChanged(
                attemptID: attemptID,
                expected: expectedCursor?.rawValue,
                current: attempt.nextFactCursor
            )
        }
        try validate(
            page,
            attempt: attempt,
            session: session,
            run: updatedRun,
            receivedAt: receivedAt
        )
        let clearedReconcileFailure =
            attempt.lastReconcileFailureReason != nil
                || attempt.lastReconcileFailedAt != nil
        attempt.lastReconcileFailureReason = nil
        attempt.lastReconcileFailedAt = nil

        for fact in page.facts {
            let observationID = executionObservationID(
                factID: fact.id,
                session: session
            )
            let observationContent = executionObservationContent(
                for: fact.body
            )
            updatedRun.executionObservations.append(
                ExecutionBackendObservation(
                    id: observationID,
                    taskID: attempt.taskID,
                    attemptID: attempt.id,
                    sequence: fact.sequence,
                    occurredAt: fact.occurredAt,
                    receivedAt: receivedAt,
                    kind: observationContent.kind,
                    summary: observationContent.summary,
                    rawPayload: observationContent.rawPayload,
                    retryable: observationContent.retryable
                )
            )
            apply(
                fact,
                observationID: observationID,
                task: task,
                run: &updatedRun,
                attempt: &attempt,
                receivedAt: receivedAt
            )
        }

        if let lastSequence = page.facts.last?.sequence {
            attempt.lastFactSequence = lastSequence
        }
        attempt.nextFactCursor = page.nextCursor?.rawValue
        attempt.isFactStreamExhausted = !page.hasMore
        if attempt.isFactStreamExhausted {
            switch attempt.status {
            case .queued, .running:
                attempt.status = .unknown
            case .blocked, .succeeded, .failed, .stopped, .unknown:
                break
            }
        }
        updatedRun.attempts[attemptIndex] = attempt
        if !page.facts.isEmpty || clearedReconcileFailure {
            updatedRun.updatedAt = receivedAt
        }
        return updatedRun
    }

    private static func validate(
        _ page: ExecutionFactPage,
        attempt: ExecutionAttempt,
        session: ExternalSessionRef,
        run: DeliveryRun,
        receivedAt: Date
    ) throws {
        if page.hasMore {
            guard let nextCursor = page.nextCursor?.rawValue,
                  !nextCursor.trimmingCharacters(
                      in: .whitespacesAndNewlines
                  ).isEmpty else {
                throw DeliveryExecutionReconcileError.malformedFactPage(
                    attemptID: attempt.id,
                    reason: "A non-terminal page requires a cursor."
                )
            }
            if page.facts.isEmpty {
                guard nextCursor == attempt.nextFactCursor else {
                    throw DeliveryExecutionReconcileError.malformedFactPage(
                        attemptID: attempt.id,
                        reason: "An idle polling page must preserve its cursor."
                    )
                }
            } else if nextCursor == attempt.nextFactCursor {
                throw DeliveryExecutionReconcileError.malformedFactPage(
                    attemptID: attempt.id,
                    reason: "A non-terminal fact page requires a new cursor."
                )
            }
        }
        if page.nextCursor?.rawValue.trimmingCharacters(
            in: .whitespacesAndNewlines
        ).isEmpty == true {
            throw DeliveryExecutionReconcileError.malformedFactPage(
                attemptID: attempt.id,
                reason: "The next cursor is empty."
            )
        }

        var previousSequence = attempt.lastFactSequence ?? 0
        var pageIDs: Set<String> = []
        let persistedObservationIDs = Set(
            run.executionObservations.map(\.id)
        )
        for fact in page.facts {
            let observationID = executionObservationID(
                factID: fact.id,
                session: session
            )
            guard fact.executionID.rawValue == session.sessionID,
                  !fact.id.rawValue.trimmingCharacters(
                      in: .whitespacesAndNewlines
                  ).isEmpty,
                  fact.sequence > previousSequence,
                  fact.occurredAt >= attempt.createdAt,
                  fact.occurredAt <= receivedAt,
                  pageIDs.insert(observationID).inserted,
                  !persistedObservationIDs.contains(observationID) else {
                throw DeliveryExecutionReconcileError.malformedFactPage(
                    attemptID: attempt.id,
                    reason: "Fact identity, execution, sequence, or chronology is invalid."
                )
            }
            previousSequence = fact.sequence
        }
    }

    private static func executionObservationID(
        factID: ExecutionFactID,
        session: ExternalSessionRef
    ) -> String {
        "\(session.backendID):\(session.sessionID):\(factID.rawValue)"
    }

    private static func executionObservationContent(
        for body: ExecutionFactBody
    ) -> (
        kind: ExecutionBackendObservationKind,
        summary: String,
        rawPayload: String?,
        retryable: Bool?
    ) {
        switch body {
        case let .phase(phase):
            return (
                .phase,
                "Backend phase: \(phase.rawValue).",
                nil,
                nil
            )
        case let .inputRequested(prompt):
            return (.inputRequested, prompt, nil, nil)
        case let .commandEvidence(evidence):
            return (
                .commandEvidence,
                "\(evidence.summary) (exit \(evidence.exitCode)).",
                evidence.command,
                evidence.exitCode != 0
            )
        case let .changedFilesEvidence(evidence):
            return (
                .changedFilesEvidence,
                evidence.paths.isEmpty
                    ? "No changed files were reported."
                    : "Changed files: \(evidence.paths.joined(separator: ", ")).",
                evidence.paths.joined(separator: "\n"),
                false
            )
        case let .pullRequestEvidence(evidence):
            return (
                .pullRequestEvidence,
                "Pull request \(evidence.url.absoluteString) is \(evidence.state.rawValue).",
                evidence.headSHA,
                false
            )
        case let .diagnostic(diagnostic):
            return (
                .diagnostic,
                diagnostic.message,
                diagnostic.code,
                diagnostic.retryable
            )
        case let .unknown(kind, rawPayload):
            return (
                .unknown,
                "Unknown backend fact: \(kind).",
                rawPayload,
                nil
            )
        }
    }

    private static func apply(
        _ fact: ExecutionFact,
        observationID: String,
        task: DeliveryTask,
        run: inout DeliveryRun,
        attempt: inout ExecutionAttempt,
        receivedAt: Date
    ) {
        switch fact.body {
        case let .phase(phase):
            apply(
                phase,
                attempt: &attempt,
                receivedAt: receivedAt
            )
        case .inputRequested:
            if !isTerminal(attempt.status) {
                attempt.status = .blocked
            }
        case let .commandEvidence(evidence):
            let kind: EvidenceKind?
            switch evidence.kind {
            case .xcodeBuild:
                kind = .xcodeBuild
            case .test:
                kind = .xcodeTest
            case .other:
                kind = nil
            }
            if let kind {
                appendEvidence(
                    matching: [kind],
                    result: evidence.exitCode == 0 ? .passed : .failed,
                    summary: evidence.summary,
                    sourceReference: evidence.command,
                    observationID: observationID,
                    observedAt: fact.occurredAt,
                    receivedAt: receivedAt,
                    task: task,
                    attempt: attempt,
                    run: &run
                )
            }
        case let .changedFilesEvidence(evidence):
            appendEvidence(
                matching: [.changedFiles],
                result: evidence.paths.isEmpty ? .failed : .passed,
                summary: evidence.paths.isEmpty
                    ? "No changed files were reported."
                    : "\(evidence.paths.count) changed file(s) were reported.",
                sourceReference: evidence.paths.joined(separator: "\n"),
                observationID: observationID,
                observedAt: fact.occurredAt,
                receivedAt: receivedAt,
                task: task,
                attempt: attempt,
                run: &run
            )
        case let .pullRequestEvidence(evidence):
            upsertPullRequest(
                evidence,
                task: task,
                attempt: attempt,
                run: &run
            )
            appendPullRequestEvidence(
                evidence,
                observationID: observationID,
                observedAt: fact.occurredAt,
                receivedAt: receivedAt,
                task: task,
                attempt: attempt,
                run: &run
            )
        case let .diagnostic(diagnostic):
            if diagnostic.severity == .error,
               !isTerminal(attempt.status) {
                attempt.status = .blocked
            }
        case .unknown:
            if !isTerminal(attempt.status) {
                attempt.status = .unknown
            }
        }
    }

    private static func apply(
        _ phase: ExecutionPhase,
        attempt: inout ExecutionAttempt,
        receivedAt: Date
    ) {
        switch phase {
        case .accepted, .running:
            guard !isTerminal(attempt.status) else { return }
            attempt.status = .running
            attempt.startedAt = attempt.startedAt ?? receivedAt
        case .waitingForInput:
            guard !isTerminal(attempt.status) else { return }
            attempt.status = .blocked
        case .stopping:
            guard !isTerminal(attempt.status) else { return }
            attempt.status = .running
            attempt.stopRequestedAt = attempt.stopRequestedAt ?? receivedAt
        case .stopped:
            attempt.status = .stopped
            attempt.endedAt = receivedAt
        case .succeeded:
            attempt.status = .succeeded
            attempt.endedAt = receivedAt
        case .failed:
            attempt.status = .failed
            attempt.endedAt = receivedAt
        }
    }

    private static func appendPullRequestEvidence(
        _ evidence: ExecutionPullRequestEvidence,
        observationID: String,
        observedAt: Date,
        receivedAt: Date,
        task: DeliveryTask,
        attempt: ExecutionAttempt,
        run: inout DeliveryRun
    ) {
        let pullRequestResult: EvidenceResult
        switch evidence.state {
        case .open, .merged:
            pullRequestResult = .passed
        case .closed:
            pullRequestResult = .failed
        }
        appendEvidence(
            matching: [.pullRequest],
            result: pullRequestResult,
            summary: "Pull request is \(evidence.state.rawValue).",
            sourceReference: evidence.url.absoluteString,
            observationID: observationID,
            observedAt: observedAt,
            receivedAt: receivedAt,
            task: task,
            attempt: attempt,
            run: &run
        )

        let checksResult: EvidenceResult
        switch evidence.checks {
        case .passing:
            checksResult = .passed
        case .failing:
            checksResult = .failed
        case .pending, .unknown:
            checksResult = .unknown
        }
        appendEvidence(
            matching: [.ciChecks],
            result: checksResult,
            summary: "Pull request checks are \(evidence.checks.rawValue).",
            sourceReference: evidence.url.absoluteString,
            observationID: observationID,
            observedAt: observedAt,
            receivedAt: receivedAt,
            task: task,
            attempt: attempt,
            run: &run
        )

        let reviewResult: EvidenceResult
        switch evidence.review {
        case .approved:
            reviewResult = .passed
        case .changesRequested:
            reviewResult = .failed
        case .required, .unknown:
            reviewResult = .unknown
        }
        appendEvidence(
            matching: [.reviewApproval],
            result: reviewResult,
            summary: "Pull request review is \(evidence.review.rawValue).",
            sourceReference: evidence.url.absoluteString,
            observationID: observationID,
            observedAt: observedAt,
            receivedAt: receivedAt,
            task: task,
            attempt: attempt,
            run: &run
        )
    }

    private static func appendEvidence(
        matching kinds: [EvidenceKind],
        result: EvidenceResult,
        summary: String,
        sourceReference: String?,
        observationID: String,
        observedAt: Date,
        receivedAt: Date,
        task: DeliveryTask,
        attempt: ExecutionAttempt,
        run: inout DeliveryRun
    ) {
        for requirement in task.evidenceRequirements
        where kinds.contains(requirement.kind) {
            let rawObservationID = "\(observationID)#\(requirement.id.uuidString)"
            guard !run.evidenceFacts.contains(where: {
                $0.rawObservationID == rawObservationID
            }) else {
                continue
            }
            let latestFact = run.evidenceFacts
                .filter {
                    $0.taskID == task.id
                        && $0.attemptID == attempt.id
                        && $0.requirementID == requirement.id
                }
                .max {
                    if $0.receivedAt != $1.receivedAt {
                        return $0.receivedAt < $1.receivedAt
                    }
                    return $0.id.uuidString < $1.id.uuidString
                }
            run.evidenceFacts.append(
                EvidenceFact(
                    taskID: task.id,
                    attemptID: attempt.id,
                    requirementID: requirement.id,
                    result: result,
                    source: .executionBackend,
                    summary: summary,
                    sourceReference: sourceReference,
                    observedAt: observedAt,
                    receivedAt: receivedAt,
                    rawObservationID: rawObservationID,
                    supersedesFactID: latestFact?.id
                )
            )
        }
    }

    private static func upsertPullRequest(
        _ evidence: ExecutionPullRequestEvidence,
        task: DeliveryTask,
        attempt: ExecutionAttempt,
        run: inout DeliveryRun
    ) {
        let id = "\(attempt.id.uuidString):\(evidence.url.absoluteString)"
        let pullRequest = PullRequestRef(
            id: id,
            taskID: task.id,
            attemptID: attempt.id,
            url: evidence.url,
            headBranch: "backend-managed",
            headCommitIdentifier: evidence.headSHA,
            baseBranch: run.brief.repository.baseBranch,
            state: pullRequestState(evidence.state),
            checksState: pullRequestChecksState(evidence.checks),
            reviewState: pullRequestReviewState(evidence.review)
        )
        if let index = run.pullRequests.firstIndex(where: { $0.id == id }) {
            run.pullRequests[index] = pullRequest
        } else {
            run.pullRequests.append(pullRequest)
        }
    }

    private static func pullRequestState(
        _ state: ExecutionPullRequestState
    ) -> PullRequestState {
        switch state {
        case .open:
            return .open
        case .merged:
            return .merged
        case .closed:
            return .closed
        }
    }

    private static func pullRequestChecksState(
        _ state: ExecutionCheckState
    ) -> PullRequestChecksState {
        switch state {
        case .pending:
            return .pending
        case .passing:
            return .passed
        case .failing:
            return .failed
        case .unknown:
            return .unknown
        }
    }

    private static func pullRequestReviewState(
        _ state: ExecutionReviewState
    ) -> PullRequestReviewState {
        switch state {
        case .required:
            return .pending
        case .approved:
            return .approved
        case .changesRequested:
            return .changesRequested
        case .unknown:
            return .unknown
        }
    }

    private static func isTerminal(
        _ status: ExecutionAttemptStatus
    ) -> Bool {
        switch status {
        case .succeeded, .failed, .stopped:
            return true
        case .queued, .running, .blocked, .unknown:
            return false
        }
    }
}
