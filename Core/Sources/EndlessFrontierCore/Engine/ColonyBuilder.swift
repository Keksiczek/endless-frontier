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
    ///
    /// **Doubled again on 2026-08-14**, at Keks's asking — *"a taky ji prosím
    /// zvěts na dvojnásobek"*. 34×34 is 1156 tiles against 576: twice the
    /// ground, and the linear step (×1.42) is carried by
    /// `SettlementGeometry.span` so a building keeps exactly the size on screen
    /// it had before. What grows is the *valley*, not the tiles in it — room
    /// for the country between the quarters, which is the point of the terrain
    /// having shapes at all.
    public static let defaultWidth = 34
    public static let defaultHeight = 34

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
        // Still nowhere to stand — the valley is taken. What is left is the
        // ground under the wrecks (§11.21 item 3).
        if let map = host.colony, centerFit(def.footprint, in: map) == nil {
            host = clearedOfDerelicts(host)
        }
        // Ground that is not ground. Worked out once here rather than inside
        // every fit: the whole grid is scanned, and the answer is the same for
        // every building raised this tick.
        let wet = drowned(in: host)
        guard let map = host.colony,
              let coord = fit(for: def, in: map, registry: registry, blocked: wet) else {
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
    public static let maxSide = 90

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

    /// Pulls down the wrecks and gives their ground back to the colony.
    ///
    /// A derelict (below `BuildingEngine.derelictBelow`) produces nothing and
    /// shelters nobody — `BuildingEngine.evictDerelict` has already turned
    /// everyone out of it — but it still **holds its tiles**. On a full grid
    /// those tiles are the difference between a farm that grows food and a line
    /// in a ledger, which is the whole of §11.21: `FarmEngine.reconcile` makes
    /// plots out of placements, so ground is production.
    ///
    /// Deliberately the **last** resort, after `grownOutward` has been tried and
    /// the valley has nothing more to give. A derelict can still be mended —
    /// `BuildingEngine.repair` takes anything under `repairBelow`, wrecks
    /// included — so a colony that pulled its ruins down the moment it fancied
    /// building something would be demolishing the houses it was about to fix.
    /// The land has to actually run out first.
    public static func clearedOfDerelicts(_ settlement: Settlement) -> Settlement {
        guard let map = settlement.colony else { return settlement }
        let wrecks = map.placements.filter {
            !$0.underConstruction && $0.condition < BuildingEngine.derelictBelow
        }
        guard !wrecks.isEmpty else { return settlement }
        var s = settlement
        let gone = Set(wrecks.map(\.id))
        // By coordinate, because `remove` looks the placement up by what covers
        // the tile and the array shifts under each removal.
        for wreck in wrecks { s = remove(s, at: wreck.coord) }
        // Anybody still calling a wreck home has no home now. `evictDerelict`
        // normally gets here first; this covers the tick where it has not.
        for i in s.pawns.indices
        where s.pawns[i].homeID.map(gone.contains) == true {
            s.pawns[i].homeID = nil
        }
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
            let def = registry.building(instance.definitionID)
            let size = def?.footprint ?? TileSize()
            for _ in 0..<max(1, instance.count) {
                // A wall laid out with the rest of the founding buildings still
                // belongs on the ring, or a colony restored from a save would
                // have its palisade in the middle of its own square.
                let spot = def.flatMap { fit(for: $0, in: map, registry: registry) }
                guard let coord = spot ?? centerFit(size, in: map) else { return map }
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
    /// **What ground is already taken, asked once instead of per tile.**
    ///
    /// `fits` calls `ColonyMap.placement(at:)`, which walks every placement in
    /// the colony — and the three functions that *search* for a spot call
    /// `fits` on every tile of a 34×34 grid. So laying out a town was
    /// `placements × 1156 × footprint × placements`: measured, `seededLayout`
    /// for a twenty-building camp took **321 ms**, which is ten frames gone on
    /// a drawing. Rule 38's shape exactly — a linear search on the inside of a
    /// loop that looked like a lookup. Nobody noticed because the colony only
    /// ever paid it at the founding and at load.
    ///
    /// One pass over the placements, then every tile question is a set lookup.
    static func occupied(in map: ColonyMap) -> Set<TileCoord> {
        var taken = Set<TileCoord>(minimumCapacity: map.occupiedTileCount)
        for placement in map.placements {
            for tile in placement.footprint { taken.insert(tile) }
        }
        return taken
    }

    /// **The tiles of the build grid that are under water.**
    ///
    /// Nothing about placing a building had ever asked. `isWater` is consulted
    /// in exactly a handful of places in the engine and none of them was this
    /// one, so a coastal colony would happily stand a granary in the sea — the
    /// same fault as *"vše tam normálně chodí"*, one layer up from the walking.
    ///
    /// Deep water only. The shallows are a beach and a ford: people wade them
    /// (`SettlementRoute.acrossShallows`) and a jetty or a mill belongs on
    /// them, so refusing to build there would be a rule nobody asked for.
    /// Returned as tiles to fold into the occupancy set, which is how every
    /// placement path already asks "may I stand here" — no new question to
    /// thread through six functions.
    static func drowned(in settlement: Settlement) -> Set<TileCoord> {
        guard let colony = settlement.colony,
              let depth = PathEngine.waterDepth(settlement) else { return [] }
        var wet = Set<TileCoord>()
        for y in 0..<max(1, colony.height) {
            for x in 0..<max(1, colony.width) {
                let at = SettlementGeometry.canvasPoint(tileX: x, tileY: y, in: colony)
                if depth(at) == .deep { wet.insert(TileCoord(x, y)) }
            }
        }
        return wet
    }

    static func fits(_ size: TileSize, at coord: TileCoord, in map: ColonyMap) -> Bool {
        fits(size, at: coord, in: map, occupied: occupied(in: map))
    }

    static func fits(_ size: TileSize, at coord: TileCoord, in map: ColonyMap,
                     occupied: Set<TileCoord>) -> Bool {
        for dy in 0..<size.height {
            for dx in 0..<size.width {
                let tile = TileCoord(coord.x + dx, coord.y + dy)
                if !map.isInBounds(tile) || occupied.contains(tile) { return false }
                // The green is not building land. `nearestFit` measures from the
                // district centre and the first district centre *is* the heart,
                // so without this the very first building a colony raises goes
                // on the one piece of ground the game treats as a place — the
                // square the midday gathering stands on and visitors walk to.
                // See `SettlementGeometry.greenTiles`.
                if SettlementGeometry.isGreen(tile, in: map) { return false }
            }
        }
        return true
    }

    /// The first top-left (row-major) where a `size` footprint fits, if any.
    static func firstFit(_ size: TileSize, in map: ColonyMap,
                         blocked: Set<TileCoord> = []) -> TileCoord? {
        let taken = occupied(in: map).union(blocked)
        for y in 0..<map.height {
            for x in 0..<map.width {
                let coord = TileCoord(x, y)
                if fits(size, at: coord, in: map, occupied: taken) { return coord }
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
    static func centerFit(_ size: TileSize, in map: ColonyMap,
                          blocked: Set<TileCoord> = []) -> TileCoord? {
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
            if let spot = nearestFit(size, to: centres[index], in: map,
                                     blocked: blocked) { return spot }
        }
        return nil
    }

    // MARK: - Where a given kind of building belongs

    /// Whether this is a thing built to stand **between** the colony and what
    /// is coming at it, rather than a thing that happens to be defended.
    ///
    /// `look == "wall"` is the archetype that describes a shape instead of a
    /// trade, and `defense` is what the data already says it is for. A barracks
    /// has soldiers in it and belongs among the houses; a palisade with houses
    /// on both sides of it is a fence in the middle of a field.
    static func isRampart(_ def: BuildingDefinition) -> Bool {
        def.defense > 0 && def.look == "wall"
    }

    /// The spot this particular building should take — which is not the same
    /// question for every building.
    ///
    /// A wall goes on the **edge**, on the ring the fighting happens at
    /// (`SiegeField.wallReach`), and as far round from the walls that already
    /// stand as it can get, so a colony that keeps building them ends up
    /// enclosed rather than with one very thick side. Everything else fills the
    /// quarters from the middle out, exactly as before.
    static func fit(for def: BuildingDefinition, in map: ColonyMap,
                    registry: GameDataRegistry,
                    /// Ground that is not ground — deep water, chiefly. Folded
                    /// into the occupancy so every path refuses it for free.
                    blocked: Set<TileCoord> = []) -> TileCoord? {
        guard isRampart(def) else {
            return centerFit(def.footprint, in: map, blocked: blocked)
        }
        return perimeterFit(def.footprint, in: map,
                            taken: rampartBearings(in: map, registry: registry),
                            blocked: blocked)
            ?? centerFit(def.footprint, in: map, blocked: blocked)
    }

    /// Which way round the town the walls that already stand are facing.
    static func rampartBearings(in map: ColonyMap, registry: GameDataRegistry) -> [Double] {
        map.placements.compactMap { placement in
            guard let def = registry.building(placement.definitionID), isRampart(def)
            else { return nil }
            return bearingFromHeart(of: placement, in: map)
        }
    }

    /// The bearing of a placement from the middle of the grid, in radians.
    static func bearingFromHeart(of placement: BuildingPlacement, in map: ColonyMap) -> Double {
        let cx = Double(map.width) / 2, cy = Double(map.height) / 2
        let x = Double(placement.coord.x) + Double(placement.width) / 2
        let y = Double(placement.coord.y) + Double(placement.height) / 2
        return atan2(y - cy, x - cx)
    }

    /// How far a wall may sit off the ring before the spot is not worth having.
    static let ringSlack = 3.0
    /// How many tiles of ring error the colony will accept to put a new wall on
    /// an *unwalled* side, per radian of gap. A wall on the open side is worth
    /// more than a neat circle.
    static let ringSpreadPull = 2.5

    /// The free spot nearest the wall ring, preferring the side nothing guards.
    static func perimeterFit(_ size: TileSize, in map: ColonyMap,
                             taken: [Double],
                             blocked: Set<TileCoord> = []) -> TileCoord? {
        guard map.width >= size.width, map.height >= size.height else { return nil }
        let ring = SettlementGeometry.ringRadiusInTiles(atReach: SiegeField.wallReach, in: map)
        let cx = Double(map.width) / 2, cy = Double(map.height) / 2
        var best: (coord: TileCoord, score: Double)?
        let occupiedTiles = occupied(in: map).union(blocked)
        for y in 0...(map.height - size.height) {
            for x in 0...(map.width - size.width) {
                let coord = TileCoord(x, y)
                // Distance first, `fits` second, and the order still matters
                // even now that `fits` is a set lookup rather than a walk over
                // every placement: a ring holds about a tenth of the grid, and
                // the cheap question rules out the other nine tenths (rule 4).
                let mx = Double(x) + Double(size.width) / 2
                let my = Double(y) + Double(size.height) / 2
                let dx = mx - cx, dy = my - cy
                let out = (dx * dx + dy * dy).squareRoot()
                let error = abs(out - ring)
                guard error <= ringSlack,
                      fits(size, at: coord, in: map, occupied: occupiedTiles) else { continue }
                let gap = taken.isEmpty ? .pi : taken
                    .map { abs(angleDifference(atan2(dy, dx), $0)) }
                    .min() ?? .pi
                let score = error - gap * ringSpreadPull
                if score < (best?.score ?? .infinity) { best = (coord, score) }
            }
        }
        return best?.coord
    }

    /// The signed shortest way round from one bearing to another, `-π…π`.
    static func angleDifference(_ a: Double, _ b: Double) -> Double {
        var delta = (a - b).truncatingRemainder(dividingBy: 2 * .pi)
        if delta > .pi { delta -= 2 * .pi }
        if delta < -.pi { delta += 2 * .pi }
        return delta
    }

    /// The free spot closest to a given point on the grid.
    static func nearestFit(_ size: TileSize, to centre: TileCoord, in map: ColonyMap,
                           blocked: Set<TileCoord> = []) -> TileCoord? {
        guard map.width >= size.width, map.height >= size.height else { return nil }
        let cx = Double(centre.x) - Double(size.width - 1) / 2
        let cy = Double(centre.y) - Double(size.height - 1) / 2
        var best: (coord: TileCoord, d2: Double)?
        let taken = occupied(in: map).union(blocked)
        for y in 0...(map.height - size.height) {
            for x in 0...(map.width - size.width) {
                let coord = TileCoord(x, y)
                guard fits(size, at: coord, in: map, occupied: taken) else { continue }
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
