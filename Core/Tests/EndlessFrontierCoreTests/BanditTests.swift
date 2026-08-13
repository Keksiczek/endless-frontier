import Testing
import Foundation
@testable import EndlessFrontierCore

/// Every fight the game had came from a *relationship*: a people who had come
/// to hate you, or a wood you had not hunted. Both can be mended. Nothing in
/// the world simply wanted the grain, so a colony with good neighbours and a
/// quiet forest had no enemies at all, however rich it got.
@Suite("Outlaws, who belong to nobody")
struct BanditTests {

    private func registry() throws -> GameDataRegistry { try GameDataRegistry.bundled() }

    private func town(
        pop: Int = 40, food: Double, capacity: Double = 1000,
        defense: Double = 0, garrison: Int = 0
    ) -> Settlement {
        let pawns = (0..<pop).map { i -> Pawn in
            var pawn = Pawn(
                id: UUID(uuidString: String(format: "00000000-0000-0000-BA47-%012d", i + 1))!,
                name: "Hand \(i)",
                assignedWork: i < garrison ? .garrison : .farming)
            pawn.age = 27 * 60
            return pawn
        }
        return Settlement(
            id: UUID(uuidString: "00000000-0000-0000-BA47-AAAAAAAAAAAA")!,
            name: "Fat Granary", kind: .capital, pawns: pawns,
            storage: [.food: food], storageCapacity: .uniform(capacity),
            stats: SettlementStats(defense: defense))
    }

    private func years(_ settlement: Settlement, ticks: Int,
                       registry reg: GameDataRegistry) -> (Settlement, Int) {
        var s = settlement
        var raids = 0
        for tick in stride(from: 0, to: ticks, by: BanditEngine.interval) {
            s = BanditEngine.advanceOneTick(
                s, registry: reg, tick: tick, era: .medieval, mapSeed: 88)
            if s.siege != nil { raids += 1; s.siege = nil }
        }
        return (s, raids)
    }

    // MARK: - What draws them

    @Test("A full granary is what draws them, and an empty one does not")
    func wealthIsTheLure() {
        #expect(BanditEngine.temptation(town(food: 0, capacity: 1000)) == 0)
        #expect(BanditEngine.temptation(town(food: 300, capacity: 1000)) == 0,
                "a third full is not worth the walk")
        let fat = BanditEngine.temptation(town(food: 1900, capacity: 1000))
        #expect(fat > 1, "a colony sitting on everything it owns is a target")
    }

    /// Rule 6, on the danger side: if a rich colony never actually sees a band,
    /// the whole system is a number nobody meets.
    @Test("A rich, unwatched colony really is robbed, inside a generation")
    func banditsAreReachable() throws {
        let reg = try registry()
        let (_, raids) = years(town(food: 1900, capacity: 1000), ticks: 1800, registry: reg)
        #expect(raids > 0, "thirty years sitting on a full granary and nobody came")
    }

    @Test("A poor colony is left alone")
    func thePoorAreSpared() throws {
        let reg = try registry()
        let (_, raids) = years(town(food: 120, capacity: 1000), ticks: 6000, registry: reg)
        #expect(raids == 0, "they walked a hundred years for an empty shed")
    }

    /// The lever has to reach: spears and a wall must visibly buy something,
    /// or the only answer to banditry is to stay poor.
    @Test("Spears and a wall make a colony a poor target")
    func watchfulnessWorks() throws {
        let reg = try registry()
        let open = town(food: 1900, capacity: 1000)
        let held = town(food: 1900, capacity: 1000, defense: 60, garrison: 6)
        #expect(BanditEngine.watchfulness(held, registry: reg)
                > BanditEngine.watchfulness(open, registry: reg) + 0.3)

        let (_, loose) = years(open, ticks: 6000, registry: reg)
        let (_, guarded) = years(held, ticks: 6000, registry: reg)
        #expect(guarded < loose, "a garrison and a wall bought nothing")
        // …and never nothing at all: a share, not a subtraction.
        #expect(BanditEngine.watchfulness(held, registry: reg) < 0.9)
    }

    // MARK: - What they are

    @Test("Nobody is charged for a raid nobody sent")
    func thereIsNoTribeToBlame() throws {
        let reg = try registry()
        var s = town(food: 1900, capacity: 1000)
        for tick in stride(from: 0, to: 4000, by: BanditEngine.interval) {
            s = BanditEngine.advanceOneTick(
                s, registry: reg, tick: tick, era: .medieval, mapSeed: 88)
            if s.siege != nil { break }
        }
        let siege = try #require(s.siege)
        #expect(siege.attackerTribeID == nil, "outlaws have no people to answer for them")
        #expect(siege.attackerLabel?.resolve(.cs) != siege.attackerLabel?.resolve(.en),
                "the band is not named in both languages")
    }

    @Test("A colony already fighting is not also held up")
    func oneFightAtATime() throws {
        let reg = try registry()
        var s = town(food: 1900, capacity: 1000)
        s = SiegeEngine.begin(s, attackerStrength: 40, attackerName: "Wolves",
                              fortification: 0, tick: 0, registry: reg, seed: 1)
        let id = try #require(s.siege).id
        for tick in stride(from: 0, to: 2000, by: BanditEngine.interval) {
            s = BanditEngine.advanceOneTick(
                s, registry: reg, tick: tick, era: .medieval, mapSeed: 88)
        }
        #expect(s.siege?.id == id)
    }

    @Test("The same colony is robbed at the same moments")
    func deterministic() throws {
        let reg = try registry()
        let a = years(town(food: 1900, capacity: 1000), ticks: 3000, registry: reg).1
        let b = years(town(food: 1900, capacity: 1000), ticks: 3000, registry: reg).1
        #expect(a == b)
    }

    @Test("Every band is named in both languages, in every age")
    func namesAreBilingual() {
        for era in Era.allCases {
            var rng = SeededRNG(seed: 4)
            for _ in 0..<6 {
                let name = BanditEngine.name(era: era, rng: &rng)
                #expect(!name.resolve(.en).isEmpty)
                #expect(!name.resolve(.cs).isEmpty)
                #expect(name.resolve(.cs) != name.resolve(.en), "\(era) has an untranslated band")
            }
        }
    }
}
