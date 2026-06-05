import Testing
@testable import EndlessFrontierCore

@Suite("Content integrity")
struct ContentIntegrityTests {
    private func registry() throws -> GameDataRegistry { try GameDataRegistry.bundled() }

    @Test("Every tech prerequisite references an existing tech")
    func techPrereqsExist() throws {
        let reg = try registry()
        for tech in reg.techs.values {
            for required in tech.requires {
                #expect(reg.tech(required) != nil, "Tech \(tech.id) requires missing \(required)")
            }
        }
    }

    @Test("Every building a tech unlocks exists")
    func techUnlocksExist() throws {
        let reg = try registry()
        for tech in reg.techs.values {
            for effect in tech.effects {
                if case let .unlockBuilding(buildingID) = effect {
                    #expect(reg.building(buildingID) != nil, "Tech \(tech.id) unlocks missing \(buildingID)")
                }
            }
        }
    }

    @Test("Every era-milestone tech exists")
    func eraMilestoneTechsExist() throws {
        let reg = try registry()
        for era in Era.allCases {
            guard let def = reg.eraDefinition(era) else { continue }
            for milestone in def.milestones {
                if case let .techResearched(id) = milestone {
                    #expect(reg.tech(id) != nil, "Era \(era.rawValue) needs missing tech \(id)")
                }
            }
        }
    }

    @Test("Every unlockable building is reachable from some tech (or is early-era)")
    func buildingsReachable() throws {
        let reg = try registry()
        var unlockable: Set<String> = []
        for tech in reg.techs.values {
            for effect in tech.effects {
                if case let .unlockBuilding(id) = effect { unlockable.insert(id) }
            }
        }
        for building in reg.buildings.values where building.era != .earlySettlement {
            #expect(unlockable.contains(building.id), "Building \(building.id) is unreachable (no tech unlocks it)")
        }
    }

    @Test("Content library has grown across eras")
    func contentVolume() throws {
        let reg = try registry()
        #expect(reg.buildings.count >= 20)
        #expect(reg.techs.count >= 14)
        #expect(reg.events.count >= 18)
        // Spans multiple eras.
        let eras = Set(reg.buildings.values.map(\.era))
        #expect(eras.contains(.medieval))
        #expect(eras.contains(.earlyIndustrial))
    }
}

@Suite("Pollution")
struct PollutionTests {
    private func settlement(factories: Int) -> Settlement {
        Settlement(name: "Town", kind: .capital, population: 20,
                   buildings: factories > 0 ? [BuildingInstance(definitionID: "factory", count: factories)] : [],
                   storage: [.food: 500, .energy: 500], storageCapacity: 9999,
                   stats: SettlementStats(morale: 80))
    }

    @Test("Industry accumulates pollution over time")
    func accumulates() throws {
        let reg = try GameDataRegistry.bundled()
        var world = WorldState(settlements: [settlement(factories: 1)])
        world = TickEngine.advance(world, ticks: 60, registry: reg).state
        #expect(world.settlements[0].stats.pollution > 5)
    }

    @Test("Heavy pollution drags morale below a clean settlement's")
    func pollutionHurtsMorale() throws {
        let reg = try GameDataRegistry.bundled()
        var dirty = WorldState(settlements: [settlement(factories: 2)])   // pollution → 60
        var clean = WorldState(settlements: [settlement(factories: 0)])
        dirty = TickEngine.advance(dirty, ticks: 120, registry: reg).state
        clean = TickEngine.advance(clean, ticks: 120, registry: reg).state
        #expect(dirty.settlements[0].stats.morale < clean.settlements[0].stats.morale)
    }
}
