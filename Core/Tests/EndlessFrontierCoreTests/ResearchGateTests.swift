import Testing
import Foundation
@testable import EndlessFrontierCore

/// **You cannot study the steam engine in the year you invent the plough.**
///
/// The only gate on research was the DAG — `requires` met, not already done —
/// so the council picked the cheapest tech *anywhere on the board*. Measured
/// over two centuries (`ResearchProbe`): a colony still in the **medieval** era
/// was studying `computing` at year 110 and `space_program` at year 120, and
/// had the whole sixty-tech tree finished by year 160 while three ages of the
/// game were still ahead of it. An age is a thing you live in.
@Suite("What a colony may study")
struct ResearchGateTests {

    private func registry() throws -> GameDataRegistry { try GameDataRegistry.bundled() }

    private func world(era: Era, researched: Set<String> = []) -> WorldState {
        var s = WorldState(tick: 600, mapSeed: 3, settlements: [
            Settlement(id: UUID(uuidString: "5EA00000-0000-0000-0000-000000000001")!,
                       name: "Study", storage: [.knowledge: 40_000],
                       storageCapacity: .uniform(80_000))
        ])
        s.era = era
        s.researchedTechs = researched
        return s
    }

    @Test("A colony may study the age it lives in")
    func theCurrentAgeIsOpen() throws {
        let reg = try registry()
        let tech = try #require(reg.techs.values.first { $0.era == .earlySettlement
            && $0.requires.isEmpty })
        #expect(TechEngine.isStudiable(tech, in: world(era: .earlySettlement)))
    }

    /// The rung that must exist: every era's milestone tech belongs either to
    /// the age before it or to the age itself — `electricity` is a *modern*
    /// tech and is what unlocks the modern era — so one age of reach is not
    /// generosity, it is the ladder (rule 66).
    @Test("…and the next one, which is where the next age's key lies")
    func oneAgeOfReach() throws {
        let reg = try registry()
        let electricity = try #require(reg.tech("electricity"))
        #expect(electricity.era == .modern)
        let ready = world(era: .earlyIndustrial,
                          researched: Set(reg.techs.values
                            .filter { $0.era.index < Era.modern.index }
                            .map(\.id)))
        #expect(TechEngine.isStudiable(electricity, in: ready),
                "the modern era's own key is out of reach of the age before it")
    }

    @Test("A colony may not study three ages ahead of itself")
    func theFarFutureIsShut() throws {
        let reg = try registry()
        let far = try #require(reg.techs.values.first { $0.era == .nearFuture })
        var everythingBefore = world(era: .medieval)
        everythingBefore.researchedTechs = Set(reg.techs.values.map(\.id))
            .subtracting([far.id])
        #expect(!TechEngine.isStudiable(far, in: everythingBefore))
    }

    @Test("The council never picks something out of its age")
    func theStewardHonoursTheGate() throws {
        let reg = try registry()
        var state = world(era: .earlySettlement)
        // Walk the council forward a hundred picks; nothing it chooses may
        // belong to an age more than one ahead of the one it lives in.
        for _ in 0..<100 {
            guard let pick = StewardEngine.nextTech(for: state, registry: reg),
                  let tech = reg.tech(pick) else { break }
            #expect(tech.era.index <= state.era.index + TechEngine.eraReach,
                    "the council picked a study out of its own age")
            state.researchedTechs.insert(pick)
        }
    }

    @Test("Setting a study out of its age is refused, not obeyed")
    func theExplicitChoiceIsGatedToo() throws {
        let reg = try registry()
        let far = try #require(reg.techs.values.first { $0.era == .nearFuture })
        // Everything it asks for, learned — so the only thing left refusing it
        // is the age the colony is living in.
        var ready = world(era: .earlySettlement)
        ready.researchedTechs = Set(far.requires)
        let state = TechEngine.setResearch(ready, techID: far.id, registry: reg)
        #expect(state.activeResearch == nil)
    }

    /// A colony that has learned everything its age allows **banks** what its
    /// scholars make. That is the point: knowledge piling up is a reason to
    /// grow into the next age, where before it was a tree that simply ran out
    /// with seventy years of game left (rule 28 — an empty option list wants a
    /// diagnosis, and this is one).
    @Test("Nothing to study is a bank, not a stall")
    func knowledgeKeepsWhenTheAgeIsExhausted() throws {
        let reg = try registry()
        var state = world(era: .earlySettlement)
        state.researchedTechs = Set(reg.techs.values
            .filter { $0.era.index <= Era.ancient.index }.map(\.id))
        state = StewardEngine.chooseResearch(state, registry: reg)
        // Either it found something in reach, or it found nothing and kept the
        // bank — what it must never do is spend the knowledge on nothing.
        let banked = state.settlements[0].storage[.knowledge]
        #expect(banked >= 40_000 - 1)
        if let active = state.activeResearch, let tech = reg.tech(active) {
            #expect(tech.era.index <= Era.earlySettlement.index + TechEngine.eraReach)
        }
    }
}
