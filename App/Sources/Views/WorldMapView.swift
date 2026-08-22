import SwiftUI
import EndlessFrontierCore

/// An interactive hex world map. Pan (drag) and zoom (pinch) — iPad and
/// iPhone friendly. Tiles are coloured by biome, fogged while unknown, and
/// marked with icons for the homeland, settlements, special sites, and the
/// active expedition target.
struct WorldMapView: View {
    @Bindable var game: GameViewModel
    @Binding var selectedRegionID: UUID?

    private let hexSize: CGFloat = 46

    @State private var zoom: CGFloat = 1
    @State private var committedZoom: CGFloat = 1
    @State private var pan: CGSize = .zero
    @State private var committedPan: CGSize = .zero
    /// **Laying ways by tapping the map itself.**
    ///
    /// The affordance was a list of neighbours in the region panel, with a
    /// price on each — a fine way to *buy* a road and a poor way to see one,
    /// because a road is a line between two places and a row of text is not.
    /// Keks: the tap belongs on the edge, and it wanted the drawing first.
    /// The drawing exists now.
    @State private var layingWays = false
    /// The edge the player has touched but not yet paid for. A road is money
    /// out of the store and the store is the colony's whole margin, so it is
    /// asked for twice: once to pick the stretch, once to buy it.
    @State private var pendingEdge: RoadLink?

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Theme.surfaceInset
                tiles
                    .scaleEffect(zoom)
                    .offset(pan)
                    .frame(width: geo.size.width, height: geo.size.height)
                    .contentShape(Rectangle())
                    .gesture(panGesture.simultaneously(with: zoomGesture))
                // The same seasonal air as the settlement canvas, so the world
                // and the valley read as one place in one time of year.
                Rectangle()
                    .fill(Theme.seasonTint(game.season))
                    .allowsHitTesting(false)
            }
            .clipped()
            .overlay(alignment: .topLeading) { homeButton }
            .overlay(alignment: .bottomLeading) { wayButton }
        }
    }

    /// An endless map grows outward without bound, so it's easy to drag off
    /// into unexplored dark and lose the homeland entirely. This walks back.
    private var homeButton: some View {
        Button {
            withAnimation(.snappy) {
                pan = .zero; committedPan = .zero
                zoom = 1; committedZoom = 1
            }
        } label: {
            Image(systemName: "house.fill")
                .font(.caption)
                .padding(8)
                .background(.ultraThinMaterial, in: Circle())
        }
        .tint(Theme.text)
        .padding(12)
        .accessibilityLabel(AppStrings.language == .cs ? "Zpět k domovině" : "Back to the homeland")
    }

    private var tiles: some View {
        ZStack {
            ForEach(game.regions) { region in
                tile(region)
                    .position(tilePosition(region.coord))
            }
            tradeLayer
            if layingWays { wayLayer }
        }
        // Centre the origin in a large virtual canvas.
        .frame(width: 1200, height: 1200)
    }

    /// Commerce made visible: standing trade routes as faint threads between
    /// the settlements they join, and every traveling caravan as an amber dot
    /// actually *on the road* — its place along the line is its real progress.
    private var tradeLayer: some View {
        TimelineView(.animation(minimumInterval: 0.25)) { timeline in
            Canvas { ctx, _ in
                let t = timeline.date.timeIntervalSinceReferenceDate
                // **The ways themselves, under everything else.** The Core has
                // owned a road network since `RoadEngine`; nothing drew it, so
                // the one thing the colony builds *on the world map* was
                // invisible. Under the trade threads on purpose: a route is a
                // contract and a road is the ground it runs over.
                // **The water, under the ways.** A river is drawn as the
                // course it is — in at one edge, out at another — so a valley
                // reads as a valley and a bridge has something visible to
                // cross. Only where the player has walked: the fog is the fog.
                for region in game.world.regions {
                    guard let river = region.river,
                          region.explorationState != .unknown else { continue }
                    let centre = tilePosition(region.coord)
                    var water = Path()
                    if let from = river.from {
                        water.move(to: midpoint(region.coord, from))
                        water.addLine(to: centre)
                    } else {
                        water.move(to: centre)
                    }
                    if let to = river.to {
                        water.addLine(to: midpoint(region.coord, to))
                    }
                    ctx.stroke(water, with: .color(Theme.water.opacity(0.75)),
                               style: StrokeStyle(lineWidth: 2.2, lineCap: .round,
                                                  lineJoin: .round))
                }

                for link in game.world.roads.all {
                    // A way through country nobody has walked is not something
                    // the player knows about. Ancient stone especially: finding
                    // it is the whole of what it is for, and a ruin drawn
                    // through the fog has already been found.
                    guard game.isKnown(link.a) || game.isKnown(link.b) else { continue }
                    let a = tilePosition(link.a)
                    let b = tilePosition(link.b)
                    var way = Path()
                    way.move(to: a)
                    way.addLine(to: b)
                    let look = RoadStyle.of(link)
                    ctx.stroke(way, with: .color(look.color),
                               style: StrokeStyle(lineWidth: look.width, lineCap: .round,
                                                  dash: look.dash))
                    // A railway is two rails and its sleepers, so it cannot be
                    // mistaken for a road that happens to be wider.
                    if link.grade == .rail {
                        ctx.stroke(way, with: .color(look.color.opacity(0.55)),
                                   style: StrokeStyle(lineWidth: look.width * 2.4,
                                                      dash: [1.5, 4]))
                    }
                }
                for route in game.tradeRoutes {
                    guard let a = position(ofSettlement: route.fromID),
                          let b = position(ofSettlement: route.toID) else { continue }
                    var thread = Path()
                    thread.move(to: a)
                    thread.addLine(to: b)
                    ctx.stroke(thread, with: .color(Theme.boneFaint.opacity(0.6)),
                               style: StrokeStyle(lineWidth: 1, dash: [4, 5]))
                }
                for caravan in game.caravans where caravan.status == .traveling {
                    guard let a = position(ofSettlement: caravan.originID),
                          let b = position(ofSettlement: caravan.destinationID) else { continue }
                    let progress = 1 - Double(caravan.ticksRemaining) / Double(max(1, caravan.totalTicks))
                    let bob = sin(t * 3) * 1.5
                    let p = CGPoint(x: a.x + (b.x - a.x) * progress,
                                    y: a.y + (b.y - a.y) * progress + bob)
                    var road = Path()
                    road.move(to: a)
                    road.addLine(to: b)
                    ctx.stroke(road, with: .color(Theme.accent.opacity(0.25)),
                               style: StrokeStyle(lineWidth: 1, dash: [3, 4]))
                    ctx.fill(Path(ellipseIn: CGRect(x: p.x - 4, y: p.y - 4, width: 8, height: 8)),
                             with: .color(Color.black.opacity(0.4)))
                    ctx.fill(Path(ellipseIn: CGRect(x: p.x - 2.6, y: p.y - 2.6,
                                                    width: 5.2, height: 5.2)),
                             with: .color(Theme.accent))
                }
            }
        }
        .allowsHitTesting(false)
    }

    // MARK: - Laying a way

    /// The switch into and out of way-laying. Only once there is something to
    /// lay: nothing can be built in the first age (`RoadGrade.road` wants
    /// `.ancient`), and a button that does nothing is worse than no button.
    @ViewBuilder
    private var wayButton: some View {
        if !game.layableEdges.isEmpty {
            Button {
                withAnimation(.snappy) {
                    layingWays.toggle()
                    pendingEdge = nil
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: layingWays ? "xmark" : "road.lanes")
                        .font(.caption)
                    Text(layingWays
                         ? (AppStrings.language == .cs ? "Hotovo" : "Done")
                         : (AppStrings.language == .cs ? "Stavět cesty" : "Lay ways"))
                        .font(.caption.weight(.semibold))
                }
                .foregroundStyle(layingWays ? Theme.ink : Theme.text)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(layingWays ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(.ultraThinMaterial),
                            in: Capsule())
            }
            .padding(12)
        }
    }

    /// **Every stretch that could be made, drawn where it would run.**
    ///
    /// A ghost line on the edge itself, with its price on it; the one the
    /// player has touched is lit and says what it is. Tapping empty ground
    /// puts the choice down again.
    ///
    /// The list is asked for once per redraw rather than inside the canvas
    /// closure — `layableEdges` walks every charted hex, and a canvas body is
    /// not a place to do that (rule 38).
    private var wayLayer: some View {
        let edges = game.layableEdges
        let purse = game.selectedSettlementStorage(.materials)
        return ZStack {
            Canvas { ctx, _ in
                for edge in edges {
                    let a = tilePosition(edge.link.a), b = tilePosition(edge.link.b)
                    let chosen = edge.link.id == pendingEdge?.id
                    let affordable = purse >= edge.cost
                    // Drawn short of both centres, so the line reads as the
                    // edge between two hexes rather than as a spoke out of one.
                    let dx = b.x - a.x, dy = b.y - a.y
                    let length = max(1, (dx * dx + dy * dy).squareRoot())
                    let trim: CGFloat = hexSize * 0.34
                    var way = Path()
                    way.move(to: CGPoint(x: a.x + dx / length * trim, y: a.y + dy / length * trim))
                    way.addLine(to: CGPoint(x: b.x - dx / length * trim, y: b.y - dy / length * trim))
                    let tint = chosen ? Theme.accent
                        : (affordable ? Theme.bone.opacity(0.42) : Theme.danger.opacity(0.30))
                    ctx.stroke(way, with: .color(tint),
                               style: StrokeStyle(lineWidth: chosen ? 4 : 2.4,
                                                  lineCap: .round, dash: chosen ? [] : [4, 4]))
                    let mid = CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
                    ctx.draw(Text("\(Int(edge.cost.rounded()))")
                                .font(.system(size: 9, weight: .semibold).monospacedDigit())
                                .foregroundStyle(chosen ? Theme.accent
                                                 : (affordable ? Theme.textDim : Theme.danger)),
                             at: mid)
                }
            }
            .frame(width: 1200, height: 1200)
            .contentShape(Rectangle())
            .onTapGesture { location in
                pendingEdge = nearestEdge(to: location, among: edges)?.link
            }
            if let pendingEdge, let edge = edges.first(where: { $0.link.id == pendingEdge.id }) {
                wayConfirmation(edge)
                    .position(x: (tilePosition(edge.link.a).x + tilePosition(edge.link.b).x) / 2,
                              y: (tilePosition(edge.link.a).y + tilePosition(edge.link.b).y) / 2 - hexSize * 0.7)
            }
        }
    }

    /// What the chosen stretch is and what it costs, with the one button that
    /// spends the money on it.
    @ViewBuilder
    private func wayConfirmation(_ edge: (link: RoadLink, cost: Double)) -> some View {
        let affordable = game.selectedSettlementStorage(.materials) >= edge.cost
        Button {
            game.layRoad(from: edge.link.a, to: edge.link.b)
            pendingEdge = nil
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "hammer.fill").font(.system(size: 9))
                Text(edge.link.grade.displayName.resolve(AppStrings.language))
                    .font(.system(size: 11, weight: .semibold))
                Image(systemName: ResourceType.materials.symbolName).font(.system(size: 9))
                Text("\(Int(edge.cost.rounded()))")
                    .font(.system(size: 11, weight: .semibold).monospacedDigit())
            }
            .foregroundStyle(affordable ? Theme.ink : Theme.textDim)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(affordable ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(Theme.surfaceRaised),
                        in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!affordable)
    }

    /// The stretch nearest the point tapped, if the tap landed near one at all.
    ///
    /// Measured to the **segment**, not to its midpoint: a long edge tapped
    /// near one end is still that edge, and picking by midpoint would hand the
    /// tap to whichever road happened to be shorter.
    private func nearestEdge(
        to point: CGPoint, among edges: [(link: RoadLink, cost: Double)]
    ) -> (link: RoadLink, cost: Double)? {
        var best: (edge: (link: RoadLink, cost: Double), distance: CGFloat)?
        for edge in edges {
            let a = tilePosition(edge.link.a), b = tilePosition(edge.link.b)
            let dx = b.x - a.x, dy = b.y - a.y
            let lengthSquared = max(0.001, dx * dx + dy * dy)
            let t = max(0, min(1, ((point.x - a.x) * dx + (point.y - a.y) * dy) / lengthSquared))
            let px = a.x + dx * t, py = a.y + dy * t
            let distance = ((point.x - px) * (point.x - px) + (point.y - py) * (point.y - py)).squareRoot()
            if best == nil || distance < best!.distance { best = (edge, distance) }
        }
        guard let best, best.distance <= hexSize * 0.45 else { return nil }
        return best.edge
    }

    /// How each grade of way is drawn.
    ///
    /// A track is a broken hairline, a road is solid, paving is heavier and
    /// warmer, and rail has its sleepers. **Condition fades the whole line**,
    /// so a network going under looks like one — the same reading
    /// `RoadLink.effectiveSpeed` gives the simulation.
    private enum RoadStyle {
        static func of(_ link: RoadLink) -> (color: Color, width: CGFloat, dash: [CGFloat]) {
            let kept = max(0.25, min(1, link.condition))
            // An ancient way is drawn as what it is: stretches of stone with
            // the country grown back over the gaps. Never as a road somebody is
            // keeping, which is what a solid line means everywhere else here.
            if link.origin == .ancient {
                return (Theme.boneFaint.opacity(0.55), 2.4, [5, 5])
            }
            switch link.grade {
            case .track: return (Theme.boneFaint.opacity(0.42 * kept), 1.1, [2, 4])
            case .road:  return (Theme.boneDim.opacity(0.62 * kept), 1.8, [])
            case .paved: return (Theme.bone.opacity(0.72 * kept), 2.6, [])
            case .rail:  return (Theme.textDim.opacity(0.78 * kept), 1.4, [])
            }
        }
    }

    /// Where a settlement's hex sits on the virtual canvas.
    private func position(ofSettlement id: UUID) -> CGPoint? {
        guard let settlement = game.world.settlements.first(where: { $0.id == id }),
              let region = game.regions.first(where: { $0.id == settlement.regionID }) else {
            return nil
        }
        return tilePosition(region.coord)
    }

    /// Halfway between two hexes' centres — where a course leaves one hex and
    /// enters the next.
    private func midpoint(_ a: HexCoord, _ b: HexCoord) -> CGPoint {
        let p = tilePosition(a), q = tilePosition(b)
        return CGPoint(x: (p.x + q.x) / 2, y: (p.y + q.y) / 2)
    }

    private func tilePosition(_ coord: HexCoord) -> CGPoint {
        let c = HexLayout.center(for: coord, size: hexSize)
        return CGPoint(x: 600 + c.x, y: 600 + c.y)
    }

    @ViewBuilder
    private func tile(_ region: Region) -> some View {
        let size = HexLayout.tileSize(for: hexSize)
        let isSelected = region.id == selectedRegionID
        let isUnknown = region.explorationState == .unknown
        let isFrontier = game.canExplore(region)

        ZStack {
            if isUnknown {
                HexTileShape().fill(Theme.surface.opacity(0.9))
                HexTileShape().fill(
                    .radialGradient(Gradient(colors: [Color.white.opacity(0.04), .clear]),
                                    center: .center, startRadius: 0, endRadius: size.width / 2)
                )
                Image(systemName: isFrontier ? "questionmark" : "circle.dotted")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(isFrontier ? Theme.accent : Theme.textDim.opacity(0.45))
            } else {
                HexTerrainView(region: region)
                hazardWash(region)
                marker(region)
                hazardPips(region)
            }

            HexTileShape()
                .stroke(strokeColor(isSelected: isSelected, isFrontier: isFrontier),
                        lineWidth: isSelected ? 3 : (isFrontier ? 2 : 1))
        }
        .frame(width: size.width, height: size.height)
        .shadow(color: isSelected ? Theme.accent.opacity(0.6) : .clear, radius: 10)
        .contentShape(HexTileShape())
        .onTapGesture { selectedRegionID = region.id }
    }

    /// Hazard rises with every ring you push out from the homeland (see
    /// `MapGenerator`), which is the spine of the whole "endless frontier"
    /// idea — going further is worth more and costs more. It was only ever a
    /// number buried in the detail panel, so the map itself couldn't tell you
    /// where the danger was. Deep tiles now darken toward red.
    @ViewBuilder
    private func hazardWash(_ region: Region) -> some View {
        let intensity = min(1, Double(region.hazardLevel) / hazardCeiling)
        if intensity > 0.01 {
            HexTileShape().fill(Theme.danger.opacity(intensity * 0.32))
        }
    }

    /// A quick read of how bad it is, without having to select the tile.
    @ViewBuilder
    private func hazardPips(_ region: Region) -> some View {
        let pips = min(4, region.hazardLevel / 2)
        if pips > 0 {
            HStack(spacing: 2) {
                ForEach(0..<pips, id: \.self) { _ in
                    Circle().fill(Theme.danger).frame(width: 3.5, height: 3.5)
                }
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(Color.black.opacity(0.35), in: Capsule())
            .offset(y: 15)
            .accessibilityLabel("\(AppStrings.language == .cs ? "Nebezpečí" : "Hazard") \(region.hazardLevel)")
        }
    }

    /// The hazard at which a tile reads as fully dangerous. Beyond this the
    /// wash simply saturates rather than going opaque and hiding the terrain.
    private let hazardCeiling: Double = 12

    @ViewBuilder
    private func marker(_ region: Region) -> some View {
        let isExpeditionTarget = game.activeExpedition?.targetRegionID == region.id
        if isExpeditionTarget {
            expeditionMarker(region)
        } else if let symbol = markerSymbol(region) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(markerTint(region))
                .padding(6)
                .background(Color.black.opacity(0.35), in: Circle())
                .shadow(color: .black.opacity(0.4), radius: 2, y: 1)
        }
    }

    /// The expedition under way: a walker with a filling ring, pulsing gently
    /// so the map's one moving thing reads as moving.
    private func expeditionMarker(_ region: Region) -> some View {
        let duration = max(1, game.expeditionDuration(for: region))
        let remaining = game.activeExpedition?.ticksRemaining ?? 0
        let progress = 1 - Double(remaining) / Double(duration)
        return TimelineView(.animation(minimumInterval: 0.25)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            Image(systemName: "figure.walk")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.white)
                .padding(6)
                .background(Color.black.opacity(0.35), in: Circle())
                .overlay(
                    Circle()
                        .trim(from: 0, to: max(0.02, progress))
                        .stroke(Theme.accent, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                )
                .scaleEffect(1 + 0.06 * sin(t * 2.4))
                .shadow(color: .black.opacity(0.4), radius: 2, y: 1)
        }
        .accessibilityLabel(AppStrings.language == .cs
                            ? "Výprava na cestě, zbývá \(remaining) tiků"
                            : "Expedition under way, \(remaining) ticks left")
    }

    private func markerSymbol(_ region: Region) -> String? {
        if game.settlement(in: region) != nil { return "house.fill" }
        // A met people's home hex carries their tent.
        if tribe(in: region) != nil { return "tent.fill" }
        return region.kind.mapSymbol
    }

    /// A neighbouring people's marker takes the colour of your standing with
    /// them — the map tells you at a glance who is a friend.
    private func markerTint(_ region: Region) -> Color {
        guard let tribe = tribe(in: region), game.settlement(in: region) == nil else { return .white }
        switch tribe.status {
        case .allied, .friendly: return Theme.good
        case .neutral: return .white
        case .tense: return Theme.accent
        case .war: return Theme.danger
        }
    }

    private func tribe(in region: Region) -> Tribe? {
        game.tribes.first { $0.regionID == region.id }
    }

    private func strokeColor(isSelected: Bool, isFrontier: Bool) -> Color {
        if isSelected { return Theme.accent }
        if isFrontier { return Theme.accent.opacity(0.6) }
        return Color.black.opacity(0.25)
    }

    // MARK: - Gestures

    private var panGesture: some Gesture {
        DragGesture()
            .onChanged { pan = CGSize(width: committedPan.width + $0.translation.width,
                                      height: committedPan.height + $0.translation.height) }
            .onEnded { _ in committedPan = pan }
    }

    private var zoomGesture: some Gesture {
        MagnifyGesture()
            .onChanged { zoom = min(max(committedZoom * $0.magnification, 0.5), 3) }
            .onEnded { _ in committedZoom = zoom }
    }
}
