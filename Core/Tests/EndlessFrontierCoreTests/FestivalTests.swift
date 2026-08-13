import Testing
import Foundation
@testable import EndlessFrontierCore

/// Midsummer, and the thing it exists to fix.
///
/// The colony does not die of hunger or of raiders — it dies because the people
/// who could still start a family stop being drawn next to each other once the
/// village is big and old. `fert` in `GrowthProbe.theCurve` runs nine to twelve
/// while it grows and one to four for the whole second century. These are the
/// tests that the fires actually answer that, rather than merely being a party.
@Suite("Midsummer")
struct FestivalTests {

    private func registry() throws -> GameDataRegistry { try GameDataRegistry.bundled() }

    /// A colony of unattached young adults with a full larder and no bonds at
    /// all — the state the second century arrives in, minus the marriages.
    private func village(
        _ registry: GameDataRegistry, souls: Int = 20, food: Double = 600,
        ages: (Int) -> Int = { 22 + $0 % 8 }
    ) -> Settlement {
        var s = Settlement(
            id: UUID(uuidString: "FE571A00-0000-0000-0000-000000000001")!,
            name: "Midsummer",
            storage: [.food: food, .materials: 200], storageCapacity: .uniform(2000))
        for i in 0..<souls {
            var p = Pawn(id: UUID(uuidString: String(
                format: "FE571A00-1111-0000-0000-%012d", i))!, name: "Soul \(i)")
            p.age = ages(i) * registry.config.ticksPerYear
            s.pawns.append(p)
        }
        return s
    }

    private func hold(_ s: Settlement, _ reg: GameDataRegistry, tick: Int = 30) -> Settlement {
        FestivalEngine.hold(s, tick: tick, ticksPerYear: reg.config.ticksPerYear,
                            mapSeed: 4242)
    }

    // MARK: - The night itself

    @Test("The fires are lit once a year, and not at the turn of it")
    func onceAYear() throws {
        let reg = try registry()
        let perYear = reg.config.ticksPerYear
        let lit = (0..<(perYear * 3)).filter {
            FestivalEngine.isFestivalTick($0, ticksPerYear: perYear)
        }
        #expect(lit.count == 3, "three years and \(lit.count) midsummers")
        #expect(!lit.contains(0), """
            midsummer lands on the turn of the year, where SocietyEngine already \
            pays the wages, sorts the classes and holds the election
            """)
    }

    @Test("A feast comes out of the larder")
    func theFeastIsPaidFor() throws {
        let reg = try registry()
        let before = village(reg)
        let after = hold(before, reg)
        let spent = before.storage[.food] - after.storage[.food]
        #expect(spent > 0, "the colony threw a feast and ate nothing")
        #expect(spent <= FestivalEngine.feastPerHead * Double(before.pawns.count) + 0.001,
                "the feast ate \(spent), more than the \(before.pawns.count) mouths at it")
    }

    /// A festival must never be a way for a colony to starve itself. This is
    /// rule 22's shape — a survival path with a comfort threshold on it — and
    /// the answer is that the fires burn lower, not that the granary empties.
    @Test("A hungry colony holds a thin midsummer, not its last one")
    func nobodyStarvesForAParty() throws {
        let reg = try registry()
        let lean = village(reg, food: 12)
        let after = hold(lean, reg)
        #expect(after.storage[.food] > 0, "the colony ate its seed corn at a party")
        #expect(after.storage[.food] >= lean.storage[.food] * (1 - FestivalEngine.mostOfTheLarder) - 0.001)
    }

    @Test("A colony with nothing on the table knows it")
    func anEmptyYear() throws {
        let reg = try registry()
        var bare = village(reg, food: 0)
        bare.stats.morale = 50
        let after = hold(bare, reg)
        #expect(after.stats.morale < 50, "midsummer with an empty granary cost nothing")
        #expect(after.relationships.isEmpty, "a feast nobody could hold still made matches")
    }

    // MARK: - What it is for

    @Test("People who had never met stand at the same fire")
    func strangersMeet() throws {
        let reg = try registry()
        let before = village(reg)
        #expect(before.relationships.isEmpty)
        let after = hold(before, reg)
        #expect(after.relationships.count >= before.pawns.count, """
            twenty unattached adults round one fire and only \
            \(after.relationships.count) bonds came of it
            """)
    }

    /// The whole mechanism, stated: the fire puts the young in front of each
    /// other. Not a rule about who *may* marry — `SocialEngine` deleted its
    /// age-gap bar on purpose — a weighting on who stands where.
    @Test("The fire puts people beside their own age")
    func theYoungFindEachOther() throws {
        let reg = try registry()
        let perYear = reg.config.ticksPerYear
        // Half the colony in its twenties, half in its sixties.
        let split = village(reg, souls: 20, ages: { $0 < 10 ? 24 : 62 })
        let matches = FestivalEngine.whoMeetsWhom(split, ticksPerYear: perYear)
        #expect(!matches.isEmpty)
        let acrossTheYears = matches.count {
            abs($0.0.ageYears(ticksPerYear: perYear) - $0.1.ageYears(ticksPerYear: perYear)) > 20
        }
        #expect(Double(acrossTheYears) / Double(matches.count) < 0.2, """
            \(acrossTheYears) of \(matches.count) matches were made across a \
            generation — the fire is drawing at random again
            """)
    }

    @Test("A colonist whose head is already full still meets somebody")
    func aFullHeadMakesRoom() throws {
        let reg = try registry()
        var s = village(reg, souls: 12)
        // Fill one colonist's five slots with weak acquaintances.
        let crowded = s.pawns[0].id
        for i in 1...SocialEngine.maxRelationsPerPawn {
            s.relationships.append(Relationship(
                between: crowded, and: s.pawns[i].id, kind: .friend, strength: 5))
        }
        let after = hold(s, reg)
        let theirs = after.relationships(of: crowded)
        #expect(theirs.count <= SocialEngine.maxRelationsPerPawn,
                "the festival overfilled a colonist's head")
        #expect(theirs.contains { $0.strength > 5 }, """
            a sociable colonist was full, so the one night meant to find them \
            somebody did nothing at all
            """)
    }

    @Test("Two who stood at the fire enough midsummers are promised")
    func courtshipsBecomeMarriages() throws {
        let reg = try registry()
        var s = village(reg)
        let perYear = reg.config.ticksPerYear
        for year in 1...4 {
            s = hold(s, reg, tick: year * perYear + perYear / 2)
        }
        let couples = s.relationships.count { $0.kind == .partner }
        #expect(couples > 0, "four midsummers and nobody was spoken for")
    }

    /// The measurement that matters, run against the thing it was measured on:
    /// an **ageing** colony, where a uniform draw of meetings is a needle in a
    /// haystack and no rate can fix it.
    @Test("The fire finds couples an ordinary year never would")
    func midsummerBeatsChance() throws {
        let reg = try registry()
        let perYear = reg.config.ticksPerYear
        // Four young unattached adults in a village of thirty — the second
        // century's shape.
        let ageing = village(reg, souls: 30, ages: { $0 < 4 ? 23 : 58 })

        var withFires = ageing
        var withoutFires = ageing
        for year in 1...6 {
            let tick = year * perYear
            for step in 0..<perYear {
                withFires = SocialEngine.advanceOneTick(
                    withFires, registry: reg, tick: tick + step, mapSeed: 4242)
                withoutFires = SocialEngine.advanceOneTick(
                    withoutFires, registry: reg, tick: tick + step, mapSeed: 4242)
            }
            withFires = FestivalEngine.hold(
                withFires, tick: tick + perYear / 2, ticksPerYear: perYear, mapSeed: 4242)
        }
        func young(_ s: Settlement) -> Int {
            s.relationships.count { bond in
                guard bond.kind == .partner else { return false }
                return [bond.a, bond.b].allSatisfy { id in
                    guard let p = s.pawns.first(where: { $0.id == id }) else { return false }
                    return p.ageYears(ticksPerYear: perYear) < 45
                }
            }
        }
        #expect(young(withFires) > young(withoutFires), """
            six years on: \(young(withFires)) young couples with midsummer and \
            \(young(withoutFires)) without — the fire is not finding anybody \
            that chance would not have
            """)
    }

    // MARK: - The invariants

    @Test("The same seed holds the same midsummer")
    func deterministic() throws {
        let reg = try registry()
        let s = village(reg)
        let a = hold(s, reg), b = hold(s, reg)
        #expect(a == b, "two runs of one night came out different")
    }

    @Test("A married colonist does not stand at the courting fire")
    func theSpokenForStayHome() throws {
        let reg = try registry()
        var s = village(reg, souls: 6)
        s.relationships.append(Relationship(
            between: s.pawns[0].id, and: s.pawns[1].id, kind: .partner, strength: 80))
        let matches = FestivalEngine.whoMeetsWhom(s, ticksPerYear: reg.config.ticksPerYear)
        let spoken = Set([s.pawns[0].id, s.pawns[1].id])
        #expect(!matches.contains { spoken.contains($0.0.id) || spoken.contains($0.1.id) },
                "a married colonist was matched at the fire")
    }

    @Test("Midsummer reaches the world through a tick")
    func wiredIn() throws {
        let reg = try registry()
        var w = GameWorldFactory.newGame(registry: reg, seed: 4242)
        let before = w.settlements[0].journal.entries.count
        w = TickEngine.advance(w, ticks: reg.config.ticksPerYear + 1, registry: reg).state
        let midsummerLines = w.settlements[0].journal.entries.count { entry in
            let text = entry.text.resolve(.en)
            return text.contains("Midsummer") || text.contains("midsummer")
        }
        #expect(midsummerLines > 0, """
            a year of ticks and the chronicle never mentions midsummer \
            (\(before) → \(w.settlements[0].journal.entries.count) lines)
            """)
    }
}
