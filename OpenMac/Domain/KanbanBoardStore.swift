import Foundation

struct KanbanBoardSnapshot: Codable, Equatable {
    var tasks: [WorkTask]
    var agents: [AgentProfile]
    var wipLimits: [KanbanStatus: Int]
}

protocol KanbanBoardStore {
    func load() throws -> KanbanBoardSnapshot?
    func save(_ snapshot: KanbanBoardSnapshot) throws
}

struct FileKanbanBoardStore: KanbanBoardStore {
    let fileURL: URL

    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(fileURL: URL = FileKanbanBoardStore.defaultFileURL) {
        self.fileURL = fileURL

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .secondsSince1970
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        self.decoder = decoder
    }

    static var defaultFileURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return appSupport
            .appendingPathComponent("OpenMac", isDirectory: true)
            .appendingPathComponent("kanban-board.json")
    }

    func load() throws -> KanbanBoardSnapshot? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return nil
        }
        let data = try Data(contentsOf: fileURL)
        return try decoder.decode(KanbanBoardSnapshot.self, from: data)
    }

    func save(_ snapshot: KanbanBoardSnapshot) throws {
        let directoryURL = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let data = try encoder.encode(snapshot)
        try data.write(to: fileURL, options: .atomic)
    }
}
