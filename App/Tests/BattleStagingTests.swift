import Testing
import Foundation
import EndlessFrontierCore
@testable import EndlessFrontier

/// The battle is drawn from the record, and the colonists in it are sent to the
/// same places the fight is drawn at. These are the joints where that can come
/// apart silently — a line drawn where nobody stands, or a defender running to
/// a post the raiders never reach.
@Suite("Battle staging")
struct BattleStagingTests {

    private func log(line: [UUID], approach: Double = 0, repelled: Bool = false,
                     tick: Int = 100, attackers: Int = 6) -> BattleLog {
        BattleLog(id: UUID(), tick: tick, attackerName: "Raiders",
                  defenderName: "Home",
                  moments: [BattleMoment(id: 0, at: 0.2, kind: .charge)],
                  repelled: repelled, approach: approach,
                  attackers: attackers, line: line)
    }

    @Test("A defender in the line is sent to the line, and gets there")
    func defenderConverges() {
        let me = UUID()
        let battle = log(line: [me, UUID(), UUID()])
        let home = LocalPoint(x: 0.5, y: 0.52)

        let early = SettlementBattle.station(for: me, log: battle, progress: 0.02, from: home)
        let held = SettlementBattle.station(for: me, log: battle, progress: 0.9, from: home)

        #expect(early != nil)
        #expect(early?.arrived == false)
        #expect(held?.arrived == true)
        // They have actually gone somewhere: the post is not the heart.
        let post = try! #require(held).position
        #expect(abs(post.x - home.x) + abs(post.y - home.y) > 0.1)
    }

    @Test("Anyone not mustered keeps their day")
    func bystandersAreLeftAlone() {
        let battle = log(line: [UUID()])
        #expect(SettlementBattle.station(for: UUID(), log: battle, progress: 0.5,
                                         from: LocalPoint(x: 0.5, y: 0.5)) == nil)
    }

    @Test("The line stands between the town and where the attack came from")
    func lineFacesTheAttack() {
        // An attack from due east: the line must form east of the heart.
        let field = SettlementBattle.Field(log(line: [], approach: 0))
        #expect(field.front.x > field.heart.x)
        #expect(field.origin.x > field.front.x)
        // …and from due west, the other way.
        let west = SettlementBattle.Field(log(line: [], approach: .pi))
        #expect(west.front.x < west.heart.x)
    }

    @Test("Defenders stand shoulder to shoulder, not on one another")
    func lineIsSpreadOut() {
        let ids = (0..<6).map { _ in UUID() }
        let field = SettlementBattle.Field(log(line: ids))
        let posts = ids.indices.map { field.defenderPost(index: $0, of: ids.count) }
        for i in posts.indices {
            for j in posts.indices where j > i {
                let dx = posts[i].x - posts[j].x, dy = posts[i].y - posts[j].y
                #expect((dx * dx + dy * dy).squareRoot() > 0.01)
            }
        }
    }

    @Test("A fight is live over its tick and a little after, and not before")
    func liveWindow() {
        var settlement = Settlement(id: UUID(), name: "Home", regionID: UUID())
        settlement.lastBattle = log(line: [], tick: 100)
        #expect(SettlementBattle.live(settlement, continuousTick: 99.5) == nil)
        #expect(SettlementBattle.live(settlement, continuousTick: 100.4) != nil)
        #expect(SettlementBattle.live(settlement, continuousTick: 101.2) != nil)
        #expect(SettlementBattle.live(settlement, continuousTick: 102) == nil)
    }
}

/// Rooms are furnished by a pure function of `(glyph, seed, workers)`, and the
/// colonists posted to a building stand at the fittings that function drew.
@Suite("Building interiors")
struct InteriorTests {

    @Test("Every worker gets a station of their own")
    func workersGetStations() {
        for workers in 1...5 {
            let stations = SettlementInterior.stationSlots(
                for: .workshop, seed: 42, stations: workers)
            #expect(stations.count >= min(workers, 5))
        }
    }

    @Test("Stations stay inside the room's walls")
    func stationsAreIndoors() {
        for glyph in [SettlementRenderer.BuildingGlyph.house, .hall, .granary,
                      .temple, .plant, .pad] {
            for slot in SettlementInterior.slots(for: glyph, seed: 7, stations: 4) {
                let limit = 0.5 - SettlementInterior.wallInset
                #expect(abs(slot.dx) <= limit, "\(glyph) \(slot.fitting) escaped sideways")
                #expect(abs(slot.dy) <= limit, "\(glyph) \(slot.fitting) escaped downwards")
            }
        }
    }

    @Test("Two stations are never the same spot")
    func stationsDoNotOverlap() {
        let slots = SettlementInterior.stationSlots(for: .plant, seed: 9, stations: 6)
        for i in slots.indices {
            for j in slots.indices where j > i {
                let dx = slots[i].dx - slots[j].dx, dy = slots[i].dy - slots[j].dy
                #expect((dx * dx + dy * dy).squareRoot() > 0.05)
            }
        }
    }

    @Test("An empty building is still a furnished room")
    func emptyRoomsAreFurnished() {
        #expect(!SettlementInterior.slots(for: .granary, seed: 1, stations: 0).isEmpty)
    }

    @Test("The roof is solid from far off and gone up close")
    func roofLifts() {
        #expect(SettlementInterior.roofFade(zoom: 1) == 1)
        #expect(SettlementInterior.roofFade(zoom: 4) == 0)
        let middle = SettlementInterior.roofFade(zoom: 2.1)
        #expect(middle > 0 && middle < 1)
    }
}
