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

    /// The approach is not a step count any more — it is the ground between
    /// two ranks and how fast people walk over it. Named for that: if the pace
    /// and the distances ever stop leaving a gap, the enemy is in the colony's
    /// faces on the first step and there is nothing to prepare for.
    @Test("They have to walk in, and nobody is touched while they are crossing")
    func approachHurtsNobody() throws {
        let reg = try registry()
        var s = try besieged(colony())
        let opened = try #require(s.siege).openedAt

        s = SiegeEngine.advance(s, to: opened + 2, registry: reg)
        let early = try #require(s.siege)
        #expect(!early.inContact, "they cannot possibly have reached anybody yet")
        #expect(s.pawns.allSatisfy { $0.health >= 100 })
        #expect(early.raiders.allSatisfy { $0.at != SiegeField(approach: early.approach).origin },
                "…but they are walking")

        // …and they arrive under their own steam, with no step index saying so.
        s = SiegeEngine.advance(s, to: opened + SiegeEngine.typicalApproachSteps + 2,
                                registry: reg)
        let record = s.siege?.moments ?? s.lastBattle?.moments ?? []
        #expect(record.contains { $0.kind == .charge }, "they arrived")
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

    // MARK: - A ground to stand on

    /// The pivot, stated as a property: the enemy is *somewhere*, and that
    /// somewhere gets nearer. Before this a raider was an index in a list and
    /// the canvas guessed where to draw them.
    @Test("The warband starts at the edge of the map and walks in")
    func raidersWalkIn() throws {
        let reg = try registry()
        var s = try besieged(colony())
        let opened = try #require(s.siege).openedAt
        let field = SiegeField(approach: try #require(s.siege).approach)

        func closest(_ siege: Siege) -> Double {
            siege.raiders.filter { !$0.down }
                .map { field.reachFromHeart($0.at) }.min() ?? .infinity
        }
        let atFirst = closest(try #require(s.siege))
        #expect(abs(atFirst - SiegeField.originReach) < 0.05, "they come in off the map")

        s = SiegeEngine.advance(s, to: opened + 3, registry: reg)
        let closer = closest(try #require(s.siege))
        #expect(closer < atFirst - 0.05, "and they are walking, not teleporting")
        #expect(try #require(s.siege).defenders.contains { !$0.down },
                "the watch is on the field too")
    }

    /// Contact used to be `step >= 4`. It is now being close enough to reach
    /// somebody — which is what makes aiming, walking and holding a line mean
    /// anything at all.
    @Test("Contact is proximity, not a round number")
    func contactIsProximity() throws {
        let reg = try registry()
        var s = try besieged(colony())
        let opened = try #require(s.siege).openedAt
        #expect(!(try #require(s.siege).inContact))

        var met = false
        for step in 1...Siege.stepsTotal {
            s = SiegeEngine.advance(s, to: opened + step, registry: reg)
            guard let siege = s.siege else { break }
            if siege.inContact { met = true; break }
        }
        #expect(met, "the two ranks never actually met")
    }

    /// §4.1 of the handoff, in one assertion. The old resolver put the whole
    /// warband's answer onto the single weakest colonist every step, so a raid
    /// produced one corpse and eleven people without a scratch — and being hurt
    /// never cost the colony anything, because nobody was.
    @Test("A fight leaves the line hurt, not one person picked out of it")
    func harmIsSpreadAcrossTheLine() throws {
        let reg = try registry()
        var s = try besieged(colony(pawns: 8, defense: 6), strength: 90)
        let opened = try #require(s.siege).openedAt
        s = SiegeEngine.advance(s, to: opened + Siege.stepsTotal, registry: reg)
        let hurt = s.pawns.filter { $0.health < 100 }.count
        #expect(hurt >= 3, "ninety raiders and only \(hurt) of eight came away marked")
    }

    // MARK: - Orders you give one person

    @Test("Told to go somewhere, a colonist goes there")
    func moveOrderIsCarriedOut() throws {
        let reg = try registry()
        var s = try besieged(colony())
        let siege = try #require(s.siege)
        let who = try #require(siege.line.first)
        let mine = try #require(siege.place(of: who))
        // Sideways off the line of the attack, so no posture would have sent
        // them here — this is the order and nothing else.
        let spot = LocalPoint(x: mine.x - 0.10, y: mine.y + 0.06)

        s = SiegeEngine.order(s, pawnID: who, moveTo: spot)
        s = SiegeEngine.advance(s, to: siege.openedAt + 6, registry: reg)
        let there = try #require(s.siege?.place(of: who))
        #expect(SiegeField.distance(there, spot) < 0.02,
                "they were told to go there and did not")
    }

    @Test("Told to take that one, a colonist closes on that one")
    func engageOrderIsCarriedOut() throws {
        let reg = try registry()
        var s = try besieged(colony(), strength: 60)
        let siege = try #require(s.siege)
        let who = try #require(siege.line.first)
        // The raider furthest from them: nothing but an order would send them
        // to this one.
        let field = SiegeField(approach: siege.approach)
        let mine = try #require(siege.place(of: who))
        let mark = try #require(siege.raiders.max {
            SiegeField.distance(mine, $0.at) < SiegeField.distance(mine, $1.at)
        })
        _ = field

        s = SiegeEngine.order(s, pawnID: who, engage: mark.id)
        s = SiegeEngine.advance(s, to: siege.openedAt + 8, registry: reg)
        guard let after = s.siege, let mine2 = after.place(of: who),
              let markNow = after.fighters.first(where: { $0.id == mark.id }) else { return }
        #expect(SiegeField.distance(mine2, markNow.at)
                < SiegeField.distance(mine, mark.at), "they never went for them")
    }

    /// Rule: an order is an *input* to the fight, not a hole in it. Same seed,
    /// same orders, same dead — and the orders have to survive the disk, or a
    /// reload quietly rewrites the battle.
    @Test("Orders given to one person survive a save and replay identically")
    func individualOrdersAreDeterministic() throws {
        let reg = try registry()
        func run() throws -> Settlement {
            var s = try besieged(colony(), strength: 60)
            let siege = try #require(s.siege)
            let who = try #require(siege.line.first)
            s = SiegeEngine.order(s, pawnID: who, moveTo: siege.place(of: who) ?? .init(x: 0.5, y: 0.5))
            s = SiegeEngine.order(s, posture: .press)
            return SiegeEngine.advance(s, to: siege.openedAt + Siege.stepsTotal, registry: reg)
        }
        let a = try run(), b = try run()
        #expect(a.pawns.map(\.health) == b.pawns.map(\.health))

        var mid = try besieged(colony(), strength: 60)
        let siege = try #require(mid.siege)
        let who = try #require(siege.line.first)
        mid = SiegeEngine.order(mid, pawnID: who, moveTo: LocalPoint(x: 0.34, y: 0.62))
        mid = SiegeEngine.advance(mid, to: siege.openedAt + 6, registry: reg)
        let back = try JSONDecoder().decode(
            Settlement.self, from: try JSONEncoder().encode(mid))
        #expect(back.siege?.orders.count == 1, "the order is part of the world")
        let x = SiegeEngine.advance(mid, to: siege.openedAt + Siege.stepsTotal, registry: reg)
        let y = SiegeEngine.advance(back, to: siege.openedAt + Siege.stepsTotal, registry: reg)
        #expect(x.pawns.map(\.health) == y.pawns.map(\.health))
    }

    // MARK: - Cover is a place you stand

    @Test("The wall covers you where it is, and not out in the field")
    func coverIsPositional() throws {
        let field = SiegeField(approach: 0)
        #expect(field.cover(at: field.heart) == 1)
        #expect(field.cover(at: field.wall) == 1)
        let onTheLine = field.cover(at: field.muster)
        #expect(onTheLine > 0.4 && onTheLine < 1, "holding the line keeps most of the wall")
        #expect(field.cover(at: field.origin) == 0, "out in the field it is behind you")
    }

    /// The grain goes because nobody is standing in the way, not because the
    /// player picked the order that spends grain. Same shape as rule 6: the
    /// effect has to be reachable by the thing that causes it.
    @Test("Raiders take the stores by reaching them, not by the order given")
    func plunderIsPositional() throws {
        let reg = try registry()
        var gave = try besieged(colony(), strength: 60)
        gave = SiegeEngine.order(gave, posture: .giveGround)
        let opened = try #require(gave.siege).openedAt
        gave = SiegeEngine.advance(gave, to: opened + Siege.stepsTotal, registry: reg)

        var held = try besieged(colony(), strength: 60)
        held = SiegeEngine.advance(held, to: opened + Siege.stepsTotal, registry: reg)

        #expect(gave.storage[.food] < held.storage[.food])
        // …and they had to physically be in the stores to do it.
        #expect(try #require(gave.lastBattle).moments.contains { $0.kind == .plunder })
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

    // MARK: - A blow happens somewhere

    /// The drawing used to paint the *aggregate*: a bright seam across the whole
    /// line, sparks at a computed "front". It had to, because a beat was a time
    /// and a name and nothing else, so there was no place to put a blow. Blood
    /// on the ground needs one, and this is where it comes from.
    @Test("Every blow is stamped with the ground it landed on")
    func woundsCarryTheirPlace() throws {
        let reg = try registry()
        var world = WorldState(mapSeed: 12)
        world.tick = 100
        // Pressing them puts the line out into the open, so blows land.
        world.settlements = [SiegeEngine.order(
            try besieged(colony(pawns: 10, defense: 4), strength: 90), posture: .press)]
        world = SiegeTestSupport.fightItOut(world, registry: reg)

        let log = try #require(world.settlements[0].lastBattle)
        let blows = log.moments.filter { $0.kind == .wound || $0.kind == .death }
        #expect(!blows.isEmpty, "a pressed line against ninety takes something")
        #expect(blows.allSatisfy { $0.spot != nil },
                "a blow that landed on nobody in particular is the old aggregate back")
        // On the field, not off the edge of the map.
        let field = SiegeField(approach: log.approach)
        #expect(blows.allSatisfy {
            guard let spot = $0.spot else { return false }
            return field.reachFromHeart(spot) <= SiegeField.originReach + 0.05
        }, "blood belongs on the ground the fight was fought over")
    }

    @Test("A battle saved before blows had a place still loads")
    func oldMomentsDecode() throws {
        let old = """
        {"id":3,"at":0.5,"kind":"wound","amount":10}
        """.data(using: .utf8)!
        let moment = try JSONDecoder().decode(BattleMoment.self, from: old)
        #expect(moment.spot == nil)
        #expect(moment.kind == .wound)
        #expect(moment.amount == 10)
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
