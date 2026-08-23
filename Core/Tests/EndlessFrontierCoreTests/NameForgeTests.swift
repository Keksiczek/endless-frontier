import Foundation
import Testing
@testable import EndlessFrontierCore

/// Generated names speak the world's language — Czech or English — and stay
/// deterministic and collision-free where the map depends on it.
@Suite("Name forge")
struct NameForgeTests {
    @Test("Colonist names are deterministic and language-styled")
    func colonistNames() {
        var a = SeededRNG(seed: 7)
        var b = SeededRNG(seed: 7)
        #expect(NameForge.colonistName(language: .cs, using: &a)
                == NameForge.colonistName(language: .cs, using: &b))

        var cs = SeededRNG(seed: 11)
        var en = SeededRNG(seed: 11)
        let czech = NameForge.colonistName(language: .cs, using: &cs)
        let english = NameForge.colonistName(language: .en, using: &en)
        #expect(czech != english)   // same rolls, different pools
    }

    @Test("Region pools have identical sizes in both languages")
    func regionPoolParity() {
        #expect(NameForge.csRegionStems.count == NameForge.regionFirsts)
        #expect(NameForge.enRegionStems.count == NameForge.regionFirsts)
        #expect(NameForge.csRegionAdjectives.count == NameForge.regionFirsts)
        #expect(NameForge.enRegionAdjectives.count == NameForge.regionFirsts)
        #expect(NameForge.csRegionSuffixes.count == NameForge.regionSeconds)
        #expect(NameForge.enRegionSuffixes.count == NameForge.regionSeconds)
        #expect(NameForge.csRegionNouns.count == NameForge.regionSeconds)
        #expect(NameForge.enRegionNouns.count == NameForge.regionSeconds)
        #expect(NameForge.csRegionEpithets.count == NameForge.enRegionEpithets.count)
        #expect(NameForge.regionNameSpace
                == NameForge.regionShapes * NameForge.regionFirsts * NameForge.regionSeconds)
    }

    /// **The complaint this was rewritten for.** Keks, looking at his phone:
    /// *"názvy map jsou skoro stejné, nudné, v okolí mám to samé."* The index
    /// walked in ones and the epithet changed once every `stems × suffixes`
    /// indices, so a quarter of the map was "Far" something.
    @Test("A player's own neighbourhood is not one name with the middle swapped")
    func nearbyNamesDoNotRhyme() {
        for language in GameLanguage.allCases {
            let names = HexCoord.disc(radius: 3).map {
                MapGenerator.name(for: $0, mapSeed: 4242, language: language)
            }
            // The first word is the one the eye reads. Thirty-seven hexes
            // sharing five of them is what "boring" looked like.
            let firstWords = Set(names.map { $0.split(separator: " ").first.map(String.init) ?? $0 })
            #expect(firstWords.count > names.count / 2,
                    "\(language): \(firstWords.count) different first words across \(names.count) hexes")
            // …and the shapes differ: some names are one word, some two, some
            // three. A map where every name has the same rhythm reads as one
            // name however many stems it has.
            let shapes = Set(names.map { $0.split(separator: " ").count })
            #expect(shapes.count >= 2, "\(language): every name has the same shape")
        }
    }

    /// Czech has to stay *Czech*: the adjective bank is deliberately the soft
    /// `-í` kind, which does not inflect for gender, so no pairing can come
    /// out ungrammatical whichever noun it lands on.
    @Test("Czech place names agree with themselves")
    func czechNamesAgree() {
        for adjective in NameForge.csRegionAdjectives {
            #expect(adjective.hasSuffix("í"), "\(adjective) inflects for gender")
        }
    }

    @Test("Nearby hexes never share a name, in either language")
    func regionNamesUnique() {
        for language in GameLanguage.allCases {
            var seen: Set<String> = []
            for coord in HexCoord.disc(radius: 6) {
                let name = MapGenerator.name(for: coord, mapSeed: 99, language: language)
                #expect(!seen.contains(name))
                seen.insert(name)
            }
        }
    }

    @Test("A Czech world charts Czech places; an English one English")
    func worldsSpeakTheirLanguage() throws {
        let reg = try GameDataRegistry.bundled()
        let czech = GameWorldFactory.newGame(registry: reg, seed: 5, language: .cs)
        let english = GameWorldFactory.newGame(registry: reg, seed: 5, language: .en)
        #expect(czech.language == .cs)
        #expect(czech.settlements[0].name == "První světlo")
        #expect(english.settlements[0].name == "First Light")
        let czechHomeland = czech.regions.first { $0.kind == .homeland }
        #expect(czechHomeland?.name == "Domovina")
        // The same hex, two languages, both real names.
        let hex = HexCoord(1, 1)
        #expect(MapGenerator.name(for: hex, mapSeed: 5, language: .cs)
                != MapGenerator.name(for: hex, mapSeed: 5, language: .en))
    }

    @Test("A founded outpost gets a forged name, not a numbered one")
    func outpostNames() throws {
        let reg = try GameDataRegistry.bundled()
        var world = GameWorldFactory.newGame(registry: reg, seed: 12, language: .cs)
        // A fully-explored, unsettled region to found in.
        guard let target = world.regions.firstIndex(where: { $0.kind != .homeland }) else {
            Issue.record("no region to settle")
            return
        }
        world.regions[target].explorationState = .fullyExplored
        world.settlements[0].storage[.materials] = 500
        world.settlements[0].storage[.food] = 500
        world.settlements[0].storage[.influence] = 200   // founding costs influence too

        let after = GameEngine.foundOutpost(world, regionID: world.regions[target].id,
                                            name: "", registry: reg)
        guard after.settlements.count == 2 else {
            Issue.record("outpost was not founded")
            return
        }
        let name = after.settlements[1].name
        #expect(!name.isEmpty)
        #expect(!name.hasPrefix("Outpost"))
    }

    @Test("A world without a language field decodes as Czech-voiced")
    func legacyWorldDecodes() throws {
        let world = WorldState()
        var json = try JSONSerialization.jsonObject(
            with: JSONEncoder().encode(world)) as! [String: Any]
        json.removeValue(forKey: "language")
        let decoded = try JSONDecoder().decode(
            WorldState.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(decoded.language == .cs)
    }
}
