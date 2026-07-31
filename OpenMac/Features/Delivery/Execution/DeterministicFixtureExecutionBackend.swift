import Foundation

typealias FixtureDelayHook = @Sendable (ExecutionBackendOperation, Int) async throws -> Void

nonisolated enum FixtureExecutionTimestampMode: Sendable {
    case deterministic
    case wallClock
}

nonisolated struct FixtureExecutionScript: Equatable, Sendable {
    var factBatches: [[ExecutionFactBody]]
    var startError: ExecutionBackendError?

    nonisolated init(
        factBatches: [[ExecutionFactBody]],
        startError: ExecutionBackendError? = nil
    ) {
        self.factBatches = factBatches
        self.startError = startError
    }

    nonisolated static var happyXcodePullRequest: FixtureExecutionScript {
        FixtureExecutionScript(
            factBatches: [
                [.phase(.accepted)],
                [.phase(.running)],
                [
                    .changedFilesEvidence(
                        ExecutionChangedFilesEvidence(
                            paths: ["Sources/FixtureFeature.swift"]
                        )
                    )
                ],
                [
                    .commandEvidence(
                        ExecutionCommandEvidence(
                            kind: .xcodeBuild,
                            command: "xcodebuild build",
                            exitCode: 0,
                            summary: "Build succeeded"
                        )
                    )
                ],
                [
                    .commandEvidence(
                        ExecutionCommandEvidence(
                            kind: .test,
                            command: "xcodebuild test",
                            exitCode: 0,
                            summary: "Tests succeeded"
                        )
                    )
                ],
                [
                    .pullRequestEvidence(
                        ExecutionPullRequestEvidence(
                            url: URL(string: "https://github.com/example/openmac/pull/1")!,
                            headSHA: "fixture-head-sha",
                            state: .open,
                            checks: .passing,
                            review: .approved
                        )
                    )
                ],
                [.phase(.succeeded)]
            ]
        )
    }

    nonisolated static var waitingForInput: FixtureExecutionScript {
        FixtureExecutionScript(
            factBatches: [
                [.phase(.accepted)],
                [.phase(.running)],
                [
                    .phase(.waitingForInput),
                    .inputRequested(prompt: "Choose the intended Xcode scheme.")
                ]
            ]
        )
    }

    nonisolated static var buildFailure: FixtureExecutionScript {
        FixtureExecutionScript(
            factBatches: [
                [.phase(.accepted)],
                [.phase(.running)],
                [
                    .commandEvidence(
                        ExecutionCommandEvidence(
                            kind: .xcodeBuild,
                            command: "xcodebuild build",
                            exitCode: 65,
                            summary: "Build failed"
                        )
                    ),
                    .phase(.failed)
                ]
            ]
        )
    }

    nonisolated static var unknownFact: FixtureExecutionScript {
        FixtureExecutionScript(
            factBatches: [
                [.phase(.accepted)],
                [
                    .unknown(
                        kind: "fixture.unrecognized-state",
                        rawPayload: #"{"state":"future","detail":"preserved"}"#
                    )
                ]
            ]
        )
    }
}

nonisolated struct FixtureExecutionBackendConfiguration: Sendable {
    var backendID: String
    var health: ExecutionBackendHealth
    var projects: [ExecutionProject]
    var baseTime: Date
    var timestampMode: FixtureExecutionTimestampMode
    var defaultScript: FixtureExecutionScript
    var scriptsByTaskID: [UUID: FixtureExecutionScript]
    var faultsByOperationAndInvocation: [ExecutionBackendOperation: [Int: ExecutionBackendError]]

    nonisolated init(
        backendID: String = "fixture",
        health: ExecutionBackendHealth,
        projects: [ExecutionProject],
        baseTime: Date,
        timestampMode: FixtureExecutionTimestampMode = .deterministic,
        defaultScript: FixtureExecutionScript = .happyXcodePullRequest,
        scriptsByTaskID: [UUID: FixtureExecutionScript] = [:],
        faultsByOperationAndInvocation: [ExecutionBackendOperation: [Int: ExecutionBackendError]] = [:]
    ) {
        self.backendID = backendID
        self.health = health
        self.projects = projects
        self.baseTime = baseTime
        self.timestampMode = timestampMode
        self.defaultScript = defaultScript
        self.scriptsByTaskID = scriptsByTaskID
        self.faultsByOperationAndInvocation = faultsByOperationAndInvocation
    }

    nonisolated static var standard: FixtureExecutionBackendConfiguration {
        let baseTime = Date(timeIntervalSince1970: 1_784_371_200)
        return FixtureExecutionBackendConfiguration(
            health: ExecutionBackendHealth(
                state: .ready,
                backendName: "Deterministic Fixture",
                version: "1",
                checkedAt: baseTime
            ),
            projects: [
                ExecutionProject(
                    id: ExecutionProjectID("fixture-project"),
                    name: "Fixture Xcode Project",
                    repositoryURL: URL(fileURLWithPath: "/fixture/OpenMac"),
                    isolation: .isolatedWorkspace
                )
            ],
            baseTime: baseTime
        )
    }
}

actor DeterministicFixtureExecutionBackend: ExecutionBackend {
    nonisolated let backendID: String

    private struct ExecutionRecord: Sendable {
        let request: ExecutionStartRequest
        let receipt: ExecutionStartReceipt
        var script: FixtureExecutionScript
        var highestBatchIndexServed: Int?
        var isStopped: Bool
    }

    private let configuration: FixtureExecutionBackendConfiguration
    private let delayHook: FixtureDelayHook
    private var invocationCounts: [ExecutionBackendOperation: Int] = [:]
    private var executionCounter = 0
    private var executionIDByRequestID: [UUID: ExecutionID] = [:]
    private var recordsByExecutionID: [ExecutionID: ExecutionRecord] = [:]

    init(
        configuration: FixtureExecutionBackendConfiguration = .standard,
        delayHook: @escaping FixtureDelayHook = { _, _ in }
    ) {
        self.backendID = configuration.backendID
        self.configuration = configuration
        self.delayHook = delayHook
    }

    func health() async throws -> ExecutionBackendHealth {
        _ = try await prepare(.health)
        return configuration.health
    }

    func listProjects() async throws -> [ExecutionProject] {
        _ = try await prepare(.listProjects)
        return configuration.projects
    }

    func start(_ request: ExecutionStartRequest) async throws -> ExecutionStartReceipt {
        _ = try await prepare(.start)

        if let existingExecutionID = executionIDByRequestID[request.requestID],
           let existingRecord = recordsByExecutionID[existingExecutionID] {
            guard existingRecord.request == request else {
                throw ExecutionBackendError.conflict(
                    "The idempotency request ID was reused with different instructions."
                )
            }
            return existingRecord.receipt
        }

        guard let project = configuration.projects.first(
            where: { $0.id == request.projectID }
        ) else {
            throw ExecutionBackendError.projectNotFound(request.projectID)
        }

        let script = configuration.scriptsByTaskID[request.taskID] ?? configuration.defaultScript
        if let startError = script.startError {
            throw startError
        }

        executionCounter += 1
        let executionID = ExecutionID(String(format: "fixture-exec-%04d", executionCounter))
        let receipt = ExecutionStartReceipt(
            requestID: request.requestID,
            executionID: executionID,
            acceptedAt: configuration.timestampMode == .wallClock
                ? Date()
                : configuration.baseTime.addingTimeInterval(
                    TimeInterval(executionCounter)
                ),
            branch: request.baseBranch,
            verificationWorkspaceURL: project.repositoryURL
        )
        let record = ExecutionRecord(
            request: request,
            receipt: receipt,
            script: script,
            highestBatchIndexServed: nil,
            isStopped: false
        )
        recordsByExecutionID[executionID] = record
        executionIDByRequestID[request.requestID] = executionID
        return receipt
    }

    func facts(
        for executionID: ExecutionID,
        after cursor: ExecutionFactCursor?
    ) async throws -> ExecutionFactPage {
        _ = try await prepare(.facts)

        guard var record = recordsByExecutionID[executionID] else {
            throw ExecutionBackendError.executionNotFound(executionID)
        }

        let batchIndex = try resolvedBatchIndex(cursor, executionID: executionID)
        if cursor != nil {
            let highestIssuedCursorIndex = (record.highestBatchIndexServed ?? -1) + 1
            guard batchIndex >= 1, batchIndex <= highestIssuedCursorIndex else {
                throw ExecutionBackendError.malformedResponse(
                    operation: .facts,
                    reason: "The fixture cursor was not issued for this execution."
                )
            }
        }
        guard batchIndex <= record.script.factBatches.count else {
            throw ExecutionBackendError.malformedResponse(
                operation: .facts,
                reason: "The fixture cursor points beyond the scripted fact stream."
            )
        }

        guard batchIndex < record.script.factBatches.count else {
            return ExecutionFactPage(
                facts: [],
                nextCursor: cursor,
                hasMore: false
            )
        }

        let sequenceOffset = record.script.factBatches
            .prefix(batchIndex)
            .reduce(0) { $0 + $1.count }
        let bodies = record.script.factBatches[batchIndex]
        let wallClockFactTime = Date()
        let facts = bodies.enumerated().map { bodyIndex, body in
            let sequence = UInt64(sequenceOffset + bodyIndex + 1)
            return ExecutionFact(
                id: ExecutionFactID(
                    String(format: "%@-fact-%04llu", executionID.rawValue, sequence)
                ),
                executionID: executionID,
                sequence: sequence,
                occurredAt: configuration.timestampMode == .wallClock
                    ? wallClockFactTime
                    : record.receipt.acceptedAt.addingTimeInterval(
                        TimeInterval(sequence)
                    ),
                body: body
            )
        }

        record.highestBatchIndexServed = max(
            record.highestBatchIndexServed ?? -1,
            batchIndex
        )
        recordsByExecutionID[executionID] = record

        let nextIndex = batchIndex + 1
        return ExecutionFactPage(
            facts: facts,
            nextCursor: makeCursor(for: executionID, batchIndex: nextIndex),
            hasMore: nextIndex < record.script.factBatches.count
        )
    }

    func stop(executionID: ExecutionID) async throws -> ExecutionStopReceipt {
        let invocation = try await prepare(.stop)

        guard var record = recordsByExecutionID[executionID] else {
            throw ExecutionBackendError.executionNotFound(executionID)
        }

        if record.isStopped {
            return stopReceipt(
                executionID: executionID,
                disposition: .alreadyStopped,
                invocation: invocation
            )
        }

        if latestServedPhase(in: record) == .stopped {
            return stopReceipt(
                executionID: executionID,
                disposition: .alreadyStopped,
                invocation: invocation
            )
        }

        if latestServedPhase(in: record) == .succeeded
            || latestServedPhase(in: record) == .failed {
            return stopReceipt(
                executionID: executionID,
                disposition: .alreadyTerminal,
                invocation: invocation
            )
        }

        let servedBatchCount = (record.highestBatchIndexServed ?? -1) + 1
        record.script.factBatches = Array(record.script.factBatches.prefix(servedBatchCount))
        record.script.factBatches.append([
            .phase(.stopping),
            .phase(.stopped)
        ])
        record.isStopped = true
        recordsByExecutionID[executionID] = record

        return stopReceipt(
            executionID: executionID,
            disposition: .accepted,
            invocation: invocation
        )
    }

    func invocationCount(for operation: ExecutionBackendOperation) -> Int {
        invocationCounts[operation, default: 0]
    }

    func executionCount() -> Int {
        recordsByExecutionID.count
    }

    func recordedStartRequests() -> [ExecutionStartRequest] {
        recordsByExecutionID.values
            .map(\.request)
            .sorted { $0.requestID.uuidString < $1.requestID.uuidString }
    }

    private func prepare(_ operation: ExecutionBackendOperation) async throws -> Int {
        let invocation = invocationCounts[operation, default: 0] + 1
        invocationCounts[operation] = invocation

        try await delayHook(operation, invocation)
        try Task.checkCancellation()

        if let fault = configuration.faultsByOperationAndInvocation[operation]?[invocation] {
            throw fault
        }
        return invocation
    }

    private func resolvedBatchIndex(
        _ cursor: ExecutionFactCursor?,
        executionID: ExecutionID
    ) throws -> Int {
        guard let cursor else { return 0 }
        let prefix = "\(executionID.rawValue):"
        guard cursor.rawValue.hasPrefix(prefix),
              let batchIndex = Int(cursor.rawValue.dropFirst(prefix.count)),
              batchIndex >= 0 else {
            throw ExecutionBackendError.malformedResponse(
                operation: .facts,
                reason: "The fixture cursor is invalid for this execution."
            )
        }
        return batchIndex
    }

    private func makeCursor(
        for executionID: ExecutionID,
        batchIndex: Int
    ) -> ExecutionFactCursor {
        ExecutionFactCursor("\(executionID.rawValue):\(batchIndex)")
    }

    private func latestServedPhase(in record: ExecutionRecord) -> ExecutionPhase? {
        guard let highestBatchIndexServed = record.highestBatchIndexServed else {
            return nil
        }

        for batch in record.script.factBatches
            .prefix(highestBatchIndexServed + 1)
            .reversed() {
            for body in batch.reversed() {
                if case let .phase(phase) = body {
                    return phase
                }
            }
        }
        return nil
    }

    private func stopReceipt(
        executionID: ExecutionID,
        disposition: ExecutionStopDisposition,
        invocation: Int
    ) -> ExecutionStopReceipt {
        ExecutionStopReceipt(
            executionID: executionID,
            disposition: disposition,
            acknowledgedAt: configuration.timestampMode == .wallClock
                ? Date()
                : configuration.baseTime.addingTimeInterval(
                    TimeInterval(10_000 + invocation)
                )
        )
    }
}
