import Testing
import Foundation
@testable import EndlessFrontierCore

/// A raid you can stand in the middle of.
///
/// The properties here are the ones that make a *live* battle safe to put in a
/// deterministic, offline-first game, and each of them has an obvious way to
/// break silently:
///
/// - a step fought twice (the app and the world clock both reaching it),
/// - a step never fought at all (the player closed the app),
/// - an outcome that depends on *when* it was asked for rather than on what
///   happened,
/// - orders that change the fight but are not saved, so a reload rewrites
///   history.
@Suite("A raid you fight")
struct SiegeTests {

    private func registry() throws -> GameDataRegistry { try GameDataRegistry.bundled() }

    /// A colony with a wall and some people in it. Fixed ids throughout —
    /// per-entity randomness is seeded from them, and a `UUID()` here would
    /// make every run a different fight (CLAUDE.md rule 3).
    private func colony(pawns: Int = 8, defense: Double = 20) -> Settlement {
        var s = Settlement(
            id: UUID(uuidString: "5E1E6E00-0000-0000-0000-000000000001")!,
            name: "Hold",
            storage: [.food: 1000], storageCapacity: 2000,
            stats: SettlementStats(defense: defense))
        for i in 0..<pawns {
            var p = Pawn(
                id: UUID(uuidString: String(format: "5E1E6E00-0000-0000-0000-%012d", i + 10))!,
                name: "Hand \(i)")
            p.age = 25 * 60
            s.pawns.append(p)
        }
        return s
    }

    private func besieged(
        _ s: Settlement, strength: Double = 40, tick: Int = 100,
        tribeID: UUID? = nil
    ) throws -> Settlement {
        try SiegeEngine.begin(
            s, attackerStrength: strength, attackerName: "The Ashfolk",
            attackerTribeID: tribeID,
            fortification: s.stats.defense, tick: tick,
            registry: registry(), seed: 0xBEEF)
    }

    /// How far the world clock has to run for a siege opened on `tick` to be
    /// carried to its end.
    private func endStep(of siege: Siege) -> Int {
        siege.openedAt + Siege.stepsTotal
    }

    // MARK: - It is actually live

    @Test("A raid opens as a fight in progress, not as a result")
    func raidOpensLive() throws {
        let s = try besieged(colony())
        let siege = try #require(s.siege)
        #expect(s.lastBattle == nil, "nothing has been decided yet")
        #expect(siege.step == 0)
        #expect(!siege.isFinished)
        #expect(siege.strength == siege.openingStrength)
        #expect(!siege.line.isEmpty, "somebody turned out")
    }

    @Test("Nobody is hurt while they are still crossing the ground")
    func approachHurtsNobody() throws {
        var s = try besieged(colony())
        let opened = try #require(s.siege).openedAt
        s = SiegeEngine.advance(s, to: opened + SiegeEngine.approachSteps - 1,
                                registry: try registry())
        #expect(s.pawns.allSatisfy { $0.health >= 100 })
        let siege = try #require(s.siege)
        #expect(siege.moments.contains { $0.kind == .charge }, "they arrived")
    }

    @Test("A siege carried to its end settles and leaves a record")
    func siegeConcludes() throws {
        var s = try besieged(colony())
        let siege = try #require(s.siege)
        s = SiegeEngine.advance(s, to: endStep(of: siege), registry: try registry())
        #expect(s.siege == nil, "the fighting is over")
        let log = try #require(s.lastBattle)
        #expect(log.id == siege.id, "the record is *this* fight")
        #expect(!log.moments.isEmpty)
        #expect(log.attackers > 0)
    }

    // MARK: - A step is fought once

    /// The contract that makes it safe for two clocks to drive one fight. If a
    /// step could be fought twice the app being open would make raids twice as
    /// deadly, and nobody would ever be able to see it happening.
    @Test("A step already fought is never fought again")
    func stepsAreNotFoughtTwice() throws {
        let reg = try registry()
        var once = try besieged(colony())
        let opened = try #require(once.siege).openedAt

        // Straight through in one call…
        once = SiegeEngine.advance(once, to: opened + 12, registry: reg)

        // …versus a call for every step, and then a redundant one that asks
        // again for ground already covered.
        var stepwise = try besieged(colony())
        for step in 1...12 {
            stepwise = SiegeEngine.advance(stepwise, to: opened + step, registry: reg)
        }
        stepwise = SiegeEngine.advance(stepwise, to: opened + 5, registry: reg)
        stepwise = SiegeEngine.advance(stepwise, to: opened + 12, registry: reg)

        let a = try #require(once.siege), b = try #require(stepwise.siege)
        #expect(a.step == b.step)
        #expect(abs(a.strength - b.strength) < 1e-9)
        #expect(a.damage == b.damage)
        #expect(once.pawns.map(\.health) == stepwise.pawns.map(\.health))
    }

    /// The player being *fast* must not change the fight — only their orders
    /// may. This is the same property from the other side: whoever reaches a
    /// step first, the step is the same step.
    @Test("Driving it quickly and driving it slowly give the same fight")
    func pacingDoesNotChangeTheOutcome() throws {
        let reg = try registry()
        var fast = try besieged(colony())
        var slow = try besieged(colony())
        let opened = try #require(fast.siege).openedAt
        let end = opened + Siege.stepsTotal

        fast = SiegeEngine.advance(fast, to: end, registry: reg)
        for step in stride(from: opened + 1, through: end, by: 1) {
            slow = SiegeEngine.advance(slow, to: step, registry: reg)
        }
        #expect(fast.lastBattle?.repelled == slow.lastBattle?.repelled)
        #expect(fast.pawns.map(\.health) == slow.pawns.map(\.health))
        #expect(fast.pawns.count == slow.pawns.count)
    }

    // MARK: - Leaving is allowed

    /// Backgrounding the app mid-raid must be neither a tactic nor a
    /// punishment: the world clock walks over the siege and finishes it.
    @Test("A raid nobody watched still gets fought")
    func unwatchedRaidResolves() throws {
        let reg = try registry()
        var world = WorldState(mapSeed: 7)
        world.tick = 100
        world.settlements = [try besieged(colony())]

        // Four world ticks of the ordinary loop, with nobody steering.
        for tick in 100..<104 {
            for step in 0..<WorldClock.actionStepsPerTick {
                world = ActionLoop.advanceStep(
                    world, clock: WorldClock(tick: tick, step: step), registry: reg)
            }
        }
        #expect(world.settlements[0].siege == nil, "it was fought without us")
        #expect(world.settlements[0].lastBattle != nil)
    }

    // MARK: - Orders are inputs, not exceptions

    @Test("The same fight with the same orders kills the same people")
    func ordersReplayIdentically() throws {
        let reg = try registry()
        func run(_ posture: Siege.Posture) throws -> Settlement {
            var s = try besieged(colony())
            s = SiegeEngine.order(s, posture: posture)
            let opened = try #require(s.siege).openedAt
            return SiegeEngine.advance(s, to: opened + Siege.stepsTotal, registry: reg)
        }
        let a = try run(.press), b = try run(.press)
        #expect(a.pawns.map(\.health) == b.pawns.map(\.health))
        #expect(a.lastBattle?.repelled == b.lastBattle?.repelled)
    }

    /// The whole reason to have a posture: it has to *do* something, and the
    /// thing it does has to cost something. Named for the trade, not the
    /// mechanic (rule 6) — a lever the player cannot feel is not a lever.
    @Test("Pressing them breaks the attack faster and costs more blood")
    func pressingIsATrade() throws {
        let reg = try registry()
        func run(_ posture: Siege.Posture) throws -> (Settlement, Siege) {
            var s = try besieged(colony(), strength: 60)
            s = SiegeEngine.order(s, posture: posture)
            let siege = try #require(s.siege)
            let out = SiegeEngine.advance(s, to: siege.openedAt + 14, registry: reg)
            return (out, try #require(out.siege ?? siege))
        }
        let (pressed, pressedSiege) = try run(.press)
        let (held, heldSiege) = try run(.hold)

        #expect(pressedSiege.strength < heldSiege.strength,
                "pressing has to actually break them faster")
        let pressedHurt = pressed.pawns.reduce(0.0) { $0 + (100 - $1.health) }
        let heldHurt = held.pawns.reduce(0.0) { $0 + (100 - $1.health) }
        #expect(pressedHurt > heldHurt, "and it has to cost")
    }

    @Test("Giving ground saves people and empties the granary")
    func givingGroundIsATrade() throws {
        let reg = try registry()
        func run(_ posture: Siege.Posture) throws -> Settlement {
            var s = try besieged(colony(), strength: 60)
            s = SiegeEngine.order(s, posture: posture)
            let opened = try #require(s.siege).openedAt
            return SiegeEngine.advance(s, to: opened + 14, registry: reg)
        }
        let gave = try run(.giveGround)
        let held = try run(.hold)

        let gaveHurt = gave.pawns.reduce(0.0) { $0 + (100 - $1.health) }
        let heldHurt = held.pawns.reduce(0.0) { $0 + (100 - $1.health) }
        #expect(gaveHurt < heldHurt, "nobody dies for grain")
        #expect(gave.storage[.food] < held.storage[.food], "…and the grain goes")
    }

    /// The flat-subtraction bug in armour. A wall that soaks `defense × k` off
    /// every blow has a height above which an attack simply cannot land, and
    /// a colony past it is invulnerable rather than well defended.
    @Test("No wall makes a raid harmless, however high it is built")
    func wallNeverCancelsAnAttack() throws {
        for defense in [0.0, 10, 25, 60, 200, 10_000] {
            let share = SiegeEngine.wallShare(fortification: defense, cover: 1)
            #expect(share >= 0 && share <= SiegeEngine.fortificationCeiling)
            #expect(share < 1, "a wall of \(defense) turned an attack off entirely")
        }
        // …and it has to be worth building.
        #expect(SiegeEngine.wallShare(fortification: 40, cover: 1)
                > SiegeEngine.wallShare(fortification: 10, cover: 1))

        // A well-walled colony still bleeds when a real warband arrives.
        let reg = try registry()
        var s = try besieged(colony(defense: 60), strength: 90)
        let opened = try #require(s.siege).openedAt
        s = SiegeEngine.advance(s, to: opened + Siege.stepsTotal, registry: reg)
        #expect(s.pawns.contains { $0.health < 100 } || s.pawns.count < 8,
                "ninety raiders against a wall of sixty and not a scratch")
    }

    @Test("Pulling somebody out takes them out of the line of fire")
    func withdrawingProtects() throws {
        let reg = try registry()
        var s = try besieged(colony(), strength: 60)
        let siege = try #require(s.siege)
        let first = try #require(siege.line.first)

        s = SiegeEngine.withdraw(s, pawnID: first)
        #expect(try #require(s.siege).withdrawn.contains(first))
        s = SiegeEngine.advance(s, to: siege.openedAt + 16, registry: reg)

        let pulled = s.pawns.first { $0.id == first }
        #expect(pulled?.health == 100, "somebody who left the wall is not hit at it")
    }

    @Test("Somebody who has been pulled out can be sent back")
    func withdrawIsReversible() throws {
        var s = try besieged(colony())
        let first = try #require(s.siege?.line.first)
        s = SiegeEngine.withdraw(s, pawnID: first)
        s = SiegeEngine.withdraw(s, pawnID: first, out: false)
        #expect(try #require(s.siege).withdrawn.isEmpty)
    }

    // MARK: - It survives a save

    @Test("A half-fought raid survives being written to disk")
    func siegeRoundTrips() throws {
        let reg = try registry()
        var s = try besieged(colony())
        let opened = try #require(s.siege).openedAt
        s = SiegeEngine.order(s, posture: .press)
        s = SiegeEngine.advance(s, to: opened + 9, registry: reg)

        let data = try JSONEncoder().encode(s)
        let back = try JSONDecoder().decode(Settlement.self, from: data)
        let before = try #require(s.siege), after = try #require(back.siege)
        #expect(after.step == before.step)
        #expect(after.posture == .press, "the orders are part of the world")
        #expect(abs(after.strength - before.strength) < 1e-9)
        #expect(after.moments.count == before.moments.count)

        // And carrying both to the end lands in the same place.
        let a = SiegeEngine.advance(s, to: opened + Siege.stepsTotal, registry: reg)
        let b = SiegeEngine.advance(back, to: opened + Siege.stepsTotal, registry: reg)
        #expect(a.pawns.map(\.health) == b.pawns.map(\.health))
    }

    @Test("A save written before sieges existed still loads")
    func oldSavesLoad() throws {
        let s = colony()
        let data = try JSONEncoder().encode(s)
        var object = try #require(
            try JSONSerialization.jsonObject(with: data) as? [String: Any])
        object.removeValue(forKey: "siege")
        let stripped = try JSONSerialization.data(withJSONObject: object)
        let back = try JSONDecoder().decode(Settlement.self, from: stripped)
        #expect(back.siege == nil)
    }

    // MARK: - It ends somewhere

    /// Rule 6, in its combat form. A fight that cannot finish inside the
    /// window it is given leaves the colony permanently under attack — no
    /// work, no record, and a canvas frozen mid-swing.
    @Test("Every siege finishes inside its own window")
    func siegeAlwaysTerminates() throws {
        let reg = try registry()
        for strength in [5.0, 40, 120, 400] {
            for posture in Siege.Posture.allCases {
                var s = try besieged(colony(), strength: strength)
                s = SiegeEngine.order(s, posture: posture)
                let opened = try #require(s.siege).openedAt
                s = SiegeEngine.advance(s, to: opened + Siege.stepsTotal, registry: reg)
                #expect(s.siege == nil,
                        "a \(strength)-strong raid at \(posture) never ended")
                #expect(s.lastBattle != nil)
            }
        }
    }

    @Test("A raid that wipes the line out stops rather than grinding on")
    func emptyLineEndsIt() throws {
        let reg = try registry()
        var s = try besieged(colony(pawns: 2, defense: 0), strength: 400)
        let opened = try #require(s.siege).openedAt
        s = SiegeEngine.advance(s, to: opened + Siege.stepsTotal, registry: reg)
        #expect(s.siege == nil)
    }

    // MARK: - The wolves too

    /// The commonest fight in the game. A raid is a once-a-year roll; wolves
    /// come at the herds all the time — and that one was still three lines of
    /// arithmetic, so the fight a colony actually has regularly was the one you
    /// could never stand in.
    @Test("A pack at the herds opens a fight you can stand in")
    func wolvesOpenASiege() throws {
        let reg = try registry()
        var s = colony(pawns: 10, defense: 5)
        var map = LocalMapGenerator.generate(
            mapSeed: 21, regionID: s.id, biome: reg.biome("forest"))
        // A bad year: pressure high enough that the roll lands.
        map.wildlife.predatorPressure = 100
        s.localMap = map

        // Walk ticks until the roll comes up; the chance is per tick.
        var opened: Siege?
        for tick in 0..<4000 {
            s = WildlifeEngine.advanceOneTick(
                s, registry: reg, tick: tick, era: .earlySettlement, mapSeed: 21)
            if let siege = s.siege { opened = siege; break }
            s.localMap?.wildlife.predatorPressure = 100
        }
        let siege = try #require(opened, "no pack ever came in four thousand ticks")
        #expect(siege.attackerLabel?.resolve(.cs) == "Vlci")
        #expect(!siege.line.isEmpty, "the watch turned out")
        #expect(s.lastBattle == nil, "it has not been decided yet")
    }

    @Test("A colony already fighting is not jumped by wolves as well")
    func onlyOneFightAtATime() throws {
        let reg = try registry()
        var s = try besieged(colony(), strength: 40)
        var map = LocalMapGenerator.generate(
            mapSeed: 22, regionID: s.id, biome: reg.biome("forest"))
        map.wildlife.predatorPressure = 100
        s.localMap = map
        let id = try #require(s.siege).id

        for tick in 0..<200 {
            s = WildlifeEngine.advanceOneTick(
                s, registry: reg, tick: tick, era: .earlySettlement, mapSeed: 22)
            s.localMap?.wildlife.predatorPressure = 100
        }
        // Either the raid is still running, or it finished — but the wolves
        // never replaced it mid-fight.
        if let running = s.siege { #expect(running.id == id) }
    }

    // MARK: - The neighbours pay for it too

    @Test("What the attempt cost the raiders is charged when it ends")
    func attackerPaysAtTheEnd() throws {
        let reg = try registry()
        var world = WorldState(mapSeed: 11)
        world.tick = 100
        let tribe = Tribe(
            id: UUID(uuidString: "7B1BE000-0000-0000-0000-000000000001")!,
            name: "The Ashfolk", regionID: UUID(), foundedTick: 0,
            originStory: LocalizedText(values: [.en: "out", .cs: "ven"]),
            population: 60, genes: Genes(), defense: 10, stores: 0, standing: -50)
        world.tribes = [tribe]
        var s = try besieged(colony(), strength: 60, tribeID: tribe.id)
        s = SiegeEngine.order(s, posture: .press)
        world.settlements = [s]

        for tick in 100..<104 {
            for step in 0..<WorldClock.actionStepsPerTick {
                world = ActionLoop.advanceStep(
                    world, clock: WorldClock(tick: tick, step: step), registry: reg)
            }
        }
        #expect(world.settlements[0].siege == nil)
        #expect(world.tribes[0].population < 60,
                "a warband that was pressed does not all walk home")
        // Charged for the fight it actually finished, not for the state it was
        // in one step earlier. A warband broken outright pays for all of it —
        // reading the siege before its last step is how the tribes came to be
        // charged for a fight that had not happened yet.
        if try #require(world.settlements[0].lastBattle).repelled {
            #expect(world.tribes[0].population <= 60 - 60 * 0.12 + 1e-6,
                    "a broken warband pays its whole strength")
        }
    }
}
