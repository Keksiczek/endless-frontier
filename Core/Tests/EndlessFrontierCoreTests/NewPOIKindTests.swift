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
                                    storage: [.food: 400], storageCapacity: .uniform(4000))
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

@Suite("Motion bank")
struct MotionBankTests {

    /// The counterpart to `itemTableIsActuallyLoaded`, and it exists for the
    /// same reason twice over: the bank shipped 48 clips and loaded **none** of
    /// them for a while, because `Wave` used the synthesised decoder and every
    /// clip omits `phase`. The build was green throughout, and so was
    /// `ContentTests`, which reads the JSON rather than the registry. Only a
    /// test that asks the registry can see this (rule 43).
    @Test("The motion bank actually reaches the registry")
    func motionBankIsActuallyLoaded() throws {
        let registry = try GameDataRegistry.bundled()
        #expect(registry.motions.count >= 40,
                "motions.json failed to decode — one malformed clip takes the lot")
        // The clips the drawing code needs by name.
        for id in ["walking", "working", "hauling", "sleeping"] {
            #expect(registry.motions[id] != nil, "the bank is missing \(id)")
        }
    }

    /// A clip nothing can select is content that loads and is never seen —
    /// the oldest bug in this repository, and the reason `serves_*` exists.
    @Test("Every clip but the fallback can be chosen by something")
    func everyClipIsReachable() throws {
        let registry = try GameDataRegistry.bundled()
        for clip in registry.motions.values where clip.id != "standing" {
            #expect(!clip.servesActivities.isEmpty,
                    "\(clip.id) serves no activity, so nothing will ever pick it")
        }
    }

    /// The activities the renderer can ask for — `AgentMotion.Activity.motionID`
    /// in the app, which the package cannot see. Kept here rather than derived,
    /// because the point of the test is to fail when the two drift apart.
    static let drawnActivities = [
        "sleeping", "at_home", "walking", "working", "socializing", "playing",
        "resting", "travelling", "expedition", "fighting", "hauling",
    ]

    /// **The test the last one was not.**
    ///
    /// `everyClipIsReachable` asks whether a clip *declares* what it is for.
    /// Every clip in the bank passed it while seventeen of forty-eight had
    /// never been drawn — because declaring is not being chosen, and the
    /// chooser broke ties on id and stopped at the first. Seven clips serve a
    /// farmer at work; `digging` sorts first; the colony dug for two hundred
    /// years.
    ///
    /// So this one asks the question that catches it: sweep every ask the
    /// renderer can actually make — activity × trade × hunt phase × the
    /// colonist's own variant — and require that every clip comes back at
    /// least once. A clip that no sweep returns is content that loads and
    /// cannot be seen, which is rule 43 with the selector in scope.
    @Test("Every clip is returned by some ask the canvas actually makes")
    func everyClipIsSelectable() throws {
        let registry = try GameDataRegistry.bundled()
        // Every workplace the canvas can name, plus "somewhere unwritten" — the
        // sweep has to cover the building axis too, or a bank of clips written
        // for rooms passes a test that never walks into one.
        let workplaces: [String?] = [nil] + registry.buildings.keys.sorted()
        var seen = Set<String>()
        for activity in Self.drawnActivities {
            for work in WorkKind.allCases.map(\.rawValue) + [nil] {
                for phase in [nil, "stalking", "closing", "killed"] {
                    for building in workplaces {
                        for variant in UInt64(0)..<8 {
                            seen.insert(registry.motion(
                                activity: activity, work: work, phase: phase,
                                variant: variant, building: building).id)
                        }
                    }
                }
            }
        }
        let unreachable = Set(registry.motions.keys).subtracting(seen)
            .subtracting(["standing"])
        #expect(unreachable.isEmpty,
                "clips that load and can never be drawn: \(unreachable.sorted())")
    }

    /// Variety, stated as an assertion: a field of farmers is not one farmer
    /// drawn several times. Without this the fix above is a number nobody
    /// checks — `one(of:variant:)` could go back to `.first` and every test
    /// but this one would still pass.
    @Test("Colonists on the same trade are drawn doing different things")
    func variantSpreadsTheWork() throws {
        let registry = try GameDataRegistry.bundled()
        for work in ["farming", "building", "cooking"] {
            let clips = Set((UInt64(0)..<12).map {
                registry.motion(activity: "working", work: work, variant: $0).id
            })
            #expect(clips.count >= 3,
                    "\(work) draws only \(clips.sorted()) however the variant falls")
        }
    }

    /// **The workplace outranks the trade.** A weaver and a tanner are both
    /// `crafting`; drawn off the trade alone they are one person twice.
    @Test("A clip written for a building wins inside that building")
    func theBuildingOutranksTheTrade() throws {
        let bellows = MotionDefinition(
            id: "bellows", name: LocalizedText(values: [.en: "Bellows", .cs: "Měch"]),
            servesActivities: ["working"], servesWork: ["crafting"],
            servesBuildings: ["bloomery"])
        let bench = MotionDefinition(
            id: "bench", name: LocalizedText(values: [.en: "Bench", .cs: "Ponk"]),
            servesActivities: ["working"], servesWork: ["crafting"])
        let registry = GameDataRegistry(
            buildings: [], techs: [], eras: [], biomes: [], events: [],
            motions: [bellows, bench], config: .default)

        #expect(registry.motion(activity: "working", work: "crafting",
                                building: "bloomery").id == "bellows")
        // …and a building nothing was written for still gets a clip, or the
        // bank only works once it is finished.
        #expect(registry.motion(activity: "working", work: "crafting",
                                building: "workshop").id == "bench")
        #expect(registry.motion(activity: "working", work: "crafting").id == "bench",
                "a clip that names a building leaked out of it")
    }

    /// The other half of the same rule: a building-specific clip must not be
    /// handed to somebody working somewhere else just because the variant fell
    /// that way.
    @Test("A building's own clip never leaks into another building")
    func namedClipsStayHome() throws {
        let registry = try GameDataRegistry.bundled()
        let named = registry.motions.values.filter { !$0.servesBuildings.isEmpty }
        for clip in named {
            for work in clip.servesWork {
                for activity in clip.servesActivities {
                    for variant in UInt64(0)..<16 {
                        let elsewhere = registry.motion(
                            activity: activity, work: work, variant: variant,
                            building: "__nowhere__")
                        #expect(elsewhere.id != clip.id,
                                "a clip written for one building was drawn in another")
                    }
                }
            }
        }
    }

    /// …and the same colonist on the same job is drawn the same way twice, or
    /// the figures flicker at frame rate.
    @Test("One variant always gets the same clip")
    func variantIsStable() throws {
        let registry = try GameDataRegistry.bundled()
        for variant in UInt64(0)..<8 {
            let first = registry.motion(activity: "working", work: "farming", variant: variant)
            let again = registry.motion(activity: "working", work: "farming", variant: variant)
            #expect(first.id == again.id)
        }
    }

    /// What the renderer actually asks, for every trade a colonist can have.
    @Test("Every trade at work gets a clip, and the same one twice")
    func selectionIsTotalAndStable() throws {
        let registry = try GameDataRegistry.bundled()
        for work in WorkKind.allCases {
            let first = registry.motion(activity: "working", work: work.rawValue)
            let again = registry.motion(activity: "working", work: work.rawValue)
            #expect(first.id == again.id,
                    "\(work.rawValue) is drawn differently on two identical asks")
        }
    }
}

@Suite("Motion bank — the trades look different")
struct MotionDistinctionTests {

    /// The whole point, stated as an assertion: a hunter at work and a builder
    /// at work must not be handed the same clip. This is the thing a screenshot
    /// cannot settle — two figures on a canvas at different phases of the same
    /// wave look different, and two figures on *different* waves can happen to
    /// look alike for a frame.
    @Test("A hunter at work is not drawn like a builder at work")
    func tradesGetTheirOwnClips() throws {
        let registry = try GameDataRegistry.bundled()
        let hunter = registry.motion(activity: "working", work: "hunting")
        let builder = registry.motion(activity: "working", work: "building")
        let farmer = registry.motion(activity: "working", work: "farming")
        let generic = registry.motion(activity: "working", work: nil)

        #expect(hunter.id != generic.id, "the hunter fell back to the generic work clip")
        #expect(farmer.id != generic.id, "the farmer fell back to the generic work clip")
        #expect(hunter.id != builder.id)
        #expect(hunter.id != farmer.id)
    }

    /// A clip is only visible if some number in it differs from the fallback.
    /// A bank of forty entries that all say the same thing is forty ways of
    /// drawing one person.
    @Test("The clips actually differ in the numbers the renderer reads")
    func clipsDifferInSubstance() throws {
        let registry = try GameDataRegistry.bundled()
        var shapes = Set<String>()
        for clip in registry.motions.values {
            shapes.insert("\(clip.legs.amplitude)/\(clip.legs.frequency)/"
                          + "\(clip.toolArm.amplitude)/\(clip.toolArm.frequency)/"
                          + "\(clip.lean)/\(clip.bob)/\(clip.slouch)/\(clip.reach)")
        }
        let summary = "\(shapes.count) distinct shapes across \(registry.motions.count) clips"
        #expect(shapes.count >= registry.motions.count - 2,
                "clips are duplicating each other's numbers: \(summary)")
    }
}

@Suite("The hunt is legible")
struct HuntPhaseTests {

    /// Each phase the engine can report must reach a *different* clip. Four
    /// hunting clips separated by nothing but the alphabet is what this
    /// replaces: whichever sorted first was drawn for every moment of the hunt,
    /// so a colonist creeping through the wood and one standing over a carcass
    /// were the same figure.
    @Test("Every hunt phase draws a different body")
    func phasesReachDifferentClips() throws {
        let registry = try GameDataRegistry.bundled()
        var chosen: [String: String] = [:]
        for phase in ["stalking", "closing", "killed"] {
            let clip = registry.motion(activity: "working", work: "hunting", phase: phase)
            #expect(clip.servesPhases.contains(phase),
                    "phase \(phase) fell through to \(clip.id), which is not written for it")
            chosen[phase] = clip.id
        }
        #expect(Set(chosen.values).count == chosen.count,
                "two phases share a clip: \(chosen)")
    }

    /// A hunter with no phase — nothing has hunted yet this save — still gets a
    /// hunter's clip rather than the generic work animation.
    @Test("A hunter with no phase yet is still a hunter")
    func absentPhaseFallsBackWithinTheTrade() throws {
        let registry = try GameDataRegistry.bundled()
        let noPhase = registry.motion(activity: "working", work: "hunting", phase: nil)
        let generic = registry.motion(activity: "working", work: nil)
        #expect(noPhase.id != generic.id)
        #expect(noPhase.servesWork.contains("hunting"))
    }
}

@Suite("Ground bank")
struct GroundBankTests {

    /// Same guard as the motion bank, for the same reason: a data file the
    /// registry decodes to nothing is invisible to the build and to
    /// `ContentTests`, and the canvas quietly falls back to plain earth
    /// everywhere (rule 43).
    @Test("Every ground cover the map can lay down has an entry")
    func everyCoverIsDescribed() throws {
        let registry = try GameDataRegistry.bundled()
        for cover in GroundCover.allCases {
            #expect(registry.ground[cover.rawValue] != nil,
                    "\(cover.rawValue) has no entry, so it draws as bare dirt")
        }
    }

    /// Twelve covers all painted the same colour is one country in twelve
    /// costumes — the thing splitting the margins was meant to prevent.
    @Test("The covers are actually different colours")
    func coversDiffer() throws {
        let registry = try GameDataRegistry.bundled()
        let shades = Set(registry.ground.values.map { "\($0.red)/\($0.green)/\($0.blue)" })
        #expect(shades.count == registry.ground.count)
    }

    /// A texture name the renderer does not know draws nothing, which reads as
    /// smooth ground — survivable, and silent, which is why it is checked.
    @Test("Every texture names a mark the renderer can draw")
    func texturesAreReal() throws {
        let known: Set<String> = ["blades", "pebbles", "ripples", "crack", "glint",
                                  "reed", "frond", "sprig", "stipple", "chips",
                                  "driedCrack"]
        let registry = try GameDataRegistry.bundled()
        for def in registry.ground.values {
            #expect(known.contains(def.texture),
                    "\(def.id) asks for '\(def.texture)', which nothing draws")
        }
    }
}

@Suite("Scenery bank")
struct SceneryBankTests {

    /// The bank is keyed on raw values, and the four enums it serves do not
    /// agree about spelling: `RockKind` states `ironSeam = "iron_seam"` while
    /// `LandformKind.ruinField` states nothing and so answers `"ruinField"`.
    /// Guessing which is which put one entry in the file under a name nothing
    /// would ever ask for — an entry that loads and can never be reached, the
    /// oldest bug here. This asks the enums instead.
    @Test("Every crop, tree, rock and landform has an entry under its own name")
    func everythingOnTheGroundIsDescribed() throws {
        let registry = try GameDataRegistry.bundled()
        for id in CropSpecies.allCases.map(\.rawValue)
            + TreeSpecies.allCases.map(\.rawValue)
            + RockKind.allCases.map(\.rawValue)
            + LandformKind.allCases.map(\.rawValue) {
            #expect(registry.scenery[id] != nil,
                    "\(id) has no entry, so it draws in the fallback green")
        }
    }

    /// Broadleaves turn and evergreens do not — half of what makes an autumn
    /// wood read as one, and a rule that lives entirely in the data now.
    @Test("The broadleaves turn in autumn and the conifers do not")
    func autumnSeparatesTheWood() throws {
        let registry = try GameDataRegistry.bundled()
        for id in ["oak", "birch", "beech", "poplar", "willow"] {
            let tree = registry.scenery(id)
            #expect(tree.colour(in: .autumn) != tree.colour(in: .summer),
                    "\(id) is a broadleaf and should turn")
        }
        for id in ["pine", "spruce", "juniper"] {
            let tree = registry.scenery(id)
            #expect(tree.colour(in: .autumn) == tree.colour(in: .summer),
                    "\(id) is an evergreen and should keep its colour")
        }
    }
}

@Suite("Ground bank — every cover is real country")
struct GroundTextureTests {

    /// **A `GroundCover` case with no row is a colour nobody wrote**, and a row
    /// with no case is a colour nobody asks for. Both are the same silent
    /// failure from opposite ends (rule 43), and the enum is the side that
    /// decides what the map can contain.
    @Test("Every cover the map can produce has a row in the bank")
    func everyCoverIsDescribed() throws {
        let registry = try GameDataRegistry.bundled()
        for cover in GroundCover.allCases {
            #expect(registry.ground.keys.contains(cover.rawValue),
                    "ground.json says nothing about \(cover.rawValue)")
        }
    }

    /// …and every row is country some biome actually lays down. A ground the
    /// generator can never place is rule 47 in the terrain: it loads, it is
    /// correct, and no player will see it.
    @Test("Every ground in the bank is produced by some biome")
    func everyGroundIsReachable() throws {
        let registry = try GameDataRegistry.bundled()
        var placed = Set<String>()
        for biome in ["forest", "desert", "tundra", "mountains", "coast", "plains"] {
            for (cover, weight) in LocalTerrain.weights(for: biome) where weight > 0 {
                placed.insert(cover.rawValue)
            }
        }
        let unreachable = Set(registry.ground.keys).subtracting(placed)
        #expect(unreachable.isEmpty,
                "ground no biome ever lays down: \(unreachable.sorted())")
    }

    /// The grain is drawn off `texture`, and the renderer answers to a closed
    /// list of names. A row naming a mark nothing draws gets the fallback dash
    /// — legible, and wrong. This is the check that the two lists are one list.
    @Test("Every texture named in the bank is one the canvas can draw")
    func everyTextureIsDrawable() throws {
        let known: Set<String> = ["blades", "pebbles", "ripples", "crack", "glint",
                                  "reed", "frond", "sprig", "stipple", "chips",
                                  "driedCrack"]
        let registry = try GameDataRegistry.bundled()
        for (id, def) in registry.ground {
            #expect(known.contains(def.texture),
                    "\(id) asks for a mark the canvas does not know")
        }
    }

    /// A biome's character is its dominant cover, and widening the margins must
    /// never cost it that (`LocalTerrainTests` checks the outcome; this checks
    /// the table it comes from).
    @Test("Widening the margins left every biome its character")
    func dominanceSurvives() {
        for biome in ["forest", "desert", "tundra", "mountains", "coast", "plains"] {
            let table = LocalTerrain.weights(for: biome).sorted { $0.1 > $1.1 }
            let total = table.reduce(0) { $0 + $1.1 }
            #expect(abs(total - 1) < 0.001, "\(biome)'s weights sum to \(total)")
            #expect(table[0].1 > table[1].1 * 1.2,
                    "\(biome) has no dominant cover any more")
        }
    }
}

/// **Step one of `docs/MOUNTS_AND_VEHICLES.md`.**
///
/// Nothing rides anything yet — this is the data layer and the guard that it
/// actually loads. Written first on purpose: the motion bank shipped 48 clips
/// of which 17 had never been drawn, and the way that happens is content going
/// in before anything reads it.
@Suite("Conveyances — the data layer")
struct ConveyanceBankTests {

    @Test("The conveyance bank actually reaches the registry")
    func bankIsLoaded() throws {
        let registry = try GameDataRegistry.bundled()
        #expect(registry.conveyances.count >= 3,
                "conveyances.json failed to decode — one malformed entry takes the lot")
        #expect(registry.conveyance("travois") != nil)
    }

    /// Every reference in the file points at something real. `references.py`
    /// asks this of the drafts; this asks it of what shipped, which is the half
    /// that matters after a hand edit.
    @Test("Nothing in the bank points at something that does not exist")
    func referencesResolve() throws {
        let registry = try GameDataRegistry.bundled()
        let species = Set(AnimalSpecies.allCases.map(\.rawValue))
        let covers = Set(GroundCover.allCases.map(\.rawValue))
        for def in registry.conveyances.values {
            if let animal = def.requiresAnimal {
                #expect(species.contains(animal),
                        "\(def.id) wants an animal the wild never produces")
            }
            if let building = def.requiresBuilding {
                #expect(registry.building(building) != nil,
                        "\(def.id) is kept in a building that does not exist")
            }
            if let tech = def.requiresTech {
                #expect(registry.tech(tech) != nil,
                        "\(def.id) waits on a tech nobody can research")
            }
            for material in def.materials.keys {
                #expect(registry.item(material)?.slot == .material,
                        "\(def.id) is built out of something that is not stock")
            }
            for ground in def.terrain {
                #expect(covers.contains(ground),
                        "\(def.id) may cross ground the map cannot make")
            }
        }
    }

    /// A mount must name its beast, and a cart must not — the one place the
    /// `class` actually changes what the entry means.
    @Test("A mount is backed by an animal and a cart is not")
    func mountsNameTheirBeast() throws {
        let registry = try GameDataRegistry.bundled()
        for def in registry.conveyances.values {
            if def.kind == .mount {
                #expect(def.requiresAnimal != nil, "\(def.id) is a mount with nothing to ride")
            } else {
                #expect(def.requiresAnimal == nil, "\(def.id) is not a mount and names a beast")
            }
        }
    }

    /// **The trade-off has to exist in the file**, or the whole design is an
    /// upgrade ladder with extra steps: something the colony can have early
    /// must carry more than a back and be *slower* than walking.
    @Test("The earliest conveyance costs speed for load")
    func theFirstOneIsATradeOff() throws {
        let registry = try GameDataRegistry.bundled()
        let early = registry.conveyances.values.filter { $0.era == .earlySettlement }
        #expect(!early.isEmpty, "a colony of twelve can have nothing at all")
        #expect(early.contains { $0.pace < 1 && $0.cargo > 1 },
                "nothing early trades pace for load, so the first choice is not a choice")
    }

    /// Terrain is what stops this being a straight upgrade. If every entry
    /// crosses everything, the map has no say.
    @Test("Something is stopped by the ground")
    func terrainMatters() throws {
        let registry = try GameDataRegistry.bundled()
        #expect(registry.conveyances.values.contains { !$0.terrain.isEmpty },
                "every conveyance crosses everything, so the map decides nothing")
        let cart = try #require(registry.conveyance("hand_cart"))
        #expect(!cart.canCross(.marsh), "a two-wheeled cart in a bog")
        #expect(cart.canCross(.dirt))
    }

    /// What a colony can actually reach right now — the list a build menu shows.
    @Test("Availability answers to era, building and tech")
    func availabilityIsGated() throws {
        let registry = try GameDataRegistry.bundled()
        let bare = registry.availableConveyances(
            era: .earlySettlement, standing: [], researched: [])
        #expect(bare.contains { $0.id == "travois" },
                "a colony with nothing standing can still lash two poles together")
        #expect(!bare.contains { $0.id == "hand_cart" },
                "a cart with no lumberyard")
        let later = registry.availableConveyances(
            era: .ancient, standing: ["lumberyard"], researched: [])
        #expect(later.contains { $0.id == "hand_cart" })
    }
}
