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

    /// **Where each thing stands**, before anything is drawn.
    ///
    /// Pulled out of the drawing so it can be *measured*: the first version
    /// refused anything that did not fit whole inside the plot, and a body is
    /// nearly as wide as its lot — so almost every attachment in the colony was
    /// silently dropped and the yards stayed as empty as before the bank
    /// existed. That is rule 47 again, self-inflicted one layer up, and it is
    /// why *"Everything a composition names is actually placed"* counts them.
    ///
    /// A building now stands on the **bottom** edge of its plot
    /// (`SettlementStructures.bodyLift`), so the open ground is the strip
    /// behind it and a hand's width down each side. Tall things go in the strip
    /// behind; the rest take the sides, and a little overhang into the lane is
    /// allowed — a woodpile against a wall is not trespass.
    static func places(names: [String], body: CGRect, lot: CGRect, seed: UInt64)
        -> [(form: Form, at: CGPoint, size: CGFloat, roll: Double)] {
        guard !names.isEmpty, body.width > 6 else { return [] }
        var h = seed | 1
        func roll() -> Double {
            h ^= h >> 33; h = h &* 0xFF51_AFD7_ED55_8CCD; h ^= h >> 29
            return Double((h >> 40) & 0xFFFF) / 65535
        }
        // Small against the walls: these name a building, they do not compete
        // with it. At two fifths of the wall they were reading as **panels
        // standing beside the houses** — Keks, on a screenshot: *"takové panely
        // nad tím"*. A quarter is about a cart, which is what these are.
        let unit = min(body.height, body.width) * 0.25
        guard unit > 2 else { return [] }

        let forms = names.compactMap(form(of:))
        let behind = max(0, body.minY - lot.minY)
        var out: [(form: Form, at: CGPoint, size: CGFloat, roll: Double)] = []
        var sideward = 0
        var backward = 0
        let backCount = forms.filter { rises($0) || behind > unit * 0.9 }.count

        for form in forms {
            let jitter = roll()
            let span = unit * CGFloat(0.8 + jitter * 0.45)
            let at: CGPoint
            if rises(form) || behind > unit * 0.9 {
                // The back yard: spread across it, so three sheds do not stack.
                let step = lot.width / CGFloat(max(1, backCount) + 1)
                backward += 1
                at = CGPoint(x: lot.minX + step * CGFloat(backward),
                             y: max(lot.minY + span * 0.6,
                                    body.minY - span * CGFloat(0.1 + jitter * 0.25)))
            } else {
                // Down the side, against the wall, alternating so a building
                // with four does not grow them all out of one hip.
                let side: CGFloat = sideward % 2 == 0 ? -1 : 1
                sideward += 1
                let row = CGFloat(sideward / 2)
                at = CGPoint(x: side < 0 ? body.minX - span * 0.45 : body.maxX + span * 0.45,
                             y: body.maxY - body.height * CGFloat(0.08 + jitter * 0.1)
                                - row * span * 0.9)
            }
            out.append((form: form, at: at, size: span, roll: jitter))
        }
        return out
    }

    /// Draw everything the composition names, around the walls it belongs to.
    ///
    /// - Parameters:
    ///   - body: the walls as drawn (`SettlementStructures.bodyRect`), so the
    ///     things beside a building move with it rather than with its plot.
    ///   - lot: the plot, which says where the open ground is.
    static func draw(
        _ context: inout GraphicsContext, names: [String], body: CGRect, lot: CGRect,
        seed: UInt64, night: Double, accent: Color?
    ) {
        for placed in places(names: names, body: body, lot: lot, seed: seed) {
            let at = placed.at
            let span = placed.size
            switch placed.form {
            case .heap:     heap(&context, at: at, size: span)
            case .stack:    stack(&context, at: at, size: span, roll: placed.roll)
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

    // Dimmer than a wall. These stand *beside* a building and must not out-draw
    // it: bone at three quarters put a white crate stack in front of every
    // house in the colony.
    private static var ink: Color { Theme.bone.opacity(0.42) }
    private static var faint: Color { Theme.bone.opacity(0.24) }

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

/// **The wall face the lift uncovers, and the ground it stands on.**
///
/// `RENDER_25D.md` §2 and §5: a building drawn a little above its own
/// footprint leaves a quadrilateral between the two, and that quad is the only
/// surface in this world that faces the viewer. Before it there was nowhere for
/// a fabric to be *seen* — `structures.json` named nine of them and the drawing
/// had no place to put one.
enum SettlementFabric {

    /// What a wall face is made of. Nine names, nine hands — a name the canvas
    /// does not know is drawn plain, which is honest and guarded.
    static func known(_ name: String) -> Bool {
        switch name {
        case "open", "thatch", "daub", "timber", "stone",
             "brick", "panel", "glass", "sheet": return true
        default: return false
        }
    }

    /// Draw the standing wall between the drawn body and the ground it owns.
    ///
    /// - Parameters:
    ///   - body: the walls as drawn — its bottom edge is the top of the face.
    ///   - groundY: where the building actually stands, in the plan.
    static func skirt(
        _ context: inout GraphicsContext, body: CGRect, groundY: CGFloat,
        fabric: String, trim: String, wall: Color, ink: Color, night: Double,
        /// The ground the building actually covers. Wider than the drawn body,
        /// so the two edges meeting is what gives the wall a **corner** — and
        /// the corner is what says the thing has depth. Zero width falls back
        /// to a flat face, which is what a thumbnail wants.
        plan: CGRect = .zero,
        /// Which way the light is going. The near wall is always drawn; the
        /// **side** wall is drawn on the side the sun is not behind, because
        /// that is the one a viewer standing in front of the building can see
        /// (`RENDER_25D.md` §2 — two quads, never four).
        sun: SettlementLight.Sun? = nil
    ) {
        let height = groundY - body.maxY
        guard height > 1.2, body.width > 3 else { return }
        let face = CGRect(x: body.minX, y: body.maxY, width: body.width, height: height)

        // The side wall: a quad from the plot's edge on the ground up to the
        // body's edge, on whichever side the light is coming *across*.
        if plan.width > body.width + 1, let sun, sun.daylight > 0.05, height > 2 {
            let leftLit = sun.shadow.dx > 0        // shadow thrown right = sun on the left
            let ground = leftLit ? plan.maxX : plan.minX
            let wallEdge = leftLit ? body.maxX : body.minX
            var side = Path()
            side.move(to: CGPoint(x: wallEdge, y: face.minY))
            side.addLine(to: CGPoint(x: ground, y: face.maxY))
            side.addLine(to: CGPoint(x: ground, y: face.maxY - height * 0.9))
            side.addLine(to: CGPoint(x: wallEdge, y: face.minY - height * 0.15))
            side.closeSubpath()
            // Darker than the face it turns away from: one surface in the light
            // and one out of it is the whole of the illusion.
            context.fill(side, with: .color(wall.opacity(0.55 - night * 0.2)))
            context.stroke(side, with: .color(ink.opacity(0.5)), lineWidth: 0.5)
        }

        // A roof on posts has no wall: two legs and the daylight between them.
        guard fabric != "open" else {
            var posts = Path()
            for x in [face.minX + face.width * 0.08, face.maxX - face.width * 0.08] {
                posts.move(to: CGPoint(x: x, y: face.minY))
                posts.addLine(to: CGPoint(x: x, y: face.maxY))
            }
            context.stroke(posts, with: .color(ink.opacity(0.8)), lineWidth: 1)
            return
        }

        // The face itself, a shade under the roof above it so the two read as
        // two surfaces rather than one silhouette.
        context.fill(Path(face), with: .color(wall.opacity(0.9 - night * 0.25)))
        context.stroke(Path(face), with: .color(ink.opacity(0.75)), lineWidth: 0.7)

        // **Nine fabrics, nine hands.** They shared four routines with different
        // counts, which at a wall's size is one texture at four densities — the
        // bank names nine materials and a viewer could tell three apart.
        var marks = Path()
        switch fabric {
        case "timber":
            // Log courses: fat, few, and rounded off at the ends where the
            // trunk shows.
            courses(&marks, in: face, count: 4)
            let step = face.height / 4
            for i in 1..<4 {
                let y = face.minY + step * CGFloat(i)
                marks.addEllipse(in: CGRect(x: face.minX - 0.4, y: y - step * 0.32,
                                            width: 1.6, height: step * 0.64))
            }
        case "brick":
            // Finer courses, and the perpends staggered half a brick.
            courses(&marks, in: face, count: 7)
            let step = face.height / 7
            for row in 1..<7 {
                let y = face.minY + step * CGFloat(row)
                let offset = row % 2 == 0 ? 0.33 : 0.66
                let x = face.minX + face.width * CGFloat(offset)
                marks.move(to: CGPoint(x: x, y: y))
                marks.addLine(to: CGPoint(x: x, y: y - step))
            }
        case "stone":
            // Coarse blocks, unequal: a wall laid by eye rather than a kiln.
            courses(&marks, in: face, count: 4, stagger: 0.5)
            let step = face.height / 4
            for row in 0..<4 where row % 2 == 1 {
                let y = face.minY + step * CGFloat(row) + step * 0.5
                marks.move(to: CGPoint(x: face.minX + face.width * 0.2, y: y))
                marks.addLine(to: CGPoint(x: face.minX + face.width * 0.2, y: y - step * 0.5))
            }
        case "thatch":
            // Combed straight down, with a thick eave across the top and an
            // uneven hem at the bottom.
            combed(&marks, in: face, count: 9)
            marks.move(to: CGPoint(x: face.minX, y: face.minY + face.height * 0.14))
            marks.addLine(to: CGPoint(x: face.maxX, y: face.minY + face.height * 0.14))
            var x = face.minX
            var up = true
            while x < face.maxX {
                let next = min(face.maxX, x + face.width / 6)
                marks.move(to: CGPoint(x: x, y: face.maxY - (up ? 1.2 : 0)))
                marks.addLine(to: CGPoint(x: next, y: face.maxY - (up ? 0 : 1.2)))
                x = next; up.toggle()
            }
        case "sheet":
            // Corrugation: tight verticals and a hem where the sheet is fixed.
            combed(&marks, in: face, count: 12)
            let hem = face.maxY - face.height * 0.12
            marks.move(to: CGPoint(x: face.minX, y: hem))
            marks.addLine(to: CGPoint(x: face.maxX, y: hem))
        case "daub":
            // Smooth, with the crucks showing through it and a rail across.
            frame(&marks, in: face)
            marks.move(to: CGPoint(x: face.minX + face.width * 0.3,
                                   y: face.minY + face.height * 0.25))
            marks.addLine(to: CGPoint(x: face.minX + face.width * 0.7,
                                      y: face.minY + face.height * 0.75))
        case "panel":
            // A grid of joints, and one seam standing proud of the rest.
            courses(&marks, in: face, count: 3)
            combed(&marks, in: face, count: 4)
            let seam = face.minX + face.width * 0.5
            marks.move(to: CGPoint(x: seam - 0.8, y: face.minY))
            marks.addLine(to: CGPoint(x: seam - 0.8, y: face.maxY))
        case "glass":
            // Verticals, one transom, and a glint across the corner.
            combed(&marks, in: face, count: 5)
            marks.move(to: CGPoint(x: face.minX, y: face.midY))
            marks.addLine(to: CGPoint(x: face.maxX, y: face.midY))
            marks.move(to: CGPoint(x: face.minX + face.width * 0.12, y: face.maxY))
            marks.addLine(to: CGPoint(x: face.minX + face.width * 0.42, y: face.minY))
        default:
            break
        }
        context.stroke(marks, with: .color(ink.opacity(0.45)), lineWidth: 0.5)

        // The trim: what frames the face at its corners.
        guard trim != "none", face.height > 4 else { return }
        var quoins = Path()
        quoins.move(to: CGPoint(x: face.minX, y: face.minY))
        quoins.addLine(to: CGPoint(x: face.minX, y: face.maxY))
        quoins.move(to: CGPoint(x: face.maxX, y: face.minY))
        quoins.addLine(to: CGPoint(x: face.maxX, y: face.maxY))
        context.stroke(quoins, with: .color(ink.opacity(0.85)), lineWidth: 1)
    }

    private static func courses(_ path: inout Path, in face: CGRect,
                                count: Int, stagger: CGFloat = 0) {
        guard count > 0 else { return }
        let step = face.height / CGFloat(count)
        for i in 1..<max(1, count) {
            let y = face.minY + step * CGFloat(i)
            path.move(to: CGPoint(x: face.minX, y: y))
            path.addLine(to: CGPoint(x: face.maxX, y: y))
            guard stagger > 0 else { continue }
            let x = face.minX + face.width * (i % 2 == 0 ? stagger : stagger * 0.5)
            path.move(to: CGPoint(x: x, y: y))
            path.addLine(to: CGPoint(x: x, y: y - step))
        }
    }

    private static func combed(_ path: inout Path, in face: CGRect, count: Int) {
        guard count > 0 else { return }
        let step = face.width / CGFloat(count)
        for i in 1..<max(1, count) {
            let x = face.minX + step * CGFloat(i)
            path.move(to: CGPoint(x: x, y: face.minY))
            path.addLine(to: CGPoint(x: x, y: face.maxY))
        }
    }

    private static func frame(_ path: inout Path, in face: CGRect) {
        // The crucks: two verticals and a brace, the timber in a daub wall.
        for x in [face.minX + face.width * 0.3, face.minX + face.width * 0.7] {
            path.move(to: CGPoint(x: x, y: face.minY))
            path.addLine(to: CGPoint(x: x, y: face.maxY))
        }
        path.move(to: CGPoint(x: face.minX, y: face.midY))
        path.addLine(to: CGPoint(x: face.maxX, y: face.midY))
    }

    /// **What the ground does around a building.** Four surfaces out of the
    /// bank, drawn on the plot the building owns — before this every yard in
    /// the colony was the same swept earth whatever stood on it.
    static func yard(_ context: inout GraphicsContext, kind: String,
                     lot: CGRect, seed: UInt64) {
        guard lot.width > 4, kind != "none" else { return }
        var marks = Path()
        switch kind {
        case "planking":
            let boards = max(3, min(9, Int(lot.height / 4)))
            for board in 1..<boards {
                let y = lot.minY + lot.height * CGFloat(board) / CGFloat(boards)
                marks.move(to: CGPoint(x: lot.minX, y: y))
                marks.addLine(to: CGPoint(x: lot.maxX, y: y))
            }
        // **Everything below is laid out in fractions of the plot**, never in
        // pixels. A loop that starts at `lot.minX` and steps four points walks
        // a different set of stones every time the camera moves a fraction of a
        // point, and the yard boils under the town — Keks: *"hromady nebo
        // komíny při posunu kamery blikají"*. The plot's own fractions are the
        // same on every frame, at every zoom.
        case "cobbles":
            var h = seed | 1
            let columns = max(3, min(12, Int(lot.width / 4)))
            let rows = max(3, min(12, Int(lot.height / 3)))
            for row in 0..<rows {
                for column in 0..<columns {
                    h ^= h >> 33; h = h &* 0xFF51_AFD7_ED55_8CCD; h ^= h >> 29
                    let r = CGFloat(Double((h >> 40) & 0xFF) / 255) * 0.8 + 0.6
                    let x = lot.minX + lot.width * (CGFloat(column) + 0.5) / CGFloat(columns)
                    let y = lot.minY + lot.height * (CGFloat(row) + 0.5) / CGFloat(rows)
                    marks.addEllipse(in: CGRect(x: x - r, y: y - r * 0.7,
                                                width: r * 2, height: r * 1.4))
                }
            }
        case "gravel":
            var h = seed | 3
            for _ in 0..<Int(min(60, max(6, lot.width * lot.height / 24))) {
                h ^= h >> 33; h = h &* 0xFF51_AFD7_ED55_8CCD; h ^= h >> 29
                let x = lot.minX + lot.width * CGFloat(Double((h >> 40) & 0xFFFF) / 65535)
                h ^= h >> 31
                let y = lot.minY + lot.height * CGFloat(Double((h >> 24) & 0xFFFF) / 65535)
                marks.addEllipse(in: CGRect(x: x, y: y, width: 0.9, height: 0.7))
            }
        default:
            return                      // beaten earth is the plot's own colour
        }
        context.stroke(marks, with: .color(Theme.bone.opacity(0.16)), lineWidth: 0.45)
    }
}
