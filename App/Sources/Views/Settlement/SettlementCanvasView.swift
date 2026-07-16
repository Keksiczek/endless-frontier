import SwiftUI
import EndlessFrontierCore

/// What the viewer currently has picked out of the scene. A tap lands on
/// whatever is nearest — a colonist walking past or the building behind them —
/// so the two selections are one choice, not two competing ones.
///
/// A building selection carries its `definitionID` as well as its layout index:
/// the index is what the renderer rings, but it only means anything next to the
/// layout's sort order, and the screen showing the inspector has no rect to
/// recompute that from.
enum CanvasSelection: Equatable {
    case none
    case pawn(UUID)
    case building(index: Int, definitionID: String)
}

/// The living settlement: a `TimelineView`-driven `Canvas` where colonists walk
/// their day. All motion is presentational (see `AgentMotion`); the simulation
/// underneath is untouched. Pinch to zoom, drag to pan, tap to inspect a
/// colonist or a building.
struct SettlementCanvasView: View {
    let settlement: Settlement
    let map: LocalMap
    let registry: GameDataRegistry
    let season: Season
    @Binding var selection: CanvasSelection

    /// A fixed epoch so the animation clock is stable across redraws.
    @State private var start = Date()
    @State private var camera = SettlementRenderer.Camera()
    /// The camera as it was when the current gesture began, so pinch and drag
    /// compose from a fixed base instead of accumulating drift.
    @State private var gestureBase = SettlementRenderer.Camera()

    var body: some View {
        GeometryReader { geo in
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
                let t = timeline.date.timeIntervalSince(start)
                Canvas { context, size in
                    SettlementRenderer.draw(
                        &context, size: size, settlement: settlement, map: map,
                        registry: registry, time: t, season: season,
                        camera: camera,
                        selectedPawnID: selectedPawnID,
                        selectedBuildingID: selectedBuildingID)
                }
            }
            .background(Theme.ink)
            .contentShape(Rectangle())
            .gesture(pan(in: geo.size).simultaneously(with: zoom))
            .gesture(tap(in: geo.size))
            .overlay(alignment: .bottomTrailing) { zoomChrome }
            .accessibilityLabel(AppStrings.language == .cs
                                ? "Živá osada. Přiblížení \(Int(camera.scale * 100)) procent."
                                : "The living settlement. Zoom \(Int(camera.scale * 100)) percent.")
        }
    }

    private var selectedPawnID: UUID? {
        if case let .pawn(id) = selection { return id }
        return nil
    }

    private var selectedBuildingID: Int? {
        if case let .building(index, _) = selection { return index }
        return nil
    }

    // MARK: - Gestures

    private func tap(in size: CGSize) -> some Gesture {
        SpatialTapGesture().onEnded { value in
            let hit = hitTest(value.location, size: size)
            withAnimation(.easeOut(duration: 0.15)) {
                selection = (hit == selection) ? .none : hit
            }
        }
    }

    private func pan(in size: CGSize) -> some Gesture {
        DragGesture()
            .onChanged { value in
                camera.offset = CGSize(
                    width: gestureBase.offset.width + value.translation.width,
                    height: gestureBase.offset.height + value.translation.height)
                camera = clamped(camera, in: size)
            }
            .onEnded { _ in gestureBase = camera }
    }

    private var zoom: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                camera.scale = min(SettlementRenderer.Camera.maxScale,
                                   max(SettlementRenderer.Camera.minScale,
                                       gestureBase.scale * value.magnification))
            }
            .onEnded { _ in gestureBase = camera }
    }

    /// Keeps the world from being dragged off-screen: at 1× there is nothing to
    /// pan, and further in you can only travel as far as the overhang.
    private func clamped(_ camera: SettlementRenderer.Camera, in size: CGSize) -> SettlementRenderer.Camera {
        var c = camera
        let slackX = max(0, size.width * (c.scale - 1) / 2)
        let slackY = max(0, size.height * (c.scale - 1) / 2)
        c.offset.width = min(slackX, max(-slackX, c.offset.width))
        c.offset.height = min(slackY, max(-slackY, c.offset.height))
        return c
    }

    // MARK: - Chrome

    @ViewBuilder
    private var zoomChrome: some View {
        if camera.scale > SettlementRenderer.Camera.minScale + 0.01 {
            Button {
                withAnimation(.easeOut(duration: 0.25)) {
                    camera = SettlementRenderer.Camera()
                    gestureBase = camera
                }
            } label: {
                Label("\(Int(camera.scale * 100))%", systemImage: "arrow.down.right.and.arrow.up.left")
                    .font(.caption2.weight(.semibold).monospacedDigit())
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial, in: Capsule())
            }
            .tint(Theme.text)
            .padding(12)
            .transition(.opacity)
            .accessibilityLabel(AppStrings.language == .cs ? "Oddálit zpět" : "Reset zoom")
        }
    }

    // MARK: - Hit testing

    /// Nearest thing to a tap: a walking colonist wins over a building when
    /// both are in reach, since they're what the eye was following.
    private func hitTest(_ location: CGPoint, size: CGSize) -> CanvasSelection {
        let viewRect = CGRect(origin: .zero, size: size)
        let rect = SettlementRenderer.worldRect(viewRect: viewRect, camera: camera)
        let t = Date().timeIntervalSince(start)

        var best: CanvasSelection = .none
        var bestDistance = touchRadius * touchRadius
        for pawn in settlement.pawns.prefix(SettlementRenderer.maxVisibleAgents) {
            let pos = AgentMotion.position(for: pawn, map: map, time: t)
            guard map.isExplored(pos) else { continue }
            let p = SettlementRenderer.point(pos, in: rect)
            let d2 = distanceSquared(p, location)
            if d2 < bestDistance {
                bestDistance = d2
                best = .pawn(pawn.id)
            }
        }
        if case .pawn = best { return best }

        for building in SettlementRenderer.layout(settlement: settlement, registry: registry, rect: rect) {
            let d2 = distanceSquared(building.center, location)
            if d2 < bestDistance {
                bestDistance = d2
                best = .building(index: building.id, definitionID: building.definitionID)
            }
        }
        return best
    }

    private func distanceSquared(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = a.x - b.x, dy = a.y - b.y
        return dx * dx + dy * dy
    }

    private var touchRadius: CGFloat { 22 }
}
