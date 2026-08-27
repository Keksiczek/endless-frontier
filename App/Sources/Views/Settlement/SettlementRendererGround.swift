import SwiftUI
import EndlessFrontierCore

/// **The ground itself**: bare country, cover, zones, roads, water.
///
/// Everything under the props and the roofs — the surveyed wilderness of a
/// region nobody lives in, the colour a tile takes in a season, the work zones,
/// the points of interest, the highways and the trails worn between them, the
/// heart of the town, and the river with the places it can be crossed.
extension SettlementRenderer {
    /// Draws an explored region's *chunk* — the same terrain, deposits,
    /// landmarks and wildlife a settlement map gets, minus the town. This is
    /// what opens when you survey a region from the world map: the land as
    /// your expedition recorded it, alive. A native people's camp (and its
    /// people, walking) is drawn when one lives here.
    static func drawWilderness(
        _ context: inout GraphicsContext,
        size: CGSize,
        map: LocalMap,
        season: Season,
        time: Double,
        camera: Camera,
        /// The age the world is in, so a people's own rooms are furnished for
        /// now rather than for the first age (`FittingDefinition`).
        era: Era = .earlySettlement,
        regionKind: RegionKind,
        tribe: Tribe?,
        /// **The people who live here, as a settlement.** Derived from the
        /// tribe by `TribeCamp` and never stored — real roofs on a real build
        /// grid and real pawns with bodies, drawn by the same code that draws
        /// your own town. Nil falls back to the old ring of tents, which is
        /// all a people who are not there yet needs.
        camp: Settlement? = nil,
        seasonProgress: Double = 0.5,
        continuousTick: Double = 0,
        selectedPawnID: UUID? = nil,
        registry: GameDataRegistry
    ) {
        let viewRect = CGRect(origin: .zero, size: size)
        let rect = worldRect(viewRect: viewRect, camera: camera)
        let night = nightness(time: time)
        let sun = SettlementLight.sun(time: time)
        let zoom = camera.scale
        let showLabels = zoom >= 1.6
        SettlementGround.draw(&context, rect: rect, map: map, season: season, zoom: zoom,
                              sun: sun, seasonProgress: seasonProgress,
                              registry: registry)
        // The sea, before the river and the landscape: everything else stands
        // on the land it leaves.
        sea(&context, rect: rect, shore: map.shore, season: season, time: time)
        river(&context, rect: rect, river: map.river, season: season, zoom: zoom)
        scenery(&context, rect: rect, map: map, season: season)
        // The real wood and rock, over the decorative landscape but under
        // anything built — a tree stands in front of the grass and behind the
        // roof it shades.
        // The mountain, before the wood: a tree at the foot of a cliff stands in
        // front of it, and nothing stands on top of solid rock.
        // The country's own shapes first of all: a ravine is *ground*, so the
        // rock, the wood and everything standing on it belongs in front.
        SettlementLandforms.draw(&context, rect: rect, map: map, season: season,
                                 zoom: zoom, showLabels: showLabels)
        SettlementStone.draw(&context, rect: rect, map: map, season: season, zoom: zoom,
                             registry: registry)
        SettlementFlora.draw(&context, rect: rect, map: map, season: season, time: time,
                             sun: sun, viewport: viewRect, registry: registry)
        // The fields, over the ground and under everything standing on it —
        // a plot is worked earth, so a figure reaping it stands in front.
        SettlementCrops.draw(&context, rect: rect, map: map, season: season, zoom: zoom,
                             registry: registry)
        // What has been cut and not yet carried in.
        SettlementPiles.draw(&context, rect: rect, map: map, zoom: zoom)
        // And whoever has come in over the edge to trade or to talk.
        SettlementVisitors.draw(
            &context, rect: rect, map: map, time: time,
            continuousStep: continuousTick * Double(WorldClock.actionStepsPerTick),
            zoom: zoom, showLabels: showLabels)
        deposits(&context, rect: rect, map: map, season: season, zoom: zoom,
                 showLabels: showLabels)
        pois(&context, rect: rect, map: map, time: time, showLabels: showLabels)
        SettlementWildlife.draw(
            &context, rect: rect, map: map, time: time,
            continuousStep: continuousTick * Double(WorldClock.actionStepsPerTick),
            zoom: zoom)
        if regionKind == .anomaly {
            anomalyGlow(&context, rect: rect, time: time)
        }
        if let camp, camp.colony?.placements.isEmpty == false {
            // **The same drawing your own town gets.** A people is not a
            // different kind of thing from a colony, so nothing here is a
            // second renderer: the lots, the roofs, the insides, the smoke and
            // the figures walking their day all come out of the code that
            // already draws yours (`docs/HANDOFF-2026-08-22.md` §4.4, stage
            // one — and stage one adds nothing to the tick).
            let placed = layout(settlement: camp, registry: registry, rect: rect,
                                viewport: CGRect(origin: .zero, size: size))
            buildings(&context, placed: placed, time: time, night: night,
                      showLabels: showLabels, zoom: zoom, sun: sun,
                      selectedBuildingID: nil, registry: registry, era: era)
            SettlementFigures.smoke(
                &context,
                houses: placed.filter { $0.glyph == .house && !$0.underConstruction },
                time: time, zoom: zoom)
            agents(&context, rect: rect, settlement: camp, map: map,
                   continuousTick: continuousTick, registry: registry,
                   time: time, zoom: zoom, selectedPawnID: selectedPawnID)
        } else if let tribe {
            SettlementStructures.camp(
                &context, rect: rect, population: tribe.population,
                tint: campTint(tribe.status), time: time,
                seed: map.terrainSeed, night: night, zoom: zoom)
        }
        seasonWash(&context, rect: viewRect, size: size, season: season, time: time)
        SettlementLight.wash(&context, rect: viewRect, sun: sun)
        nightWash(&context, rect: viewRect, night: night)
    }

    static func campTint(_ status: DiplomaticStanding) -> Color {
        switch status {
        case .allied, .friendly: return Theme.good
        case .neutral: return Theme.bone
        case .tense: return Theme.accent
        case .war: return Theme.danger
        }
    }

    /// The anomaly's unquiet light: a breathing glow and slow-orbiting motes.
    static func anomalyGlow(
        _ context: inout GraphicsContext, rect: CGRect, time: Double
    ) {
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let breath = 0.5 + 0.5 * sin(time * 0.8)
        let radius = rect.width * (0.16 + 0.03 * breath)
        context.fill(
            Path(ellipseIn: CGRect(x: c.x - radius, y: c.y - radius,
                                   width: radius * 2, height: radius * 2)),
            with: .radialGradient(
                Gradient(colors: [Color(red: 0.55, green: 0.45, blue: 0.85).opacity(0.20 + 0.10 * breath), .clear]),
                center: c, startRadius: 0, endRadius: radius))
        for i in 0..<5 {
            let angle = time * 0.3 + Double(i) * 1.26
            let r = radius * (0.5 + 0.35 * sin(time * 0.5 + Double(i)))
            let p = CGPoint(x: c.x + cos(angle) * r, y: c.y + sin(angle) * r * 0.7)
            context.fill(Path(ellipseIn: CGRect(x: p.x - 1.2, y: p.y - 1.2, width: 2.4, height: 2.4)),
                         with: .color(Color(red: 0.7, green: 0.6, blue: 0.95).opacity(0.7)))
        }
    }

    // MARK: - Ground tiles

    /// The earth, drawn by `SettlementGround` — a square grain over the fog
    /// grid rather than the fog grid itself, which on a phone is three times
    /// taller than it is wide and made every meadow a green column.
    static func coverColor(_ cover: GroundCover, season: Season,
                           registry: GameDataRegistry) -> Color {
        SettlementGround.coverColor(cover, season: season, registry: registry)
    }

    // MARK: - Zones

    /// The amenity zones the player painted on the build grid, visible on the
    /// living canvas at last: a park's green, a plaza's paving, a garden's
    /// blooms. The plaza is also where the midday crowd gathers (see
    /// `AgentMotion.Scene`).
    static func zones(
        _ context: inout GraphicsContext, rect: CGRect, settlement: Settlement, season: Season
    ) {
        guard let colony = settlement.colony, !colony.zones.isEmpty else { return }
        let unit = min(rect.width, rect.height)
        let tile = unit * 0.038
        for zone in colony.zones {
            let center = point(canvasPoint(for: zone.coord, in: colony), in: rect)
            let patch = CGRect(x: center.x - tile / 2, y: center.y - tile / 2,
                               width: tile, height: tile)
            switch zone.kind {
            case .park:
                context.fill(Path(roundedRect: patch, cornerRadius: tile * 0.3),
                             with: .color(canopyColor(season).opacity(0.16)))
                for i in 0..<2 {
                    let x = patch.minX + tile * (0.3 + Double(i) * 0.4)
                    context.stroke(Path { p in
                        p.move(to: CGPoint(x: x, y: patch.maxY - 2))
                        p.addLine(to: CGPoint(x: x, y: patch.midY))
                    }, with: .color(canopyColor(season).opacity(0.7)), lineWidth: 0.8)
                    context.stroke(
                        Path(ellipseIn: CGRect(x: x - 2.4, y: patch.midY - 4.5, width: 4.8, height: 4.5)),
                        with: .color(canopyColor(season).opacity(0.7)), lineWidth: 0.8)
                }
            case .plaza:
                context.fill(Path(roundedRect: patch, cornerRadius: tile * 0.15),
                             with: .color(Theme.bone.opacity(0.08)))
                for i in 0..<4 {
                    let x = patch.minX + tile * (0.2 + Double(i % 2) * 0.5)
                    let y = patch.minY + tile * (0.25 + Double(i / 2) * 0.45)
                    context.stroke(Path(CGRect(x: x, y: y, width: 2.6, height: 1.8)),
                                   with: .color(Theme.boneFaint), lineWidth: 0.5)
                }
            case .garden:
                context.fill(Path(roundedRect: patch, cornerRadius: tile * 0.3),
                             with: .color(Color(red: 0.35, green: 0.5, blue: 0.32).opacity(0.18)))
                for i in 0..<3 {
                    let x = patch.minX + tile * (0.25 + Double(i) * 0.25)
                    let y = patch.midY + (i % 2 == 0 ? -2.0 : 2.0)
                    context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 1.8, height: 1.8)),
                                 with: .color(Color(red: 0.85, green: 0.72, blue: 0.6).opacity(0.8)))
                }
            }
        }
    }

    // MARK: - Points of interest

    /// Discovered landmarks — what the scouts' walking actually found.
    static func pois(
        _ context: inout GraphicsContext, rect: CGRect, map: LocalMap, time: Double,
        showLabels: Bool = false, expeditions: [POIExpedition] = []
    ) {
        let unit = min(rect.width, rect.height)
        for poi in map.pois where poi.discovered && map.isExplored(poi.position) {
            let c = point(poi.position, in: rect)
            // A faint halo separates a landmark from mere scenery — and says
            // at a glance whether the place still has anything to give. A
            // picked-clean ruin should not keep inviting you over.
            let spent = poi.isExhausted
            let halo = unit * 0.024
            context.fill(Path(ellipseIn: CGRect(x: c.x - halo, y: c.y - halo,
                                                width: halo * 2, height: halo * 2)),
                         with: .color(Theme.accent.opacity(spent ? 0.02 : 0.06)))
            context.stroke(Path(ellipseIn: CGRect(x: c.x - halo, y: c.y - halo,
                                                  width: halo * 2, height: halo * 2)),
                           with: .color(spent ? Theme.textDim.opacity(0.18)
                                              : Theme.accent.opacity(0.22)),
                           lineWidth: 0.7)
            SettlementStructures.poi(poi.kind, at: c,
                                     s: unit * 0.014, time: time, context: &context)
            // If a party is in there right now, draw what they are dealing
            // with. A visit used to be a party standing on a dot for six ticks.
            if let site = expeditions.first(where: { $0.poiID == poi.id })?.site {
                SettlementSites.draw(site, in: rect, time: time, context: &context)
            }
            if showLabels {
                let caption = Text(poi.kind.displayLabel)
                    .font(.system(size: 5.5))
                    .foregroundStyle(Theme.accent.opacity(0.8))
                context.draw(context.resolve(caption),
                             at: CGPoint(x: c.x, y: c.y + halo + 5))
            }
        }
    }

    // MARK: - Paths

    /// Worn trails printed into the grass: from the heart out to every working
    /// structure and to the deposits the colony is actually harvesting — the
    /// routes the colonists genuinely walk. The town stops floating on lawn
    /// and starts being *connected*.
    /// **The paved and the railed, where they cross the valley.**
    ///
    /// A track and a road are ground: they are drawn by wearing the earth bare
    /// along their line, in the ground's own opaque colour, which is what
    /// `SettlementTracks` does for the town's streets and for these. Paving and
    /// rail are not ground — they are stone somebody cut and iron somebody
    /// laid, and no shade of packed earth can say so.
    ///
    /// Opaque, like everything drawn over the ground: the earth tiles overlap
    /// by a third of themselves and anything see-through doubles along every
    /// seam of it (rule 9).
    static func highways(
        _ context: inout GraphicsContext, rect: CGRect,
        approaches: [RoadApproach], zoom: CGFloat
    ) {
        let heart = point(colonyHeart, in: rect)
        for approach in approaches where approach.link.grade == .paved || approach.link.grade == .rail {
            let edge = point(approach.edgePoint, in: rect)
            var way = Path()
            way.move(to: edge)
            way.addLine(to: heart)
            // A way in poor repair is a way with the country coming back
            // through it, so the stone narrows rather than fading — fading is
            // translucency, and translucency is the thing that cannot be done
            // here.
            let kept = max(0.35, min(1, approach.link.condition))
            let width = SettlementTracks.halfWidth(of: approach.link.grade)
                * 2 * rect.width * kept
            switch approach.link.grade {
            case .paved:
                context.stroke(way, with: .color(Color(red: 0.53, green: 0.51, blue: 0.47)),
                               style: StrokeStyle(lineWidth: width, lineCap: .round))
                context.stroke(way, with: .color(Color(red: 0.44, green: 0.42, blue: 0.38)),
                               style: StrokeStyle(lineWidth: width * 0.42, lineCap: .round,
                                                  dash: [width * 0.5, width * 0.8]))
            case .rail:
                context.stroke(way, with: .color(Color(red: 0.30, green: 0.25, blue: 0.20)),
                               style: StrokeStyle(lineWidth: width, lineCap: .butt,
                                                  dash: [max(1, 2.4 * zoom), max(1, 4.2 * zoom)]))
                let gauge = width * 0.30
                let dx = heart.x - edge.x, dy = heart.y - edge.y
                let length = max(1, (dx * dx + dy * dy).squareRoot())
                let nx = -dy / length * gauge, ny = dx / length * gauge
                for side in [1.0, -1.0] {
                    var rail = Path()
                    rail.move(to: CGPoint(x: edge.x + nx * side, y: edge.y + ny * side))
                    rail.addLine(to: CGPoint(x: heart.x + nx * side, y: heart.y + ny * side))
                    context.stroke(rail, with: .color(Color(red: 0.62, green: 0.61, blue: 0.60)),
                                   style: StrokeStyle(lineWidth: max(0.8, 1.2 * zoom), lineCap: .round))
                }
            case .track, .road:
                break
            }
        }
    }

    /// **The trails out of the town**, to the wood and the quarry and the herb
    /// patch — and nothing else.
    ///
    /// This used to draw a curve from the heart of the colony to every
    /// building in it, which was invented: no colonist ever walks from the
    /// green to the smithy and back for its own sake, and the drawing was
    /// there because the town needed *something* between its boxes. It has
    /// that now, and it is real — `SettlementPaths`, worn by the journeys the
    /// engine actually gives people, drawn into the ground itself.
    ///
    /// What is left here is the half that was always true. A deposit is out in
    /// the valley rather than on the build grid, so no amount of walking to it
    /// wears a build-grid tile; and only a deposit somebody is *assigned* to
    /// work gets a trail, which is the same rule it always had.
    static func trails(
        _ context: inout GraphicsContext, rect: CGRect,
        settlement: Settlement, registry: GameDataRegistry, map: LocalMap, zoom: CGFloat
    ) {
        let heart = point(colonyHeart, in: rect)
        var targets: [CGPoint] = []
        let worked = Set(settlement.pawns.map(\.assignedWork))
        for node in map.nodes
        where map.isExplored(node.position) && worked.contains(node.kind.work) {
            targets.append(point(node.position, in: rect))
        }

        let dirt = Color(red: 0.36, green: 0.31, blue: 0.23)
        for (i, target) in targets.prefix(14).enumerated() {
            let dx = target.x - heart.x, dy = target.y - heart.y
            let length = max(1, sqrt(dx * dx + dy * dy))
            let side: CGFloat = i.isMultiple(of: 2) ? 1 : -1
            let bow = min(14 * zoom, length * 0.12) * side
            var trail = Path()
            trail.move(to: heart)
            trail.addQuadCurve(
                to: target,
                control: CGPoint(x: (heart.x + target.x) / 2 - dy / length * bow,
                                 y: (heart.y + target.y) / 2 + dx / length * bow))
            context.stroke(trail, with: .color(dirt.opacity(0.32)),
                           style: StrokeStyle(lineWidth: 2.6 * zoom, lineCap: .round))
        }
    }

    static func heartGlow(_ context: inout GraphicsContext, rect: CGRect) {
        let heart = CGPoint(x: rect.midX, y: rect.minY + rect.height * 0.52)
        context.fill(
            Path(ellipseIn: CGRect(x: heart.x - rect.width * 0.4, y: heart.y - rect.height * 0.4,
                                   width: rect.width * 0.8, height: rect.height * 0.8)),
            with: .radialGradient(
                Gradient(colors: [Theme.bone.opacity(0.05), .clear]),
                center: heart, startRadius: 0, endRadius: rect.width * 0.42)
        )
    }

    // MARK: - River

    static func river(
        _ context: inout GraphicsContext, rect: CGRect, river: RiverShape,
        season: Season, zoom: CGFloat = 1
    ) {
        // A dry valley has no river to draw. Six kinds of country that all came
        // with the same blue ribbon across them read as one kind of country in
        // six tints — which is why the biome now decides whether water runs.
        guard river.flows else { return }
        var path = Path()
        let steps = 48
        for i in 0...steps {
            let nx = Double(i) / Double(steps)
            let p = point(LocalPoint(x: nx, y: river.y(atX: nx)), in: rect)
            if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
        }
        // The band is *geometry* (a river has a width in the world), so it
        // grows with the camera; the highlight stays a near-hairline.
        let body = 14 * zoom
        let sheen = max(1.4, 2 * sqrt(zoom))
        if season == .winter {
            context.stroke(path, with: .color(Color(red: 0.42, green: 0.50, blue: 0.60)),
                           style: StrokeStyle(lineWidth: body, lineCap: .round, lineJoin: .round))
            context.stroke(path, with: .color(Color(red: 0.72, green: 0.80, blue: 0.90).opacity(0.8)),
                           style: StrokeStyle(lineWidth: sheen, lineCap: .round,
                                              dash: [6 * zoom, 5 * zoom]))
        } else {
            context.stroke(path, with: .color(Color(red: 0.15, green: 0.22, blue: 0.30)),
                           style: StrokeStyle(lineWidth: body, lineCap: .round, lineJoin: .round))
            context.stroke(path, with: .color(Color(red: 0.38, green: 0.52, blue: 0.64).opacity(0.75)),
                           style: StrokeStyle(lineWidth: sheen, lineCap: .round))
        }
        fords(&context, rect: rect, river: river, season: season, zoom: zoom)
    }

    /// **The crossings**, drawn over the water they break.
    ///
    /// A ford is a place: `RiverShape.fords` is where the channel spreads over
    /// gravel, `PathEngine.waterDepth` calls it wadeable, and every party that
    /// has to reach the far side of the valley walks to one. Rule 18 — what is
    /// in the simulation is on the canvas, and until this the crossings were
    /// somewhere people mysteriously converged on.
    static func fords(
        _ context: inout GraphicsContext, rect: CGRect, river: RiverShape,
        season: Season, zoom: CGFloat
    ) {
        let gravel = season == .winter
            ? Color(red: 0.68, green: 0.70, blue: 0.72)
            : Color(red: 0.55, green: 0.51, blue: 0.42)
        for x in river.fords {
            let half = RiverShape.fordHalfWidth
            var bed = Path()
            let steps = 8
            for i in 0...steps {
                let nx = x - half + (half * 2) * Double(i) / Double(steps)
                let p = point(LocalPoint(x: nx, y: river.y(atX: nx)), in: rect)
                if i == 0 { bed.move(to: p) } else { bed.addLine(to: p) }
            }
            // Shallow water over stones: the band narrows and pales.
            context.stroke(bed, with: .color(gravel.opacity(0.85)),
                           style: StrokeStyle(lineWidth: 11 * zoom, lineCap: .round))
            // …and the stones themselves, so it reads as something underfoot.
            for i in 0..<5 {
                let nx = x - half * 0.7 + half * 1.4 * Double(i) / 4
                let p = point(LocalPoint(x: nx, y: river.y(atX: nx)), in: rect)
                let r = 1.1 * zoom
                let lift = CGFloat(i.isMultiple(of: 2) ? -1.6 : 1.8) * zoom
                context.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r + lift,
                                                    width: r * 2, height: r * 1.5)),
                             with: .color(gravel))
            }
        }
    }

    // MARK: - Scenery

}
