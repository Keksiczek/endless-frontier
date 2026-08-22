import Testing
import Foundation
import CoreGraphics
import EndlessFrontierCore
@testable import EndlessFrontier

/// The first tests the app target has ever had. Everything the renderer decides
/// — where a structure is drawn, what a tap can land on, where the camera may
/// travel — was previously verified only by the fact that it compiled.
///
/// These are the pure parts: layout and the camera transform. Nothing here
/// touches the simulation, which is the point — the canvas is presentation
/// only and must never write `WorldState`.

private func settlement(colony: ColonyMap?) -> Settlement {
    var s = Settlement(
        id: UUID(uuidString: "00000000-0000-0000-0000-00000000AAA1")!,
        name: "Test Town",
        buildings: [BuildingInstance(definitionID: "hut", count: 3)]
    )
    s.colony = colony
    return s
}

private func registry() -> GameDataRegistry {
    GameDataRegistry(
        buildings: [
            BuildingDefinition(id: "hut", era: .earlySettlement, name: "Hut",
                               cost: [.materials: 10], housing: 30),
            BuildingDefinition(id: "hall", era: .earlySettlement, name: "Hall",
                               cost: [.materials: 60], production: [.influence: 2],
                               footprint: TileSize(width: 2, height: 2))
        ],
        techs: [], eras: [], biomes: [], events: [], config: .default)
}

private let rect = CGRect(x: 0, y: 0, width: 400, height: 400)

@Suite("The canvas shows the colony you actually built")
struct CanvasLayoutTests {
    /// The colony used to have two truths: the grid the player lays out, and a
    /// decorative ring of glyphs on the canvas that had nothing to do with it.
    @Test("A placed building is drawn where it was placed")
    func gridPositionsAreHonoured() {
        let colony = ColonyMap(width: 12, height: 12, placements: [
            BuildingPlacement(id: UUID(), definitionID: "hut", coord: TileCoord(0, 0)),
            BuildingPlacement(id: UUID(), definitionID: "hut", coord: TileCoord(11, 11))
        ])
        let placed = SettlementRenderer.layout(
            settlement: settlement(colony: colony), registry: registry(), rect: rect)

        #expect(placed.count == 2)
        let topLeft = placed[0].center, bottomRight = placed[1].center
        #expect(topLeft.x < bottomRight.x, "a building in the far corner must not be drawn near the first")
        #expect(topLeft.y < bottomRight.y)
    }

    /// Reported from a real game: buildings stood out in the unexplored dark,
    /// nowhere near the settlement. The grid was stretched across most of the
    /// canvas while the fog only clears a blob around the heart, so tile (0,0)
    /// landed well outside the only ground anyone had seen.
    @Test("Every tile of the grid lands on the settlement, not out in the fog")
    func gridSitsOnTheSettlement() {
        var placements: [BuildingPlacement] = []
        for x in 0..<12 {
            placements.append(BuildingPlacement(id: UUID(), definitionID: "hut",
                                                coord: TileCoord(x, 11 - x)))
        }
        let colony = ColonyMap(width: 12, height: 12, placements: placements)
        let placed = SettlementRenderer.layout(
            settlement: settlement(colony: colony), registry: registry(), rect: rect)

        // The cleared ground is a blob about the heart; nothing may be drawn
        // further from it than the colony's own half-span.
        let heart = SettlementRenderer.point(SettlementRenderer.colonyHeart, in: rect)
        let reach = SettlementRenderer.colonySpan / 2 * rect.width
        for building in placed {
            #expect(rect.contains(building.center), "a structure drawn off-canvas can never be tapped")
            let dx = building.center.x - heart.x, dy = building.center.y - heart.y
            #expect((dx * dx + dy * dy).squareRoot() <= reach * 1.5,
                    "a building must stand in the colony, not out in the unexplored dark")
        }
    }

    @Test("Opposite corners of the grid still read as opposite")
    func gridKeepsItsShape() {
        let colony = ColonyMap(width: 12, height: 12, placements: [
            BuildingPlacement(id: UUID(), definitionID: "hut", coord: TileCoord(0, 0)),
            BuildingPlacement(id: UUID(), definitionID: "hut", coord: TileCoord(11, 11))
        ])
        let placed = SettlementRenderer.layout(
            settlement: settlement(colony: colony), registry: registry(), rect: rect)
        let separation = (placed[1].center.x - placed[0].center.x)
        #expect(separation > 40, "the grid must stay legible, not collapse onto a single point")
    }

    @Test("A colony with no layout yet still shows its buildings")
    func fallsBackToRings() {
        let placed = SettlementRenderer.layout(
            settlement: settlement(colony: nil), registry: registry(), rect: rect)
        #expect(placed.count == 3, "the ring fallback must still draw what the settlement owns")
    }

    @Test("An empty colony draws nothing rather than crashing")
    func emptyIsEmpty() {
        var bare = settlement(colony: nil)
        bare.buildings = []
        let placed = SettlementRenderer.layout(settlement: bare, registry: registry(), rect: rect)
        #expect(placed.isEmpty)
    }

    @Test("A structure carries the id of what it actually is, so a tap can name it")
    func placementsKnowTheirDefinition() {
        let colony = ColonyMap(width: 12, height: 12, placements: [
            BuildingPlacement(id: UUID(), definitionID: "hall", coord: TileCoord(4, 4),
                              width: 2, height: 2)
        ])
        let placed = SettlementRenderer.layout(
            settlement: settlement(colony: colony), registry: registry(), rect: rect)
        #expect(placed.first?.definitionID == "hall")
        #expect(placed.first?.size ?? 0 > 0)
    }

    @Test("A big footprint is drawn bigger")
    func footprintDrivesSize() {
        let reg = registry()
        let small = ColonyMap(width: 12, height: 12, placements: [
            BuildingPlacement(id: UUID(), definitionID: "hut", coord: TileCoord(4, 4))
        ])
        let large = ColonyMap(width: 12, height: 12, placements: [
            BuildingPlacement(id: UUID(), definitionID: "hall", coord: TileCoord(4, 4),
                              width: 2, height: 2)
        ])
        let a = SettlementRenderer.layout(settlement: settlement(colony: small), registry: reg, rect: rect)
        let b = SettlementRenderer.layout(settlement: settlement(colony: large), registry: reg, rect: rect)
        #expect((b.first?.size ?? 0) > (a.first?.size ?? 0))
    }
}

/// Keks: *"ve skladu neleží suroviny."* A store was furnished with two sacks
/// whether the colony was starving or sitting on four thousand — the one
/// building whose whole point is *how much is in it* was the one that could
/// not show it.
@Suite("A store shows what is in it")
struct StoreContentsTests {

    private func granaryRegistry() -> GameDataRegistry {
        GameDataRegistry(
            buildings: [
                BuildingDefinition(id: "granary", era: .earlySettlement, name: "Granary",
                                   cost: [.materials: 30], storage: [.food: 500],
                                   footprint: TileSize(width: 2, height: 2), look: "granary"),
                BuildingDefinition(id: "hut", era: .earlySettlement, name: "Hut",
                                   cost: [.materials: 10], housing: 30)
            ],
            techs: [], eras: [], biomes: [], events: [], config: .default)
    }

    private func town(food: Double, capacity: Double) -> Settlement {
        var s = Settlement(
            id: UUID(uuidString: "00000000-0000-0000-0000-00000000BBB1")!,
            name: "Store Town",
            buildings: [BuildingInstance(definitionID: "granary", count: 1)])
        s.storage = [.food: food, .materials: 0]
        s.storageCapacity = [.food: capacity, .materials: capacity]
        return s
    }

    @Test("A full granary is drawn fuller than an empty one")
    func stockFollowsTheStores() {
        let registry = granaryRegistry()
        let empty = SettlementRenderer.stock(of: "granary", in: town(food: 0, capacity: 1000),
                                             registry: registry)
        let half = SettlementRenderer.stock(of: "granary", in: town(food: 500, capacity: 1000),
                                            registry: registry)
        let full = SettlementRenderer.stock(of: "granary", in: town(food: 1000, capacity: 1000),
                                            registry: registry)
        #expect(empty?.fullness == 0)
        #expect((half?.fullness ?? 0) > 0.4 && (half?.fullness ?? 0) < 0.6)
        #expect(full?.fullness == 1)
        // Grain is sacks, not crates: what a store holds decides what stands
        // on its floor.
        #expect(full?.fitting == .sack)
    }

    @Test("A building that stores nothing shows no stock")
    func onlyStoresAreStocked() {
        #expect(SettlementRenderer.stock(of: "hut", in: town(food: 900, capacity: 1000),
                                         registry: granaryRegistry()) == nil)
    }

    @Test("The floor fills as the store does, and stops when it is packed")
    func slotsGrowWithFullness() {
        let empty = SettlementInterior.storeSlots(fullness: 0, fitting: .sack, seed: 7)
        let some = SettlementInterior.storeSlots(fullness: 0.3, fitting: .sack, seed: 7)
        let packed = SettlementInterior.storeSlots(fullness: 1, fitting: .sack, seed: 7)
        #expect(empty.isEmpty, "a swept store is swept")
        #expect(some.count > 0 && some.count < packed.count)
        #expect(packed.count == SettlementInterior.storeCeiling)
        // …and every sack is inside the room, not through a wall.
        #expect(packed.allSatisfy { abs($0.dx) < 0.5 && abs($0.dy) < 0.5 })
    }

    /// The same store drawn twice must look the same, or a granary shuffles
    /// its own sacks every frame.
    @Test("A store's floor does not shuffle between frames")
    func stockIsStable() {
        let a = SettlementInterior.storeSlots(fullness: 0.7, fitting: .crate, seed: 42)
        let b = SettlementInterior.storeSlots(fullness: 0.7, fitting: .crate, seed: 42)
        #expect(a.map(\.dx) == b.map(\.dx))
        #expect(a.map(\.dy) == b.map(\.dy))
    }
}

@Suite("The camera")
struct CameraTests {
    /// Zoom works by scaling the rect the world maps into rather than by a
    /// `scaleEffect`, because a layer transform resamples the finished bitmap
    /// and turns the hairlines to mush.
    @Test("At full extent the world fills the view exactly")
    func identityCamera() {
        var camera = SettlementRenderer.Camera()
        camera.scale = SettlementRenderer.Camera.minScale
        #expect(SettlementRenderer.worldRect(viewRect: rect, camera: camera) == rect)
    }

    /// The screen opens framed on the **town**, not on the whole valley: at 1
    /// the built span is a little over half a phone's width holding an 18×18
    /// grid, so a one-tile house came out about eleven points across and a
    /// colony read as a scatter of marks.
    @Test("The camera opens on the town and can still pull back to the valley")
    func openingFramesTheColony() {
        let opening = SettlementRenderer.Camera()
        #expect(opening.scale == SettlementRenderer.Camera.opening)
        #expect(opening.scale > SettlementRenderer.Camera.minScale,
                "opening on the whole map is what made the town illegible")
        #expect(opening.scale <= SettlementRenderer.Camera.maxScale)
        // Far enough in that roofs are named the moment you arrive.
        #expect(opening.scale >= 1.6)
        // …and the built span really does end up across most of the screen.
        let world = SettlementRenderer.worldRect(viewRect: rect, camera: opening)
        let town = world.width * SettlementRenderer.colonySpan
        #expect(town > rect.width * 0.75, "the town still does not fill the screen")
    }

    @Test("Zooming in grows the world about the view's centre")
    func zoomIsCentred() {
        var camera = SettlementRenderer.Camera()
        camera.scale = 2
        let world = SettlementRenderer.worldRect(viewRect: rect, camera: camera)

        #expect(world.width == rect.width * 2)
        #expect(world.midX == rect.midX, "zoom must not drift the view sideways")
        #expect(world.midY == rect.midY)
    }

    @Test("Panning moves the world by exactly what was dragged")
    func panTranslates() {
        var camera = SettlementRenderer.Camera()
        camera.scale = 2
        camera.offset = CGSize(width: 30, height: -20)
        let world = SettlementRenderer.worldRect(viewRect: rect, camera: camera)

        #expect(world.midX == rect.midX + 30)
        #expect(world.midY == rect.midY - 20)
    }

    @Test("Zooming in draws the same tile larger, not blurrier")
    func zoomRescalesTheLayout() {
        let colony = ColonyMap(width: 12, height: 12, placements: [
            BuildingPlacement(id: UUID(), definitionID: "hut", coord: TileCoord(0, 0))
        ])
        var camera = SettlementRenderer.Camera()
        camera.scale = 3

        let near = SettlementRenderer.layout(
            settlement: settlement(colony: colony), registry: registry(),
            rect: SettlementRenderer.worldRect(viewRect: rect, camera: camera))
        let far = SettlementRenderer.layout(
            settlement: settlement(colony: colony), registry: registry(), rect: rect)

        #expect((near.first?.size ?? 0) > (far.first?.size ?? 0),
                "the stroke must be re-laid at the new scale rather than magnified after the fact")
    }
}

/// A tap on the fog names the ground the scouts walk to, so the screen→map
/// conversion is the difference between "go north-west" and "go somewhere
/// else entirely". An inverted or unscaled axis here fails silently: the
/// order lands, the beacon draws, and the scouts chart the wrong corner.
@Suite("A tap on the fog names real ground")
struct CanvasCoordinateTests {
    @Test("Screen and map coordinates round-trip", arguments: [
        LocalPoint(x: 0, y: 0), LocalPoint(x: 1, y: 1), LocalPoint(x: 0.5, y: 0.5),
        LocalPoint(x: 0.12, y: 0.87), LocalPoint(x: 0.93, y: 0.04)
    ])
    func roundTrips(p: LocalPoint) {
        let back = SettlementRenderer.normalised(SettlementRenderer.point(p, in: rect), in: rect)
        #expect(abs(back.x - p.x) < 1e-9)
        #expect(abs(back.y - p.y) < 1e-9)
    }

    @Test("The conversion follows the camera, so a tap while zoomed still lands true")
    func honoursCamera() {
        var camera = SettlementRenderer.Camera()
        camera.scale = 2.5
        camera.offset = CGSize(width: 40, height: -25)
        let world = SettlementRenderer.worldRect(viewRect: rect, camera: camera)

        let target = LocalPoint(x: 0.3, y: 0.7)
        let onScreen = SettlementRenderer.point(target, in: world)
        let back = SettlementRenderer.normalised(onScreen, in: world)
        #expect(abs(back.x - target.x) < 1e-9)
        #expect(abs(back.y - target.y) < 1e-9)
    }

    @Test("A tap outside the world clamps onto it rather than off the map")
    func clampsOutOfBounds() {
        let far = SettlementRenderer.normalised(CGPoint(x: -500, y: 9000), in: rect)
        #expect(far.x == 0)
        #expect(far.y == 1)
    }

    @Test("A degenerate rect answers the centre instead of dividing by zero")
    func survivesEmptyRect() {
        let p = SettlementRenderer.normalised(CGPoint(x: 10, y: 10), in: .zero)
        #expect(p == LocalPoint(x: 0.5, y: 0.5))
    }
}

/// The whole point of an expedition is watching it. A colony past the drawing
/// cap must not quietly leave the party out of the frame.
@Suite("A party out is always drawn")
struct VisibleAgentsTests {
    private func crowd(_ count: Int, away: Int) -> Settlement {
        var s = Settlement(id: UUID(uuidString: "00000000-0000-0000-0000-00000000BBB1")!,
                           name: "Boomtown")
        let trip = UUID()
        s.pawns = (0..<count).map { i in
            var p = Pawn(name: "Soul \(i)")
            // The away ones sit at the *end*, exactly where a plain prefix drops them.
            if i >= count - away { p.expeditionID = trip }
            return p
        }
        return s
    }

    @Test("A small colony is drawn entire")
    func underTheCapDrawsEveryone() {
        let s = crowd(10, away: 3)
        #expect(SettlementRenderer.visibleAgents(s).count == 10)
    }

    @Test("Past the cap, the party out is drawn even from the far end of the roster")
    func awayPawnsSurviveTheCap() {
        let count = SettlementRenderer.maxVisibleAgents + 40
        let s = crowd(count, away: 3)
        let drawn = SettlementRenderer.visibleAgents(s)

        #expect(drawn.count == SettlementRenderer.maxVisibleAgents)
        for pawn in s.pawns where pawn.isAway {
            #expect(drawn.contains { $0.id == pawn.id },
                    "the party the player is watching must never be cropped out")
        }
    }

    @Test("With nobody away the cap behaves exactly as before")
    func noPartyKeepsThePlainPrefix() {
        let count = SettlementRenderer.maxVisibleAgents + 10
        let s = crowd(count, away: 0)
        let drawn = SettlementRenderer.visibleAgents(s)
        #expect(drawn.count == SettlementRenderer.maxVisibleAgents)
        #expect(drawn.first?.id == s.pawns.first?.id)
    }
}

/// A battle is drawn from the record, against the clock — so it has to appear
/// on its tick, play through, and then leave the field. Getting the window
/// wrong means a raid either never shows or replays over the colony forever.
@Suite("A raid plays out and then clears")
struct BattlePlaybackTests {
    /// Beats carry the action step they happened on, the way the resolver
    /// stamps them — a fight that runs long occupies more of its tick.
    private func log(tick: Int, repelled: Bool = false) -> BattleLog {
        var r = CombatEngine.BattleRecorder()
        r.record(.volley, step: 0, amount: 3)
        r.record(.charge, step: 0, amount: 20)
        r.record(.clash, step: 4, amount: 12)
        if repelled { r.record(.repelled, step: 6) }
        return r.finish(id: UUID(uuidString: "BBBBBBBB-0000-0000-0000-000000000001")!,
                        tick: tick, attackerName: "Vorenn", defenderName: "Home",
                        repelled: repelled)
    }

    @Test("Nothing has happened at the very start of the battle's tick")
    func nothingBeforeItBegins() {
        let l = log(tick: 10)
        #expect(l.moments(upTo: 0).isEmpty)
    }

    @Test("The battle reveals itself across its tick")
    func revealsProgressively() {
        let l = log(tick: 10)
        let early = l.moments(upTo: 0.2).count
        let late = l.moments(upTo: 0.9).count
        #expect(early < late)
        #expect(late == l.moments.count)
    }

    /// The playback window: on its tick, never before, and never indefinitely
    /// — a finished raid must stop being drawn.
    @Test("The window opens on the tick and closes after it")
    func windowIsBounded() {
        var settlement = Settlement(id: UUID(), name: "Home", regionID: UUID())
        settlement.lastBattle = log(tick: 10)
        func showing(at continuousTick: Double) -> Bool {
            SettlementBattle.live(settlement, continuousTick: continuousTick) != nil
        }
        #expect(!showing(at: 9.99), "not before it happens")
        #expect(showing(at: 10.0))
        #expect(showing(at: 10.2))
        #expect(!showing(at: 11.0), "a battle from last minute is over")
        #expect(!showing(at: 40.0), "and does not haunt the colony")
    }

    /// A repelled raid still has to say so — the beat that reads as "they
    /// broke" is what the ring on the canvas is drawn from.
    @Test("A repelled raid records the moment it broke")
    func repelledIsRecorded() {
        let l = log(tick: 10, repelled: true)
        #expect(l.repelled)
        #expect(l.moments.contains { $0.kind == .repelled })
        #expect(l.moments.last?.kind == .repelled, "it breaks at the end, not the start")
    }
}

/// The cap that dropped the newest roof in town.
///
/// `maxVisibleBuildings = 30` was applied as `placements.prefix(30)` — the
/// first thirty in **build order** — inside `normalizedLayout`, which is also
/// where `AgentMotion` reads homes, beds and work posts. A colony of seventy-
/// nine therefore had forty-nine buildings that were not drawn, could not be
/// tapped, nobody lived in and nobody worked at. The one the player had just
/// paid for was always among them.
@Suite("A big town is all there")
struct RenderBudgetTests {
    private func town(of count: Int) -> ColonyMap {
        var placements: [BuildingPlacement] = []
        for i in 0..<count {
            placements.append(BuildingPlacement(
                id: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012X", i + 1))!,
                definitionID: "hut",
                coord: TileCoord(i % 20, i / 20)))
        }
        return ColonyMap(width: 20, height: 20, placements: placements)
    }

    @Test("Every building the colony owns is in the layout, however many it has")
    func layoutIsComplete() {
        let placed = SettlementRenderer.normalizedLayout(
            settlement: settlement(colony: town(of: 79)), registry: registry())
        #expect(placed.count == 79,
                "the layout feeds AgentMotion — a building missing from it is one nobody can live or work in")
    }

    /// The specific regression: with a build-order cut, the *last* placement is
    /// the first casualty.
    @Test("The building raised most recently is drawn")
    func newestSurvives() {
        let colony = town(of: 79)
        let placed = SettlementRenderer.layout(
            settlement: settlement(colony: colony), registry: registry(), rect: rect,
            viewport: rect)
        let newest = colony.placements.count - 1
        #expect(placed.contains { $0.id == newest },
                "a colonist watches a roof go up and it must not vanish for being late")
    }

    @Test("Nothing off screen is drawn")
    func offScreenIsCulled() {
        let placed = SettlementRenderer.layout(
            settlement: settlement(colony: town(of: 79)), registry: registry(), rect: rect,
            viewport: CGRect(x: 0, y: 0, width: 40, height: 40))
        let full = SettlementRenderer.layout(
            settlement: settlement(colony: town(of: 79)), registry: registry(), rect: rect)
        #expect(placed.count < full.count, "a corner of the view must not pay for the whole town")
        #expect(!placed.isEmpty, "…nor cull away the corner you are looking at")
    }

    /// Culling must not renumber anything: `id` is what a selection holds on to
    /// and what `.building(index:)` reports from a tap.
    @Test("A building keeps its number whatever else is drawn")
    func idsAreStableUnderCulling() {
        let s = settlement(colony: town(of: 79))
        let whole = SettlementRenderer.layout(settlement: s, registry: registry(), rect: rect)
        let corner = SettlementRenderer.layout(
            settlement: s, registry: registry(), rect: rect,
            viewport: CGRect(x: 0, y: 0, width: 120, height: 120))
        for building in corner {
            let same = whole.first { $0.id == building.id }
            #expect(same?.definitionID == building.definitionID)
            #expect(same?.center == building.center, "an id must mean the same roof in both")
        }
    }

    /// Over budget, what survives is what you are looking at — not what was
    /// built first.
    @Test("Over budget, the middle of the view is what stays")
    func budgetKeepsTheMiddle() {
        let many = SettlementRenderer.maxDrawnBuildings + 40
        let placed = SettlementRenderer.layout(
            settlement: settlement(colony: town(of: many)), registry: registry(), rect: rect,
            viewport: rect)
        #expect(placed.count <= SettlementRenderer.maxDrawnBuildings,
                "the frame still has a budget")
        let middle = CGPoint(x: rect.midX, y: rect.midY)
        func distance(_ p: CGPoint) -> CGFloat {
            ((p.x - middle.x) * (p.x - middle.x) + (p.y - middle.y) * (p.y - middle.y)).squareRoot()
        }
        let drawn = Set(placed.map(\.id))
        let all = SettlementRenderer.layout(
            settlement: settlement(colony: town(of: many)), registry: registry(), rect: rect)
        let kept = all.filter { drawn.contains($0.id) }.map { distance($0.center) }
        let dropped = all.filter { !drawn.contains($0.id) }.map { distance($0.center) }
        if let farthestKept = kept.max(), let nearestDropped = dropped.min() {
            #expect(farthestKept <= nearestDropped + 1,
                    "nothing nearer the eye may be dropped for something further away")
        }
    }
}
