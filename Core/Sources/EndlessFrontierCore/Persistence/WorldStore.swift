import Foundation

/// JSON-on-disk persistence for `WorldState`. Offline-first: no network.
public struct WorldStore: Sendable {
    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    /// Default location in the app's Documents directory.
    public static func defaultURL(fileManager: FileManager = .default) -> URL {
        let documents = (try? fileManager.url(
            for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        )) ?? fileManager.temporaryDirectory
        return documents.appendingPathComponent("endless-frontier-world.json")
    }

    /// Returns the saved world, or `nil` if no save exists yet.
    public func load() throws -> WorldState? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        return try Self.decoder.decode(WorldState.self, from: data)
    }

    /// Atomically writes the world to disk.
    public func save(_ state: WorldState) throws {
        let data = try Self.encoder.encode(state)
        try data.write(to: url, options: .atomic)
    }

    public func deleteSave() throws {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }

    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()

    static let decoder = JSONDecoder()
}
