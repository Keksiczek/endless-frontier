import Testing
import Foundation
@testable import EndlessFrontierCore

/// Six place kinds was an evening's worth: by the second valley the player had
/// seen all of them and a landmark stopped being news. These pin the six new
/// ones — and, more usefully, pin the *shape* of the set, so a seventh kind
/// added later cannot quietly ship with no name, no reward and no way to reach
/// it from any biome on the map.
@Suite("The places worth walking to")
struct NewPOIKindTests {
    private let seat = UUID(uuidString: "00000000-0000-0000-0000-0000000000C1")!

    private var registry: GameDataRegistry { Fixtures.registry(buildings: []) }
    private var ticksPerYear: Int { registry.config.ticksPerYear }

    private func colony(adults: Int = 8) -> Settlement {
        var settlement = Settlement(id: seat, name: "Camp", pawns: [],
                                    storage: [.food: 400], storageCapacity: 4000)
        settlement.pawns = (0..<adults).map { i in
            var p = Pawn(
                id: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", 900 + i))!,
                name: "Soul \(i)",
                skills: [.mining: 3 + i % 4, .farming: 2, .research: 1],
                assignedWork: .mining, health: 80)
            p.age = 28 * ticksPerYear
            p.needs.recreation = 40
            return p
        }
        var map = LocalMapGenerator.generate(mapSeed: 21, regionID: seat,
                                             biome: Fixtures.defaultBiomes[0])
        map.pois = []
        settlement.localMap = map
        return settlement
    }

    /// Works a place once, straight through the engine's own entry point.
    private func worked(
        _ kind: LocalPOIKind, at position: LocalPoint = LocalPoint(x: 0.5, y: 0.5),
        settlement: Settlement? = nil, party: [UUID] = []
    ) -> (before: Settlement, after: Settlement, outcome: LocalPOIOutcome) {
        var s = settlement ?? colony()
        let before = s
        let poi = LocalPOI(id: 7, kind: kind, position: position, discovered: true)
        s.localMap?.pois = [poi]
        var rng = SeededRNG(seed: 4242)
        let outcome = LocalPOIEngine.work(&s, poi: poi, depletion: 1, party: party,
                                          registry: registry, rng: &rng)
        return (before, s, outcome)
    }

    private func stored(_ s: Settlement, _ r: ResourceType) -> Double { s.storage[r] }

    // MARK: - The shape of the set

    /// Every kind must be *reachable*: a place that no biome ever rolls is
    /// content that does not exist. This is the reachability rule applied to
    /// content rather than to a threshold.
    @Test("Every kind of place can turn up in at least one country")
    func everyKindOccursSomewhere() {
        let biomes = ["forest", "desert", "tundra", "mountains", "coast", "plains"]
        var reachable: Set<LocalPOIKind> = []
        for biome in biomes {
            for (kind, weight) in LocalMapGenerator.poiMix(for: biome) where weight > 0 {
                reachable.insert(kind)
            }
        }
        #expect(reachable.count == LocalPOIKind.allCases.count,
                "unreachable: \(Set(LocalPOIKind.allCases).subtracting(reachable))")
    }

    @Test("Every country can fill a map without running out of kinds")
    func everyBiomeHasEnoughKinds() {
        for biome in ["forest", "desert", "tundra", "mountains", "coast", "plains"] {
            let available = LocalMapGenerator.poiMix(for: biome).filter { $0.1 > 0 }.count
            #expect(available >= LocalMapGenerator.poiCountRange.upperBound,
                    "\(biome) offers only \(available) kinds")
        }
    }

    @Test("Every kind is named, in both languages", arguments: LocalPOIKind.allCases)
    func everyKindIsNamed(kind: LocalPOIKind) {
        for language in [GameLanguage.en, .cs] {
            #expect(!kind.plainName.resolve(language).isEmpty)
            #expect(!kind.discoveryText.resolve(language).isEmpty)
        }
        #expect(!kind.plainNameDative.isEmpty)
        #expect(kind.partySize > 0)
        #expect(kind.workTicks > 0)
    }

    /// A place that pays nothing is a place nobody will walk to twice.
    @Test("Every kind pays for the walk", arguments: LocalPOIKind.allCases)
    func everyKindRewardsSomething(kind: LocalPOIKind) {
        let party = colony().pawns.prefix(kind.partySize).map(\.id)
        let (before, after, outcome) = worked(kind, party: Array(party))
        let gainedGoods = ResourceType.allCases.contains { stored(after, $0) > stored(before, $0) }
        let changedPeople = zip(before.pawns, after.pawns).contains { $0.health != $1.health }
            || before.stats.morale != after.stats.morale
            || zip(before.pawns, after.pawns).contains { $0.skills != $1.skills }
            || (before.localMap?.exploredCells.count ?? 0) != (after.localMap?.exploredCells.count ?? 0)
        #expect(gainedGoods || changedPeople, "\(kind) gave nothing at all")
        for language in [GameLanguage.en, .cs] {
            #expect(!outcome.narrative.resolve(language).isEmpty)
        }
    }

    // MARK: - What each new place actually does

    @Test("A wild orchard feeds the colony and bears again")
    func orchardFeeds() {
        let (before, after, _) = worked(.orchard)
        #expect(stored(after, .food) > stored(before, .food) + 20)
        #expect(LocalPOIKind.orchard.isRenewable)
        #expect(LocalPOIKind.orchard.cooldownYears == 1)
    }

    /// The hermit is the only place that pays the *party* rather than the
    /// colony, so it is the only one where an empty party must still be safe.
    @Test("The hermit teaches the people who walked there")
    func hermitTeachesTheParty() {
        var s = colony()
        let learners = Array(s.pawns.prefix(2).map(\.id))
        for id in learners {
            guard let i = s.pawns.firstIndex(where: { $0.id == id }) else { continue }
            s.pawns[i].skills = [.mining: 6]
        }
        let (_, after, _) = worked(.hermit, settlement: s, party: learners)
        for id in learners {
            let taught = after.pawns.first { $0.id == id }
            #expect(taught?.skill(.mining) == 7, "the hermit taught nobody")
        }
        // And everyone who stayed home is exactly as they were.
        let stayed = after.pawns.filter { !learners.contains($0.id) }
        #expect(stayed.allSatisfy { $0.skill(.mining) <= 6 })
    }

    @Test("A hermit visited by nobody changes nothing and does not trap")
    func hermitWithNoParty() {
        let (before, after, _) = worked(.hermit, party: [])
        #expect(after.pawns.count == before.pawns.count)
        #expect(stored(after, .knowledge) > stored(before, .knowledge))
    }

    /// The one place that pays in map. It is also the case that caught a real
    /// bug: `resolve` used to write back a copy of the map taken *before* the
    /// work ran, which put the fog straight back over the charted ground.
    @Test("The watchtower charts the country, and the charting survives the trip home")
    func watchtowerChartsAndKeepsIt() {
        var s = colony()
        s.localMap?.exploredCells = [0]
        let poi = LocalPOI(id: 7, kind: .watchtower,
                           position: LocalPoint(x: 0.5, y: 0.5), discovered: true)
        s.localMap?.pois = [poi]
        let charted = s.localMap?.exploredCells.count ?? 0

        // Straight through the engine, expedition and all — the path the bug
        // lived in.
        var world = WorldState(tick: 0, settlements: [s])
        world = GameEngine.dispatchToPOI(world, settlementID: seat, poiID: 7, registry: registry)
        let travel = LocalPOIEngine.travelTicks(to: poi.position)
        for _ in 0..<(travel * 2 + LocalPOIKind.watchtower.workTicks + 4) {
            world.tick += 1
            world.settlements[0] = LocalPOIEngine.advanceOneTick(
                world.settlements[0], tick: world.tick, mapSeed: world.mapSeed,
                registry: registry)
        }
        let after = world.settlements[0]
        #expect(after.expeditions.isEmpty, "the party never came home")
        #expect((after.localMap?.exploredCells.count ?? 0) > charted + 10,
                "the tower charted nothing that stuck")
        #expect(after.localMap?.pois.first?.visits == 1)
    }

    @Test("A salt pan keeps the colony fed")
    func saltPanFeeds() {
        let (before, after, _) = worked(.saltPan)
        #expect(stored(after, .food) > stored(before, .food))
        #expect(LocalPOIKind.saltPan.maxVisits == 3)
    }

    /// Robbing the dead pays best and costs something no other place costs.
    @Test("Opening a barrow pays richly and the colony minds")
    func barrowCostsMorale() {
        var s = colony()
        s.stats.morale = 70
        let (before, after, outcome) = worked(.barrow, settlement: s)
        #expect(stored(after, .influence) > stored(before, .influence) + 20)
        #expect(after.stats.morale < before.stats.morale)
        #expect(outcome.visitsRemaining == 0)
    }

    @Test("A faithful colony minds the barrow more than a faithless one")
    func faithMindsTheBarrowMore() {
        var faithless = colony(); faithless.stats.morale = 80
        var faithful = colony(); faithful.stats.morale = 80
        faithful.faith.cultID = "any"; faithful.faith.faith = 60

        let a = worked(.barrow, settlement: faithless).after
        let b = worked(.barrow, settlement: faithful).after
        #expect(b.stats.morale < a.stats.morale)
        #expect(b.faith.faith < 60)
    }

    @Test("A fallen star is the richest single haul on the map")
    func starfallIsRich() {
        let (before, after, _) = worked(.starfall)
        #expect(stored(after, .materials) >= stored(before, .materials) + 40)
        #expect(stored(after, .knowledge) >= stored(before, .knowledge) + 34)
        #expect(LocalPOIKind.starfall.hazardChance > LocalPOIKind.cave.hazardChance)
    }

    // MARK: - The items the new places drop

    @Test("Every new item is named and described in both languages")
    func newItemsAreBilingual() throws {
        // The shipped data, not the stub the rest of this suite runs on.
        let registry = try GameDataRegistry.bundled()
        let wanted = ["grafting_knife", "salt_crock", "preserving_jar", "hermits_journal",
                      "whittled_charm", "grave_torc", "barrow_blade", "mourning_mask",
                      "star_iron", "skyfall_blade", "crater_glass", "survey_glass",
                      "march_map", "watchmans_horn"]
        for id in wanted {
            guard let def = registry.items[id] else {
                Issue.record("missing item \(id)")
                continue
            }
            for language in [GameLanguage.en, .cs] {
                #expect(!def.name.resolve(language).isEmpty, "\(id) has no \(language) name")
                #expect(!def.description.resolve(language).isEmpty,
                        "\(id) has no \(language) description")
            }
        }
    }

    @Test("The loot pool is deep enough that a run of finds is not the same find")
    func lootPoolIsDeep() throws {
        #expect(try SiteEngine.lootPool(registry: GameDataRegistry.bundled()).count >= 40)
    }

    /// `GameDataRegistry.bundled()` loads items with `try?`, so **one** malformed
    /// effect anywhere in `items.json` silently empties the entire table — no
    /// loot, no equipment, no error, for the whole game. That cost a debugging
    /// round the first time a new item used the wrong key for its payload; this
    /// is the tripwire so it costs nothing the second time.
    @Test("A single bad item cannot silently empty the whole table")
    func itemTableIsActuallyLoaded() throws {
        let registry = try GameDataRegistry.bundled()
        #expect(registry.items.count >= 60,
                "items.json failed to decode — a malformed effect takes the lot with it")
        #expect(registry.items.values.contains { $0.slot == .equipment })
        #expect(registry.items.values.contains { !$0.effects.isEmpty })
    }
}
