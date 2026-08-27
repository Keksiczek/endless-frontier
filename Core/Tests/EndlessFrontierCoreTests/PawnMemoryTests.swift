import Foundation
import Testing
@testable import EndlessFrontierCore

/// What a colonist carries of their own life.
///
/// The inspector card's *what happened to them* section reads two stores and
/// the interesting one is the second. `MemoryProbe` measured the first: the
/// colony's journal is a ring of 140 entries shared by everybody, and at year
/// 200 of seed 4242 it spans **one in-game year** with four fifths of it taken
/// up by chatter. Subjects were never the shortage — 113–125 of the 140 held
/// entries already named somebody. *Keeping* was.
@Suite("What a colonist remembers")
struct PawnMemoryTests {

    /// `note` is the only door, and it files a moment on the people named and
    /// on nobody else.
    @Test("A moment is kept by the people it happened to")
    func keptByTheNamed() {
        var settlement = Fixtures.world(population: 3).settlements[0]
        let bride = settlement.pawns[0].id
        let groom = settlement.pawns[1].id
        let bystander = settlement.pawns[2].id

        settlement.note(tick: 10, kind: .social,
                        text: LocalizedText(values: [.en: "wed", .cs: "svatba"]),
                        subject: .pawn(bride), keptBy: [bride, groom])

        #expect(settlement.pawns[0].keepsakes.count == 1)
        #expect(settlement.pawns[1].keepsakes.count == 1)
        #expect(settlement.pawns[2].keepsakes.isEmpty)
        #expect(settlement.pawns[0].keepsakes[0].id == settlement.journal.entries[0].id)
        _ = bystander
    }

    /// Chatter goes in the diary and stays out of a life.
    @Test("A line nobody keeps is only in the journal")
    func unkeptStaysInTheRing() {
        var settlement = Fixtures.world(population: 2).settlements[0]
        settlement.note(tick: 1, kind: .social,
                        text: LocalizedText(values: [.en: "chat", .cs: "klábosení"]),
                        subject: .pawn(settlement.pawns[0].id))
        #expect(settlement.journal.entries.count == 1)
        #expect(settlement.pawns.allSatisfy { $0.keepsakes.isEmpty })
    }

    /// **The reachability this exists for.** A wedding has to still be there
    /// after the colony has talked over it — which, at real colony size, takes
    /// about a year.
    @Test("What a colonist remembers outlives the colony's journal")
    func keepsakeOutlivesTheRing() {
        var settlement = Fixtures.world(population: 2).settlements[0]
        let who = settlement.pawns[0].id
        settlement.note(tick: 1, kind: .social,
                        text: LocalizedText(values: [.en: "wed", .cs: "svatba"]),
                        subject: .pawn(who), keptBy: [who])
        let weddingID = settlement.journal.entries[0].id

        for tick in 2...(ColonyLog.capacity + 20) {
            settlement.note(tick: tick, kind: .work,
                            text: LocalizedText(values: [.en: "work", .cs: "práce"]))
        }

        #expect(!settlement.journal.entries.contains { $0.id == weddingID })
        #expect(settlement.pawns[0].keepsakes.contains { $0.id == weddingID })
    }

    /// A life, not a diary: past the cap the newest moments are the ones kept.
    @Test("A colonist carries a life's worth and no more")
    func theCap() {
        var settlement = Fixtures.world(population: 1).settlements[0]
        let who = settlement.pawns[0].id
        for tick in 1...(Pawn.keepsakeCapacity + 5) {
            settlement.note(tick: tick, kind: .birth,
                            text: LocalizedText(values: [.en: "\(tick)", .cs: "\(tick)"]),
                            keptBy: [who])
        }
        let kept = settlement.pawns[0].keepsakes
        #expect(kept.count == Pawn.keepsakeCapacity)
        #expect(kept.last?.tick == Pawn.keepsakeCapacity + 5)
        #expect(kept.first?.tick == 6)
    }

    /// A line naming somebody twice is one moment, not two.
    @Test("The same moment is kept once")
    func filedOnce() {
        var settlement = Fixtures.world(population: 1).settlements[0]
        let who = settlement.pawns[0].id
        settlement.note(tick: 3, kind: .arrival,
                        text: LocalizedText(values: [.en: "came", .cs: "přišli"]),
                        keptBy: [who, who])
        #expect(settlement.pawns[0].keepsakes.count == 1)
    }

    /// Rule 73: a stored property that is not in the coding keys is thrown
    /// away on the next save, and a round-trip over an empty field proves
    /// nothing. So this one carries a value.
    @Test("Keepsakes survive a save")
    func roundTrip() throws {
        var world = Fixtures.world(population: 2)
        let who = world.settlements[0].pawns[0].id
        world.settlements[0].note(tick: 7, kind: .birth,
                                  text: LocalizedText(values: [.en: "born", .cs: "narodil se"]),
                                  subject: .pawn(who), keptBy: [who])

        let data = try JSONEncoder().encode(world)
        let back = try JSONDecoder().decode(WorldState.self, from: data)
        #expect(back.settlements[0].pawns[0].keepsakes.count == 1)
        #expect(back.settlements[0].pawns[0].keepsakes[0].text.resolve(.cs) == "narodil se")
    }

    /// Rule 3: a save written before anybody kept anything still loads, and
    /// the colonist simply has nothing to tell you yet.
    @Test("A colonist saved before keepsakes existed loads with none")
    func oldSavesDecode() throws {
        var world = Fixtures.world(population: 1)
        world.settlements[0].note(tick: 1, kind: .work,
                                  text: LocalizedText(values: [.en: "a", .cs: "a"]))
        let data = try JSONEncoder().encode(world)
        var json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        var settlements = try #require(json["settlements"] as? [[String: Any]])
        var pawns = try #require(settlements[0]["pawns"] as? [[String: Any]])
        pawns[0].removeValue(forKey: "keepsakes")
        settlements[0]["pawns"] = pawns
        json["settlements"] = settlements

        let stripped = try JSONSerialization.data(withJSONObject: json)
        let back = try JSONDecoder().decode(WorldState.self, from: stripped)
        #expect(back.settlements[0].pawns[0].keepsakes.isEmpty)
    }

    /// The wiring, in a colony that is actually being played. Rule 67: assert
    /// the precondition — that anything happened at all — before the thing
    /// this test came for.
    @Test("A colony at play writes moments onto the people they happened to")
    func aRealColonyRemembers() throws {
        let registry = try GameDataRegistry.bundled()
        var state = GameWorldFactory.newGame(registry: registry, seed: 4242)
        state = TickEngine.advance(state, ticks: 600, registry: registry).state
        let settlement = try #require(state.settlements.first)

        #expect(!settlement.journal.entries.isEmpty)          // the colony had a life
        let remembering = settlement.pawns.filter { !$0.keepsakes.isEmpty }
        #expect(!remembering.isEmpty)
        // …and what they carry is the shape of a life, not the day's gossip.
        let kinds = Set(remembering.flatMap { $0.keepsakes.map(\.kind) })
        #expect(kinds.contains(.birth) || kinds.contains(.social))
    }
}
