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
        "resting", "travelling", "expedition", "fighting", "hauling", "riding",
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
        // …and everything the yard can put somebody on, for the same reason: a
        // clip written for a cart is only ever asked for by a body on one.
        // Its own loop rather than another axis on the one above — the
        // conveyance arm answers before the trade, the building and the phase
        // are even looked at, so crossing it with them is a million asks for
        // one answer.
        for activity in Self.drawnActivities {
            for conveyance in registry.conveyances.keys.sorted().compactMap(registry.conveyance) {
                for work in WorkKind.allCases.map(\.rawValue) + [nil] {
                    for variant in UInt64(0)..<8 {
                        seen.insert(registry.motion(
                            activity: activity, work: work, variant: variant,
                            conveyance: conveyance).id)
                    }
                }
            }
        }
        // Activities the *content* declares and the app has not learned yet.
        // Written down rather than silently skipped, on the same reasoning as
        // rule 49's `new_fields`: a bypass that has to be typed out costs one
        // line and leaves a record of why, and this list failing to shrink is
        // itself the reminder.
        //
        // `riding` is step six of `docs/MOUNTS_AND_VEHICLES.md` — seven clips
        // were written for it ahead of the pose that will play them. Delete
        // this line when `AgentMotion.Activity` learns to ride, and the seven
        // become live content the same day.
        let awaiting: Set<String> = ["riding"]
        let unreachable = Set(registry.motions.keys).subtracting(seen)
            .subtracting(["standing"])
            .subtracting(registry.motions.values
                .filter { !Set($0.servesActivities).isDisjoint(with: awaiting) }
                .map(\.id))
        #expect(unreachable.isEmpty,
                "clips that load and can never be drawn: \(unreachable.sorted())")
        // …and the waiting list is real content, not a hole to hide things in.
        let waiting = registry.motions.values.count {
            !Set($0.servesActivities).isDisjoint(with: awaiting)
        }
        #expect(waiting <= 12, "the 'not drawn yet' list is being used as a bin")
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

    /// **The sweep above asks combinations the canvas can name. This one asks
    /// only the combinations the simulation can actually produce.**
    ///
    /// `everyClipIsSelectable` walks every trade against every building, so a
    /// clip written for a hunter's lodge and marked `crafting` comes back from
    /// it and looks alive. No crafter is ever posted to a lodge:
    /// `LaborEngine.staffBuildings` fills a bench only with the trade
    /// `ColonyBuilder.workKind(for:)` names, so the only ask the canvas will
    /// ever make about that room carries `hunting`. Fourteen of thirty-six
    /// freshly written clips were wrong this way, and the bank's own checker
    /// called them clean.
    @Test("A clip written for a building serves the trade posted there")
    func buildingClipsServeTheTradePostedThere() throws {
        let registry = try GameDataRegistry.bundled()
        for clip in registry.motions.values where !clip.servesBuildings.isEmpty {
            for id in clip.servesBuildings {
                guard let def = registry.building(id) else {
                    Issue.record("\(clip.id) names a building that does not exist: \(id)")
                    continue
                }
                let posted = ColonyBuilder.workKind(for: def)
                #expect(def.workers > 0 && posted != .idle,
                        "\(clip.id) is written for \(id), where nobody can be posted")
                #expect(clip.servesWork.contains(posted.rawValue),
                        "a clip names a building whose trade it does not serve")
            }
        }
    }

    /// The same hole one layer down, and the reason nine buildings were quietly
    /// broken: a building with benches and no trade to fill them.
    ///
    /// `workKind` answers `.idle`, `staffBuildings` gives it no room, and
    /// `ResourceLoop.staffingFactors` — which counts every building with
    /// `workers > 0` — pins it at `unstaffedFloor` for ever. Every energy
    /// building in the game ran at 40% of its stated output, permanently, with
    /// nothing the player could do about it.
    @Test("Every bench in the game has a trade that can stand at it")
    func everyBenchCanBeFilled() throws {
        let registry = try GameDataRegistry.bundled()
        for def in registry.buildings.values where def.workers > 0 {
            #expect(ColonyBuilder.workKind(for: def) != .idle,
                    "a building employs people and names no trade, so it is unstaffable")
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
        // A shop is not enough: a cart waits on the wheel, which is what makes
        // it something research *gives* you rather than something the calendar
        // hands over.
        let shopButIgnorant = registry.availableConveyances(
            era: .ancient, standing: ["lumberyard"], researched: [])
        #expect(!shopButIgnorant.contains { $0.id == "hand_cart" },
                "a cart built by a colony that has not invented the wheel")
        let later = registry.availableConveyances(
            era: .ancient, standing: ["lumberyard"], researched: ["the_wheel"])
        #expect(later.contains { $0.id == "hand_cart" })
    }
}

/// **Step two of `docs/MOUNTS_AND_VEHICLES.md`** — the yard: one can be made,
/// kept and lost. Nothing moves any faster yet; that is step three, and these
/// exist so that step has ground to stand on.
@Suite("The yard")
struct StableEngineTests {

    private func registry() throws -> GameDataRegistry { try .bundled() }

    private func colony(_ reg: GameDataRegistry, materials: [String: Int] = [:],
                        buildings: [String] = []) -> Settlement {
        var s = Settlement(
            id: UUID(uuidString: "0C0FFEE0-0000-0000-0000-000000000001")!,
            name: "Yardville", regionID: UUID())
        s.stockpile = materials
        for (i, id) in buildings.enumerated() {
            s.buildings.append(BuildingInstance(
                id: UUID(uuidString: "0C0FFEE0-0000-0000-0000-00000000000\(i + 2)")!,
                definitionID: id))
        }
        return s
    }

    /// The conveyances are tech-gated now — a cart waits on the wheel and a
    /// pack animal on husbandry — so a fixture that wants to build one has to
    /// know them. That gate is the point of the change; the tests follow it
    /// rather than working round it.
    private func world(_ s: Settlement, era: Era = .ancient,
                       knowing techs: Set<String> = ["husbandry", "the_wheel"]) -> WorldState {
        var w = WorldState(tick: 100, settlements: [s])
        w.era = era
        w.researchedTechs = techs
        return w
    }

    // MARK: - Making one

    @Test("A colony with the materials can lash a travois together")
    func theSimplestThingIsBuildable() throws {
        let reg = try registry()
        let s = colony(reg, materials: ["wood": 5, "hide": 2])
        let w = world(s, era: .earlySettlement)
        #expect(StableEngine.canBuild("travois", in: w, settlement: s, registry: reg))
        let after = StableEngine.build(s, definitionID: "travois", in: w, registry: reg)
        #expect(after.conveyances.count == 1)
        #expect(after.conveyances[0].definitionID == "travois")
        #expect(!after.conveyances[0].isMount, "a travois is not a beast")
        // …and it cost what it said it cost.
        #expect(after.stockpile["wood"] == 2)
        #expect(after.stockpile["hide"] == 1)
    }

    @Test("Without the materials, nothing is built")
    func poverty() throws {
        let reg = try registry()
        let s = colony(reg, materials: ["wood": 1])
        let w = world(s, era: .earlySettlement)
        #expect(!StableEngine.canBuild("travois", in: w, settlement: s, registry: reg))
        #expect(StableEngine.build(s, definitionID: "travois", in: w, registry: reg)
            .conveyances.isEmpty)
    }

    @Test("A cart wants its shop, and an age that has reached it")
    func gatesHold() throws {
        let reg = try registry()
        let rich = ["wood": 20, "iron_ingot": 4]
        let noShop = colony(reg, materials: rich)
        #expect(!StableEngine.canBuild("hand_cart", in: world(noShop),
                                       settlement: noShop, registry: reg),
                "a cart with no lumberyard")
        let shop = colony(reg, materials: rich, buildings: ["lumberyard"])
        #expect(StableEngine.canBuild("hand_cart", in: world(shop),
                                      settlement: shop, registry: reg))
        #expect(!StableEngine.canBuild("hand_cart", in: world(shop, era: .earlySettlement),
                                       settlement: shop, registry: reg),
                "an ancient cart in the first age")
        // …and the tech gate, which is what makes a conveyance a *reward* for
        // research rather than a thing that appears when the calendar turns.
        #expect(!StableEngine.canBuild("hand_cart", in: world(shop, knowing: []),
                                       settlement: shop, registry: reg),
                "a cart built by a colony that has not invented the wheel")
    }

    /// **You do not build a horse.** A mount needs a beast already gentled, and
    /// the same beast cannot be two mounts.
    @Test("A mount needs a free tamed beast of the right species")
    func mountsNeedABeast() throws {
        let reg = try registry()
        var s = colony(reg, materials: ["leather": 4, "wood": 4],
                       buildings: ["hunters_lodge"])
        let w = world(s)
        #expect(!StableEngine.canBuild("pack_elk", in: w, settlement: s, registry: reg),
                "an elk-less colony saddled an elk")

        let elk = Animal(id: UUID(uuidString: "0C0FFEE0-0000-0000-0000-0000000000E1")!,
                         species: .elk, sex: .male, age: 4 * 60,
                         position: LocalPoint(x: 0.5, y: 0.5))
        s.tamed = [TamedAnimal(animal: elk, role: .beastOfBurden, tamedTick: 1)]
        #expect(StableEngine.canBuild("pack_elk", in: w, settlement: s, registry: reg))

        let after = StableEngine.build(s, definitionID: "pack_elk", in: w, registry: reg)
        #expect(after.conveyances.count == 1)
        #expect(after.conveyances[0].animalID == elk.id, "the saddle is on no particular elk")
        #expect(after.tamed[0].role == .mount, "the beast is still down as a pack animal")
        // The one elk is spoken for.
        #expect(!StableEngine.canBuild("pack_elk", in: w, settlement: after, registry: reg),
                "the same elk was saddled twice")
    }

    /// Rule 3: the same colony building the same thing on the same tick must
    /// get the same id in every run, or the world drifts between launches.
    @Test("Ids are derived, not drawn")
    func idsAreStable() throws {
        let reg = try registry()
        let s = colony(reg, materials: ["wood": 9, "hide": 3])
        let w = world(s, era: .earlySettlement)
        let a = StableEngine.build(s, definitionID: "travois", in: w, registry: reg)
        let b = StableEngine.build(s, definitionID: "travois", in: w, registry: reg)
        #expect(a.conveyances[0].id == b.conveyances[0].id)
        // …and two built together are still two.
        let two = StableEngine.build(a, definitionID: "travois", in: w, registry: reg)
        #expect(two.conveyances.count == 2)
        #expect(two.conveyances[0].id != two.conveyances[1].id)
    }

    // MARK: - Keeping them

    @Test("A cart wears out and is eventually broken up")
    func cartsWearOut() throws {
        let reg = try registry()
        var s = StableEngine.build(colony(reg, materials: ["wood": 5, "hide": 2]),
                                   definitionID: "travois",
                                   in: world(colony(reg), era: .earlySettlement),
                                   registry: reg)
        let w = world(s, era: .earlySettlement)
        let before = s.conveyances[0].condition
        s = StableEngine.advanceOneTick(s, in: w, registry: reg)
        #expect(s.conveyances[0].condition < before, "a cart in use does not stay new")

        // Run it into the ground.
        for _ in 0..<(60 * 60) {
            s = StableEngine.advanceOneTick(s, in: w, registry: reg)
            if s.conveyances.isEmpty { break }
        }
        #expect(s.conveyances.isEmpty, "a travois lasted for ever")
    }

    /// A mount is its beast. When the beast is gone, so is the mount — and the
    /// saddle does not quietly go on carrying people.
    @Test("A mount whose beast has died is not a mount")
    func aMountIsItsBeast() throws {
        let reg = try registry()
        var s = colony(reg, materials: ["leather": 4, "wood": 4],
                       buildings: ["hunters_lodge"])
        let elk = Animal(id: UUID(uuidString: "0C0FFEE0-0000-0000-0000-0000000000E2")!,
                         species: .elk, sex: .male, age: 4 * 60,
                         position: LocalPoint(x: 0.5, y: 0.5))
        s.tamed = [TamedAnimal(animal: elk, role: .beastOfBurden, tamedTick: 1)]
        s = StableEngine.build(s, definitionID: "pack_elk", in: world(s), registry: reg)
        #expect(s.conveyances.count == 1)

        s.tamed[0].animal.health = 0
        s = StableEngine.advanceOneTick(s, in: world(s), registry: reg)
        #expect(s.conveyances.isEmpty, "the colony is still riding a dead elk")
    }

    /// A beast does not wear like an axle — its body already does that, and
    /// charging it twice would be paying for the same animal twice.
    @Test("A mount does not wear out")
    func mountsDoNotWear() throws {
        let reg = try registry()
        var s = colony(reg, materials: ["leather": 4, "wood": 4],
                       buildings: ["hunters_lodge"])
        let elk = Animal(id: UUID(uuidString: "0C0FFEE0-0000-0000-0000-0000000000E3")!,
                         species: .elk, sex: .male, age: 4 * 60,
                         position: LocalPoint(x: 0.5, y: 0.5))
        s.tamed = [TamedAnimal(animal: elk, role: .beastOfBurden, tamedTick: 1)]
        s = StableEngine.build(s, definitionID: "pack_elk", in: world(s), registry: reg)
        for _ in 0..<500 { s = StableEngine.advanceOneTick(s, in: world(s), registry: reg) }
        #expect(s.conveyances.count == 1)
        #expect(s.conveyances[0].condition == 1)
    }

    // MARK: - Reading the yard

    /// The numbers the four seams will multiply by. Written and tested before
    /// anything reads them, which is the whole ordering this document argues
    /// for.
    @Test("An empty yard is walking pace and no cargo")
    func anEmptyYardIsWalking() throws {
        let reg = try registry()
        let s = colony(reg)
        #expect(StableEngine.bestPace(s, registry: reg) == 1)
        #expect(StableEngine.bestRegionPace(s, registry: reg) == 1)
        #expect(StableEngine.cargoCapacity(s, registry: reg) == 0)
    }

    @Test("The yard's pace is its best, and its cargo is all of it")
    func theYardAddsUp() throws {
        let reg = try registry()
        var s = colony(reg, materials: ["wood": 30, "hide": 6, "iron_ingot": 4],
                       buildings: ["lumberyard"])
        let w = world(s)
        s = StableEngine.build(s, definitionID: "travois", in: w, registry: reg)
        s = StableEngine.build(s, definitionID: "hand_cart", in: w, registry: reg)
        #expect(s.conveyances.count == 2)
        let travois = try #require(reg.conveyance("travois"))
        let cart = try #require(reg.conveyance("hand_cart"))
        #expect(StableEngine.bestPace(s, registry: reg) == max(travois.pace, cart.pace))
        #expect(StableEngine.cargoCapacity(s, registry: reg) == travois.cargo + cart.cargo)
    }

    /// The ground has a say, which is the field that stops this being a ladder.
    @Test("A yard of carts cannot cross a bog")
    func theGroundHasASay() throws {
        let reg = try registry()
        var s = colony(reg, materials: ["wood": 10, "iron_ingot": 2],
                       buildings: ["lumberyard"])
        s = StableEngine.build(s, definitionID: "hand_cart", in: world(s), registry: reg)
        #expect(StableEngine.canCross(.dirt, s, registry: reg))
        #expect(!StableEngine.canCross(.marsh, s, registry: reg))
    }

    /// Rule 15: a steward left alone will buy for ever unless something says
    /// when to stop.
    @Test("The yard has a ceiling")
    func theYardIsNotInfinite() throws {
        let reg = try registry()
        var s = colony(reg, materials: ["wood": 1000, "hide": 400])
        let w = world(s, era: .earlySettlement)
        for _ in 0..<(StableEngine.yardLimit + 6) {
            s = StableEngine.build(s, definitionID: "travois", in: w, registry: reg)
        }
        #expect(s.conveyances.count == StableEngine.yardLimit)
    }

    // MARK: - Who is on it

    private func hauler(_ n: Int, walking: Bool = true) -> Pawn {
        var p = Pawn(
            id: UUID(uuidString: "0C0FFEE0-0000-0000-0000-000000000A0\(n)")!,
            name: "Carrier \(n)", assignedWork: .logging,
            age: 30 * 60)
        p.carrying = HaulLoad(itemID: "wood", amount: 3,
                              destination: LocalPoint(x: 0.5, y: 0.5))
        if walking {
            p.haulWalk = WalkPath(from: LocalPoint(x: 0.2, y: 0.2),
                                  to: LocalPoint(x: 0.5, y: 0.5),
                                  leftAt: 0, arrivesAt: 20)
        }
        return p
    }

    /// **Nobody rides anything the yard does not have.** The seams read the
    /// colony's best conveyance whether or not a soul is on it, so this is the
    /// first thing that makes one a *thing on the canvas* rather than a number.
    @Test("The yard goes under whoever is carrying something")
    func carriersGetTheCarts() throws {
        let reg = try registry()
        var s = colony(reg, materials: ["wood": 30, "hide": 10])
        let w = world(s, era: .earlySettlement)
        s = StableEngine.build(s, definitionID: "travois", in: w, registry: reg)
        s = StableEngine.build(s, definitionID: "travois", in: w, registry: reg)
        s.pawns = [hauler(1), hauler(2), hauler(3)]

        s = StableEngine.assignRiders(s, registry: reg)
        let riders = s.conveyances.compactMap(\.riderID)
        #expect(riders.count == 2, "two carts and three carriers is two riders")
        #expect(Set(riders).count == 2, "one person on two carts")
        #expect(StableEngine.conveyance(of: s.pawns[0].id, in: s) != nil)
    }

    /// …and lets go of them again. A cart that keeps a rider who has put the
    /// load down draws a colonist on a cart standing at a bench.
    @Test("A cart standing in the yard has nobody on it")
    func ridersAreReleased() throws {
        let reg = try registry()
        var s = colony(reg, materials: ["wood": 30, "hide": 10])
        s = StableEngine.build(s, definitionID: "travois",
                               in: world(s, era: .earlySettlement), registry: reg)
        s.pawns = [hauler(4)]
        s = StableEngine.assignRiders(s, registry: reg)
        #expect(s.conveyances[0].riderID != nil)

        s.pawns[0].carrying = nil
        s = StableEngine.assignRiders(s, registry: reg)
        #expect(s.conveyances[0].riderID == nil, "a cart still ridden by somebody empty-handed")
    }

    /// **The yard has to tick in a running game.** Everything above was built,
    /// tested and reachable from nowhere but these tests: `advanceOneTick` had
    /// no caller in the whole repository, so in play no cart ever wore out, no
    /// fuel was ever burned and no rider was ever seated. Rule 47, in the one
    /// system this document is about.
    @Test("A world advancing wears the yard out")
    func theYardTicksInPlay() throws {
        let reg = try registry()
        var settlement = colony(reg, materials: ["wood": 30, "hide": 10])
        settlement.pawns = [hauler(5)]
        var w = world(settlement, era: .earlySettlement)
        settlement = StableEngine.build(settlement, definitionID: "travois",
                                        in: w, registry: reg)
        w.settlements = [settlement]
        let before = try #require(w.settlements.first?.conveyances.first?.condition)

        let after = TickEngine.advance(w, ticks: 5, registry: reg).state
        let cart = try #require(after.settlements.first?.conveyances.first)
        #expect(cart.condition < before, "five ticks of a running world and nothing wore")
        #expect(cart.riderID != nil, "nobody was put on it by the tick")
    }

    // MARK: - What it burns

    /// **A machine burns a thing, not a number.** `upkeep` is the ledger — the
    /// five abstract resources, where `energy` means "the colony has power".
    /// A locomotive does not burn power, it burns *coal*, which somebody mined
    /// out of a seam and somebody hauled home, and that is a supply line the
    /// player can lose. Fourteen machines drew `energy` instead, and one of
    /// them — a maglev — ate a unit of food a tick.
    @Test("Every machine burns something real")
    func machinesBurnAThing() throws {
        let reg = try registry()
        let items = Set(reg.items.keys)
        for def in reg.conveyances.values
        where def.kind == .rail || def.kind == .motor || def.kind == .air {
            let fuel = def.materialUpkeep
            let grid = def.upkeep[.energy] > 0
            #expect(!fuel.isEmpty || grid,
                    "\(def.id) is a machine that runs on nothing at all")
            for (item, due) in fuel {
                #expect(items.contains(item),
                        "\(def.id) burns \(item), which is not a thing")
                #expect(due > 0, "\(def.id) burns nothing of \(item)")
            }
            #expect(def.upkeep[.food] == 0,
                    "\(def.id) eats food, and it has no mouth")
        }
    }

    /// …and there has to be a way to *get* it. A fuel nothing produces is the
    /// gear-in-a-ruin problem with the colony's whole industrial age attached.
    @Test("Every fuel can be got at")
    func everyFuelIsObtainable() throws {
        let reg = try registry()
        let cooked = Set(reg.recipes.values.map(\.outputItemID))
        let dug = Set(LocalResourceKind.allCases.compactMap(\.rawMaterialID))
        for def in reg.conveyances.values {
            for item in def.materialUpkeep.keys {
                #expect(cooked.contains(item) || dug.contains(item),
                        "\(def.id) burns \(item), which nothing makes and nothing digs")
            }
        }
    }

    /// The ground has to hold it, somewhere. Coal and oil are deliberately not
    /// everywhere — that is what makes the industrial ages a reason to settle a
    /// second valley — but "not everywhere" and "nowhere" are one typo apart.
    @Test("Some country holds coal, and some holds oil")
    func theGroundHoldsFuel() throws {
        let biomes = ["plains", "forest", "desert", "tundra", "mountains", "coast"]
        let mixes = biomes.map(LocalMapGenerator.depositMix(for:))
        #expect(mixes.contains { $0.coal > 0 }, "no valley in the world has coal")
        #expect(mixes.contains { $0.oilSeep > 0 }, "no valley in the world has oil")
    }

    /// A fuelled machine spends its fuel; an unfuelled one stands still. All of
    /// it or none of it — half a tank of coal does not half-run a locomotive,
    /// and taking the coal without moving the train is the worst of both.
    @Test("A locomotive spends coal, and stops without it")
    func fuelIsSpentOrTheThingStands() throws {
        let reg = try registry()
        // Whatever the bank's coal-burner is called today, rather than a name
        // written down here that a regenerated file can quietly invalidate.
        guard let burner = reg.conveyances.values
            .filter({ !$0.materialUpkeep.isEmpty })
            .min(by: { $0.id < $1.id })
        else { return }
        let (fuel, due) = try #require(burner.materialUpkeep.sorted { $0.key < $1.key }.first)

        var s = colony(reg)
        s.stockpile[fuel] = due * 3
        s.conveyances = [Conveyance(
            id: UUID(uuidString: "0C0FFEE0-0000-0000-0000-0000000000F1")!,
            definitionID: burner.id, condition: 1)]
        let w = world(s)

        s = StableEngine.advanceOneTick(s, in: w, registry: reg)
        #expect(s.stockpile[fuel] == due * 2, "it ran and paid for nothing")

        // Run it dry, then one more tick: nothing left is taken, and a machine
        // that is not driven does not wear either.
        s.stockpile[fuel] = 0
        let worn = try #require(s.conveyances.first?.condition)
        s = StableEngine.advanceOneTick(s, in: w, registry: reg)
        #expect(s.stockpile[fuel, default: 0] == 0, "it drank fuel it did not have")
        #expect(s.conveyances.first?.condition == worn,
                "a machine nobody could fuel still wore out")
    }
}

/// **Research that changes the valley rather than a menu.**
///
/// Counted before this existed: of fifty-four tech effects, thirty-nine
/// unlocked a building, five opened an event category, and all ten `modifier`
/// effects moved one of exactly two numbers — `knowledgeOutput` and
/// `influenceOutput`. So finishing a study gave you a new row in the build
/// menu, or research that produces more research. Keks: *"ať to není jen text,
/// ale ať to něco dělá."*
///
/// These are the tests that stop the new stats going the way of `texture` in
/// `ground.json` — validated, generated, and read by nothing (rule 52). Each
/// one runs the seam and checks the world moved.
@Suite("Research does something")
struct ResearchStatTests {

    private func world(_ modifiers: [ResearchStat: Double]) -> WorldState {
        var w = WorldState(tick: 0, settlements: [])
        for (stat, delta) in modifiers { w.statModifiers[stat.rawValue] = delta }
        return w
    }

    @Test("An unstudied colony is multiplied by one, everywhere")
    func nothingStudiedChangesNothing() {
        let bare = WorldState(tick: 0, settlements: [])
        for stat in ResearchStat.allCases where stat.kind == .factor {
            #expect(bare.researchFactor(stat) == 1,
                    "\(stat.rawValue) is not neutral before anything is studied")
        }
        for stat in ResearchStat.allCases where stat.kind == .addedToOutput {
            #expect(bare.researchBonus(stat) == 0)
        }
    }

    /// No stack of studies may drive a rate negative — "slower" and
    /// "backwards" are different words.
    @Test("A factor is floored, however much is stacked against it")
    func factorsAreFloored() {
        let w = world([.buildingWear: -50])
        #expect(w.researchFactor(.buildingWear) == ResearchStat.minimumFactor)
    }

    /// The two that always worked keep working, through the new vocabulary.
    @Test("Output bonuses are added, not multiplied")
    func outputsAreAdditive() {
        let w = world([.knowledgeOutput: 4])
        #expect(w.researchBonus(.knowledgeOutput) == 4)
        #expect(w.researchFactor(.knowledgeOutput) == 1, "an output is not a factor")
    }

    // MARK: - Each seam, run

    /// The seam the player would notice first: the same field, the same
    /// season, more on the ground.
    ///
    /// Run through a real founding colony rather than a hand-built plot,
    /// because `FarmEngine` only reaps ground a farm owns and a farmer has
    /// walked to — a fixture that skips either of those measures nothing and
    /// passes for the wrong reason.
    @Test("A studied colony gets more off the same fields")
    func cropYieldReachesTheGround() throws {
        let reg = try GameDataRegistry.bundled()
        let kinds = CookingEngine.foodstuffs(reg)

        func reaped(_ factor: Double) -> Int {
            var world = GameWorldFactory.newGame(registry: reg, seed: 4242)
            for tick in 1...900 {
                world.tick = tick
                world.settlements[0] = FarmEngine.advanceOneTick(
                    world.settlements[0], registry: reg, tick: tick, yieldFactor: factor)
                world.settlements[0] = HaulEngine.advanceStep(
                    world.settlements[0], registry: reg,
                    clock: WorldClock(tick: tick, step: 0))
            }
            let s = world.settlements[0]
            let onTheGround = s.localMap?.piles.reduce(0) { $0 + $1.amount } ?? 0
            return onTheGround + kinds.reduce(0) { $0 + s.stockpile[$1, default: 0] }
        }
        let plain = reaped(1)
        let studied = reaped(2.5)
        #expect(plain > 0, "this fixture reaped nothing at all — it measures nothing")
        #expect(studied > plain,
                "a richer yield put no more on the ground: \(studied) against \(plain)")
    }

    @Test("A studied colony raises a roof sooner")
    func buildSpeedReachesTheScaffold() throws {
        let reg = try GameDataRegistry.bundled()
        var s = Fixtures.world(population: 6).settlements[0]
        s.pawns = Fixtures.pawns(6, work: .building)
        s.constructions = [ConstructionProject(
            id: 1, definitionID: "hut", startedTick: 0, progress: 0, required: 500)]
        let plain = ConstructionEngine.advanceOneTick(s, registry: reg, tick: 1)
        let studied = ConstructionEngine.advanceOneTick(s, registry: reg, tick: 1,
                                                        speedFactor: 2)
        let a = plain.constructions.first?.progress ?? 0
        let b = studied.constructions.first?.progress ?? 0
        #expect(b > a, "twice the build speed did not raise the frame any faster")
    }

    @Test("A studied colony mends faster")
    func recoveryReachesTheBody() throws {
        let reg = try GameDataRegistry.bundled()
        var hurt = Fixtures.world(population: 4).settlements[0]
        for i in hurt.pawns.indices { hurt.pawns[i].health = 50 }
        let plain = PawnEngine.advanceOneTick(hurt, registry: reg, tick: 1)
        let studied = PawnEngine.advanceOneTick(hurt, registry: reg, tick: 1,
                                                recoveryFactor: 3)
        let a = plain.pawns.first?.health ?? 0
        let b = studied.pawns.first?.health ?? 0
        #expect(b > a, "three times the recovery healed nobody any faster")
    }

    // MARK: - The content actually uses it

    /// A stat nothing in `techs.json` ever grants is a stat the player can
    /// never have — the same fault from the content side.
    /// **The guard the file's own documentation promised and nobody wrote.**
    ///
    /// `ResearchStat` says "a test here fails if a case is never read by any
    /// engine". Every seam below is written by hand, which is a fine test and
    /// a bad *guarantee*: the next stat added is only covered if somebody
    /// remembers to add a test for it. This walks the engine sources instead,
    /// the way the app's string audit walks its views — a declared lever that
    /// nothing multiplies is a lie on the science screen.
    @Test("Every research stat is read by an engine, not merely declared")
    func everyStatHasASeam() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/EndlessFrontierCore")
        var sources: [String] = []
        let walk = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)
        while let url = walk?.nextObject() as? URL {
            guard url.pathExtension == "swift",
                  // Declaring a case is not reading it.
                  url.lastPathComponent != "ResearchStat.swift" else { continue }
            sources.append(try String(contentsOf: url, encoding: .utf8))
        }
        #expect(sources.count > 40, "found \(sources.count) engine sources — the path is wrong")

        for stat in ResearchStat.allCases {
            let read = sources.contains {
                $0.contains("researchFactor(.\(stat.rawValue))")
                    || $0.contains("researchBonus(.\(stat.rawValue))")
                    || $0.contains("research[.\(stat.rawValue)]")
            }
            #expect(read, """
                `\(stat.rawValue)` is declared and never read: a study that \
                moved it would change nothing, and the science screen would \
                say it had.
                """)
        }
    }

    /// The hunters' half of the food chain, which had no study touching it
    /// until the tree turned out to be exhausted by year seventy.
    @Test("A studied colony brings more home off the same kill")
    func huntYieldReachesTheTable() throws {
        let reg = try GameDataRegistry.bundled()
        func hunted(_ factor: Double) -> Double {
            var world = GameWorldFactory.newGame(registry: reg, seed: 4242)
            for index in world.settlements[0].pawns.indices {
                world.settlements[0].pawns[index].assignedWork = .hunting
            }
            world.settlements[0].storage[.food] = 0
            for tick in 1...400 {
                world.settlements[0] = WildlifeEngine.advanceOneTick(
                    world.settlements[0], registry: reg, tick: tick, era: .earlySettlement,
                    mapSeed: world.mapSeed, huntYield: factor)
            }
            return world.settlements[0].storage[.food]
        }
        let plain = hunted(1), studied = hunted(2)
        #expect(plain > 0, "nothing was hunted at all — this fixture measures nothing")
        #expect(studied > plain * 1.5, "\(studied) against \(plain)")
    }

    /// One pair of hands, one trip: what a study of yokes and barrows is worth.
    @Test("A studied colony carries more in one trip")
    func carryCapacityReachesTheLoad() throws {
        let reg = try GameDataRegistry.bundled()
        let world = GameWorldFactory.newGame(registry: reg, seed: 4242)
        let plain = HaulEngine.carryLimit(world.settlements[0], registry: reg)
        let studied = HaulEngine.carryLimit(world.settlements[0], registry: reg, learned: 2)
        #expect(studied > plain, "\(studied) against \(plain)")
        // …and a study that has not yet bought a whole armful buys nothing,
        // rather than a fraction of a log.
        #expect(HaulEngine.carryLimit(world.settlements[0], registry: reg, learned: 1.01) == plain)
    }

    /// Studied fortification: the same wall, worth more when they come.
    @Test("A studied colony's wall counts for more")
    func wallStrengthReachesTheDefence() throws {
        let reg = try GameDataRegistry.bundled()
        func defence(_ factor: Double) -> Double {
            var world = GameWorldFactory.newGame(registry: reg, seed: 4242)
            world.statModifiers[ResearchStat.wallStrength.rawValue] = factor - 1
            world.settlements[0].buildings.append(
                BuildingInstance(definitionID: "palisade", count: 2))
            for tick in 1...120 {
                world.tick = tick
                world = ResourceLoop.advanceOneTick(world, registry: reg)
            }
            return world.settlements[0].stats.defense
        }
        let plain = defence(1), studied = defence(2)
        #expect(plain > 0, "the fixture built no wall at all")
        #expect(studied > plain, "\(studied) against \(plain)")
    }

    /// The slowest-acting study in the game: nothing this year, everything in
    /// twenty.
    @Test("A studied colony gets good at its trades sooner")
    func trainingSpeedReachesTheSkill() throws {
        let reg = try GameDataRegistry.bundled()
        func skill(_ factor: Double) -> Int {
            var settlement = GameWorldFactory.newGame(registry: reg, seed: 4242).settlements[0]
            for index in settlement.pawns.indices {
                settlement.pawns[index].assignedWork = .logging
                settlement.pawns[index].skills[.logging] = 0
                settlement.pawns[index].skillXP[.logging] = 0
            }
            for tick in 1...600 {
                settlement = PawnEngine.advanceOneTick(
                    settlement, registry: reg, tick: tick,
                    gatheringFactors: [.logging: 1], trainingFactor: factor)
            }
            return settlement.pawns.reduce(0) { $0 + $1.skill(.logging) }
        }
        let plain = skill(1), studied = skill(3)
        #expect(studied > plain, "\(studied) against \(plain)")
    }

    @Test("Every research stat is granted by some tech")
    func everyStatIsGrantable() throws {
        let reg = try GameDataRegistry.bundled()
        var granted = Set<String>()
        for tech in reg.techs.values {
            for effect in tech.effects {
                if case let .modifier(stat, _, _) = effect {
                    granted.insert(stat.hasPrefix("global.")
                                   ? String(stat.dropFirst("global.".count)) : stat)
                }
            }
        }
        let ungranted = Set(ResearchStat.allCases.map(\.rawValue)).subtracting(granted)
        #expect(ungranted.isEmpty,
                "stats no tech ever grants: \(ungranted.sorted())")
    }

    /// …and the endless studies are not all about the library any more.
    @Test("Some study that never ends pays out in the valley")
    func theEndlessStudiesAreNotAllLibraries() throws {
        let reg = try GameDataRegistry.bundled()
        let worldFacing = reg.techs.values.filter { tech in
            guard tech.repeatable else { return false }
            return tech.effects.contains { effect in
                guard case let .modifier(stat, _, _) = effect else { return false }
                let name = stat.hasPrefix("global.")
                    ? String(stat.dropFirst("global.".count)) : stat
                return ResearchStat(rawValue: name)?.kind == .factor
            }
        }
        #expect(worldFacing.count >= 3,
                "every endless study still buys nothing but more studying")
    }
}

/// **Step three of `docs/MOUNTS_AND_VEHICLES.md`** — the yard is felt.
///
/// A conveyance that does not change one of these numbers is a picture of a
/// horse. Each of these runs the seam and checks the number moved.
@Suite("The yard is felt")
struct ConveyanceSeamTests {

    private func yard(_ reg: GameDataRegistry, _ ids: [String]) -> Settlement {
        var s = Settlement(id: UUID(uuidString: "0C0FFEE0-0000-0000-0000-00000000000F")!,
                           name: "Cartville", regionID: UUID())
        s.stockpile = ["wood": 200, "hide": 60, "iron_ingot": 40]
        s.buildings = [BuildingInstance(
            id: UUID(uuidString: "0C0FFEE0-0000-0000-0000-00000000001F")!,
            definitionID: "lumberyard")]
        var w = WorldState(tick: 10, settlements: [s])
        w.era = .ancient
        w.researchedTechs = ["husbandry", "the_wheel"]
        for id in ids { s = StableEngine.build(s, definitionID: id, in: w, registry: reg) }
        return s
    }

    /// **The seam the colony feels most**, because hauling is most of what it
    /// does: a load is an armful, and a cart makes the armful bigger.
    @Test("A load has a size, and the yard is what makes it bigger")
    func aLoadHasASize() throws {
        let reg = try GameDataRegistry.bundled()
        let bare = Settlement(id: UUID(uuidString: "0C0FFEE0-0000-0000-0000-00000000002F")!,
                              name: "Bare", regionID: UUID())
        #expect(HaulEngine.carryLimit(bare, registry: reg) == HaulEngine.armfuls,
                "a colony with no yard carries an armful and nothing more")

        let carted = yard(reg, ["hand_cart"])
        #expect(!carted.conveyances.isEmpty, "this fixture built nothing to measure")
        #expect(HaulEngine.carryLimit(carted, registry: reg)
                > HaulEngine.carryLimit(bare, registry: reg),
                "a cart in the yard did not make one trip worth any more")
    }

    /// …and the heap is not swallowed whole any more: what will not fit stays
    /// for the next trip, which is the pressure a cart is an answer to.
    @Test("What will not fit stays on the ground")
    func theRestIsLeftBehind() throws {
        let reg = try GameDataRegistry.bundled()
        var s = Settlement(id: UUID(uuidString: "0C0FFEE0-0000-0000-0000-00000000003F")!,
                           name: "Heaps", regionID: UUID())
        s.pawns = Fixtures.pawns(1, work: .logging)
        var map = LocalMapGenerator.generate(
            mapSeed: 7, regionID: s.id, biome: Fixtures.defaultBiomes[0])
        var dropRNG = SeededRNG(seed: 7)
        map = HaulEngine.drop(map, itemID: "wood",
                              amount: HaulEngine.armfuls * 5,
                              at: LocalPoint(x: 0.5, y: 0.5), tick: 0, rng: &dropRNG)
        s.localMap = map
        let before = s.localMap?.piles.reduce(0) { $0 + $1.amount } ?? 0
        for step in 0..<40 {
            s = HaulEngine.advanceStep(s, registry: reg,
                                       clock: WorldClock(tick: 1, step: step % 8))
        }
        let carried = s.pawns[0].carrying?.amount ?? 0
        #expect(before > 0, "this fixture dropped nothing to carry")
        #expect(carried <= HaulEngine.carryLimit(s, registry: reg),
                "one colonist walked off with the whole heap")
    }

    /// The two roads. `regionPace` is a *speed*, and both of these count ticks
    /// per distance — so they divide. One number, converted at each seam
    /// rather than copied (rule 34).
    @Test("A yard shortens the walk to a place of interest")
    func poiTravelReadsTheYard() {
        let far = LocalPoint(x: 0.95, y: 0.95)
        let onFoot = LocalPOIEngine.travelTicks(to: far)
        let mounted = LocalPOIEngine.travelTicks(to: far, pace: 2)
        #expect(mounted < onFoot, "twice the pace was the same walk")
        #expect(LocalPOIEngine.travelTicks(to: far, pace: 1) == onFoot,
                "a pace of one is not the walk it always was")
    }

    @Test("An empty yard changes nothing at all")
    func anEmptyYardIsNeutral() throws {
        let reg = try GameDataRegistry.bundled()
        let bare = Settlement(id: UUID(uuidString: "0C0FFEE0-0000-0000-0000-00000000004F")!,
                              name: "Bare", regionID: UUID())
        #expect(StableEngine.haulLift(bare, registry: reg) == 0)
        #expect(StableEngine.bestRegionPace(bare, registry: reg) == 1)
    }

    /// Rule 14's ceiling: a yard stacked to the limit is quicker, not instant.
    @Test("The yard's lift is capped")
    func theLiftIsCapped() throws {
        let reg = try GameDataRegistry.bundled()
        var s = yard(reg, [])
        s.stockpile = ["wood": 4000, "iron_ingot": 900]
        var w = WorldState(tick: 10, settlements: [s])
        w.era = .ancient
        w.researchedTechs = ["the_wheel"]
        for _ in 0..<StableEngine.yardLimit {
            s = StableEngine.build(s, definitionID: "hand_cart", in: w, registry: reg)
        }
        #expect(StableEngine.haulLift(s, registry: reg) <= StableEngine.maximumHaulLift)
    }
}

/// **Which way the world is.** A raid by the tribe to the north used to come
/// over the southern fence, and a trader from the eastern neighbour walked in
/// from the west — because the world map knew where everybody was and the local
/// map rolled a die.
@Suite("Arrivals come from where they live")
struct BearingTests {

    @Test("A neighbour due east is due east")
    func eastIsEast() {
        let home = HexCoord(0, 0)
        let angle = try! #require(Bearing.angle(from: home, toward: HexCoord(3, 0)))
        #expect(abs(angle) < 0.01, "a hex three to the east is not east")
        let entry = Bearing.edgePoint(along: angle)
        #expect(entry.x > 0.9, "they did not come in from the eastern edge")
        #expect(abs(entry.y - 0.5) < 0.2)
    }

    @Test("The opposite neighbour is the opposite edge")
    func oppositeSides() {
        let home = HexCoord(0, 0)
        let east = try! #require(Bearing.angle(from: home, toward: HexCoord(4, 0)))
        let west = try! #require(Bearing.angle(from: home, toward: HexCoord(-4, 0)))
        let a = Bearing.edgePoint(along: east), b = Bearing.edgePoint(along: west)
        #expect(a.x > 0.9 && b.x < 0.1, "east and west arrived on the same side")
    }

    @Test("Nowhere has no bearing, and the caller keeps its own roll")
    func sameHexHasNoBearing() {
        #expect(Bearing.angle(from: HexCoord(2, 2),
                              toward: HexCoord(2, 2)) == nil)
    }

    /// Every arrival lands *on* the map — an entry drawn outside the valley is
    /// a party the player never sees walking in.
    @Test("Every bearing lands inside the valley", arguments: 0..<24)
    func entriesAreOnTheMap(step: Int) {
        let angle = Double(step) / 24 * 2 * .pi
        for spread in [0.0, 0.5, 1.0] {
            let p = Bearing.edgePoint(along: angle, spread: spread)
            #expect(p.x >= 0.02 && p.x <= 0.98)
            #expect(p.y >= 0.02 && p.y <= 0.98)
        }
    }

    /// …and on the *edge*, not wandering into the middle of the town.
    @Test("An arrival starts at the rim", arguments: 0..<12)
    func entriesAreOnTheRim(step: Int) {
        let angle = Double(step) / 12 * 2 * .pi
        let p = Bearing.edgePoint(along: angle)
        let fromMiddle = max(abs(p.x - 0.5), abs(p.y - 0.5))
        #expect(fromMiddle > 0.35, "a party appeared in the middle of town")
    }
}

/// **Step five of `docs/MOUNTS_AND_VEHICLES.md`** — the ground has a say.
///
/// Without this every conveyance is strictly better than the last and the only
/// decision is whether you have unlocked it yet, which is not a decision. A
/// cart cannot take a bog; a pack animal can. That is what makes owning both
/// worth doing.
@Suite("The ground decides what can travel")
struct ConveyanceTerrainTests {

    @Test("A route knows what it crosses")
    func aRouteKnowsItsGround() throws {
        let map = LocalMapGenerator.generate(
            mapSeed: 21, regionID: UUID(), biome: Fixtures.defaultBiomes[0])
        let crossed = map.covers(from: LocalPoint(x: 0.05, y: 0.5),
                                 to: LocalPoint(x: 0.95, y: 0.5))
        #expect(!crossed.isEmpty, "a walk across the whole valley crossed nothing")
        // A point is the ground it stands on and nothing else.
        let here = LocalPoint(x: 0.5, y: 0.5)
        #expect(map.covers(from: here, to: here) == [map.cover(at: here)])
    }

    /// The decisive one: two conveyances, one route, and only one of them can
    /// make it.
    @Test("A cart is turned back by ground a pack animal takes")
    func theBogTurnsTheCartBack() throws {
        let reg = try GameDataRegistry.bundled()
        let onlyDry = ConveyanceDefinition(
            id: "dry_cart", name: LocalizedText(values: [.en: "Dry cart", .cs: "Suchý vůz"]),
            description: LocalizedText(values: [.en: "For dry roads", .cs: "Na suché cesty"]),
            era: .ancient, kind: .cart, pace: 3, regionPace: 3,
            terrain: [GroundCover.grass.rawValue])
        let anywhere = ConveyanceDefinition(
            id: "sure_foot", name: LocalizedText(values: [.en: "Sure foot", .cs: "Jistá noha"]),
            description: LocalizedText(values: [.en: "Goes anywhere", .cs: "Projde všude"]),
            era: .ancient, kind: .mount, pace: 2, regionPace: 2, terrain: [])
        #expect(onlyDry.canCross(.grass))
        #expect(!onlyDry.canCross(.marsh), "a dry cart forded a bog")
        #expect(anywhere.canCross(.marsh), "an empty terrain list means anywhere")
    }

    /// A country's character is what a road through it has to cross.
    @Test("Every biome has a dominant cover a road can be judged against")
    func everyBiomeHasCharacter() {
        for biome in ["forest", "desert", "tundra", "mountains", "coast", "plains"] {
            let cover = LocalTerrain.dominantCover(of: biome)
            #expect(cover != nil, "\(biome) has no dominant cover")
        }
        #expect(LocalTerrain.dominantCover(of: "desert") == .sand)
        #expect(LocalTerrain.dominantCover(of: "tundra") == .snow)
        #expect(LocalTerrain.dominantCover(of: "mountains") == .rock)
    }

    /// An empty yard is walking pace whatever the ground, and a yard that
    /// cannot make a trip is walking pace for *that trip* — never slower than
    /// feet, which are always available.
    @Test("Ground nothing can cross is walking pace, not a stop")
    func impassableGroundIsStillWalkable() throws {
        let reg = try GameDataRegistry.bundled()
        var s = Settlement(id: UUID(uuidString: "0C0FFEE0-0000-0000-0000-00000000005F")!,
                           name: "Boggy", regionID: UUID())
        s.localMap = LocalMapGenerator.generate(
            mapSeed: 5, regionID: s.id, biome: Fixtures.defaultBiomes[0])
        let pace = StableEngine.bestPace(s, from: LocalPoint(x: 0.1, y: 0.1),
                                         to: LocalPoint(x: 0.9, y: 0.9), registry: reg)
        #expect(pace == 1, "an empty yard is walking, and walking is never slower than walking")
    }

    /// The world map's version of the same question.
    @Test("A road through country a cart cannot take is walked")
    func theRoadReadsTheCountry() throws {
        let reg = try GameDataRegistry.bundled()
        var s = Settlement(id: UUID(uuidString: "0C0FFEE0-0000-0000-0000-00000000006F")!,
                           name: "Roads", regionID: UUID())
        s.stockpile = ["wood": 60, "iron_ingot": 12]
        s.buildings = [BuildingInstance(
            id: UUID(uuidString: "0C0FFEE0-0000-0000-0000-00000000007F")!,
            definitionID: "lumberyard")]
        var w = WorldState(tick: 5, settlements: [s])
        w.era = .ancient
        w.researchedTechs = ["the_wheel"]
        s = StableEngine.build(s, definitionID: "hand_cart", in: w, registry: reg)
        #expect(!s.conveyances.isEmpty, "this fixture built no cart to turn back")

        let cart = try #require(reg.conveyance("hand_cart"))
        let overPlains = StableEngine.bestRegionPace(s, crossing: ["plains"], registry: reg)
        #expect(overPlains == cart.regionPace || overPlains == 1,
                "a cart on the plains is either its own pace or walking, nothing else")
        // Whatever the cart's terrain list says, the answer is never *worse*
        // than feet — a journey it cannot make is one it does not join.
        for country in [["tundra"], ["coast"], ["mountains"], ["desert", "tundra"]] {
            #expect(StableEngine.bestRegionPace(s, crossing: country, registry: reg) >= 1)
        }
    }
}

/// **A fight lasts as long as the fight.**
///
/// Every siege used to run exactly `Siege.stepsTotal` — three bandits and a
/// tribe's whole warband took the same twenty-four steps. It could end early on
/// a break but never run long, so a big battle was cut off by the clock rather
/// than decided, and a colony one step from finishing somebody was told the
/// time was up. Keks: *"ať boje nemají pevné trvání, to je docela omezení."*
@Suite("A fight lasts as long as the fight")
struct SiegeLengthTests {

    @Test("A bigger assault runs longer")
    func sizeDecidesLength() {
        #expect(Siege.lengthFor(attackers: 4) < Siege.lengthFor(attackers: 30))
        #expect(Siege.lengthFor(attackers: 30) < Siege.lengthFor(attackers: 200))
    }

    /// Both ends bounded: a fight the player cannot react to is a number, and
    /// one that never ends is a bug wearing drama's coat.
    @Test("However big, a fight is neither a flicker nor a chore",
          arguments: [0, 1, 12, 200, 5000])
    func lengthIsBounded(attackers: Int) {
        let steps = Siege.lengthFor(attackers: attackers)
        #expect(steps >= Siege.stepsFloor)
        #expect(steps <= Siege.stepsCeiling)
    }

    /// **The defence must not lengthen the siege.** Counting defenders in the
    /// length made a well-manned town drag its own raid out, and a longer raid
    /// is more steps of plunder — so a town of sixty lost more stores to the
    /// same warband than a town of ten. Caught by `RampartTests`, and pinned
    /// here at the source.
    @Test("Holding the line does not make the raid last longer")
    func theDefenceDoesNotPayTheAttacker() {
        let small = Siege(
            id: UUID(uuidString: "51E6E000-0000-0000-0000-00000000000A")!,
            startTick: 0, openedAt: 0, attackerName: "Same warband",
            approach: 0, attackers: 60, openingStrength: 60, fortification: 0,
            seed: 9, line: (0..<5).map { _ in UUID() })
        let large = Siege(
            id: UUID(uuidString: "51E6E000-0000-0000-0000-00000000000B")!,
            startTick: 0, openedAt: 0, attackerName: "Same warband",
            approach: 0, attackers: 60, openingStrength: 60, fortification: 0,
            seed: 9, line: (0..<60).map { _ in UUID() })
        #expect(small.steps == large.steps,
                "the same warband fights longer against a bigger town")
    }

    /// The line delivers its weight once across the fight, whatever its length.
    /// That contract is what a per-step share *means*, and it broke the moment
    /// fights stopped all being the same size.
    @Test("A long fight does not land its line's weight three times over")
    func theWeightIsSpreadOverTheFight() {
        for steps in [Siege.stepsFloor, 24, 40, Siege.stepsCeiling] {
            let share = SiegeEngine.meleePerStep(steps: steps)
            let contactSteps = Double(steps - SiegeEngine.typicalApproachSteps)
            #expect(abs(share * contactSteps - 1) < 0.001,
                    "a \(steps)-step fight lands \(share * contactSteps) weights")
        }
    }

    /// A siege decides its length when the attack arrives and then keeps it —
    /// recomputing as the line thins would make a fight accelerate toward its
    /// own end.
    @Test("The length is fixed when the attack lands")
    func lengthIsDecidedOnce() {
        var siege = Siege(
            id: UUID(uuidString: "51E6E000-0000-0000-0000-000000000001")!,
            startTick: 0, openedAt: 0, attackerName: "Wolves",
            approach: 0, attackers: 40,
            openingStrength: 40, fortification: 0, seed: 1,
            line: (0..<30).map { _ in UUID() })
        let decided = siege.steps
        #expect(decided > Siege.stepsFloor, "forty on thirty is not a skirmish")
        siege.withdrawn = Set(siege.line.prefix(25))
        #expect(siege.steps == decided, "the fight got shorter as people fell")
    }

    /// …and a save from before this keeps the length it was actually fought at.
    @Test("An old save is still twenty-four steps")
    func oldSavesKeepTheirClock() throws {
        let siege = Siege(
            id: UUID(uuidString: "51E6E000-0000-0000-0000-000000000002")!,
            startTick: 0, openedAt: 0, attackerName: "Old",
            approach: 0, attackers: 6, openingStrength: 6, fortification: 0,
            seed: 2, line: [UUID()])
        var json = try JSONSerialization.jsonObject(
            with: JSONEncoder().encode(siege)) as! [String: Any]
        json.removeValue(forKey: "steps")
        let restored = try JSONDecoder().decode(
            Siege.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(restored.steps == Siege.stepsTotal)
    }

    /// Progress and the finish line both read the fight's own clock.
    @Test("Progress runs to one over the fight's own length")
    func progressReadsItsOwnClock() {
        var siege = Siege(
            id: UUID(uuidString: "51E6E000-0000-0000-0000-000000000003")!,
            startTick: 0, openedAt: 0, attackerName: "Host",
            approach: 0, attackers: 80, openingStrength: 80, fortification: 0,
            seed: 3, line: (0..<60).map { _ in UUID() })
        #expect(siege.steps > Siege.stepsFloor, "eighty attackers is not a skirmish")
        #expect(siege.progress == 0)
        #expect(!siege.isFinished)
        siege.advancedTo = siege.steps - 1
        #expect(siege.progress < 1, "the fight is over before its last step")
        #expect(!siege.isFinished)
        siege.advancedTo = siege.steps
        #expect(siege.progress == 1)
        #expect(siege.isFinished)
    }
}
