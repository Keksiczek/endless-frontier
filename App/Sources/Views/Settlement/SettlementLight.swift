import SwiftUI
import EndlessFrontierCore

/// The sun, and everything the sun does to the ground.
///
/// The valley used to be lit by nothing. Every surface took its colour straight
/// from its cover and its season, so a meadow was one flat green from edge to
/// edge and the whole map read — the complaint was exact — as *boring*, however
/// much detail was drawn on top of it. Detail was never the problem. Light was:
/// a landscape is legible because parts of it face the light and parts of it do
/// not, and nothing here faced anything.
///
/// Three things arrive together, and they are one idea:
///
/// 1. **A sun with a position.** It rises, crosses, and sets on the same clock
///    the colonists already keep (`AgentMotion.dayLength`), so noon is when the
///    town is busiest and dusk is when they walk home.
/// 2. **Relief.** A slow height field over the map — hills and hollows the
///    simulation does not know about, because they are the *look* of ground,
///    not a fact about it. Lit from the sun's side, a slope brightens; away
///    from it, it darkens. This is what stops a field being a printed colour.
/// 3. **Shadows that fall the right way.** Buildings, trees, rock and people
///    all throw their shadow along the sun's line: long and raking at dawn,
///    tucked under at noon, long the other way at dusk. A low sun is the whole
///    reason the town looks like it is standing on something.
///
/// Strictly presentational and strictly pure: `sun(time:)` and
/// `relief(_:_:seed:)` are functions of their arguments, nothing is stored, and
/// nothing here can reach the simulation.
enum SettlementLight {

    // MARK: - The sun

    /// Where the sun stands and what its light is doing.
    struct Sun: Equatable {
        /// 0 at the horizon, 1 straight overhead. Zero all night.
        var elevation: Double
        /// How much of the light is direct sun — 0 in the dark, 1 in full day.
        /// Separate from elevation so the last of the dusk still tints without
        /// still casting.
        var daylight: Double
        /// Which way, and how far, a thing of unit height throws its shadow.
        /// In multiples of the caster's own height.
        var shadow: CGVector
        /// How dark a cast shadow is.
        var strength: Double
        /// How hard the relief is lit — flat at noon, raking at dawn and dusk.
        var relief: Double
        /// The colour of the light itself: cold before dawn, gold at the edges
        /// of the day, plain white in the middle of it.
        var tint: Color
    }

    /// Daylight runs from a quarter past midnight to three quarters — dawn at
    /// 0.25 of the day, noon at 0.5, dusk at 0.75, matching `nightness`.
    static let dawn = 0.25
    static let dusk = 0.75

    /// The longest a shadow may get, in multiples of its caster's height. A
    /// real sun on the horizon throws an infinite shadow; a drawn one that does
    /// smears the whole map into stripes.
    static let maxShadow: CGFloat = 3.4

    /// Where the sun stands at a given moment of the shared day.
    ///
    /// Pure, and the *only* place the day's geometry is written down — the
    /// ground bands, the cast shadows and the warm wash all read this, so they
    /// can never disagree about where the light is coming from.
    static func sun(time: Double) -> Sun {
        let t = (time / AgentMotion.dayLength).truncatingRemainder(dividingBy: 1)
        let day = t < 0 ? t + 1 : t
        // How far through the daylit half of the day we are, 0…1.
        let course = (day - dawn) / (dusk - dawn)
        guard course > 0, course < 1 else {
            return Sun(elevation: 0, daylight: 0, shadow: .zero, strength: 0,
                       relief: 0.10, tint: Color(red: 0.52, green: 0.58, blue: 0.78))
        }
        let elevation = sin(course * .pi)
        // The last stretch of dawn and the first of dusk still light the world
        // without throwing anything: shadows fade in over the first sliver of
        // the morning rather than snapping on at full length.
        let daylight = min(1, elevation * 3.2)
        // A low sun throws a long shadow. Clamped, or the horizon throws one
        // the width of the valley.
        let length = min(maxShadow, 0.62 / max(0.18, CGFloat(elevation)))
        // Sunrise on the right, so the morning shadow lies to the left. The
        // vertical lean is constant: this is an oblique view of flat ground,
        // and a shadow always falls a little toward the viewer.
        let across = -CGFloat(cos(course * .pi))
        let sunlow = 1 - elevation
        return Sun(
            elevation: elevation,
            daylight: daylight,
            shadow: CGVector(dx: across * length, dy: length * 0.42),
            strength: 0.34 * daylight,
            // Raking light picks out relief; noon flattens it.
            relief: 0.10 + 0.26 * daylight * (0.35 + 0.65 * sunlow),
            tint: lightTint(elevation: elevation, low: sunlow))
    }

    /// Gold at the edges of the day, plain in the middle of it.
    private static func lightTint(elevation: Double, low: Double) -> Color {
        let warm = low * low                       // only really the last hour
        return Color(red: 0.98, green: 0.94 - warm * 0.18, blue: 0.86 - warm * 0.34)
    }

    // MARK: - Relief

    /// The height of the land at a normalised point — pure decoration, and the
    /// same for a given `(seed, u, v)` for ever, so the hills do not crawl.
    ///
    /// Two octaves: broad swells that a whole quarter of the map sits on, and a
    /// finer roll that gives a single field its shape.
    static func relief(_ u: Double, _ v: Double, seed: UInt64) -> Double {
        let broad = lattice(u * 3.1, v * 2.3, seed: seed)
        let fine = lattice(u * 8.3, v * 6.1, seed: seed &+ 0x5BF0_3635)
        return broad * 0.68 + fine * 0.32
    }

    /// How bright the ground at a point is, −1 (in shade) … +1 (facing the
    /// sun).
    ///
    /// Two terms, and both are needed. **Height** carries the broad reading —
    /// a rise catches more light than a hollow, whatever the hour — and is what
    /// gives the valley shape you can see from a distance. **Slope** carries
    /// the direction: the face turned toward the sun brightens and the far side
    /// of the same ridge goes dark, and that flips as the sun crosses. On its
    /// own the slope term was too fine-grained to see; almost every tile landed
    /// in the middle band and the map came out exactly as flat as before.
    static func slopeLight(_ u: Double, _ v: Double, seed: UInt64, sun: Sun) -> Double {
        let height = (relief(u, v, seed: seed) - 0.5) * 1.7
        guard sun.daylight > 0.001 else {
            // Under a flat sky the hollows are still darker than the tops; the
            // land keeps its shape at night rather than going out entirely.
            return max(-1, min(1, height))
        }
        let e = 0.020
        let dx = relief(u + e, v, seed: seed) - relief(u - e, v, seed: seed)
        let dy = relief(u, v + e, seed: seed) - relief(u, v - e, seed: seed)
        // The sun's horizontal bearing, normalised. `shadow` points *away* from
        // the sun, so a slope facing the sun is one leaning against it.
        let len = max(0.0001, sqrt(sun.shadow.dx * sun.shadow.dx + sun.shadow.dy * sun.shadow.dy))
        let sx = Double(-sun.shadow.dx / len), sy = Double(-sun.shadow.dy / len)
        let slope = (dx * sx + dy * sy) * 26
        return max(-1, min(1, height * 0.55 + slope * 0.75))
    }

    /// One octave of smooth value noise on a lattice.
    private static func lattice(_ x: Double, _ y: Double, seed: UInt64) -> Double {
        let xi = Int(floor(x)), yi = Int(floor(y))
        let xf = x - Double(xi), yf = y - Double(yi)
        // Smoothstep, so the lattice never shows as a grid of creases.
        let u = xf * xf * (3 - 2 * xf), v = yf * yf * (3 - 2 * yf)
        let a = corner(xi, yi, seed), b = corner(xi + 1, yi, seed)
        let c = corner(xi, yi + 1, seed), d = corner(xi + 1, yi + 1, seed)
        return (a + (b - a) * u) + ((c + (d - c) * u) - (a + (b - a) * u)) * v
    }

    private static func corner(_ x: Int, _ y: Int, _ seed: UInt64) -> Double {
        SettlementGround.unit(SettlementGround.hash(seed &+ 0x51_7C_C1_B7, x, y))
    }

    // MARK: - Cast shadows

    /// The shadow of a box standing on the ground: its own footprint, plus the
    /// footprint dragged along the sun's line, plus the sheared band that joins
    /// the two. Filled non-zero, so the three overlap into one silhouette.
    ///
    /// `height` is in pixels — how tall the thing is, which is what decides how
    /// far the shadow reaches.
    static func boxShadow(
        at c: CGPoint, footprint: CGSize, height: CGFloat, sun: Sun
    ) -> Path {
        let sx = sun.shadow.dx * height, sy = sun.shadow.dy * height
        let w = footprint.width / 2, h = footprint.height / 2
        let base = CGRect(x: c.x - w, y: c.y - h, width: footprint.width, height: footprint.height)
        var path = Path()
        path.addRect(base)
        path.addRect(base.offsetBy(dx: sx, dy: sy))
        // The two corners on the silhouette, which depend only on the quadrant
        // the light is coming from.
        let (p, q): (CGPoint, CGPoint) = sx * sy >= 0
            ? (CGPoint(x: base.maxX, y: base.minY), CGPoint(x: base.minX, y: base.maxY))
            : (CGPoint(x: base.minX, y: base.minY), CGPoint(x: base.maxX, y: base.maxY))
        path.move(to: p)
        path.addLine(to: q)
        path.addLine(to: CGPoint(x: q.x + sx, y: q.y + sy))
        path.addLine(to: CGPoint(x: p.x + sx, y: p.y + sy))
        path.closeSubpath()
        return path
    }

    /// The shadow of something roughly round — a tree, a boulder, a person.
    /// A puddle at the feet, a smaller one at the far end, and the band between.
    static func blobShadow(
        at c: CGPoint, halfWidth: CGFloat, height: CGFloat, sun: Sun
    ) -> Path {
        let sx = sun.shadow.dx * height, sy = sun.shadow.dy * height
        let tip = CGPoint(x: c.x + sx, y: c.y + sy)
        let tipHalf = halfWidth * 0.72
        var path = Path()
        path.addEllipse(in: CGRect(x: c.x - halfWidth, y: c.y - halfWidth * 0.34,
                                   width: halfWidth * 2, height: halfWidth * 0.68))
        guard abs(sx) + abs(sy) > 0.4 else { return path }
        path.addEllipse(in: CGRect(x: tip.x - tipHalf, y: tip.y - tipHalf * 0.34,
                                   width: tipHalf * 2, height: tipHalf * 0.68))
        // The band, perpendicular to the sun's line so it reads as one shape
        // however the light swings round.
        let len = max(0.0001, sqrt(sx * sx + sy * sy))
        let nx = -sy / len * halfWidth * 0.5, ny = sx / len * halfWidth * 0.5
        path.move(to: CGPoint(x: c.x + nx, y: c.y + ny))
        path.addLine(to: CGPoint(x: c.x - nx, y: c.y - ny))
        path.addLine(to: CGPoint(x: tip.x - nx * 0.72, y: tip.y - ny * 0.72))
        path.addLine(to: CGPoint(x: tip.x + nx * 0.72, y: tip.y + ny * 0.72))
        path.closeSubpath()
        return path
    }

    /// The colour a cast shadow is drawn in. Never pure black: a shadow on a
    /// sunlit day is lit by the sky, which is blue.
    static func shadowColour(_ sun: Sun) -> Color {
        Color(red: 0.05, green: 0.06, blue: 0.12).opacity(sun.strength)
    }

    /// The warm cast of a low sun over the whole lens, and the light falling
    /// off away from it. Atmosphere, so it stays in view space like the season
    /// and night washes and does not slide when the map is panned.
    static func wash(
        _ context: inout GraphicsContext, rect: CGRect, sun: Sun
    ) {
        guard sun.daylight > 0.02 else { return }
        let warmth = (1 - sun.elevation) * sun.daylight
        guard warmth > 0.02 else { return }
        // A gradient running the way the light does, so one side of the valley
        // is in the sun and the other is falling into evening.
        let len = max(0.0001, sqrt(sun.shadow.dx * sun.shadow.dx + sun.shadow.dy * sun.shadow.dy))
        let toSun = CGPoint(x: -sun.shadow.dx / len, y: -sun.shadow.dy / len)
        let reach = max(rect.width, rect.height) * 0.75
        let mid = CGPoint(x: rect.midX, y: rect.midY)
        context.fill(
            Path(rect),
            with: .linearGradient(
                Gradient(colors: [sun.tint.opacity(0.20 * warmth),
                                  sun.tint.opacity(0.02 * warmth)]),
                startPoint: CGPoint(x: mid.x + toSun.x * reach, y: mid.y + toSun.y * reach),
                endPoint: CGPoint(x: mid.x - toSun.x * reach, y: mid.y - toSun.y * reach)))
    }
}
