import Foundation
import Testing
@testable import EndlessFrontierCore

@Suite("Content integrity")
struct ContentIntegrityTests {
    private func registry() throws -> GameDataRegistry { try GameDataRegistry.bundled() }

    @Test("Every tech prerequisite references an existing tech")
    func techPrereqsExist() throws {
        let reg = try registry()
        for tech in reg.techs.values {
            for required in tech.requires {
                #expect(reg.tech(required) != nil, "Tech \(tech.id) requires missing \(required)")
            }
        }
    }

    @Test("Every building a tech unlocks exists")
    func techUnlocksExist() throws {
        let reg = try registry()
        for tech in reg.techs.values {
            for effect in tech.effects {
                if case let .unlockBuilding(buildingID) = effect {
                    #expect(reg.building(buildingID) != nil, "Tech \(tech.id) unlocks missing \(buildingID)")
                }
            }
        }
    }

    @Test("Every era-milestone tech exists")
    func eraMilestoneTechsExist() throws {
        let reg = try registry()
        for era in Era.allCases {
            guard let def = reg.eraDefinition(era) else { continue }
            for milestone in def.milestones {
                if case let .techResearched(id) = milestone {
                    #expect(reg.tech(id) != nil, "Era \(era.rawValue) needs missing tech \(id)")
                }
            }
        }
    }

    @Test("Every unlockable building is reachable from some tech (or is early-era)")
    func buildingsReachable() throws {
        let reg = try registry()
        var unlockable: Set<String> = []
        for tech in reg.techs.values {
            for effect in tech.effects {
                if case let .unlockBuilding(id) = effect { unlockable.insert(id) }
            }
        }
        for building in reg.buildings.values where building.era != .earlySettlement {
            #expect(unlockable.contains(building.id), "Building \(building.id) is unreachable (no tech unlocks it)")
        }
    }

    /// Every event has to happen **to somebody or somewhere**.
    ///
    /// Thirty-four of seventy-two did neither: a drought, a wildfire, a bandit
    /// raid and a golden age were all a number moving in a struct, and the
    /// colony you were watching went on exactly as before. Every hook to land
    /// them existed — `pawn_health`, `pawn_mood`, `damage_buildings` — and none
    /// of them were used. This is the guard so a new event cannot be written
    /// that way again.
    @Test("Every event lands on a person or on the place")
    func eventsHappenToSomebody() throws {
        let reg = try registry()
        func lands(_ effect: EventEffect) -> Bool {
            switch effect {
            case .pawnHealthDelta, .pawnMoodDelta, .addPawn, .removePawn,
                 .damageBuildings, .raid, .regionHazardDelta, .regionKindChange:
                return true
            default:
                return false
            }
        }
        let faceless = reg.events
            .filter { template in
                !template.effects.contains(where: lands)
                    && !template.choices.contains { $0.effects.contains(where: lands) }
            }
            .map { $0.id }
            .sorted()
        #expect(faceless.isEmpty,
                "these happen to nobody and nowhere: \(faceless.joined(separator: ", "))")
    }

    /// Content Claude touches ships in both languages in the same change. The
    /// forty-eight `narrative_hint`s that were plain strings decoded into a
    /// `LocalizedText` with one value in it, so a Czech player read the whole
    /// storyteller in English and nothing anywhere said so.
    @Test("Every event narrates in Czech as well as English")
    func eventsAreBilingual() throws {
        let reg = try registry()
        let english: [String] = reg.events
            .filter { (template: EventTemplate) -> Bool in
                template.narrativeHint.resolve(GameLanguage.cs)
                    == template.narrativeHint.resolve(GameLanguage.en)
            }
            .map { $0.id }
            .sorted()
        #expect(english.isEmpty,
                "these narrate in English to a Czech player: \(english.joined(separator: ", "))")
    }

    /// …and so does everything else the player reads.
    ///
    /// The event guard above covers one file. Buildings and techs were English
    /// -only for a long time, got translated, and `CLAUDE.md` went on saying
    /// they had not been — which is the failure mode a note cannot fix: prose
    /// about content drifts, a test walking the content does not.
    ///
    /// Deliberately over the **raw JSON** rather than over the decoded registry:
    /// a `LocalizedText` field nobody modelled in Swift yet is exactly where a
    /// half-translated entry hides.
    @Test("Every line of content reads in Czech as well as English")
    func allContentIsBilingual() throws {
        // Every JSON in `GameData`, enumerated rather than listed: a hardcoded
        // list stops covering the file somebody adds next week, which is the
        // same drift this test exists to stop.
        let files = Bundle.module.urls(forResourcesWithExtension: "json",
                                       subdirectory: "GameData") ?? []
        #expect(files.count >= 10, "only \(files.count) data files found — is the bundle right?")
        var english: [String] = []
        for url in files {
            let root = try JSONSerialization.jsonObject(with: Data(contentsOf: url))
            walk(root, path: url.deletingPathExtension().lastPathComponent, into: &english)
        }
        #expect(english.isEmpty,
                "these read in English to a Czech player: \(english.sorted().joined(separator: ", "))")
    }

    /// Every `{"en": …}` in the tree, and whether it has a Czech twin.
    private func walk(_ node: Any, path: String, into out: inout [String]) {
        if let object = node as? [String: Any] {
            if let en = object["en"] as? String, !en.isEmpty {
                let cs = object["cs"] as? String
                if cs == nil || cs?.isEmpty == true { out.append(path) }
                return
            }
            // `id` names the entry, so a failure says *which* one rather than
            // handing back an array index nobody can look up.
            let name = (object["id"] as? String).map { "\(path)/\($0)" } ?? path
            for (key, value) in object { walk(value, path: "\(name).\(key)", into: &out) }
        } else if let array = node as? [Any] {
            for item in array { walk(item, path: path, into: &out) }
        }
    }

    @Test("Content library has grown across eras")
    func contentVolume() throws {
        let reg = try registry()
        #expect(reg.buildings.count >= 20)
        #expect(reg.techs.count >= 14)
        #expect(reg.events.count >= 18)
        // Spans multiple eras.
        let eras = Set(reg.buildings.values.map(\.era))
        #expect(eras.contains(.medieval))
        #expect(eras.contains(.earlyIndustrial))
    }

    /// **Everything a colonist can be handed goes into a slot.**
    ///
    /// `GameEngine.equipItem` requires `slot == .equipment` *and* a non-nil
    /// `equipSlot`, and returns the world unchanged when either is missing.
    /// `ItemsPanel` switches on `slot` alone and offers an Equip menu for
    /// anything marked equipment. **Seventy-three items had the first and not
    /// the second**, so the player picked a colonist and nothing happened — no
    /// error, no message, the item still on the shelf.
    ///
    /// They were not obscure: eighty-nine recipes made them, a fifth of the
    /// whole book, and because `ItemEngine.equippedEffects` only reads what is
    /// *worn*, every skill bonus, mood bonus and health regen on all
    /// seventy-three was dead the entire time.
    @Test("Every item a colonist can be handed has somewhere to put it")
    func everyEquipmentHasASlot() throws {
        let reg = try registry()
        let homeless = reg.items.values
            .filter { $0.slot == .equipment && $0.equipSlot == nil }
            .map(\.id).sorted()
        #expect(homeless.isEmpty,
                "these say they are equipment and name no slot, so equipping them silently does nothing: \(homeless)")
    }

    /// …and nothing the colony can make produces one of them.
    ///
    /// The slot check above is about the item; this is about the *cost*. A
    /// recipe whose output cannot be used is materials and worker-ticks spent
    /// on nothing, and the bench will happily take the order.
    @Test("No recipe makes a thing that cannot be used")
    func noRecipeMakesADeadThing() throws {
        let reg = try registry()
        let wasted = reg.recipes.values.compactMap { recipe -> String? in
            guard let item = reg.item(recipe.outputItemID) else { return recipe.id }
            guard item.slot == .equipment, item.equipSlot == nil else { return nil }
            return recipe.id
        }.sorted()
        #expect(wasted.isEmpty,
                "these recipes cost materials and produce something nobody can equip: \(wasted)")
    }
}

@Suite("Pollution")
struct PollutionTests {
    /// A fixed id so the two towns draw the same society rolls (wages, unrest);
    /// pollution is then the only thing telling them apart.
    private func settlement(factories: Int) -> Settlement {
        Settlement(id: UUID(uuidString: "00000000-0000-0000-0F0C-000000000001")!,
                   name: "Town", kind: .capital, pawns: Fixtures.pawns(20),
                   buildings: factories > 0 ? [BuildingInstance(definitionID: "factory", count: factories)] : [],
                   storage: [.food: 500, .energy: 500], storageCapacity: .uniform(9999),
                   stats: SettlementStats(morale: 80))
    }

    @Test("Industry accumulates pollution over time")
    func accumulates() throws {
        let reg = try GameDataRegistry.bundled()
        var world = WorldState(settlements: [settlement(factories: 1)])
        world.stewardEnabled = false
        world = TickEngine.advance(world, ticks: 60, registry: reg).state
        #expect(world.settlements[0].stats.pollution > 5)
    }

    @Test("Heavy pollution drags morale below a clean settlement's")
    func pollutionHurtsMorale() throws {
        let reg = try GameDataRegistry.bundled()
        // The council off: this is a test about smoke, and a colony that
        // builds itself a library halfway through is measuring something else.
        var dirty = WorldState(settlements: [settlement(factories: 2)])   // pollution → 60
        var clean = WorldState(settlements: [settlement(factories: 0)])
        dirty.stewardEnabled = false
        clean.stewardEnabled = false
        dirty = TickEngine.advance(dirty, ticks: 120, registry: reg).state
        clean = TickEngine.advance(clean, ticks: 120, registry: reg).state
        #expect(dirty.settlements[0].stats.morale < clean.settlements[0].stats.morale)
    }
}

/// **Every key on an authored effect is one the decoder reads.**
///
/// `EventEffect.init(from:)` takes what it knows and drops the rest in silence,
/// so an effect can be spelled four different ways and only one of them does
/// anything. Measured on the shipped file: of twenty-odd `damage_buildings`,
/// twelve said `strength` and the rest said `delta`, `damage` or `amount` — all
/// three ignored, all three falling back to a severity of 0.5, so an authored
/// landslide and an authored dam breach were exactly as bad as each other.
/// `add_pawn` with `count: 3` added one person; `remove_pawn` with `count: 2`
/// took one.
///
/// The check works by round-tripping: decode the effect, encode it again, and
/// anything in the original that the encoded form has no place for is a key
/// nothing reads. No second list to keep in step with the decoder — the decoder
/// *is* the list.
@Suite("Nothing in an event is written for a reader that does not exist")
struct EffectShapeTests {
    @Test("Every key on every effect is one the game reads")
    func noKeyIsIgnored() throws {
        let url = try #require(Bundle.module.url(forResource: "events", withExtension: "json",
                                                 subdirectory: "GameData"))
        let raw = try JSONSerialization.jsonObject(with: Data(contentsOf: url))
        let events = try #require(raw as? [[String: Any]])

        func inspect(_ effects: Any?, in event: String, at place: String) throws {
            guard let effects = effects as? [[String: Any]] else { return }
            for (i, effect) in effects.enumerated() {
                let data = try JSONSerialization.data(withJSONObject: effect)
                let decoded = try JSONDecoder().decode(EventEffect.self, from: data)
                let round = try JSONSerialization.jsonObject(
                    with: try JSONEncoder().encode(decoded))
                let kept = Set((round as? [String: Any])?.keys ?? [:].keys)
                for key in Set(effect.keys).subtracting(kept).sorted() {
                    Issue.record("\(event) \(place)[\(i)] (\(effect["type"] ?? "?")) carries '\(key)', which nothing reads")
                }
            }
        }

        for event in events {
            let id = event["id"] as? String ?? "?"
            try inspect(event["effects"], in: id, at: "effects")
            for choice in (event["choices"] as? [[String: Any]]) ?? [] {
                try inspect(choice["effects"], in: id,
                            at: "choices.\(choice["id"] as? String ?? "?").effects")
            }
        }
    }
}

/// **A progress bar must not cost determinism.**
///
/// Catch-up after a long absence had no progress at all — a spinner over up to
/// 43,200 ticks, which in a debug build is minutes the player cannot tell from
/// a hang. Reporting it means running the catch-up in slices, and slicing a
/// simulation is exactly the kind of change that quietly stops two runs of the
/// same seed agreeing.
///
/// It is safe here for one reason worth stating: `TickEngine.advance` is a
/// plain `for _ in 0..<ticks` over a pure step, and `ticks` is nothing but the
/// loop's bound. This test is what keeps that true.
@Suite("A month of world runs the same whether or not anybody is watching")
struct CatchUpSliceTests {
    @Test("Catch-up in slices lands on the same world as catch-up in one go")
    func catchUpIsTheSameWorldEitherWay() throws {
        let registry = try GameDataRegistry.bundled()
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        var world = GameWorldFactory.newGame(registry: registry, seed: 4242, now: start)
        world.lastRealTimestamp = start
        // Far enough to cross several slices, and several game years.
        let later = start.addingTimeInterval(
            Double(registry.config.realSecondsPerTick) * 900)

        let whole = GameEngine.openSession(world, now: later, registry: registry)
        var seen: [(Int, Int)] = []
        let sliced = GameEngine.openSession(
            world, now: later, registry: registry, sliceTicks: 97,
            onProgress: { done, total in seen.append((done, total)) })

        #expect(sliced.state == whole.state,
                "slicing the catch-up must not change a single thing about the world")
        #expect(sliced.fired.count == whole.fired.count,
                "…nor swallow or duplicate an event")
        #expect(seen.first?.0 == 0, "progress must start at nothing")
        #expect(seen.last?.0 == seen.last?.1, "…and end at everything")
        #expect((seen.last?.1 ?? 0) > 0, "a long absence must report a total worth showing")
    }

    /// The slice size is a tuning knob, not a behaviour.
    @Test("Any slice size gives the same world", arguments: [1, 13, 240, 10_000])
    func sliceSizeDoesNotMatter(slice: Int) throws {
        let registry = try GameDataRegistry.bundled()
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        var world = GameWorldFactory.newGame(registry: registry, seed: 77, now: start)
        world.lastRealTimestamp = start
        let later = start.addingTimeInterval(Double(registry.config.realSecondsPerTick) * 300)

        let whole = GameEngine.openSession(world, now: later, registry: registry)
        let sliced = GameEngine.openSession(world, now: later, registry: registry,
                                            sliceTicks: slice, onProgress: { _, _ in })
        #expect(sliced.state == whole.state)
    }
}

/// **A colony is a hundred hours of somebody's life and it lived in one file.**
///
/// `.atomic` promises the file is never *half* written. It promises nothing
/// about the contents being loadable, and every way a save goes bad — a schema
/// change that encodes fine and decodes badly, a disk that fills, a field that
/// stops being optional by mistake — replaces the good save with a bad one and
/// the good one is gone.
@Suite("A bad save does not cost the colony")
struct SaveBackupTests {
    private func store() -> WorldStore {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return WorldStore(url: dir.appendingPathComponent("world.json"))
    }

    private func world() throws -> WorldState {
        GameWorldFactory.newGame(registry: try GameDataRegistry.bundled(), seed: 7,
                                 now: Date(timeIntervalSince1970: 1_700_000_000))
    }

    @Test("The second save keeps the first")
    func savingRotates() throws {
        let store = store()
        var first = try world()
        first.tick = 100
        try store.save(first)
        #expect(!FileManager.default.fileExists(atPath: store.backupURL.path),
                "there is nothing to keep on the very first save")

        var second = first
        second.tick = 200
        try store.save(second)
        #expect(try store.load()?.tick == 200)
        let kept = try JSONDecoder().decode(
            WorldState.self, from: Data(contentsOf: store.backupURL))
        #expect(kept.tick == 100, "the backup must be the world before this one, not a copy of it")
    }

    /// The case the whole thing exists for.
    @Test("A save that will not decode falls back to the one that will")
    func corruptionIsSurvivable() throws {
        let store = store()
        var good = try world()
        good.tick = 500
        try store.save(good)
        var newer = good
        newer.tick = 600
        try store.save(newer)

        try Data("{ this is not a world }".utf8).write(to: store.url)
        let result = try store.loadRecovering()
        #expect(result.state?.tick == 500, "the colony must come back, one save behind")
        #expect(result.rescued, "…and the app must be able to say so")
    }

    @Test("A world that cannot be encoded never touches either file")
    func encodingFailsBeforeAnythingMoves() throws {
        let store = store()
        var first = try world()
        first.tick = 42
        try store.save(first)
        var second = first
        second.tick = 43
        try store.save(second)
        // Both files are sound; the encode-then-rotate order is what guarantees
        // it, and this is the ordering pinned so a refactor cannot swap them.
        #expect(try store.load()?.tick == 43)
        #expect(try JSONDecoder().decode(
            WorldState.self, from: Data(contentsOf: store.backupURL)).tick == 42)
    }

    @Test("Deleting a save deletes the backup with it")
    func deletingTakesBoth() throws {
        let store = store()
        try store.save(try world())
        try store.save(try world())
        try store.deleteSave()
        #expect(!FileManager.default.fileExists(atPath: store.url.path))
        #expect(!FileManager.default.fileExists(atPath: store.backupURL.path),
                "a player who deletes their world must not leave a copy of it behind")
    }
}
