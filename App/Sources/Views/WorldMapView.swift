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
        }
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
            HexTileShape()
                .fill(isUnknown ? Theme.surface.opacity(0.85) : BiomePalette.color(region.biomeID))
            HexTileShape()
                .stroke(strokeColor(isSelected: isSelected, isFrontier: isFrontier),
                        lineWidth: isSelected ? 3 : (isFrontier ? 2 : 1))

            if isUnknown {
                Image(systemName: isFrontier ? "questionmark" : "circle.dotted")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(isFrontier ? Theme.accent : Theme.textDim.opacity(0.5))
            } else {
                marker(region)
            }
        }
        .frame(width: size.width, height: size.height)
        .contentShape(HexTileShape())
        .onTapGesture { selectedRegionID = region.id }
    }

    @ViewBuilder
    private func marker(_ region: Region) -> some View {
        let isExpeditionTarget = game.activeExpedition?.targetRegionID == region.id
        VStack(spacing: 2) {
            if game.settlement(in: region) != nil {
                Image(systemName: "house.fill").foregroundStyle(.white)
            } else if isExpeditionTarget {
                Image(systemName: "figure.walk").foregroundStyle(.white)
            } else if let symbol = region.kind.mapSymbol {
                Image(systemName: symbol).foregroundStyle(.white.opacity(0.9))
            }
        }
        .font(.system(size: 15, weight: .semibold))
        .shadow(radius: 1)
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
        MagnificationGesture()
            .onChanged { zoom = min(max(committedZoom * $0, 0.5), 3) }
            .onEnded { _ in committedZoom = zoom }
    }
}
