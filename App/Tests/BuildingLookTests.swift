import Testing
import Foundation
import EndlessFrontierCore
@testable import EndlessFrontier

/// Forty-seven buildings used to be drawn as eight shapes, and the mapping was
/// blunt enough that a library, a school, a bank, a market and an observatory
/// were all the same Greek temple, while a spaceport was a workshop shed. These
/// tests run the real `buildings.json` through the mapping, because the point of
/// the change is what the *shipping content* looks like, not a fixture.
@Suite("A colony's skyline has more than one idea in it")
struct BuildingLookTests {

    private func allBuildings() throws -> [BuildingDefinition] {
        Array(try GameDataRegistry.bundled().buildings.values)
    }

    private func glyph(_ id: String, _ defs: [BuildingDefinition])
        -> SettlementRenderer.BuildingGlyph? {
        defs.first { $0.id == id }.map(SettlementRenderer.glyph(for:))
    }

    @Test("Buildings that are nothing alike are not drawn alike")
    func landmarkBuildingsGetTheirOwnShape() throws {
        let defs = try allBuildings()
        #expect(glyph("hut", defs) == .house)
        #expect(glyph("apartment_block", defs) == .house)
        #expect(glyph("library", defs) == .hall)
        #expect(glyph("university", defs) == .hall)
        #expect(glyph("market", defs) == .market)
        #expect(glyph("bank", defs) == .market)
        #expect(glyph("watchtower", defs) == .tower)
        #expect(glyph("solar_array", defs) == .array)
        #expect(glyph("wind_farm", defs) == .array)
        #expect(glyph("spaceport", defs) == .pad)
        // A craftsman's shed and a heavy plant are not the same building.
        #expect(glyph("workshop", defs) == .workshop)
        #expect(glyph("factory", defs) == .plant)
        // The three the numbers cannot tell apart — all just "make materials".
        #expect(glyph("lumberyard", defs) == .mill)
        #expect(glyph("quarry", defs) == .mine)
    }

    /// `look` is content, so a typo must not silently pick a shape.
    @Test("Every look named in the content is one the renderer knows")
    func statedLooksAllResolve() throws {
        for def in try allBuildings() {
            guard let look = def.look else { continue }
            #expect(SettlementRenderer.glyph(named: look) != nil,
                    "\(def.id) asks for an unknown look '\(look)'")
        }
    }

    /// The regression that matters: no single silhouette may swallow the town.
    @Test("No one silhouette carries most of the colony")
    func silhouettesAreSpread() throws {
        let defs = try allBuildings()
        var counts: [String: Int] = [:]
        for def in defs { counts["\(SettlementRenderer.glyph(for: def))", default: 0] += 1 }
        let biggest = counts.values.max() ?? 0
        // Before this change the temple alone took 12 of 47.
        #expect(counts.count >= 8, "only \(counts.count) distinct silhouettes: \(counts)")
        #expect(Double(biggest) / Double(defs.count) < 0.35,
                "one silhouette takes \(biggest) of \(defs.count): \(counts)")
    }

    /// A fusion-era colony should not still be built out of wattle and thatch.
    @Test("What a building is made of follows the era that raised it")
    func materialsAgeWithTheEra() {
        let early = SettlementStructures.materials(.earlySettlement)
        let industrial = SettlementStructures.materials(.earlyIndustrial)
        let future = SettlementStructures.materials(.nearFuture)
        #expect(early.wall != industrial.wall)
        #expect(industrial.wall != future.wall)
        // Timber is warm (more red than blue); panel and glass are cool.
        #expect(early.wall.0 > early.wall.2)
        #expect(future.wall.2 > future.wall.0)
    }
}
