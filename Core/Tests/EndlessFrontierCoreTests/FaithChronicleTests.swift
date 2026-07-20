import Foundation
import Testing
@testable import EndlessFrontierCore

@Suite("Faith & chronicle")
struct FaithChronicleTests {
    private func registry() throws -> GameDataRegistry { try GameDataRegistry.bundled() }
    private static let townID = UUID(uuidString: "00000000-0000-0000-0FA1-000000000001")!

    private func town(_ pawns: [Pawn], laws: [LawInstance] = [], faith: FaithState = FaithState()) -> Settlement {
        Settlement(id: Self.townID, name: "Templeton", kind: .capital, pawns: pawns,
                   storage: [.food: 500], storageCapacity: 9999,
                   laws: laws, faith: faith)
    }

    private func folk(_ count: Int, work: WorkKind = .farming) -> [Pawn] {
        (0..<count).map { i in
            Pawn(id: UUID(uuidString: String(format: "00000000-0000-0000-0FA2-%012d", i + 1))!,
                 name: "Soul \(i)", assignedWork: work)
        }
    }

    private func world(_ settlement: Settlement, year: Int, config: WorldConfig) -> WorldState {
        WorldState(tick: year * config.ticksPerYear, mapSeed: 4, settlements: [settlement])
    }

    // MARK: - Faith

    @Test("A temple raised by law gives a cult somewhere to take root")
    func templeBirthsACult() throws {
        let reg = try registry()
        let s = town(folk(10), laws: [LawInstance(definitionID: "temple", enactedTick: 0, expiresTick: 9999)])
        let after = FaithEngine.advanceYear(world(s, year: 1, config: reg.config), registry: reg)
        let faith = after.settlements[0].faith
        #expect(faith.cultID != nil)
        // Founded at `foundingFaith`, then the same year's tending applies —
        // with no priests yet, devotion has already begun to bleed.
        #expect(faith.faith > 0)
        #expect(faith.faith <= FaithEngine.foundingFaith)
        #expect(reg.cult(faith.cultID!) != nil)
    }

    @Test("Priests sustain the faith; without them it bleeds away")
    func priestsSustainFaith() throws {
        let reg = try registry()
        let temple = [LawInstance(definitionID: "temple", enactedTick: 0, expiresTick: 99999)]
        let devout = FaithState(cultID: "sun", faith: 50)

        var tended = world(town(folk(4, work: .priest), laws: temple, faith: devout), year: 1, config: reg.config)
        var neglected = world(town(folk(4, work: .farming), laws: temple, faith: devout), year: 1, config: reg.config)
        for year in 1...3 {
            tended.tick = year * reg.config.ticksPerYear
            neglected.tick = year * reg.config.ticksPerYear
            tended = FaithEngine.advanceYear(tended, registry: reg)
            neglected = FaithEngine.advanceYear(neglected, registry: reg)
        }
        #expect(tended.settlements[0].faith.faith > neglected.settlements[0].faith.faith)
    }

    @Test("Devotion lifts morale and softens disaster")
    func faithComforts() throws {
        let reg = try registry()
        let faithful = town(folk(6), faith: FaithState(cultID: "moon", faith: 100))
        let godless = town(folk(6))
        #expect(FaithEngine.moraleBonus(faithful, registry: reg) > 0)
        #expect(FaithEngine.moraleBonus(godless, registry: reg) == 0)
        #expect(FaithEngine.solace(faithful, registry: reg) > 0)
        #expect(FaithEngine.solace(godless, registry: reg) == 0)
    }

    @Test("A temple opens the priesthood as a trade")
    func templeOpensPriesthood() throws {
        let reg = try registry()
        // 25 idle adults, temple standing → some become priests.
        var s = town(folk(25, work: .idle), faith: FaithState(cultID: "river", faith: 50))
        s = LaborEngine.assignIdleAdults(s, registry: reg)
        #expect(s.pawns.contains { $0.assignedWork == .priest })

        // No temple → nobody preaches.
        var godless = town(folk(25, work: .idle))
        godless = LaborEngine.assignIdleAdults(godless, registry: reg)
        #expect(!godless.pawns.contains { $0.assignedWork == .priest })
    }

    @Test("Faith is deterministic across a run of years")
    func faithDeterministic() throws {
        let reg = try registry()
        func run() -> FaithState {
            var w = world(town(folk(8, work: .priest),
                               laws: [LawInstance(definitionID: "temple", enactedTick: 0, expiresTick: 99999)]),
                          year: 0, config: reg.config)
            for year in 1...20 {
                w.tick = year * reg.config.ticksPerYear
                w = FaithEngine.advanceYear(w, registry: reg)
            }
            return w.settlements[0].faith
        }
        #expect(run() == run())
    }

    @Test("Shipped cults decode bilingually")
    func bundledCults() throws {
        let reg = try registry()
        #expect(reg.cults.count >= 6)
        for cult in reg.cults.values {
            #expect(!cult.name.resolve(.cs).isEmpty)
            #expect(!cult.creed.resolve(.cs).isEmpty)
            #expect(cult.name.resolve(.cs) != cult.name.resolve(.en))   // really translated
        }
    }

    // MARK: - Chronicle

    @Test("The chronicle records one snapshot a year")
    func recordsOnePerYear() throws {
        let reg = try registry()
        var w = world(town(folk(12)), year: 3, config: reg.config)
        w = ChronicleEngine.record(w, registry: reg)
        #expect(w.records.count == 1)
        #expect(w.records[0].year == 3)
        #expect(w.records[0].population == 12)

        // Recording the same year again changes nothing.
        w = ChronicleEngine.record(w, registry: reg)
        #expect(w.records.count == 1)
    }

    @Test("The record keeps average genes — where selection becomes visible")
    func recordsGeneAverages() throws {
        let reg = try registry()
        var pawns = folk(4)
        for i in pawns.indices { pawns[i].genes = Genes(industry: 0.8, fertility: 0.2) }
        var w = world(town(pawns), year: 1, config: reg.config)
        w = ChronicleEngine.record(w, registry: reg)
        #expect(abs(w.records[0].industry - 0.8) < 1e-9)
        #expect(abs(w.records[0].fertility - 0.2) < 1e-9)
    }

    @Test("The chronicle is capped so saves stay small")
    func recordsAreCapped() throws {
        let reg = try registry()
        var w = world(town(folk(5)), year: 0, config: reg.config)
        for year in 0..<(ChronicleEngine.maxRecords + 30) {
            w.tick = year * reg.config.ticksPerYear
            w = ChronicleEngine.record(w, registry: reg)
        }
        #expect(w.records.count == ChronicleEngine.maxRecords)
        #expect(w.records.last?.year == ChronicleEngine.maxRecords + 29)
    }

    @Test("Insights read gene drift out of the record, bilingually")
    func insightsSpotSelection() throws {
        let reg = try registry()
        var w = world(town(folk(10)), year: 0, config: reg.config)
        // A century in which courage climbs steadily.
        for year in 0..<80 {
            let brave = 0.3 + Double(year) * 0.005
            var pawns = folk(10)
            for i in pawns.indices { pawns[i].genes = Genes(courage: brave) }
            w.settlements[0].pawns = pawns
            w.tick = year * reg.config.ticksPerYear
            w = ChronicleEngine.record(w, registry: reg)
        }
        let insights = ChronicleEngine.insights(w, registry: reg)
        let selection = insights.first { $0.id == "selection" }
        let found = try #require(selection)
        #expect(found.text.resolve(.cs).contains("odvaha"))
        #expect(found.text.resolve(.en).contains("courage"))
    }

    @Test("A young world says it has too little history")
    func youngWorldHasNoInsights() throws {
        let reg = try registry()
        let w = world(town(folk(5)), year: 0, config: reg.config)
        #expect(ChronicleEngine.insights(w, registry: reg).first?.id == "gathering")
    }

    @Test("A ticking world fills its chronicle and survives a save")
    func chronicleThroughTheTick() throws {
        let reg = try registry()
        let world = GameWorldFactory.newGame(registry: reg, seed: 21)
        let after = TickEngine.advance(world, ticks: reg.config.ticksPerYear * 5, registry: reg).state
        #expect(after.records.count >= 4)

        let restored = try JSONDecoder().decode(
            WorldState.self, from: JSONEncoder().encode(after))
        #expect(restored.records == after.records)
    }
}
