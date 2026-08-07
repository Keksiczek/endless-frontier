import SwiftUI
import EndlessFrontierCore

/// The world beyond the valley, walking in.
///
/// Trade and diplomacy were a panel — numbers moved, a journal line appeared,
/// and nobody ever set foot on the map except raiders. A visiting party is the
/// same trade and the same diplomacy with somebody attached to it: traders with
/// mules coming up the road, an envoy with a retinue, families out of a colony
/// that had a worse winter than yours.
///
/// You can tell them apart from across the valley without reading anything —
/// the traders have pack animals, the envoy carries a standard, the refugees
/// carry what they have left — which is the whole point of putting them on the
/// ground instead of in a list.
///
/// Purely presentational; everything comes off `LocalMap.visitors`.
enum SettlementVisitors {

    static func draw(
        _ context: inout GraphicsContext, rect: CGRect, map: LocalMap,
        time: Double, zoom: CGFloat, showLabels: Bool
    ) {
        for visitor in map.visitors {
            guard map.isExplored(visitor.position) else { continue }
            let at = SettlementRenderer.point(visitor.position, in: rect)
            party(&context, visitor, at: at, time: time, zoom: zoom)
            guard showLabels else { continue }
            let caption = Text(visitor.kind.displayName.resolve(AppStrings.language))
                .font(.system(size: 6, weight: .medium))
                .foregroundStyle(tint(visitor.kind).opacity(0.9))
            context.draw(context.resolve(caption),
                         at: CGPoint(x: at.x, y: at.y - 11 * zoom))
        }
    }

    /// A party of outsiders: a few figures abreast, and whatever they brought.
    private static func party(
        _ context: inout GraphicsContext, _ visitor: Visitor, at c: CGPoint,
        time: Double, zoom: CGFloat
    ) {
        let colour = tint(visitor.kind)
        let s = 3.6 * zoom
        let walking = visitor.phase != .visiting
        let phase = Double(visitor.id.uuidString.hashValue % 1000) / 1000 * 6.28

        // Pack animals first, so the people walk in front of them.
        if visitor.kind.hasPackAnimals {
            for i in 0..<2 {
                let p = CGPoint(x: c.x - s * (1.9 + CGFloat(i) * 1.3),
                                y: c.y + s * (0.25 - CGFloat(i) * 0.35))
                mule(&context, at: p, s: s, colour: colour, time: time,
                     phase: phase + Double(i), walking: walking)
            }
        }

        for i in 0..<visitor.kind.partySize {
            let spread = (CGFloat(i) - CGFloat(visitor.kind.partySize - 1) / 2)
            let p = CGPoint(x: c.x + spread * s * 0.95,
                            y: c.y + CGFloat(sin(Double(i) * 2.1)) * s * 0.28)
            figure(&context, at: p, s: s, colour: colour, time: time,
                   phase: phase + Double(i) * 0.7, walking: walking,
                   burdened: visitor.kind == .refugee)
        }

        // What they came under: a standard for an envoy, so a delegation reads
        // as a delegation and not as four more colonists.
        if visitor.kind == .envoy {
            let pole = CGPoint(x: c.x + s * 1.9, y: c.y)
            context.stroke(Path { p in
                p.move(to: CGPoint(x: pole.x, y: pole.y + s * 0.9))
                p.addLine(to: CGPoint(x: pole.x, y: pole.y - s * 2.4))
            }, with: .color(Theme.boneDim.opacity(0.9)), lineWidth: max(0.7, zoom * 0.6))
            let wave = CGFloat(sin(time * 2.2 + phase)) * s * 0.18
            context.fill(Path { p in
                p.move(to: CGPoint(x: pole.x, y: pole.y - s * 2.4))
                p.addLine(to: CGPoint(x: pole.x + s * 1.2 + wave, y: pole.y - s * 2.0))
                p.addLine(to: CGPoint(x: pole.x, y: pole.y - s * 1.55))
                p.closeSubpath()
            }, with: .color(colour.opacity(0.85)))
        }
    }

    /// One outsider — deliberately the same read as a colonist, in a stranger's
    /// colour, so a crowd of them stands out without looking like another game.
    private static func figure(
        _ context: inout GraphicsContext, at p: CGPoint, s: CGFloat, colour: Color,
        time: Double, phase: Double, walking: Bool, burdened: Bool
    ) {
        let gait = walking ? CGFloat(sin(time * 5 + phase)) * s * 0.32 : 0

        context.fill(Path(ellipseIn: CGRect(x: p.x - s * 0.45, y: p.y + s * 0.85,
                                            width: s * 0.9, height: s * 0.3)),
                     with: .color(.black.opacity(0.24)))
        // Head.
        context.fill(Path(ellipseIn: CGRect(x: p.x - s * 0.28, y: p.y - s * 1.15,
                                            width: s * 0.56, height: s * 0.56)),
                     with: .color(Color(red: 0.82, green: 0.74, blue: 0.62)))
        // Cloak and legs.
        var frame = Path()
        frame.move(to: CGPoint(x: p.x, y: p.y - s * 0.6))
        frame.addLine(to: CGPoint(x: p.x, y: p.y + s * 0.25))
        frame.move(to: CGPoint(x: p.x - s * 0.3 + gait, y: p.y + s * 0.95))
        frame.addLine(to: CGPoint(x: p.x, y: p.y + s * 0.25))
        frame.addLine(to: CGPoint(x: p.x + s * 0.3 - gait, y: p.y + s * 0.95))
        context.stroke(frame, with: .color(colour),
                       style: StrokeStyle(lineWidth: max(1, s * 0.28), lineCap: .round))
        // Everything they have left, on their back.
        if burdened {
            context.fill(Path(roundedRect: CGRect(x: p.x - s * 0.5, y: p.y - s * 0.62,
                                                  width: s * 1.0, height: s * 0.7),
                              cornerRadius: s * 0.16),
                         with: .color(Color(red: 0.46, green: 0.38, blue: 0.30)))
        }
    }

    /// A pack animal under a load — the thing that says "trade" at a glance.
    private static func mule(
        _ context: inout GraphicsContext, at p: CGPoint, s: CGFloat, colour: Color,
        time: Double, phase: Double, walking: Bool
    ) {
        let hide = Color(red: 0.44, green: 0.37, blue: 0.30)
        let gait = walking ? CGFloat(sin(time * 4.5 + phase)) * s * 0.2 : 0

        context.fill(Path(ellipseIn: CGRect(x: p.x - s * 0.7, y: p.y + s * 0.55,
                                            width: s * 1.4, height: s * 0.3)),
                     with: .color(.black.opacity(0.2)))
        // Body and neck.
        context.fill(Path(ellipseIn: CGRect(x: p.x - s * 0.65, y: p.y - s * 0.3,
                                            width: s * 1.3, height: s * 0.68)),
                     with: .color(hide))
        context.fill(Path(ellipseIn: CGRect(x: p.x + s * 0.5, y: p.y - s * 0.62,
                                            width: s * 0.42, height: s * 0.42)),
                     with: .color(hide))
        // Four short legs.
        for i in 0..<4 {
            let x = p.x - s * 0.45 + CGFloat(i) * s * 0.3
            context.stroke(Path { q in
                q.move(to: CGPoint(x: x, y: p.y + s * 0.24))
                q.addLine(to: CGPoint(x: x + (i % 2 == 0 ? gait : -gait), y: p.y + s * 0.7))
            }, with: .color(hide), lineWidth: max(0.6, s * 0.16))
        }
        // The panniers — the cargo, in the party's own colour.
        context.fill(Path(roundedRect: CGRect(x: p.x - s * 0.42, y: p.y - s * 0.62,
                                              width: s * 0.84, height: s * 0.42),
                          cornerRadius: s * 0.12),
                     with: .color(colour.opacity(0.9)))
    }

    /// What each kind is drawn in. Distinct from every colonist trade shade, so
    /// an outsider never reads as one of yours.
    static func tint(_ kind: VisitorKind) -> Color {
        switch kind {
        case .trader: return Color(red: 0.85, green: 0.66, blue: 0.36)
        case .envoy: return Color(red: 0.64, green: 0.60, blue: 0.86)
        case .refugee: return Color(red: 0.70, green: 0.62, blue: 0.58)
        case .wanderer: return Color(red: 0.62, green: 0.74, blue: 0.72)
        // Warmer than the rest of the road: the one party that is not passing
        // through, and the only one still on the canvas next season.
        case .settler: return Color(red: 0.82, green: 0.72, blue: 0.48)
        }
    }
}
