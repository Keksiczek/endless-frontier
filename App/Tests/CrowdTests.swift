import Testing
import Foundation
import EndlessFrontierCore
@testable import EndlessFrontier

/// A town of sixty has to read as a town. These pin the grouping: that people
/// standing together become one mark, that people across the valley do not,
/// and that pushing the camera in gives you the people back.
@Suite("A crowd read from a distance")
struct CrowdTests {

    private func person(_ n: Int, at p: LocalPoint, trade: WorkKind = .farming,
                        hurt: Bool = false)
    -> (id: UUID, position: LocalPoint, trade: WorkKind, hurt: Bool) {
        (UUID(uuidString: String(format: "00000000-0000-0000-C90D-%012d", n))!, p, trade, hurt)
    }

    @Test("People standing together become one mark")
    func nearbyPeopleGroup() {
        let clusters = SettlementCrowd.cluster([
            person(0, at: LocalPoint(x: 0.50, y: 0.50)),
            person(1, at: LocalPoint(x: 0.51, y: 0.50)),
            person(2, at: LocalPoint(x: 0.50, y: 0.51)),
        ])
        #expect(clusters.count == 1)
        #expect(clusters[0].count == 3)
    }

    @Test("People across the valley from each other do not")
    func distantPeopleStayApart() {
        let clusters = SettlementCrowd.cluster([
            person(0, at: LocalPoint(x: 0.1, y: 0.1)),
            person(1, at: LocalPoint(x: 0.9, y: 0.9)),
        ])
        #expect(clusters.count == 2)
    }

    @Test("A group stands among its people, not on whoever got there first")
    func theMarkSitsInTheMiddle() {
        let clusters = SettlementCrowd.cluster([
            person(0, at: LocalPoint(x: 0.50, y: 0.50)),
            person(1, at: LocalPoint(x: 0.53, y: 0.50)),
        ])
        #expect(clusters.count == 1)
        #expect(clusters[0].position.x > 0.50)
        #expect(clusters[0].position.x < 0.53)
    }

    @Test("A group is named for what most of it is doing")
    func theCommonestTradeWins() {
        let clusters = SettlementCrowd.cluster([
            person(0, at: LocalPoint(x: 0.5, y: 0.5), trade: .logging),
            person(1, at: LocalPoint(x: 0.51, y: 0.5), trade: .logging),
            person(2, at: LocalPoint(x: 0.5, y: 0.51), trade: .mining),
        ])
        #expect(clusters[0].trade == .logging)
    }

    @Test("Somebody hurt in the group is flagged on it")
    func woundedEscalate() {
        let clusters = SettlementCrowd.cluster([
            person(0, at: LocalPoint(x: 0.5, y: 0.5)),
            person(1, at: LocalPoint(x: 0.51, y: 0.5), hurt: true),
        ])
        #expect(clusters[0].anyHurt)
    }

    @Test("Everybody ends up in exactly one group")
    func nobodyIsLostOrDoubled() {
        let people = (0..<40).map { i in
            person(i, at: LocalPoint(x: 0.2 + Double(i % 7) * 0.09,
                                     y: 0.2 + Double(i / 7) * 0.09))
        }
        let clusters = SettlementCrowd.cluster(people)
        #expect(clusters.reduce(0) { $0 + $1.count } == people.count)
        let ids = Set(clusters.flatMap(\.members))
        #expect(ids.count == people.count)
    }

    @Test("Push the camera in and you get the people back")
    func detailReturnsWithZoom() {
        #expect(!SettlementCrowd.showsIndividuals(zoom: 1))
        #expect(SettlementCrowd.showsIndividuals(zoom: 3))
    }

    @Test("Grouping does not jitter between identical frames")
    func groupingIsStable() {
        let people = (0..<12).map { i in
            person(i, at: LocalPoint(x: 0.4 + Double(i % 4) * 0.02,
                                     y: 0.4 + Double(i / 4) * 0.02))
        }
        let a = SettlementCrowd.cluster(people)
        let b = SettlementCrowd.cluster(people)
        #expect(a.map(\.count) == b.map(\.count))
        #expect(a.map(\.position) == b.map(\.position))
    }

    @Test("An empty colony makes no marks")
    func nobodyMakesNothing() {
        #expect(SettlementCrowd.cluster([]).isEmpty)
    }
}
