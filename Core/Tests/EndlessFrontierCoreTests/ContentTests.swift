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
