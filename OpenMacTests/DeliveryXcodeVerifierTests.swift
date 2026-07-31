import Foundation
import Testing
@testable import OpenMac

private actor CapturedXcodeCommandRunner: XcodeCommandRunning {
    private var results: [XcodeCommandResult]
    private var capturedInvocations: [XcodeCommandInvocation] = []

    init(results: [XcodeCommandResult]) {
        self.results = results
    }

    func run(
        _ invocation: XcodeCommandInvocation
    ) async throws -> XcodeCommandResult {
        capturedInvocations.append(invocation)
        guard !results.isEmpty else {
            throw URLError(.resourceUnavailable)
        }
        return results.removeFirst()
    }

    func invocations() -> [XcodeCommandInvocation] {
        capturedInvocations
    }
}

private enum DeliveryXcodeVerifierTestSupport {
    static func commandResult(
        exitCode: Int32 = 0,
        stdout: String = "",
        stderr: String = "",
        timedOut: Bool = false
    ) -> XcodeCommandResult {
        XcodeCommandResult(
            exitCode: exitCode,
            stdout: stdout,
            stderr: stderr,
            timedOut: timedOut
        )
    }

    static func stubRunner(
        commonDirectoryPath: String,
        branch: String,
        xcodeResult: XcodeCommandResult
    ) -> CapturedXcodeCommandRunner {
        CapturedXcodeCommandRunner(
            results: [
                commandResult(
                    stdout: commonDirectoryPath + "\n"
                ),
                commandResult(stdout: branch + "\n"),
                xcodeResult
            ]
        )
    }

    static func verifier(
        runner: any XcodeCommandRunning,
        directoryURL: URL,
        clock: DeliveryDispatchTestClock
    ) -> XcodeVerifier {
        XcodeVerifier(
            runner: runner,
            artifactRootURL: directoryURL.appendingPathComponent(
                "artifacts",
                isDirectory: true
            ),
            derivedDataRootURL: directoryURL.appendingPathComponent(
                "derived-data",
                isDirectory: true
            ),
            now: clock.now
        )
    }

    static func makeSwiftPackage() throws -> (
        rootURL: URL,
        commonDirectoryURL: URL
    ) {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "openmac-xcode-verifier-sample-\(UUID().uuidString)",
                isDirectory: true
            )
        let sourceURL = rootURL
            .appendingPathComponent("Sources", isDirectory: true)
            .appendingPathComponent("VerifierSample", isDirectory: true)
        try FileManager.default.createDirectory(
            at: sourceURL,
            withIntermediateDirectories: true
        )
        try Data(
            """
            // swift-tools-version: 6.0
            import PackageDescription

            let package = Package(
                name: "VerifierSample",
                products: [
                    .library(
                        name: "VerifierSample",
                        targets: ["VerifierSample"]
                    )
                ],
                targets: [
                    .target(name: "VerifierSample")
                ]
            )
            """.utf8
        ).write(
            to: rootURL.appendingPathComponent("Package.swift"),
            options: .atomic
        )
        try Data(
            """
            public struct VerifierSample {
                public init() {}
                public let value = 42
            }
            """.utf8
        ).write(
            to: sourceURL.appendingPathComponent("VerifierSample.swift"),
            options: .atomic
        )
        try DeliveryGitTestRepository.runGit(["init"], in: rootURL)
        try DeliveryGitTestRepository.runGit(
            ["symbolic-ref", "HEAD", "refs/heads/main"],
            in: rootURL
        )
        try DeliveryGitTestRepository.runGit(
            ["config", "user.email", "openmac-tests@example.invalid"],
            in: rootURL
        )
        try DeliveryGitTestRepository.runGit(
            ["config", "user.name", "OpenMac Tests"],
            in: rootURL
        )
        try DeliveryGitTestRepository.runGit(["add", "."], in: rootURL)
        try DeliveryGitTestRepository.runGit(
            ["commit", "-m", "Initial verifier sample"],
            in: rootURL
        )
        let commonPath = try DeliveryGitTestRepository.runGit(
            [
                "rev-parse",
                "--path-format=absolute",
                "--git-common-dir"
            ],
            in: rootURL
        )
        return (
            rootURL,
            URL(fileURLWithPath: commonPath, isDirectory: true)
        )
    }
}

@Suite("Delivery v2 Xcode verifier", .serialized)
struct DeliveryXcodeVerifierTests {
    @Test("verifier uses argument arrays and preserves command result")
    func verifierBuildsSafeInvocation() async throws {
        let repository = DeliveryGitTestRepository.shared
        let context = try DeliveryPlanningRepositoryContext.resolving(
            repositoryRootPath: repository.rootURL.path,
            containerKind: .xcodeProject,
            containerRelativePath: repository.containerRelativePath,
            targetNames: ["OpenMac"],
            schemeNames: ["OpenMac"]
        )
        let identity = try context.identitySnapshot(
            validatingBaseBranch: repository.baseBranch
        )
        let runner = DeliveryXcodeVerifierTestSupport.stubRunner(
            commonDirectoryPath: identity.gitCommonDirectoryPath,
            branch: repository.baseBranch,
            xcodeResult: DeliveryXcodeVerifierTestSupport.commandResult(
                stdout: "** BUILD SUCCEEDED **\n"
            )
        )
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "openmac-verifier-safe-\(UUID().uuidString)",
                isDirectory: true
            )
        defer { try? FileManager.default.removeItem(at: directoryURL) }
        let clock = DeliveryDispatchTestClock(
            startingAt: Date(timeIntervalSince1970: 1_785_500_000)
        )
        let verifier = DeliveryXcodeVerifierTestSupport.verifier(
            runner: runner,
            directoryURL: directoryURL,
            clock: clock
        )

        let record = try await verifier.verify(
            XcodeVerificationRequest(
                kind: .build,
                scheme: "OpenMac",
                workspaceURL: repository.rootURL,
                expectedGitCommonDirectoryURL: URL(
                    fileURLWithPath: identity.gitCommonDirectoryPath,
                    isDirectory: true
                ),
                expectedBranch: repository.baseBranch,
                containerKind: .xcodeProject,
                containerRelativePath: repository.containerRelativePath
            )
        )
        let invocations = await runner.invocations()
        let xcodeInvocation = try #require(invocations.last)

        #expect(invocations.count == 3)
        #expect(xcodeInvocation.executableURL.path == "/usr/bin/xcrun")
        #expect(xcodeInvocation.arguments.first == "xcodebuild")
        #expect(xcodeInvocation.arguments.contains("-project"))
        #expect(xcodeInvocation.arguments.contains("OpenMac"))
        #expect(xcodeInvocation.arguments.last == "build")
        #expect(record.exitCode == 0)
        #expect(!record.timedOut)
        #expect(record.command.contains("/usr/bin/xcrun xcodebuild"))
        #expect(record.summary.contains("passed"))
    }

    @Test("workspace branch mismatch prevents xcodebuild")
    func branchMismatchFailsClosed() async throws {
        let repository = DeliveryGitTestRepository.shared
        let commonPath = try DeliveryGitTestRepository.runGit(
            [
                "rev-parse",
                "--path-format=absolute",
                "--git-common-dir"
            ],
            in: repository.rootURL
        )
        let runner = CapturedXcodeCommandRunner(
            results: [
                DeliveryXcodeVerifierTestSupport.commandResult(
                    stdout: commonPath + "\n"
                ),
                DeliveryXcodeVerifierTestSupport.commandResult(
                    stdout: "unexpected-branch\n"
                )
            ]
        )
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "openmac-verifier-branch-\(UUID().uuidString)",
                isDirectory: true
            )
        defer { try? FileManager.default.removeItem(at: directoryURL) }
        let verifier = DeliveryXcodeVerifierTestSupport.verifier(
            runner: runner,
            directoryURL: directoryURL,
            clock: DeliveryDispatchTestClock(startingAt: Date())
        )

        do {
            _ = try await verifier.verify(
                XcodeVerificationRequest(
                    kind: .test,
                    scheme: "OpenMac",
                    workspaceURL: repository.rootURL,
                    expectedGitCommonDirectoryURL: URL(
                        fileURLWithPath: commonPath,
                        isDirectory: true
                    ),
                    expectedBranch: "main",
                    containerKind: .xcodeProject,
                    containerRelativePath: repository.containerRelativePath
                )
            )
            Issue.record("Expected branch mismatch")
        } catch let error as XcodeVerifierError {
            #expect(
                error == .branchMismatch(
                    expected: "main",
                    actual: "unexpected-branch"
                )
            )
        }
        #expect(await runner.invocations().count == 2)
    }

    @Test("verification evidence persists and a later failure supersedes it")
    func coordinatorPersistsSupersedingEvidence() async throws {
        let (store, directoryURL) = try await DeliveryDispatchFixture.makeStore(
            label: "xcode-verifier-persistence"
        )
        defer { try? FileManager.default.removeItem(at: directoryURL) }
        let backend = DeterministicFixtureExecutionBackend(
            configuration: DeliveryDispatchFixture.backendConfiguration()
        )
        let dispatcher = DeliveryDispatcher(
            store: store,
            backend: backend,
            projectID: DeliveryDispatchFixture.projectID
        )
        _ = try await dispatcher.dispatchReadyWave(
            runID: DeliveryDispatchFixture.runID
        )
        let completedAt = Date()
        _ = try await DeliveryDispatchFixture.markCurrentAttemptsSucceeded(
            in: store,
            at: completedAt
        )
        let identity = try #require(
            try await store.load()?.runs.first?.repositoryIdentity
        )
        let passingRunner = DeliveryXcodeVerifierTestSupport.stubRunner(
            commonDirectoryPath: identity.gitCommonDirectoryPath,
            branch: DeliveryGitTestRepository.shared.baseBranch,
            xcodeResult: DeliveryXcodeVerifierTestSupport.commandResult(
                stdout: "** TEST SUCCEEDED **\n"
            )
        )
        let passingClock = DeliveryDispatchTestClock(
            startingAt: completedAt.addingTimeInterval(10)
        )
        let passingCoordinator = DeliveryXcodeVerificationCoordinator(
            store: store,
            verifier: DeliveryXcodeVerifierTestSupport.verifier(
                runner: passingRunner,
                directoryURL: directoryURL,
                clock: passingClock
            ),
            now: passingClock.now
        )

        let passing = try await passingCoordinator.verify(
            runID: DeliveryDispatchFixture.runID,
            taskID: DeliveryDispatchFixture.taskA,
            kind: .test
        )
        let passingRun = try #require(passing.snapshot.runs.first)
        let passedFact = try #require(
            passingRun.evidenceFacts.last(where: {
                $0.attemptID == passing.attemptID
            })
        )

        #expect(passedFact.result == .passed)
        #expect(passedFact.source == .xcodeVerifier)
        #expect(passedFact.xcodeVerification == passing.record)
        #expect(DeliveryRunValidator.isValid(passingRun))

        let failingRunner = DeliveryXcodeVerifierTestSupport.stubRunner(
            commonDirectoryPath: identity.gitCommonDirectoryPath,
            branch: DeliveryGitTestRepository.shared.baseBranch,
            xcodeResult: DeliveryXcodeVerifierTestSupport.commandResult(
                exitCode: 65,
                stderr: "** TEST FAILED **\n"
            )
        )
        let failingClock = DeliveryDispatchTestClock(
            startingAt: passing.snapshot.savedAt.addingTimeInterval(10)
        )
        let failingCoordinator = DeliveryXcodeVerificationCoordinator(
            store: store,
            verifier: DeliveryXcodeVerifierTestSupport.verifier(
                runner: failingRunner,
                directoryURL: directoryURL,
                clock: failingClock
            ),
            now: failingClock.now
        )

        let failing = try await failingCoordinator.verify(
            runID: DeliveryDispatchFixture.runID,
            taskID: DeliveryDispatchFixture.taskA,
            kind: .test
        )
        let failingRun = try #require(failing.snapshot.runs.first)
        let failedFact = try #require(
            failingRun.evidenceFacts.last(where: {
                $0.attemptID == failing.attemptID
            })
        )

        #expect(failedFact.result == .failed)
        #expect(failedFact.supersedesFactID == passedFact.id)
        #expect(
            DeliveryDispatchStateReducer.state(for: failingRun)
                != .readyToMerge
        )
        #expect(
            DeliveryAttentionDashboard.make(for: failingRun).needsYou
                .contains(where: {
                    $0.taskID == DeliveryDispatchFixture.taskA
                })
        )
        #expect(DeliveryRunValidator.isValid(failingRun))
    }

    @Test("real Swift package sample produces an xcresult build record")
    func realSampleBuildProducesRecord() async throws {
        let sample = try DeliveryXcodeVerifierTestSupport.makeSwiftPackage()
        defer { try? FileManager.default.removeItem(at: sample.rootURL) }
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "openmac-verifier-real-\(UUID().uuidString)",
                isDirectory: true
            )
        defer { try? FileManager.default.removeItem(at: outputURL) }
        let verifier = XcodeVerifier(
            artifactRootURL: outputURL.appendingPathComponent(
                "artifacts",
                isDirectory: true
            ),
            derivedDataRootURL: outputURL.appendingPathComponent(
                "derived-data",
                isDirectory: true
            )
        )

        let record = try await verifier.verify(
            XcodeVerificationRequest(
                kind: .build,
                scheme: "VerifierSample",
                workspaceURL: sample.rootURL,
                expectedGitCommonDirectoryURL:
                    sample.commonDirectoryURL,
                expectedBranch: "main",
                containerKind: .swiftPackage,
                containerRelativePath: "Package.swift",
                timeout: 180
            )
        )
        let recordURL = outputURL.appendingPathComponent(
            "verification-record.json"
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        try encoder.encode(record).write(to: recordURL, options: .atomic)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let persistedRecord = try decoder.decode(
            XcodeVerificationRecord.self,
            from: Data(contentsOf: recordURL)
        )

        #expect(record.exitCode == 0)
        #expect(!record.timedOut)
        #expect(record.resultBundlePath != nil)
        #expect(record.summary.contains("passed"))
        #expect(persistedRecord.id == record.id)
        #expect(persistedRecord.command == record.command)
        #expect(persistedRecord.exitCode == record.exitCode)
        #expect(persistedRecord.resultBundlePath == record.resultBundlePath)
        #expect(
            abs(
                persistedRecord.startedAt.timeIntervalSince(
                    record.startedAt
                )
            ) < 0.001
        )
        #expect(
            abs(
                persistedRecord.endedAt.timeIntervalSince(
                    record.endedAt
                )
            ) < 0.001
        )
    }
}
