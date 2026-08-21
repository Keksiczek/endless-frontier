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
                for link in game.world.roads.all {
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

    /// How each grade of way is drawn.
    ///
    /// A track is a broken hairline, a road is solid, paving is heavier and
    /// warmer, and rail has its sleepers. **Condition fades the whole line**,
    /// so a network going under looks like one — the same reading
    /// `RoadLink.effectiveSpeed` gives the simulation.
    private enum RoadStyle {
        static func of(_ link: RoadLink) -> (color: Color, width: CGFloat, dash: [CGFloat]) {
            let kept = max(0.25, min(1, link.condition))
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
