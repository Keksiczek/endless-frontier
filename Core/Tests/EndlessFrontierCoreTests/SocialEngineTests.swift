import Foundation
import Testing
@testable import EndlessFrontierCore

/// Village life: friendships form, quarrels sting, weddings bind, grief cuts.
@Suite("Social engine")
struct SocialEngineTests {
    private let registry = Fixtures.registry()
    private let seed: UInt64 = 0x5eed_0001   // fixed world seed

    private func village(_ count: Int, sociability: Double = 0.8) -> Settlement {
        var pawns = Fixtures.pawns(count, work: .farming)
        for i in pawns.indices {
            pawns[i].genes = Genes(industry: 0.5, fertility: 0.5,
                                   sociability: sociability, courage: 0.5)
        }
        return Settlement(id: UUID(uuidString: "BBBBBBBB-0000-0000-0000-000000000001")!,
                          name: "Ves", kind: .capital, pawns: pawns,
                          storage: [.food: 500], storageCapacity: 9999)
    }

    private func advance(_ settlement: Settlement, ticks: Int) -> Settlement {
        var s = settlement
        for tick in 0..<ticks {
            s = SocialEngine.advanceOneTick(s, registry: registry, tick: tick, mapSeed: seed)
        }
        return s
    }

    @Test("A sociable village grows friendships, and some reach the journal")
    func friendshipsForm() {
        let after = advance(village(12), ticks: 240)
        #expect(!after.relationships.isEmpty)
        #expect(after.relationships.contains { $0.kind == .friend })
        #expect(after.journal.entries.contains { $0.kind == .social })
    }

    @Test("Village life is deterministic for a given seed")
    func deterministic() {
        let a = advance(village(10), ticks: 120)
        let b = advance(village(10), ticks: 120)
        #expect(a == b)
    }

    @Test("Close friends eventually wed, and the wedding makes the journal")
    func friendsWed() {
        var s = village(8)
        // Two colonists already fast friends.
        s.relationships = [Relationship(between: s.pawns[0].id, and: s.pawns[1].id,
                                        kind: .friend, strength: 80)]
        let after = advance(s, ticks: 600)
        #expect(after.relationships.contains { $0.kind == .partner })
        #expect(after.journal.entries.contains {
            $0.text.resolve(.cs).contains("svatbu") || $0.text.resolve(.en).contains("wed")
        })
    }

    @Test("Nobody takes a second spouse")
    func monogamy() {
        let after = advance(village(14), ticks: 900)
        var spouses: [UUID: Int] = [:]
        for bond in after.relationships where bond.kind == .partner {
            spouses[bond.a, default: 0] += 1
            spouses[bond.b, default: 0] += 1
        }
        #expect(spouses.values.allSatisfy { $0 <= 1 })
    }

    @Test("Death of a spouse brings grief and lays the bond to rest")
    func mourning() {
        var s = village(6)
        let widow = s.pawns[0]
        let dead = s.pawns[1]
        s.relationships = [Relationship(between: widow.id, and: dead.id,
                                        kind: .partner, strength: 90)]
        s.pawns.removeAll { $0.id == dead.id }

        let after = SocialEngine.mourn(s, dead: dead, tick: 10)
        #expect(after.relationships.isEmpty)
        #expect(after.pawns[0].needs.recreation < widow.needs.recreation)
        #expect(after.journal.entries.contains {
            $0.text.resolve(.cs).contains("truchlí") || $0.text.resolve(.en).contains("mourns")
        })
    }

    @Test("Bonds to colonists who left are pruned")
    func pruning() {
        var s = village(6)
        let ghost = UUID(uuidString: "DDDDDDDD-0000-0000-0000-000000000099")!
        s.relationships = [Relationship(between: s.pawns[0].id, and: ghost,
                                        kind: .friend, strength: 60)]
        let after = SocialEngine.advanceOneTick(s, registry: registry, tick: 0, mapSeed: seed)
        #expect(after.relationships.allSatisfy { $0.other(than: ghost) == nil })
    }

    @Test("Marriage fills more cradles than solitude")
    func partneredFertility() {
        // Same village twice: once everyone married, once everyone single.
        func pregnancies(married: Bool) -> Int {
            var s = village(12)
            let ticksPerYear = registry.config.ticksPerYear
            for i in s.pawns.indices {
                s.pawns[i].age = 25 * ticksPerYear   // squarely fertile
                s.pawns[i].genes = Genes(industry: 0.5, fertility: 0.9,
                                         sociability: 0.5, courage: 0.5)
            }
            if married {
                for pair in stride(from: 0, to: s.pawns.count - 1, by: 2) {
                    s.relationships.append(Relationship(
                        between: s.pawns[pair].id, and: s.pawns[pair + 1].id,
                        kind: .partner, strength: 90))
                }
            }
            var total = 0
            for tick in 0..<1200 {
                let before = s.pawns.filter { $0.pregnancyTicksRemaining > 0 }.count
                s = PopulationEngine.advanceOneTick(s, registry: registry, tick: tick, mapSeed: seed)
                let now = s.pawns.filter { $0.pregnancyTicksRemaining > 0 }.count
                total += max(0, now - before)
            }
            return total
        }
        #expect(pregnancies(married: true) > pregnancies(married: false))
    }
}
