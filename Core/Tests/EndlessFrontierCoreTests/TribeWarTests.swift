import Testing
import Foundation
@testable import EndlessFrontierCore

/// **A war you can fight rather than only survive.**
///
/// Every field on `WarState` counted a raid *they* made. `declareWar` set a
/// flag, and then the player waited to be attacked — so a war was a mood, and
/// there was no verb, no engine and no column for anything the colony did back.
/// Keks went looking for the button: *"nevím, jak udělat nájezd na město."*
///
/// The reachability tests are the ones that matter most here. This codebase has
/// paid for rule 6 more than once — a threshold beyond the reach of the rate
/// meant to cross it — and a march is exactly that shape: a share of a place
/// cleared, measured against `brokeInAtShare`. If a full party cannot get past
/// it, the verb ships as decoration.
@Suite("Marching on a neighbour")
struct TribeWarTests {

    private func registry() throws -> GameDataRegistry { try GameDataRegistry.bundled() }

    /// A colony, and a people two hexes away with a war already on.
    private func world(
        atWar: Bool = true, discovered: Bool = true,
        explored: ExplorationState = .fullyExplored,
        theirDefense: Double = 40, theirPopulation: Double = 60,
        theirStores: Double = 400, pop: Int = 20
    ) -> WorldState {
        let homeRegion = Region(
            id: UUID(uuidString: "00000000-0000-0000-3A11-000000000001")!,
            name: "Home Vale", coord: HexCoord(0, 0), kind: .homeland,
            biomeID: "temperate", explorationState: .fullyExplored)
        let theirs = Region(
            id: UUID(uuidString: "00000000-0000-0000-3A11-000000000002")!,
            name: "Kamenný Brod", coord: HexCoord(2, 0), kind: .wilderness,
            biomeID: "temperate", hazardLevel: 2, explorationState: explored)

        let pawns = (0..<pop).map { i -> Pawn in
            var pawn = Pawn(
                id: UUID(uuidString: String(format: "00000000-0000-0000-3A11-%012d", i + 10))!,
                name: "Voják \(i)")
            pawn.age = 27 * 60
            return pawn
        }
        var capital = Settlement(
            id: UUID(uuidString: "00000000-0000-0000-3A11-AAAAAAAAAAAA")!,
            name: "Domov", kind: .capital, pawns: pawns,
            storage: [.food: 800], storageCapacity: .uniform(4000))
        capital.regionID = homeRegion.id

        var tribe = Tribe(
            id: UUID(uuidString: "00000000-0000-0000-3A11-BBBBBBBBBBBB")!,
            name: "Vlčí lid", regionID: theirs.id, foundedTick: 0,
            originStory: "", population: theirPopulation, genes: Genes(),
            defense: theirDefense, stores: theirStores,
            standing: -60, grudge: 40)
        tribe.discovered = discovered
        if atWar { tribe.war = WarState(declaredTick: 0, declaredByColony: true) }

        return WorldState(tick: 0, mapSeed: 71, settlements: [capital],
                          regions: [homeRegion, theirs], tribes: [tribe])
    }

    private func theirRegion(_ state: WorldState) -> UUID { state.regions[1].id }

    private func carry(_ state: WorldState, ticks: Int,
                       registry reg: GameDataRegistry) -> WorldState {
        var s = state
        for tick in 0..<ticks {
            s.tick = tick
            for step in 0..<WorldClock.actionStepsPerTick {
                s = RegionExpeditionEngine.advanceStep(
                    s, clock: WorldClock(tick: tick, step: step), registry: reg)
            }
        }
        return s
    }

    // MARK: - Who you may march on

    @Test("A war has to be declared before anybody marches")
    func peaceIsNotAMarch() throws {
        let peaceful = world(atWar: false)
        #expect(TribeWarEngine.target(in: peaceful, regionID: theirRegion(peaceful)) == nil)
        #expect(RegionExpeditionEngine.dispatch(
            peaceful, settlementID: peaceful.settlements[0].id,
            regionID: theirRegion(peaceful), registry: try registry()) == nil)
    }

    @Test("You cannot march on a people nobody has met")
    func unmetIsNotATarget() {
        let hidden = world(discovered: false)
        #expect(TribeWarEngine.target(in: hidden, regionID: theirRegion(hidden)) == nil)
    }

    @Test("You cannot march into country nobody has walked")
    func unchartedIsNotATarget() {
        let dark = world(explored: ExplorationState.unknown)
        #expect(TribeWarEngine.target(in: dark, regionID: theirRegion(dark)) == nil)
    }

    @Test("A declared war on a charted people is a target")
    func atWarIsATarget() {
        let w = world()
        #expect(TribeWarEngine.target(in: w, regionID: theirRegion(w))?.name == "Vlčí lid")
    }

    // MARK: - The journey is the one the colony already makes

    @Test("A march is an expedition: the hands go, and they are gone")
    func handsLeave() throws {
        let reg = try registry()
        let start = world()
        let sent = try #require(RegionExpeditionEngine.dispatch(
            start, settlementID: start.settlements[0].id,
            regionID: theirRegion(start), registry: reg))
        #expect(sent.regionExpeditions.count == 1)
        let away = sent.settlements[0].pawns.filter { $0.isAway }.count
        #expect(away > 0)
        #expect(away == sent.regionExpeditions[0].memberIDs.count)
    }

    @Test("Only one party goes down one road")
    func oneAtATime() throws {
        let reg = try registry()
        let start = world()
        let sent = try #require(RegionExpeditionEngine.dispatch(
            start, settlementID: start.settlements[0].id,
            regionID: theirRegion(start), registry: reg))
        #expect(RegionExpeditionEngine.dispatch(
            sent, settlementID: sent.settlements[0].id,
            regionID: theirRegion(sent), registry: reg) == nil)
    }

    // MARK: - What is waiting there

    @Test("A people turns out fighters, and holds its stores")
    func theyAreAPlace() {
        let w = world()
        let encounter = TribeWarEngine.encounter(
            for: w.tribes[0], party: [UUID()], seed: 99)
        #expect(encounter.things.contains { $0.kind == SiteEncounter.Thing.Kind.guardian })
        #expect(encounter.things.contains { $0.kind == SiteEncounter.Thing.Kind.cache })
        // Every label reads in both languages — a fight is content too.
        for thing in encounter.things {
            #expect(!thing.label.resolve(GameLanguage.cs).isEmpty)
            #expect(thing.label.resolve(GameLanguage.cs) != thing.label.resolve(GameLanguage.en))
        }
    }

    @Test("A bigger people is a harder fight")
    func sizeTells() {
        let small = world(theirDefense: 10, theirPopulation: 15)
        let large = world(theirDefense: 120, theirPopulation: 200)
        let weak = TribeWarEngine.encounter(for: small.tribes[0], party: [], seed: 5)
        let strong = TribeWarEngine.encounter(for: large.tribes[0], party: [], seed: 5)
        func weight(_ e: SiteEncounter) -> Double {
            e.things.filter { $0.kind == SiteEncounter.Thing.Kind.guardian }.reduce(0) { $0 + $1.strength }
        }
        #expect(weight(strong) > weight(weak) * 3)
    }

    @Test("A people you have already hurt is dug in")
    func grudgeDigsIn() {
        var fresh = world()
        fresh.tribes[0].grudge = 0
        var scarred = world()
        scarred.tribes[0].grudge = 80
        let a = TribeWarEngine.encounter(for: fresh.tribes[0], party: [], seed: 3)
        let b = TribeWarEngine.encounter(for: scarred.tribes[0], party: [], seed: 3)
        #expect(!a.things.contains { $0.kind == SiteEncounter.Thing.Kind.trap })
        #expect(b.things.contains { $0.kind == SiteEncounter.Thing.Kind.trap })
    }

    // MARK: - What it costs

    @Test("A march that gets in takes stores, people and strength")
    func sackingCosts() {
        let start = world()
        let (after, march) = TribeWarEngine.sacked(
            start, tribeID: start.tribes[0].id, settlementIndex: 0, share: 1.0)
        let march2 = try? #require(march)
        #expect(march2?.brokeIn == true)
        #expect(after.tribes[0].stores < start.tribes[0].stores)
        #expect(after.tribes[0].population < start.tribes[0].population)
        #expect(after.tribes[0].defense < start.tribes[0].defense)
        // …and it is home, in the granary of the settlement that sent them.
        #expect(after.settlements[0].storage[ResourceType.food] > start.settlements[0].storage[ResourceType.food])
        #expect(after.settlements[0].storage[ResourceType.materials] > start.settlements[0].storage[ResourceType.materials])
    }

    /// The other half of rule 6: a total victory must not be a total wipe, or
    /// one march ends a people and a war is a single button.
    @Test("One march never finishes a people")
    func neverTotal() {
        let start = world(theirPopulation: 60, theirStores: 400)
        let (after, _) = TribeWarEngine.sacked(
            start, tribeID: start.tribes[0].id, settlementIndex: 0, share: 1.0)
        #expect(after.tribes[0].population > start.tribes[0].population * 0.7)
        #expect(after.tribes[0].stores > start.tribes[0].stores * 0.5)
    }

    @Test("A march that was held at the edge still costs them, in proportion")
    func partialIsProportional() {
        let start = world()
        let (whole, _) = TribeWarEngine.sacked(
            start, tribeID: start.tribes[0].id, settlementIndex: 0, share: 1.0)
        let (part, held) = TribeWarEngine.sacked(
            start, tribeID: start.tribes[0].id, settlementIndex: 0, share: 0.25)
        #expect(held?.brokeIn == false)
        let tookWhole = start.tribes[0].stores - whole.tribes[0].stores
        let tookPart = start.tribes[0].stores - part.tribes[0].stores
        #expect(tookPart > 0)
        #expect(abs(tookPart - tookWhole * 0.25) < 0.01)
    }

    @Test("Marching on a people is the worst thing you can do to the relationship")
    func itIsRemembered() {
        let start = world()
        let (after, _) = TribeWarEngine.sacked(
            start, tribeID: start.tribes[0].id, settlementIndex: 0, share: 1.0)
        #expect(after.tribes[0].grudge > start.tribes[0].grudge)
        #expect(after.tribes[0].standing < start.tribes[0].standing)
    }

    @Test("The war's tally gains our own column")
    func bothColumns() {
        let start = world()
        let (after, _) = TribeWarEngine.sacked(
            start, tribeID: start.tribes[0].id, settlementIndex: 0, share: 1.0)
        let war = after.tribes[0].war
        #expect(war?.sorties == 1)
        #expect(war?.sortiesWon == 1)
        #expect((war?.plunder ?? 0) > 0)
        #expect((war?.theirStrengthSpent ?? 0) > 0)
        // …and their column is untouched by our march.
        #expect(war?.raids == 0)
    }

    // MARK: - Reachability (rule 6)

    /// **The test this feature would be worthless without.** `brokeInAtShare`
    /// is 0.6 of a place cleared; if a full party of four cannot reach that
    /// against a middling people, "March on them" is a button that always says
    /// the party was held at the edge.
    @Test("A full party can actually break into a middling people")
    func aMarchCanSucceed() throws {
        let reg = try registry()
        let start = world(theirDefense: 40, theirPopulation: 60)
        let sent = try #require(RegionExpeditionEngine.dispatch(
            start, settlementID: start.settlements[0].id,
            regionID: theirRegion(start), registry: reg))
        let expedition = sent.regionExpeditions[0]
        let whole = expedition.travelTicks * 2 + expedition.workTicks + 2
        let home = carry(sent, ticks: whole, registry: reg)

        #expect(home.regionExpeditions.isEmpty, "the party never came home")
        let war = try #require(home.tribes[0].war)
        #expect(war.sorties == 1, "the march was never recorded")
        #expect(war.sortiesWon == 1,
                "a full party cannot clear \(TribeWarEngine.brokeInAtShare) of a middling people — the verb is decoration")
        #expect(home.tribes[0].stores < start.tribes[0].stores)
    }

    /// …and the other end of the same rule: a small party against a large
    /// people must be able to *fail*, or the march is a free harvest.
    @Test("A march on a great people is not a free harvest")
    func aMarchCanFail() throws {
        let reg = try registry()
        let start = world(theirDefense: 900, theirPopulation: 400, pop: 12)
        let sent = try #require(RegionExpeditionEngine.dispatch(
            start, settlementID: start.settlements[0].id,
            regionID: theirRegion(start), registry: reg))
        let expedition = sent.regionExpeditions[0]
        let whole = expedition.travelTicks * 2 + expedition.workTicks + 2
        let home = carry(sent, ticks: whole, registry: reg)
        let war = try #require(home.tribes[0].war)
        #expect(war.sortiesWon == 0,
                "four people walked into a people of four hundred and broke it")
    }

    // MARK: - Saves

    /// A war saved before the colony could march must decode to one it has not
    /// marched in, rather than failing the save (rule 3).
    @Test("A war saved before any of this decodes to a war nobody marched in")
    func oldSavesLoad() throws {
        let old = """
        {"declaredTick":120,"declaredByColony":false,"raids":3,"repelled":1,
         "colonistsLost":2,"strengthSpent":40.5,"lootLost":90.0}
        """
        let war = try JSONDecoder().decode(WarState.self, from: Data(old.utf8))
        #expect(war.raids == 3)
        #expect(war.sorties == 0)
        #expect(war.sortiesWon == 0)
        #expect(war.plunder == 0)
        #expect(war.theirStrengthSpent == 0)
    }

    @Test("A war with marches in it survives the round trip")
    func roundTrip() throws {
        let before = WarState(declaredTick: 10, declaredByColony: true, raids: 2,
                              sorties: 4, sortiesWon: 3,
                              theirStrengthSpent: 61.5, plunder: 220)
        let data = try JSONEncoder().encode(before)
        let after = try JSONDecoder().decode(WarState.self, from: data)
        #expect(after == before)
    }
}
