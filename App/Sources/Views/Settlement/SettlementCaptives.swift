import SwiftUI
import EndlessFrontierCore

/// **The prisoners, who were in the save and nowhere on the screen.**
///
/// A raid that breaks against the wall leaves people on the ground who are not
/// dead, and `CaptiveEngine` has kept them — a whole `Pawn` each, with a name,
/// an age, a trade and a `trust` that walks from *out the gate the first dark
/// night* to *one of us* — since the day it was written. The canvas drew none
/// of them, no panel listed them, and the only sign a colony had prisoners at
/// all was a line in the journal on the day one joined.
///
/// That is the same fault as the roads (drawn on the world map, missing from
/// the valley) and as the marks before `SettlementMarks`: **the simulation
/// having a thing is not the same as the game having it.**
///
/// They are drawn apart from the colonists on purpose — a knot of people at
/// the edge of the yard, not mixed into the crowd — because that is exactly
/// what they are: in the settlement, not of it. Presentation only; nothing
/// here writes state, and their positions are derived, never stored.
enum SettlementCaptives {

    /// How far from the heart of the colony they are held, in map units.
    static let holdReach = 0.17

    /// Where each captive stands. Derived from their id, so a prisoner does
    /// not wander the yard between frames, and clustered so a colony holding
    /// four has a knot of four rather than four people scattered about.
    static func position(_ captive: Captive, index: Int, count: Int, heart: LocalPoint) -> LocalPoint {
        let turn = Double(index) / Double(max(1, count)) * 2 * .pi
        // A little unevenness off the id, or four prisoners stand on a perfect
        // circle like a diagram.
        let jitter = Double(hash(captive.id) % 997) / 997 * 0.04 - 0.02
        return LocalPoint(x: heart.x + cos(turn) * (holdReach + jitter),
                          y: heart.y + sin(turn) * (holdReach * 0.7 + jitter))
    }

    static func draw(
        _ context: inout GraphicsContext, rect: CGRect, settlement: Settlement,
        map: LocalMap, registry: GameDataRegistry, time: Double, zoom: CGFloat,
        ticksPerYear: Int, selected: UUID?
    ) {
        guard !settlement.captives.isEmpty else { return }
        let heart = SettlementGeometry.heart
        for (index, captive) in settlement.captives.enumerated() {
            let where_ = position(captive, index: index,
                                  count: settlement.captives.count, heart: heart)
            guard map.isExplored(where_) else { continue }
            let at = SettlementRenderer.point(where_, in: rect)
            // A prisoner stands; they are not at work and they are not walking
            // a day. `AgentMotion` is for people with somewhere to be.
            let pose = AgentMotion.Pose(position: where_, activity: .resting,
                                        stride: 0, facing: 1)
            SettlementFigures.draw(
                pawn: captive.pawn, pose: pose, at: at,
                time: time, ticksPerYear: ticksPerYear,
                selected: captive.id == selected, zoom: zoom,
                context: &context)
            ring(&context, at: at, trust: captive.trust, zoom: zoom, time: time)
        }
    }

    /// The one thing about a prisoner worth reading from across the valley:
    /// how far round they have come. Red at the gate, gold when they are
    /// nearly one of you.
    private static func ring(
        _ context: inout GraphicsContext, at p: CGPoint,
        trust: Double, zoom: CGFloat, time: Double
    ) {
        let r = max(4, 7 * zoom)
        let share = min(1, max(0, (trust + 1) / 2))
        let colour = Color(
            red: 0.85 - 0.35 * share, green: 0.35 + 0.4 * share, blue: 0.25 + 0.1 * share)
        let base = CGRect(x: p.x - r, y: p.y - r * 2.4, width: r * 2, height: r * 2)
        context.stroke(Path(ellipseIn: base), with: .color(colour.opacity(0.8)),
                       style: StrokeStyle(lineWidth: 1.2, dash: [2.5, 2]))
    }

    /// The same cheap stable hash the rest of the canvas uses for a UUID.
    static func hash(_ id: UUID) -> UInt64 {
        let u = id.uuid
        var h: UInt64 = 0xCBF2_9CE4_8422_2325
        for byte in [u.0, u.1, u.2, u.3, u.4, u.5, u.6, u.7] {
            h = (h ^ UInt64(byte)) &* 0x0100_0000_01B3
        }
        return h
    }
}
