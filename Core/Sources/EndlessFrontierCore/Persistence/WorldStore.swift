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

    /// The previous save, kept beside the current one.
    ///
    /// One file and an atomic write is not the same as being safe. `.atomic`
    /// promises the file is never *half* written; it promises nothing about the
    /// contents being loadable, and a colony is a hundred hours of somebody's
    /// life. A schema change that encodes fine and decodes badly, a disk that
    /// fills between the encode and the write, a field that goes non-optional
    /// by mistake — each of those replaces a good save with a bad one and the
    /// good one is gone.
    public var backupURL: URL {
        url.deletingPathExtension().appendingPathExtension("bak.json")
    }

    /// Returns the saved world (migrated up to the current schema), or `nil` if
    /// no save exists yet — or if the save is too old to load, in which case the
    /// caller starts a fresh world.
    ///
    /// **Falls back to the backup** when the current file will not decode. A
    /// player who loses one session's progress has had a bad day; a player who
    /// loses the colony has stopped playing.
    public func load() throws -> WorldState? {
        try loadRecovering().state
    }

    /// The same load, saying **where the world came from**.
    ///
    /// The app wants to know: a save silently rewound by a session reads as the
    /// game having eaten one, and a player told "we had to go back to
    /// yesterday's save" understands exactly what happened. Returned rather
    /// than stashed in a flag — a `Sendable` value type with shared mutable
    /// state is not a value type.
    public func loadRecovering() throws -> (state: WorldState?, rescued: Bool) {
        do {
            if let current = try read(url) { return (current, false) }
        } catch {
            // The current save is unreadable. Silently starting a new world
            // over somebody's colony is the worst thing this could do, so try
            // what we kept before giving up.
            if let rescued = try? read(backupURL) { return (rescued, true) }
            throw error
        }
        // No current save at all. A backup without a current file means the
        // write failed after the rotate, so it is still the best thing here.
        if let rescued = try? read(backupURL) { return (rescued, true) }
        return (nil, false)
    }

    private func read(_ from: URL) throws -> WorldState? {
        guard FileManager.default.fileExists(atPath: from.path) else { return nil }
        let data = try Data(contentsOf: from)
        let decoded = try Self.decoder.decode(WorldState.self, from: data)
        // Pre-V2 saves have incompatible population semantics; discard them.
        guard decoded.schemaVersion >= WorldState.minimumSupportedSchemaVersion else { return nil }
        return SaveMigrator.migrate(decoded)
    }

    /// Atomically writes the world to disk, keeping the previous save.
    ///
    /// Order matters and is the whole point: encode first, so a state that
    /// cannot be encoded never touches either file; then rotate the current
    /// save to `.bak`; then write. A failure at any step leaves at least one
    /// loadable world on disk.
    public func save(_ state: WorldState) throws {
        let data = try Self.encoder.encode(state)
        rotate()
        try data.write(to: url, options: .atomic)
    }

    /// Moves the current save aside. Best-effort by design: a colony that
    /// cannot make a backup should still be able to *save*, so a failure here
    /// must never fail the write that follows it.
    private func rotate() {
        let manager = FileManager.default
        guard manager.fileExists(atPath: url.path) else { return }
        try? manager.removeItem(at: backupURL)
        try? manager.copyItem(at: url, to: backupURL)
    }

    public func deleteSave() throws {
        let manager = FileManager.default
        if manager.fileExists(atPath: backupURL.path) {
            try manager.removeItem(at: backupURL)
        }
        guard manager.fileExists(atPath: url.path) else { return }
        try manager.removeItem(at: url)
    }

    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()

    static let decoder = JSONDecoder()
}
