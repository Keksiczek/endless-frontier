import Testing
import Foundation
@testable import EndlessFrontierCore

/// **The fight belongs to the ground it is fought on.**
///
/// Two faults, one root. `SiegeField`'s reaches were written down when a colony
/// was a ring of huts — the line at 0.30, the wall at 0.26 — and the build grid
/// has since grown to cover `SettlementGeometry.span` = 0.70 of the valley, so
/// its edge stands at 0.35. Every raid was therefore fought *inside the town*:
/// the watch ran inward from their work to a crescent among the houses, and the
/// warband walked over the roofs to meet them. Keks: *"všichni tam naběhnou v
/// takovém umělém archu … taky se to kreslí přes aktuální mapu"* — it was not
/// being drawn over the map, it was being fought on top of it.
///
/// And nothing on the field was ever *used*. `CoverField` has stamped every
/// tree, rock, cliff and building into one grid since §11.27, and the fight
/// read it only to tax arrows already in flight. Keks: *"ať je souboj dynamický
/// dle prostředí, kde bojují — stačí vědět, co je okolo, za co se skrýt, vše
/// tam už máme."*
@Suite("The ground a fight is fought on")
struct FightGroundTests {

    private func registry() throws -> GameDataRegistry { try GameDataRegistry.bundled() }

    /// A town spread over its grid: a ring of buildings out to `reach` tiles.
    private func colony(reachTiles: Int) -> ColonyMap {
        var map = ColonyMap(width: 24, height: 24)
        let middle = 12
        for (i, offset) in [-reachTiles, reachTiles].enumerated() {
            for across in [-2, 0, 2] {
                map.placements.append(BuildingPlacement(
                    id: UUID(uuidString: String(format: "C0100000-0000-0000-0000-%012d",
                                                i * 10 + across + 5))!,
                    definitionID: "hut",
                    coord: TileCoord(middle + offset, middle + across),
                    width: 2, height: 2))
            }
        }
        return map
    }

    // MARK: - Where the line forms

    @Test("The line forms outside the town, not in its market place")
    func theLineFormsAtTheEdge() {
        let town = colony(reachTiles: 8)
        let edge = SettlementGeometry.builtReach(in: town, axisX: 1, axisY: 0)
        // Measured against **this town**, not against a constant. The reach is
        // whatever ground the colony has actually covered, so the bar is that
        // it covers the furthest roof and stops inside its own grid — the old
        // version compared it with `SiegeField.wallReach`, which stopped being
        // a fact about anything the moment the span started following the grid.
        let furthest = town.placements
            .map { SiegeField.distance(SettlementGeometry.heart,
                                       SettlementGeometry.canvasPoint(for: $0, in: town)) }
            .max() ?? 0
        #expect(edge > furthest, "the line forms inside the last roof")
        #expect(edge < SettlementGeometry.span(of: town),
                "the line formed off the far side of the valley")
        let field = SiegeField(approach: 0, edge: edge)
        // Every defender's post stands beyond the furthest roof on that side.
        for index in 0..<20 {
            let post = field.defenderPost(index: index, of: 20)
            #expect(SiegeField.distance(field.heart, post) > edge - SiegeField.rankDepth * 3,
                    "a defender formed up inside the town at \(post)")
        }
        // …and the warband still has ground to cross to reach them.
        #expect(field.originAt > field.musterAt + SiegeField.approachRun * 0.9)
    }

    @Test("A colony with nothing built on it falls back to the old constants")
    func anEmptyGridKeepsTheOldGeometry() {
        let empty = ColonyMap(width: 24, height: 24)
        #expect(SettlementGeometry.builtReach(in: empty, axisX: 1, axisY: 0) == 0)
        let field = SiegeField(approach: 0)
        #expect(field.wallAt == SiegeField.wallReach)
    }

    @Test("A town that grew moves the fight out with it")
    func aBiggerTownIsFoughtOverFurtherOut() {
        let small = SettlementGeometry.builtReach(in: colony(reachTiles: 4), axisX: 1, axisY: 0)
        let large = SettlementGeometry.builtReach(in: colony(reachTiles: 10), axisX: 1, axisY: 0)
        #expect(large > small)
        #expect(SiegeField(approach: 0, edge: large).musterAt
                > SiegeField(approach: 0, edge: small).musterAt)
    }

    @Test("Only what stands counts — a building site is stakes in the ground")
    func siteDoesNotMoveTheLine() {
        var town = ColonyMap(width: 24, height: 24)
        town.placements.append(BuildingPlacement(
            id: UUID(uuidString: "C0100000-0000-0000-0000-0000000000AA")!,
            definitionID: "hut", coord: TileCoord(22, 12), width: 2, height: 2,
            underConstruction: true))
        #expect(SettlementGeometry.builtReach(in: town, axisX: 1, axisY: 0) == 0)
    }

    @Test("The record carries the edge, so a replay is the same battle")
    func theRecordRemembersTheGround() throws {
        let log = BattleLog(id: UUID(), tick: 4, attackerName: "Kamenní",
                            defenderName: "Wallside", moments: [], repelled: true,
                            approach: 0, edge: 0.41)
        let data = try JSONEncoder().encode(log)
        let back = try JSONDecoder().decode(BattleLog.self, from: data)
        #expect(back.edge == 0.41)
        // A record from before the town's edge decided anything reads as zero,
        // and the canvas falls back to the constant it was fought on.
        let old = BattleLog(id: UUID(), tick: 4, attackerName: "Kamenní",
                            defenderName: "Wallside", moments: [], repelled: true)
        #expect(old.edge == 0)
    }

    // MARK: - Using what is there

    /// A grid with one building in the middle of the walk.
    private func walledGround() throws -> (CoverField, ColonyMap) {
        let reg = try registry()
        var town = ColonyMap(width: 24, height: 24)
        town.placements.append(BuildingPlacement(
            id: UUID(uuidString: "C0100000-0000-0000-0000-0000000000BB")!,
            definitionID: "hut", coord: TileCoord(12, 11), width: 3, height: 3))
        var map = LocalMap(river: RiverShape(baseY: 0.95, amplitude: 0, phase: 0),
                           nodes: [], pois: [])
        map.trees = []
        map.rocks = []
        map.scenery = []
        return (CoverField(map, colony: town, registry: reg), town)
    }

    @Test("Nobody walks through a wall")
    func aStrideStopsAtTheBuilding() throws {
        let (cover, town) = try walledGround()
        let wall = SettlementGeometry.canvasPoint(
            tileX: 13, tileY: 12, in: town)
        #expect(cover.building(at: wall) != nil, "the fixture put no building there")
        // Somebody walking straight at it from outside.
        let me = Siege.Combatant(
            id: UUID(uuidString: "C0100000-0000-0000-0000-0000000000C1")!,
            side: .raider, at: LocalPoint(x: wall.x - 0.09, y: wall.y), strength: 10)
        let goal = LocalPoint(x: wall.x + 0.09, y: wall.y)
        var here = me
        for _ in 0..<6 {
            here.at = SiegeEngine.groundStride(here, toward: goal, threat: nil, cover: cover)
            #expect(cover.building(at: here.at) == nil,
                    "a fighter walked into the building at \(here.at)")
        }
    }

    @Test("Somebody already inside can still walk out")
    func theWallRuleDoesNotTrapAnybody() throws {
        let (cover, town) = try walledGround()
        let inside = SettlementGeometry.canvasPoint(tileX: 13, tileY: 12, in: town)
        let me = Siege.Combatant(
            id: UUID(uuidString: "C0100000-0000-0000-0000-0000000000C2")!,
            side: .raider, at: inside, strength: 10)
        let out = LocalPoint(x: inside.x + 0.2, y: inside.y)
        let step = SiegeEngine.groundStride(me, toward: out, threat: nil, cover: cover)
        #expect(step != inside, "the raider in the stores is stuck in them")
    }

    @Test("Under fire in the open, a fighter puts something between them")
    func coverIsSomewhereYouGo() throws {
        let reg = try registry()
        var map = LocalMap(river: RiverShape(baseY: 0.95, amplitude: 0, phase: 0),
                           nodes: [], pois: [])
        map.trees = []
        map.rocks = []
        // A boulder just off the line of the walk.
        map.scenery = [SceneryProp(id: 1, kind: .boulder,
                                   position: LocalPoint(x: 0.50, y: 0.545), scale: 1)]
        let cover = CoverField(map, colony: nil, registry: reg)
        let threat = LocalPoint(x: 0.5, y: 0.9)
        let me = Siege.Combatant(
            id: UUID(uuidString: "C0100000-0000-0000-0000-0000000000C3")!,
            side: .raider, at: LocalPoint(x: 0.42, y: 0.5), strength: 10)
        let goal = LocalPoint(x: 0.62, y: 0.5)
        let plain = SiegeField.stride(from: me.at, toward: goal, pace: SiegeEngine.pace)
        let taken = SiegeEngine.groundStride(me, toward: goal, threat: threat, cover: cover)
        #expect(cover.shelter(at: taken, from: threat).fraction
                >= cover.shelter(at: plain, from: threat).fraction,
                "the fighter walked past the boulder in the open")
        // And they still arrive: cover is a lean, not a detour.
        #expect(SiegeField.distance(taken, goal)
                <= SiegeField.distance(plain, goal) + SiegeEngine.coverSlip + 1e-9)
    }

    // MARK: - A blow that lands on somebody

    /// A hit is a thing that happens **to** a body, and until this the body had
    /// no way of knowing: a blade passed through somebody who walked on exactly
    /// as before, and the only sign was a stain appearing on the ground. Keks:
    /// *"radoby se mydlí."*
    @Test("A body remembers the blow it just took, and which way it came from")
    func blowsAreRecordedOnTheBody() throws {
        let registry = try registry()
        var settlement = Settlement(
            id: UUID(uuidString: "F16C0000-0000-0000-0000-000000000001")!,
            name: "Contact", storage: [.food: 400], storageCapacity: .uniform(2000))
        settlement.pawns = (0..<14).map {
            Pawn(id: UUID(uuidString: String(format: "F16C0000-0000-0000-0000-%012d", $0))!,
                 name: "Hand \($0)")
        }
        settlement.siege = Siege(
            id: UUID(uuidString: "F16C0000-0000-0000-0000-0000000000FF")!,
            startTick: 0, openedAt: 0, attackerName: "Kamenní",
            approach: 0, attackers: 18, openingStrength: 50,
            fortification: 6, seed: 0xF16C, line: settlement.pawns.map(\.id))
        // Far enough in that the ranks have met.
        for step in 1...10 {
            settlement = SiegeEngine.advance(settlement, to: step, registry: registry)
        }
        let siege = try #require(settlement.siege)
        let struck = siege.fighters.filter { $0.struckAtStep != nil }
        #expect(!struck.isEmpty, "ten steps of a raid and nobody was ever hit")
        #expect(struck.contains { $0.struckFrom != nil },
                "a blow landed from nowhere")
        // Both sides take them: a fight where only one side is hit is the
        // one-sided raid this project has fixed once already.
        #expect(struck.contains { $0.side == .raider })
    }

    @Test("In contact, nobody wanders off to hide")
    func theMeleeIsNotAGameOfHideAndSeek() throws {
        let (cover, _) = try walledGround()
        let enemy = LocalPoint(x: 0.30, y: 0.5)
        let me = Siege.Combatant(
            id: UUID(uuidString: "C0100000-0000-0000-0000-0000000000C4")!,
            side: .colony, at: LocalPoint(x: 0.31, y: 0.5), strength: 10)
        let step = SiegeEngine.groundStride(me, toward: enemy, threat: enemy,
                                            cover: cover, crowded: false)
        let plain = SiegeField.stride(from: me.at, toward: enemy, pace: SiegeEngine.pace)
        #expect(SiegeField.distance(step, plain) < 1e-9,
                "somebody in contact stepped aside instead of fighting")
    }
}
