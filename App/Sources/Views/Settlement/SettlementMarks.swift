import SwiftUI
import EndlessFrontierCore

/// **What the player has pointed at, drawn on the ground.**
///
/// A mark you cannot see is a mark you do not believe in: you tap a tree, the
/// card says *marked for felling*, and then the valley looks exactly as it did
/// before. So every standing `Designation` gets a ring over the thing it
/// points at, and the ring is drawn from the same list the engines read — the
/// drawing cannot disagree with the order.
///
/// Presentation only. Nothing here writes anything (rule: the canvas never
/// feeds the simulation).
enum SettlementMarks {

    /// Drawn over the world layers and under the people, so a colonist walking
    /// past a marked tree is in front of the ring.
    static func draw(
        _ context: inout GraphicsContext, rect: CGRect, settlement: Settlement,
        map: LocalMap, time: Double, zoom: CGFloat
    ) {
        guard !settlement.designations.isEmpty else { return }
        // A slow pulse, so a mark reads as *asked for* rather than as part of
        // the scenery. One phase for all of them: marks blinking out of step
        // look like a fault.
        let pulse = 0.55 + 0.25 * sin(time * 1.6)
        let radius = max(5, 9 * zoom)

        for mark in settlement.designations {
            guard let position = position(of: mark.target, in: map, settlement: settlement),
                  map.isExplored(position) else { continue }
            let p = SettlementRenderer.point(position, in: rect)
            let ring = CGRect(x: p.x - radius, y: p.y - radius,
                              width: radius * 2, height: radius * 2)
            context.stroke(Path(ellipseIn: ring),
                           with: .color(Theme.accent.opacity(pulse)),
                           style: StrokeStyle(lineWidth: 1.4, dash: [3, 2.5]))
            glyph(&context, kind: mark.kind, at: p, radius: radius, opacity: pulse)
        }
    }

    /// Where the marked thing is standing *now* — read live, because a heap
    /// that is being carried in has moved and a beast walks.
    private static func position(
        of target: Designation.Target, in map: LocalMap, settlement: Settlement
    ) -> LocalPoint? {
        switch target {
        case .tree(let id): return map.trees.first { $0.id == id }?.position
        case .rock(let id): return map.rocks.first { $0.id == id }?.position
        case .pile(let id): return map.piles.first { $0.id == id }?.position
        case .animal(let id): return map.wildlife.animals.first { $0.id == id }?.position
        }
    }

    /// A stroke inside the ring saying what was asked: an axe cut, a broken
    /// line for the pick, an arrow in for hauling, a cross-hair for the hunt.
    private static func glyph(
        _ context: inout GraphicsContext, kind: Designation.Kind,
        at p: CGPoint, radius: CGFloat, opacity: Double
    ) {
        let colour = GraphicsContext.Shading.color(Theme.accent.opacity(opacity))
        let r = radius * 0.55
        switch kind {
        case .fell:
            context.stroke(Path { path in
                path.move(to: CGPoint(x: p.x - r, y: p.y + r))
                path.addLine(to: CGPoint(x: p.x + r, y: p.y - r))
            }, with: colour, lineWidth: 1.6)
        case .mine:
            context.stroke(Path { path in
                path.move(to: CGPoint(x: p.x - r, y: p.y))
                path.addLine(to: CGPoint(x: p.x, y: p.y - r * 0.6))
                path.addLine(to: CGPoint(x: p.x + r, y: p.y))
            }, with: colour, lineWidth: 1.6)
        case .haul:
            context.stroke(Path { path in
                path.move(to: CGPoint(x: p.x, y: p.y - r))
                path.addLine(to: CGPoint(x: p.x, y: p.y + r))
                path.move(to: CGPoint(x: p.x - r * 0.5, y: p.y + r * 0.4))
                path.addLine(to: CGPoint(x: p.x, y: p.y + r))
                path.addLine(to: CGPoint(x: p.x + r * 0.5, y: p.y + r * 0.4))
            }, with: colour, lineWidth: 1.4)
        case .hunt:
            context.stroke(Path { path in
                path.move(to: CGPoint(x: p.x - r, y: p.y))
                path.addLine(to: CGPoint(x: p.x + r, y: p.y))
                path.move(to: CGPoint(x: p.x, y: p.y - r))
                path.addLine(to: CGPoint(x: p.x, y: p.y + r))
            }, with: colour, lineWidth: 1.2)
        }
    }
}
