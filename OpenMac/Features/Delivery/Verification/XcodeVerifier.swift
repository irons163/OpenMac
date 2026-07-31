import Foundation

nonisolated struct XcodeCommandInvocation: Equatable, Sendable {
    let executableURL: URL
    let arguments: [String]
    let workingDirectoryURL: URL
    let timeout: TimeInterval

    nonisolated init(
        executableURL: URL,
        arguments: [String],
        workingDirectoryURL: URL,
        timeout: TimeInterval
    ) {
        self.executableURL = executableURL
        self.arguments = arguments
        self.workingDirectoryURL = workingDirectoryURL
        self.timeout = timeout
    }
}

nonisolated struct XcodeCommandResult: Equatable, Sendable {
    let exitCode: Int32
    let stdout: String
    let stderr: String
    let timedOut: Bool

    nonisolated init(
        exitCode: Int32,
        stdout: String,
        stderr: String,
        timedOut: Bool
    ) {
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
        self.timedOut = timedOut
    }
}

nonisolated protocol XcodeCommandRunning: Sendable {
    func run(_ invocation: XcodeCommandInvocation) async throws
        -> XcodeCommandResult
}

nonisolated private final class XcodeCommandOutputBuffer:
    @unchecked Sendable
{
    private let lock = NSLock()
    private var data = Data()

    func append(_ chunk: Data) {
        lock.lock()
        data.append(chunk)
        lock.unlock()
    }

    func value() -> Data {
        lock.lock()
        defer { lock.unlock() }
        return data
    }
}

nonisolated struct FoundationXcodeCommandRunner: XcodeCommandRunning {
    func run(
        _ invocation: XcodeCommandInvocation
    ) async throws -> XcodeCommandResult {
        try await Task.detached {
            try Task.checkCancellation()
            let result = try Self.runSynchronously(invocation)
            try Task.checkCancellation()
            return result
        }.value
    }

    nonisolated private static func runSynchronously(
        _ invocation: XcodeCommandInvocation
    ) throws -> XcodeCommandResult {
        let process = Process()
        process.executableURL = invocation.executableURL
        process.arguments = invocation.arguments
        process.currentDirectoryURL = invocation.workingDirectoryURL
        process.environment = environment()

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        let stdoutBuffer = XcodeCommandOutputBuffer()
        let stderrBuffer = XcodeCommandOutputBuffer()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else {
                handle.readabilityHandler = nil
                return
            }
            stdoutBuffer.append(chunk)
        }
        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else {
                handle.readabilityHandler = nil
                return
            }
            stderrBuffer.append(chunk)
        }

        let completion = DispatchGroup()
        completion.enter()
        process.terminationHandler = { _ in completion.leave() }
        try process.run()
        let timedOut = completion.wait(
            timeout: .now() + max(1, invocation.timeout)
        ) == .timedOut
        if timedOut {
            process.terminate()
            _ = completion.wait(timeout: .now() + 5)
        }

        stdoutPipe.fileHandleForReading.readabilityHandler = nil
        stderrPipe.fileHandleForReading.readabilityHandler = nil
        stdoutBuffer.append(
            stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        )
        stderrBuffer.append(
            stderrPipe.fileHandleForReading.readDataToEndOfFile()
        )
        return XcodeCommandResult(
            exitCode: timedOut ? -9 : process.terminationStatus,
            stdout: String(
                data: stdoutBuffer.value(),
                encoding: .utf8
            ) ?? "",
            stderr: String(
                data: stderrBuffer.value(),
                encoding: .utf8
            ) ?? "",
            timedOut: timedOut
        )
    }

    nonisolated private static func environment() -> [String: String] {
        let source = ProcessInfo.processInfo.environment
        let allowedKeys = [
            "DEVELOPER_DIR",
            "HOME",
            "LANG",
            "LC_ALL",
            "SDKROOT",
            "TMPDIR"
        ]
        var result = Dictionary(
            uniqueKeysWithValues: allowedKeys.compactMap { key in
                source[key].map { (key, $0) }
            }
        )
        result["PATH"] = "/usr/bin:/bin:/usr/sbin:/sbin"
        return result
    }
}

nonisolated struct XcodeVerificationRequest: Equatable, Sendable {
    let recordID: UUID
    let kind: XcodeVerificationKind
    let scheme: String
    let workspaceURL: URL
    let expectedGitCommonDirectoryURL: URL
    let expectedBranch: String
    let containerKind: DeliveryContainerKind
    let containerRelativePath: String
    let timeout: TimeInterval

    nonisolated init(
        recordID: UUID = UUID(),
        kind: XcodeVerificationKind,
        scheme: String,
        workspaceURL: URL,
        expectedGitCommonDirectoryURL: URL,
        expectedBranch: String,
        containerKind: DeliveryContainerKind,
        containerRelativePath: String,
        timeout: TimeInterval = 20 * 60
    ) {
        self.recordID = recordID
        self.kind = kind
        self.scheme = scheme
        self.workspaceURL = workspaceURL
        self.expectedGitCommonDirectoryURL =
            expectedGitCommonDirectoryURL
        self.expectedBranch = expectedBranch
        self.containerKind = containerKind
        self.containerRelativePath = containerRelativePath
        self.timeout = timeout
    }
}

nonisolated enum XcodeVerifierError:
    Error,
    Equatable,
    LocalizedError,
    Sendable
{
    case invalidWorkspace(String)
    case gitIdentityUnavailable
    case gitCommonDirectoryMismatch(expected: String, actual: String)
    case branchMismatch(expected: String, actual: String)
    case invalidContainer(String)
    case invalidScheme

    nonisolated var errorDescription: String? {
        switch self {
        case let .invalidWorkspace(path):
            return "The verification workspace is unavailable at \(path)."
        case .gitIdentityUnavailable:
            return "The verification workspace Git identity is unavailable."
        case let .gitCommonDirectoryMismatch(expected, actual):
            return "The verification workspace belongs to Git common directory \(actual), not the approved \(expected)."
        case let .branchMismatch(expected, actual):
            return "The verification workspace is on branch \(actual), not the backend-confirmed \(expected)."
        case let .invalidContainer(path):
            return "The approved Xcode container is unavailable in the verification workspace at \(path)."
        case .invalidScheme:
            return "A non-empty approved Xcode scheme is required."
        }
    }
}

actor XcodeVerifier {
    private let runner: any XcodeCommandRunning
    private let artifactRootURL: URL
    private let derivedDataRootURL: URL
    private let now: @Sendable () -> Date

    init(
        runner: any XcodeCommandRunning = FoundationXcodeCommandRunner(),
        artifactRootURL: URL = XcodeVerifier.defaultArtifactRootURL,
        derivedDataRootURL: URL = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "OpenMac-XcodeVerifier-DerivedData",
                isDirectory: true
            ),
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.runner = runner
        self.artifactRootURL = artifactRootURL
        self.derivedDataRootURL = derivedDataRootURL
        self.now = now
    }

    nonisolated static var defaultArtifactRootURL: URL {
        let base = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory
        return base
            .appendingPathComponent("OpenMac", isDirectory: true)
            .appendingPathComponent("v2", isDirectory: true)
            .appendingPathComponent(
                "verification-artifacts",
                isDirectory: true
            )
    }

    func verify(
        _ request: XcodeVerificationRequest
    ) async throws -> XcodeVerificationRecord {
        let context = try await validatedContext(for: request)
        let scheme = request.scheme.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !scheme.isEmpty else {
            throw XcodeVerifierError.invalidScheme
        }

        let recordDirectory = artifactRootURL.appendingPathComponent(
            request.recordID.uuidString.lowercased(),
            isDirectory: true
        )
        let resultBundleURL = recordDirectory.appendingPathComponent(
            request.kind == .build ? "Build.xcresult" : "Test.xcresult",
            isDirectory: true
        )
        let derivedDataURL = derivedDataRootURL.appendingPathComponent(
            request.recordID.uuidString.lowercased(),
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: recordDirectory,
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: derivedDataRootURL,
            withIntermediateDirectories: true
        )
        defer {
            try? FileManager.default.removeItem(at: derivedDataURL)
        }

        let arguments = xcodebuildArguments(
            request: request,
            context: context,
            scheme: scheme,
            resultBundleURL: resultBundleURL,
            derivedDataURL: derivedDataURL
        )
        let invocation = XcodeCommandInvocation(
            executableURL: URL(fileURLWithPath: "/usr/bin/xcrun"),
            arguments: arguments,
            workingDirectoryURL: context.workspaceURL,
            timeout: request.timeout
        )
        let startedAt = now()
        let result = try await runner.run(invocation)
        let endedAt = max(now(), startedAt)
        let summary = Self.summary(
            kind: request.kind,
            result: result
        )
        let persistedBundlePath = FileManager.default.fileExists(
            atPath: resultBundleURL.path
        ) ? resultBundleURL.path : nil

        return XcodeVerificationRecord(
            id: request.recordID,
            kind: request.kind,
            scheme: scheme,
            command: Self.displayCommand(invocation),
            workingDirectoryPath: context.workspaceURL.path,
            exitCode: result.exitCode,
            timedOut: result.timedOut,
            summary: summary,
            resultBundlePath: persistedBundlePath,
            startedAt: startedAt,
            endedAt: endedAt
        )
    }

    private struct ValidatedContext: Sendable {
        let workspaceURL: URL
        let containerURL: URL
    }

    private func validatedContext(
        for request: XcodeVerificationRequest
    ) async throws -> ValidatedContext {
        let workspaceURL = request.workspaceURL
            .standardizedFileURL
            .resolvingSymlinksInPath()
        var isDirectory: ObjCBool = false
        guard workspaceURL.isFileURL,
              FileManager.default.fileExists(
                  atPath: workspaceURL.path,
                  isDirectory: &isDirectory
              ),
              isDirectory.boolValue else {
            throw XcodeVerifierError.invalidWorkspace(workspaceURL.path)
        }

        let commonDirectory = try await gitValue(
            arguments: [
                "rev-parse",
                "--path-format=absolute",
                "--git-common-dir"
            ],
            workspaceURL: workspaceURL
        )
        let actualCommonURL = URL(fileURLWithPath: commonDirectory)
            .standardizedFileURL
            .resolvingSymlinksInPath()
        let expectedCommonURL = request.expectedGitCommonDirectoryURL
            .standardizedFileURL
            .resolvingSymlinksInPath()
        guard actualCommonURL.path == expectedCommonURL.path else {
            throw XcodeVerifierError.gitCommonDirectoryMismatch(
                expected: expectedCommonURL.path,
                actual: actualCommonURL.path
            )
        }

        let actualBranch = try await gitValue(
            arguments: ["rev-parse", "--abbrev-ref", "HEAD"],
            workspaceURL: workspaceURL
        )
        guard actualBranch == request.expectedBranch else {
            throw XcodeVerifierError.branchMismatch(
                expected: request.expectedBranch,
                actual: actualBranch
            )
        }

        let containerURL = workspaceURL.appendingPathComponent(
            request.containerRelativePath
        ).standardizedFileURL
        let workspacePrefix = workspaceURL.path.hasSuffix("/")
            ? workspaceURL.path
            : workspaceURL.path + "/"
        guard containerURL.path.hasPrefix(workspacePrefix),
              FileManager.default.fileExists(atPath: containerURL.path) else {
            throw XcodeVerifierError.invalidContainer(containerURL.path)
        }
        return ValidatedContext(
            workspaceURL: workspaceURL,
            containerURL: containerURL
        )
    }

    private func gitValue(
        arguments: [String],
        workspaceURL: URL
    ) async throws -> String {
        let result = try await runner.run(
            XcodeCommandInvocation(
                executableURL: URL(fileURLWithPath: "/usr/bin/git"),
                arguments: ["-C", workspaceURL.path] + arguments,
                workingDirectoryURL: workspaceURL,
                timeout: 15
            )
        )
        let output = result.stdout.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard result.exitCode == 0,
              !result.timedOut,
              !output.isEmpty else {
            throw XcodeVerifierError.gitIdentityUnavailable
        }
        return output
    }

    private func xcodebuildArguments(
        request: XcodeVerificationRequest,
        context: ValidatedContext,
        scheme: String,
        resultBundleURL: URL,
        derivedDataURL: URL
    ) -> [String] {
        var arguments = ["xcodebuild"]
        switch request.containerKind {
        case .xcodeProject:
            arguments += ["-project", context.containerURL.path]
        case .xcodeWorkspace:
            arguments += ["-workspace", context.containerURL.path]
        case .swiftPackage:
            break
        }
        arguments += [
            "-scheme", scheme,
            "-configuration", "Debug",
            "-destination", "platform=macOS",
            "-derivedDataPath", derivedDataURL.path,
            "-resultBundlePath", resultBundleURL.path,
            request.kind == .build ? "build" : "test"
        ]
        return arguments
    }

    nonisolated private static func displayCommand(
        _ invocation: XcodeCommandInvocation
    ) -> String {
        ([invocation.executableURL.path] + invocation.arguments)
            .map(shellQuoted)
            .joined(separator: " ")
    }

    nonisolated private static func shellQuoted(_ value: String) -> String {
        let safe = CharacterSet(
            charactersIn:
                "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_./:=+-"
        )
        if value.unicodeScalars.allSatisfy({ safe.contains($0) }) {
            return value
        }
        return "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    nonisolated private static func summary(
        kind: XcodeVerificationKind,
        result: XcodeCommandResult
    ) -> String {
        let merged = [result.stdout, result.stderr]
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
        let tail = merged
            .split(whereSeparator: \.isNewline)
            .map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .filter { !$0.isEmpty }
            .suffix(12)
            .joined(separator: "\n")
        let state: String
        if result.timedOut {
            state = "timed out"
        } else {
            state = result.exitCode == 0 ? "passed" : "failed"
        }
        let heading =
            "Xcode \(kind.rawValue) \(state) (exit \(result.exitCode))."
        guard !tail.isEmpty else { return heading }
        return String((heading + "\n" + tail).prefix(4_096))
    }
}
