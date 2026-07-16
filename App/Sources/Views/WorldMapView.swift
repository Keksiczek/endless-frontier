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
        }
        // Centre the origin in a large virtual canvas.
        .frame(width: 1200, height: 1200)
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
        if let symbol = markerSymbol(region, isExpeditionTarget: isExpeditionTarget) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.white)
                .padding(6)
                .background(Color.black.opacity(0.35), in: Circle())
                .shadow(color: .black.opacity(0.4), radius: 2, y: 1)
        }
    }

    private func markerSymbol(_ region: Region, isExpeditionTarget: Bool) -> String? {
        if game.settlement(in: region) != nil { return "house.fill" }
        if isExpeditionTarget { return "figure.walk" }
        return region.kind.mapSymbol
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
