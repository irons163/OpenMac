import Foundation

nonisolated enum DeliveryFixtureReviewBootstrapError:
    Error,
    Equatable,
    LocalizedError,
    Sendable
{
    case repositoryDirectoryRequired
    case gitMetadataMissing
    case invalidGitMetadata
    case detachedHead
    case currentBranchMissing(String)
    case supportedContainerMissing
    case ambiguousContainers([String])
    case planningInventoryUnavailable(String)
    case storeRevisionChanged(expected: Int?, current: Int?)

    nonisolated var errorDescription: String? {
        switch self {
        case .repositoryDirectoryRequired:
            return "Choose a repository directory."
        case .gitMetadataMissing:
            return "The selected directory is not a Git worktree root."
        case .invalidGitMetadata:
            return "The selected repository has invalid or unsupported Git metadata."
        case .detachedHead:
            return "Fixture review requires a checked-out local branch, not detached HEAD."
        case let .currentBranchMissing(branch):
            return "The checked-out branch \(branch) does not resolve to an existing commit."
        case .supportedContainerMissing:
            return "The repository root needs one Xcode project, workspace, or Package.swift."
        case let .ambiguousContainers(names):
            return "Choose a repository with one top-level Apple container; found \(names.joined(separator: ", "))."
        case let .planningInventoryUnavailable(container):
            return "Could not read targets or schemes from \(container). Check the project or package locally and try again."
        case let .storeRevisionChanged(expected, current):
            let expectedValue = expected.map(String.init) ?? "none"
            let currentValue = current.map(String.init) ?? "none"
            return "Delivery store revision changed from \(expectedValue) to \(currentValue)."
        }
    }
}

nonisolated protocol DeliveryFixtureReviewPersisting: DeliveryRunStoring {
    func createGeneratedFixtureReviewRun(
        _ result: DeliveryPlanGenerationResult,
        request: DeliveryPlanGenerationRequest,
        expectedStoreRevision: Int?
    ) async throws -> DeliveryRunSnapshot
}

nonisolated struct DeliveryFixtureReviewBootstrapper: Sendable {
    private let persistence: any DeliveryFixtureReviewPersisting
    private let planner: any DeliveryPlanning
    private let now: @Sendable () -> Date

    nonisolated init(
        persistence: any DeliveryFixtureReviewPersisting,
        planner: any DeliveryPlanning = DeterministicFixtureDeliveryPlanner(),
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.persistence = persistence
        self.planner = planner
        self.now = now
    }

    nonisolated func createFixtureReview(
        repositoryRootURL: URL
    ) async throws -> DeliveryRunSnapshot {
        let repository = try DeliveryFixtureReviewRepository.resolve(
            repositoryRootURL
        )
        let existingSnapshot = try await persistence.load()
        let generatedAt = now()
        let brief = FeatureBrief(
            title: "Fixture review for \(repository.displayName)",
            body: """
            Create a deterministic delivery-plan fixture for \(repository.displayName). \
            This review is local, editable, and must not dispatch any execution sessions.
            """,
            repository: DeliveryRepositoryReference(
                rootPath: repository.context.repositoryRootPath,
                baseBranch: repository.baseBranch,
                xcodeContainerRelativePath: repository.context.containerRelativePath
            ),
            createdAt: generatedAt
        )
        let repositoryIdentity = try repository.context.identitySnapshot(
            validatingBaseBranch: repository.baseBranch
        )
        let request = DeliveryPlanGenerationRequest(
            baseStoreRevision: existingSnapshot?.storeRevision ?? 0,
            brief: brief,
            repositoryContext: repository.context,
            repositoryIdentity: repositoryIdentity,
            generatedAt: generatedAt
        )
        let result = try await planner.generate(request)
        try Task.checkCancellation()
        return try await persistence.createGeneratedFixtureReviewRun(
            result,
            request: request,
            expectedStoreRevision: existingSnapshot?.storeRevision
        )
    }
}

nonisolated private struct DeliveryFixtureReviewRepository {
    let displayName: String
    let baseBranch: String
    let context: DeliveryPlanningRepositoryContext

    nonisolated static func resolve(
        _ selectedURL: URL
    ) throws -> DeliveryFixtureReviewRepository {
        let rootURL = selectedURL
            .standardizedFileURL
            .resolvingSymlinksInPath()
            .standardizedFileURL
        var isDirectory = ObjCBool(false)
        guard FileManager.default.fileExists(
            atPath: rootURL.path,
            isDirectory: &isDirectory
        ), isDirectory.boolValue else {
            throw DeliveryFixtureReviewBootstrapError.repositoryDirectoryRequired
        }

        let baseBranch = try currentBranch(in: rootURL)
        let container = try supportedContainer(in: rootURL)
        let displayName = rootURL.lastPathComponent.isEmpty
            ? "Repository"
            : rootURL.lastPathComponent
        let inventory = discoverInventory(
            repositoryRootURL: rootURL,
            container: container
        )
        guard !inventory.targets.isEmpty || !inventory.schemes.isEmpty else {
            throw DeliveryFixtureReviewBootstrapError
                .planningInventoryUnavailable(container.url.lastPathComponent)
        }
        let context = try DeliveryPlanningRepositoryContext.resolving(
            repositoryRootPath: rootURL.path,
            containerKind: container.kind,
            containerRelativePath: container.url.lastPathComponent,
            targetNames: inventory.targets,
            schemeNames: inventory.schemes
        )
        return DeliveryFixtureReviewRepository(
            displayName: displayName,
            baseBranch: baseBranch,
            context: context
        )
    }

    nonisolated private static func supportedContainer(
        in rootURL: URL
    ) throws -> (url: URL, kind: DeliveryContainerKind) {
        let contents = try FileManager.default.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        var candidates: [(url: URL, kind: DeliveryContainerKind)] = []
        for url in contents {
            let values = try url.resourceValues(forKeys: [.isDirectoryKey])
            let name = url.lastPathComponent.lowercased()
            if name.hasSuffix(".xcworkspace"), values.isDirectory == true {
                candidates.append((url, .xcodeWorkspace))
            } else if name.hasSuffix(".xcodeproj"), values.isDirectory == true {
                candidates.append((url, .xcodeProject))
            } else if name == "package.swift", values.isDirectory == false {
                candidates.append((url, .swiftPackage))
            }
        }
        candidates.sort { $0.url.lastPathComponent < $1.url.lastPathComponent }
        guard !candidates.isEmpty else {
            throw DeliveryFixtureReviewBootstrapError.supportedContainerMissing
        }
        guard candidates.count == 1 else {
            throw DeliveryFixtureReviewBootstrapError.ambiguousContainers(
                candidates.map { $0.url.lastPathComponent }
            )
        }
        return candidates[0]
    }

    nonisolated private static func discoverInventory(
        repositoryRootURL: URL,
        container: (url: URL, kind: DeliveryContainerKind)
    ) -> (targets: [String], schemes: [String]) {
        switch container.kind {
        case .xcodeProject, .xcodeWorkspace:
            let containerFlag = container.kind == .xcodeWorkspace
                ? "-workspace"
                : "-project"
            guard let data = processOutput(
                executableURL: URL(fileURLWithPath: "/usr/bin/xcodebuild"),
                arguments: [
                    "-list",
                    "-json",
                    "-disableAutomaticPackageResolution",
                    "-skipPackageUpdates",
                    containerFlag,
                    container.url.path
                ]
            ), let object = try? JSONSerialization.jsonObject(with: data)
                as? [String: Any] else {
                return ([], [])
            }
            let key = container.kind == .xcodeWorkspace
                ? "workspace"
                : "project"
            let inventory = object[key] as? [String: Any]
            return (
                normalizedInventory(inventory?["targets"]),
                normalizedInventory(inventory?["schemes"])
            )
        case .swiftPackage:
            guard let data = processOutput(
                executableURL: URL(fileURLWithPath: "/usr/bin/xcrun"),
                arguments: [
                    "swift",
                    "package",
                    "--package-path",
                    repositoryRootURL.path,
                    "describe",
                    "--type",
                    "json"
                ]
            ), let object = try? JSONSerialization.jsonObject(with: data)
                as? [String: Any] else {
                return ([], [])
            }
            let targetNames = (object["targets"] as? [[String: Any]] ?? [])
                .compactMap { $0["name"] as? String }
            return (normalizedInventory(targetNames), [])
        }
    }

    nonisolated private static func normalizedInventory(
        _ value: Any?
    ) -> [String] {
        let values = value as? [String] ?? []
        var seen: Set<String> = []
        return values.compactMap {
            let item = $0.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !item.isEmpty, seen.insert(item).inserted else {
                return nil
            }
            return item
        }
        .sorted()
    }

    nonisolated private static func processOutput(
        executableURL: URL,
        arguments: [String]
    ) -> Data? {
        let outputPipe = Pipe()
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        process.standardOutput = outputPipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            let timeout = DispatchWorkItem {
                if process.isRunning {
                    process.terminate()
                }
            }
            DispatchQueue.global().asyncAfter(
                deadline: .now() + 15,
                execute: timeout
            )
            let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            timeout.cancel()
            guard process.terminationStatus == 0,
                  data.count <= 4 * 1_024 * 1_024 else {
                return nil
            }
            return data
        } catch {
            return nil
        }
    }

    nonisolated private static func currentBranch(
        in rootURL: URL
    ) throws -> String {
        let gitDirectories = try resolveGitDirectories(in: rootURL)
        let head = try readSmallTextFile(
            gitDirectories.worktree.appendingPathComponent("HEAD")
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        guard head.hasPrefix("ref: ") else {
            throw DeliveryFixtureReviewBootstrapError.detachedHead
        }
        let reference = String(head.dropFirst("ref: ".count))
        let prefix = "refs/heads/"
        guard reference.hasPrefix(prefix) else {
            throw DeliveryFixtureReviewBootstrapError.invalidGitMetadata
        }
        let branch = String(reference.dropFirst(prefix.count))
        guard isSafeGitReference(branch) else {
            throw DeliveryFixtureReviewBootstrapError.invalidGitMetadata
        }
        guard gitReferenceExists(reference, commonGitURL: gitDirectories.common) else {
            throw DeliveryFixtureReviewBootstrapError.currentBranchMissing(branch)
        }
        return branch
    }

    nonisolated private static func resolveGitDirectories(
        in rootURL: URL
    ) throws -> (worktree: URL, common: URL) {
        let dotGitURL = rootURL.appendingPathComponent(".git")
        var isDirectory = ObjCBool(false)
        guard FileManager.default.fileExists(
            atPath: dotGitURL.path,
            isDirectory: &isDirectory
        ) else {
            throw DeliveryFixtureReviewBootstrapError.gitMetadataMissing
        }

        let worktreeGitURL: URL
        if isDirectory.boolValue {
            worktreeGitURL = dotGitURL
        } else {
            let pointer = try readSmallTextFile(dotGitURL)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let prefix = "gitdir:"
            guard pointer.lowercased().hasPrefix(prefix) else {
                throw DeliveryFixtureReviewBootstrapError.invalidGitMetadata
            }
            let rawPath = pointer.dropFirst(prefix.count)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !rawPath.isEmpty else {
                throw DeliveryFixtureReviewBootstrapError.invalidGitMetadata
            }
            let candidate = URL(fileURLWithPath: rawPath)
            worktreeGitURL = (candidate.path as NSString).isAbsolutePath
                ? candidate
                : rootURL.appendingPathComponent(rawPath)
        }
        let resolvedWorktreeURL = worktreeGitURL
            .standardizedFileURL
            .resolvingSymlinksInPath()
            .standardizedFileURL

        let commonDirectoryFile = resolvedWorktreeURL
            .appendingPathComponent("commondir")
        let commonURL: URL
        if FileManager.default.fileExists(atPath: commonDirectoryFile.path) {
            let rawPath = try readSmallTextFile(commonDirectoryFile)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let candidate = URL(fileURLWithPath: rawPath)
            commonURL = ((candidate.path as NSString).isAbsolutePath
                ? candidate
                : resolvedWorktreeURL.appendingPathComponent(rawPath))
                .standardizedFileURL
                .resolvingSymlinksInPath()
                .standardizedFileURL
        } else {
            commonURL = resolvedWorktreeURL
        }
        return (resolvedWorktreeURL, commonURL)
    }

    nonisolated private static func gitReferenceExists(
        _ reference: String,
        commonGitURL: URL
    ) -> Bool {
        if FileManager.default.fileExists(
            atPath: commonGitURL.appendingPathComponent(reference).path
        ) {
            return true
        }
        let packedRefsURL = commonGitURL.appendingPathComponent("packed-refs")
        guard let contents = try? readSmallTextFile(packedRefsURL) else {
            return false
        }
        return contents.split(whereSeparator: \.isNewline).contains { line in
            guard !line.hasPrefix("#"), !line.hasPrefix("^") else {
                return false
            }
            return line.hasSuffix(" \(reference)")
        }
    }

    nonisolated private static func isSafeGitReference(_ branch: String) -> Bool {
        guard !branch.isEmpty,
              !branch.hasPrefix("/"),
              !branch.hasSuffix("/"),
              !branch.contains(".."),
              !branch.contains("\\"),
              !branch.contains("@{") else {
            return false
        }
        return branch.split(separator: "/", omittingEmptySubsequences: false)
            .allSatisfy { component in
                !component.isEmpty
                    && component != "."
                    && component != ".."
            }
    }

    nonisolated private static func readSmallTextFile(
        _ url: URL
    ) throws -> String {
        let data = try Data(contentsOf: url, options: [.mappedIfSafe])
        guard data.count <= 4 * 1_024 * 1_024,
              let value = String(data: data, encoding: .utf8) else {
            throw DeliveryFixtureReviewBootstrapError.invalidGitMetadata
        }
        return value
    }
}
