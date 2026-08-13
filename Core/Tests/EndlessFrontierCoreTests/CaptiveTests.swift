import Testing
import Foundation
@testable import EndlessFrontierCore

/// The third door into a colony that cannot grow out of its own cradle: the
/// people a broken raid leaves behind.
///
/// What these pin is the pair of failures this door can have, and they pull in
/// opposite directions. Taking nobody makes the whole mechanism scenery; taking
/// everybody turns a colony that has learned to defend itself into a population
/// faucet, which is rule 14 with a wall around it.
@Suite("The ones who did not walk home")
struct CaptiveTests {

    private func registry() throws -> GameDataRegistry { try GameDataRegistry.bundled() }

    private func id(_ n: Int) -> UUID {
        UUID(uuidString: String(format: "CA971FE0-0000-0000-0000-%012d", n))!
    }

    /// A colony big enough to guard somebody, with a larder and a good mood —
    /// the conditions under which a prisoner ever comes round.
    private func colony(souls: Int = 27, food: Double = 900, morale: Double = 80) -> Settlement {
        var s = Settlement(id: id(1), name: "Wallside",
                           storage: [.food: food], storageCapacity: .uniform(2000))
        s.pawns = (0..<souls).map { Pawn(id: id(100 + $0), name: "Hand \($0)") }
        s.stats.morale = morale
        return s
    }

    /// A raid that broke against the wall, with `downed` of its people on the
    /// ground and nobody left standing.
    private func brokenRaid(
        downed: Int, fromTribe: Bool = true, leftStanding: Double = 0
    ) -> Siege {
        // `strength` is set from `openingStrength`, and `repelled` is
        // `strength <= 0` — so a broken raid is one that arrived worth nothing
        // left, and `leftStanding` is how a raid that got through is written.
        var siege = Siege(
            id: id(2), startTick: 100, openedAt: 0, attackerName: "Kamenní",
            attackerTribeID: fromTribe ? id(3) : nil,
            approach: 0.5, attackers: downed,
            openingStrength: leftStanding, fortification: 10, seed: 0xBEEF,
            line: [id(100)])
        // A raid that got through has to be *finished* some other way, or
        // `conclude` will not touch it.
        siege.advancedTo = Siege.stepsTotal
        siege.fighters = (0..<downed).map {
            Siege.Combatant(id: id(500 + $0), side: .raider,
                            at: LocalPoint(x: 0.4, y: 0.4), strength: 0, down: true)
        }
        return siege
    }

    private func held(_ s: Settlement, siege: Siege, registry: GameDataRegistry) -> Settlement {
        var out = s
        out.siege = siege
        return SiegeEngine.conclude(out, registry: registry)
    }

    // MARK: - Taking them

    @Test("A raid that breaks leaves people behind")
    func abrokenRaidLeavesCaptives() throws {
        let reg = try registry()
        let s = held(colony(), siege: brokenRaid(downed: 6), registry: reg)
        #expect(!s.captives.isEmpty, "six went down and the colony took none of them")
        #expect(s.captives.allSatisfy { $0.pawn.assignedWork == .idle },
                "a prisoner was put straight to work")
        #expect(s.population == 27, "a captive is not a colonist yet")
    }

    /// Rule 14's ceiling. Without it a colony that gets good at winning turns
    /// raids into a way to farm people.
    @Test("A village cannot hold more prisoners than it can watch")
    func captivesAreBoundedByTheColony() throws {
        let reg = try registry()
        for souls in [4, 12, 27, 60, 200] {
            var s = colony(souls: souls)
            // Raid after raid after raid, each one enormous.
            for _ in 0..<8 {
                s = held(s, siege: brokenRaid(downed: 40), registry: reg)
            }
            #expect(s.captives.count <= CaptiveEngine.capacity(s),
                    "\(souls) souls are holding \(s.captives.count) prisoners")
            #expect(s.captives.count <= CaptiveEngine.heldCeiling)
        }
    }

    @Test("A raid that got through leaves nobody, and neither does a wolf pack")
    func nothingToTakeFromTheWrongRaid() throws {
        let reg = try registry()
        let wonThrough = brokenRaid(downed: 6, leftStanding: 25)
        #expect(held(colony(), siege: wonThrough, registry: reg).captives.isEmpty)

        // Animals leave no prisoners — `attackerTribeID` is the honest test of
        // whether the attacker was people, and the alternative is a colony that
        // converts a bear.
        let beasts = brokenRaid(downed: 6, fromTribe: false)
        #expect(held(colony(), siege: beasts, registry: reg).captives.isEmpty)
    }

    // MARK: - What becomes of them

    private func run(_ s: Settlement, ticks: Int, registry: GameDataRegistry) -> Settlement {
        var w = WorldState(settlements: [s])
        w.mapSeed = 4242
        for _ in 0..<ticks {
            w = CaptiveEngine.advanceOneTick(w, registry: registry, mapSeed: w.mapSeed)
            w.tick += 1
        }
        return w.settlements[0]
    }

    @Test("A colony worth living in wins its prisoners over")
    func goodColoniesConvert() throws {
        let reg = try registry()
        let taken = held(colony(), siege: brokenRaid(downed: 6), registry: reg)
        let before = taken.population
        let after = run(taken, ticks: 900, registry: reg)
        #expect(after.population > before, "nobody came round in fifteen good years")
        #expect(after.captives.count < taken.captives.count)
    }

    /// The half that keeps this from being free. A colony that wins its fights
    /// and then starves its prisoners does not gain people.
    @Test("A hungry, wretched colony loses them over the wall")
    func badColoniesLoseThem() throws {
        let reg = try registry()
        let taken = held(colony(food: 0, morale: 20),
                         siege: brokenRaid(downed: 6), registry: reg)
        #expect(!taken.captives.isEmpty, "nobody was taken, so nothing is being tested")
        let before = taken.population
        let after = run(taken, ticks: 900, registry: reg)
        #expect(after.captives.isEmpty, "they stayed in a colony with nothing to eat")
        #expect(after.population == before, "a starving colony converted somebody")
    }

    @Test("Coming round takes years, not a season")
    func conversionIsSlow() throws {
        let reg = try registry()
        let taken = held(colony(), siege: brokenRaid(downed: 6), registry: reg)
        let soon = run(taken, ticks: 120, registry: reg)   // two years
        #expect(soon.population == taken.population,
                "a prisoner was one of us inside two years")
    }

    @Test("Prisoners eat out of the same larder")
    func captivesCostFood() throws {
        let reg = try registry()
        let taken = held(colony(), siege: brokenRaid(downed: 6), registry: reg)
        let food = taken.storage[.food]
        // One tick, so this is upkeep and not a season's drift.
        let after = run(taken, ticks: 1, registry: reg)
        #expect(after.storage[.food] < food, "a prisoner was fed out of thin air")
    }

    // MARK: - The rules that must not break

    @Test("The same raid carries in the same people")
    func captureIsDeterministic() throws {
        let reg = try registry()
        func names() -> [String] {
            held(colony(), siege: brokenRaid(downed: 6), registry: reg)
                .captives.map(\.pawn.name)
        }
        #expect(names() == names())
    }

    @Test("A colony holding nobody costs nothing to reckon")
    func theEmptyCaseIsUntouched() throws {
        let reg = try registry()
        var w = WorldState(settlements: [colony()])
        w.mapSeed = 4242
        #expect(CaptiveEngine.advanceOneTick(w, registry: reg, mapSeed: w.mapSeed) == w)
    }

    @Test("A save written before anybody was taken alive holds nobody")
    func oldSavesDecode() throws {
        var data = try JSONSerialization.jsonObject(
            with: JSONEncoder().encode(colony(souls: 1))) as? [String: Any] ?? [:]
        data.removeValue(forKey: "captives")
        let back = try JSONDecoder().decode(
            Settlement.self, from: JSONSerialization.data(withJSONObject: data))
        #expect(back.captives.isEmpty)
    }
}
