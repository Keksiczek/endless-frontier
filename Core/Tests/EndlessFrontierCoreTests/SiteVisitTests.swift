import Testing
import Foundation
@testable import EndlessFrontierCore

/// A visit used to be: walk out, roll once, add resources, walk home. The walk
/// was simulated at eight steps a tick and the *destination* was a number, so
/// an expedition felt instant however long it lasted. These are named for the
/// thing that was missing: something to find, something in the way, and a
/// reason it might not work.
@Suite("A place worth walking to")
struct SiteVisitTests {

    private func registry() throws -> GameDataRegistry { try GameDataRegistry.bundled() }

    private func poi(_ kind: LocalPOIKind, at p: LocalPoint = LocalPoint(x: 0.8, y: 0.3)) -> LocalPOI {
        LocalPOI(id: 1, kind: kind, position: p, discovered: true)
    }

    private func party(_ n: Int) -> [Pawn] {
        (0..<n).map { i in
            var pawn = Pawn(
                id: UUID(uuidString: String(format: "00000000-0000-0000-5171-%012d", i + 1))!,
                name: "Walker \(i)")
            pawn.age = 26 * 60
            return pawn
        }
    }

    private func town(_ pawns: [Pawn], poi kind: LocalPOIKind) -> Settlement {
        var s = Settlement(
            id: UUID(uuidString: "00000000-0000-0000-5171-FFFFFFFFFFFF")!,
            name: "Camp", kind: .capital, pawns: pawns,
            storage: [.food: 500], storageCapacity: 999)
        s.localMap = LocalMap(river: RiverShape(baseY: 0.8, amplitude: 0.02, phase: 0),
                              nodes: [], pois: [poi(kind)])
        return s
    }

    // MARK: - There is something in there

    @Test("A ruin holds things, not a number")
    func aPlaceHoldsThings() throws {
        let site = SiteVisitEngine.lay(out: poi(.ruins), party: party(3).map(\.id), seed: 77)
        #expect(site.things.contains { $0.kind == .cache }, "nothing to come for")
        #expect(site.things.allSatisfy { !$0.done })
        #expect(site.progress == 0)
        #expect(site.beats.first?.kind == .arrived)
    }

    /// Rule 6, in the direction that matters here: if a party cannot reach the
    /// things at the pace it walks in the steps it is given, a site is a room
    /// nobody ever gets into and every expedition comes home empty.
    @Test("A party can actually reach and clear what a place holds")
    func aSiteIsClearableInTheTimeAllowed() throws {
        let reg = try registry()
        for kind in LocalPOIKind.allCases {
            var s = town(party(4), poi: kind)
            let expedition = POIExpedition(
                id: UUID(uuidString: "00000000-0000-0000-5171-000000000AAA")!,
                poiID: 1, memberIDs: s.pawns.map(\.id), departedTick: 0,
                travelTicks: 1, workTicks: kind.workTicks,
                site: SiteVisitEngine.lay(out: poi(kind), party: s.pawns.map(\.id), seed: 9))
            s.expeditions = [expedition]
            guard !(s.expeditions[0].site?.things.isEmpty ?? true) else { continue }
            for step in 0..<(kind.workTicks * WorldClock.actionStepsPerTick) {
                s = SiteVisitEngine.advanceStep(s, expeditionIndex: 0, step: step, registry: reg)
            }
            let site = try #require(s.expeditions[0].site)
            #expect(site.isCleared, "\(kind) is a room nobody can finish searching")
        }
    }

    @Test("What comes home is what they got the lid off")
    func lootIsWhatWasOpened() throws {
        let reg = try registry()
        var s = town(party(4), poi: .treasure)
        s.expeditions = [POIExpedition(
            id: UUID(uuidString: "00000000-0000-0000-5171-000000000BBB")!,
            poiID: 1, memberIDs: s.pawns.map(\.id), departedTick: 0,
            travelTicks: 1, workTicks: 6,
            site: SiteVisitEngine.lay(out: poi(.treasure), party: s.pawns.map(\.id), seed: 5))
        ]
        let held = try #require(s.expeditions[0].site).things.count { $0.kind == .cache }
        for step in 0..<60 {
            s = SiteVisitEngine.advanceStep(s, expeditionIndex: 0, step: step, registry: reg)
        }
        let site = try #require(s.expeditions[0].site)
        #expect(site.loot.values.reduce(0, +) == held, "the chests were not emptied")
        #expect(site.beats.contains { $0.kind == .opened })
        #expect(site.beats.contains { $0.kind == .cleared })
    }

    /// The place has to be able to cost something, or it is scenery again.
    @Test("A guarded place fights back, and it is somebody in particular")
    func aGuardedPlaceHurts() throws {
        let reg = try registry()
        var s = town(party(2), poi: .barrow)
        s.expeditions = [POIExpedition(
            id: UUID(uuidString: "00000000-0000-0000-5171-000000000CCC")!,
            poiID: 1, memberIDs: s.pawns.map(\.id), departedTick: 0,
            travelTicks: 1, workTicks: 7,
            site: SiteVisitEngine.lay(out: poi(.barrow), party: s.pawns.map(\.id), seed: 3))
        ]
        #expect(try #require(s.expeditions[0].site).isGuarded, "a barrow should not be empty")
        for step in 0..<80 {
            s = SiteVisitEngine.advanceStep(s, expeditionIndex: 0, step: step, registry: reg)
        }
        let site = try #require(s.expeditions[0].site)
        #expect(site.beats.contains { $0.kind == .fought || $0.kind == .killed })
        #expect(s.pawns.contains { $0.health < 100 }, "two people robbed a guarded grave for free")
        // And the record names who it happened to.
        let named = site.beats.compactMap(\.pawnName)
        #expect(!named.isEmpty)
    }

    @Test("Guardians are dealt with before the chests")
    func theLivingComeFirst() throws {
        let reg = try registry()
        var s = town(party(3), poi: .cave)
        s.expeditions = [POIExpedition(
            id: UUID(uuidString: "00000000-0000-0000-5171-000000000DDD")!,
            poiID: 1, memberIDs: s.pawns.map(\.id), departedTick: 0,
            travelTicks: 1, workTicks: 10,
            site: SiteVisitEngine.lay(out: poi(.cave), party: s.pawns.map(\.id), seed: 11))
        ]
        var firstKill: Int?
        var firstOpen: Int?
        for step in 0..<120 {
            s = SiteVisitEngine.advanceStep(s, expeditionIndex: 0, step: step, registry: reg)
            let beats = s.expeditions[0].site?.beats ?? []
            if firstKill == nil, beats.contains(where: { $0.kind == .killed }) { firstKill = step }
            if firstOpen == nil, beats.contains(where: { $0.kind == .opened }) { firstOpen = step }
        }
        if let firstKill, let firstOpen {
            #expect(firstKill <= firstOpen, "they robbed the room with something still in it")
        }
    }

    // MARK: - The invariants everything else here rests on

    @Test("The same place worked twice goes exactly the same way")
    func deterministic() throws {
        let reg = try registry()
        func run() -> Settlement {
            var s = town(party(3), poi: .ruins)
            s.expeditions = [POIExpedition(
                id: UUID(uuidString: "00000000-0000-0000-5171-000000000EEE")!,
                poiID: 1, memberIDs: s.pawns.map(\.id), departedTick: 0,
                travelTicks: 1, workTicks: 8,
                site: SiteVisitEngine.lay(out: poi(.ruins), party: s.pawns.map(\.id), seed: 21))
            ]
            for step in 0..<90 {
                s = SiteVisitEngine.advanceStep(s, expeditionIndex: 0, step: step, registry: reg)
            }
            return s
        }
        let a = run(), b = run()
        #expect(a.pawns.map(\.health) == b.pawns.map(\.health))
        #expect(a.expeditions[0].site == b.expeditions[0].site)
    }

    @Test("A half-searched place survives being written to disk")
    func siteSurvivesASave() throws {
        let reg = try registry()
        var s = town(party(3), poi: .ruins)
        s.expeditions = [POIExpedition(
            id: UUID(uuidString: "00000000-0000-0000-5171-00000000FFFF")!,
            poiID: 1, memberIDs: s.pawns.map(\.id), departedTick: 0,
            travelTicks: 1, workTicks: 8,
            site: SiteVisitEngine.lay(out: poi(.ruins), party: s.pawns.map(\.id), seed: 33))
        ]
        for step in 0..<12 {
            s = SiteVisitEngine.advanceStep(s, expeditionIndex: 0, step: step, registry: reg)
        }
        let back = try JSONDecoder().decode(
            Settlement.self, from: try JSONEncoder().encode(s))
        #expect(back.expeditions[0].site == s.expeditions[0].site)
    }

    /// Rule 3. A journey that was already out when the game was updated must
    /// still come home rather than crash into an absent field.
    @Test("An expedition saved before places had anything in them still loads")
    func oldExpeditionsLoad() throws {
        let json = """
        {"id":"00000000-0000-0000-5171-000000000001","poiID":1,
         "memberIDs":[],"departedTick":4,"travelTicks":2,"workTicks":3,
         "casualtyDied":false}
        """
        let old = try JSONDecoder().decode(POIExpedition.self, from: Data(json.utf8))
        #expect(old.site == nil)
        #expect(old.workTicks == 3)
    }

    @Test("A party wiped out on the way stops the search rather than looping")
    func nobodyLeftEndsIt() throws {
        let reg = try registry()
        var s = town(party(1), poi: .ruins)
        s.expeditions = [POIExpedition(
            id: UUID(uuidString: "00000000-0000-0000-5171-000000000111")!,
            poiID: 1, memberIDs: s.pawns.map(\.id), departedTick: 0,
            travelTicks: 1, workTicks: 8,
            site: SiteVisitEngine.lay(out: poi(.ruins), party: s.pawns.map(\.id), seed: 44))
        ]
        s.pawns[0].health = 0
        s = SiteVisitEngine.advanceStep(s, expeditionIndex: 0, step: 1, registry: reg)
        let site = try #require(s.expeditions[0].site)
        #expect(site.beats.contains { $0.kind == .driven })
    }
}
