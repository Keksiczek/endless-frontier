import Testing
import Foundation
@testable import EndlessFrontierCore

/// The threat that has to get **worse** as the colony gets better.
///
/// Measured over two hundred years: every death was old age. Not because the
/// fighting was weak — a warband can kill twelve bare-handed colonists — but
/// because every threat scaled with the colony's own strength, and four hundred
/// people with walls and iron *should* turn back a hundred and forty raiders.
/// These tests are named for the property that makes a sickness different.
@Suite("A sickness in a crowded town")
struct PlagueTests {

    private func registry() throws -> GameDataRegistry { try GameDataRegistry.bundled() }

    private func town(_ count: Int, huts: Int = 6, housed: Bool = true) -> Settlement {
        let home = UUID(uuidString: "00000000-0000-0000-9149-00000000FFFF")!
        let pawns = (0..<count).map { i -> Pawn in
            var pawn = Pawn(
                id: UUID(uuidString: String(format: "00000000-0000-0000-9149-%012d", i + 1))!,
                name: "Soul \(i)")
            pawn.age = 28 * 60
            pawn.homeID = housed ? home : nil
            return pawn
        }
        return Settlement(
            id: UUID(uuidString: "00000000-0000-0000-9149-AAAAAAAAAAAA")!,
            name: "Crowd", kind: .capital, pawns: pawns,
            buildings: [BuildingInstance(definitionID: "hut", count: huts)],
            storage: [.food: 5000], storageCapacity: .uniform(9999))
    }

    private func struck(_ settlement: Settlement, plague id: String = "camp_fever",
                        infected: Int, tick: Int = 0) throws -> Settlement {
        var s = settlement
        var outbreak = Outbreak(
            id: UUID(uuidString: "00000000-0000-0000-9149-BBBBBBBBBBBB")!,
            plagueID: id, startedTick: tick)
        var rng = SeededRNG(seed: 7)
        for pawn in s.pawns.prefix(infected) {
            outbreak.infected.insert(pawn.id)
            s = PlagueEngine.testInfect(s, pawnID: pawn.id,
                                        plague: try #require(try registry().plague(id)),
                                        tick: tick, rng: &rng)
        }
        s.outbreak = outbreak
        return s
    }

    private func carry(_ settlement: Settlement, ticks: Int,
                       registry reg: GameDataRegistry) -> Settlement {
        var s = settlement
        for tick in stride(from: 0, to: ticks, by: PlagueEngine.interval) {
            s = PlagueEngine.advanceOneTick(
                s, registry: reg, tick: tick, era: .medieval, season: .autumn, mapSeed: 12)
        }
        return s
    }

    // MARK: - It is the colony's own success that brings it

    /// The property the whole system exists for, stated as an inequality.
    @Test("A crowded town is a worse place to be than a roomy one")
    func crowdingIsTheMechanism() throws {
        let reg = try registry()
        let roomy = PlagueEngine.crowding(town(30, huts: 12), registry: reg)
        let packed = PlagueEngine.crowding(town(90, huts: 6), registry: reg)
        #expect(packed > roomy * 1.3, "living on top of each other has to matter")
    }

    /// Rule 6: a threat gated above what the game can reach is not rare, it is
    /// impossible. A colony that has grown must actually see one of these.
    @Test("A big colony really does catch something, inside a lifetime")
    func anOutbreakIsReachable() throws {
        let reg = try registry()
        var s = town(120, huts: 8)
        var seen = false
        for tick in stride(from: 0, to: 6000, by: PlagueEngine.interval) {
            s = PlagueEngine.advanceOneTick(
                s, registry: reg, tick: tick, era: .medieval, season: .winter, mapSeed: 3)
            if s.outbreak != nil { seen = true; break }
            // Keep the town at size: this is about the *rate*, not about the
            // sickness eating the sample.
            if s.pawns.count < 120 { s = town(120, huts: 8) }
        }
        #expect(seen, "a hundred and twenty people packed into eight huts never got sick")
    }

    @Test("A hamlet is not an epidemic waiting to happen")
    func smallColoniesAreSpared() throws {
        let reg = try registry()
        var s = town(8, huts: 4)
        for tick in stride(from: 0, to: 4000, by: PlagueEngine.interval) {
            s = PlagueEngine.advanceOneTick(
                s, registry: reg, tick: tick, era: .medieval, season: .winter, mapSeed: 5)
        }
        #expect(s.outbreak == nil, "eight people in four huts is not a place a plague can run")
    }

    // MARK: - What it does, and what you can do about it

    @Test("Untended, it spreads and it kills")
    func itKills() throws {
        let reg = try registry()
        var s = try struck(town(60, huts: 5), plague: "the_great_dying", infected: 3)
        let before = s.pawns.count
        s = carry(s, ticks: 900, registry: reg)
        #expect(s.pawns.count < before, "nobody died of the great dying")
        #expect(s.deathTallies[PawnDeathCause.sickness.rawValue, default: 0] > 0)
    }

    /// The lever has to *reach* — same shape as rule 6, in the player's
    /// direction this time.
    @Test("Shutting the gates saves people, and costs the colony its work")
    func quarantineIsATrade() throws {
        let reg = try registry()
        let start = try struck(town(60, huts: 5), plague: "the_great_dying", infected: 3)

        let open = carry(start, ticks: 900, registry: reg)
        var shut = PlagueEngine.setQuarantine(start, true)
        shut = carry(shut, ticks: 900, registry: reg)

        #expect(shut.pawns.count >= open.pawns.count, "shutting the gates bought nothing")
        #expect(PlagueEngine.workFactor(PlagueEngine.setQuarantine(start, true)) < 1,
                "…and it has to cost something, or it is not a decision")
    }

    @Test("It burns out rather than going round for ever")
    func itEnds() throws {
        let reg = try registry()
        var s = try struck(town(40, huts: 6), infected: 2)
        s = carry(s, ticks: 4000, registry: reg)
        #expect(s.outbreak == nil, "the sickness never let go of the colony")
        // …and the chronicle says so, one way or the other.
        #expect(s.journal.entries.contains { $0.kind == .danger })
    }

    @Test("Nobody catches the same sickness twice")
    func immunityHolds() throws {
        let reg = try registry()
        var s = try struck(town(40, huts: 6), infected: 2)
        s = carry(s, ticks: 2000, registry: reg)
        guard let outbreak = s.outbreak else { return }
        #expect(outbreak.infected.intersection(outbreak.recovered).isEmpty)
    }

    // MARK: - The invariants

    @Test("The same colony, the same sickness, the same dead")
    func deterministic() throws {
        let reg = try registry()
        func run() throws -> Settlement {
            carry(try struck(town(60, huts: 5), plague: "grey_cough", infected: 4),
                  ticks: 1200, registry: reg)
        }
        let a = try run(), b = try run()
        #expect(a.pawns.map(\.id) == b.pawns.map(\.id))
        #expect(a.pawns.map(\.health) == b.pawns.map(\.health))
        #expect(a.outbreak == b.outbreak)
    }

    @Test("An outbreak survives being written to disk")
    func survivesASave() throws {
        let reg = try registry()
        let s = carry(try struck(town(40, huts: 6), infected: 3), ticks: 200, registry: reg)
        let back = try JSONDecoder().decode(
            Settlement.self, from: try JSONEncoder().encode(s))
        #expect(back.outbreak == s.outbreak)
    }

    /// Rule 3. A save from before sicknesses existed must load and simply be
    /// a colony nothing is wrong with.
    @Test("A settlement saved before sicknesses existed still loads")
    func oldSavesLoad() throws {
        // A real settlement, encoded and then stripped of the field, which is
        // exactly the shape of a save written before the field existed.
        var current = town(4, huts: 1)
        current.outbreak = nil
        var raw = try #require(try JSONSerialization.jsonObject(
            with: try JSONEncoder().encode(current)) as? [String: Any])
        raw.removeValue(forKey: "outbreak")
        let old = try JSONDecoder().decode(
            Settlement.self, from: try JSONSerialization.data(withJSONObject: raw))
        #expect(old.outbreak == nil)
        #expect(old.pawns.count == 4)
    }

    @Test("Every shipped sickness is readable in both languages")
    func contentIsBilingual() throws {
        let reg = try registry()
        #expect(!reg.plagues.isEmpty, "no sicknesses shipped at all")
        for plague in reg.plagues.values {
            #expect(!plague.name.resolve(.en).isEmpty)
            #expect(!plague.name.resolve(.cs).isEmpty)
            #expect(plague.name.resolve(.cs) != plague.name.resolve(.en),
                    "\(plague.id) is not actually translated")
            #expect(plague.contagion > 0 && plague.virulence > 0)
        }
    }
}
