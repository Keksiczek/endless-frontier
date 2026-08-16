import Testing
import Foundation
@testable import EndlessFrontierCore

/// §11.27, the second half — **a wall is a thing that stands somewhere.**
///
/// Cover was built as a field over the ground and then wired into shooting, and
/// all of that was right. What was still a number was the wall itself: every one
/// of the forty-nine buildings covered identically, `nearestFit` put a palisade
/// wherever there happened to be room — which is the middle of town, because
/// that is where a colony builds — and `fortification` was one scalar summed off
/// `defense`, so a rampart on the north side turned aside an attack from the
/// south exactly as well.
///
/// Three facts, and each of them is something a player can point at on the map.
@Suite("Walls stand somewhere")
struct RampartTests {

    private func registry() throws -> GameDataRegistry { try GameDataRegistry.bundled() }

    /// Fixed ids throughout: per-entity randomness is seeded from them
    /// (CLAUDE.md rule 3).
    private func town() -> Settlement {
        var s = Settlement(
            id: UUID(uuidString: "A11A11A1-0000-0000-0000-000000000001")!,
            name: "Hold",
            storage: [.food: 500], storageCapacity: .uniform(1000),
            stats: SettlementStats(defense: 0))
        s.colony = ColonyMap(width: 34, height: 34)
        return s
    }

    private func distanceFromHeart(_ placement: BuildingPlacement, in colony: ColonyMap) -> Double {
        let cx = Double(colony.width) / 2, cy = Double(colony.height) / 2
        let x = Double(placement.coord.x) + Double(placement.width) / 2
        let y = Double(placement.coord.y) + Double(placement.height) / 2
        return ((x - cx) * (x - cx) + (y - cy) * (y - cy)).squareRoot()
    }

    // MARK: - What a building is made of

    @Test("A palisade is timber and the ramparts are stone")
    func aBuildingIsMadeOfWhatItWasBuiltFrom() throws {
        let r = try registry()
        let palisade = try #require(r.building("palisade"))
        let walls = try #require(r.building("stone_walls"))
        #expect(Cover.body(of: palisade, registry: r).substance == .wood)
        #expect(Cover.body(of: walls, registry: r).substance == .stone)

        let timber = Cover.fraction(Cover.body(of: palisade, registry: r).stature,
                                    Cover.body(of: palisade, registry: r).substance)
        let mortared = Cover.fraction(Cover.body(of: walls, registry: r).stature,
                                      Cover.body(of: walls, registry: r).substance)
        #expect(timber < mortared, "a shaft knows the difference")
        #expect(timber > 0.4, "and a palisade is still a palisade")
    }

    /// A wall is something you stand *behind*; a granary is something you stand
    /// *inside*. Height is the axis, and the archetype is where it comes from.
    @Test("A roof covers more than a wall of the same stuff")
    func aRoofIsTotalAndAWallIsNot() throws {
        let r = try registry()
        let palisade = try #require(r.building("palisade"))
        let granary = try #require(r.building("granary"))   // also built of timber
        let wall = Cover.body(of: palisade, registry: r)
        let roof = Cover.body(of: granary, registry: r)
        #expect(wall.substance == roof.substance)
        #expect(wall.stature < roof.stature)
    }

    @Test("A building whose materials say nothing still stands in the way")
    func theFallbackIsAShackAndNotNothing() throws {
        let r = try registry()
        let nameless = BuildingDefinition(id: "nowhere", era: .earlySettlement,
                                          name: "Nowhere", cost: Resources())
        let body = Cover.body(of: nameless, registry: r)
        #expect(Cover.fraction(body.stature, body.substance) > 0.5)
    }

    // MARK: - Where it goes

    @Test("A wall goes on the edge of town, not on the square")
    func aRampartIsBuiltOnTheRing() throws {
        let r = try registry()
        let sited = ColonyBuilder.placeSiteAtFirstFit(
            town(), definitionID: "palisade", registry: r)
        let colony = try #require(sited.settlement.colony)
        let wall = try #require(colony.placements.first)
        let ring = SettlementGeometry.ringRadiusInTiles(
            atReach: SiegeField.wallReach, in: colony)
        let out = distanceFromHeart(wall, in: colony)
        #expect(abs(out - ring) <= ColonyBuilder.ringSlack,
                "a palisade belongs where the fighting happens, \(out) against \(ring)")
    }

    @Test("A granary still goes where the town is")
    func ordinaryBuildingsAreUnmoved() throws {
        let r = try registry()
        let sited = ColonyBuilder.placeSiteAtFirstFit(
            town(), definitionID: "granary", registry: r)
        let colony = try #require(sited.settlement.colony)
        let store = try #require(colony.placements.first)
        let ring = SettlementGeometry.ringRadiusInTiles(
            atReach: SiegeField.wallReach, in: colony)
        #expect(distanceFromHeart(store, in: colony) < ring - ColonyBuilder.ringSlack)
    }

    /// A colony that keeps building walls should end up **enclosed**, not with
    /// one very thick side.
    @Test("The next wall goes round the other side")
    func rampartsSpreadRoundTheRing() throws {
        let r = try registry()
        var s = town()
        for _ in 0..<3 {
            s = ColonyBuilder.placeSiteAtFirstFit(
                s, definitionID: "palisade", registry: r).settlement
        }
        let colony = try #require(s.colony)
        #expect(colony.placements.count == 3)
        let bearings = colony.placements.map {
            ColonyBuilder.bearingFromHeart(of: $0, in: colony)
        }
        for (i, one) in bearings.enumerated() {
            for other in bearings[(i + 1)...] {
                #expect(abs(ColonyBuilder.angleDifference(one, other)) > 0.8,
                        "three walls on the same side are one wall")
            }
        }
    }

    // MARK: - Which way it faces

    @Test("A wall on the far side of town counts for less")
    func fortificationFacesTheAttack() throws {
        let r = try registry()
        var s = town()
        s = ColonyBuilder.placeSiteAtFirstFit(
            s, definitionID: "palisade", registry: r).settlement
        s.colony?.placements[0].underConstruction = false
        let colony = try #require(s.colony)
        let bearing = ColonyBuilder.bearingFromHeart(of: colony.placements[0], in: colony)

        let head_on = SiegeEngine.facingShare(s, registry: r, approach: bearing)
        let behind = SiegeEngine.facingShare(s, registry: r, approach: bearing + .pi)
        #expect(head_on > 0.95, "you are standing behind it")
        #expect(behind < head_on)
        #expect(behind >= SiegeEngine.strayRampartShare,
                "the ditch still runs round the whole town")
    }

    /// A colony whose defence is *people* has no side to be caught on.
    @Test("A colony with no walls is untouched by which way the attack came")
    func garrisonsHaveNoBearing() throws {
        let r = try registry()
        var s = town()
        s = ColonyBuilder.placeSiteAtFirstFit(
            s, definitionID: "barracks", registry: r).settlement
        s.colony?.placements[0].underConstruction = false
        #expect(SiegeEngine.facingShare(s, registry: r, approach: 0) == 1)
        #expect(SiegeEngine.facingShare(s, registry: r, approach: 2) == 1)
    }

    /// The other end of the wear: a wall the last raid knocked about turns less
    /// aside than one that has been kept up.
    @Test("A battered wall turns aside less than a sound one")
    func conditionCountsTowardTheWall() throws {
        let r = try registry()
        var s = town()
        s = ColonyBuilder.placeSiteAtFirstFit(
            s, definitionID: "palisade", registry: r).settlement
        s = ColonyBuilder.placeSiteAtFirstFit(
            s, definitionID: "palisade", registry: r).settlement
        for i in s.colony!.placements.indices { s.colony?.placements[i].underConstruction = false }
        let colony = try #require(s.colony)
        let facing = ColonyBuilder.bearingFromHeart(of: colony.placements[0], in: colony)

        let sound = SiegeEngine.facingShare(s, registry: r, approach: facing)
        s.colony?.placements[0].condition = 0.3
        let battered = SiegeEngine.facingShare(s, registry: r, approach: facing)
        #expect(battered < sound)
    }

    // MARK: - What a fight does to the town

    @Test("A shot that is stopped knows what stopped it")
    func aStoppedShotNamesTheWall() throws {
        let r = try registry()
        var s = town()
        // Clear of the green, which is reserved ground nothing may be built on.
        s = ColonyBuilder.place(s, definitionID: "palisade",
                                at: TileCoord(8, 8), registry: r)
        let colony = try #require(s.colony)
        let wall = try #require(colony.placements.first)
        var map = LocalMap(river: RiverShape(baseY: 0.95, amplitude: 0, phase: 0),
                           nodes: [], pois: [])
        map.scenery = []; map.trees = []; map.rocks = []
        let field = CoverField(map, colony: colony, registry: r)

        let middle = SettlementGeometry.canvasPoint(for: wall, in: colony)
        let shot = field.struck(LocalPoint(x: middle.x - 0.2, y: middle.y),
                                LocalPoint(x: middle.x + 0.2, y: middle.y))
        #expect(shot.fraction > 0.4)
        #expect(shot.building == wall.id, "an arrow in the palisade is the palisade's business")
    }

    @Test("A tree that stops a shot is nobody's to repair")
    func onlyBuildingsAreNamed() {
        var map = LocalMap(river: RiverShape(baseY: 0.95, amplitude: 0, phase: 0),
                           nodes: [], pois: [])
        map.scenery = [SceneryProp(id: 1, kind: .boulder,
                                   position: LocalPoint(x: 0.5, y: 0.5), scale: 1)]
        map.trees = []; map.rocks = []
        let shot = CoverField(map).struck(LocalPoint(x: 0.2, y: 0.5),
                                          LocalPoint(x: 0.8, y: 0.5))
        #expect(shot.fraction > 0.4)
        #expect(shot.building == nil)
    }

    @Test("Chipping wears the named building and nothing else")
    func chipTakesConditionOffOneThing() throws {
        let r = try registry()
        var s = town()
        s = ColonyBuilder.place(s, definitionID: "palisade",
                                at: TileCoord(10, 10), registry: r)
        s = ColonyBuilder.place(s, definitionID: "granary",
                                at: TileCoord(20, 20), registry: r)
        let wall = try #require(s.colony?.placements.first)
        let after = BuildingEngine.chip(s, by: [wall.id: 0.2])
        #expect(after.colony?.placements[0].condition == 0.8)
        #expect(after.colony?.placements[1].condition == 1)
    }

    // MARK: - Standing behind it

    /// The number that makes cover *a place people go* rather than a tax on a
    /// number: a defender with something within a stride of their post puts it
    /// between themselves and the attack.
    @Test("A defender steps behind the boulder at their post")
    func peopleTakeCover() {
        let field = SiegeField(approach: 0)          // they come from the east
        let post = field.out(SiegeField.musterReach)
        // A boulder off the post's shoulder: nothing shelters somebody standing
        // *on* the post, and one step north of it the rock is due east — which
        // is the side they are coming from.
        var map = LocalMap(river: RiverShape(baseY: 0.95, amplitude: 0, phase: 0),
                           nodes: [], pois: [])
        map.scenery = [SceneryProp(id: 1, kind: .boulder,
                                   position: LocalPoint(x: post.x + 0.035,
                                                        y: post.y + 0.055),
                                   scale: 1)]
        map.trees = []; map.rocks = []
        let cover = CoverField(map)

        let took = SiegeEngine.sheltering(post, field: field, cover: cover)
        func onTheAttackSide(_ p: LocalPoint) -> Double {
            cover.shelter(at: p, from: LocalPoint(x: p.x + 0.1, y: p.y)).fraction
        }
        #expect(onTheAttackSide(took) > onTheAttackSide(post),
                "they found the rock and stood behind it")
        #expect(SiegeField.distance(took, post) <= SiegeEngine.coverSearch + 1e-9,
                "and they did not leave the line to do it")
    }

    // MARK: - A building that fights

    /// Fixed ids, and people old enough to hold a line.
    private func garrison(_ s: Settlement, count: Int = 6) -> Settlement {
        var out = s
        for i in 0..<count {
            var p = Pawn(
                id: UUID(uuidString: String(format: "A11A11A1-0000-0000-0000-%012d", i + 10))!,
                name: "Hand \(i)")
            p.age = 25 * 60
            out.pawns.append(p)
        }
        return out
    }

    private func withTower(_ s: Settlement, registry r: GameDataRegistry) -> Settlement {
        var out = ColonyBuilder.place(s, definitionID: "watchtower",
                                      at: TileCoord(22, 12), registry: r)
        for i in out.colony!.placements.indices {
            out.colony?.placements[i].underConstruction = false
        }
        return out
    }

    private func raid(_ s: Settlement, strength: Double = 40,
                      registry r: GameDataRegistry) throws -> Settlement {
        try SiegeEngine.begin(s, attackerStrength: strength, attackerName: "The Ashfolk",
                              fortification: 0, tick: 100, registry: r, seed: 0xBEEF)
    }

    @Test("A watchtower stands on the field, where it was built")
    func aTowerIsOnTheField() throws {
        let r = try registry()
        let s = try raid(withTower(garrison(town()), registry: r), registry: r)
        let siege = try #require(s.siege)
        let tower = try #require(siege.emplacements.first)
        let placement = try #require(s.colony?.placements.first)
        #expect(tower.id == placement.id)
        #expect(tower.at == SettlementGeometry.canvasPoint(for: placement, in: s.colony!))
        #expect(!siege.defenders.contains { $0.id == tower.id },
                "a tower is not a name on the roster")
    }

    /// A warband big enough that it is not wiped out either way — comparing two
    /// raids that both ended at zero says nothing about the tower.
    @Test("A tower shoots at what comes")
    func aTowerCostsTheWarbandSomething() throws {
        let r = try registry()
        let bare = try raid(garrison(town()), strength: 300, registry: r)
        let held = try raid(withTower(garrison(town()), registry: r),
                            strength: 300, registry: r)
        // Read it **mid-fight**: a finished siege is cleared off the settlement
        // by `conclude`, so comparing two raids at the end compares two nils.
        let half = (bare.siege?.openedAt ?? 0) + Siege.stepsTotal / 2

        let afterBare = SiegeEngine.advance(bare, to: half, registry: r)
        let afterHeld = SiegeEngine.advance(held, to: half, registry: r)
        let leftBare = try #require(afterBare.siege?.strength)
        let leftHeld = try #require(afterHeld.siege?.strength)
        #expect(leftHeld < leftBare, "the tower is worth something, \(leftHeld) against \(leftBare)")
    }

    @Test("A tower does not march")
    func aTowerStaysWhereItWasBuilt() throws {
        let r = try registry()
        var s = try raid(withTower(garrison(town()), registry: r), registry: r)
        let before = try #require(s.siege?.emplacements.first?.at)
        s = SiegeEngine.advance(s, to: (s.siege?.openedAt ?? 0) + 8, registry: r)
        #expect(s.siege?.emplacements.first?.at == before)
    }

    @Test("A wreck of a tower shoots nothing")
    func aDerelictTowerIsOutOfTheFight() throws {
        let r = try registry()
        var s = withTower(garrison(town()), registry: r)
        s.colony?.placements[0].condition = 0.1      // below `derelictBelow`
        s = try raid(s, registry: r)
        #expect(s.siege?.emplacements.isEmpty == true)
    }

    @Test("A defender with nothing near them stands where they were sent")
    func openGroundIsOpenGround() {
        let field = SiegeField(approach: 1.2)
        let post = field.out(SiegeField.musterReach)
        var map = LocalMap(river: RiverShape(baseY: 0.95, amplitude: 0, phase: 0),
                           nodes: [], pois: [])
        map.scenery = []; map.trees = []; map.rocks = []
        #expect(SiegeEngine.sheltering(post, field: field, cover: CoverField(map)) == post)
    }

    @Test("Cover-seeking never walks a defender toward the enemy")
    func shelterIsNeverASteoTowardTheAttack() {
        let field = SiegeField(approach: 0)
        let post = field.out(SiegeField.musterReach)
        var map = LocalMap(river: RiverShape(baseY: 0.95, amplitude: 0, phase: 0),
                           nodes: [], pois: [])
        // A wall of boulders on the enemy's side, tempting from every angle.
        map.scenery = (0..<6).map {
            SceneryProp(id: $0, kind: .boulder,
                        position: LocalPoint(x: post.x + 0.02,
                                             y: post.y - 0.05 + Double($0) * 0.02),
                        scale: 1)
        }
        map.trees = []; map.rocks = []
        let took = SiegeEngine.sheltering(post, field: field, cover: CoverField(map))
        #expect(SiegeField.distance(took, field.origin)
                >= SiegeField.distance(post, field.origin) - 1e-9)
    }
}
