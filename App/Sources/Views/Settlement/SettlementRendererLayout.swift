import SwiftUI
import EndlessFrontierCore

/// **Where a building stands** — the glyph it is drawn as, the lot it owns,
/// and the arithmetic that turns a `ColonyMap` into points on a canvas.
///
/// This is the half of the renderer that is not drawing at all: `AgentMotion`
/// reads `normalizedLayout` for homes, beds and work posts, so a change here
/// moves the colonists as well as the roofs (rule 63).
extension SettlementRenderer {
    /// What a structure looks like on the map. Derived from what the building
    /// actually *does*, so new content picks up a sensible silhouette for free.
    /// The silhouettes a structure can be drawn as.
    ///
    /// Eight of these used to carry all forty-seven buildings, which is why a
    /// spaceport and a workshop were the same shed and every library, school,
    /// bank and market was the same Greek temple. A colony reads as a place
    /// when its skyline has more than one idea in it.
    /// What a building looks like.
    ///
    /// Twenty-nine of these for forty-seven buildings, because thirteen was not
    /// enough to tell them apart: thirty-six of the forty-seven stated no
    /// `look` at all and had their shape *derived* from their numbers, which
    /// put thirteen of them on `hall` and nine on `plant`. A farm, a granary
    /// and a well were the same barrel. Every building names its own archetype
    /// now, and no archetype carries more than four.
    /// The building shapes the canvas can draw.
    ///
    /// A `String` raw value because the content names them: `fittings.json`
    /// says which rooms a piece of furniture belongs in, and `glyph(named:)`
    /// below already reads the same spellings out of `buildings.json`. One
    /// vocabulary, written down once.
    enum BuildingGlyph: String, CaseIterable {
        // Where people live
        case house      // hut, longhouse
        case tenement   // apartment block, arcology — stacked storeys
        // Ground and wood
        case farm       // furrows and a low barn
        case lodge      // the hunters', with the racks outside
        case sawmill    // a timber stack and a saw frame
        case mine       // a cut into the rock
        case well       // a ring of stones and a windlass
        // Fire and craft
        case workshop   // light craft
        case forge      // bloomery, foundry — the hearth that glows
        case cookhouse  // ovens and a standing fire — where the harvest is eaten
        case plant      // heavy industry, the smoking block
        case tanks      // refinery, chemical works
        case rail       // a shed, a water tower and track
        // Knowing
        case hall       // library, school, university
        case lab        // the clean block, glass and rooftop plant
        case dish       // observatory, orbital array
        // Trade and rule
        case market     // stalls under awnings
        case vault      // the bank: a squat stone strongbox
        case temple     // civic monument
        case clinic     // hospital, clinic
        case granary    // food and stores
        case aqueduct   // a run of arches
        // Holding the line
        case wall       // a run of palisade or masonry
        case tower      // the watchtower
        case barracks   // a long low block under a banner
        // Power
        case mill       // the wheel and the sails
        case generator  // a machine that makes power
        case turbine    // the tall three-bladed kind
        case array      // fields of panels
        case dam        // a curved wall holding water
        case pad        // spaceport
    }

    /// The archetype names `buildings.json` may state outright via `look`.
    static func glyph(named name: String) -> BuildingGlyph? {
        switch name {
        case "house": return .house
        case "tenement": return .tenement
        case "farm": return .farm
        case "lodge": return .lodge
        case "sawmill": return .sawmill
        case "mine": return .mine
        case "well": return .well
        case "workshop": return .workshop
        case "forge": return .forge
        case "plant": return .plant
        case "tanks": return .tanks
        case "rail": return .rail
        case "hall": return .hall
        case "lab": return .lab
        case "dish": return .dish
        case "market": return .market
        case "vault": return .vault
        case "temple": return .temple
        case "clinic": return .clinic
        case "granary": return .granary
        case "cookhouse": return .cookhouse
        case "aqueduct": return .aqueduct
        case "wall": return .wall
        case "tower": return .tower
        case "barracks": return .barracks
        case "mill": return .mill
        case "generator": return .generator
        case "turbine": return .turbine
        case "array": return .array
        case "dam": return .dam
        case "pad": return .pad
        default: return nil
        }
    }

    /// What a building looks like: what the content says, else what the numbers
    /// imply. Order matters — the strongest signal is asked first.
    ///
    /// Deriving alone was never enough. Every materials producer answers
    /// `workKind` the same way, so lumberyard, quarry, workshop, foundry and
    /// factory were all drawn as one waterwheel; `look` is how the handful the
    /// numbers cannot separate say what they are.
    static func glyph(for def: BuildingDefinition) -> BuildingGlyph {
        if let stated = def.look, let g = glyph(named: stated) { return g }
        if def.housing > 0 { return .house }
        if def.defense > 0 { return .tower }
        // Anything that smokes is heavy industry, whatever else it does.
        if def.pollution >= 10 { return .plant }
        // The furthest-out civic works read as nothing else.
        if def.era == .nearFuture, def.production[.influence] > 0 { return .pad }
        if def.production[.energy] > 0 {
            // Panels and turbines lie flat over the ground; everything earlier
            // that makes power is a machine in a shed.
            return def.era == .nearFuture ? .array : .generator
        }
        if def.production[.knowledge] > 0 { return .hall }
        if def.production[.influence] > 0 { return .market }
        if def.production[.food] > 0 || def.storage.total > 0 { return .granary }
        return .workshop
    }

    /// One structure in the settlement, in normalised (0…1) space — the shared
    /// truth for the renderer, the tap targets *and* the colonists' motion, so
    /// a builder walks to the same scaffolding you see.
    struct NormalizedBuilding: Identifiable {
        let id: Int              // stable within a layout pass
        let definitionID: String
        let name: String
        let glyph: BuildingGlyph
        let center: LocalPoint
        /// Glyph size as a fraction of the canvas's short side.
        let size: Double
        /// The ground the building actually covers, as fractions of the short
        /// side — width×height of its footprint, so a 2×2 stands on a 2×2 plot
        /// instead of hovering as a single glyph.
        let footprintW: Double
        let footprintH: Double
        let underConstruction: Bool
        /// Construction completion 0…1 (1 when built).
        let progress: Double
        /// A stable per-building seed for cosmetic variation (tone, size).
        let seed: UInt64
        /// **How this kind of building is put together** — see
        /// `StructureVariant`. The seed above varies one instance from the
        /// next; this varies one *kind* from another that shares its glyph.
        let variant: StructureVariant
        /// The era that raised it — timber and thatch give way to brick, then
        /// to panel and glass, so a data centre is not a wattle hut in a hat.
        let era: Era
        /// **What this one is built of**, off its own `materialCost`. The era
        /// says what the age can make; this says what *this* building is, so a
        /// timber granary and a brick one in the same year are not the same
        /// drawing. Same field the cover model and the weathering read.
        let fabric: Cover.Substance
        /// How many storeys it has. `floors` has been in the data since the
        /// beginning and was read by exactly one thing (`HouseholdEngine`, to
        /// count beds); a tenement was a tenement because its `look` said so.
        let floors: Int
        /// The colonists the *simulation* has posted here
        /// (`BuildingPlacement.assignedPawnIDs`). The canvas stands them on
        /// this lot rather than guessing a workplace from their trade, so what
        /// the player watches is the roster the engine actually keeps.
        let assignedPawnIDs: [UUID]
        /// The placement this came from, where there is one. How a colonist's
        /// `homeID` finds the house it names.
        let placementID: UUID?
        /// How sound the building is, 0…1.
        let condition: Double
        /// How full the colony's store of the thing **this** building keeps
        /// is, 0…1, and what those goods look like on a floor. Nil for a
        /// building that stores nothing. Derived from `Settlement.storage`
        /// against `storageCapacity` — the drawing reads the simulation and
        /// never the other way round.
        var stock: (fullness: Double, fitting: SettlementInterior.Fitting)?
        /// …and *what* is in it: the colony's own stockpile, biggest heap
        /// first. Only stores get any.
        var goods: [(kind: SettlementInterior.Goods, count: Int)] = []
    }

    /// The same structure mapped to pixels for one frame.
    struct PlacedBuilding: Identifiable {
        let id: Int
        let definitionID: String
        let name: String
        let glyph: BuildingGlyph
        let center: CGPoint
        let size: CGFloat
        /// The building's footprint on the ground, in pixels.
        let footprint: CGSize
        let underConstruction: Bool
        let progress: Double
        let seed: UInt64
        /// See `NormalizedBuilding.variant`.
        let variant: StructureVariant
        let era: Era
        /// What it is built of, and how tall it stands. See `NormalizedBuilding`.
        let fabric: Cover.Substance
        let floors: Int
        /// How many colonists the engine posted here — the room is furnished
        /// with a station apiece, and they are drawn standing at them.
        let workers: Int
        /// …and how many live here, for a dwelling: a bed apiece.
        let residents: Int
        /// How sound it is, 0…1 — cracks, then a hole in the roof, then a ruin.
        let condition: Double
        /// How full the colony's store of the thing **this** building keeps
        /// is, 0…1, and what those goods look like on a floor. Nil for a
        /// building that stores nothing. Derived from `Settlement.storage`
        /// against `storageCapacity` — the drawing reads the simulation and
        /// never the other way round.
        var stock: (fullness: Double, fitting: SettlementInterior.Fitting)?
        /// …and *what* is in it: the colony's own stockpile, biggest heap
        /// first. Only stores get any.
        var goods: [(kind: SettlementInterior.Goods, count: Int)] = []
    }

    /// A stable per-building seed for cosmetic variation — from a placement's
    /// id where there is one, else its kind and ring slot.
    static func buildingSeed(_ uuid: UUID) -> UInt64 {
        let u = uuid.uuid
        return UInt64(u.0) << 56 | UInt64(u.1) << 48 | UInt64(u.2) << 40 | UInt64(u.3) << 32
             | UInt64(u.4) << 24 | UInt64(u.5) << 16 | UInt64(u.6) << 8 | UInt64(u.7)
    }
    static func buildingSeed(_ id: String, _ index: Int) -> UInt64 {
        var h: UInt64 = 0xCBF2_9CE4_8422_2325
        for byte in id.utf8 { h = (h ^ UInt64(byte)) &* 0x0100_0000_01B3 }
        return h ^ UInt64(bitPattern: Int64(index))
    }

    /// Where the settlement's heart sits on the canvas — the fog is cleared
    /// around here, so this is the only part of the world anyone has actually
    /// seen.
    static let colonyHeart = LocalPoint(x: 0.5, y: 0.52)
    /// How wide a slice of the canvas the whole build grid covers.
    ///
    /// Widened from 0.42 once buildings gained insides: an 18×18 grid squeezed
    /// into 0.42 gave each tile about nine pixels at rest, which is a room you
    /// cannot see into and a town whose people are drawn on top of one another.
    /// Widened again to 0.58 when the complaint was that the town was not
    /// legible at a glance. Two things move together for that: this, and
    /// `Camera.opening` — a wider span gives each building more ground and the
    /// opening zoom puts that ground across the screen.
    ///
    /// **Taken from `SettlementGeometry.span`, not copied from it.**
    ///
    /// This was a literal `0.58` with a comment saying it must agree with the
    /// Core, and a test guarding that it did. The comment and the test were
    /// both doing a job that one `=` does better: widening the valley on
    /// 2026-08-14 changed the Core's number and left this one behind, which
    /// draws every building in a different place from where colonists are sent
    /// to work in it. A number that must equal another number should *be* that
    /// number.
    /// **The ground *this* colony's grid covers**, asked of the Core.
    ///
    /// Was a constant — one slice of the valley for a camp of twelve and for a
    /// city of two hundred alike — which is why a grown town's tiles shrank
    /// until it was a knot with the same thin rim of country round it. The span
    /// follows the grid now (`SettlementGeometry.span(of:)`), and this is the
    /// same number rather than a copy of it (rule 35).
    static func colonySpan(_ colony: ColonyMap) -> Double {
        SettlementGeometry.span(of: colony)
    }

    /// The founding valley, for the handful of places that have no colony in
    /// hand — a preview of a region nobody has settled yet.
    static let colonySpan: Double = SettlementGeometry.baseSpan

    /// Maps a grid tile to the point on the canvas it sits at, centred on the
    /// heart so the built colony always lands inside the cleared ground.
    static func canvasPoint(for coord: TileCoord, in colony: ColonyMap) -> LocalPoint {
        let fx = (Double(coord.x) + 0.5) / Double(max(1, colony.width)) - 0.5
        let fy = (Double(coord.y) + 0.5) / Double(max(1, colony.height)) - 0.5
        let span = colonySpan(colony)
        return LocalPoint(
            x: colonyHeart.x + fx * span,
            y: colonyHeart.y + fy * span)
    }

    /// The inverse of `canvasPoint`: which build tile a point on the canvas
    /// falls on, or nil when it lies off the colony's ground. This is what lets
    /// the player place a building by pointing at the settlement itself rather
    /// than at an abstract grid on another screen.
    static func tile(at p: LocalPoint, in colony: ColonyMap) -> TileCoord? {
        let span = colonySpan(colony)
        guard colony.width > 0, colony.height > 0, span > 0 else { return nil }
        let fx = (p.x - colonyHeart.x) / span + 0.5
        let fy = (p.y - colonyHeart.y) / span + 0.5
        guard fx >= 0, fx < 1, fy >= 0, fy < 1 else { return nil }
        return TileCoord(min(colony.width - 1, Int(fx * Double(colony.width))),
                         min(colony.height - 1, Int(fy * Double(colony.height))))
    }

    /// Where the settlement's structures stand, in normalised space. The grid
    /// is the truth wherever one exists; the rings are only the fallback for a
    /// colony that hasn't been laid out yet.
    static func normalizedLayout(
        settlement: Settlement, registry: GameDataRegistry
    ) -> [NormalizedBuilding] {
        if let colony = settlement.colony, !colony.placements.isEmpty {
            return gridLayout(settlement: settlement, colony: colony, registry: registry)
        }
        return ringLayout(settlement: settlement, registry: registry)
    }

    /// **How big a building is drawn on the ground it owns.**
    ///
    /// The intent has always been *the building fills its parcel*; the
    /// arithmetic never did it. It was `min(lotW, lotH) / 2.2` — the lot's
    /// **short** side, over a rule-of-thumb for how many `size` a body runs
    /// across — and then `bodySize` multiplied the result by the lot's aspect
    /// again. Both ends of that are wrong in the same direction:
    ///
    /// - A square lot came out **73% filled across and about half filled
    ///   down**, so a street of huts was a street of models of huts with bare
    ///   ground between them. This is the complaint: *the houses want to be
    ///   bigger so everything fits and looks right.*
    /// - A lot that is narrow and long — a 1×3 — took its size from the *one*
    ///   tile and its aspect clamp from the three, and came out **44% of its
    ///   own width**. The longer the plot, the smaller the building on it.
    ///
    /// So ask the question directly instead: what `size` makes this glyph's
    /// body, in this lot's proportions, just fit the lot? `bodyShape` says how
    /// many `size` wide and tall each kind is drawn, and `bodySize` applies the
    /// same aspect clamp, so the two agree by construction rather than by a
    /// constant that has to be kept in step by hand.
    ///
    /// `fill` leaves a hair of ground at the edge, because lots may be directly
    /// adjacent — nothing forces a gap between two placements — and eaves that
    /// overhang into next door read as a bug rather than as a village. It is
    /// divided by the largest cosmetic jitter `bodySize` can add, so the
    /// *biggest* a building can come out is still inside its own parcel.
    static func lotSize(glyph: BuildingGlyph, lotW: Double, lotH: Double) -> Double {
        let fill = 0.94 / maxBodyJitter
        let shape = SettlementStructures.bodyShape(glyph)
        // The same clamp `bodySize` applies, or the width this solves for is
        // not the width that gets drawn.
        let aspect = lotH > 0 ? min(1.7, max(0.6, lotW / lotH)) : 1
        let byWidth = lotW * fill / (Double(shape.width) * aspect)
        // Capped by the ground it owns rather than by the room on screen: the
        // grid is square in map units and the canvas stretches it, so sizing to
        // the *drawn* height would make a colony of towers on a tall phone and
        // a colony of sheds on a squat one.
        let byHeight = lotH * fill / Double(shape.height)
        return min(byWidth, byHeight)
    }

    /// The most `SettlementStructures.bodySize` can enlarge a building for
    /// variety's sake. Stated here because `lotSize` has to leave room for it.
    static let maxBodyJitter: Double = 1.1

    /// The pixel-space layout for one frame — what drawing and hit-testing use.
    ///
    /// `viewport` is the rect actually on screen (the *view's* bounds, not the
    /// world rect the camera maps into). Pass it and the result is culled to
    /// what a viewer can see, which is the only cull that is safe: a building
    /// dropped for being off-screen is one nobody is looking at. Pass `nil` —
    /// as the path-drawing does — for the whole town.
    ///
    /// `PlacedBuilding.id` is the building's index in the **complete** layout,
    /// so culling never renumbers anything: a selection made before you panned
    /// still points at the same roof afterwards.
    static func layout(
        settlement: Settlement, registry: GameDataRegistry, rect: CGRect,
        viewport: CGRect? = nil
    ) -> [PlacedBuilding] {
        let unit = min(rect.width, rect.height)
        // Who sleeps where, counted once for the whole frame.
        var household: [UUID: Int] = [:]
        for pawn in settlement.pawns {
            guard let home = pawn.homeID else { continue }
            household[home, default: 0] += 1
        }
        let all = normalizedLayout(settlement: settlement, registry: registry).map { b in
            PlacedBuilding(id: b.id, definitionID: b.definitionID, name: b.name, glyph: b.glyph,
                           center: point(b.center, in: rect), size: unit * b.size,
                           footprint: CGSize(width: b.footprintW * unit, height: b.footprintH * unit),
                           underConstruction: b.underConstruction, progress: b.progress,
                           seed: b.seed, variant: b.variant,
                           era: b.era, fabric: b.fabric, floors: b.floors,
                           workers: b.assignedPawnIDs.count,
                           residents: b.placementID.map { household[$0] ?? 0 } ?? 0,
                           condition: b.condition,
                           stock: stock(of: b.definitionID, in: settlement, registry: registry),
                           goods: goods(of: b.definitionID, in: settlement, registry: registry,
                                        seed: b.seed))
        }
        return onScreen(all, viewport: viewport)
    }

    /// What one frame draws, out of every building the colony has.
    ///
    /// Two steps, in this order, because they answer different questions:
    ///
    /// 1. **Is it on screen?** A lot is kept if it overlaps the viewport grown
    ///    by `offscreenMargin` — the margin so a roof half off the edge, and
    ///    the shadow it throws inward, are still drawn.
    /// 2. **If more than the budget survive, which?** The ones nearest the
    ///    middle of the view. Zoomed out over a large town this is the whole
    ///    colony minus its outskirts, which is the right thing to lose: you
    ///    are looking at the middle.
    static func onScreen(_ all: [PlacedBuilding], viewport: CGRect?) -> [PlacedBuilding] {
        guard let viewport else { return all }
        let frame = viewport.insetBy(dx: -offscreenMargin, dy: -offscreenMargin)
        let visible = all.filter { b in
            frame.intersects(CGRect(x: b.center.x - b.footprint.width / 2,
                                    y: b.center.y - b.footprint.height / 2,
                                    width: max(1, b.footprint.width),
                                    height: max(1, b.footprint.height)))
        }
        guard visible.count > maxDrawnBuildings else { return visible }
        let middle = CGPoint(x: viewport.midX, y: viewport.midY)
        // Sorted by distance, then by id, so a tie never depends on the order
        // the layout happened to come back in.
        return visible.sorted { a, b in
            let da = (a.center.x - middle.x) * (a.center.x - middle.x)
                + (a.center.y - middle.y) * (a.center.y - middle.y)
            let db = (b.center.x - middle.x) * (b.center.x - middle.x)
                + (b.center.y - middle.y) * (b.center.y - middle.y)
            return da == db ? a.id < b.id : da < db
        }
        .prefix(maxDrawnBuildings)
        .sorted { $0.id < $1.id }
    }

    /// How far outside the view a building is still drawn. A lot whose middle
    /// has just left the screen still has eaves and a shadow inside it.
    static let offscreenMargin: CGFloat = 80

    /// The structures as actually placed on the build grid.
    static func gridLayout(
        settlement: Settlement, colony: ColonyMap, registry: GameDataRegistry
    ) -> [NormalizedBuilding] {
        // Which buildings keep or build a conveyance, read out of the vehicle
        // bank once for the whole pass rather than per placement.
        let sheds = StructureVariant.conveyanceHomes(registry)
        return colony.placements.enumerated().map { index, placement in
            // `coord` is the footprint's top-left origin, so a multi-tile
            // building is nudged to the middle of what it covers — and drawn
            // larger for covering it.
            let origin = canvasPoint(for: placement.coord, in: colony)
            let span = colonySpan(colony)
            let p = LocalPoint(
                x: origin.x + Double(placement.width - 1) * 0.5 / Double(max(1, colony.width)) * span,
                y: origin.y + Double(placement.height - 1) * 0.5 / Double(max(1, colony.height)) * span)
            let def = registry.building(placement.definitionID)
            let glyph = def.map(glyph(for:)) ?? .house
            let progress = settlement.constructions
                .first { $0.placementID == placement.id }?.fraction
            let label = def?.name.resolve(AppStrings.language) ?? placement.definitionID
            // The footprint in canvas fractions: one tile is this slice of the
            // built span, and the plot is as many tiles wide and tall as the
            // building covers.
            // This colony's own ground, not the founding constant: a building's
            // *size* has to be measured off the same span its *place* is, or a
            // grown town draws every roof at the founding scale on tiles that
            // are no longer that size — neighbours overlap and the lots stop
            // meaning anything (rule 35).
            let tileW = span / Double(max(1, colony.width))
            let tileH = span / Double(max(1, colony.height))
            return NormalizedBuilding(
                id: index,
                definitionID: placement.definitionID,
                name: label,
                glyph: glyph,
                center: p,
                // Sized to the ground it owns, and **to the shape it is drawn
                // in** — see `lotSize`.
                size: lotSize(glyph: glyph,
                              lotW: Double(max(1, placement.width)) * tileW,
                              lotH: Double(max(1, placement.height)) * tileH),
                footprintW: Double(max(1, placement.width)) * tileW,
                footprintH: Double(max(1, placement.height)) * tileH,
                underConstruction: placement.underConstruction,
                progress: placement.underConstruction ? (progress ?? 0) : 1,
                seed: buildingSeed(placement.id),
                variant: def.map { StructureVariant.of($0, housesConveyances: sheds.contains($0.id),
                                              composition: registry.structure($0.id)) }
                    ?? .plain,
                era: def?.era ?? .earlySettlement,
                fabric: def.map { Cover.substance(of: $0, registry: registry) } ?? .wood,
                floors: max(1, def?.floors ?? 1),
                assignedPawnIDs: placement.assignedPawnIDs,
                placementID: placement.id,
                condition: placement.condition)
        }
    }

    /// Calm rings around the heart, for a colony with no layout of its own yet.
    /// Civic buildings hold the centre; housing drifts to the outer rings.
    /// Pure and deterministic — the same settlement always lays out the same.
    static func ringLayout(
        settlement: Settlement, registry: GameDataRegistry
    ) -> [NormalizedBuilding] {
        var expanded: [(id: String, name: String, glyph: BuildingGlyph, era: Era,
                        fabric: Cover.Substance, floors: Int,
                        variant: StructureVariant)] = []
        let sheds = StructureVariant.conveyanceHomes(registry)
        for instance in settlement.buildings {
            let def = registry.building(instance.definitionID)
            let g = def.map(glyph(for:)) ?? .house
            for _ in 0..<instance.count {
                expanded.append((instance.definitionID,
                                 def?.name.resolve(AppStrings.language) ?? instance.definitionID,
                                 g, def?.era ?? .earlySettlement,
                                 def.map { Cover.substance(of: $0, registry: registry) } ?? .wood,
                                 max(1, def?.floors ?? 1),
                                 def.map { StructureVariant.of($0, housesConveyances: sheds.contains($0.id),
                                                              composition: registry.structure($0.id)) }
                                    ?? .plain))
            }
        }
        guard !expanded.isEmpty else { return [] }
        expanded.sort { rank($0.glyph) < rank($1.glyph) }

        var placed: [NormalizedBuilding] = []
        var drawn = 0, ringIndex = 0
        while drawn < expanded.count {
            let perRing = ringIndex == 0 ? 1 : ringIndex * 6
            let radius = Double(ringIndex) * 0.052
            for slot in 0..<perRing where drawn < expanded.count {
                let angle = Double(slot) / Double(perRing) * 2 * .pi + Double(ringIndex) * 0.6
                // The y-step is damped: normalised y maps to the (taller)
                // screen height, and an uncorrected circle stretches into an
                // egg on a portrait phone.
                let c = LocalPoint(x: colonyHeart.x + cos(angle) * radius,
                                   y: colonyHeart.y + sin(angle) * radius * 0.72)
                placed.append(NormalizedBuilding(
                    id: drawn, definitionID: expanded[drawn].id,
                    name: expanded[drawn].name, glyph: expanded[drawn].glyph,
                    center: c,
                    // The same rule the grid uses, so a colony that has not been
                    // laid out yet is not drawn a size smaller than one that has.
                    size: lotSize(glyph: expanded[drawn].glyph, lotW: 0.05, lotH: 0.05),
                    footprintW: 0.05, footprintH: 0.05,
                    underConstruction: false, progress: 1,
                    seed: buildingSeed(expanded[drawn].id, drawn),
                    variant: expanded[drawn].variant,
                    era: expanded[drawn].era,
                    fabric: expanded[drawn].fabric, floors: expanded[drawn].floors,
                    assignedPawnIDs: [], placementID: nil, condition: 1))
                drawn += 1
            }
            ringIndex += 1
        }
        return placed
    }

    /// Civic buildings rank low (centre), housing high (outskirts).
    static func rank(_ g: BuildingGlyph) -> Int {
        switch g {
        case .temple: return 0
        case .hall: return 1
        case .market: return 2
        case .granary: return 3
        case .cookhouse: return 3
        case .workshop: return 4
        case .mill: return 5
        case .plant: return 6
        case .generator: return 7
        case .array: return 8
        case .pad: return 9
        case .mine: return 10
        case .sawmill: return 10
        case .forge: return 6
        case .tanks: return 7
        case .rail: return 7
        case .lab: return 2
        case .dish: return 8
        case .vault: return 2
        case .clinic: return 3
        case .aqueduct: return 3
        case .turbine: return 8
        case .dam: return 9
        case .wall: return 13
        case .barracks: return 11
        case .well: return 3
        case .lodge: return 11
        case .farm: return 14
        case .tower: return 11
        case .house: return 12
        case .tenement: return 12
        }
    }

}
