import Testing
import Foundation
@testable import EndlessFrontierCore

/// Keks: *"k banditům napiš, aby byli víc různorodí — třeba chodili ze
/// základen na mapě, co nejsou žádná frakce."*
///
/// The old bandits were weather: conjured out of nothing, sized off how full
/// your granary was, and gone without trace. What is being tested here is the
/// half that did not exist — that a raid comes **from a place**, that the
/// place pays for it, that what it takes goes somewhere a colony can go and
/// get, and that it is still not a faction.
@Suite("Outlaws with somewhere to come from")
struct OutlawTests {

    private func registry() throws -> GameDataRegistry { try GameDataRegistry.bundled() }

    /// A world as the factory makes it, which is the only place camps are
    /// founded.
    private func world(_ registry: GameDataRegistry, seed: UInt64 = 4242) -> WorldState {
        GameWorldFactory.newGame(registry: registry, seed: seed)
    }

    // MARK: - A camp is a place

    @Test("A new world has outlaws living in it")
    func campsAreFounded() throws {
        let registry = try registry()
        let state = world(registry)
        #expect(state.camps.count == OutlawCampEngine.foundingCamps)
        for camp in state.camps {
            let home = try #require(state.regions.first { $0.id == camp.regionID })
            #expect(home.kind == .outlawCamp, "a camp the map draws as ordinary country is not a place")
            #expect(home.coord.distance(to: .origin) >= OutlawCampEngine.minimumDistance)
            #expect(camp.strength > 0)
        }
    }

    @Test("Outlaws never take a people's ground, or a colony's")
    func campsDoNotCrowd() throws {
        let registry = try registry()
        let state = world(registry)
        let peoples = Set(state.tribes.map(\.regionID))
        let towns = Set(state.settlements.map(\.regionID))
        for camp in state.camps {
            #expect(!peoples.contains(camp.regionID))
            #expect(!towns.contains(camp.regionID))
        }
    }

    @Test("The same seed puts the same camps in the same hills")
    func campsAreDeterministic() throws {
        let registry = try registry()
        let a = world(registry, seed: 77), b = world(registry, seed: 77)
        #expect(a.camps == b.camps)
        let c = world(registry, seed: 78)
        #expect(a.camps.map(\.regionID) != c.camps.map(\.regionID)
                || a.camps.map(\.kind) != c.camps.map(\.kind),
                "two different worlds should not be the same country")
    }

    // MARK: - Variety is what a camp *is*

    @Test("What a camp is decides what it brings, not a name list")
    func kindsDiffer() {
        let deserters = OutlawCamp.Kind.deserters, starving = OutlawCamp.Kind.starving
        // Few and well armed against many and badly armed — the same strength,
        // a different fight.
        #expect(deserters.armsShift > starving.armsShift)
        #expect(deserters.bodyShare < starving.bodyShare)
        #expect(OutlawCamp.Kind.hold.walls > deserters.walls)
        #expect(starving.growthPerYear > deserters.growthPerYear)
    }

    @Test("Deserters fight with the arms of a later age than the starving do")
    func armsComeFromTheKind() {
        func camp(_ kind: OutlawCamp.Kind) -> OutlawCamp {
            OutlawCamp(id: UUID(), regionID: UUID(), kind: kind,
                       name: LocalizedText(values: [.en: "x", .cs: "x"]), strength: 30)
        }
        #expect(camp(.deserters).armsEra(in: .medieval) == .earlyIndustrial)
        #expect(camp(.starving).armsEra(in: .medieval) == .ancient)
        #expect(camp(.hold).armsEra(in: .medieval) == .medieval)
        // …and the ends of the road hold: nobody carries beam weapons in the
        // first year and nobody is disarmed below stones.
        #expect(camp(.starving).armsEra(in: .earlySettlement) == .earlySettlement)
        #expect(camp(.deserters).armsEra(in: .nearFuture) == .nearFuture)
    }

    @Test("A starving band is more bodies than deserters of the same weight")
    func bodiesComeFromTheKind() {
        func camp(_ kind: OutlawCamp.Kind) -> OutlawCamp {
            OutlawCamp(id: UUID(), regionID: UUID(), kind: kind,
                       name: LocalizedText(values: [.en: "x", .cs: "x"]), strength: 60)
        }
        #expect(camp(.starving).drawn(for: 60) > camp(.deserters).drawn(for: 60))
    }

    // MARK: - A raid is a thing a place did

    /// The rule the old bandits broke, and the reason a band of four attacked
    /// a colony of sixty-eight: the warband was sized off the granary.
    @Test("What arrives is the camp, not the granary")
    func strengthComesFromTheCamp() throws {
        let registry = try registry()
        var state = world(registry)
        var settlement = try #require(state.settlements.first)
        settlement.pawns = Fixtures.pawns(30)
        settlement.storage = [.food: 400, .materials: 300]
        settlement.storageCapacity = .uniform(500)
        state.settlements = [settlement]
        state.camps[0].strength = 200

        var rng = SeededRNG(seed: 5)
        let after = OutlawCampEngine.send(state, campIndex: 0, settlementIndex: 0,
                                          registry: registry, tick: 600, rng: &rng)
        let siege = try #require(after.settlements[0].siege)
        #expect(siege.openingStrength >= 200 * OutlawCampEngine.raidShare)
        #expect(siege.attackerCampID == state.camps[0].id)
        #expect(siege.attackerTribeID == nil, "outlaws are not a people")
        // …and the camp paid for it.
        #expect(after.camps[0].strength < state.camps[0].strength)
        #expect(after.camps[0].lastRaidTick == 600)
    }

    @Test("They walk in from where they live")
    func raidsArriveOnABearing() throws {
        let registry = try registry()
        var state = world(registry)
        var settlement = try #require(state.settlements.first)
        settlement.pawns = Fixtures.pawns(30)
        state.settlements = [settlement]
        let expected = try #require(Bearing.angle(fromRegion: settlement.regionID,
                                                  towardRegion: state.camps[0].regionID, in: state))
        var rng = SeededRNG(seed: 9)
        let after = OutlawCampEngine.send(state, campIndex: 0, settlementIndex: 0,
                                          registry: registry, tick: 600, rng: &rng)
        let siege = try #require(after.settlements[0].siege)
        // `SiegeEngine.begin` wobbles the bearing by up to a quarter radian so
        // two raids do not walk single file; the direction still has to be the
        // one the map says.
        #expect(abs(siege.approach - expected) < 0.3)
    }

    @Test("A raid says where it came from, in both languages")
    func theJournalNamesThePlace() throws {
        let registry = try registry()
        var state = world(registry)
        var settlement = try #require(state.settlements.first)
        settlement.pawns = Fixtures.pawns(30)
        state.settlements = [settlement]
        var rng = SeededRNG(seed: 3)
        let after = OutlawCampEngine.send(state, campIndex: 0, settlementIndex: 0,
                                          registry: registry, tick: 600, rng: &rng)
        let line = try #require(after.settlements[0].journal.entries.last)
        let region = try #require(state.regions.first { $0.id == state.camps[0].regionID })
        #expect(line.text.resolve(.en).contains(region.name))
        #expect(line.text.resolve(.cs).contains(region.name))
        #expect(line.text.resolve(.cs) != line.text.resolve(.en))
    }

    // MARK: - What they take is somewhere

    @Test("What got past the door is theirs, and what died at the wall is gone")
    func plunderFeedsTheCamp() throws {
        let registry = try registry()
        var state = world(registry)
        let camp = state.camps[0]
        state.camps[0].strength = 40
        let siege = Siege(
            id: UUID(), startTick: 0, openedAt: 0, attackerName: "x",
            attackerTribeID: nil, attackerCampID: camp.id,
            approach: 0, attackers: 6, openingStrength: 60, fortification: 0,
            seed: 1, line: [])
        var finished = siege
        finished.strength = 18          // what walked home
        finished.plundered = 50
        let after = OutlawCampEngine.charge(state, for: finished)
        #expect(after.camps[0].strength == 40 + 18)
        #expect(after.camps[0].loot.total == 50)
        #expect(after.camps[0].loot[.food] > after.camps[0].loot[.materials])
    }

    @Test("A camp nobody troubles gets stronger, and stops somewhere")
    func campsGrowAndAreBounded() throws {
        let registry = try registry()
        var state = world(registry)
        state.camps = [state.camps[0]]
        state.camps[0].strength = 10
        let kind = state.camps[0].kind
        var tick = 0
        for _ in 0..<(60 * 400 / OutlawCampEngine.interval) {
            tick += OutlawCampEngine.interval
            state.tick = tick
            state = OutlawCampEngine.advanceOneTick(state, registry: registry, tick: tick)
        }
        #expect(state.camps[0].strength > 10, "a camp left alone for four centuries should have grown")
        // Bounded — but the bound includes what the country around them is
        // worth (`ceilingPerSoul`), or a camp is scenery by year sixty.
        let souls = Double(state.settlements.map(\.pawns.count).max() ?? 0)
        let ceiling = kind.foundingStrength * OutlawCampEngine.ceilingMultiple
            + souls * OutlawCampEngine.ceilingPerSoul
        #expect(state.camps[0].strength <= ceiling + 1,
                "an unbounded camp is a colony-killer by year two hundred")
    }

    /// The fault two centuries of measurement found: a camp's ceiling was its
    /// own founding strength and nothing else, so from year sixty on every
    /// camp sat pinned at twenty-six men beside a colony of two hundred and
    /// sixty-one. That is not a threat, it is scenery.
    @Test("A camp beside a great colony grows past one beside a hamlet")
    func campsGrowWithTheCountryTheyLiveOff() throws {
        let registry = try registry()
        func grown(colony: Int) throws -> Double {
            var state = world(registry)
            state.camps = [state.camps[0]]
            state.camps[0].strength = 10
            var settlement = try #require(state.settlements.first)
            settlement.pawns = Fixtures.pawns(colony)
            settlement.storage = [.food: 0]        // nothing worth walking for
            state.settlements = [settlement]
            var tick = 0
            for _ in 0..<(60 * 120 / OutlawCampEngine.interval) {
                tick += OutlawCampEngine.interval
                state.tick = tick
                state = OutlawCampEngine.advanceOneTick(state, registry: registry, tick: tick)
            }
            return state.camps[0].strength
        }
        let beside = try grown(colony: 260)
        let hamlet = try grown(colony: 10)
        #expect(beside > hamlet + 40,
                "\(Int(beside)) against \(Int(hamlet)): the hills fill up out of the same country")
    }

    @Test("A camp lying low neither raids nor grows")
    func brokenCampsRest() throws {
        let registry = try registry()
        var state = world(registry)
        for index in state.camps.indices {
            state.camps[index].brokenUntil = 5_000
            state.camps[index].strength = 20
        }
        state.tick = 1_000
        let after = OutlawCampEngine.advanceOneTick(state, registry: registry,
                                                    tick: OutlawCampEngine.interval * 50)
        #expect(after.camps.allSatisfy { $0.strength == 20 }, "a camp lying low does not fatten")
        #expect(OutlawCampEngine.nearestCamp(to: try #require(state.settlements.first),
                                             in: state, at: 1_000) == nil,
                "…and nobody walks out of it either")
        // …and it is up again on the far side of the season.
        #expect(OutlawCampEngine.nearestCamp(to: try #require(state.settlements.first),
                                             in: state, at: 5_000) != nil)
    }

    // MARK: - Burning them out

    /// A camp is laid out in the vocabulary the party system already speaks:
    /// the outlaws are guardians, their hoard is a cache, a fence is a trap.
    /// Nothing here is a second combat system.
    @Test("A camp is a place a party can walk into")
    func campsLayOutAsAPlace() throws {
        let registry = try registry()
        var state = world(registry)
        state.camps[0].kind = .hold
        state.camps[0].strength = 60
        let party = Fixtures.pawns(4).map(\.id)
        let site = OutlawCampEngine.encounter(for: state.camps[0], party: party,
                                              at: 0, seed: 7)
        let guardians = site.things.filter { $0.kind == .guardian }
        #expect(!guardians.isEmpty)
        #expect(abs(guardians.reduce(0) { $0 + $1.strength } - 60) < 60 * 0.35,
                "the fight is the camp's own strength, not a table")
        #expect(site.things.contains { $0.kind == .cache })
        #expect(site.things.contains { $0.kind == .trap }, "a hold has a fence")
        #expect(site.places.count == party.count)
        // …and a starving camp of the same weight is more of them.
        var hungry = state.camps[0]
        hungry.kind = .starving
        let crowd = OutlawCampEngine.encounter(for: hungry, party: party, at: 0, seed: 7)
        #expect(crowd.things.count { $0.kind == .guardian } > guardians.count)
    }

    @Test("A camp burned out last season is found cold")
    func brokenCampsAreEmpty() throws {
        let registry = try registry()
        var state = world(registry)
        state.camps[0].brokenUntil = 5_000
        let site = OutlawCampEngine.encounter(for: state.camps[0], party: [], at: 1_000, seed: 7)
        #expect(!site.things.contains { $0.kind == .guardian })
    }

    @Test("A party that breaks a camp brings its plunder home")
    func sackingReturnsTheLoot() throws {
        let registry = try registry()
        var state = world(registry)
        state.camps[0].strength = 40
        state.camps[0].loot = Resources([.food: 120, .materials: 80])
        let before = state.settlements[0].storage[.food]
        let (after, clearing) = OutlawCampEngine.sacked(
            state, regionID: state.camps[0].regionID, settlementIndex: 0, share: 1)
        let done = try #require(clearing)
        #expect(done.broken)
        #expect(done.recovered.total == 200)
        #expect(after.settlements[0].storage[.food] == before + 120)
        #expect(after.camps[0].loot.total == 0)
        #expect(after.camps[0].brokenUntil == state.tick + OutlawCampEngine.brokenForTicks)
    }

    /// Getting in and having to leave again is a real outcome, and it must not
    /// read as a victory: they keep most of what they hold and they are still
    /// there next season.
    @Test("A party that only bloodied them takes only what it cleared")
    func aHalfSackIsHalfPaid() throws {
        let registry = try registry()
        var state = world(registry)
        state.camps[0].strength = 40
        state.camps[0].loot = Resources([.food: 100])
        let (after, clearing) = OutlawCampEngine.sacked(
            state, regionID: state.camps[0].regionID, settlementIndex: 0, share: 0.4)
        let done = try #require(clearing)
        #expect(!done.broken)
        #expect(abs(done.recovered.total - 40) < 0.001)
        #expect(abs(after.camps[0].loot.total - 60) < 0.001)
        #expect(after.camps[0].brokenUntil == nil, "they are still there")
    }

    @Test("A camp is broken, never abolished")
    func clearingIsNotForEver() throws {
        let registry = try registry()
        var state = world(registry)
        let (cleared, _) = OutlawCampEngine.sacked(
            state, regionID: state.camps[0].regionID, settlementIndex: 0, share: 1)
        #expect(cleared.camps.count == state.camps.count,
                "a country with no outlaws left in it has nothing left to do in it")
        #expect(!cleared.camps[0].isActive(at: cleared.tick))
        #expect(cleared.camps[0].isActive(at: cleared.tick + OutlawCampEngine.brokenForTicks))
    }

    /// The whole loop, end to end: they take your grain, it is *theirs*, you
    /// walk out and take it back.
    @Test("What a raid carried off is what a sack brings home")
    func theLoopCloses() throws {
        let registry = try registry()
        var state = world(registry)
        var finished = Siege(
            id: UUID(), startTick: 0, openedAt: 0, attackerName: "x",
            attackerTribeID: nil, attackerCampID: state.camps[0].id,
            approach: 0, attackers: 6, openingStrength: 60, fortification: 0,
            seed: 1, line: [])
        finished.strength = 10
        finished.plundered = 200
        state = OutlawCampEngine.charge(state, for: finished)
        #expect(state.camps[0].loot.total == 200)
        let before = state.settlements[0].storage.total
        let (after, _) = OutlawCampEngine.sacked(
            state, regionID: state.camps[0].regionID, settlementIndex: 0, share: 1)
        #expect(abs(after.settlements[0].storage.total - (before + 200)) < 0.001)
    }

    // MARK: - The lines that must not be crossed

    @Test("A camp is not a people")
    func campsAreNotTribes() throws {
        let registry = try registry()
        var state = world(registry)
        let before = state.tribes
        var rng = SeededRNG(seed: 11)
        var settlement = try #require(state.settlements.first)
        settlement.pawns = Fixtures.pawns(30)
        state.settlements = [settlement]
        let after = OutlawCampEngine.send(state, campIndex: 0, settlementIndex: 0,
                                          registry: registry, tick: 600, rng: &rng)
        #expect(after.tribes == before, "outlaws must have no standing to change")
        let siege = try #require(after.settlements[0].siege)
        // The tribe-charging path must not touch a camp's raid either.
        #expect(SiegeEngine.chargeAttacker(after, for: siege).tribes == before)
    }

    @Test("Outlaws survive being saved")
    func campsRoundTrip() throws {
        let registry = try registry()
        var state = world(registry)
        state.camps[0].loot = Resources([.food: 42])
        state.camps[0].brokenUntil = 900
        let back = try JSONDecoder().decode(
            WorldState.self, from: try JSONEncoder().encode(state))
        #expect(back.camps == state.camps)
    }

    @Test("A world saved before the outlaws had homes still loads")
    func oldSavesLoad() throws {
        let json = """
        {"schemaVersion":4,"tick":10,"settlements":[],"regions":[]}
        """
        let back = try JSONDecoder().decode(WorldState.self, from: Data(json.utf8))
        #expect(back.camps.isEmpty)
    }

    /// Both paths firing on the same check would rob a colony twice, by the
    /// same people, from two directions.
    @Test("A world with camps does not also conjure bands out of nothing")
    func onlyOnePathRaids() throws {
        let registry = try registry()
        var settlement = Settlement(name: "Test", pawns: Fixtures.pawns(30))
        settlement.storage = [.food: 900, .materials: 900]
        settlement.storageCapacity = .uniform(1000)
        // A thousand checks with the granary full: with a camp in the world,
        // this path must never open a siege.
        for step in 1...1000 {
            let after = ResourceLoop.advanceSettlement(
                settlement, registry: registry, config: registry.config,
                tick: step * BanditEngine.interval, mapSeed: 99, hasOutlawCamps: true)
            #expect(after.siege == nil)
        }
    }
}

/// Rule 23 — print the distribution before setting a threshold against it.
/// Run with `EF_DIAG=1 swift test --package-path Core --filter ZZOutlawDiag`.
@Suite("outlaw diag", .enabled(if: ProcessInfo.processInfo.environment["EF_DIAG"] != nil, "diag"))
struct ZZOutlawDiag {

    @Test("two centuries of living next door to outlaws")
    func twoCenturies() throws {
        let registry = try GameDataRegistry.bundled()
        var state = GameWorldFactory.newGame(registry: registry, seed: 4242)
        var raids = Set<UUID>()
        var fromCamps = Set<UUID>()
        var fromPeoples = Set<UUID>()
        // A people's warband is named for the people; a camp is known by id.
        var peopleNames = Set<String>()
        var plundered = 0.0   // what the camps are holding, all told
        var strongest = 0.0

        print("""

        ── outlaws ────────────────────────────────────────────────────
        year | camps                                   | raids | taken
        """)
        for step in 0..<240 {
            state = BalanceHarness.autoPlay(state, registry: registry)
            state = TickEngine.advance(state, ticks: 50, registry: registry).state
            for people in state.tribes { peopleNames.insert(people.name) }
            guard let capital = state.settlements.first else { continue }
            // **Counted off the record, not off the live siege.** Sampling
            // `capital.siege` once every fifty ticks only sees the fights that
            // happen to be running at that instant — measured, that reported
            // fourteen raids in two centuries and made the long fights (a
            // people's warband) look like all of them. `battleHistory` keeps
            // what actually happened.
            for log in capital.battleHistory where raids.insert(log.id).inserted {
                if log.attackerCampID != nil { fromCamps.insert(log.id) }
                else if peopleNames.contains(log.attackerName) { fromPeoples.insert(log.id) }
            }
            // What they carried off, counted where it lands: a camp's loot is
            // the only ledger of it that survives the fight.
            plundered = state.camps.reduce(0) { $0 + $1.loot.total }
            strongest = max(strongest, state.camps.map(\.strength).max() ?? 0)
            if step % 24 == 0 {
                let camps = state.camps.map {
                    "\($0.kind.rawValue.prefix(4)) \(Int($0.strength))/\(Int($0.loot.total))"
                }.joined(separator: "  ")
                print(String(format: "%4d | %-38@ | %5d | %5d",
                             step * 50 / registry.config.ticksPerYear, camps,
                             raids.count, Int(plundered)))
            }
        }
        let capital = try #require(state.settlements.first)
        print("""
        ───────────────────────────────────────────────────────────────
        raids \(raids.count) — camps \(fromCamps.count), peoples \(fromPeoples.count), \
        the wild \(raids.count - fromCamps.count - fromPeoples.count)
        strongest camp ever \(Int(strongest))
        camps now  \(state.camps.map { "\($0.kind.rawValue) \(Int($0.strength)) loot \(Int($0.loot.total))" })
        colony     \(capital.pawns.count) souls, \(Int(capital.storage[.food])) food, \
        defense \(Int(capital.stats.defense))
        ───────────────────────────────────────────────────────────────

        """)
    }
}
