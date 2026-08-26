import Testing
import Foundation
@testable import EndlessFrontierCore

/// **Every death is somebody's.**
///
/// A tally is what the chronicle reads at the end of a year; a name is what the
/// player needs on the day. `SiegeEngine.conclude` counted the fallen into
/// `deathTallies`, removed them, and wrote **nothing at all** — a raid could
/// take four colonists and leave a number behind. `WildlifeEngine` did write a
/// line for a mauling but filed it under `.danger`, where it sorts with a bad
/// harvest and a broken roof. Keks: *"lidé umřeli na zvěř ale nevím o tom."*
@Suite("A death the colony hears about")
struct DeathRecordTests {

    static let registry = try! GameDataRegistry.bundled()

    private static func finishedSiege(startTick: Int = 100) -> Siege {
        var siege = Siege(
            id: UUID(uuidString: "00000000-0000-0000-DEAD-00000000000A")!,
            startTick: startTick, openedAt: startTick,
            attackerName: "Vlčí lid", approach: 0, attackers: 4,
            openingStrength: 20, fortification: 2, seed: 7, line: [])
        // Fought to the last step, so `conclude` will do its work.
        siege.advancedTo = startTick + siege.steps
        return siege
    }

    /// The one that wrote nothing.
    @Test("The fallen of a raid are named in the diary")
    func theRaidDeadAreNamed() {
        var s = Settlement(
            id: UUID(uuidString: "00000000-0000-0000-DEAD-000000000001")!,
            name: "Domov", kind: .capital,
            pawns: [Pawn(name: "Wren", health: 0), Pawn(name: "Ferd", health: 80)])
        s.siege = Self.finishedSiege()

        let after = SiegeEngine.conclude(s, registry: Self.registry)
        let deaths = after.journal.entries.filter { $0.kind == .death }
        #expect(deaths.count == 1,
                "a raid took a colonist and the diary wrote \(deaths.count) lines")
        #expect(deaths.first?.text.resolve(.en).contains("Wren") == true,
                "the fallen were counted, not named")
        // Both languages, like everything else the player reads.
        #expect(deaths.first?.text.resolve(.cs) != deaths.first?.text.resolve(.en))
        #expect(after.deathTallies[PawnDeathCause.battle.rawValue] == 1)
        #expect(!after.pawns.contains { $0.name == "Wren" })
    }

    @Test("A survivor is not mourned")
    func survivorsAreNotBuried() {
        var s = Settlement(
            id: UUID(uuidString: "00000000-0000-0000-DEAD-000000000003")!,
            name: "Domov", kind: .capital, pawns: [Pawn(name: "Ferd", health: 80)])
        s.siege = Self.finishedSiege()
        let after = SiegeEngine.conclude(s, registry: Self.registry)
        #expect(after.journal.entries.allSatisfy { $0.kind != .death })
        #expect(after.pawns.count == 1)
    }

    /// Four fell, four names. A raid that takes half the line should read as
    /// four losses rather than as one sentence with a number in it.
    @Test("Every one of the fallen gets their own line")
    func allTheFallenAreNamed() {
        var s = Settlement(
            id: UUID(uuidString: "00000000-0000-0000-DEAD-000000000005")!,
            name: "Domov", kind: .capital,
            pawns: [Pawn(name: "Wren", health: 0), Pawn(name: "Ferd", health: 0),
                    Pawn(name: "Ota", health: 0), Pawn(name: "Bela", health: 55)])
        s.siege = Self.finishedSiege()
        let after = SiegeEngine.conclude(s, registry: Self.registry)
        let deaths = after.journal.entries.filter { $0.kind == .death }
        #expect(deaths.count == 3)
        for name in ["Wren", "Ferd", "Ota"] {
            #expect(deaths.contains { $0.text.resolve(.en).contains(name) },
                    "\(name) fell and the diary does not say so")
        }
        #expect(after.pawns.map(\.name) == ["Bela"])
    }

    // A beast killing a hunter is driven from inside `WildlifeEngine.hunt`,
    // out of a `HuntEngine` bag that a test cannot hand it without reaching
    // through three engines. The change there is one word — `.danger` to
    // `.death` on the fatal branch — and a test asserting `.death != .danger`
    // would pass whatever the engine did, which is worse than no test. It is
    // covered where it can be: `ColonyLogEntry.Kind.death` is what the
    // journal's Deaths lens reads, and `JournalPanel` is where it shows.
}

/// **A warband made of people.**
///
/// A colonist has a name, a face, a trade and a history. The people who came to
/// kill them were `Combatant(strength:intent:)` — interchangeable tokens with
/// no way to tell one from the next, and a card that could only lead with the
/// band because there was nothing else to lead with. Keks: *"raideři nemají
/// žádné vlastní features."*
@Suite("Raiders are somebody")
struct RaiderIdentityTests {

    static let registry = try! GameDataRegistry.bundled()

    private static func raided(seed: UInt64 = 4242,
                               language: GameLanguage = .cs) -> Settlement {
        var s = Settlement(
            id: UUID(uuidString: "00000000-0000-0000-BAD0-000000000001")!,
            name: "Domov", kind: .capital,
            pawns: (0..<8).map { Pawn(name: "Osadník \($0)", health: 90) },
            storage: [.food: 400], storageCapacity: .uniform(2000))
        s.localMap = nil
        return SiegeEngine.begin(
            s, attackerStrength: 30, attackerName: "Vlčí lid",
            fortification: 2, tick: 100, registry: Self.registry, seed: seed,
            language: language, drawn: 6)
    }

    @Test("Everybody who came has a name")
    func theWarbandIsNamed() throws {
        let s = Self.raided()
        let siege = try #require(s.siege)
        #expect(!siege.raiders.isEmpty)
        for raider in siege.raiders {
            #expect(raider.name?.isEmpty == false,
                    "a raider turned up with no name")
        }
    }

    /// Not all the same name — a warband of six Bjorns is worse than none.
    @Test("They are not all the same person")
    func theyDiffer() throws {
        let siege = try #require(Self.raided().siege)
        let names = Set(siege.raiders.compactMap(\.name))
        #expect(names.count > 1, "the whole warband is called \(names)")
    }

    /// Rule 3: the same save reopened is the same warband.
    @Test("The same raid names the same people twice")
    func namingIsDeterministic() throws {
        let a = try #require(Self.raided().siege).raiders.compactMap(\.name)
        let b = try #require(Self.raided().siege).raiders.compactMap(\.name)
        #expect(a == b)
    }

    @Test("A different raid is different people")
    func adifferentRaidDiffers() throws {
        let a = try #require(Self.raided(seed: 1).siege).raiders.compactMap(\.name)
        let b = try #require(Self.raided(seed: 2).siege).raiders.compactMap(\.name)
        #expect(a != b)
    }

    /// A warband saved before any of this is a warband of strangers, and reads
    /// exactly as it used to rather than failing the save (rule 3).
    @Test("A raid saved before names decodes to a nameless one")
    func oldSavesLoad() throws {
        let old = """
        {"id":"00000000-0000-0000-0000-00000000000A","side":"raider",
         "at":{"x":0.5,"y":0.5},"strength":4.0,"down":false}
        """
        let one = try JSONDecoder().decode(Siege.Combatant.self, from: Data(old.utf8))
        #expect(one.name == nil)
        #expect(one.strength == 4.0)
    }
}
