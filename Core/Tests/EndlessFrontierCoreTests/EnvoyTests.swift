import Testing
import Foundation
@testable import EndlessFrontierCore

/// **An embassy is a colonist who is not here.**
///
/// That is the whole cost, and the reason it is a decision rather than a
/// purchase. What it buys is not a lump of standing but a **rate**:
/// `DiplomacyProbe` measured standings swinging over bands of fifty-eight to a
/// hundred and fifty-five points, so any single payment is noise, and a verb is
/// felt when it accrues. See `docs/NEIGHBOURS.md` §2.1.
@Suite("Somebody of ours lives among them")
struct EnvoyTests {
    private func world() throws -> (WorldState, GameDataRegistry) {
        let registry = try GameDataRegistry.bundled()
        var s = GameWorldFactory.newGame(registry: registry, seed: 29,
                                         now: Date(timeIntervalSince1970: 1_700_000_000))
        s.settlements[0].storage[.influence] = 4000
        for index in s.tribes.indices { s.tribes[index].discovered = true }
        return (s, registry)
    }

    private func them(_ s: WorldState) -> Tribe? { s.tribes.first(where: \.discovered) }

    @Test("Posting an envoy takes them out of the settlement's hands")
    func theEnvoyIsGone() throws {
        let (s, reg) = try world()
        guard let they = them(s) else { return }
        let working = s.settlements[0].pawns.count { !$0.isAway }

        let after = GameEngine.sendEnvoy(s, tribeID: they.id, registry: reg)
        #expect(GameEngine.envoy(in: after, toward: they.id) != nil, "nobody was posted")
        #expect(after.settlements[0].pawns.count { !$0.isAway } == working - 1,
                "the colony must be one pair of hands short — that is the whole cost")
    }

    @Test("It costs influence")
    func itIsNotFree() throws {
        let (s, reg) = try world()
        guard let they = them(s) else { return }
        let purse = s.settlements[0].storage[.influence]
        let after = GameEngine.sendEnvoy(s, tribeID: they.id, registry: reg)
        #expect(after.settlements[0].storage[.influence] < purse)
    }

    /// The point of the verb: it pays every year rather than once.
    @Test("An embassy that has stood for fifty years is worth more than one from last spring")
    func itAccrues() throws {
        var (s, reg) = try world()
        guard let they = them(s),
              let index = s.tribes.firstIndex(where: { $0.id == they.id }) else { return }
        s.tribes[index].standing = 0
        s = GameEngine.sendEnvoy(s, tribeID: they.id, registry: reg)

        var oneYear = DiplomacyEngine.envoyYear(s, tribeIndex: index)
        let after1 = oneYear.tribes[index].standing
        for _ in 0..<49 { oneYear = DiplomacyEngine.envoyYear(oneYear, tribeIndex: index) }
        #expect(oneYear.tribes[index].standing > after1 * 5,
                "a rate that does not accumulate is a payment with extra steps")
    }

    /// Rule 69, the expensive lesson from `RoadEngine`: the rate must exist
    /// because the embassy stands, not fire on an event.
    @Test("No embassy, no yearly gain")
    func nothingAccruesWithoutAnEnvoy() throws {
        let (s, _) = try world()
        guard let they = them(s),
              let index = s.tribes.firstIndex(where: { $0.id == they.id }) else { return }
        let before = s.tribes[index].standing
        #expect(DiplomacyEngine.envoyYear(s, tribeIndex: index).tribes[index].standing == before)
    }

    @Test("A people hosts one envoy, not a queue of them")
    func oneEnvoyPerPeople() throws {
        var (s, reg) = try world()
        guard let they = them(s) else { return }
        s = GameEngine.sendEnvoy(s, tribeID: they.id, registry: reg)
        let posted = s.settlements[0].pawns.count { $0.envoyToTribeID == they.id }
        s = GameEngine.sendEnvoy(s, tribeID: they.id, registry: reg)
        #expect(s.settlements[0].pawns.count { $0.envoyToTribeID == they.id } == posted)
    }

    /// Calling them home gives back the hands and keeps the standing: it was
    /// paid a year at a time and is not on loan.
    @Test("Recalling an envoy returns the colonist and keeps what they earned")
    func recallIsNotARefund() throws {
        var (s, reg) = try world()
        guard let they = them(s),
              let index = s.tribes.firstIndex(where: { $0.id == they.id }) else { return }
        s = GameEngine.sendEnvoy(s, tribeID: they.id, registry: reg)
        for _ in 0..<10 { s = DiplomacyEngine.envoyYear(s, tribeIndex: index) }
        let earned = s.tribes[index].standing
        let away = s.settlements[0].pawns.count { $0.isAway }

        let home = GameEngine.recallEnvoy(s, tribeID: they.id, registry: reg)
        #expect(home.settlements[0].pawns.count { $0.isAway } == away - 1)
        #expect(home.tribes[index].standing == earned, "the years they served still happened")
        #expect(GameEngine.envoy(in: home, toward: they.id) == nil)
    }

    @Test("A people nobody has met takes no envoy")
    func strangersHostNobody() throws {
        var (s, reg) = try world()
        guard let they = them(s),
              let index = s.tribes.firstIndex(where: { $0.id == they.id }) else { return }
        s.tribes[index].discovered = false
        #expect(GameEngine.envoy(
            in: GameEngine.sendEnvoy(s, tribeID: they.id, registry: reg),
            toward: they.id) == nil)
    }

    /// Rule 3: a save written before embassies existed decodes to nobody posted.
    @Test("A save from before embassies opens with nobody posted")
    func oldSavesDecode() throws {
        let (s, _) = try world()
        let data = try JSONEncoder().encode(s.settlements[0].pawns[0])
        var json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        json.removeValue(forKey: "envoyToTribeID")
        let decoded = try JSONDecoder().decode(
            Pawn.self, from: try JSONSerialization.data(withJSONObject: json))
        #expect(decoded.envoyToTribeID == nil)
        #expect(!decoded.isAway)
    }
}

/// **Buying peace**, and what it costs to stop.
///
/// `demandTribute` has always pointed outward; nothing pointed in, so a colony
/// that could not fight had no way to buy peace except a gift — one payment
/// against a grievance that keeps growing. This is the verb a losing player
/// needs. See `docs/NEIGHBOURS.md` §2.3.
@Suite("A colony that cannot fight can still buy peace")
struct TributeTests {
    private func world() throws -> (WorldState, GameDataRegistry) {
        let registry = try GameDataRegistry.bundled()
        var s = GameWorldFactory.newGame(registry: registry, seed: 31,
                                         now: Date(timeIntervalSince1970: 1_700_000_000))
        s.settlements[0].storage[.materials] = 5000
        for index in s.tribes.indices {
            s.tribes[index].discovered = true
            s.tribes[index].grudge = 80
        }
        return (s, registry)
    }

    private func first(_ s: WorldState) -> Int? { s.tribes.indices.first { s.tribes[$0].discovered } }

    @Test("Paying every year works a grievance down")
    func itBuysPeace() throws {
        var (s, reg) = try world()
        guard let index = first(s) else { return }
        s = GameEngine.payTribute(s, tribeID: s.tribes[index].id,
                                  perYear: DiplomacyEngine.tributeMostPerYear, registry: reg)
        let before = s.tribes[index].grudge
        s = DiplomacyEngine.collectTribute(s, tribeIndex: index)
        #expect(s.tribes[index].grudge < before)
        #expect(s.settlements[0].storage[.materials] < 5000, "…and it was paid for")
    }

    /// Half a tribute buys half a peace, so the amount is a real decision.
    @Test("What it buys is scaled by what is paid")
    func halfBuysHalf() throws {
        func relief(paying amount: Double) throws -> Double {
            var (s, reg) = try world()
            guard let index = first(s) else { return 0 }
            s = GameEngine.payTribute(s, tribeID: s.tribes[index].id,
                                      perYear: amount, registry: reg)
            let before = s.tribes[index].grudge
            return before - DiplomacyEngine.collectTribute(s, tribeIndex: index).tribes[index].grudge
        }
        let full = try relief(paying: DiplomacyEngine.tributeMostPerYear)
        let half = try relief(paying: DiplomacyEngine.tributeMostPerYear / 2)
        #expect(full > half)
        #expect(half > 0)
    }

    /// **The half that makes it a promise.** A colony that pays for twenty
    /// years and stops has taught a people to expect something and then taken
    /// it away, which is worse than never having offered.
    @Test("Stopping costs more than never having started")
    func breakingItHurts() throws {
        var (s, reg) = try world()
        guard let index = first(s) else { return }
        s = GameEngine.payTribute(s, tribeID: s.tribes[index].id,
                                  perYear: DiplomacyEngine.tributeMostPerYear, registry: reg)
        s.tribes[index].grudge = 40
        s.settlements[0].storage[.materials] = 0   // nothing to send

        let after = DiplomacyEngine.collectTribute(s, tribeIndex: index)
        #expect(after.tribes[index].grudge > 40, "they noticed")
        #expect(after.tribes[index].tributePerYear == 0, "…and the arrangement is over")
    }

    /// A colony that cannot pay and one that will not pay look the same from
    /// the other side, and the game must not pretend otherwise.
    @Test("Cannot pay and will not pay are the same thing to them")
    func povertyIsNotAnExcuse() throws {
        var (s, reg) = try world()
        guard let index = first(s) else { return }
        s = GameEngine.payTribute(s, tribeID: s.tribes[index].id, perYear: 60, registry: reg)
        s.tribes[index].grudge = 30
        var broke = s; broke.settlements[0].storage[.materials] = 0
        let refused = GameEngine.payTribute(s, tribeID: s.tribes[index].id,
                                            perYear: 0, registry: reg)
        let failed = DiplomacyEngine.collectTribute(broke, tribeIndex: index)
        #expect(failed.tribes[index].tributePerYear == 0)
        #expect(refused.tribes[index].tributePerYear == 0)
    }

    @Test("Nobody can be promised more than the ceiling")
    func thereIsACeiling() throws {
        let (s, reg) = try world()
        guard let index = first(s) else { return }
        let over = GameEngine.payTribute(
            s, tribeID: s.tribes[index].id,
            perYear: DiplomacyEngine.tributeMostPerYear * 3, registry: reg)
        #expect(over.tribes[index].tributePerYear == 0, "an impossible promise is not made")
    }

    @Test("No arrangement, no yearly charge")
    func nothingHappensWithoutOne() throws {
        let (s, _) = try world()
        guard let index = first(s) else { return }
        let purse = s.settlements[0].storage[.materials]
        #expect(DiplomacyEngine.collectTribute(s, tribeIndex: index)
                    .settlements[0].storage[.materials] == purse)
    }

    /// Rule 3: saves from before anybody could buy peace.
    @Test("A save from before tribute opens with nobody paying")
    func oldSavesDecode() throws {
        let (s, _) = try world()
        guard let index = first(s) else { return }
        let data = try JSONEncoder().encode(s.tribes[index])
        var json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        json.removeValue(forKey: "tributePerYear")
        let decoded = try JSONDecoder().decode(
            Tribe.self, from: try JSONSerialization.data(withJSONObject: json))
        #expect(decoded.tributePerYear == 0)
    }
}
