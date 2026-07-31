import Darwin
import Foundation

nonisolated struct AgentOrchestratorDaemonEndpoint:
    Equatable,
    Sendable
{
    let baseURL: URL
    let pid: Int
    let startedAt: Date
    let runFileURL: URL
}

nonisolated enum AgentOrchestratorDaemonDiscoveryError:
    Error,
    Equatable,
    LocalizedError,
    Sendable
{
    case unsafeRunFile(URL)
    case oversizedRunFile(Int64)
    case malformedRunFile
    case invalidPort(Int)
    case invalidPID(Int)
    case staleProcess(Int)

    nonisolated var errorDescription: String? {
        switch self {
        case let .unsafeRunFile(url):
            return "AO discovery refused the unsafe run file at \(url.path). Enter the loopback URL manually."
        case let .oversizedRunFile(byteCount):
            return "AO discovery refused an oversized run file (\(byteCount) bytes). Enter the loopback URL manually."
        case .malformedRunFile:
            return "AO discovery could not read a valid running.json. Start AO again or enter its loopback URL manually."
        case let .invalidPort(port):
            return "AO discovery found an invalid daemon port (\(port))."
        case let .invalidPID(pid):
            return "AO discovery found an invalid daemon process ID (\(pid))."
        case let .staleProcess(pid):
            return "AO discovery found a stale daemon process ID (\(pid)). Start AO again or connect manually."
        }
    }
}

nonisolated struct AgentOrchestratorDaemonDiscovery: Sendable {
    typealias ProcessIsAlive = @Sendable (Int32) -> Bool

    static let capturedUpstreamRevision =
        "b58bae51bac08c9e48bded4c636e504863a93c21"
    static let maximumRunFileSize: Int64 = 64 * 1_024

    let runFileURL: URL
    private let processIsAlive: ProcessIsAlive

    nonisolated init(
        runFileURL: URL = FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent(".ao", isDirectory: true)
            .appendingPathComponent("running.json"),
        processIsAlive: @escaping ProcessIsAlive = Self.liveProcessExists
    ) {
        self.runFileURL = runFileURL
        self.processIsAlive = processIsAlive
    }

    nonisolated func discover()
        throws -> AgentOrchestratorDaemonEndpoint?
    {
        let descriptor = Darwin.open(
            runFileURL.path,
            O_RDONLY | O_NOFOLLOW | O_CLOEXEC
        )
        guard descriptor >= 0 else {
            if errno == ENOENT {
                return nil
            }
            throw AgentOrchestratorDaemonDiscoveryError
                .unsafeRunFile(runFileURL)
        }
        defer { Darwin.close(descriptor) }

        var fileStatus = stat()
        guard Darwin.fstat(descriptor, &fileStatus) == 0,
              fileStatus.st_mode & S_IFMT == S_IFREG,
              fileStatus.st_uid == Darwin.getuid(),
              fileStatus.st_mode & (S_IWGRP | S_IWOTH) == 0 else {
            throw AgentOrchestratorDaemonDiscoveryError
                .unsafeRunFile(runFileURL)
        }
        guard fileStatus.st_size >= 0,
              fileStatus.st_size <= Self.maximumRunFileSize else {
            throw AgentOrchestratorDaemonDiscoveryError
                .oversizedRunFile(fileStatus.st_size)
        }

        let handle = FileHandle(
            fileDescriptor: descriptor,
            closeOnDealloc: false
        )
        guard let data = try handle.readToEnd(),
              !data.isEmpty,
              let payload = try? JSONDecoder().decode(
                  RunFile.self,
                  from: data
              ) else {
            throw AgentOrchestratorDaemonDiscoveryError
                .malformedRunFile
        }
        guard payload.pid > 0,
              payload.pid <= Int(Int32.max) else {
            throw AgentOrchestratorDaemonDiscoveryError
                .invalidPID(payload.pid)
        }
        guard (1 ... 65_535).contains(payload.port) else {
            throw AgentOrchestratorDaemonDiscoveryError
                .invalidPort(payload.port)
        }
        guard let startedAt = Self.parseDate(payload.startedAt) else {
            throw AgentOrchestratorDaemonDiscoveryError
                .malformedRunFile
        }
        guard processIsAlive(Int32(payload.pid)) else {
            throw AgentOrchestratorDaemonDiscoveryError
                .staleProcess(payload.pid)
        }
        guard let baseURL = URL(
            string: "http://127.0.0.1:\(payload.port)"
        ) else {
            throw AgentOrchestratorDaemonDiscoveryError
                .invalidPort(payload.port)
        }

        return AgentOrchestratorDaemonEndpoint(
            baseURL: baseURL,
            pid: payload.pid,
            startedAt: startedAt,
            runFileURL: runFileURL
        )
    }

    private struct RunFile: Decodable {
        let pid: Int
        let port: Int
        let startedAt: String
    }

    private nonisolated static func liveProcessExists(
        _ pid: Int32
    ) -> Bool {
        Darwin.kill(pid, 0) == 0 || errno == EPERM
    }

    private nonisolated static func parseDate(_ raw: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [
            .withInternetDateTime,
            .withFractionalSeconds
        ]
        if let date = fractional.date(from: raw) {
            return date
        }
        return ISO8601DateFormatter().date(from: raw)
    }
}
