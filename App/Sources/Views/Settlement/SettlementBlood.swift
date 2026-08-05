import SwiftUI
import EndlessFrontierCore

/// What a blow leaves behind.
///
/// The fight was already right — `SiegeEngine` moves real people over real
/// ground and a blow lands on a named person — and the drawing was the part
/// that still spoke in aggregate: a bright seam across the whole line, sparks
/// at a computed "front", a bar floating over every defender's head. Colour
/// standing in for events, which is what "kaňky barvy všude" means.
///
/// Three things replace it, and all three hang off one fact: `BattleMoment.spot`
/// says **where** a blow landed.
///
/// 1. **The impact** is a moment on two specific bodies — short, small, and at
///    the point between them.
/// 2. **The ground keeps it.** A stain stays where somebody bled for the rest of
///    the fight. It is the only part of a battle that accumulates on the map,
///    and that is exactly why the field looks fought-over by the end.
/// 3. **So does the person.** Harm is drawn on the body that took it rather than
///    on a bar above their head, so a colonist who has been in it *looks* like
///    they have been in it.
///
/// Presentation only: everything here is read off the record and off `Siege`,
/// and nothing is written anywhere (rule 5).
enum SettlementBlood {

    /// Blood is its own colour. Not `Theme.danger`, which is the UI's warning
    /// red and reads as a label; this is dark, slightly brown, and sits on the
    /// ground rather than over it.
    static let fresh = Color(red: 0.62, green: 0.09, blue: 0.09)
    static let dried = Color(red: 0.34, green: 0.08, blue: 0.07)

    /// How long a blow's own flash lasts, as a fraction of the fight.
    static let flash = 0.055
    /// …and how long the spray is still in the air after it.
    static let spray = 0.10

    // MARK: - What the ground keeps

    /// Every stain on the field so far, drawn **under** the figures.
    ///
    /// Called from the renderer before the colonists, which is the whole reason
    /// this is a pass of its own: blood is on the ground, and a person stands on
    /// it. Nothing here fades — the field a fight was fought on stays marked for
    /// as long as the fight is on screen.
    static func ground(
        _ context: inout GraphicsContext, rect: CGRect, log: BattleLog,
        progress: Double, siege: Siege?, field: SiegeField, zoom: CGFloat
    ) {
        for moment in log.moments(upTo: progress) {
            guard moment.kind == .wound || moment.kind == .death else { continue }
            guard let spot = place(of: moment, log: log, field: field, siege: siege)
            else { continue }
            // A stain darkens and spreads for a moment after the blow, then
            // stops. Blood does not evaporate.
            let age = min(1, max(0, (progress - moment.at) / 0.06))
            let fatal = moment.kind == .death
            pool(&context, at: SettlementRenderer.point(spot, in: rect),
                 size: (fatal ? 1.7 : 0.55 + min(0.9, moment.amount / 40)) * age,
                 zoom: zoom, seed: UInt64(bitPattern: Int64(moment.id &* 2_654_435_761)))
        }
    }

    /// One stain: an irregular pool with a few thrown droplets around it.
    private static func pool(
        _ context: inout GraphicsContext, at p: CGPoint, size: Double,
        zoom: CGFloat, seed: UInt64
    ) {
        guard size > 0.02 else { return }
        var h = seed | 1
        func roll() -> Double {
            h ^= h >> 33; h = h &* 0xFF51_AFD7_ED55_8CCD; h ^= h >> 29
            return Double(h % 1000) / 1000
        }
        let s = CGFloat(size) * 3.4 * zoom
        // The pool: three overlapping ellipses, so it is a shape rather than a
        // dot. Squashed vertically because the ground is seen at an angle.
        for i in 0..<3 {
            let dx = CGFloat(roll() - 0.5) * s * 0.9
            let dy = CGFloat(roll() - 0.5) * s * 0.4
            let w = s * CGFloat(0.55 + roll() * 0.7)
            let blob = CGRect(x: p.x + dx - w / 2, y: p.y + dy - w * 0.22,
                              width: w, height: w * 0.44)
            context.fill(Path(ellipseIn: blob),
                         with: .color((i == 0 ? fresh : dried).opacity(0.42)))
        }
        // …and what was thrown clear of it.
        for _ in 0..<4 {
            let a = roll() * 2 * .pi
            let r = s * CGFloat(0.6 + roll() * 1.1)
            let d = s * CGFloat(0.10 + roll() * 0.10)
            let q = CGPoint(x: p.x + CGFloat(cos(a)) * r, y: p.y + CGFloat(sin(a)) * r * 0.45)
            context.fill(Path(ellipseIn: CGRect(x: q.x - d / 2, y: q.y - d / 4,
                                                width: d, height: d * 0.6)),
                         with: .color(dried.opacity(0.38)))
        }
    }

    // MARK: - The moment itself

    /// A blow landing: a short bright edge at the point of contact and a spray
    /// of blood away from it.
    ///
    /// `along` is the direction the blow travelled — the spray goes that way,
    /// because that is where it would go.
    static func impact(
        _ context: inout GraphicsContext, at p: CGPoint, along: (x: Double, y: Double),
        age: Double, fatal: Bool, unit: CGFloat, seed: Int
    ) {
        var h = UInt64(bitPattern: Int64(seed)) &* 0x9E37_79B9_7F4A_7C15 | 1
        func roll() -> Double {
            h ^= h >> 33; h = h &* 0xFF51_AFD7_ED55_8CCD; h ^= h >> 29
            return Double(h % 1000) / 1000
        }
        // Steel on bone: a hard white tick, gone almost at once.
        if age < flash {
            let fade = 1 - age / flash
            let r = unit * 0.006 * CGFloat(0.6 + fade * 0.8)
            context.stroke(Path { path in
                path.move(to: CGPoint(x: p.x - CGFloat(along.y) * r, y: p.y + CGFloat(along.x) * r))
                path.addLine(to: CGPoint(x: p.x + CGFloat(along.y) * r, y: p.y - CGFloat(along.x) * r))
            }, with: .color(Theme.bone.opacity(0.85 * fade)),
               style: StrokeStyle(lineWidth: max(0.9, unit * 0.0018), lineCap: .round))
        }
        // And the blood, thrown forward along the blow and spreading as it goes.
        guard age < spray else { return }
        let t = age / spray
        let count = fatal ? 9 : 5
        for _ in 0..<count {
            let spread = (roll() - 0.5) * (fatal ? 1.5 : 1.0)
            let dx = along.x * cos(spread) - along.y * sin(spread)
            let dy = along.x * sin(spread) + along.y * cos(spread)
            let reach = unit * CGFloat(0.008 + roll() * (fatal ? 0.030 : 0.016)) * CGFloat(t)
            let q = CGPoint(x: p.x + CGFloat(dx) * reach, y: p.y + CGFloat(dy) * reach)
            let d = unit * CGFloat(0.0016 + roll() * 0.0022)
            context.fill(Path(ellipseIn: CGRect(x: q.x - d, y: q.y - d, width: d * 2, height: d * 2)),
                         with: .color(fresh.opacity((1 - t) * 0.9)))
        }
    }

    // MARK: - What stays on the person

    /// Harm, drawn on the body that took it. `harm` is 0…1 against a whole
    /// person; `zoom` is the figure scale the rest of the canvas draws at.
    ///
    /// This is what replaces the bar over everybody's head. A bar is a readout;
    /// this is an injury, and the difference is that you can tell at a glance
    /// which of the twelve people in the line is the one who is about to go
    /// down.
    static func onBody(
        _ context: inout GraphicsContext, at p: CGPoint, harm: Double,
        zoom: CGFloat, seed: UInt64
    ) {
        guard harm > 0.04 else { return }
        var h = seed | 1
        func roll() -> Double {
            h ^= h >> 33; h = h &* 0xFF51_AFD7_ED55_8CCD; h ^= h >> 29
            return Double(h % 1000) / 1000
        }
        let s = 4.0 * zoom
        // A smear over the torso, growing down the body as it gets worse.
        let run = CGFloat(min(1, harm * 1.6))
        var smear = Path()
        let originX = p.x + CGFloat(roll() - 0.5) * s * 0.4
        smear.move(to: CGPoint(x: originX, y: p.y - s * 0.45))
        smear.addLine(to: CGPoint(x: originX + CGFloat(roll() - 0.5) * s * 0.3,
                                  y: p.y - s * 0.45 + s * 0.75 * run))
        context.stroke(smear, with: .color(fresh.opacity(0.55 + 0.35 * harm)),
                       style: StrokeStyle(lineWidth: max(0.8, s * (0.10 + 0.16 * harm)),
                                          lineCap: .round))
        // Badly hurt, it is running off them and onto the ground.
        guard harm > 0.45 else { return }
        for _ in 0..<2 {
            let d = s * CGFloat(0.10 + roll() * 0.09)
            let q = CGPoint(x: p.x + CGFloat(roll() - 0.5) * s * 0.6, y: p.y + s * CGFloat(0.5 + roll() * 0.5))
            context.fill(Path(ellipseIn: CGRect(x: q.x - d / 2, y: q.y - d / 2,
                                                width: d, height: d)),
                         with: .color(fresh.opacity(0.7)))
        }
    }

    // MARK: - Shared

    /// Where a beat happened, in the order the record can answer it.
    ///
    /// The spot the simulation stamped on it first — that is the point of
    /// impact, and it is right in a live fight and in a replay alike. Failing
    /// that (a raid the player never saw, settled by `BattleResolver`, which has
    /// no field), wherever the person it happened to is standing.
    static func place(
        of moment: BattleMoment, log: BattleLog, field: SiegeField, siege: Siege?
    ) -> LocalPoint? {
        if let spot = moment.spot { return spot }
        guard let id = moment.pawnID else { return nil }
        if let live = siege?.place(of: id) { return live }
        guard let index = log.line.firstIndex(of: id) else { return nil }
        return field.defenderPost(index: index, of: log.line.count)
    }
}
