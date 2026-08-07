import Foundation
import Testing
@testable import EndlessFrontierCore

@Suite("Population life cycle")
struct PopulationTests {
    private let registry = Fixtures.registry()

    // A fixed id keeps the per-settlement RNG stream stable across runs, so
    // determinism tests compare like with like.
    private static let fixedID = UUID(uuidString: "00000000-0000-0000-00FF-000000000001")!

    private func village(_ pawns: [Pawn], food: Double = 500, id: UUID = fixedID) -> Settlement {
        Settlement(id: id, name: "Village", kind: .capital, pawns: pawns,
                   storage: [.food: food], storageCapacity: 999)
    }

    @Test("Everyone ages one tick per tick")
    func aging() {
        let s = village(Fixtures.pawns(3))
        let after = PopulationEngine.advanceOneTick(s, registry: registry, tick: 1, mapSeed: 7)
        #expect(after.pawns.allSatisfy { $0.age == Pawn.defaultAdultAgeTicks + 1 })
    }

    @Test("A pregnancy comes to term as a child with mutated genes and a dowry")
    func birth() {
        var parent = Pawn(name: "Mara", genes: Genes(industry: 0.9, fertility: 0.8), wealth: 100,
                          pregnancyTicksRemaining: 1)
        parent.mood = 80
        let s = village([parent])
        let after = PopulationEngine.advanceOneTick(s, registry: registry, tick: 10, mapSeed: 7)

        #expect(after.pawns.count == 2)
        let child = after.pawns[1]
        #expect(child.age == 0)
        #expect(!child.isAdult(ticksPerYear: registry.config.ticksPerYear))
        // Genes inherited within the mutation spread of the parent's.
        #expect(abs(child.genes.industry - 0.9) <= 0.09 + 1e-9)
        #expect(abs(child.genes.fertility - 0.8) <= 0.09 + 1e-9)
        // Dowry: 15 % of the parent's wealth changes hands.
        #expect(abs(child.wealth - 15) < 1e-9)
        #expect(abs(after.pawns[0].wealth - 85) < 1e-9)
    }

    @Test("Fertile, housed adults eventually conceive; a village at capacity doesn't")
    func conceptionRespectsHousing() {
        let fertile = (0..<10).map { i in
            Pawn(id: UUID(uuidString: String(format: "00000000-0000-0000-0002-%012d", i + 1))!,
                 name: "F\(i)", mood: 90, genes: Genes(fertility: 1.0))
        }
        // Housing: base 30 → 10 pawns have headroom.
        //
        // …and they have to be **married**. Children come out of a bond now
        // (`PopulationEngine.conceive`), not out of a per-colonist birth rate,
        // so ten strangers under one roof conceive nothing however fertile they
        // are — which is the point of the change and is worth a test saying so.
        var s = village(fertile)
        s.relationships = stride(from: 0, to: fertile.count - 1, by: 2).map {
            Relationship(between: fertile[$0].id, and: fertile[$0 + 1].id,
                         kind: .partner, strength: 90)
        }
        var conceived = false
        for tick in 0..<200 {
            s = PopulationEngine.advanceOneTick(s, registry: registry, tick: tick, mapSeed: 3)
            if s.pawns.contains(where: { $0.pregnancyTicksRemaining > 0 }) { conceived = true; break }
        }
        #expect(conceived)

        // At capacity (30 base housing, 30+ pawns) no new pregnancies start.
        var crowded = village((0..<35).map { i in
            Pawn(id: UUID(uuidString: String(format: "00000000-0000-0000-0003-%012d", i + 1))!,
                 name: "C\(i)", mood: 90, genes: Genes(fertility: 1.0))
        })
        for tick in 0..<100 {
            crowded = PopulationEngine.advanceOneTick(crowded, registry: registry, tick: tick, mapSeed: 3)
        }
        #expect(crowded.pawns.allSatisfy { $0.pregnancyTicksRemaining == 0 })
    }

    @Test("The old eventually pass away; the estate passes to a kin")
    func oldAgeDeath() {
        let ticksPerYear = registry.config.ticksPerYear
        let elder = Pawn(name: "Elder", age: 90 * ticksPerYear, wealth: 100)
        // A child heir won't die of old age during the run, so the estate has
        // exactly one place to go.
        let heir = Pawn(name: "Heir", age: 0)
        var s = village([elder, heir])
        var died = false
        for tick in 0..<3000 {
            s = PopulationEngine.advanceOneTick(s, registry: registry, tick: tick, mapSeed: 11)
            if s.pawns.count == 1 { died = true; break }
        }
        #expect(died)
        #expect(s.deathTallies[PawnDeathCause.oldAge.rawValue] == 1)
        #expect(s.pawns.first?.name == "Heir")
        #expect(abs((s.pawns.first?.wealth ?? 0) - 70) < 1e-9)   // 70 % inherited
    }

    @Test("The life cycle is deterministic for a given seed")
    func deterministic() {
        func run() -> Settlement {
            var s = village((0..<12).map { i in
                Pawn(id: UUID(uuidString: String(format: "00000000-0000-0000-0004-%012d", i + 1))!,
                     name: "P\(i)", mood: 85, genes: Genes(fertility: 0.9))
            })
            for tick in 0..<300 {
                s = PopulationEngine.advanceOneTick(s, registry: registry, tick: tick, mapSeed: 42)
            }
            return s
        }
        #expect(run() == run())
    }

    @Test("Children don't work; adults do")
    func childrenDontWork() {
        let child = Pawn(name: "Kid", skills: [.farming: 10], assignedWork: .farming, age: 0)
        let adult = Pawn(name: "Ada", skills: [.farming: 10], assignedWork: .farming)

        // Adding a farming child changes neither production nor consumption:
        // children eat (both settlements have both mouths) but don't work.
        let adultOnly = PawnEngine.advanceOneTick(village([adult], food: 100), registry: registry, tick: 0)
        let withChild = PawnEngine.advanceOneTick(village([adult, child], food: 100), registry: registry, tick: 0)
        #expect(abs(withChild.storage[.food] - adultOnly.storage[.food]) < 1e-9)

        // Only the adult earned XP toward the next level.
        #expect((withChild.pawns[1].skillXP[.farming] ?? 0) == 0)   // the child
        #expect((withChild.pawns[0].skillXP[.farming] ?? 0) > 0)    // the adult
    }
}
