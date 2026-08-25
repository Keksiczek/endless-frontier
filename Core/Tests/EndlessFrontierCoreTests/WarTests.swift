import Foundation
import Testing
@testable import EndlessFrontierCore

/// **A war with a beginning, a tally and an end.**
///
/// Before this, "war" was `standing < −30` rolling a raid each year and a
/// counter going up. Nothing in the world could be asked whether there was one
/// on, which is why nothing showed one: the map drew tents, the town's strip
/// drew stores, and the only surface that knew was the diplomacy list — and it
/// drew its WAR pill at −60, so it disagreed with the engine that sent the
/// warband at −30.
@Suite("War")
struct WarTests {
    private func registry() throws -> GameDataRegistry { try GameDataRegistry.bundled() }
    private static let capitalID = UUID(uuidString: "00000000-0000-0000-0FAF-000000000001")!
    private static let tribeID = UUID(uuidString: "00000000-0000-0000-0FAF-000000000002")!

    private func folk(_ count: Int) -> [Pawn] {
        (0..<count).map { i in
            Pawn(id: UUID(uuidString: String(format: "00000000-0000-0000-0FA0-%012d", i + 1))!,
                 name: "Citizen \(i)", assignedWork: .farming)
        }
    }

    private func world(standing: Double, config: WorldConfig, year: Int = 4) -> WorldState {
        let capital = Settlement(
            id: Self.capitalID, name: "Home", kind: .capital, pawns: folk(20),
            storage: [.food: 400], storageCapacity: .uniform(9999),
            stats: SettlementStats(stability: 60, morale: 70, defense: 20))
        let tribe = Tribe(id: Self.tribeID, name: "Neighbours", foundedTick: 0,
                          originStory: "They left.", population: 40, genes: Genes(),
                          standing: standing)
        return WorldState(tick: year * config.ticksPerYear, mapSeed: 11,
                          settlements: [capital], tribes: [tribe])
    }

    // MARK: - The state itself

    @Test("A grievance under the war threshold eventually becomes a declared war")
    func grievanceBecomesWar() throws {
        let reg = try registry()
        var w = world(standing: -70, config: reg.config)
        for year in 4...24 where w.tribes[0].war == nil {
            w.tick = year * reg.config.ticksPerYear
            var rng = SeededRNG(seed: DiplomacyEngine.tribeSeed(
                mapSeed: w.mapSeed, tribeID: Self.tribeID, year: year))
            w = DiplomacyEngine.resolveRelations(w, tribeIndex: 0, registry: reg, rng: &rng)
        }
        let war = try #require(w.tribes[0].war, "twenty years under −70 and no war declared")
        #expect(!war.declaredByColony)
        #expect(w.tribes[0].wars == 1)
        #expect(w.tribes[0].atWar)
    }

    @Test("The declaration is in the colony's journal, in Czech and English")
    func declarationIsWrittenDown() throws {
        let reg = try registry()
        var w = world(standing: -70, config: reg.config)
        w = DiplomacyEngine.declare(w, tribeIndex: 0, capitalIndex: 0, byColony: false)
        let entry = try #require(w.settlements[0].journal.entries.last)
        #expect(entry.kind == .danger)
        #expect(entry.text.resolve(.cs).contains("válku"))
        #expect(entry.text.resolve(.en).lowercased().contains("war"))
        _ = reg
    }

    @Test("The status pill and the engine agree — a people at war reads as at war")
    func statusFollowsTheWarNotTheScore() throws {
        let reg = try registry()
        // −40 is under the raid threshold (−30) and over the old pill's (−60):
        // exactly the band where the panel used to say "tense" while warbands
        // were arriving every year.
        var w = world(standing: -40, config: reg.config)
        #expect(w.tribes[0].status == .tense)
        w = DiplomacyEngine.declare(w, tribeIndex: 0, capitalIndex: 0, byColony: false)
        #expect(w.tribes[0].status == .war)
    }

    @Test("A raid reached directly still leaves a war behind it")
    func raidImpliesWar() throws {
        let reg = try registry()
        var w = world(standing: -70, config: reg.config)
        var rng = SeededRNG(seed: 4)
        w = DiplomacyEngine.raid(w, tribeIndex: 0, capitalIndex: 0, registry: reg, rng: &rng)
        let war = try #require(w.tribes[0].war)
        #expect(war.raids == 1)
        #expect(w.settlements[0].siege != nil)
    }

    @Test("Peace ends it, and says how long it went on")
    func peaceEndsIt() throws {
        let reg = try registry()
        var w = world(standing: -70, config: reg.config, year: 4)
        w = DiplomacyEngine.declare(w, tribeIndex: 0, capitalIndex: 0, byColony: false)
        w.tick += reg.config.ticksPerYear * 3
        w = DiplomacyEngine.makePeace(w, tribeIndex: 0, capitalIndex: 0,
                                      ticksPerYear: reg.config.ticksPerYear)
        #expect(w.tribes[0].war == nil)
        #expect(w.tribes[0].standing == -5)
        let entry = try #require(w.settlements[0].journal.entries.last)
        #expect(entry.kind == .diplomacy)
        #expect(entry.text.resolve(.cs).contains("3"))
    }

    @Test("A long war wears both sides down — terms get likelier every year")
    func warWeariness() throws {
        let reg = try registry()
        var w = world(standing: -70, config: reg.config, year: 1)
        w = DiplomacyEngine.declare(w, tribeIndex: 0, capitalIndex: 0, byColony: false)
        let firstYear = DiplomacyEngine.peaceOdds(
            of: w.tribes[0], now: w.tick, ticksPerYear: reg.config.ticksPerYear)
        let tenthYear = DiplomacyEngine.peaceOdds(
            of: w.tribes[0], now: w.tick + reg.config.ticksPerYear * 9,
            ticksPerYear: reg.config.ticksPerYear)
        #expect(tenthYear > firstYear)
        #expect(tenthYear <= 1)
    }

    @Test("Tribute buys terms — paying them raises the odds of peace")
    func tributeBuysPeace() throws {
        let reg = try registry()
        var w = world(standing: -70, config: reg.config)
        w = DiplomacyEngine.declare(w, tribeIndex: 0, capitalIndex: 0, byColony: false)
        let unpaid = DiplomacyEngine.peaceOdds(
            of: w.tribes[0], now: w.tick, ticksPerYear: reg.config.ticksPerYear)
        w.tribes[0].tributePerYear = DiplomacyEngine.tributeMostPerYear
        let paid = DiplomacyEngine.peaceOdds(
            of: w.tribes[0], now: w.tick, ticksPerYear: reg.config.ticksPerYear)
        #expect(paid > unpaid)
    }

    @Test("Nobody trades with a people they are at war with")
    func warStopsCommerce() throws {
        let reg = try registry()
        var w = world(standing: 80, config: reg.config)
        w.tribes[0].stores = 200
        w.tribes[0].war = WarState(declaredTick: w.tick)
        let before = w.settlements[0].storage[.food]
        for year in 4...12 {
            w.tick = year * reg.config.ticksPerYear
            var rng = SeededRNG(seed: DiplomacyEngine.tribeSeed(
                mapSeed: w.mapSeed, tribeID: Self.tribeID, year: year))
            w = DiplomacyEngine.resolveRelations(w, tribeIndex: 0, registry: reg, rng: &rng)
        }
        #expect(w.settlements[0].storage[.food] <= before)
        #expect(!w.tribes[0].married)
    }

    @Test("A war survives a save and a load")
    func warRoundTrips() throws {
        let reg = try registry()
        var w = world(standing: -70, config: reg.config)
        w = DiplomacyEngine.declare(w, tribeIndex: 0, capitalIndex: 0, byColony: true)
        w.tribes[0].war?.raids = 4
        w.tribes[0].war?.colonistsLost = 2
        let data = try JSONEncoder().encode(w)
        let back = try JSONDecoder().decode(WorldState.self, from: data)
        let war = try #require(back.tribes[0].war)
        #expect(war.raids == 4)
        #expect(war.colonistsLost == 2)
        #expect(war.declaredByColony)
        _ = reg
    }

    // MARK: - Everyone lives somewhere

    @Test("A people who secede move out — they do not live on the colony's hex")
    func secessionMovesOut() throws {
        let reg = try registry()
        let regions = MapGenerator.generate(seed: 7, registry: reg)
        let home = try #require(regions.first { $0.kind == .homeland })
        var capital = Settlement(
            id: Self.capitalID, name: "Home", kind: .capital,
            pawns: folk(24), storage: [.food: 100], storageCapacity: .uniform(9999),
            stats: SettlementStats(stability: 40, morale: 20, defense: 10))
        capital.regionID = home.id
        var w = WorldState(tick: reg.config.ticksPerYear, mapSeed: 7,
                           settlements: [capital], regions: regions)
        for year in 1...20 where w.tribes.isEmpty {
            w.tick = year * reg.config.ticksPerYear
            w = DiplomacyEngine.secede(w, registry: reg, year: year)
        }
        let tribe = try #require(w.tribes.first, "nobody ever seceded")
        #expect(tribe.regionID != nil)
        #expect(tribe.regionID != home.id, "a people who walked out still lives on your roof")
    }

    @Test("An old save's peoples are re-homed off the colony's hex")
    func migrationRehomesTribes() throws {
        let reg = try registry()
        let regions = MapGenerator.generate(seed: 9, registry: reg)
        let home = try #require(regions.first { $0.kind == .homeland })
        var capital = Settlement(id: Self.capitalID, name: "Home", kind: .capital,
                                 pawns: folk(10))
        capital.regionID = home.id
        // Two peoples squatting on the capital's hex, which is what every save
        // written before this looks like.
        let squatters = (0..<2).map { i in
            Tribe(id: UUID(uuidString: String(format: "00000000-0000-0000-0FAB-%012d", i + 1))!,
                  name: "Squatters \(i)", regionID: home.id, foundedTick: 0,
                  originStory: "They left.", population: 20, genes: Genes())
        }
        var old = WorldState(tick: 100, mapSeed: 9, settlements: [capital],
                             regions: regions, tribes: squatters)
        old.schemaVersion = 4
        let migrated = SaveMigrator.migrate(old, to: 5)
        #expect(migrated.tribes.allSatisfy { $0.regionID != home.id })
        let homes: [UUID] = migrated.tribes.compactMap { $0.regionID }
        #expect(Set(homes).count == migrated.tribes.count,
                "two peoples were given the same hex")
        // Running the chain again must not shuffle a settled world.
        let again = SaveMigrator.migrate(migrated, to: 5)
        let after: [UUID] = again.tribes.compactMap { $0.regionID }
        #expect(after == homes)
    }
}
