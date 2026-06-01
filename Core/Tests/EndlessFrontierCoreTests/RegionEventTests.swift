import Testing
@testable import EndlessFrontierCore

@Suite("Dynamic region events")
struct RegionEventTests {
    private func world() -> WorldState {
        let regions = [
            Region(name: "Home", coord: .origin, kind: .homeland, biomeID: "plains",
                   hazardLevel: 1, explorationState: .fullyExplored),
            Region(name: "Field", coord: HexCoord(1, 0), kind: .wilderness, biomeID: "plains",
                   hazardLevel: 2, explorationState: .fullyExplored),
            Region(name: "Yonder", coord: HexCoord(2, 0), kind: .wilderness, biomeID: "forest",
                   hazardLevel: 5, explorationState: .unknown)
        ]
        return WorldState(regions: regions)
    }

    @Test("region_hazard raises the hazard of the targeted region")
    func hazardDelta() {
        let after = EffectApplier.apply(
            [.regionHazardDelta(delta: 3, selector: .highestHazard)],
            to: world(), registry: Fixtures.registry()
        )
        #expect(after.regions.first { $0.name == "Yonder" }?.hazardLevel == 8)
    }

    @Test("region_kind transforms an unknown region into ruins")
    func kindChange() {
        let after = EffectApplier.apply(
            [.regionKindChange(kind: .ruins, selector: .anyUnknown)],
            to: world(), registry: Fixtures.registry()
        )
        #expect(after.regions.first { $0.name == "Yonder" }?.kind == .ruins)
    }

    @Test("any_explored skips the homeland")
    func anyExploredSkipsHomeland() {
        let index = EffectApplier.regionIndex(in: world(), selector: .anyExplored)
        #expect(index != nil)
        #expect(world().regions[index!].kind != .homeland)
    }

    @Test("Bundled dynamic region events decode")
    func bundledRegionEvents() throws {
        let ids = Set(try GameDataRegistry.bundled().events.map(\.id))
        #expect(ids.contains("creeping_blight"))
        #expect(ids.contains("ruins_surface"))
    }
}
