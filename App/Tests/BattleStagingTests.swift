import Testing
import Foundation
import EndlessFrontierCore
@testable import EndlessFrontier

/// The battle is drawn from the record, and the colonists in it are sent to the
/// same places the fight is drawn at. These are the joints where that can come
/// apart silently — a line drawn where nobody stands, or a defender running to
/// a post the raiders never reach.
@Suite("Battle staging")
struct BattleStagingTests {

    private func log(line: [UUID], approach: Double = 0, repelled: Bool = false,
                     tick: Int = 100, attackers: Int = 6) -> BattleLog {
        BattleLog(id: UUID(), tick: tick, attackerName: "Raiders",
                  defenderName: "Home",
                  moments: [BattleMoment(id: 0, at: 0.2, kind: .charge)],
                  repelled: repelled, approach: approach,
                  attackers: attackers, line: line)
    }

    @Test("A defender in the line is sent to the line, and gets there")
    func defenderConverges() {
        let me = UUID()
        let battle = log(line: [me, UUID(), UUID()])
        let home = LocalPoint(x: 0.5, y: 0.52)

        let early = SettlementBattle.station(for: me, log: battle, progress: 0.02, from: home)
        let held = SettlementBattle.station(for: me, log: battle, progress: 0.9, from: home)

        #expect(early != nil)
        #expect(early?.arrived == false)
        #expect(held?.arrived == true)
        // They have actually gone somewhere: the post is not the heart.
        let post = try! #require(held).position
        #expect(abs(post.x - home.x) + abs(post.y - home.y) > 0.1)
    }

    @Test("Anyone not mustered keeps their day")
    func bystandersAreLeftAlone() {
        let battle = log(line: [UUID()])
        #expect(SettlementBattle.station(for: UUID(), log: battle, progress: 0.5,
                                         from: LocalPoint(x: 0.5, y: 0.5)) == nil)
    }

    @Test("The line stands between the town and where the attack came from")
    func lineFacesTheAttack() {
        // An attack from due east: the line must form east of the heart.
        let field = SettlementBattle.ground(log(line: [], approach: 0))
        #expect(field.muster.x > field.heart.x)
        #expect(field.origin.x > field.muster.x)
        // …and from due west, the other way.
        let west = SettlementBattle.ground(log(line: [], approach: .pi))
        #expect(west.muster.x < west.heart.x)
    }

    @Test("Defenders stand shoulder to shoulder, not on one another")
    func lineIsSpreadOut() {
        let ids = (0..<6).map { _ in UUID() }
        let field = SettlementBattle.ground(log(line: ids))
        let posts = ids.indices.map { field.defenderPost(index: $0, of: ids.count) }
        for i in posts.indices {
            for j in posts.indices where j > i {
                #expect(SiegeField.distance(posts[i], posts[j]) > 0.01)
            }
        }
    }

    /// The record is *replayed*, not lived through: twenty seconds for the
    /// whole fight whatever tick it happened on. At the tick's own pace eight
    /// rounds came out as one exchange every seven and a half seconds, which is
    /// a fight you can watch and see nothing happen in.
    /// **The fight the player stands in used to jump.** `Siege.progress` is
    /// `step / steps`, and a step only moves when the simulation resolves one,
    /// so every beat arrived in a leap: an arrow never flew, impacts landed in
    /// a lump, and the replay of a finished fight looked better than the live
    /// one. Keks: *"souboje jsou rozhozené, efekty a grafika nesedí."*
    @Test("A live fight moves between its steps, not in jumps")
    func liveFightIsInterpolated() {
        let perTick = Double(WorldClock.actionStepsPerTick)
        var siege = Siege(
            id: UUID(), startTick: 10, openedAt: 10 * Int(perTick),
            attackerName: "Broken men", approach: 0, attackers: 6,
            openingStrength: 60, fortification: 0, seed: 1, line: [], steps: 40)
        // Four steps resolved: the fight is 4/40 through, and no further until
        // the fifth lands.
        siege.advancedTo = siege.openedAt + 4
        let atStep = SettlementBattle.liveProgress(
            of: siege, continuousTick: Double(siege.advancedTo) / perTick)
        #expect(abs(atStep - 4.0 / 40) < 0.001)

        // Half a step later the picture is half a step further on — which is
        // the whole of what an arrow needs to be in the air.
        let halfway = SettlementBattle.liveProgress(
            of: siege, continuousTick: Double(siege.advancedTo) / perTick + 0.5 / perTick)
        #expect(halfway > atStep, "\(halfway) against \(atStep)")
        #expect(abs(halfway - 4.5 / 40) < 0.001)

        // …and it never runs ahead of the step the simulation has reached.
        let far = SettlementBattle.liveProgress(
            of: siege, continuousTick: Double(siege.advancedTo) / perTick + 5)
        #expect(abs(far - 5.0 / 40) < 0.001, "the drawing may not outrun the fight")
    }

    @Test("A fight is played back faster than the tick that carried it")
    func liveWindow() {
        var settlement = Settlement(id: UUID(), name: "Home", regionID: UUID())
        settlement.lastBattle = log(line: [], tick: 100)
        // A minute-long tick played over twenty seconds runs at 3×, so the
        // fight and its aftermath occupy a little over half a tick.
        #expect(SettlementBattle.live(settlement, continuousTick: 99.5) == nil,
                "not before it happens")
        #expect(SettlementBattle.live(settlement, continuousTick: 100.0) != nil)
        #expect(SettlementBattle.live(settlement, continuousTick: 100.3) != nil)
        #expect(SettlementBattle.live(settlement, continuousTick: 100.9) == nil,
                "over well inside its own tick")
        #expect(SettlementBattle.live(settlement, continuousTick: 140) == nil,
                "and does not haunt the colony")
    }

    /// Rule 6 in its combat form: the fight must actually *finish* inside the
    /// window it is given, or the last thing the player sees is a rank of
    /// raiders frozen mid-swing.
    @Test("The whole record has played before the window closes")
    func recordFinishesInsideTheWindow() {
        var settlement = Settlement(id: UUID(), name: "Home", regionID: UUID())
        settlement.lastBattle = log(line: [], tick: 100)
        let speed = 60.0 / SettlementBattle.playSeconds
        let lastTick = 100.0 + (1 + SettlementBattle.lingerFraction) / speed
        // A hair inside the end of the window, the replay is at its finish.
        let end = SettlementBattle.live(settlement, continuousTick: lastTick - 0.001)
        #expect(end?.progress == 1)
    }

    @Test("A replay outranks the live fight and runs on its own clock")
    func replayPlaysFromTheTop() {
        var settlement = Settlement(id: UUID(), name: "Home", regionID: UUID())
        settlement.lastBattle = log(line: [], tick: 100)
        let started = Date()
        let replay = SettlementBattle.Replay(log: log(line: [], tick: 7), startedAt: started)
        // Long after the live fight is over, the replay is still playing.
        let seen = SettlementBattle.live(
            settlement, continuousTick: 900, replay: replay,
            now: started.addingTimeInterval(SettlementBattle.playSeconds * 0.5))
        #expect(seen?.log.tick == 7)
        #expect(abs((seen?.progress ?? 0) - 0.5) < 0.02)

        // …and when it has run out, it stops standing in the way.
        let after = SettlementBattle.live(
            settlement, continuousTick: 900, replay: replay,
            now: started.addingTimeInterval(SettlementBattle.playSeconds * 4))
        #expect(after == nil)
    }

    /// The fight has to *read* as a fight: named stages in order, a rank that
    /// thins as the colony holds, and blows that land on the record's beats
    /// rather than on a free-running sine.
    @Test("The fight runs through its stages in order")
    func phasesRunInOrder() {
        #expect(SettlementBattle.phase(at: 0.0) == .marching)
        #expect(SettlementBattle.phase(at: 0.30) == .volley)
        #expect(SettlementBattle.phase(at: 0.60) == .melee)
        #expect(SettlementBattle.phase(at: 0.95) == .breaking)
    }

    @Test("A rank that is being beaten visibly thins")
    func attackersThin() {
        let held = log(line: [UUID(), UUID()], repelled: true, attackers: 8)
        #expect(SettlementBattle.attackersStanding(held, at: 0.1) == held.drawnAttackers)
        #expect(SettlementBattle.attackersStanding(held, at: 0.6)
                < SettlementBattle.attackersStanding(held, at: 0.45))
        #expect(SettlementBattle.attackersStanding(held, at: 0.99) == 0,
                "a broken assault leaves nobody standing")

        // One that got through pays for it but walks away.
        let through = log(line: [UUID()], repelled: false, attackers: 8)
        #expect(SettlementBattle.attackersStanding(through, at: 0.99) > 0)
        #expect(SettlementBattle.attackersStanding(through, at: 0.99) < through.drawnAttackers)
    }

    @Test("A blow lands on the beat the record wrote it on")
    func blowsLandOnTheRecord() {
        let battle = BattleLog(
            id: UUID(), tick: 1, attackerName: "Raiders", defenderName: "Home",
            moments: [BattleMoment(id: 0, at: 0.50, kind: .clash)],
            repelled: false, approach: 0, attackers: 4, line: [UUID()])
        #expect(SettlementBattle.strikeBeat(battle, at: 0.40) == 0, "before the blow")
        #expect(SettlementBattle.strikeBeat(battle, at: 0.50) > 0.9, "on it")
        #expect(SettlementBattle.strikeBeat(battle, at: 0.80) == 0, "and well after it")
    }

    @Test("A defender's bar empties as the wounds the record names land on them")
    func harmFollowsTheRecord() {
        let me = UUID()
        let battle = BattleLog(
            id: UUID(), tick: 1, attackerName: "Raiders", defenderName: "Home",
            moments: [
                BattleMoment(id: 0, at: 0.5, kind: .wound, pawnID: me, amount: 30),
                BattleMoment(id: 1, at: 0.7, kind: .wound, pawnID: me, amount: 30),
            ],
            repelled: false, approach: 0, attackers: 3, line: [me])
        #expect(SettlementBattle.harm(battle, pawn: me, at: 0.2) == 0)
        #expect(abs(SettlementBattle.harm(battle, pawn: me, at: 0.6) - 0.3) < 0.001)
        #expect(abs(SettlementBattle.harm(battle, pawn: me, at: 0.9) - 0.6) < 0.001)
        #expect(SettlementBattle.harm(battle, pawn: UUID(), at: 0.9) == 0)
    }

    @Test("Someone the record killed reads as down, whatever else happened")
    func deathIsTotal() {
        let me = UUID()
        let battle = BattleLog(
            id: UUID(), tick: 1, attackerName: "Raiders", defenderName: "Home",
            moments: [BattleMoment(id: 0, at: 0.4, kind: .death, pawnID: me, amount: 8)],
            repelled: false, approach: 0, attackers: 3, line: [me, UUID()])
        #expect(SettlementBattle.harm(battle, pawn: me, at: 0.5) == 1)
        #expect(SettlementBattle.defendersStanding(battle, at: 0.3) == 2)
        #expect(SettlementBattle.defendersStanding(battle, at: 0.5) == 1)
    }
}

/// Rooms are furnished by a pure function of `(glyph, seed, workers)`, and the
/// colonists posted to a building stand at the fittings that function drew.
/// **A blow that lands.** The Core stamps the step a body was struck on and
/// where the blow came from; the canvas turns that into a jolt away from it.
@Suite("A hit that reads as a hit")
struct FlinchTests {

    private func siege(step: Int) -> Siege {
        var siege = Siege(
            id: UUID(uuidString: "F11C0000-0000-0000-0000-0000000000FF")!,
            startTick: 0, openedAt: 0, attackerName: "Kamenní",
            approach: 0, attackers: 4, openingStrength: 30,
            fortification: 4, seed: 7, line: [])
        siege.advancedTo = step
        return siege
    }

    private func hit(at step: Int?, from: LocalPoint?) -> Siege.Combatant {
        Siege.Combatant(
            id: UUID(uuidString: "F11C0000-0000-0000-0000-000000000001")!,
            side: .raider, at: LocalPoint(x: 0.5, y: 0.5), strength: 10,
            struckAtStep: step, struckFrom: from)
    }

    @Test("Nobody who was not hit moves at all")
    func theUnhurtStandStill() {
        let quiet = SettlementBattle.flinch(hit(at: nil, from: nil),
                                            siege: siege(step: 3), within: 0)
        #expect(quiet.dx == 0 && quiet.dy == 0)
    }

    @Test("A body is thrown away from the blow, not toward it")
    func theJoltRunsWithTheBlow() {
        let struck = hit(at: 3, from: LocalPoint(x: 0.4, y: 0.5))   // hit from the west
        let jolt = SettlementBattle.flinch(struck, siege: siege(step: 3), within: 0)
        #expect(jolt.dx > 0, "the blow came from the west and threw them west")
        #expect(abs(jolt.dy) < 1e-9)
    }

    @Test("It is hardest on the beat and gone by the end of the step")
    func theJoltDecays() {
        let struck = hit(at: 3, from: LocalPoint(x: 0.4, y: 0.5))
        let onTheBeat = SettlementBattle.flinch(struck, siege: siege(step: 3), within: 0)
        let halfWay = SettlementBattle.flinch(struck, siege: siege(step: 3), within: 0.5)
        let over = SettlementBattle.flinch(struck, siege: siege(step: 3), within: 1)
        #expect(onTheBeat.dx > halfWay.dx)
        #expect(halfWay.dx > over.dx)
        #expect(over.dx == 0)
        // And never further than the reach a blow is struck at, or the line
        // comes apart every time somebody swings.
        #expect(onTheBeat.dx <= SiegeEngine.reach)
    }

    @Test("A blow from a step ago is over")
    func theBodySettles() {
        let struck = hit(at: 2, from: LocalPoint(x: 0.4, y: 0.5))
        let jolt = SettlementBattle.flinch(struck, siege: siege(step: 3), within: 0)
        #expect(jolt.dx == 0 && jolt.dy == 0)
    }
}

@Suite("Building interiors")
struct InteriorTests {

    /// A room is furnished out of `fittings.json` for the century the town is
    /// living in, so laying one out now needs the book and the era. An empty
    /// registry furnishes the fallback room, which is exactly what these tests
    /// are asking about: where the fittings *land*, not which ones they are.
    private func book() -> GameDataRegistry {
        GameDataRegistry(buildings: [], techs: [], eras: [], biomes: [], events: [],
                         fittings: TestBook.fittings, config: .default)
    }

    @Test("Every worker gets a station of their own")
    func workersGetStations() {
        for workers in 1...5 {
            let stations = SettlementInterior.stationSlots(
                for: .workshop, seed: 42, stations: workers,
                era: .earlySettlement, registry: book())
            #expect(stations.count >= min(workers, 5))
        }
    }

    @Test("Stations stay inside the room's walls")
    func stationsAreIndoors() {
        for glyph in [SettlementRenderer.BuildingGlyph.house, .hall, .granary,
                      .temple, .plant, .pad] {
            for slot in SettlementInterior.slots(for: glyph, seed: 7, stations: 4,
                                                 era: .earlySettlement, registry: book()) {
                let limit = 0.5 - SettlementInterior.wallInset
                #expect(abs(slot.dx) <= limit, "\(glyph) \(slot.fitting) escaped sideways")
                #expect(abs(slot.dy) <= limit, "\(glyph) \(slot.fitting) escaped downwards")
            }
        }
    }

    @Test("Two stations are never the same spot")
    func stationsDoNotOverlap() {
        let slots = SettlementInterior.stationSlots(
            for: .plant, seed: 9, stations: 6, era: .earlySettlement, registry: book())
        for i in slots.indices {
            for j in slots.indices where j > i {
                let dx = slots[i].dx - slots[j].dx, dy = slots[i].dy - slots[j].dy
                #expect((dx * dx + dy * dy).squareRoot() > 0.05)
            }
        }
    }

    @Test("An empty building is still a furnished room")
    func emptyRoomsAreFurnished() {
        #expect(!SettlementInterior.slots(for: .granary, seed: 1, stations: 0,
                                          era: .earlySettlement, registry: book()).isEmpty)
    }

    @Test("The roof is solid from far off and gone up close")
    func roofLifts() {
        #expect(SettlementInterior.roofFade(zoom: 1) == 1)
        #expect(SettlementInterior.roofFade(zoom: 4) == 0)
        let middle = SettlementInterior.roofFade(zoom: 2.1)
        #expect(middle > 0 && middle < 1)
    }
}

/// **The volley.** Keks, watching a fight: *"střílení je docela rychlé."*
///
/// It was not the rate — a step of a siege is fifteen real seconds and at most
/// one volley is loosed in it. Two other things were wrong, and together they
/// read as continuous fire:
///
/// - a beat stayed on screen for 0.12 of the fight, very nearly **three**
///   steps, so three volleys overlapped and each faded through the next;
/// - the arrows did not move. Six dashes were strung along the flight path at
///   `t = 0.15 + i * 0.12` — a function of *which arrow*, never of *when* — so
///   a volley was a static fan that faded where it stood.
@Suite("A volley is a flight, and it lands")
struct VolleyTests {

    /// One beat, one step — of *this* fight. Derived rather than written down,
    /// so it cannot drift away from the fight it is timing (rule 35), and so a
    /// long siege has more beats rather than shorter ones.
    @Test("A beat lasts one step of the fight and no longer",
          arguments: [Siege.stepsFloor, 24, 40, Siege.stepsCeiling])
    func aBeatIsAStep(steps: Int) {
        let beat = SettlementBattle.momentLife(steps: steps)
        #expect(abs(beat - 1 / Double(steps)) < 1e-9)
        // The bug, pinned: three of these used to fit inside one beat.
        #expect(beat < 0.12, "a volley outlives its own step again")
    }

    /// The volley phase still comes before the clash, whatever the beat is —
    /// the fix must not reorder the fight.
    @Test("The shooting still happens before the lines meet")
    func theOrderHolds() {
        #expect(SettlementBattle.volleyAt < SettlementBattle.meleeAt)
        #expect(SettlementBattle.phase(at: SettlementBattle.volleyAt + 0.01) == .volley)
        #expect(SettlementBattle.phase(at: 0.0) == .marching)
    }

    /// A beat has to be long enough to *see*. One step of a siege is fifteen
    /// real seconds at the shipped tick rate; an arrow crossing the field in
    /// that is a flight rather than a flicker.
    @Test("A beat is long enough to watch")
    func aBeatIsWatchable() {
        let stepsPerTick = 8.0
        let secondsPerTick = 120.0
        // A beat is one step whatever the fight's length, so this is the same
        // number of real seconds for a skirmish and for a war — which is the
        // point: the fight gets longer, its beats do not get faster.
        for steps in [Siege.stepsFloor, 24, Siege.stepsCeiling] {
            let beatSeconds = SettlementBattle.momentLife(steps: steps)
                * Double(steps) * (secondsPerTick / stepsPerTick)
            #expect(beatSeconds > 5, "a volley is gone too fast to see")
            #expect(beatSeconds < 30, "a volley hangs about")
        }
    }
}
