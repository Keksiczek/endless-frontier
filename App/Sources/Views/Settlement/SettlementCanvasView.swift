import SwiftUI
import EndlessFrontierCore

/// The living settlement: a `TimelineView`-driven `Canvas` where colonists walk
/// their day. All motion is presentational (see `AgentMotion`); the simulation
/// underneath is untouched. Tapping a colonist selects them for the inspector.
struct SettlementCanvasView: View {
    let settlement: Settlement
    let map: LocalMap
    let registry: GameDataRegistry
    let season: Season
    @Binding var selectedPawnID: UUID?

    /// A fixed epoch so the animation clock is stable across redraws.
    @State private var start = Date()

    var body: some View {
        GeometryReader { geo in
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
                let t = timeline.date.timeIntervalSince(start)
                Canvas { context, size in
                    SettlementRenderer.draw(
                        &context, size: size, settlement: settlement, map: map,
                        registry: registry, time: t, season: season,
                        selectedPawnID: selectedPawnID)
                }
            }
            .background(Theme.ink)
            .contentShape(Rectangle())
            .gesture(
                SpatialTapGesture().onEnded { value in
                    let hit = hitTest(value.location, size: geo.size)
                    withAnimation(.easeOut(duration: 0.15)) {
                        selectedPawnID = (hit == selectedPawnID) ? nil : hit
                    }
                }
            )
        }
    }

    /// Nearest visible colonist to a tap, within a comfortable touch radius.
    private func hitTest(_ location: CGPoint, size: CGSize) -> UUID? {
        let rect = CGRect(origin: .zero, size: size)
        let t = Date().timeIntervalSince(start)
        var best: UUID?
        var bestDistance = touchRadius * touchRadius
        for pawn in settlement.pawns.prefix(SettlementRenderer.maxVisibleAgents) {
            let pos = AgentMotion.position(for: pawn, map: map, time: t)
            guard map.isExplored(pos) else { continue }
            let p = SettlementRenderer.point(pos, in: rect)
            let dx = p.x - location.x, dy = p.y - location.y
            let d2 = dx * dx + dy * dy
            if d2 < bestDistance {
                bestDistance = d2
                best = pawn.id
            }
        }
        return best
    }

    private let touchRadius: CGFloat = 22
}
