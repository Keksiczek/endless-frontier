import Testing
import Foundation
@testable import EndlessFrontierCore

/// A colony handing itself on: the day a child is counted grown, and the old
/// standing at the elbow of the young.
///
/// The same measured failure as `FestivalTests`, from the other end. Midsummer
/// finds the young each other; this is about there being young to find, and
/// about a trade outliving the person who was good at it.
@Suite("One generation to the next")
struct GenerationTests {

    private func registry() throws -> GameDataRegistry { try GameDataRegistry.bundled() }

    private func pawn(_ n: Int, years: Int, ticksPerYear: Int,
                      work: WorkKind = .farming, skill: Int = 0) -> Pawn {
        var p = Pawn(id: UUID(uuidString: String(
            format: "6E4E0000-0000-0000-0000-%012d", n))!, name: "Soul \(n)")
        p.age = years * ticksPerYear
        p.assignedWork = work
        p.skills[work] = skill
        return p
    }

    private func town(_ reg: GameDataRegistry, _ pawns: [Pawn]) -> Settlement {
        var s = Settlement(
            id: UUID(uuidString: "6E4E0000-0000-0000-0000-0000000000FF")!,
            name: "Handover",
            storage: [.food: 600, .materials: 200], storageCapacity: .uniform(2000))
        s.pawns = pawns
        return s
    }

    // MARK: - Coming of age

    @Test("The day a colonist is counted grown is a day in the chronicle")
    func theDayIsMarked() throws {
        let reg = try registry()
        let perYear = reg.config.ticksPerYear
        var s = town(reg, [pawn(1, years: Pawn.adultAgeYears, ticksPerYear: perYear),
                           pawn(2, years: 30, ticksPerYear: perYear)])
        let before = s.journal.entries.count
        s = GenerationEngine.comeOfAge(s, tick: 100, ticksPerYear: perYear)
        #expect(s.journal.entries.count > before)
        #expect(s.journal.entries.last?.subject == .pawn(s.pawns[0].id),
                "the line does not say who it is about, so the camera cannot go to them")
    }

    /// The crossing happens on exactly one tick, and `PopulationEngine` moves
    /// every age by exactly one per tick. A `>=` here would fire for every adult
    /// in the colony, every tick, for ever.
    @Test("It happens once, not every tick thereafter")
    func onlyOnTheDay() throws {
        let reg = try registry()
        let perYear = reg.config.ticksPerYear
        let grown = town(reg, [pawn(1, years: Pawn.adultAgeYears + 1, ticksPerYear: perYear),
                               pawn(2, years: 30, ticksPerYear: perYear)])
        let after = GenerationEngine.comeOfAge(grown, tick: 100, ticksPerYear: perYear)
        #expect(after.journal.entries.count == grown.journal.entries.count,
                "a colonist who grew up years ago came of age again today")
    }

    /// The point of it: a new adult already knows the people they grew up with,
    /// so the fertile window is not a room full of strangers.
    @Test("A new adult already knows the ones they grew up with")
    func childhoodCounts() throws {
        let reg = try registry()
        let perYear = reg.config.ticksPerYear
        var s = town(reg, [
            pawn(1, years: Pawn.adultAgeYears, ticksPerYear: perYear),
            pawn(2, years: Pawn.adultAgeYears + 1, ticksPerYear: perYear),
            pawn(3, years: Pawn.adultAgeYears + 2, ticksPerYear: perYear),
            pawn(4, years: 60, ticksPerYear: perYear)])
        s = GenerationEngine.comeOfAge(s, tick: 100, ticksPerYear: perYear)
        let theirs = s.relationships(of: s.pawns[0].id)
        #expect(theirs.count >= 2, "grew up in a village and knows nobody")
        let elder = s.pawns[3].id
        #expect(!theirs.contains { $0.involves(elder) },
                "a fourteen-year-old 'grew up with' somebody sixty")
    }

    /// A head start, not a betrothal: the bond has to stay under the wedding
    /// threshold or coming of age would marry people off on their birthday.
    @Test("Growing up together is a head start, not a betrothal")
    func notABetrothal() {
        #expect(GenerationEngine.childhoodBondStrength < SocialEngine.weddingMinStrength)
        #expect(GenerationEngine.childhoodBondStrength > SocialEngine.strengthPerChat)
    }

    @Test("A childhood does not turn a grudge into a friendship")
    func grudgesSurviveChildhood() throws {
        let reg = try registry()
        let perYear = reg.config.ticksPerYear
        var s = town(reg, [pawn(1, years: Pawn.adultAgeYears, ticksPerYear: perYear),
                           pawn(2, years: Pawn.adultAgeYears, ticksPerYear: perYear)])
        s.relationships.append(Relationship(
            between: s.pawns[0].id, and: s.pawns[1].id, kind: .rival, strength: 30))
        s = GenerationEngine.comeOfAge(s, tick: 100, ticksPerYear: perYear)
        #expect(s.relationships.first?.kind == .rival,
                "two who could not stand each other became friends by turning fourteen")
    }

    // MARK: - What the old know

    @Test("An elder at the elbow makes a pupil learn faster")
    func theOldTeachTheYoung() throws {
        let reg = try registry()
        let perYear = reg.config.ticksPerYear
        let s = town(reg, [
            pawn(1, years: 60, ticksPerYear: perYear, skill: 14),
            pawn(2, years: 20, ticksPerYear: perYear, skill: 2)])
        let after = GenerationEngine.teach(s, tick: 100, ticksPerYear: perYear)
        #expect((after.pawns[1].skillXP[.farming] ?? 0) > 0,
                "sixty years of knowing how, and none of it went anywhere")
        #expect(after.pawns[0].skillXP[.farming] ?? 0 == 0,
                "the elder learned from the pupil")
    }

    @Test("Nobody teaches what the pupil already knows")
    func noPointlessLessons() throws {
        let reg = try registry()
        let perYear = reg.config.ticksPerYear
        let level = town(reg, [
            pawn(1, years: 60, ticksPerYear: perYear, skill: 9),
            pawn(2, years: 20, ticksPerYear: perYear, skill: 9)])
        let after = GenerationEngine.teach(level, tick: 100, ticksPerYear: perYear)
        #expect((after.pawns[1].skillXP[.farming] ?? 0) == 0)
    }

    @Test("One elder teaches one pupil")
    func oneAtATime() throws {
        let reg = try registry()
        let perYear = reg.config.ticksPerYear
        let s = town(reg, [
            pawn(1, years: 60, ticksPerYear: perYear, skill: 14),
            pawn(2, years: 20, ticksPerYear: perYear, skill: 1),
            pawn(3, years: 22, ticksPerYear: perYear, skill: 2)])
        let after = GenerationEngine.teach(s, tick: 100, ticksPerYear: perYear)
        let learning = after.pawns.count { ($0.skillXP[.farming] ?? 0) > 0 }
        #expect(learning == 1, "\(learning) pupils at one elder's elbow")
    }

    @Test("An elder only teaches their own trade")
    func ownTradeOnly() throws {
        let reg = try registry()
        let perYear = reg.config.ticksPerYear
        let s = town(reg, [
            pawn(1, years: 60, ticksPerYear: perYear, work: .farming, skill: 14),
            pawn(2, years: 20, ticksPerYear: perYear, work: .mining, skill: 1)])
        let after = GenerationEngine.teach(s, tick: 100, ticksPerYear: perYear)
        #expect((after.pawns[1].skillXP[.mining] ?? 0) == 0,
                "a farmer taught somebody to mine")
    }

    @Test("A trade outlives the person who was good at it")
    func theTradeSurvives() throws {
        let reg = try registry()
        let perYear = reg.config.ticksPerYear
        var s = town(reg, [
            pawn(1, years: 60, ticksPerYear: perYear, skill: 12),
            pawn(2, years: 20, ticksPerYear: perYear, skill: 2)])
        for step in stride(from: 0, to: 4000, by: GenerationEngine.teachingInterval) {
            s = GenerationEngine.teach(s, tick: step, ticksPerYear: perYear)
        }
        #expect(s.pawns[1].skill(.farming) >= 10, """
            a lifetime at a master's elbow and the pupil reached \
            \(s.pawns[1].skill(.farming)) of the elder's 12
            """)
    }

    // MARK: - Invariants

    @Test("Nothing here is drawn — the same state gives the same day")
    func deterministic() throws {
        let reg = try registry()
        let perYear = reg.config.ticksPerYear
        let s = town(reg, [
            pawn(1, years: Pawn.adultAgeYears, ticksPerYear: perYear, skill: 1),
            pawn(2, years: Pawn.adultAgeYears, ticksPerYear: perYear, skill: 2),
            pawn(3, years: 60, ticksPerYear: perYear, skill: 14)])
        let a = GenerationEngine.teach(
            GenerationEngine.comeOfAge(s, tick: 100, ticksPerYear: perYear),
            tick: 100, ticksPerYear: perYear)
        let b = GenerationEngine.teach(
            GenerationEngine.comeOfAge(s, tick: 100, ticksPerYear: perYear),
            tick: 100, ticksPerYear: perYear)
        #expect(a == b)
    }

    @Test("It reaches the world through a tick")
    func wiredIn() throws {
        let reg = try registry()
        var w = GameWorldFactory.newGame(registry: reg, seed: 4242)
        // Far enough that somebody born in the first years has grown up.
        w = TickEngine.advance(w, ticks: reg.config.ticksPerYear * 20, registry: reg).state
        let grownUp = w.settlements[0].journal.entries.count {
            $0.text.resolve(.en).contains("counted a grown colonist")
        }
        #expect(grownUp > 0, "twenty years and nobody in the colony ever grew up")
    }
}
