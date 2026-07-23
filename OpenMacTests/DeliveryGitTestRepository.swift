import Foundation

enum DeliveryGitTestRepository {
    struct Repository: Sendable {
        let rootURL: URL
        let baseBranch: String
        let containerRelativePath: String

        func commitFile(
            named name: String,
            contents: String
        ) throws {
            try Data(contents.utf8).write(
                to: rootURL.appendingPathComponent(name),
                options: .atomic
            )
            try DeliveryGitTestRepository.runGit(
                ["add", "--", name],
                in: rootURL
            )
            try DeliveryGitTestRepository.runGit(
                ["commit", "-m", "Update \(name)"],
                in: rootURL
            )
        }
    }

    static let shared: Repository = {
        do {
            return try make(label: "shared")
        } catch {
            preconditionFailure("Unable to create Git test repository: \(error)")
        }
    }()

    static func make(label: String) throws -> Repository {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "openmac-\(label)-git-\(UUID().uuidString)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: rootURL,
            withIntermediateDirectories: true
        )
        let sourceProjectURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("OpenMac.xcodeproj", isDirectory: true)
        try FileManager.default.copyItem(
            at: sourceProjectURL,
            to: rootURL.appendingPathComponent(
                "OpenMac.xcodeproj",
                isDirectory: true
            )
        )
        try Data("fixture\n".utf8).write(
            to: rootURL.appendingPathComponent("README.md"),
            options: .atomic
        )
        try runGit(["init"], in: rootURL)
        try runGit(
            ["symbolic-ref", "HEAD", "refs/heads/main"],
            in: rootURL
        )
        try runGit(
            ["config", "user.email", "openmac-tests@example.invalid"],
            in: rootURL
        )
        try runGit(
            ["config", "user.name", "OpenMac Tests"],
            in: rootURL
        )
        try runGit(
            ["add", "--", "README.md", "OpenMac.xcodeproj"],
            in: rootURL
        )
        try runGit(["commit", "-m", "Initial fixture"], in: rootURL)
        return Repository(
            rootURL: rootURL,
            baseBranch: "main",
            containerRelativePath: "OpenMac.xcodeproj"
        )
    }

    @discardableResult
    static func runGit(
        _ arguments: [String],
        in rootURL: URL
    ) throws -> String {
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", rootURL.path] + arguments
        var environment = ProcessInfo.processInfo.environment
        environment["GIT_CONFIG_NOSYSTEM"] = "1"
        environment["GIT_CONFIG_GLOBAL"] = "/dev/null"
        environment["GIT_TERMINAL_PROMPT"] = "0"
        environment["GIT_CONFIG_COUNT"] = "2"
        environment["GIT_CONFIG_KEY_0"] = "commit.gpgSign"
        environment["GIT_CONFIG_VALUE_0"] = "false"
        environment["GIT_CONFIG_KEY_1"] = "core.hooksPath"
        environment["GIT_CONFIG_VALUE_1"] = "/dev/null"
        process.environment = environment
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        try process.run()
        process.waitUntilExit()
        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
        guard process.terminationStatus == 0 else {
            let reason = String(data: errorData, encoding: .utf8) ?? "unknown"
            throw NSError(
                domain: "DeliveryGitTestRepository",
                code: Int(process.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: reason]
            )
        }
        return (String(data: outputData, encoding: .utf8) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
