import Testing
import Foundation
import EndlessFrontierCore
@testable import EndlessFrontier

/// The colonists' day used to be a flat fifteen hours of work over three and a
/// half hours of sleep, identical in every season — a convincing-looking round
/// built from numbers nobody had ever added up. These tests add them up.
///
/// Presentation only: nothing here touches `WorldState`, and the simulation
/// still has no clock of its own. What is asserted is that what the player
/// *watches* is a day a person could plausibly live.

private let ticksPerYear = 60

private func registry() -> GameDataRegistry {
    GameDataRegistry(
        buildings: [
            BuildingDefinition(id: "hut", era: .earlySettlement, name: "Hut",
                               cost: [.materials: 10], housing: 30)
        ],
        techs: [], eras: [], biomes: [], events: [], config: .default)
}

private func settlement(pawns: [Pawn]) -> Settlement {
    var s = Settlement(
        id: UUID(uuidString: "00000000-0000-0000-0000-00000000BBB1")!,
        name: "Day Town",
        buildings: [BuildingInstance(definitionID: "hut", count: 3)]
    )
    s.pawns = pawns
    return s
}

private func map() -> LocalMap {
    LocalMap(river: RiverShape(baseY: 0.5, amplitude: 0.05, phase: 0),
             nodes: [], pois: [],
             exploredCells: Set(0..<(LocalMap.gridColumns * LocalMap.gridRows)))
}

/// A tick that lands inside the given season, so the motion derives it back.
private func tick(in season: Season) -> Int {
    season.rawValue * (ticksPerYear / 4) + 1
}

@Suite("The colonists' day is one a person could live")
struct DayShapeTests {

    @Test("At the equinox the day is humane — about ten hours' work, eight of sleep")
    func equinoxIsHumane() {
        let shape = AgentMotion.dayShape(.spring)
        #expect(shape.workingHours > 9 && shape.workingHours < 11)
        #expect(shape.sleepingHours > 7.5 && shape.sleepingHours < 9)
    }

    /// The regression this whole change exists for.
    @Test("Nobody works a fifteen-hour day or sleeps under six hours, in any season",
          arguments: Season.allCases)
    func noSeasonIsInhumane(season: Season) {
        let shape = AgentMotion.dayShape(season)
        #expect(shape.workingHours <= 13.5)
        #expect(shape.sleepingHours >= 5.9)
    }

    @Test("Summer works a longer day than winter, and winter sleeps it off")
    func seasonsTradeLightForSleep() {
        let summer = AgentMotion.dayShape(.summer)
        let winter = AgentMotion.dayShape(.winter)
        #expect(summer.workingHours > winter.workingHours + 3)
        #expect(winter.sleepingHours > summer.sleepingHours + 3)
    }

    @Test("Spring and autumn are the same mean day")
    func equinoxesMatch() {
        #expect(AgentMotion.dayShape(.spring) == AgentMotion.dayShape(.autumn))
    }

    /// A seasonal shift that pushed one boundary past the next would make the
    /// schedule's legs run backwards and the day would come apart.
    @Test("The day's landmarks stay in order all year", arguments: Season.allCases)
    func dayStaysOrdered(season: Season) {
        let s = AgentMotion.dayShape(season)
        #expect(s.wake > 0)
        #expect(s.wake < s.workStart)
        #expect(s.workStart < s.middayStart)
        #expect(s.middayStart < s.middayEnd)
        #expect(s.middayEnd < s.workEnd)
        #expect(s.workEnd < s.bed)
        #expect(s.bed < 1)
    }
}

/// The canvas used to guess where a colonist worked from their trade, and the
/// guess was thin: three building slots for the whole colony, so every scholar
/// went to the same civic house and everyone else stood in the middle of town.
/// The engine has known who is on which building's roster all along.
@Suite("A colonist stands at the building the engine posted them to")
struct WorkplacePostTests {
    private let placementID = UUID(uuidString: "00000000-0000-0000-D0D0-000000000001")!
    private let scholarID = UUID(uuidString: "00000000-0000-0000-D0D0-000000000002")!

    private func registryWithLibrary() -> GameDataRegistry {
        GameDataRegistry(
            buildings: [
                BuildingDefinition(id: "hut", era: .earlySettlement, name: "Hut",
                                   cost: [.materials: 10], housing: 30),
                BuildingDefinition(id: "library", era: .earlySettlement, name: "Library",
                                   cost: [.materials: 30], workers: 2,
                                   production: [.knowledge: 5],
                                   footprint: TileSize(width: 2, height: 2))
            ],
            techs: [], eras: [], biomes: [], events: [], config: .default)
    }

    /// A town whose library sits far off-centre, so "at the library" and
    /// "somewhere near the middle of town" cannot be confused.
    private func town(posted: Bool) -> Settlement {
        var s = Settlement(id: UUID(uuidString: "00000000-0000-0000-D0D0-00000000FFFF")!,
                           name: "Postville",
                           buildings: [BuildingInstance(definitionID: "library", count: 1)])
        s.pawns = [Pawn(id: scholarID, name: "Zora", assignedWork: .research)]
        var colony = ColonyMap(width: 12, height: 12)
        colony.placements = [
            BuildingPlacement(id: placementID, definitionID: "library",
                              coord: TileCoord(0, 0), width: 2, height: 2,
                              assignedPawnIDs: posted ? [scholarID] : [])
        ]
        s.colony = colony
        return s
    }

    private func library(in scene: AgentMotion.Scene) -> SettlementRenderer.NormalizedBuilding {
        scene.layout.first { $0.definitionID == "library" }!
    }

    @Test("A scholar on the library's roster is drawn inside the library")
    func aPostedColonistStandsAtTheirPost() {
        let reg = registryWithLibrary()
        let scene = AgentMotion.Scene(settlement: town(posted: true), registry: reg)
        let pawn = town(posted: true).pawns[0]
        let spot = AgentMotion.workplace(for: pawn, map: emptyMap(), scene: scene,
                                         seed: 12345)
        let lib = library(in: scene)
        #expect(abs(spot.x - lib.center.x) <= lib.footprintW / 2)
        #expect(abs(spot.y - lib.center.y) <= lib.footprintH / 2)
    }

    /// Several scholars on one roster should fill the floor, not stack on a pin.
    ///
    /// They are seated by the roster now, not by a hash of who they are: a hash
    /// spreads people *on average*, which is no help at all in a two-seat room,
    /// where it put both scholars on the same stool about half the time. So the
    /// test asks the real question — two names on the books, two desks — rather
    /// than the old one of whether the same scholar moves when you re-roll a
    /// number they should not depend on.
    @Test("Two colonists posted to the same building stand apart")
    func postedWorkersSpreadAcrossTheFloor() {
        let reg = registryWithLibrary()
        let town = crowdedLibraryTown()
        let scene = AgentMotion.Scene(settlement: town, registry: reg)
        let a = AgentMotion.workplace(for: town.pawns[0], map: emptyMap(), scene: scene, seed: 11)
        let b = AgentMotion.workplace(for: town.pawns[1], map: emptyMap(), scene: scene, seed: 11)
        #expect(a != b)
    }

    /// The same colonist stands at the same desk from one frame to the next —
    /// a seat is a seat, not something re-rolled every time you look.
    @Test("A posted colonist keeps their own station")
    func aStationIsStable() {
        let reg = registryWithLibrary()
        let town = crowdedLibraryTown()
        let scene = AgentMotion.Scene(settlement: town, registry: reg)
        let first = AgentMotion.workplace(for: town.pawns[0], map: emptyMap(), scene: scene, seed: 3)
        let again = AgentMotion.workplace(for: town.pawns[0], map: emptyMap(), scene: scene, seed: 77)
        #expect(first == again)
    }

    /// Two scholars, both on the library's books.
    private func crowdedLibraryTown() -> Settlement {
        let second = UUID(uuidString: "00000000-0000-0000-D0D0-000000000003")!
        var s = town(posted: true)
        s.pawns.append(Pawn(id: second, name: "Milo", assignedWork: .research))
        s.colony?.placements[0].assignedPawnIDs = [scholarID, second]
        return s
    }

    /// Without a post the colonist still has to end up somewhere sensible —
    /// a building kept for their trade, not the middle of the green.
    @Test("An unposted scholar still finds a library")
    func unpostedFallsBackToTheTrade() {
        let reg = registryWithLibrary()
        let scene = AgentMotion.Scene(settlement: town(posted: false), registry: reg)
        let pawn = town(posted: false).pawns[0]
        let spot = AgentMotion.workplace(for: pawn, map: emptyMap(), scene: scene, seed: 7)
        let lib = library(in: scene)
        #expect(abs(spot.x - lib.center.x) <= lib.footprintW / 2)
        #expect(abs(spot.y - lib.center.y) <= lib.footprintH / 2)
    }

    private func emptyMap() -> LocalMap {
        LocalMap(river: RiverShape(baseY: 0.5, amplitude: 0.05, phase: 0),
                 nodes: [], pois: [],
                 exploredCells: Set(0..<(LocalMap.gridColumns * LocalMap.gridRows)))
    }
}

@Suite("The day the canvas actually plays")
struct DayScheduleTests {

    /// Samples a colonist's whole day and reports what fraction of it was spent
    /// in each activity — the day as the player would watch it.
    private func dayProfile(pawn: Pawn, tickOfYear: Int) -> [String: Double] {
        let reg = registry()
        let scene = AgentMotion.Scene(settlement: settlement(pawns: [pawn]),
                                      registry: reg,
                                      continuousTick: Double(tickOfYear))
        let samples = 480
        var counts: [String: Double] = [:]
        for i in 0..<samples {
            let time = Double(i) / Double(samples) * AgentMotion.dayLength
            let pose = AgentMotion.pose(for: pawn, map: map(), scene: scene,
                                        time: time, ticksPerYear: ticksPerYear)
            counts["\(pose.activity)", default: 0] += 1 / Double(samples)
        }
        return counts
    }

    @Test("An adult's watched day is mostly sleep and work, not a single endless shift")
    func adultDayIsBalanced() {
        let pawn = Pawn(id: UUID(uuidString: "00000000-0000-0000-0000-00000000CCC1")!,
                        name: "Vesna", assignedWork: .farming)
        let profile = dayProfile(pawn: pawn, tickOfYear: tick(in: .spring))
        let sleeping = profile["sleeping"] ?? 0
        let working = profile["working"] ?? 0
        // Sampled through `pose`, so the walk at the head of each leg eats a
        // little from both — the point is the balance, not the exact minute.
        #expect(sleeping > 0.28)
        #expect(working > 0.30 && working < 0.45)
        #expect(sleeping + working > 0.65)
        // And the midday gathering has to actually happen, not be spent walking.
        #expect((profile["socializing"] ?? 0) > 0.05)
    }

    @Test("Children sleep longer than the adults who work")
    func childrenSleepLonger() {
        let adult = Pawn(id: UUID(uuidString: "00000000-0000-0000-0000-00000000CCC2")!,
                         name: "Radek", assignedWork: .farming)
        let child = Pawn(id: UUID(uuidString: "00000000-0000-0000-0000-00000000CCC3")!,
                         name: "Mila", assignedWork: .idle,
                         age: 6 * ticksPerYear)
        let adultSleep = dayProfile(pawn: adult, tickOfYear: tick(in: .spring))["sleeping"] ?? 0
        let childSleep = dayProfile(pawn: child, tickOfYear: tick(in: .spring))["sleeping"] ?? 0
        #expect(childSleep > adultSleep)
    }

    @Test("A child never works")
    func childrenDoNotWork() {
        let child = Pawn(id: UUID(uuidString: "00000000-0000-0000-0000-00000000CCC4")!,
                         name: "Bela", assignedWork: .farming,
                         age: 5 * ticksPerYear)
        let profile = dayProfile(pawn: child, tickOfYear: tick(in: .spring))
        #expect(profile["working"] == nil)
        #expect((profile["playing"] ?? 0) > 0.3)
    }

    @Test("The sick keep to their bed all day")
    func theSickRest() {
        let sick = Pawn(id: UUID(uuidString: "00000000-0000-0000-0000-00000000CCC5")!,
                        name: "Jarek", assignedWork: .farming, health: 20)
        let profile = dayProfile(pawn: sick, tickOfYear: tick(in: .spring))
        #expect((profile["resting"] ?? 0) > 0.99)
    }

    /// The seasonal day has to survive the trip through `pose` — deriving the
    /// season from the scene's tick is where this could silently do nothing.
    @Test("A summer day on the canvas really is more work than a winter one")
    func seasonReachesTheCanvas() {
        let pawn = Pawn(id: UUID(uuidString: "00000000-0000-0000-0000-00000000CCC6")!,
                        name: "Hana", assignedWork: .farming)
        let summer = dayProfile(pawn: pawn, tickOfYear: tick(in: .summer))["working"] ?? 0
        let winter = dayProfile(pawn: pawn, tickOfYear: tick(in: .winter))["working"] ?? 0
        #expect(summer > winter)
    }
}

/// **Two clocks on one screen, and they disagreed by thirty times.**
///
/// A colonist living the drawn day walked at `AgentMotion.walkSpeed` — map
/// widths per five-minute day. A colonist carrying a load or going for a meal
/// walked at a rate written per *world tick*, and a world tick is two real
/// minutes. Converted to the one unit that matters here — map widths per real
/// second of somebody watching — the first is `0.015` and the second was
/// `0.0008`. Both were "moving". Only one of them was moving fast enough for
/// the eye to call it motion, and the other was most of the working town.
///
/// This is the guard on that. It does not pin either number; it pins that they
/// are answers to the same question.
@Suite("The two walking clocks agree")
struct WalkPaceAgreementTests {

    /// Map widths a second, as the player sees it.
    private var drawnDay: Double { AgentMotion.walkSpeed / AgentMotion.dayLength }
    private var simulated: Double {
        let secondsPerStep =
            WorldConfig.default.realSecondsPerTick / Double(WorldClock.actionStepsPerTick)
        return WalkPace.perStep / secondsPerStep
    }

    @Test("A hauler and a colonist walking to work cross the screen at comparable speeds")
    func neitherWalkerIsScenery() {
        let ratio = max(drawnDay, simulated) / min(drawnDay, simulated)
        #expect(ratio < 5, """
            one walker covers \(String(format: "%.4f", drawnDay)) map widths a second \
            and the other \(String(format: "%.4f", simulated)) — \
            \(String(format: "%.0f", ratio))× apart, which is one of them reading as furniture
            """)
    }

    /// The floor under it: a figure that moves less than a thousandth of the map
    /// a second is, at any sane zoom, a figure standing still.
    @Test("Simulated walking is above the eye's threshold for motion")
    func aWalkerVisiblyMoves() {
        #expect(simulated > 0.002,
                "\(String(format: "%.4f", simulated)) map widths a second is not visible motion")
    }
}
