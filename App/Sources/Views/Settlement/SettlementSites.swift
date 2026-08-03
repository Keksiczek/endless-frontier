import SwiftUI
import EndlessFrontierCore

/// What a party is dealing with, drawn where they are dealing with it.
///
/// A visit used to be four people standing on a dot for six ticks while a
/// number was rolled somewhere off screen. The place has *things* in it now
/// (`SiteEncounter`) and each of them has a position the Core owns, so this is
/// a reading of the world rather than a decoration over it — the same contract
/// the battle drawing keeps. Rule 5: nothing here writes anything.
enum SettlementSites {

    static func draw(
        _ site: SiteEncounter, in rect: CGRect, time: Double,
        context: inout GraphicsContext
    ) {
        let unit = min(rect.width, rect.height)
        // Who is going for what, drawn under everything so it reads as
        // intent rather than as wire.
        for (pawn, markID) in site.marks.sorted(by: { $0.key.uuidString < $1.key.uuidString }) {
            guard let from = site.places[pawn],
                  let mark = site.things.first(where: { $0.id == markID }), !mark.done
            else { continue }
            context.stroke(Path { p in
                p.move(to: SettlementRenderer.point(from, in: rect))
                p.addLine(to: SettlementRenderer.point(mark.at, in: rect))
            }, with: .color(Theme.accent.opacity(0.14)),
               style: StrokeStyle(lineWidth: max(0.5, unit * 0.0012), dash: [2, 3]))
        }

        for thing in site.things {
            let c = SettlementRenderer.point(thing.at, in: rect)
            switch thing.kind {
            case .cache: chest(&context, at: c, unit: unit, done: thing.done)
            case .trap:  snare(&context, at: c, unit: unit, done: thing.done)
            case .guardian:
                guardian(&context, at: c, unit: unit, time: time,
                         left: thing.done ? 0 : 1)
            }
        }
    }

    /// A chest: shut and bound while it holds something, thrown open after.
    private static func chest(
        _ ctx: inout GraphicsContext, at c: CGPoint, unit: CGFloat, done: Bool
    ) {
        let w = unit * 0.013, h = unit * 0.009
        let box = CGRect(x: c.x - w / 2, y: c.y - h / 2, width: w, height: h)
        ctx.fill(Path(box), with: .color(done ? Theme.ink.opacity(0.45)
                                              : Color(red: 0.36, green: 0.26, blue: 0.17)))
        ctx.stroke(Path(box), with: .color(done ? Theme.textDim.opacity(0.4)
                                                : Theme.accent.opacity(0.8)),
                   lineWidth: 0.8)
        guard !done else { return }
        // The band and the lock — a shut chest reads as *shut*.
        ctx.stroke(Path { p in
            p.move(to: CGPoint(x: c.x, y: box.minY))
            p.addLine(to: CGPoint(x: c.x, y: box.maxY))
        }, with: .color(Theme.accent.opacity(0.55)), lineWidth: 0.6)
    }

    /// A trap, before and after: a ring of teeth, then a sprung one.
    private static func snare(
        _ ctx: inout GraphicsContext, at c: CGPoint, unit: CGFloat, done: Bool
    ) {
        let r = unit * 0.008
        let ring = CGRect(x: c.x - r, y: c.y - r * 0.6, width: r * 2, height: r * 1.2)
        ctx.stroke(Path(ellipseIn: ring),
                   with: .color(done ? Theme.textDim.opacity(0.3)
                                     : Theme.danger.opacity(0.55)),
                   style: StrokeStyle(lineWidth: 0.8, dash: done ? [] : [1.5, 1.5]))
        guard !done else { return }
        ctx.fill(Path(ellipseIn: ring.insetBy(dx: r * 0.55, dy: r * 0.35)),
                 with: .color(Theme.ink.opacity(0.6)))
    }

    /// Something alive, breathing. Gone once it is dealt with — the body stays
    /// as a mark on the ground.
    private static func guardian(
        _ ctx: inout GraphicsContext, at c: CGPoint, unit: CGFloat,
        time: Double, left: Double
    ) {
        let s = unit * 0.011
        guard left > 0 else {
            ctx.fill(Path(ellipseIn: CGRect(x: c.x - s * 0.8, y: c.y - s * 0.25,
                                            width: s * 1.6, height: s * 0.5)),
                     with: .color(Theme.ink.opacity(0.4)))
            return
        }
        let breath = CGFloat(1 + 0.06 * sin(time * 2.4))
        ctx.fill(Path(ellipseIn: CGRect(x: c.x - s * 0.9 * breath, y: c.y - s * 0.55,
                                        width: s * 1.8 * breath, height: s * 1.1)),
                 with: .color(Theme.danger.opacity(0.55)))
        ctx.fill(Path(ellipseIn: CGRect(x: c.x + s * 0.55, y: c.y - s * 0.8,
                                        width: s * 0.7, height: s * 0.7)),
                 with: .color(Theme.danger.opacity(0.7)))
        // Two points of light where it is looking from.
        ctx.fill(Path(ellipseIn: CGRect(x: c.x + s * 0.72, y: c.y - s * 0.66,
                                        width: s * 0.16, height: s * 0.16)),
                 with: .color(Theme.accent.opacity(0.9)))
    }
}
