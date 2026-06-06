import Foundation
import Testing
@testable import EndlessFrontierCore

/// The save migrator brings older `schemaVersion` saves up to the current one
/// by running ordered steps, while leaving current and newer saves intact.
@Suite("Save migration")
struct SaveMigrationTests {
    @Test("A current save is returned untouched")
    func currentSaveUnchanged() {
        let now = WorldState(schemaVersion: WorldState.currentSchemaVersion, settlements: [Settlement(name: "A")])
        #expect(SaveMigrator.migrate(now) == now)
    }

    @Test("An older save is stamped up to the target version")
    func stampsVersion() {
        let old = WorldState(schemaVersion: 0, settlements: [Settlement(name: "A")])
        let migrated = SaveMigrator.migrate(old, to: 2, steps: [:])
        #expect(migrated.schemaVersion == 2)
    }

    @Test("A single registered step runs and bumps the version")
    func runsOneStep() {
        let old = WorldState(schemaVersion: 0, settlements: [Settlement(name: "A")])
        let steps: [Int: SaveMigrator.Step] = [
            0: { var s = $0; s.worldFlags["m0"] = true; return s }
        ]
        let migrated = SaveMigrator.migrate(old, to: 1, steps: steps)
        #expect(migrated.schemaVersion == 1)
        #expect(migrated.worldFlags["m0"] == true)
    }

    @Test("Steps run in order across multiple versions")
    func runsChain() {
        let old = WorldState(schemaVersion: 0, settlements: [Settlement(name: "A")])
        let steps: [Int: SaveMigrator.Step] = [
            0: { var s = $0; s.worldFlags["a"] = true; return s },
            1: { var s = $0; s.worldFlags["b"] = (s.worldFlags["a"] == true); return s }   // sees step 0's result
        ]
        let migrated = SaveMigrator.migrate(old, to: 2, steps: steps)
        #expect(migrated.schemaVersion == 2)
        #expect(migrated.worldFlags["a"] == true)
        #expect(migrated.worldFlags["b"] == true)
    }

    @Test("A future save is left forward-compatibly intact")
    func futureSaveUntouched() {
        let future = WorldState(schemaVersion: 99, settlements: [Settlement(name: "A")])
        #expect(SaveMigrator.migrate(future, to: 1, steps: [:]) == future)
    }

    @Test("WorldStore.load migrates a legacy save on disk")
    func loadMigratesFromDisk() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("ef-migration-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: tmp) }
        let store = WorldStore(url: tmp)
        // Persist a save carrying an old schema version.
        let legacy = WorldState(schemaVersion: 0, settlements: [Settlement(name: "Old")])
        try store.save(legacy)
        let loaded = try store.load()
        #expect(loaded?.schemaVersion == WorldState.currentSchemaVersion)
    }
}
