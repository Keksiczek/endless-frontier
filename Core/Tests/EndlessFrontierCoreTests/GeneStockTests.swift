import Testing
import Foundation
@testable import EndlessFrontierCore

/// Where a newcomer's dispositions come from, and why it matters.
@Suite("Somebody who arrives came from somewhere")
struct GeneStockTests {

    @Test("A stranger from nowhere is a fresh roll around the middle")
    func noStockIsTheOldBehaviour() {
        let drawn = (0..<200).map {
            PawnFactory.generate(seed: UInt64($0) &* 0x9E37_79B9).genes.industry
        }
        let mean = drawn.reduce(0, +) / Double(drawn.count)
        #expect(abs(mean - 0.5) < 0.05, "`Genes.founder` is centred on 0.5 by construction")
    }

    @Test("Somebody drawn from a people takes after that people")
    func stockCarries() {
        let hardy = Genes(industry: 0.85, fertility: 0.2, sociability: 0.5, courage: 0.9)
        let drawn = (0..<200).map {
            PawnFactory.generate(seed: UInt64($0) &* 0x9E37_79B9, stock: hardy).genes
        }
        let industry = drawn.map(\.industry).reduce(0, +) / Double(drawn.count)
        let fertility = drawn.map(\.fertility).reduce(0, +) / Double(drawn.count)
        // Within the individual spread of the folk they came from — not
        // dragged back toward 0.5, which is the whole point.
        #expect(abs(industry - hardy.industry) < Genes.stockSpread)
        #expect(abs(fertility - hardy.fertility) < Genes.stockSpread)
        #expect(industry > 0.7)
        #expect(fertility < 0.3)
    }

    @Test("The mean of nobody is nobody")
    func meanOfEmpty() {
        #expect(Genes.mean(of: []) == nil)
    }

    @Test("An outpost is founded by your own people, not by strangers")
    func outpostCarriesTheRealm() throws {
        let registry = try GameDataRegistry.bundled()
        var state = GameWorldFactory.newGame(registry: registry, seed: 4242)
        // Make the realm markedly unlike the middle, so "took after them" and
        // "rolled fresh" cannot look the same.
        for index in state.settlements[0].pawns.indices {
            state.settlements[0].pawns[index].genes = Genes(
                industry: 0.9, fertility: 0.9, sociability: 0.9, courage: 0.9)
        }
        state.settlements[0].storage[.materials] = 500
        state.settlements[0].storage[.influence] = 500
        guard let target = state.regions.first(where: {
            $0.id != state.settlements[0].regionID
        }) else { return }
        if let index = state.regions.firstIndex(where: { $0.id == target.id }) {
            state.regions[index].explorationState = .fullyExplored
        }
        let after = ExpansionEngine.foundOutpost(state, regionID: target.id,
                                                 name: "Test", registry: registry)
        guard let outpost = after.settlements.first(where: { $0.kind == .outpost })
        else { return }
        let mean = Genes.mean(of: outpost.pawns.map(\.genes))
        #expect(mean != nil)
        #expect((mean?.industry ?? 0) > 0.7,
                "settlers who walked out of a diligent realm are diligent")
    }

    // MARK: - The gene couplings

    @Test("A colonist's fertility moves their chance of a child, and 0.5 changes nothing")
    func fertilityFactorIsCentred() {
        #expect(PopulationEngine.fertilityFactor(Genes(fertility: 0.5)) == 1)
        #expect(PopulationEngine.fertilityFactor(Genes(fertility: 0.9)) > 1.3)
        #expect(PopulationEngine.fertilityFactor(Genes(fertility: 0.1)) < 0.7)
        #expect(PopulationEngine.fertilityFactor(Genes(fertility: 0)) > 0,
                "nobody is barred outright — the taper is the age, not the gene")
    }

    @Test("Two sociable colonists grow closer faster, and average ones no faster than before")
    func bondPullIsCentred() {
        let middling = Genes(sociability: 0.5)
        #expect(SocialEngine.bondPull(middling, middling) == 1)
        #expect(SocialEngine.bondPull(Genes(sociability: 0.9), Genes(sociability: 0.9)) > 1.2)
        #expect(SocialEngine.bondPull(Genes(sociability: 0.1), Genes(sociability: 0.1)) < 0.8)
    }

    @Test("Of those with nothing to lose, the boldest walk out first")
    func theBoldLeaveFirst() {
        let bold = Pawn(name: "Bold", genes: Genes(courage: 0.9))
        let meek = Pawn(name: "Meek", genes: Genes(courage: 0.2))
        #expect(DiplomacyEngine.boldestFirst(bold, meek))
        #expect(!DiplomacyEngine.boldestFirst(meek, bold))
    }
}

/// The save carries the world, all of it.
@Suite("What a save actually keeps")
struct SavePersistenceTests {

    @Test("Roads survive a save")
    func roadsPersist() throws {
        // They did not. `roads` and `roadTraffic` had no `CodingKeys` case, so
        // every way the colony built was dropped on write and came back an
        // empty network — invisible until the map began generating with ancient
        // stone already on it.
        let registry = try GameDataRegistry.bundled()
        var world = GameWorldFactory.newGame(registry: registry, seed: 4242)
        world.roads.lay(RoadLink(a: HexCoord(0, 0), b: HexCoord(1, 0), grade: .paved))
        world.roadTraffic[RoadLink.key(HexCoord(0, 0), HexCoord(1, 0))] = 12.5

        let data = try JSONEncoder().encode(world)
        let restored = try JSONDecoder().decode(WorldState.self, from: data)
        #expect(restored.roads.link(HexCoord(0, 0), HexCoord(1, 0))?.grade == .paved)
        #expect(restored.roadTraffic[RoadLink.key(HexCoord(0, 0), HexCoord(1, 0))] == 12.5)
        #expect(restored.roads == world.roads)
    }

    @Test("An ancient way is still ancient after a save")
    func originSurvives() throws {
        let link = RoadLink(a: HexCoord(0, 0), b: HexCoord(1, 0),
                            grade: .paved, condition: 0.22, origin: .ancient)
        let restored = try JSONDecoder().decode(
            RoadLink.self, from: JSONEncoder().encode(link))
        #expect(restored == link)
        #expect(restored.origin == .ancient)
    }

    @Test("A road saved before origins existed is one somebody built")
    func oldSavesDecode() throws {
        let json = Data(#"{"a":{"q":0,"r":0},"b":{"q":1,"r":0},"grade":"road","condition":0.8}"#.utf8)
        let link = try JSONDecoder().decode(RoadLink.self, from: json)
        #expect(link.origin == .built)
    }
}

/// The counters that tell "nobody came" from "it was not recorded" (rule 67).
@Suite("Births and arrivals are counted, not inferred")
struct ColonyTallyTests {

    @Test("A newborn is counted once, and not off the diary")
    func birthsAreTallied() throws {
        let registry = try GameDataRegistry.bundled()
        var state = GameWorldFactory.newGame(registry: registry, seed: 4242)
        #expect(state.settlements[0].birthTally == 0)
        state = TickEngine.advance(state, ticks: 2000, registry: registry).state
        let settlement = state.settlements[0]
        #expect(settlement.birthTally > 0, "a colony that has no children has no future")
        // `ColonyLog` is a 140-entry ring, so the diary undercounts as soon as
        // the colony outlives it. The tally is the number that can be trusted.
        let inTheDiary = settlement.journal.entries.count { $0.kind == .birth }
        #expect(settlement.birthTally >= inTheDiary)
    }

    @Test("A settler party takes after the colony when no people can be named")
    func settlersWithNoTribeTakeAfterTheColony() throws {
        // `VisitorEngine.settlerParty` invents an origin that is not a place on
        // the map and carries `tribeID: nil`, so a fix that only looked up a
        // tribe fell straight back to the fixed distribution — and a whole
        // re-measurement came back identical because of it.
        let hardy = Genes(industry: 0.9, fertility: 0.5, sociability: 0.5, courage: 0.5)
        let drawn = (0..<80).map {
            PawnFactory.generate(seed: UInt64($0) &* 0x9E37_79B9, stock: hardy).genes.industry
        }
        let mean = drawn.reduce(0, +) / Double(drawn.count)
        #expect(mean > 0.8, "they are people of this country, not a draw around 0.5")
    }
}
