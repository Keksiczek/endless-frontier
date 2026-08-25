import Foundation

/// Upgrades a decoded `WorldState` from an older `schemaVersion` to the current
/// one by applying ordered migration steps.
///
/// The resilient `WorldState` decoder already tolerates *added* fields (missing
/// keys fall back to defaults). This migrator is for the harder case the
/// decoder can't handle: when a field's *meaning* changes (a rename, a unit
/// change, a re-scoped value). Register a step keyed by the version it upgrades
/// *from*; `migrate` runs the chain and stamps the new version.
public enum SaveMigrator {
    /// A migration transforms a state at version `key` into version `key + 1`.
    public typealias Step = @Sendable (WorldState) -> WorldState

    /// Registered migrations, keyed by the version they upgrade *from*.
    public static let steps: [Int: Step] = [
        // **2 → 3: put the water on the map.**
        //
        // `Region.river` is derived from the same elevation and moisture fields
        // the biomes come from, and it is written where every other derived
        // field is written: at generation, in `MapGenerator.region(at:...)`. So
        // a world that already existed had `nil` on every hex and would have
        // had it for ever — no rivers, no bridges, and no way to tell "this
        // country is dry" from "this save predates water".
        //
        // Safe to recompute rather than to guess, because the course is a pure
        // function of `(mapSeed, coord)`: filling it in gives exactly the map
        // the generator would have drawn for this seed, which is the same map a
        // newly explored hex on the frontier will get.
        2: { state in
            var s = state
            for index in s.regions.indices {
                s.regions[index].river = MapGenerator.river(
                    at: s.regions[index].coord, mapSeed: s.mapSeed)
            }
            return s
        },
        // **3 → 4: the outlaws move in.**
        //
        // Camps are founded at world creation, so a world that already existed
        // would have had none for ever — every raid in it conjured out of
        // nowhere, which is the whole fault `OutlawCamp` was written to fix.
        // The player who has been in one save for two hundred years is exactly
        // the player this was built for.
        //
        // Safe to found rather than to guess, for the same reason the rivers
        // were: the placement is a pure function of `(mapSeed, regions)`, so an
        // old world gets the camps its seed would have been born with. Skipped
        // where a save already has them, so re-running the chain cannot stack
        // three more camps on a world every time it loads.
        3: { state in
            guard state.camps.isEmpty, !state.regions.isEmpty else { return state }
            var s = state
            let founded = OutlawCampEngine.found(
                regions: s.regions, tribes: s.tribes, seed: s.mapSeed, language: s.language)
            s.regions = founded.regions
            s.camps = founded.camps
            return s
        },
        // **4 → 5: every people gets a hex of its own.**
        //
        // A seceding people was given `regionID` of the settlement it walked
        // out of, so it lived on the colony's own hex — where the world map
        // draws a house, not a tent. Every emergent people in every save is
        // therefore invisible on the map it is supposed to live on, and no
        // amount of drawing fixes a tribe that is standing on your roof.
        //
        // Re-homed rather than re-rolled: the people keeps its name, its
        // history and its standing, and only moves house. Deterministic from
        // `(mapSeed, tribe.id)`, and skipped for anyone already somewhere
        // sensible, so running the chain twice cannot shuffle a settled world.
        4: { state in
            var s = state
            let settled = Set(s.settlements.compactMap(\.regionID))
            var taken = Set(s.tribes.compactMap(\.regionID).filter { !settled.contains($0) })
            for index in s.tribes.indices {
                let here = s.tribes[index].regionID
                let homeless = here == nil || settled.contains(here!)
                    || s.tribes.prefix(index).contains { $0.regionID == here }
                guard homeless else { continue }
                var rng = SeededRNG(seed: DiplomacyEngine.tribeSeed(
                    mapSeed: s.mapSeed, tribeID: s.tribes[index].id, year: 0))
                let free = s.regions.filter {
                    !settled.contains($0.id) && !taken.contains($0.id) && $0.kind != .homeland
                }
                guard !free.isEmpty else { continue }
                // Nearest to the colony first, ties on the name — the same
                // ordering `DiplomacyEngine.newHome` uses, so a migrated world
                // and a fresh one put peoples in the same kind of place.
                let originCoord = s.settlements.first
                    .flatMap { home in s.regions.first { $0.id == home.regionID }?.coord }
                    ?? .origin
                let sorted = free.sorted {
                    $0.coord.distance(to: originCoord) != $1.coord.distance(to: originCoord)
                        ? $0.coord.distance(to: originCoord) < $1.coord.distance(to: originCoord)
                        : $0.name < $1.name
                }
                let pick = sorted[min(sorted.count - 1,
                                      Int(rng.nextUnit() * Double(sorted.count)))]
                s.tribes[index].regionID = pick.id
                taken.insert(pick.id)
            }
            return s
        }
    ]

    /// Brings `state` up to `target`, applying each registered step in order.
    /// A save already at (or ahead of) the target is returned untouched, so a
    /// newer save opened by an older build is left forward-compatibly intact.
    public static func migrate(
        _ state: WorldState,
        to target: Int = WorldState.currentSchemaVersion,
        steps: [Int: Step] = SaveMigrator.steps
    ) -> WorldState {
        guard state.schemaVersion < target else { return state }
        var s = state
        var version = s.schemaVersion
        while version < target {
            if let step = steps[version] { s = step(s) }
            version += 1
            s.schemaVersion = version
        }
        return s
    }
}
