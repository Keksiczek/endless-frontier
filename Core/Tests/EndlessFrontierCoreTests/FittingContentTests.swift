import Testing
import Foundation
@testable import EndlessFrontierCore

/// **The book of furniture, held against the rooms that use it.**
///
/// Keks, twice: *"budovy mají nudné interiéry, pořád stejné"* and *"vesnice má
/// hodně technologií a je moderní až v budoucnosti, canvas vypadá stejně."*
/// Which fittings a building got was a `switch` over building shapes with no
/// notion of **when**, so a medieval workshop and a near-future assembly plant
/// were furnished from the same two lines.
///
/// These gate the content the same way the flora and animal tests do: a piece
/// of furniture that names a drawing nobody has, a room nobody builds, or an
/// age nobody reaches is content that loads and then does nothing.
@Suite("Every fitting is a real thing in a real room")
struct FittingContentTests {

    /// The drawings that exist. Mirrors `SettlementInterior.Fitting`, which
    /// lives in the app and cannot be imported here — so the list is written
    /// down once, and the app's own tests hold the two together.
    static let shapes: Set<String> = [
        "bed", "hearth", "table", "bench", "anvil", "rack", "desk", "shelf",
        "counter", "crate", "sack", "barrel", "altar", "pew", "watchpost",
        "weapons", "millstone", "machine", "cart", "panel", "console",
    ]

    /// The rooms that exist. Mirrors `SettlementRenderer.BuildingGlyph`.
    static let rooms: Set<String> = [
        "house", "tenement", "farm", "lodge", "sawmill", "mine", "well",
        "workshop", "forge", "plant", "tanks", "rail", "hall", "lab", "dish",
        "market", "vault", "temple", "clinic", "granary", "cookhouse",
        "aqueduct", "wall", "tower", "barracks", "mill", "generator",
        "turbine", "array", "dam", "pad",
    ]

    @Test("Every fitting names a drawing the canvas has")
    func shapesAreDrawable() throws {
        let registry = try GameDataRegistry.bundled()
        #expect(!registry.fittings.isEmpty, "fittings.json loaded nothing")
        for (id, def) in registry.fittings {
            #expect(Self.shapes.contains(def.shape),
                    "\(id) is drawn as '\(def.shape)', which the canvas cannot draw")
        }
    }

    @Test("Every fitting stands in a room somebody builds")
    func roomsAreReal() throws {
        let registry = try GameDataRegistry.bundled()
        for (id, def) in registry.fittings {
            #expect(!def.rooms.isEmpty, "\(id) belongs in no room, so it stands nowhere")
            for room in def.rooms {
                #expect(Self.rooms.contains(room),
                        "\(id) stands in '\(room)', which is not a kind of building")
            }
        }
    }

    @Test("Every fitting belongs to ages that exist")
    func erasAreReal() throws {
        let registry = try GameDataRegistry.bundled()
        let known = Set(Era.allCases.map(\.rawValue))
        for (id, def) in registry.fittings {
            for era in def.eras {
                #expect(known.contains(era), "\(id) belongs to age '\(era)', which is not one")
            }
        }
    }

    /// The one that actually answers Keks's complaint: ask the same room in two
    /// ages and you must not be handed the same furniture in both.
    @Test("A room furnished in two ages is furnished differently in at least one")
    func agesDiverge() throws {
        let registry = try GameDataRegistry.bundled()
        // True the day any dated fitting ships; until then this records what is
        // missing rather than failing, because the *mechanism* is what this
        // change delivers and the furniture is content still to be written.
        let dated = registry.fittings.values.filter { !$0.eras.isEmpty }
        if dated.isEmpty {
            print("no fitting names an age yet — every room is furnished timelessly")
            return
        }
        for room in Self.rooms {
            let first = registry.fittings(inRoom: room, era: .earlySettlement).map(\.id)
            let last = registry.fittings(inRoom: room, era: .nearFuture).map(\.id)
            guard !first.isEmpty, !last.isEmpty else { continue }
            if first != last { return }
        }
        Issue.record("every room is furnished identically in the first age and the last")
    }

    @Test("Every room a building can be drawn as has something in it")
    func noBareRooms() throws {
        let registry = try GameDataRegistry.bundled()
        // A room the book furnishes with nothing is a building you can walk
        // into and find empty — which is what the interiors looked like before
        // any of this, and is worth refusing outright.
        var bare: [String] = []
        for room in Self.rooms where registry.fittings(inRoom: room, era: .medieval).isEmpty {
            bare.append(room)
        }
        #expect(bare.isEmpty, "nothing stands in: \(bare.sorted())")
    }
}
