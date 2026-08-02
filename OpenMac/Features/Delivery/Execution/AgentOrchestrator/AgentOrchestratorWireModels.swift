import Foundation

nonisolated enum AgentOrchestratorWire {
    struct DaemonProbe: Decodable, Sendable {
        let status: String
        let service: String
        let pid: Int
    }

    struct APIError: Decodable, Sendable {
        let error: String
        let code: String
        let message: String
        let requestId: String?
    }

    struct ProjectList: Decodable, Sendable {
        let projects: [ProjectSummary]
    }

    struct ProjectEnvelope: Decodable, Sendable {
        let status: String
        let project: ProjectDetail
    }

    struct ProjectDetail: Decodable, Sendable {
        let id: String
        let name: String
        let path: String
        let kind: String
        let defaultBranch: String?
        let resolveError: String?
    }

    struct ProjectSummary: Decodable, Sendable {
        let id: String
        let name: String
        let path: String
        let kind: String
        let sessionPrefix: String
        let resolveError: String?
    }

    struct SessionList: Decodable, Sendable {
        let sessions: [Session]
    }

    struct SessionEnvelope: Decodable, Sendable {
        let session: Session
    }

    struct SpawnSessionResponse: Decodable, Sendable {
        let session: Session
        let promptBytes: Int
        let systemPromptBytes: Int
    }

    struct SpawnSessionRequest: Encodable, Sendable {
        let projectId: String
        let kind: String
        let harness: String
        let branch: String
        let prompt: String
        let displayName: String
    }

    struct Session: Codable, Sendable {
        let id: String
        let projectId: String
        let kind: String
        let harness: String?
        let displayName: String?
        let activity: Activity
        let isTerminated: Bool
        let createdAt: String
        let updatedAt: String
        let status: String
        let scmStatus: String?
        let branch: String?
        let prs: [PullRequest]
    }

    struct Activity: Codable, Sendable {
        let state: String
        let lastActivityAt: String
    }

    struct PullRequest: Codable, Sendable {
        let url: String
        let number: Int
        let state: String
        let ci: String
        let review: String
        let mergeability: String
        let reviewComments: Bool
        let updatedAt: String
    }

    struct WorkspaceFiles: Codable, Sendable {
        let sessionId: String
        let files: [WorkspaceFile]
        let truncated: Bool
    }

    struct OpenShellTerminalRequest: Encodable, Sendable {
        let projectId: String
        let sessionId: String
    }

    struct ShellTerminalEnvelope: Decodable, Sendable {
        let shellTerminal: ShellTerminal
    }

    struct ShellTerminal: Decodable, Sendable {
        let handleId: String
        let projectId: String?
        let sessionId: String?
        let workingDir: String
    }

    struct WorkspaceFile: Codable, Sendable {
        let path: String
        let status: String
        let additions: Int
        let deletions: Int
        let size: Int64
        let binary: Bool
    }

    struct KillSessionResponse: Decodable, Sendable {
        let ok: Bool
        let sessionId: String
        let freed: Bool?
    }

    struct FactCursor: Codable, Sendable {
        let executionID: String
        let nextSequence: UInt64
        let snapshotFingerprint: String?

        init(
            executionID: String,
            nextSequence: UInt64,
            snapshotFingerprint: String? = nil
        ) {
            self.executionID = executionID
            self.nextSequence = nextSequence
            self.snapshotFingerprint = snapshotFingerprint
        }
    }
}
