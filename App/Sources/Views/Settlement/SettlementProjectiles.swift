import SwiftUI
import EndlessFrontierCore

/// What a shot looks like crossing the ground.
///
/// **Every weapon in the game fired the same thing.** Six bone-coloured shafts,
/// fixed spread, one line width — whether the colony was loosing arrows off a
/// palisade or putting rifle fire into a warband three eras later. Fifty-eight
/// weapons, one picture. Keks: *"at ma kazda zbran unikat, pistol strili mensi
/// nez sniper"*.
///
/// Composed rather than drawn, for the same reason `SettlementConveyances` is:
/// there will be a great many weapons, and the difference between them has to
/// come out of what they *are* — `ProjectileKind`, `caliber`, `shots`, the
/// distance the shot actually crossed — so a weapon generated next month
/// arrives already looking like itself.
///
/// Presentation only. The Core decides who shot whom and for how much; this
/// decides nothing at all.
enum SettlementProjectiles {

    /// One volley, drawn as whatever it was fired from.
    ///
    /// - `flight`: 0 at the loose, 1 at the landing.
    /// - `from` / `to`: the two ends the Core recorded. A shot with no origin
    ///   in the record is an old save, and is drawn from a little way back
    ///   along its own line rather than from nowhere.
    static func draw(
        _ context: inout GraphicsContext, rect: CGRect,
        kind: ProjectileKind, from: LocalPoint, to: LocalPoint,
        flight: Double, fade: Double, zoom: CGFloat,
        caliber: Double = 1, shots: Int = 1, seed: UInt64 = 0
    ) {
        guard kind != .none else { return }
        let unit = min(rect.width, rect.height)
        let size = max(0.6, zoom * CGFloat(caliber))
        // A beam is not a thing in flight — it is a line that exists for an
        // instant. Drawn whole and faded, rather than travelled.
        if kind == .beam {
            beam(&context, rect: rect, from: from, to: to,
                 fade: fade, size: size)
            return
        }

        // The axis, and the perpendicular the spread is measured along.
        let dx = to.x - from.x, dy = to.y - from.y
        let span = max(0.0001, (dx * dx + dy * dy).squareRoot())
        let nx = -dy / span, ny = dx / span

        let count = max(1, min(12, shots))
        for i in 0..<count {
            // Fired together, arriving in a ragged rank. The stagger is per
            // shot rather than per frame, so the fan travels instead of
            // standing still and fading — which is what it used to do.
            let stagger = Double(i) * (kind == .bullet || kind == .shot ? 0.02 : 0.05)
            let t = min(1, max(0, flight * 1.15 - stagger))
            guard t > 0 else { continue }
            let offset = wobble(seed: seed &+ UInt64(i), index: i, count: count)
                * spreadOf(kind)
            let a = LocalPoint(x: from.x + nx * offset, y: from.y + ny * offset)
            let b = LocalPoint(x: to.x + nx * offset, y: to.y + ny * offset)
            let head = point(along: a, b, t: t, kind: kind, rect: rect)
            let tail = point(along: a, b, t: max(0, t - tailOf(kind)),
                             kind: kind, rect: rect)

            switch kind {
            case .none, .beam:
                break
            case .arrow, .bolt, .dart:
                shaft(&context, from: tail, to: head, fade: fade,
                      size: size * (kind == .bolt ? 1.3 : 1), colour: Theme.bone)
            case .stone:
                pellet(&context, at: head, r: size * 0.9, fade: fade,
                       colour: Theme.boneDim)
            case .ball:
                pellet(&context, at: head, r: size * 1.2, fade: fade, colour: Theme.bone)
                // Black powder: the smoke is most of what a musket looks like.
                smoke(&context, at: point(along: a, b, t: 0, kind: kind, rect: rect),
                      spread: unit * 0.012 * CGFloat(caliber), fade: fade, age: t)
            case .bullet:
                // Small, and mostly a streak: what you see is where it was.
                shaft(&context, from: tail, to: head, fade: fade * 0.9,
                      size: size * 0.6, colour: Theme.accent.opacity(0.9))
            case .shot:
                pellet(&context, at: head, r: size * 0.45, fade: fade,
                       colour: Theme.boneDim)
            case .shell, .grenade, .rocket:
                pellet(&context, at: head, r: size * 1.1, fade: fade, colour: Theme.bone)
                if kind == .rocket {
                    trail(&context, from: tail, to: head, fade: fade, size: size)
                }
            }
        }

        // What goes off when it arrives. Drawn at the landing and only in the
        // last of the flight, so it is the arrival that bursts rather than the
        // shot carrying a ball of fire the whole way.
        if kind.bursts, flight > 0.85 {
            burst(&context, at: SettlementRenderer.point(to, in: rect),
                  r: unit * 0.014 * CGFloat(max(1, caliber)) * CGFloat(flight),
                  fade: fade)
        }
    }

    // MARK: - The pieces

    /// Where a shot is at `t`, with an arc on the kinds that arc.
    private static func point(
        along a: LocalPoint, _ b: LocalPoint, t: Double,
        kind: ProjectileKind, rect: CGRect
    ) -> CGPoint {
        var p = SettlementRenderer.point(
            LocalPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t), in: rect)
        guard kind.arcs else { return p }
        // A lob: highest in the middle, and higher the further it is thrown.
        let reach = ((b.x - a.x) * (b.x - a.x) + (b.y - a.y) * (b.y - a.y)).squareRoot()
        let rise = min(rect.height, rect.width) * CGFloat(reach) * 0.45
        p.y -= CGFloat(4 * t * (1 - t)) * rise
        return p
    }

    private static func shaft(
        _ context: inout GraphicsContext, from: CGPoint, to: CGPoint,
        fade: Double, size: CGFloat, colour: Color
    ) {
        context.stroke(Path { p in
            p.move(to: from)
            p.addLine(to: to)
        }, with: .color(colour.opacity(0.78 * fade)),
           style: StrokeStyle(lineWidth: size, lineCap: .round))
    }

    private static func pellet(
        _ context: inout GraphicsContext, at c: CGPoint, r: CGFloat,
        fade: Double, colour: Color
    ) {
        context.fill(
            Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)),
            with: .color(colour.opacity(0.8 * fade)))
    }

    private static func beam(
        _ context: inout GraphicsContext, rect: CGRect,
        from: LocalPoint, to: LocalPoint, fade: Double, size: CGFloat
    ) {
        let a = SettlementRenderer.point(from, in: rect)
        let b = SettlementRenderer.point(to, in: rect)
        // Two strokes: a wide dim one for the bloom, a thin bright one for the
        // line itself. Cheaper than a gradient and reads better small.
        context.stroke(Path { p in p.move(to: a); p.addLine(to: b) },
                       with: .color(Theme.accent.opacity(0.22 * fade)),
                       style: StrokeStyle(lineWidth: size * 3.2, lineCap: .round))
        context.stroke(Path { p in p.move(to: a); p.addLine(to: b) },
                       with: .color(Theme.bone.opacity(0.9 * fade)),
                       style: StrokeStyle(lineWidth: size * 0.7, lineCap: .round))
    }

    private static func trail(
        _ context: inout GraphicsContext, from: CGPoint, to: CGPoint,
        fade: Double, size: CGFloat
    ) {
        context.stroke(Path { p in
            p.move(to: from)
            p.addLine(to: to)
        }, with: .color(Theme.boneDim.opacity(0.35 * fade)),
           style: StrokeStyle(lineWidth: size * 2.2, lineCap: .round))
    }

    private static func smoke(
        _ context: inout GraphicsContext, at c: CGPoint, spread: CGFloat,
        fade: Double, age: Double
    ) {
        let r = spread * CGFloat(0.6 + age * 1.6)
        context.fill(
            Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)),
            with: .color(Theme.boneDim.opacity(0.22 * fade * (1 - age))))
    }

    private static func burst(
        _ context: inout GraphicsContext, at c: CGPoint, r: CGFloat, fade: Double
    ) {
        context.fill(
            Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)),
            with: .radialGradient(
                Gradient(colors: [Theme.accent.opacity(0.75 * fade), .clear]),
                center: c, startRadius: 0, endRadius: r))
        context.stroke(
            Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)),
            with: .color(Theme.accent.opacity(0.5 * fade)), lineWidth: 1)
    }

    // MARK: - How wide it goes

    /// How far off the line one kind wanders, as a fraction of the map. This is
    /// the other half of "a pistol is not a sniper": a smoothbore throws its
    /// shot about, a rifle does not, and a beam cannot.
    static func spreadOf(_ kind: ProjectileKind) -> Double {
        switch kind {
        case .none, .beam:      return 0
        case .bullet:           return 0.006
        case .bolt, .dart:      return 0.010
        case .arrow:            return 0.014
        case .ball, .rocket:    return 0.016
        case .stone, .grenade:  return 0.020
        case .shot, .shell:     return 0.028
        }
    }

    /// How long a shot is drawn, as a fraction of its own flight.
    private static func tailOf(_ kind: ProjectileKind) -> Double {
        switch kind {
        case .bullet:      return 0.14
        case .arrow, .bolt: return 0.06
        case .rocket:      return 0.10
        default:           return 0.04
        }
    }

    /// A shot's own place in the fan, −1…1, spread across however many there
    /// are and jittered from the seed so two volleys are not one drawing twice.
    private static func wobble(seed: UInt64, index: Int, count: Int) -> Double {
        let middle = Double(count - 1) / 2
        let place = count == 1 ? 0 : (Double(index) - middle) / max(1, middle)
        let h = (seed &* 0x9E37_79B9_7F4A_7C15) >> 33
        return place + (Double(h & 0xFFFF) / 65535 - 0.5) * 0.35
    }
}
