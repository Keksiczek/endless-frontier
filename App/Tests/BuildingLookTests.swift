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
        #expect(glyph("apartment_block", defs) == .tenement)
        #expect(glyph("library", defs) == .hall)
        #expect(glyph("university", defs) == .hall)
        #expect(glyph("market", defs) == .market)
        #expect(glyph("bank", defs) == .vault)
        #expect(glyph("palisade", defs) == .wall)
        #expect(glyph("watchtower", defs) == .tower)
        #expect(glyph("solar_array", defs) == .array)
        #expect(glyph("wind_farm", defs) == .turbine)
        #expect(glyph("spaceport", defs) == .pad)
        // A craftsman's shed and a heavy plant are not the same building.
        #expect(glyph("workshop", defs) == .workshop)
        #expect(glyph("factory", defs) == .plant)
        // The three the numbers cannot tell apart — all just "make materials".
        #expect(glyph("lumberyard", defs) == .sawmill)
        #expect(glyph("quarry", defs) == .mine)
        #expect(glyph("foundry", defs) == .forge)
        // …and the four that all just "produce food or store it".
        #expect(glyph("farm_basic", defs) == .farm)
        #expect(glyph("granary", defs) == .granary)
        #expect(glyph("well", defs) == .well)
        #expect(glyph("hunters_lodge", defs) == .lodge)
    }

    /// The point of the whole pass: nothing may be left to the *derivation*.
    ///
    /// Thirty-six of the forty-seven stated no `look` at all, and the numbers
    /// cannot tell a farm from a granary from a well — so thirteen buildings
    /// came out as the same lecture hall and nine as the same smoking block.
    /// Deriving is the fallback for content that has not caught up; shipping
    /// content should never need it.
    @Test("Every shipped building says what it looks like")
    func nothingIsLeftToTheDerivation() throws {
        let unnamed = try allBuildings().filter { $0.look == nil }.map(\.id).sorted()
        #expect(unnamed.isEmpty, "these fall back to a guessed shape: \(unnamed)")
    }

    /// The bug a screenshot found and the tests had not: `size` came from
    /// `0.021 × max(w, h)`, which has nothing to do with the lot, so a 3×2 was
    /// drawn twice as wide as its own plot and the colony read as a heap of
    /// overlapping glyphs.
    @Test("A building is drawn small enough to stand on its own lot",
          arguments: [(1, 1), (2, 1), (2, 2), (3, 2), (3, 3)])
    func structuresFitTheirFootprint(w: Int, h: Int) {
        let reg = GameDataRegistry(
            buildings: [BuildingDefinition(id: "b", era: .earlySettlement, name: "B",
                                           cost: [.materials: 10],
                                           production: [.materials: 3],
                                           footprint: TileSize(width: w, height: h))],
            techs: [], eras: [], biomes: [], events: [], config: .default)
        var s = Settlement(id: UUID(uuidString: "00000000-0000-0000-F17F-000000000001")!,
                           name: "Fitville",
                           buildings: [BuildingInstance(definitionID: "b", count: 1)])
        var colony = ColonyMap(width: 12, height: 12)
        colony.placements = [BuildingPlacement(
            id: UUID(uuidString: "00000000-0000-0000-F17F-000000000002")!,
            definitionID: "b", coord: TileCoord(4, 4), width: w, height: h)]
        s.colony = colony
        let b = SettlementRenderer.normalizedLayout(settlement: s, registry: reg)[0]
        // A body runs roughly 2.2 × size across; it must not spill its parcel.
        #expect(b.size * 2.2 <= b.footprintW + 1e-9)
        #expect(b.size * 2.2 <= b.footprintH + 1e-9)
    }

    /// Two buildings on neighbouring tiles must not grow into each other.
    @Test("Neighbouring buildings do not overlap")
    func neighboursKeepTheirDistance() {
        let reg = GameDataRegistry(
            buildings: [BuildingDefinition(id: "b", era: .earlySettlement, name: "B",
                                           cost: [.materials: 10],
                                           production: [.materials: 3])],
            techs: [], eras: [], biomes: [], events: [], config: .default)
        var s = Settlement(id: UUID(uuidString: "00000000-0000-0000-F17F-000000000003")!,
                           name: "Rowville",
                           buildings: [BuildingInstance(definitionID: "b", count: 2)])
        var colony = ColonyMap(width: 12, height: 12)
        colony.placements = [
            BuildingPlacement(id: UUID(uuidString: "00000000-0000-0000-F17F-000000000004")!,
                              definitionID: "b", coord: TileCoord(4, 4)),
            BuildingPlacement(id: UUID(uuidString: "00000000-0000-0000-F17F-000000000005")!,
                              definitionID: "b", coord: TileCoord(5, 4))
        ]
        s.colony = colony
        let layout = SettlementRenderer.normalizedLayout(settlement: s, registry: reg)
        let gap = abs(layout[1].center.x - layout[0].center.x)
        // Bodies run 2.2 × size across, so half-widths must not exceed the gap.
        // They are sized to fill the lot exactly, so this touches rather than
        // clears — the epsilon is float slack, not headroom.
        #expect(gap >= (layout[0].size + layout[1].size) * 1.1 - 1e-9)
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
        #expect(counts.count >= 24, "only \(counts.count) distinct silhouettes: \(counts)")
        #expect(Double(biggest) / Double(defs.count) < 0.12,
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
