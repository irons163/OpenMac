import Foundation

struct GitHubPRFlowRequest: Equatable {
    var repositoryPath: String
    var boardName: String
    var baseBranch: String
    var remoteName: String
    var branchPrefix: String
    var commitMessage: String
    var prTitle: String
    var prBody: String
}

struct GitHubPRFlowResult: Equatable {
    var succeeded: Bool
    var branchName: String
    var pullRequestURL: String?
    var message: String
    var debugLog: String
}

enum GitHubPRFlowUseCase {
    typealias CommandRunner = (
        _ executablePath: String,
        _ arguments: [String],
        _ workingDirectoryPath: String
    ) throws -> (code: Int32, output: String)

    nonisolated static func run(
        request: GitHubPRFlowRequest,
        now: Date = Date(),
        commandRunner: CommandRunner = runSystemCommand
    ) -> GitHubPRFlowResult {
        let repositoryPath = request.repositoryPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !repositoryPath.isEmpty else {
            return GitHubPRFlowResult(
                succeeded: false,
                branchName: "",
                pullRequestURL: nil,
                message: "Repository path is required",
                debugLog: ""
            )
        }

        let branchName = generatedBranchName(
            boardName: request.boardName,
            branchPrefix: request.branchPrefix,
            date: now
        )
        let trimmedBaseBranch = normalizedValue(request.baseBranch, fallback: "main")
        let trimmedRemoteName = normalizedValue(request.remoteName, fallback: "origin")
        let trimmedCommitMessage = normalizedValue(request.commitMessage, fallback: "chore: update board")
        let trimmedPRTitle = normalizedValue(request.prTitle, fallback: "[OpenMac] Board update")
        let trimmedPRBody = request.prBody.trimmingCharacters(in: .whitespacesAndNewlines)

        var debugLines: [String] = []

        do {
            let repoCheck = try run(
                executablePath: "/usr/bin/env",
                arguments: ["git", "rev-parse", "--is-inside-work-tree"],
                workingDirectoryPath: repositoryPath,
                commandRunner: commandRunner
            )
            debugLines.append(repoCheck.log)
            guard repoCheck.code == 0 else {
                return failure(
                    branchName: "",
                    message: "Folder is not a git repository",
                    debugLines: debugLines
                )
            }

            let branchCreate = try run(
                executablePath: "/usr/bin/env",
                arguments: ["git", "checkout", "-b", branchName],
                workingDirectoryPath: repositoryPath,
                commandRunner: commandRunner
            )
            debugLines.append(branchCreate.log)
            guard branchCreate.code == 0 else {
                return failure(
                    branchName: branchName,
                    message: "Failed to create git branch",
                    debugLines: debugLines
                )
            }

            let stageAll = try run(
                executablePath: "/usr/bin/env",
                arguments: ["git", "add", "-A"],
                workingDirectoryPath: repositoryPath,
                commandRunner: commandRunner
            )
            debugLines.append(stageAll.log)
            guard stageAll.code == 0 else {
                return failure(
                    branchName: branchName,
                    message: "Failed to stage changes",
                    debugLines: debugLines
                )
            }

            let stagedDiff = try run(
                executablePath: "/usr/bin/env",
                arguments: ["git", "diff", "--cached", "--quiet"],
                workingDirectoryPath: repositoryPath,
                commandRunner: commandRunner
            )
            debugLines.append(stagedDiff.log)
            guard stagedDiff.code != 0 else {
                return failure(
                    branchName: branchName,
                    message: "No staged changes to commit",
                    debugLines: debugLines
                )
            }

            let commit = try run(
                executablePath: "/usr/bin/env",
                arguments: ["git", "commit", "-m", trimmedCommitMessage],
                workingDirectoryPath: repositoryPath,
                commandRunner: commandRunner
            )
            debugLines.append(commit.log)
            guard commit.code == 0 else {
                return failure(
                    branchName: branchName,
                    message: "Failed to create git commit",
                    debugLines: debugLines
                )
            }

            let push = try run(
                executablePath: "/usr/bin/env",
                arguments: ["git", "push", "-u", trimmedRemoteName, branchName],
                workingDirectoryPath: repositoryPath,
                commandRunner: commandRunner
            )
            debugLines.append(push.log)
            guard push.code == 0 else {
                return failure(
                    branchName: branchName,
                    message: "Failed to push branch",
                    debugLines: debugLines
                )
            }

            let createPR = try run(
                executablePath: "/usr/bin/env",
                arguments: [
                    "gh",
                    "pr",
                    "create",
                    "--base", trimmedBaseBranch,
                    "--head", branchName,
                    "--title", trimmedPRTitle,
                    "--body", trimmedPRBody
                ],
                workingDirectoryPath: repositoryPath,
                commandRunner: commandRunner
            )
            debugLines.append(createPR.log)
            guard createPR.code == 0 else {
                let fallbackCommand = "gh pr create --base \(trimmedBaseBranch) --head \(branchName) --title \"\(trimmedPRTitle)\" --body-file <file>"
                let hasMissingGH = createPR.output.localizedCaseInsensitiveContains("command not found")
                    || createPR.output.localizedCaseInsensitiveContains("no such file")
                let message = hasMissingGH
                    ? "GitHub CLI not found. Install gh, then run manually: \(fallbackCommand)"
                    : "Failed to create GitHub pull request"
                return failure(
                    branchName: branchName,
                    message: message,
                    debugLines: debugLines
                )
            }

            let prURL = pullRequestURL(from: createPR.output)
            let successMessage: String
            if let prURL {
                successMessage = "GitHub PR created: \(prURL)"
            } else {
                successMessage = "GitHub PR created for branch \(branchName)"
            }
            return GitHubPRFlowResult(
                succeeded: true,
                branchName: branchName,
                pullRequestURL: prURL,
                message: successMessage,
                debugLog: debugLines.joined(separator: "\n\n")
            )
        } catch {
            return failure(
                branchName: branchName,
                message: "GitHub PR flow failed: \(error.localizedDescription)",
                debugLines: debugLines
            )
        }
    }

    nonisolated static func generatedBranchName(
        boardName: String,
        branchPrefix: String,
        date: Date
    ) -> String {
        let trimmedPrefix = normalizedValue(branchPrefix, fallback: "openmac")
        let slug = slugified(boardName, fallback: "board")
        return "\(trimmedPrefix)/\(slug)-\(Self.branchTimestampFormatter.string(from: date))"
    }

    nonisolated static func pullRequestURL(from output: String) -> String? {
        let pattern = #"https://github\.com/[^\s]+/pull/\d+"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []),
              let match = regex.firstMatch(
                  in: output,
                  options: [],
                  range: NSRange(output.startIndex..<output.endIndex, in: output)
              ),
              let range = Range(match.range, in: output) else {
            return nil
        }
        return String(output[range])
    }

    nonisolated static func runSystemCommand(
        executablePath: String,
        arguments: [String],
        workingDirectoryPath: String
    ) throws -> (code: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        process.currentDirectoryURL = URL(fileURLWithPath: workingDirectoryPath, isDirectory: true)

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()
        process.waitUntilExit()

        let stdoutData = stdout.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderr.fileHandleForReading.readDataToEndOfFile()
        let mergedData = stdoutData + stderrData
        let output = String(data: mergedData, encoding: .utf8) ?? ""
        return (process.terminationStatus, output.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    nonisolated private static func run(
        executablePath: String,
        arguments: [String],
        workingDirectoryPath: String,
        commandRunner: CommandRunner
    ) throws -> (code: Int32, output: String, log: String) {
        let result = try commandRunner(executablePath, arguments, workingDirectoryPath)
        let command = ([executablePath] + arguments).joined(separator: " ")
        let log = """
        $ \(command)
        exit=\(result.code)
        \(result.output)
        """
        return (result.code, result.output, log)
    }

    nonisolated private static func normalizedValue(_ value: String, fallback: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }

    nonisolated private static func slugified(_ rawValue: String, fallback: String) -> String {
        let lowered = rawValue.lowercased()
        let transformed = lowered.map { character -> Character in
            if character.isLetter || character.isNumber {
                return character
            }
            return "-"
        }
        let slug = String(transformed)
            .replacingOccurrences(of: "-+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return slug.isEmpty ? fallback : slug
    }

    nonisolated private static func failure(
        branchName: String,
        message: String,
        debugLines: [String]
    ) -> GitHubPRFlowResult {
        GitHubPRFlowResult(
            succeeded: false,
            branchName: branchName,
            pullRequestURL: nil,
            message: message,
            debugLog: debugLines.joined(separator: "\n\n")
        )
    }

    nonisolated private static let branchTimestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter
    }()
}
