import Testing
import Foundation
@testable import EndlessFrontierCore

/// At sixty souls nobody wants to click each colonist. These pin the standing
/// orders: that they *reach* — a policy set on a full town has to change that
/// town, not only the next child to come of age — and that a colony under no
/// orders behaves exactly as it did before there were any.
@Suite("Standing orders")
struct ColonyPolicyTests {
    private let seat = UUID(uuidString: "00000000-0000-0000-0000-0000000000D1")!

    private var registry: GameDataRegistry { Fixtures.registry(buildings: []) }
    private var ticksPerYear: Int { registry.config.ticksPerYear }

    private func town(_ adults: Int, work: WorkKind = .farming,
                      policy: ColonyPolicy = ColonyPolicy()) -> Settlement {
        var s = Settlement(id: seat, name: "Town", pawns: [],
                           storage: [.food: 4000], storageCapacity: 8000)
        s.pawns = (0..<adults).map { i in
            var p = Pawn(
                id: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", 100 + i))!,
                name: "Soul \(i)", skills: [work: 5], assignedWork: work, health: 85)
            p.age = 30 * ticksPerYear
            p.needs = PawnNeeds(hunger: 80, rest: 80, recreation: 80)
            return p
        }
        s.policy = policy
        return s
    }

    private func tally(_ s: Settlement) -> [WorkKind: Int] {
        var counts: [WorkKind: Int] = [:]
        for pawn in s.pawns { counts[pawn.assignedWork, default: 0] += 1 }
        return counts
    }

    // MARK: - Nothing changes for a colony under no orders

    @Test("A colony with no standing orders is the colony there always was")
    func defaultPolicyChangesNothing() {
        let policy = ColonyPolicy()
        #expect(policy.isDefault)
        #expect(policy.ration.foodPerMeal == 1)
        #expect(policy.ration.hungerPerMeal == 1)
        #expect(policy.ration.moodEffect == 0)
        #expect(policy.stance(.mining) == .normal)

        let plain = LaborEngine.quotaTable(hasTemple: false, hasWalls: false,
                                           policy: ColonyPolicy())
        #expect(plain.count == LaborEngine.quotas.count)
        for (a, b) in zip(plain, LaborEngine.quotas) {
            #expect(a.work == b.work)
            #expect(a.share == b.share)
        }
    }

    @Test("Rebalancing a colony under no orders never moves anybody")
    func rebalanceIsInertWithoutOrders() {
        let before = town(30, work: .farming)
        let after = LaborEngine.rebalance(before, registry: registry)
        #expect(tally(after) == tally(before))
    }

    /// A save written before standing orders existed has no `policy` key at
    /// all. Built by taking a real save and deleting the field, so this cannot
    /// pass against a hand-written stub that drifts from the actual encoding.
    @Test("An old save with no policy field loads as a colony under no orders")
    func policyDecodesFromAnOlderSave() throws {
        var s = town(3)
        s.policy = ColonyPolicy(trades: [.mining: .priority], ration: .short)
        let encoded = try JSONEncoder().encode(s)
        var fields = try #require(
            try JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        #expect(fields["policy"] != nil, "the policy is not being written at all")
        fields.removeValue(forKey: "policy")

        let older = try JSONSerialization.data(withJSONObject: fields)
        let decoded = try JSONDecoder().decode(Settlement.self, from: older)
        #expect(decoded.policy == ColonyPolicy())
        #expect(decoded.policy.isDefault)
        #expect(decoded.pawns.count == 3)
    }

    // MARK: - Trades

    /// The reachability that matters here: an order given to a *full* town has
    /// to change that town. Before `rebalance` existed the policy only ever
    /// touched the idle, so a colony of thirty ignored it for ever.
    @Test("A priority trade actually takes over a town that is already full")
    func priorityReachesAFullTown() {
        var s = town(30, work: .farming,
                     policy: ColonyPolicy().setting(.mining, to: .priority))
        // Nobody is idle: every one of the thirty is already a farmer.
        #expect(tally(s)[.mining] == nil)
        for _ in 0..<60 {
            s = LaborEngine.rebalance(s, registry: registry)
        }
        let miners = tally(s)[.mining] ?? 0
        #expect(miners >= 6, "priority mining reached only \(miners) of 30")
    }

    /// …and "priority" must not mean "only". A weight left unnormalised makes
    /// one trade look permanently starved and swallows the entire town.
    @Test("A priority trade takes a bigger slice, not the whole town")
    func priorityIsNotTotal() {
        var s = town(30, work: .farming,
                     policy: ColonyPolicy().setting(.mining, to: .priority))
        for _ in 0..<200 {
            s = LaborEngine.rebalance(s, registry: registry)
        }
        let miners = tally(s)[.mining] ?? 0
        #expect(miners < 20, "priority mining swallowed \(miners) of 30")
        #expect((tally(s)[.farming] ?? 0) > 0, "the town stopped farming entirely")
    }

    @Test("A trade switched off empties out")
    func offEmptiesTheTrade() {
        var s = town(24, work: .research,
                     policy: ColonyPolicy().setting(.research, to: .off))
        for _ in 0..<80 {
            s = LaborEngine.rebalance(s, registry: registry)
        }
        #expect((tally(s)[.research] ?? 0) == 0, "researchers survived being switched off")
    }

    @Test("A trade switched off is never handed a new adult")
    func offIsNeverAssigned() {
        let policy = ColonyPolicy().setting(.mining, to: .off)
        for _ in 0..<40 {
            var counts: [WorkKind: Int] = [:]
            let role = LaborEngine.neediestRole(
                counts: counts, adultCount: 20, population: 20, policy: policy)
            #expect(role != .mining)
            counts[role, default: 0] += 1
        }
    }

    /// Scouting has a floor that beats the quota maths. An order to send nobody
    /// out has to beat the floor, or "off" quietly means "one, always".
    @Test("Switching scouting off beats even the scouting floor")
    func offBeatsTheScoutingFloor() {
        let role = LaborEngine.neediestRole(
            counts: [:], adultCount: 20, population: 20, needsScouts: true,
            policy: ColonyPolicy().setting(.scouting, to: .off))
        #expect(role != .scouting)
        // …and with no such order, the floor still holds.
        #expect(LaborEngine.neediestRole(counts: [:], adultCount: 20, population: 20,
                                         needsScouts: true) == .scouting)
    }

    @Test("Orders that switch off every trade still put people somewhere")
    func everythingOffStillAssigns() {
        var policy = ColonyPolicy()
        for work in WorkKind.allCases { policy = policy.setting(work, to: .off) }
        let role = LaborEngine.neediestRole(counts: [:], adultCount: 10,
                                            population: 10, policy: policy)
        #expect(role != .idle, "a colonist with nowhere to be is a colonist who starves")
    }

    @Test("Setting a trade back to normal forgets it was ever set")
    func normalIsNotStored() {
        let policy = ColonyPolicy()
            .setting(.mining, to: .priority)
            .setting(.mining, to: .normal)
        #expect(policy.trades.isEmpty)
        #expect(policy.isDefault)
    }

    @Test("Rebalancing moves the least skilled hand, and only one at a time")
    func rebalanceIsGentleAndDeterministic() {
        var s = town(20, work: .farming,
                     policy: ColonyPolicy().setting(.mining, to: .priority))
        for (i, _) in s.pawns.enumerated() { s.pawns[i].skills = [.farming: i] }
        let after = LaborEngine.rebalance(s, registry: registry)
        let moved = zip(s.pawns, after.pawns).filter { $0.assignedWork != $1.assignedWork }
        #expect(moved.count == 1, "a colony re-sorted wholesale is a spreadsheet")
        #expect(moved.first?.1.name == "Soul 0", "it took the wrong hand")
        // And the same world always moves the same person.
        #expect(LaborEngine.rebalance(s, registry: registry).pawns.map(\.assignedWork)
                == after.pawns.map(\.assignedWork))
    }

    // MARK: - Rations

    @Test("Short rations really do stretch the granary")
    func shortRationsSaveFood() {
        func eaten(_ ration: ColonyPolicy.Ration) -> Double {
            // Healers, so the town eats without also growing its own dinner —
            // a colony of farmers nets food and the meter runs backwards.
            var s = town(20, work: .healing)
            s.policy.ration = ration
            for i in s.pawns.indices { s.pawns[i].needs.hunger = 40 }
            let before = s.storage[.food]
            for tick in 0..<40 {
                s = ErrandEngine.advanceOneTick(s, registry: registry, tick: tick)
                s = PawnEngine.advanceOneTick(s, registry: registry, tick: tick)
            }
            return before - s.storage[.food]
        }
        let full = eaten(.full)
        let short = eaten(.short)
        let famine = eaten(.famine)
        #expect(short < full, "short rations ate \(short) against \(full)")
        #expect(famine < short)
        #expect(eaten(.feast) > full)
    }

    /// A saving with no cost is not a decision. People must feel it.
    @Test("Short rations cost mood")
    func shortRationsCostMood() {
        func mood(_ ration: ColonyPolicy.Ration) -> Double {
            var s = town(12, work: .healing)
            s.policy.ration = ration
            for tick in 0..<20 {
                s = ErrandEngine.advanceOneTick(s, registry: registry, tick: tick)
                s = PawnEngine.advanceOneTick(s, registry: registry, tick: tick)
            }
            return s.pawns.map(\.mood).reduce(0, +) / Double(s.pawns.count)
        }
        #expect(mood(.short) < mood(.full))
        #expect(mood(.famine) < mood(.short))
        #expect(mood(.feast) > mood(.full))
    }

    /// The lever has to be reachable from where a player would pull it: a
    /// colony that is about to starve must last meaningfully longer on famine
    /// rations, or the option is decoration.
    @Test("Famine rations buy a colony real time")
    func famineRationsBuyTime() {
        // Time to the thing that actually matters — the first empty stomach —
        // rather than to an empty granary. The store never quite reaches zero:
        // once less than one meal is left nobody can take it, so it freezes
        // just above nothing and a "ticks until empty" measure never fires.
        func ticksUntilSomebodyStarves(_ ration: ColonyPolicy.Ration) -> Int {
            var s = town(20, work: .healing)
            s.storage[.food] = 60
            s.policy.ration = ration
            for i in s.pawns.indices { s.pawns[i].needs.hunger = 30 }
            for tick in 0..<600 {
                s = ErrandEngine.advanceOneTick(s, registry: registry, tick: tick)
                s = PawnEngine.advanceOneTick(s, registry: registry, tick: tick)
                if s.pawns.contains(where: { $0.needs.hunger <= 0 }) { return tick }
            }
            return 600
        }
        let full = ticksUntilSomebodyStarves(.full)
        let famine = ticksUntilSomebodyStarves(.famine)
        #expect(full < 600, "the test never ran the colony out of food at all")
        #expect(famine > full + 10,
                "famine rations bought \(famine - full) ticks — not worth a menu")
    }

    // MARK: - The roster

    @Test("A colony that sends nobody out sends nobody")
    func nobodyLeavesMeansNobody() {
        var s = town(20, work: .mining)
        s.policy.roster = .nobody
        #expect(LocalPOIEngine.chooseParty(s, for: .cave, ticksPerYear: ticksPerYear).isEmpty)
    }

    @Test("Spare hands only keeps a priority trade at its post")
    func spareHandsProtectsPriorityTrades() {
        var s = town(20, work: .mining)
        // Half the town is a farmer, half a miner; mining is the priority.
        for i in s.pawns.indices where i % 2 == 0 { s.pawns[i].assignedWork = .farming }
        s.policy = ColonyPolicy(trades: [.mining: .priority], roster: .spareHands)

        let party = LocalPOIEngine.chooseParty(s, for: .cave, ticksPerYear: ticksPerYear)
        #expect(!party.isEmpty, "the colony refused to send anybody at all")
        for id in party {
            #expect(s.pawns.first { $0.id == id }?.assignedWork != .mining,
                    "a cave party stripped the mine it was meant to spare")
        }
        // With no such order, the best miners go, which is the old behaviour.
        s.policy = ColonyPolicy()
        let free = LocalPOIEngine.chooseParty(s, for: .cave, ticksPerYear: ticksPerYear)
        let freeTrades = free.compactMap { id in s.pawns.first { $0.id == id }?.assignedWork }
        #expect(freeTrades.contains(.mining))
    }

    // MARK: - The words

    @Test("Every order is written in both languages")
    func everyOrderIsBilingual() {
        for language in [GameLanguage.en, .cs] {
            for stance in ColonyPolicy.TradeStance.allCases {
                #expect(!stance.label.resolve(language).isEmpty)
            }
            for ration in ColonyPolicy.Ration.allCases {
                #expect(!ration.label.resolve(language).isEmpty)
                #expect(!ration.detail.resolve(language).isEmpty)
            }
            for roster in ColonyPolicy.Roster.allCases {
                #expect(!roster.label.resolve(language).isEmpty)
            }
        }
    }
}
