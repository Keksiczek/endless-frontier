import SwiftUI
import EndlessFrontierCore

/// Plays a battle out on the canvas.
///
/// The simulation settles a raid inside one whole tick and always did — what
/// was missing was any way to *see* it happen. `BattleLog` records the order
/// and timing of the beats; this walks that record against the frame clock, so
/// a raid arrives, breaks on the wall, and costs someone, in front of the
/// player rather than in a line of journal text after the fact.
///
/// Strictly presentational: it reads `settlement.lastBattle` and nothing here
/// ever writes back. A player who looks away misses the show, not the outcome.
enum SettlementBattle {
    /// How long after its tick a battle stays on screen. A tick is a real
    /// minute; the fight itself plays over the tick and then the field clears.
    static let lingerTicks: Double = 0.35

    /// Where the attackers come from — a fixed bearing per battle, so a raid
    /// does not swing around the map while you watch it.
    private static func approach(_ log: BattleLog) -> LocalPoint {
        let angle = Double(abs(log.id.hashValue % 360)) * .pi / 180
        return LocalPoint(x: 0.5 + cos(angle) * 0.46, y: 0.5 + sin(angle) * 0.44)
    }

    /// Draws the battle happening at `continuousTick`, if one is.
    static func draw(
        _ context: inout GraphicsContext, rect: CGRect, settlement: Settlement,
        continuousTick: Double, time: Double, zoom: CGFloat
    ) {
        guard let log = settlement.lastBattle else { return }
        let elapsed = continuousTick - Double(log.tick)
        guard elapsed >= 0, elapsed <= 1 + lingerTicks else { return }
        let progress = min(1, elapsed)

        let heart = SettlementRenderer.point(SettlementRenderer.colonyHeart, in: rect)
        let from = SettlementRenderer.point(approach(log), in: rect)
        let unit = min(rect.width, rect.height)
        let played = log.moments(upTo: progress)

        // The band closes on the settlement as the fight runs, and is pushed
        // back out again once it breaks.
        let closing = log.repelled ? min(1, progress * 2) : progress
        let advance = log.repelled && progress > 0.5
            ? 1 - (progress - 0.5) * 1.6
            : closing
        band(&context, from: from, to: heart, advance: max(0, advance),
             unit: unit, zoom: zoom, time: time)

        for moment in played {
            let age = progress - moment.at
            guard age >= 0, age < 0.35 else { continue }
            let fade = 1 - age / 0.35
            switch moment.kind {
            case .volley:
                volley(&context, from: heart, to: from, fade: fade, unit: unit, zoom: zoom)
            case .clash, .charge:
                flash(&context, at: midpoint(from, heart, t: 0.72), fade: fade,
                      unit: unit, tint: Theme.danger)
            case .wound, .death:
                flash(&context, at: heart, fade: fade, unit: unit,
                      tint: moment.kind == .death ? Theme.danger : Theme.accent)
            case .plunder:
                flash(&context, at: midpoint(from, heart, t: 0.4), fade: fade,
                      unit: unit, tint: Theme.textDim)
            case .repelled:
                ring(&context, at: heart, fade: fade, unit: unit)
            }
        }
    }

    /// The attacking band: a scatter of marks advancing along the road in.
    private static func band(
        _ context: inout GraphicsContext, from: CGPoint, to: CGPoint,
        advance: Double, unit: CGFloat, zoom: CGFloat, time: Double
    ) {
        let stop = 0.78 * advance
        for i in 0..<7 {
            let lane = (Double(i % 3) - 1) * 0.03
            let stagger = Double(i) * 0.012
            let t = max(0, stop - stagger)
            var p = midpoint(from, to, t: t)
            // A little sideways scatter so it reads as a crowd, not a column.
            p.x += CGFloat(lane) * unit * 0.5
            p.y += CGFloat(sin(time * 2 + Double(i)) * 0.004) * unit
            let r = unit * 0.007 * zoom
            context.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)),
                         with: .color(Theme.danger.opacity(0.75)))
        }
    }

    /// Arrows loosed from the wall, back down the road.
    private static func volley(
        _ context: inout GraphicsContext, from: CGPoint, to: CGPoint,
        fade: Double, unit: CGFloat, zoom: CGFloat
    ) {
        for i in 0..<5 {
            let t = 0.2 + Double(i) * 0.11
            let a = midpoint(from, to, t: t)
            let b = midpoint(from, to, t: t + 0.05)
            context.stroke(Path { p in
                p.move(to: a)
                p.addLine(to: b)
            }, with: .color(Theme.bone.opacity(0.7 * fade)), lineWidth: 1 * zoom)
        }
    }

    private static func flash(
        _ context: inout GraphicsContext, at point: CGPoint, fade: Double,
        unit: CGFloat, tint: Color
    ) {
        let r = unit * (0.012 + 0.02 * (1 - fade))
        context.stroke(
            Path(ellipseIn: CGRect(x: point.x - r, y: point.y - r, width: r * 2, height: r * 2)),
            with: .color(tint.opacity(0.8 * fade)), lineWidth: 1.4)
    }

    private static func ring(
        _ context: inout GraphicsContext, at point: CGPoint, fade: Double, unit: CGFloat
    ) {
        let r = unit * (0.05 + 0.06 * (1 - fade))
        context.stroke(
            Path(ellipseIn: CGRect(x: point.x - r, y: point.y - r, width: r * 2, height: r * 2)),
            with: .color(Theme.good.opacity(0.7 * fade)), lineWidth: 1.6)
    }

    private static func midpoint(_ a: CGPoint, _ b: CGPoint, t: Double) -> CGPoint {
        CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
    }
}
