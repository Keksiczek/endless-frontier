import SwiftUI
import EndlessFrontierCore

/// **What stands beside a building and says what it is.**
///
/// `structures.json` names them — a charcoal heap, a hitching rail, drying
/// racks, a crane — and until now the renderer drew none of them, which is the
/// fault rule 47 exists for: 54 names in the bank, validated, generated and
/// read by nothing. A building was still its own silhouette and nothing else,
/// so five works sharing `look: plant` differed by a bay count.
///
/// **Composition, not more routines** (rule 92). Fifty-four names map onto
/// **fifteen forms**, and a name that maps to none draws nothing — which reads
/// as a plainer building rather than as a fault, so it is guarded by *"Every
/// attachment in the bank is a thing the canvas can draw"*.
enum SettlementAttachments {

    /// The fifteen things the canvas can actually draw beside a building.
    enum Form {
        case heap        // spoil, ore, charcoal — a mound with grain in it
        case stack       // crates, logs, sacks — boxes, squared off
        case rack        // uprights and crossbars, with things hung on them
        case line        // posts and a sagging run between them
        case rail        // a low bar on two posts
        case block       // a bench, an anvil, a table — worked at, waist high
        case canopy      // posts and a slope: a cart out of the rain
        case platform    // a loading step, a raised floor, an apron
        case mast        // a crane, a chimney, a cooling tower — it goes up
        case dish        // a bowl aimed at the sky
        case pipes       // fins, ducts, a chute, a ladder — parallel runs
        case wheel       // a water wheel
        case glow        // a brazier, a furnace mouth, an emitter
        case barrel      // a water butt
        case planting    // a bed of something green
    }

    /// The whole bank, by name. Adding a composition with a new name means
    /// adding a row here — one line, and the guard says so before it ships.
    static func form(of name: String) -> Form? {
        switch name {
        case "coal_heap", "ore_pile", "slag_heap", "sawdust_pile",
             "charcoal_heap", "turf_mound":
            return .heap
        case "crates", "timber_stack", "sack_stack", "tyre_stack",
             "woodpile", "log_trestle":
            return .stack
        case "tool_rack", "drying_racks", "wheel_rack", "antler_mount", "saw_frame":
            return .rack
        case "wash_line", "cable_run", "cable_ducts":
            return .line
        case "hitching_rail", "yoke_beam":
            return .rail
        case "bench", "long_table", "work_block", "anvil", "grindstone", "scales":
            return .block
        case "cart_under_awning", "awning_row", "walkway_canopy":
            return .canopy
        case "loading_step", "raised_floor", "vehicle_apron", "wide_door":
            return .platform
        case "crane", "chimney_stack", "chimney_bank", "cooling_towers", "sails":
            return .mast
        case "satellite_dish", "waveguide_array":
            return .dish
        case "cooling_fins", "coolant_pipes", "chute", "log_conveyor", "ladder":
            return .pipes
        case "water_wheel":
            return .wheel
        case "brazier", "bellows", "hologram_emitter", "backup_generator":
            return .glow
        case "water_butt":
            return .barrel
        case "courtyard_planting":
            return .planting
        default:
            return nil
        }
    }

    /// Whether the thing belongs **behind** the building — it is taller than the
    /// roof and would otherwise be drawn standing in the front yard.
    private static func rises(_ form: Form) -> Bool {
        switch form {
        case .mast, .dish, .wheel: return true
        default: return false
        }
    }

    /// Draw everything the composition names, around the walls it belongs to.
    ///
    /// - Parameters:
    ///   - body: the walls as drawn (`SettlementStructures.bodyRect`), so the
    ///     things beside a building move with it rather than with its plot.
    ///   - lot: the plot, so nothing is put down in the neighbour's yard.
    static func draw(
        _ context: inout GraphicsContext, names: [String], body: CGRect, lot: CGRect,
        seed: UInt64, night: Double, accent: Color?
    ) {
        guard !names.isEmpty, body.width > 6 else { return }
        var h = seed | 1
        func roll() -> Double {
            h ^= h >> 33; h = h &* 0xFF51_AFD7_ED55_8CCD; h ^= h >> 29
            return Double((h >> 40) & 0xFFFF) / 65535
        }
        // Small against the walls: these name a building, they do not compete
        // with it. A quarter of the wall height is about a cart.
        let unit = min(body.height, body.width) * 0.34
        guard unit > 2 else { return }

        var left = true
        for name in names {
            guard let form = form(of: name) else { continue }
            let jitter = roll()
            let side: CGFloat = left ? -1 : 1
            left.toggle()
            let span = unit * CGFloat(0.85 + jitter * 0.4)
            let x = side < 0
                ? body.minX - span * 0.75
                : body.maxX + span * 0.75
            let y = rises(form)
                ? body.minY + body.height * CGFloat(0.15 + jitter * 0.2)
                : body.maxY - body.height * CGFloat(0.04 + jitter * 0.12)
            // Never into next door's plot: what does not fit stays unbuilt,
            // which is the honest answer for a building crammed onto its lot.
            guard x - span > lot.minX - span * 0.4, x + span < lot.maxX + span * 0.4 else { continue }
            let at = CGPoint(x: x, y: y)
            switch form {
            case .heap:     heap(&context, at: at, size: span)
            case .stack:    stack(&context, at: at, size: span, roll: jitter)
            case .rack:     rack(&context, at: at, size: span)
            case .line:     line(&context, at: at, size: span, toward: body)
            case .rail:     rail(&context, at: at, size: span)
            case .block:    block(&context, at: at, size: span)
            case .canopy:   canopy(&context, at: at, size: span)
            case .platform: platform(&context, at: at, size: span)
            case .mast:     mast(&context, at: at, size: span, foot: body.maxY)
            case .dish:     dish(&context, at: at, size: span, foot: body.maxY)
            case .pipes:    pipes(&context, at: at, size: span)
            case .wheel:    wheel(&context, at: at, size: span)
            case .glow:     glow(&context, at: at, size: span, night: night, accent: accent)
            case .barrel:   barrel(&context, at: at, size: span)
            case .planting: planting(&context, at: at, size: span)
            }
        }
    }

    // MARK: - The forms

    private static var ink: Color { Theme.bone.opacity(0.72) }
    private static var faint: Color { Theme.bone.opacity(0.4) }

    private static func heap(_ context: inout GraphicsContext, at c: CGPoint, size s: CGFloat) {
        var mound = Path()
        mound.move(to: CGPoint(x: c.x - s * 0.5, y: c.y))
        mound.addQuadCurve(to: CGPoint(x: c.x + s * 0.5, y: c.y),
                           control: CGPoint(x: c.x, y: c.y - s * 0.85))
        mound.closeSubpath()
        context.fill(mound, with: .color(Theme.bone.opacity(0.13)))
        context.stroke(mound, with: .color(ink), lineWidth: 0.7)
        // The grain that says it is loose stuff and not a rock.
        var grain = Path()
        grain.move(to: CGPoint(x: c.x - s * 0.2, y: c.y - s * 0.18))
        grain.addLine(to: CGPoint(x: c.x - s * 0.05, y: c.y - s * 0.34))
        grain.move(to: CGPoint(x: c.x + s * 0.1, y: c.y - s * 0.15))
        grain.addLine(to: CGPoint(x: c.x + s * 0.24, y: c.y - s * 0.3))
        context.stroke(grain, with: .color(faint), lineWidth: 0.5)
    }

    private static func stack(_ context: inout GraphicsContext, at c: CGPoint,
                              size s: CGFloat, roll: Double) {
        let rows = roll > 0.55 ? 3 : 2
        let boxW = s * 0.44, boxH = s * 0.26
        for row in 0..<rows {
            let count = row == rows - 1 ? 1 : 2
            for column in 0..<count {
                let x = c.x - boxW * CGFloat(count) / 2 + boxW * CGFloat(column)
                let y = c.y - boxH * CGFloat(row + 1)
                let box = CGRect(x: x, y: y, width: boxW * 0.92, height: boxH * 0.92)
                context.fill(Path(box), with: .color(Theme.bone.opacity(0.1)))
                context.stroke(Path(box), with: .color(ink), lineWidth: 0.6)
            }
        }
    }

    private static func rack(_ context: inout GraphicsContext, at c: CGPoint, size s: CGFloat) {
        var frame = Path()
        frame.move(to: CGPoint(x: c.x - s * 0.4, y: c.y))
        frame.addLine(to: CGPoint(x: c.x - s * 0.4, y: c.y - s * 0.8))
        frame.move(to: CGPoint(x: c.x + s * 0.4, y: c.y))
        frame.addLine(to: CGPoint(x: c.x + s * 0.4, y: c.y - s * 0.8))
        frame.move(to: CGPoint(x: c.x - s * 0.46, y: c.y - s * 0.78))
        frame.addLine(to: CGPoint(x: c.x + s * 0.46, y: c.y - s * 0.78))
        context.stroke(frame, with: .color(ink), lineWidth: 0.7)
        // What hangs on it.
        var hung = Path()
        for i in 0..<3 {
            let x = c.x - s * 0.28 + s * 0.28 * CGFloat(i)
            hung.move(to: CGPoint(x: x, y: c.y - s * 0.74))
            hung.addLine(to: CGPoint(x: x, y: c.y - s * 0.4))
        }
        context.stroke(hung, with: .color(faint), lineWidth: 0.5)
    }

    private static func line(_ context: inout GraphicsContext, at c: CGPoint,
                             size s: CGFloat, toward body: CGRect) {
        var posts = Path()
        posts.move(to: CGPoint(x: c.x, y: c.y))
        posts.addLine(to: CGPoint(x: c.x, y: c.y - s * 0.9))
        context.stroke(posts, with: .color(ink), lineWidth: 0.7)
        // The run itself, sagging back to the wall it comes from.
        let wall = CGPoint(x: c.x < body.midX ? body.minX : body.maxX,
                           y: c.y - s * 0.55)
        var run = Path()
        run.move(to: CGPoint(x: c.x, y: c.y - s * 0.85))
        run.addQuadCurve(to: wall,
                         control: CGPoint(x: (c.x + wall.x) / 2, y: c.y - s * 0.5))
        context.stroke(run, with: .color(faint), lineWidth: 0.5)
    }

    private static func rail(_ context: inout GraphicsContext, at c: CGPoint, size s: CGFloat) {
        var path = Path()
        path.move(to: CGPoint(x: c.x - s * 0.45, y: c.y))
        path.addLine(to: CGPoint(x: c.x - s * 0.45, y: c.y - s * 0.42))
        path.move(to: CGPoint(x: c.x + s * 0.45, y: c.y))
        path.addLine(to: CGPoint(x: c.x + s * 0.45, y: c.y - s * 0.42))
        path.move(to: CGPoint(x: c.x - s * 0.5, y: c.y - s * 0.36))
        path.addLine(to: CGPoint(x: c.x + s * 0.5, y: c.y - s * 0.36))
        context.stroke(path, with: .color(ink), lineWidth: 0.7)
    }

    private static func block(_ context: inout GraphicsContext, at c: CGPoint, size s: CGFloat) {
        let top = CGRect(x: c.x - s * 0.4, y: c.y - s * 0.46,
                         width: s * 0.8, height: s * 0.18)
        context.fill(Path(top), with: .color(Theme.bone.opacity(0.14)))
        context.stroke(Path(top), with: .color(ink), lineWidth: 0.7)
        var legs = Path()
        legs.move(to: CGPoint(x: c.x - s * 0.3, y: c.y - s * 0.28))
        legs.addLine(to: CGPoint(x: c.x - s * 0.3, y: c.y))
        legs.move(to: CGPoint(x: c.x + s * 0.3, y: c.y - s * 0.28))
        legs.addLine(to: CGPoint(x: c.x + s * 0.3, y: c.y))
        context.stroke(legs, with: .color(faint), lineWidth: 0.6)
    }

    private static func canopy(_ context: inout GraphicsContext, at c: CGPoint, size s: CGFloat) {
        var roof = Path()
        roof.move(to: CGPoint(x: c.x - s * 0.55, y: c.y - s * 0.5))
        roof.addLine(to: CGPoint(x: c.x + s * 0.55, y: c.y - s * 0.72))
        roof.addLine(to: CGPoint(x: c.x + s * 0.55, y: c.y - s * 0.6))
        roof.addLine(to: CGPoint(x: c.x - s * 0.55, y: c.y - s * 0.38))
        roof.closeSubpath()
        context.fill(roof, with: .color(Theme.bone.opacity(0.12)))
        context.stroke(roof, with: .color(ink), lineWidth: 0.6)
        var posts = Path()
        posts.move(to: CGPoint(x: c.x - s * 0.5, y: c.y - s * 0.42))
        posts.addLine(to: CGPoint(x: c.x - s * 0.5, y: c.y))
        posts.move(to: CGPoint(x: c.x + s * 0.5, y: c.y - s * 0.64))
        posts.addLine(to: CGPoint(x: c.x + s * 0.5, y: c.y))
        context.stroke(posts, with: .color(ink), lineWidth: 0.6)
    }

    private static func platform(_ context: inout GraphicsContext, at c: CGPoint, size s: CGFloat) {
        let deck = CGRect(x: c.x - s * 0.55, y: c.y - s * 0.22,
                          width: s * 1.1, height: s * 0.22)
        context.fill(Path(deck), with: .color(Theme.bone.opacity(0.1)))
        context.stroke(Path(deck), with: .color(ink), lineWidth: 0.6)
        var edge = Path()
        edge.move(to: CGPoint(x: c.x - s * 0.55, y: c.y))
        edge.addLine(to: CGPoint(x: c.x + s * 0.55, y: c.y))
        context.stroke(edge, with: .color(faint), lineWidth: 0.5)
    }

    private static func mast(_ context: inout GraphicsContext, at c: CGPoint,
                             size s: CGFloat, foot: CGFloat) {
        var shaft = Path()
        shaft.move(to: CGPoint(x: c.x, y: foot))
        shaft.addLine(to: CGPoint(x: c.x, y: c.y - s * 1.5))
        context.stroke(shaft, with: .color(ink), lineWidth: 0.8)
        // The head: a jib, a cap, whatever it carries.
        var head = Path()
        head.move(to: CGPoint(x: c.x - s * 0.45, y: c.y - s * 1.35))
        head.addLine(to: CGPoint(x: c.x + s * 0.5, y: c.y - s * 1.5))
        context.stroke(head, with: .color(ink), lineWidth: 0.6)
        var stay = Path()
        stay.move(to: CGPoint(x: c.x, y: c.y - s * 1.5))
        stay.addLine(to: CGPoint(x: c.x + s * 0.4, y: foot - s * 0.1))
        context.stroke(stay, with: .color(faint), lineWidth: 0.5)
    }

    private static func dish(_ context: inout GraphicsContext, at c: CGPoint,
                             size s: CGFloat, foot: CGFloat) {
        var stand = Path()
        stand.move(to: CGPoint(x: c.x, y: foot))
        stand.addLine(to: CGPoint(x: c.x, y: c.y - s * 0.5))
        context.stroke(stand, with: .color(ink), lineWidth: 0.7)
        var bowl = Path()
        bowl.addArc(center: CGPoint(x: c.x, y: c.y - s * 0.55), radius: s * 0.5,
                    startAngle: .degrees(200), endAngle: .degrees(340), clockwise: false)
        context.stroke(bowl, with: .color(ink), lineWidth: 0.7)
    }

    private static func pipes(_ context: inout GraphicsContext, at c: CGPoint, size s: CGFloat) {
        var runs = Path()
        for i in 0..<4 {
            let x = c.x - s * 0.3 + s * 0.2 * CGFloat(i)
            runs.move(to: CGPoint(x: x, y: c.y))
            runs.addLine(to: CGPoint(x: x, y: c.y - s * 0.85))
        }
        runs.move(to: CGPoint(x: c.x - s * 0.36, y: c.y - s * 0.5))
        runs.addLine(to: CGPoint(x: c.x + s * 0.36, y: c.y - s * 0.5))
        context.stroke(runs, with: .color(ink), lineWidth: 0.55)
    }

    private static func wheel(_ context: inout GraphicsContext, at c: CGPoint, size s: CGFloat) {
        let r = s * 0.62
        let centre = CGPoint(x: c.x, y: c.y - r * 0.7)
        context.stroke(Path(ellipseIn: CGRect(x: centre.x - r, y: centre.y - r,
                                              width: r * 2, height: r * 2)),
                       with: .color(ink), lineWidth: 0.7)
        var spokes = Path()
        for i in 0..<4 {
            let angle = Double(i) * .pi / 4
            spokes.move(to: CGPoint(x: centre.x - CGFloat(cos(angle)) * r,
                                    y: centre.y - CGFloat(sin(angle)) * r))
            spokes.addLine(to: CGPoint(x: centre.x + CGFloat(cos(angle)) * r,
                                       y: centre.y + CGFloat(sin(angle)) * r))
        }
        context.stroke(spokes, with: .color(faint), lineWidth: 0.5)
    }

    private static func glow(_ context: inout GraphicsContext, at c: CGPoint, size s: CGFloat,
                             night: Double, accent: Color?) {
        var bowl = Path()
        bowl.move(to: CGPoint(x: c.x - s * 0.3, y: c.y - s * 0.34))
        bowl.addLine(to: CGPoint(x: c.x + s * 0.3, y: c.y - s * 0.34))
        bowl.addLine(to: CGPoint(x: c.x + s * 0.18, y: c.y))
        bowl.addLine(to: CGPoint(x: c.x - s * 0.18, y: c.y))
        bowl.closeSubpath()
        context.stroke(bowl, with: .color(ink), lineWidth: 0.7)
        // The one warm thing a building is allowed, and brighter after dark.
        let warmth = accent ?? Theme.accent
        context.fill(Path(ellipseIn: CGRect(x: c.x - s * 0.22, y: c.y - s * 0.52,
                                            width: s * 0.44, height: s * 0.3)),
                     with: .color(warmth.opacity(0.35 + night * 0.45)))
    }

    private static func barrel(_ context: inout GraphicsContext, at c: CGPoint, size s: CGFloat) {
        let body = CGRect(x: c.x - s * 0.22, y: c.y - s * 0.55,
                          width: s * 0.44, height: s * 0.55)
        context.fill(Path(body), with: .color(Theme.bone.opacity(0.12)))
        context.stroke(Path(body), with: .color(ink), lineWidth: 0.6)
        var hoops = Path()
        hoops.move(to: CGPoint(x: body.minX, y: body.midY))
        hoops.addLine(to: CGPoint(x: body.maxX, y: body.midY))
        context.stroke(hoops, with: .color(faint), lineWidth: 0.5)
    }

    private static func planting(_ context: inout GraphicsContext, at c: CGPoint, size s: CGFloat) {
        var bed = Path()
        for i in 0..<4 {
            let x = c.x - s * 0.36 + s * 0.24 * CGFloat(i)
            bed.move(to: CGPoint(x: x, y: c.y))
            bed.addQuadCurve(to: CGPoint(x: x + s * 0.08, y: c.y - s * 0.38),
                             control: CGPoint(x: x - s * 0.06, y: c.y - s * 0.2))
        }
        context.stroke(bed, with: .color(Theme.bone.opacity(0.5)), lineWidth: 0.55)
    }
}
