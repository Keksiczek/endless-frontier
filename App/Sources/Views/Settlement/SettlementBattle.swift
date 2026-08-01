import SwiftUI
import EndlessFrontierCore

/// A battle, fought in front of you.
///
/// What was here before drew the fight as three enormous red discs sliding
/// toward the middle of the map. It was a placeholder that outlived its welcome
/// by a long way: a raid is the most dramatic thing that happens in the game
/// and it looked like a stain.
///
/// This plays the record out as *people*. Raiders come in over the ground from
/// a fixed bearing and form up. The colony's own line — the pawns the engine
/// actually mustered, `BattleLog.line` — runs out from the town to meet them,
/// and they close over the tick until the two ranks touch. Blades ring where
/// the ranks meet; arrows go the other way when the wall looses. Whoever falls
/// falls *at their place in the line*, and their body stays there while the
/// field clears.
///
/// Strictly presentational. `BattleLog` already carried the order and timing of
/// every beat; this session it also carries who came, how many, and from which
/// side — so nothing here invents anything, and a player who looks away misses
/// the show rather than the outcome.
enum SettlementBattle {
    /// How long after its tick a battle stays on screen. A tick is a real
    /// minute; the fight plays over it and the dead lie a moment longer.
    static let lingerTicks: Double = 0.5

    /// The phases of the tick. The fight is one deterministic step in the
    /// simulation; this is only how it is *paced* on screen.
    private static let closing = 0.34      // marching in and turning out
    private static let melee = 0.82        // the ranks in contact

    // MARK: - The field

    /// Where everything stands. One geometry, shared by the drawing and by
    /// `AgentMotion` — the defenders have to run to the same line the raiders
    /// are drawn breaking on, or the colony fights an empty field.
    struct Field {
        /// The heart of the settlement, which is what is being defended.
        let heart: LocalPoint
        /// Off the edge of the map, where the attackers came from.
        let origin: LocalPoint
        /// Where the two ranks meet.
        let front: LocalPoint
        /// The unit vector along the line the ranks face each other across.
        let axis: (x: Double, y: Double)

        init(_ log: BattleLog, heart: LocalPoint = SettlementRenderer.colonyHeart) {
            self.heart = heart
            let a = log.approach
            axis = (cos(a), sin(a))
            origin = LocalPoint(x: heart.x + axis.x * 0.48, y: heart.y + axis.y * 0.46)
            // The line forms outside the built colony, not on top of it.
            front = LocalPoint(x: heart.x + axis.x * 0.30, y: heart.y + axis.y * 0.29)
        }

        /// The place a given defender holds in the line: shoulder to shoulder,
        /// spread across the front, facing the way the attack came.
        func defenderPost(index: Int, of count: Int) -> LocalPoint {
            post(at: front, index: index, of: count, back: 0.012)
        }

        /// …and where a raider stands opposite them.
        func attackerPost(index: Int, of count: Int) -> LocalPoint {
            post(at: front, index: index, of: count, back: -0.030)
        }

        /// A rank of `count` bodies abreast, `back` behind the front along the
        /// axis of the attack. Fanned a little so it reads as a line of people
        /// rather than a fence.
        private func post(at centre: LocalPoint, index: Int, of count: Int,
                          back: Double) -> LocalPoint {
            let spread = 0.030
            let offset = count <= 1 ? 0 : (Double(index) / Double(count - 1) - 0.5)
            // Perpendicular to the axis: the width of the line.
            let px = -axis.y, py = axis.x
            // A shallow crescent — the ends of a line sag back.
            let sag = abs(offset) * 0.014
            return LocalPoint(
                x: centre.x + px * offset * spread * Double(count) * 0.6
                    + axis.x * (back + sag),
                y: centre.y + py * offset * spread * Double(count) * 0.6
                    + axis.y * (back + sag))
        }
    }

    /// The battle a settlement is fighting right now, if it is fighting one.
    /// Both the canvas and the colonists' motion ask this — a defender is only
    /// pulled out of their day while the fight is actually running.
    static func live(_ settlement: Settlement, continuousTick: Double) -> (log: BattleLog, progress: Double)? {
        guard let log = settlement.lastBattle else { return nil }
        let elapsed = continuousTick - Double(log.tick)
        guard elapsed >= 0, elapsed <= 1 + lingerTicks else { return nil }
        return (log, min(1, elapsed))
    }

    /// Where a colonist called to the line should be at `progress`, and whether
    /// they have arrived. Returns nil for anyone not in this fight.
    ///
    /// This is the whole of "the garrison converges": the colonist is not drawn
    /// twice, they simply stop living their day and go where the fighting is.
    static func station(
        for pawnID: UUID, log: BattleLog, progress: Double, from: LocalPoint
    ) -> (position: LocalPoint, arrived: Bool)? {
        guard let index = log.line.firstIndex(of: pawnID) else { return nil }
        let field = Field(log)
        let post = field.defenderPost(index: index, of: log.line.count)
        // They run out over the first third of the tick, then hold.
        let t = min(1, progress / closing)
        let eased = t * t * (3 - 2 * t)
        return (LocalPoint(x: from.x + (post.x - from.x) * eased,
                           y: from.y + (post.y - from.y) * eased),
                t >= 1)
    }

    // MARK: - Drawing

    static func draw(
        _ context: inout GraphicsContext, rect: CGRect, settlement: Settlement,
        continuousTick: Double, time: Double, zoom: CGFloat
    ) {
        guard let (log, progress) = live(settlement, continuousTick: continuousTick) else { return }
        let field = Field(log)
        let unit = min(rect.width, rect.height)

        // The raiders: in over the ground, then held at the line, then either
        // driven back off the map or pushing through into the town.
        let count = log.drawnAttackers
        let march = min(1, progress / closing)
        let fallen = casualties(log, upTo: progress)
        for i in 0..<count {
            let post = field.attackerPost(index: i, of: count)
            var p = interpolate(field.origin, post, t: ease(march))
            if progress > melee {
                let after = (progress - melee) / (1 - melee)
                let away = log.repelled
                    ? interpolate(post, field.origin, t: ease(after))
                    : interpolate(post, field.heart, t: ease(after) * 0.7)
                p = away
            }
            // A little jostle, so a rank of raiders is not a row of stamps.
            let jitter = sin(time * 3.4 + Double(i) * 1.7) * 0.0022
            raider(&context, at: SettlementRenderer.point(
                LocalPoint(x: p.x + jitter, y: p.y + jitter * 0.6), in: rect),
                   zoom: zoom, time: time, phase: Double(i) * 0.9,
                   fighting: progress > closing && progress < melee)
        }

        // The line itself: where the two ranks touch, a bright seam of contact
        // that brightens as blades land.
        if progress > closing {
            contact(&context, field: field, rect: rect, log: log,
                    progress: progress, time: time, unit: unit)
        }

        // The beats: arrows away from the wall, sparks at the seam, and the
        // dead marked where they stood.
        for moment in log.moments(upTo: progress) {
            let age = progress - moment.at
            guard age >= 0, age < 0.4 else { continue }
            let fade = 1 - age / 0.4
            switch moment.kind {
            case .volley:
                volley(&context, field: field, rect: rect, fade: fade, zoom: zoom)
            case .clash, .charge:
                sparks(&context, at: SettlementRenderer.point(field.front, in: rect),
                       fade: fade, unit: unit, seed: moment.id)
            case .wound:
                if let p = place(of: moment, log: log, field: field) {
                    hit(&context, at: SettlementRenderer.point(p, in: rect),
                        fade: fade, unit: unit, tint: Theme.accent)
                }
            case .death:
                if let p = place(of: moment, log: log, field: field) {
                    hit(&context, at: SettlementRenderer.point(p, in: rect),
                        fade: fade, unit: unit, tint: Theme.danger)
                }
            case .plunder:
                plunder(&context, field: field, rect: rect, fade: fade, unit: unit)
            case .repelled:
                horn(&context, at: SettlementRenderer.point(field.front, in: rect),
                     fade: fade, unit: unit)
            }
        }

        // And the bodies, lying where they fell for as long as the field stays.
        for (index, moment) in fallen.enumerated() {
            guard let p = place(of: moment, log: log, field: field) else { continue }
            body(&context, at: SettlementRenderer.point(p, in: rect),
                 zoom: zoom, seed: UInt64(index &+ moment.id))
        }
    }

    /// Where a beat happened: at the fallen colonist's post in the line if they
    /// were in it, otherwise at the front.
    private static func place(of moment: BattleMoment, log: BattleLog, field: Field) -> LocalPoint? {
        guard let id = moment.pawnID else { return field.front }
        guard let index = log.line.firstIndex(of: id) else { return field.front }
        return field.defenderPost(index: index, of: log.line.count)
    }

    private static func casualties(_ log: BattleLog, upTo progress: Double) -> [BattleMoment] {
        log.moments(upTo: progress).filter { $0.kind == .death }
    }

    // MARK: - Figures

    /// A raider: a dark figure with a weapon, leaning into the advance.
    private static func raider(
        _ context: inout GraphicsContext, at p: CGPoint, zoom: CGFloat,
        time: Double, phase: Double, fighting: Bool
    ) {
        let s = 4.2 * zoom
        let swing = fighting
            ? CGFloat(sin(time * 9 + phase)) * s * 0.5
            : CGFloat(sin(time * 5 + phase)) * s * 0.18
        let skin = Color(red: 0.62, green: 0.30, blue: 0.27)
        let cloth = Color(red: 0.38, green: 0.18, blue: 0.18)

        // Shadow first, so they stand on the ground.
        context.fill(Path(ellipseIn: CGRect(x: p.x - s * 0.5, y: p.y + s * 0.85,
                                            width: s, height: s * 0.34)),
                     with: .color(.black.opacity(0.28)))
        // Head, body, legs.
        context.fill(Path(ellipseIn: CGRect(x: p.x - s * 0.30, y: p.y - s * 1.15,
                                            width: s * 0.6, height: s * 0.6)),
                     with: .color(skin))
        var frame = Path()
        frame.move(to: CGPoint(x: p.x, y: p.y - s * 0.55))
        frame.addLine(to: CGPoint(x: p.x, y: p.y + s * 0.28))
        frame.move(to: CGPoint(x: p.x - s * 0.34 + swing * 0.2, y: p.y + s * 0.95))
        frame.addLine(to: CGPoint(x: p.x, y: p.y + s * 0.28))
        frame.addLine(to: CGPoint(x: p.x + s * 0.34 - swing * 0.2, y: p.y + s * 0.95))
        context.stroke(frame, with: .color(cloth),
                       style: StrokeStyle(lineWidth: max(1, s * 0.26), lineCap: .round))
        // The weapon arm, swinging when the ranks are in contact.
        context.stroke(Path { path in
            path.move(to: CGPoint(x: p.x, y: p.y - s * 0.35))
            path.addLine(to: CGPoint(x: p.x + s * 0.75, y: p.y - s * 0.35 - swing))
        }, with: .color(Theme.boneDim.opacity(0.9)),
           style: StrokeStyle(lineWidth: max(0.8, s * 0.16), lineCap: .round))
    }

    /// Someone who is not getting up. Drawn flat, which is the whole point.
    private static func body(
        _ context: inout GraphicsContext, at p: CGPoint, zoom: CGFloat, seed: UInt64
    ) {
        let s = 4.0 * zoom
        let angle = Double(seed % 7) * 0.4 - 0.8
        context.fill(Path(ellipseIn: CGRect(x: p.x - s * 0.7, y: p.y - s * 0.2,
                                            width: s * 1.4, height: s * 0.5)),
                     with: .color(.black.opacity(0.32)))
        var lying = Path()
        lying.move(to: CGPoint(x: p.x - CGFloat(cos(angle)) * s * 0.6,
                               y: p.y - CGFloat(sin(angle)) * s * 0.3))
        lying.addLine(to: CGPoint(x: p.x + CGFloat(cos(angle)) * s * 0.6,
                                  y: p.y + CGFloat(sin(angle)) * s * 0.3))
        context.stroke(lying, with: .color(Theme.boneDim.opacity(0.75)),
                       style: StrokeStyle(lineWidth: max(1, s * 0.3), lineCap: .round))
        context.fill(Path(ellipseIn: CGRect(x: p.x - CGFloat(cos(angle)) * s * 0.7 - s * 0.22,
                                            y: p.y - CGFloat(sin(angle)) * s * 0.35 - s * 0.22,
                                            width: s * 0.44, height: s * 0.44)),
                     with: .color(Theme.boneDim.opacity(0.7)))
    }

    // MARK: - The seam

    /// The line where the ranks meet: a bright band that pulses with the fight.
    private static func contact(
        _ context: inout GraphicsContext, field: Field, rect: CGRect,
        log: BattleLog, progress: Double, time: Double, unit: CGFloat
    ) {
        let count = max(2, log.line.count)
        let a = SettlementRenderer.point(field.defenderPost(index: 0, of: count), in: rect)
        let b = SettlementRenderer.point(field.defenderPost(index: count - 1, of: count), in: rect)
        let heat = progress < melee ? 1.0 : max(0, 1 - (progress - melee) / (1 - melee))
        let pulse = 0.5 + 0.5 * sin(time * 7)
        context.stroke(Path { p in
            p.move(to: a)
            p.addLine(to: b)
        }, with: .color(Theme.danger.opacity(0.16 * heat * (0.6 + pulse * 0.4))),
           style: StrokeStyle(lineWidth: unit * 0.035, lineCap: .round))
    }

    /// Arrows loosed from the colony's side, back down the road.
    private static func volley(
        _ context: inout GraphicsContext, field: Field, rect: CGRect,
        fade: Double, zoom: CGFloat
    ) {
        for i in 0..<6 {
            let t = 0.15 + Double(i) * 0.12
            let spread = (Double(i) - 2.5) * 0.012
            let px = -field.axis.y * spread, py = field.axis.x * spread
            let from = LocalPoint(x: field.front.x + px, y: field.front.y + py)
            let to = LocalPoint(x: field.origin.x + px, y: field.origin.y + py)
            let a = SettlementRenderer.point(interpolate(from, to, t: t), in: rect)
            let b = SettlementRenderer.point(interpolate(from, to, t: t + 0.06), in: rect)
            context.stroke(Path { p in
                p.move(to: a)
                p.addLine(to: b)
            }, with: .color(Theme.bone.opacity(0.75 * fade)),
               style: StrokeStyle(lineWidth: max(0.7, zoom), lineCap: .round))
        }
    }

    /// Sparks where steel meets steel.
    private static func sparks(
        _ context: inout GraphicsContext, at p: CGPoint, fade: Double,
        unit: CGFloat, seed: Int
    ) {
        var h = UInt64(bitPattern: Int64(seed)) &* 0x9E37_79B9_7F4A_7C15 | 1
        for _ in 0..<5 {
            h ^= h >> 33; h = h &* 0xFF51_AFD7_ED55_8CCD
            let a = Double(h % 360) * .pi / 180
            let r = unit * (0.006 + 0.020 * (1 - fade))
            let q = CGPoint(x: p.x + CGFloat(cos(a)) * r, y: p.y + CGFloat(sin(a)) * r)
            context.stroke(Path { path in
                path.move(to: q)
                path.addLine(to: CGPoint(x: q.x + CGFloat(cos(a)) * unit * 0.008,
                                         y: q.y + CGFloat(sin(a)) * unit * 0.008))
            }, with: .color(Theme.accent.opacity(0.85 * fade)), lineWidth: 1)
        }
    }

    /// A hit landing on someone: a short, sharp ring at their place in the line.
    private static func hit(
        _ context: inout GraphicsContext, at p: CGPoint, fade: Double,
        unit: CGFloat, tint: Color
    ) {
        let r = unit * (0.008 + 0.016 * (1 - fade))
        context.stroke(
            Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)),
            with: .color(tint.opacity(0.9 * fade)), lineWidth: 1.6)
    }

    /// Stores going the other way, on somebody's back.
    private static func plunder(
        _ context: inout GraphicsContext, field: Field, rect: CGRect,
        fade: Double, unit: CGFloat
    ) {
        for i in 0..<3 {
            let t = 0.3 + Double(i) * 0.14
            let p = SettlementRenderer.point(
                interpolate(field.front, field.origin, t: t), in: rect)
            let s = unit * 0.010
            context.fill(Path(CGRect(x: p.x - s / 2, y: p.y - s / 2, width: s, height: s)),
                         with: .color(Theme.accent.opacity(0.55 * fade)))
        }
    }

    /// The moment it breaks: a ring going out from the line.
    private static func horn(
        _ context: inout GraphicsContext, at p: CGPoint, fade: Double, unit: CGFloat
    ) {
        let r = unit * (0.04 + 0.07 * (1 - fade))
        context.stroke(
            Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)),
            with: .color(Theme.good.opacity(0.7 * fade)), lineWidth: 1.6)
    }

    // MARK: - Maths

    private static func interpolate(_ a: LocalPoint, _ b: LocalPoint, t: Double) -> LocalPoint {
        LocalPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
    }

    private static func ease(_ t: Double) -> Double {
        let c = min(1, max(0, t))
        return c * c * (3 - 2 * c)
    }
}
