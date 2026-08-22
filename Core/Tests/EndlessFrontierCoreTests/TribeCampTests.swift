import Testing
import Foundation
@testable import EndlessFrontierCore

/// Keks, on the neighbours: *"nyní jsou to basic postavičky a stany na mapě"*,
/// and, asked how far to take it, *"ideálně plné národy, ale klidně bych to
/// nejdřív trochu osekal… jen ať vypadají a chovají se nějak jako hlavní
/// pawni."*
///
/// This is stage one, and **the line stage one must not cross is that it adds
/// nothing to the tick.** Half these tests are about that line rather than
/// about how a camp looks, because it is the line that decides whether five
/// peoples on a map cost anything.
@Suite("A people, standing on their own ground")
struct TribeCampTests {

    private func registry() throws -> GameDataRegistry { try GameDataRegistry.bundled() }

    private func tribe(
        population: Double = 30, stores: Double = 90, defense: Double = 10,
        courage: Double = 0.5, wars: Int = 0
    ) -> Tribe {
        Tribe(id: UUID(uuidString: "00000000-0000-0000-0000-0000000000AA")!,
              name: "Lidé od řeky", regionID: nil, foundedTick: 0,
              originStory: LocalizedText(values: [.en: "left", .cs: "odešli"]),
              population: population,
              genes: Genes(industry: 0.5, fertility: 0.5, sociability: 0.5, courage: courage),
              defense: defense, stores: stores, standing: 0, grudge: 0,
              married: false, wars: wars, defections: 0, isNative: true, discovered: true)
    }

    private func camp(_ tribe: Tribe, registry: GameDataRegistry, seed: UInt64 = 4242) -> Settlement {
        TribeCamp.settlement(for: tribe, mapSeed: seed, era: .earlySettlement,
                             registry: registry, language: .cs)
    }

    // MARK: - They are people, and they are in a place

    @Test("A people has roofs on the ground and folk under them")
    func aCampIsAPlace() throws {
        let registry = try registry()
        let s = camp(tribe(), registry: registry)
        #expect(s.colony?.placements.isEmpty == false, "a camp with nothing on it is the old ring of tents")
        #expect(s.pawns.count > 4)
        // Real people: bodies, ages, trades. Not marks orbiting a fire.
        #expect(s.pawns.allSatisfy { $0.age > 0 })
        #expect(s.pawns.allSatisfy { $0.assignedWork != .idle })
        #expect(Set(s.pawns.map(\.name)).count > 1)
    }

    @Test("Everybody has a roof of their own to walk back to")
    func everybodyIsHoused() throws {
        let registry = try registry()
        let s = camp(tribe(population: 20), registry: registry)
        let housed = s.pawns.filter { $0.homeID != nil }.count
        #expect(housed > s.pawns.count / 2,
                "\(housed) of \(s.pawns.count) had a roof — the rest have nowhere to be drawn going")
    }

    /// Rule 2, and the one that cost a session on the founders: the same world
    /// must put the same person outside the same tent every time it is opened.
    @Test("The same people are the same people every time their hex is opened")
    func aCampIsDeterministic() throws {
        let registry = try registry()
        let people = tribe()
        let a = camp(people, registry: registry), b = camp(people, registry: registry)
        #expect(a.pawns.map(\.id) == b.pawns.map(\.id))
        #expect(a.pawns.map(\.name) == b.pawns.map(\.name))
        #expect(a.colony?.placements.map(\.coord.x) == b.colony?.placements.map(\.coord.x))
    }

    @Test("Two peoples are not the same people")
    func campsDiffer() throws {
        let registry = try registry()
        var other = tribe()
        other = Tribe(id: UUID(uuidString: "00000000-0000-0000-0000-0000000000BB")!,
                      name: other.name, regionID: nil, foundedTick: 0,
                      originStory: other.originStory, population: other.population,
                      genes: other.genes, defense: other.defense, stores: other.stores,
                      standing: 0, grudge: 0, married: false, wars: 0, defections: 0,
                      isNative: true, discovered: true)
        #expect(camp(tribe(), registry: registry).pawns.map(\.name)
                != camp(other, registry: registry).pawns.map(\.name))
    }

    // MARK: - The camp says what the numbers say

    /// Rule 18 — the drawing is a picture of what the engine holds. A people
    /// who have grown must visibly have grown.
    @Test("A people who have grown have more roofs")
    func roofsFollowPopulation() throws {
        let registry = try registry()
        let small = camp(tribe(population: 8), registry: registry)
        let large = camp(tribe(population: 60), registry: registry)
        let smallRoofs = small.colony?.placements.count(where: { $0.definitionID == "hut" }) ?? 0
        let largeRoofs = large.colony?.placements.count(where: { $0.definitionID == "hut" }) ?? 0
        #expect(largeRoofs > smallRoofs)
        #expect(large.pawns.count > small.pawns.count)
    }

    @Test("A people who have been at war have put a fence up")
    func warBuildsAPalisade() throws {
        let registry = try registry()
        let peaceful = TribeCamp.roster(for: tribe(defense: 5, wars: 0), era: .earlySettlement, drawn: 20)
        let fought = TribeCamp.roster(for: tribe(defense: 5, wars: 2), era: .earlySettlement, drawn: 20)
        #expect(!peaceful.contains { $0.definitionID == "palisade" })
        #expect(fought.contains { $0.definitionID == "palisade" })
    }

    @Test("A people with a full granary have somewhere to keep it")
    func storesBuildAGranary() throws {
        #expect(!TribeCamp.roster(for: tribe(stores: 10), era: .earlySettlement, drawn: 12)
            .contains { $0.definitionID == "granary" })
        #expect(TribeCamp.roster(for: tribe(stores: 200), era: .earlySettlement, drawn: 12)
            .contains { $0.definitionID == "granary" })
    }

    /// A tribe of four hundred is four hundred figures at thirty frames a
    /// second, for a place the player is only visiting.
    @Test("A very large people is drawn, not simulated to death")
    func theRosterIsCapped() throws {
        let registry = try registry()
        let s = camp(tribe(population: 900), registry: registry)
        #expect(s.pawns.count == TribeCamp.mostDrawn)
        #expect((s.colony?.placements.count ?? 0) < 40, "a camp is not a city of lots")
    }

    // MARK: - Stage one adds nothing to the tick

    /// The line. If this ever fails, the neighbours have quietly become a
    /// second simulation and the cost of five of them wants measuring first.
    @Test("Deriving a people costs the world nothing")
    func nothingIsStored() throws {
        let registry = try registry()
        var world = GameWorldFactory.newGame(registry: registry, seed: 4242)
        world = TickEngine.advance(world, ticks: 30, registry: registry).state
        let before = world
        for people in world.tribes {
            _ = TribeCamp.settlement(for: people, mapSeed: world.mapSeed,
                                     era: world.era, registry: registry)
        }
        #expect(world.settlements.count == before.settlements.count)
        #expect(world.tribes == before.tribes,
                "a camp that writes back to its tribe is stage two wearing stage one's hat")
    }

    @Test("A tribe's camp is not one of the world's settlements")
    func campsAreNotSettlements() throws {
        let registry = try registry()
        var world = GameWorldFactory.newGame(registry: registry, seed: 4242)
        world = TickEngine.advance(world, ticks: 60, registry: registry).state
        guard let people = world.tribes.first else { return }
        let s = TribeCamp.settlement(for: people, mapSeed: world.mapSeed,
                                     era: world.era, registry: registry)
        #expect(!world.settlements.contains { $0.id == s.id },
                "the tick walks `settlements`; a camp in it is a camp that eats")
    }

    /// Deriving a camp happens when a hex is opened, and the cost is almost
    /// all `ColonyBuilder.seededLayout` — which the colony itself pays at the
    /// founding and at load, so nobody had ever timed it.
    ///
    /// It was **321 ms**, because `fits` asks `ColonyMap.placement(at:)` — a
    /// walk over every placement — and the three functions that search for a
    /// spot ask `fits` on every tile of a 34×34 grid. Indexing the occupied
    /// tiles once per search took it to 68 ms.
    ///
    /// The bar below is a **debug** number: tests build without optimisation
    /// and the shipped build is several times faster. It is set to catch the
    /// shape of the regression — a linear search inside a grid scan, rule 38 —
    /// rather than to pin a frame budget, and the camp is derived off the main
    /// actor anyway.
    @Test("Deriving a people does not walk the whole colony per tile")
    func derivingIsCheap() throws {
        let registry = try registry()
        let people = tribe(population: 200)
        let began = Date()
        for _ in 0..<20 { _ = camp(people, registry: registry) }
        let each = Date().timeIntervalSince(began) / 20
        #expect(each < 0.15, "\(Int(each * 1000)) ms each, unoptimised — it was 400")
    }
}
