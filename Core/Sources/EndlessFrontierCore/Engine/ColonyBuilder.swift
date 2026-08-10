import Foundation

/// Player-driven construction and colonist assignment on a settlement's
/// in-settlement grid (`ColonyMap`). Pure and deterministic: every function
/// takes a settlement and returns a new one, leaving the input unchanged on an
/// invalid action (matching the rest of the engine's style).
///
/// Building here keeps the spatial layout and the count-based
/// `Settlement.buildings` ledger in sync, so the resource loop — which still
/// reads `buildings` — stays the single source of truth for the economy.
public enum ColonyBuilder {
    /// The build grid a new colony gets.
    ///
    /// 12×12 was sized when every building stood on a single tile. Now that 43
    /// of 47 own real ground — up to 3×3, nine tiles apiece — a late colony ran
    /// out of room long before it ran out of things to build: a dozen 3×3 works
    /// alone would fill three quarters of the old grid. 18×18 is 2.25× the
    /// ground for the same span on screen, so lots stay legible while a mature
    /// town actually fits.
    ///
    /// Existing saves keep whatever grid they were created with — `ColonyMap`
    /// stores its own width and height — so this only widens new colonies.
    /// Widened again to 24×24 when every footprint grew a tile in each
    /// direction (a hut is 2×2 now, a works 4×4): 576 tiles, so a mature town
    /// of fifty buildings still uses only about two thirds of its ground and
    /// there is room left for squares and gardens. The span on screen is
    /// unchanged, so a tile is smaller and a *building* — which is now two to
    /// four tiles across instead of one to three — comes out larger.
    public static let defaultWidth = 24
    public static let defaultHeight = 24

    /// Ensures the settlement has a colony grid, creating an empty one if needed.
    public static func ensureMap(
        _ settlement: Settlement,
        width: Int = defaultWidth,
        height: Int = defaultHeight
    ) -> Settlement {
        guard settlement.colony == nil else { return settlement }
        var s = settlement
        s.colony = ColonyMap(width: width, height: height)
        return s
    }

    /// `true` if `definitionID` can be placed with its top-left at `coord` right
    /// now: its whole footprint is in bounds, every tile is free, and the
    /// building exists. A `nil` map is treated as an empty default-sized grid,
    /// since `place` will create one.
    public static func canPlace(
        _ settlement: Settlement,
        definitionID: String,
        at coord: TileCoord,
        registry: GameDataRegistry
    ) -> Bool {
        guard let def = registry.building(definitionID) else { return false }
        let map = settlement.colony ?? ColonyMap(width: defaultWidth, height: defaultHeight)
        return fits(def.footprint, at: coord, in: map)
            && isClearOfRock(def.footprint, at: coord, in: map, settlement: settlement)
    }

    /// Whether a footprint's ground is free of standing rock.
    ///
    /// A mountain is generated clear of the colony's founding ground, but a
    /// colony grows outward and can reach a hillside — and when it does, the
    /// answer is to *mine the block first*, not to build a granary inside a
    /// cliff. This is the one place a `StoneField` reaches into the build
    /// rules, and it is the whole of what "solid" means.
    static func isClearOfRock(
        _ size: TileSize, at coord: TileCoord, in map: ColonyMap, settlement: Settlement
    ) -> Bool {
        guard let stone = settlement.localMap?.stone, stone.usesBlocks, !stone.isEmpty else {
            return true
        }
        for dx in 0..<max(1, size.width) {
            for dy in 0..<max(1, size.height) {
                let tile = TileCoord(coord.x + dx, coord.y + dy)
                let placement = BuildingPlacement(
                    id: UUID(), definitionID: "", coord: tile, width: 1, height: 1)
                if stone.blocks(SettlementGeometry.canvasPoint(for: placement, in: map)) {
                    return false
                }
            }
        }
        return true
    }

    /// Places a building (with its footprint) on the grid with its top-left at
    /// `coord` and increments the matching `BuildingInstance` count. Creates the
    /// grid if the settlement has none. Unchanged if the action is invalid.
    public static func place(
        _ settlement: Settlement,
        definitionID: String,
        at coord: TileCoord,
        registry: GameDataRegistry
    ) -> Settlement {
        guard let def = registry.building(definitionID) else { return settlement }
        var s = ensureMap(settlement)
        guard var map = s.colony, fits(def.footprint, at: coord, in: map),
              isClearOfRock(def.footprint, at: coord, in: map, settlement: s) else {
            return settlement
        }

        let placement = BuildingPlacement(
            id: placementID(definitionID, coord),
            definitionID: definitionID,
            coord: coord,
            width: def.footprint.width,
            height: def.footprint.height
        )
        map.placements.append(placement)
        s.colony = map

        // Keep the count-based economy ledger in step with the layout.
        if let i = s.buildings.firstIndex(where: { $0.definitionID == definitionID }) {
            s.buildings[i].count += 1
        } else {
            // Derived, not random: this runs inside the tick path, and two
            // identical worlds must come out with identical ids.
            s.buildings.append(BuildingInstance.founding(
                definitionID, at: s.id, slot: s.buildings.count))
        }
        return s
    }

    /// Places a building as a construction *site*: its tiles are reserved and
    /// the scaffolding is drawn, but the economy ledger is untouched until
    /// `ConstructionEngine` finishes the roof. Unchanged if it doesn't fit.
    public static func placeSite(
        _ settlement: Settlement,
        definitionID: String,
        at coord: TileCoord,
        registry: GameDataRegistry
    ) -> Settlement {
        guard let def = registry.building(definitionID) else { return settlement }
        var s = ensureMap(settlement)
        guard var map = s.colony, fits(def.footprint, at: coord, in: map),
              isClearOfRock(def.footprint, at: coord, in: map, settlement: s) else {
            return settlement
        }
        map.placements.append(BuildingPlacement(
            id: placementID(definitionID, coord),
            definitionID: definitionID,
            coord: coord,
            width: def.footprint.width,
            height: def.footprint.height,
            underConstruction: true
        ))
        s.colony = map
        return s
    }

    /// Places a construction site on the first free tile that fits (row by
    /// row) — how a quick-build from the construction panel lands on a colony
    /// that has a layout. Returns the settlement unchanged (and a nil id)
    /// when the grid is full.
    public static func placeSiteAtFirstFit(
        _ settlement: Settlement,
        definitionID: String,
        registry: GameDataRegistry
    ) -> (settlement: Settlement, placementID: UUID?) {
        guard let def = registry.building(definitionID) else { return (settlement, nil) }
        // A colony that has run out of ground takes in more of the valley.
        var host = settlement
        if let map = host.colony, centerFit(def.footprint, in: map) == nil {
            host = grownOutward(host)
        }
        guard let map = host.colony,
              let coord = centerFit(def.footprint, in: map) else {
            return (settlement, nil)
        }
        let sited = placeSite(host, definitionID: definitionID, at: coord, registry: registry)
        return (sited, sited.colony?.placement(at: coord)?.id)
    }

    /// How much ground a colony takes in when it runs out, and how far it may go.
    ///
    /// **This is the ceiling the game sat under.** The grid was a fixed 24×24,
    /// and when nothing fitted `GameEngine.build` enqueued the building anyway
    /// with `placementID: nil` — so it went into the ledger and owned no ground.
    /// For most buildings that is merely a lie the canvas cannot draw; for a
    /// *farm* it is fatal, because `FarmEngine.reconcile` makes plots out of
    /// placements. Measured, seed 4242: buildings 79 → 107 while plots stood at
    /// 38 and `plotsWanted` climbed to 49, materials pinned at the cap, and the
    /// colony starved with a hundred and twenty people in it.
    ///
    /// A colony is a place in a valley, not a fenced yard. When it needs room it
    /// takes another ring of the ground it is standing on.
    public static let growthStep = 4
    /// Where it stops. 64×64 is four thousand tiles — a town of six hundred
    /// buildings — and past that the tiles are too small to be worth drawing.
    public static let maxSide = 64

    /// Takes in another ring of ground, keeping the town where it stands.
    ///
    /// Grown **outward on every side** rather than at the right and bottom
    /// edges, so the settlement stays in the middle of its own map: everything
    /// on the grid is shifted by half the step, which is why `growthStep` is
    /// even. `SettlementGeometry` maps tiles to canvas through the colony's own
    /// width and height, so the drawing follows for free — the tiles get
    /// smaller and the town keeps its shape.
    public static func grownOutward(_ settlement: Settlement) -> Settlement {
        guard var map = settlement.colony,
              map.width < maxSide || map.height < maxSide else { return settlement }
        let step = growthStep
        let shift = step / 2
        var s = settlement
        map.width = min(maxSide, map.width + step)
        map.height = min(maxSide, map.height + step)
        for index in map.placements.indices {
            map.placements[index].coord = TileCoord(
                map.placements[index].coord.x + shift,
                map.placements[index].coord.y + shift)
        }
        map.zones = map.zones.map {
            ZoneTile(coord: TileCoord($0.coord.x + shift, $0.coord.y + shift), kind: $0.kind)
        }
        s.colony = map
        return s
    }

    /// Removes whatever building stands on `coord`, decrements the ledger, and
    /// frees any colonists that were assigned to it. Unchanged if the tile is
    /// empty.
    public static func remove(_ settlement: Settlement, at coord: TileCoord) -> Settlement {
        var s = settlement
        guard var map = s.colony,
              let index = map.placements.firstIndex(where: { $0.covers(coord) }) else {
            return settlement
        }
        let removed = map.placements[index]
        map.placements.remove(at: index)
        s.colony = map

        // Free the colonists who worked here.
        for pawnID in removed.assignedPawnIDs {
            if let pi = s.pawns.firstIndex(where: { $0.id == pawnID }) {
                s.pawns[pi].assignedWork = .idle
            }
        }

        // Decrement the ledger, dropping the entry when it hits zero. A site
        // still under scaffolding was never counted, so there is nothing to
        // take back out.
        if !removed.underConstruction,
           let bi = s.buildings.firstIndex(where: { $0.definitionID == removed.definitionID }) {
            s.buildings[bi].count -= 1
            if s.buildings[bi].count <= 0 {
                s.buildings.remove(at: bi)
            }
        }
        return s
    }

    /// Assigns a colonist to staff a placed building, setting their work to the
    /// kind that building employs. Respects the building's worker cap and moves
    /// the colonist off any building they were previously on. Unchanged if the
    /// pawn, placement or building can't be found, or the building is full.
    public static func assign(
        _ settlement: Settlement,
        pawnID: UUID,
        to placementID: UUID,
        registry: GameDataRegistry
    ) -> Settlement {
        var s = settlement
        guard var map = s.colony,
              let pIdx = map.placements.firstIndex(where: { $0.id == placementID }),
              !map.placements[pIdx].underConstruction,   // a site can't be staffed
              s.pawns.contains(where: { $0.id == pawnID }),
              let def = registry.building(map.placements[pIdx].definitionID) else {
            return settlement
        }

        // Respect the worker cap (workers == 0 means no staffing, e.g. housing).
        let alreadyHere = map.placements[pIdx].assignedPawnIDs.filter { $0 != pawnID }.count
        guard def.workers > 0, alreadyHere < def.workers else { return settlement }

        // Move the pawn off every building, then onto this one.
        for i in map.placements.indices {
            map.placements[i].assignedPawnIDs.removeAll { $0 == pawnID }
        }
        map.placements[pIdx].assignedPawnIDs.append(pawnID)
        s.colony = map

        if let pi = s.pawns.firstIndex(where: { $0.id == pawnID }) {
            s.pawns[pi].assignedWork = workKind(for: def)
        }
        return s
    }

    /// Removes a colonist from any building and sets them idle.
    public static func unassign(_ settlement: Settlement, pawnID: UUID) -> Settlement {
        var s = settlement
        guard var map = s.colony else { return settlement }
        for i in map.placements.indices {
            map.placements[i].assignedPawnIDs.removeAll { $0 == pawnID }
        }
        s.colony = map
        if let pi = s.pawns.firstIndex(where: { $0.id == pawnID }) {
            s.pawns[pi].assignedWork = .idle
        }
        return s
    }

    /// The kind of work a building employs, derived from the resource it
    /// produces most. Buildings that produce nothing a colonist can work toward
    /// (e.g. pure energy, housing or defence) map to `.idle`.
    public static func workKind(for def: BuildingDefinition) -> WorkKind {
        // A building may name its trade outright — the only way to know that a
        // hospital is where the healer works, since it produces nothing the
        // ledger counts.
        if let stated = def.work { return stated }
        var best: WorkKind = .idle
        var bestAmount = 0.0
        for kind in WorkKind.allCases {
            guard let resource = kind.resource else { continue }
            let amount = def.production[resource]
            if amount > bestAmount {
                bestAmount = amount
                best = kind
            }
        }
        return best
    }

    /// Lays a settlement's existing buildings out on a fresh grid, scanning for
    /// the first spot each footprint fits (row by row). Used to seed the layout
    /// for a new game *without* touching the economy ledger — the caller already
    /// holds the matching `buildings`, so this only mirrors them spatially.
    public static func seededLayout(
        for buildings: [BuildingInstance],
        registry: GameDataRegistry,
        width: Int = defaultWidth,
        height: Int = defaultHeight
    ) -> ColonyMap {
        var map = ColonyMap(width: width, height: height)
        for instance in buildings {
            let size = registry.building(instance.definitionID)?.footprint ?? TileSize()
            for _ in 0..<max(1, instance.count) {
                guard let coord = centerFit(size, in: map) else { return map }
                map.placements.append(
                    BuildingPlacement(
                        id: placementID(instance.definitionID, coord),
                        definitionID: instance.definitionID,
                        coord: coord,
                        width: size.width,
                        height: size.height
                    )
                )
            }
        }
        return map
    }

    // MARK: - Zones (amenity designations)

    /// Paints a zone of `kind` onto `coord` (replacing any existing zone there).
    /// Creates the grid if the settlement has none. Zones are independent of
    /// buildings.
    public static func paintZone(
        _ settlement: Settlement,
        at coord: TileCoord,
        kind: ZoneKind
    ) -> Settlement {
        var s = ensureMap(settlement)
        guard var map = s.colony, map.isInBounds(coord) else { return settlement }
        map.zones.removeAll { $0.coord == coord }
        map.zones.append(ZoneTile(coord: coord, kind: kind))
        s.colony = map
        return s
    }

    /// Clears any zone painted on `coord`.
    public static func eraseZone(_ settlement: Settlement, at coord: TileCoord) -> Settlement {
        var s = settlement
        guard var map = s.colony else { return settlement }
        map.zones.removeAll { $0.coord == coord }
        s.colony = map
        return s
    }

    // MARK: - Footprint placement helpers

    /// `true` if a `size` footprint with its top-left at `coord` fits in `map`
    /// (all tiles in bounds and unoccupied).
    static func fits(_ size: TileSize, at coord: TileCoord, in map: ColonyMap) -> Bool {
        for dy in 0..<size.height {
            for dx in 0..<size.width {
                let tile = TileCoord(coord.x + dx, coord.y + dy)
                if !map.isInBounds(tile) || map.placement(at: tile) != nil { return false }
            }
        }
        return true
    }

    /// The first top-left (row-major) where a `size` footprint fits, if any.
    static func firstFit(_ size: TileSize, in map: ColonyMap) -> TileCoord? {
        for y in 0..<map.height {
            for x in 0..<map.width {
                let coord = TileCoord(x, y)
                if fits(size, at: coord, in: map) { return coord }
            }
        }
        return nil
    }

    /// The fit closest to the **middle** of the grid. Row-major scanning
    /// stacked every seeded and quick-built structure into the top-left
    /// corner — which the canvas maps to the fog's edge, leaving the cleared
    /// ground around the settlement heart conspicuously empty. Growth now
    /// spirals outward from the centre, the way a town actually grows.
    /// How many buildings one district holds before the colony opens another.
    ///
    /// Everything used to be packed as near the middle as it would go, so a
    /// town of sixty was one dense knot with fields all round it: you could not
    /// tell the quarter you worked in from the quarter you slept in, because
    /// there were no quarters. A district is what makes a town a *place* — a
    /// second little square with its own houses around it, and a walk between
    /// them.
    public static let buildingsPerDistrict = 9

    /// Where the colony's districts sit on the grid, heart first.
    ///
    /// They open as the town needs them and always in the same order, so a
    /// colony's shape is a consequence of its history rather than a shuffle.
    /// The ring is deliberately tight — these are quarters of one town, not
    /// separate villages — and every centre stays inside the grid.
    public static func districtCentres(in map: ColonyMap, count: Int) -> [TileCoord] {
        let heart = TileCoord(map.width / 2, map.height / 2)
        guard count > 1 else { return [heart] }
        var centres = [heart]
        let reach = Double(min(map.width, map.height)) * 0.28
        for i in 0..<(count - 1) {
            let angle = Double(i) / Double(max(1, count - 1)) * 2 * .pi
            let x = Int((Double(heart.x) + cos(angle) * reach).rounded())
            let y = Int((Double(heart.y) + sin(angle) * reach).rounded())
            centres.append(TileCoord(min(map.width - 1, max(0, x)),
                                     min(map.height - 1, max(0, y))))
        }
        return centres
    }

    /// The free spot a new building should take.
    ///
    /// Not simply "nearest the middle" any more: the colony fills its heart,
    /// then opens a second quarter and fills that, and so on — so a town grows
    /// outward into recognisable neighbourhoods instead of packing tighter and
    /// tighter around one point.
    static func centerFit(_ size: TileSize, in map: ColonyMap) -> TileCoord? {
        let districts = max(1, (map.placements.count / buildingsPerDistrict) + 1)
        let centres = districtCentres(in: map, count: districts)

        // How busy each quarter already is, so the newest one gets the work.
        var occupancy = [Int](repeating: 0, count: centres.count)
        for placement in map.placements {
            let nearest = centres.indices.min {
                squaredDistance(placement.coord, centres[$0])
                    < squaredDistance(placement.coord, centres[$1])
            } ?? 0
            occupancy[nearest] += 1
        }
        let order = centres.indices.sorted {
            occupancy[$0] == occupancy[$1] ? $0 < $1 : occupancy[$0] < occupancy[$1]
        }

        // Nearest free ground to the emptiest quarter's centre; if that quarter
        // is full, the next one, and so on — a colony never fails to build
        // merely because its newest square filled up.
        for index in order {
            if let spot = nearestFit(size, to: centres[index], in: map) { return spot }
        }
        return nil
    }

    /// The free spot closest to a given point on the grid.
    static func nearestFit(_ size: TileSize, to centre: TileCoord, in map: ColonyMap) -> TileCoord? {
        guard map.width >= size.width, map.height >= size.height else { return nil }
        let cx = Double(centre.x) - Double(size.width - 1) / 2
        let cy = Double(centre.y) - Double(size.height - 1) / 2
        var best: (coord: TileCoord, d2: Double)?
        for y in 0...(map.height - size.height) {
            for x in 0...(map.width - size.width) {
                let coord = TileCoord(x, y)
                guard fits(size, at: coord, in: map) else { continue }
                let dx = Double(x) - cx, dy = Double(y) - cy
                let d2 = dx * dx + dy * dy
                if d2 < (best?.d2 ?? .infinity) { best = (coord, d2) }
            }
        }
        return best?.coord
    }

    static func squaredDistance(_ a: TileCoord, _ b: TileCoord) -> Double {
        let dx = Double(a.x - b.x), dy = Double(a.y - b.y)
        return dx * dx + dy * dy
    }

    /// Best-effort: assigns a colonist to the first placed building that employs
    /// their current work and still has room. Leaves them as-is if none fits.
    public static func autoAssign(
        _ settlement: Settlement,
        pawnID: UUID,
        registry: GameDataRegistry
    ) -> Settlement {
        guard let map = settlement.colony,
              let pawn = settlement.pawns.first(where: { $0.id == pawnID }) else {
            return settlement
        }
        for placement in map.placements {
            guard let def = registry.building(placement.definitionID) else { continue }
            if workKind(for: def) == pawn.assignedWork,
               def.workers > 0,
               placement.assignedPawnIDs.count < def.workers {
                return assign(settlement, pawnID: pawnID, to: placement.id, registry: registry)
            }
        }
        return settlement
    }

    // MARK: - Deterministic placement ids

    /// A stable id for a placement, hashed from its definition and tile so the
    /// same build action always produces the same id (FNV-1a style, matching
    /// the seeding used elsewhere in the engine).
    private static func placementID(_ definitionID: String, _ coord: TileCoord) -> UUID {
        var h: UInt64 = 0x9E37_79B9_7F4A_7C15
        for byte in definitionID.utf8 {
            h = (h ^ UInt64(byte)) &* 0x0100_0000_01B3
        }
        h = (h ^ UInt64(bitPattern: Int64(coord.x))) &* 0x0100_0000_01B3
        h = (h ^ UInt64(bitPattern: Int64(coord.y))) &* 0x0100_0000_01B3
        var rng = SeededRNG(seed: h ^ (h >> 29))
        return rng.nextUUID()
    }
}
