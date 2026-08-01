import SwiftUI
import EndlessFrontierCore

/// A battle, fought in front of you — and slow enough to follow.
///
/// The first version of this replaced three enormous red discs with people,
/// which was right, but it played the record at the **tick's** own pace. A tick
/// is a real minute and `BattleResolver` gives a fight eight rounds, so the
/// whole thing came out as one exchange every seven and a half seconds: a
/// fight you could stare straight at and see nothing happen in. That, and the
/// fact that raids are a once-a-year roll, is the whole of "I never see any
/// fighting".
///
/// Three things change that:
///
/// 1. **The record is played back, not lived through.** Twenty seconds for the
///    whole fight, whatever tick it happened on, so eight rounds land at a
///    pace a person can read. See `playSeconds`.
/// 2. **The fight has a shape you can name.** Four phases — they come over the
///    ground, the wall looses, the ranks are in contact, and it breaks — with
///    a caption on the canvas saying which one you are watching and what the
///    tally is. This is the "order" the fight was missing.
/// 3. **Everyone is fighting somebody.** Each raider is paired with the
///    colonist opposite them, closes to arm's length, and trades blows *on the
///    beat the record says a blow landed*. The wounded show it; whoever falls
///    falls at their place in the line and stays there.
///
/// Strictly presentational. `BattleLog` carried the order and timing of every
/// beat, who came, how many and from which side; nothing here invents anything.
enum SettlementBattle {

    // MARK: - Pace

    /// Real seconds the whole record is played over.
    ///
    /// Not the length of the tick it happened in: this is a replay, and it may
    /// run at whatever speed makes it legible. Twenty seconds over eight rounds
    /// is an exchange every two and a half — quick enough to be a fight, slow
    /// enough to see who is hit.
    static let playSeconds: Double = 20

    /// How long the field stays after the last blow: the dead lying where they
    /// fell, the raiders' backs going over the hill.
    static let lingerSeconds: Double = 14

    /// The linger as a fraction of the play-through, which is the unit
    /// `progress` is in.
    static var lingerFraction: Double { lingerSeconds / playSeconds }

    /// A fight the player has asked to see again.
    ///
    /// A raid lasts half a minute inside an hour of colony time. Looking away
    /// used to mean missing it for good — the report card would tell you what
    /// it cost and the thing itself was gone. This is the same record, played
    /// from the top, on a clock of its own.
    struct Replay: Equatable {
        let log: BattleLog
        let startedAt: Date

        init(log: BattleLog, startedAt: Date = Date()) {
            self.log = log
            self.startedAt = startedAt
        }
    }

    // MARK: - The shape of a fight

    /// What is happening right now. The whole point of naming these is that
    /// the player can be *told* which one they are looking at.
    enum Phase: Equatable {
        /// Coming over the ground; the line runs out to meet them.
        case marching
        /// The wall looses, before they are close enough to answer.
        case volley
        /// The ranks in contact.
        case melee
        /// It breaks — back off the map, or through into the town.
        case breaking
    }

    static let volleyAt = 0.26
    static let meleeAt = 0.40
    static let breakAt = 0.84

    static func phase(at progress: Double) -> Phase {
        switch progress {
        case ..<volleyAt: return .marching
        case ..<meleeAt: return .volley
        case ..<breakAt: return .melee
        default: return .breaking
        }
    }

    /// The line across the top of the fight: who is on the field, at what
    /// stage, and what it has cost so far.
    static func caption(_ log: BattleLog, progress: Double, cs: Bool) -> String {
        let attacker = log.attacker(cs ? .cs : .en)
        let standing = attackersStanding(log, at: progress)
        let head = "\(attacker) \(standing) — \(log.defenderName) \(defendersStanding(log, at: progress))"
        let stage: String
        switch phase(at: progress) {
        case .marching: stage = cs ? "táhnou na osadu" : "coming over the ground"
        case .volley:   stage = cs ? "salva" : "the wall looses"
        case .melee:    stage = cs ? "boj muže proti muži" : "the ranks are in contact"
        case .breaking: stage = log.repelled
            ? (cs ? "odraženi" : "turned back")
            : (cs ? "prolomili obranu" : "through the line")
        }
        return "\(head) · \(stage)"
    }

    // MARK: - Who is still up

    /// How many raiders are still on their feet at this point of the replay.
    ///
    /// The resolver settles the fight on one strength number, so the log has no
    /// per-raider deaths to read. What it does have is the outcome, and that is
    /// enough to be honest with: the rank thins through the melee, and by the
    /// end a broken assault has nobody left standing and a successful one has
    /// paid for it.
    static func attackersStanding(_ log: BattleLog, at progress: Double) -> Int {
        let count = log.drawnAttackers
        guard progress > meleeAt else { return count }
        let through = min(1, (progress - meleeAt) / (breakAt - meleeAt))
        let survivors = log.repelled ? 0.0 : Double(count) * 0.55
        return max(log.repelled ? 0 : 1,
                   Int((Double(count) + (survivors - Double(count)) * through).rounded()))
    }

    /// …and how much of the colony's line is still standing, from the deaths
    /// the record actually names.
    static func defendersStanding(_ log: BattleLog, at progress: Double) -> Int {
        let fallen = Set(log.moments(upTo: progress)
            .filter { $0.kind == .death }
            .compactMap(\.pawnID))
        return max(0, log.line.count - log.line.filter { fallen.contains($0) }.count)
    }

    /// How badly a given defender has been hurt by this point, 0 (untouched) …
    /// 1 (down). Read from the wounds the record stamped on them, so the bar
    /// over someone's head is the damage the simulation actually dealt.
    static func harm(_ log: BattleLog, pawn: UUID, at progress: Double) -> Double {
        var taken = 0.0
        for moment in log.moments(upTo: progress) where moment.pawnID == pawn {
            switch moment.kind {
            case .death: return 1
            case .wound: taken += moment.amount
            default: break
            }
        }
        // Against a hundred, which is what a colonist has.
        return min(0.95, taken / 100)
    }

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

        /// …and where a raider stands opposite them. `closed` walks the rank in
        /// to arm's length once the ranks are in contact, which is the whole
        /// difference between two lines of people and a fight.
        func attackerPost(index: Int, of count: Int, closed: Double = 0) -> LocalPoint {
            post(at: front, index: index, of: count,
                 back: -0.030 + 0.016 * min(1, max(0, closed)))
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

    /// The battle a settlement is fighting right now, if it is fighting one —
    /// or the one the player asked to see again.
    ///
    /// Both the canvas and the colonists' motion ask this, so a defender is
    /// pulled out of their day for exactly as long as the fight is on screen.
    static func live(
        _ settlement: Settlement, continuousTick: Double,
        secondsPerTick: Double = 60, replay: Replay? = nil, now: Date = Date()
    ) -> (log: BattleLog, progress: Double)? {
        // A replay outranks the live fight: the player asked for this one.
        if let replay {
            let elapsed = now.timeIntervalSince(replay.startedAt) / playSeconds
            if elapsed >= 0, elapsed <= 1 + lingerFraction {
                return (replay.log, min(1, elapsed))
            }
        }
        guard let log = settlement.lastBattle else { return nil }
        let speed = max(1, secondsPerTick) / playSeconds
        let elapsed = (continuousTick - Double(log.tick)) * speed
        guard elapsed >= 0, elapsed <= 1 + lingerFraction else { return nil }
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
        // They run out while the raiders are still coming on, and hold from
        // the volley onward.
        let t = min(1, progress / volleyAt)
        let eased = t * t * (3 - 2 * t)
        return (LocalPoint(x: from.x + (post.x - from.x) * eased,
                           y: from.y + (post.y - from.y) * eased),
                t >= 1)
    }

    // MARK: - Drawing

    static func draw(
        _ context: inout GraphicsContext, rect: CGRect, settlement: Settlement,
        continuousTick: Double, time: Double, zoom: CGFloat,
        secondsPerTick: Double = 60, replay: Replay? = nil
    ) {
        guard let (log, progress) = live(settlement, continuousTick: continuousTick,
                                         secondsPerTick: secondsPerTick,
                                         replay: replay) else { return }
        draw(&context, rect: rect, log: log, progress: progress, time: time, zoom: zoom)
    }

    /// The fight itself, from a record and a point inside it. Split out so a
    /// test — and a replay — can drive it at any moment without a settlement.
    static func draw(
        _ context: inout GraphicsContext, rect: CGRect, log: BattleLog,
        progress: Double, time: Double, zoom: CGFloat
    ) {
        let field = Field(log)
        let unit = min(rect.width, rect.height)
        let stage = phase(at: progress)

        // How far the ranks have closed on each other, and how hard the fight
        // is going at this instant.
        let closing = min(1, progress / volleyAt)
        let closed = stage == .marching ? 0
            : min(1, max(0, (progress - volleyAt) / (meleeAt - volleyAt)))
        let strike = strikeBeat(log, at: progress)

        // The raiders. They come in over the ground, form up opposite the line,
        // close, and then either go back over the hill or push through.
        let count = log.drawnAttackers
        let standing = attackersStanding(log, at: progress)
        let defenders = max(1, log.line.count)
        for i in 0..<count {
            let post = field.attackerPost(index: i, of: count, closed: closed)
            var p = interpolate(field.origin, post, t: ease(closing))
            var down = false
            if progress > breakAt {
                let after = (progress - breakAt) / (1 - breakAt)
                p = log.repelled
                    ? interpolate(post, field.origin, t: ease(after))
                    : interpolate(post, field.heart, t: ease(after) * 0.7)
            }
            // Whoever is past the standing count has been put down — the rank
            // visibly thins instead of nine raiders walking away from a fight
            // the colony won.
            if i >= standing {
                down = true
                p = post
            }
            let screen = SettlementRenderer.point(p, in: rect)
            if down {
                body(&context, at: screen, zoom: zoom, seed: UInt64(i &* 31))
                continue
            }
            // A little jostle, so a rank of raiders is not a row of stamps.
            let jitter = sin(time * 3.4 + Double(i) * 1.7) * 0.0022
            raider(&context,
                   at: CGPoint(x: screen.x + CGFloat(jitter) * rect.width,
                               y: screen.y + CGFloat(jitter) * 0.6 * rect.height),
                   facing: field.axis, zoom: zoom, time: time, phase: Double(i) * 0.9,
                   swinging: stage == .melee ? strike : 0)
            // Who they are fighting: a short line to the colonist opposite,
            // drawn only while the ranks are in contact.
            if stage == .melee, defenders > 0 {
                let opposite = defenders == 1 ? 0 : i * (defenders - 1) / max(1, count - 1)
                pairing(&context, from: screen,
                        to: SettlementRenderer.point(
                            field.defenderPost(index: opposite, of: defenders), in: rect),
                        fade: strike * 0.5 + 0.12, unit: unit)
            }
        }

        // The line itself: where the two ranks touch, a bright seam of contact
        // that brightens as blades land.
        if stage == .melee || stage == .breaking {
            contact(&context, field: field, rect: rect, log: log,
                    progress: progress, strike: strike, unit: unit)
        }

        // What the fight has done to the colonists holding the line, over their
        // heads: a wound is a thing you can see happening to somebody.
        for (index, id) in log.line.enumerated() {
            let hurt = harm(log, pawn: id, at: progress)
            guard hurt > 0.01 else { continue }
            let post = field.defenderPost(index: index, of: log.line.count)
            wounded(&context, at: SettlementRenderer.point(post, in: rect),
                    harm: hurt, unit: unit, zoom: zoom)
        }

        // The beats: arrows away from the wall, sparks at the seam, and the
        // dead marked where they stood.
        for moment in log.moments(upTo: progress) {
            let age = progress - moment.at
            guard age >= 0, age < 0.12 else { continue }
            let fade = 1 - age / 0.12
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
        for (index, moment) in casualties(log, upTo: progress).enumerated() {
            guard let p = place(of: moment, log: log, field: field) else { continue }
            body(&context, at: SettlementRenderer.point(p, in: rect),
                 zoom: zoom, seed: UInt64(index &+ moment.id))
        }

        banner(&context, rect: rect, log: log, progress: progress)
    }

    /// How hard a blow is landing right now, 0…1 — a spike at every clash in
    /// the record, decaying between them.
    ///
    /// This is what makes the swing mean something. Before it, every raider
    /// swung on a free-running sine and the arms moved whether or not anything
    /// was happening; now the rank strikes *together, on the beat the fight was
    /// actually resolved on*.
    static func strikeBeat(_ log: BattleLog, at progress: Double) -> Double {
        var best = 0.0
        for moment in log.moments(upTo: progress)
        where moment.kind == .clash || moment.kind == .charge {
            let age = progress - moment.at
            guard age >= 0, age < 0.10 else { continue }
            best = max(best, 1 - age / 0.10)
        }
        return best
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

    // MARK: - Telling the player what they are watching

    /// The caption: who is fighting whom, how many of each are up, and which
    /// part of the fight this is. Drawn over the field, high enough to clear it.
    private static func banner(
        _ context: inout GraphicsContext, rect: CGRect, log: BattleLog, progress: Double
    ) {
        let text = Text(caption(log, progress: progress, cs: AppStrings.language == .cs))
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(Theme.bone)
        let resolved = context.resolve(text)
        let size = resolved.measure(in: CGSize(width: rect.width, height: 40))
        let centre = CGPoint(x: rect.midX, y: rect.minY + rect.height * 0.06)
        let plate = CGRect(x: centre.x - size.width / 2 - 8, y: centre.y - size.height / 2 - 4,
                           width: size.width + 16, height: size.height + 8)
        context.fill(Path(roundedRect: plate, cornerRadius: plate.height / 2),
                     with: .color(Theme.ink.opacity(0.72)))
        context.stroke(Path(roundedRect: plate, cornerRadius: plate.height / 2),
                       with: .color(Theme.danger.opacity(0.55)), lineWidth: 1)
        context.draw(resolved, at: centre)
    }

    /// Who is fighting whom: a faint thread between a raider and the colonist
    /// they closed with. Drawn under the figures, so it reads as engagement
    /// rather than as a wire.
    private static func pairing(
        _ context: inout GraphicsContext, from: CGPoint, to: CGPoint,
        fade: Double, unit: CGFloat
    ) {
        context.stroke(Path { p in
            p.move(to: from)
            p.addLine(to: to)
        }, with: .color(Theme.danger.opacity(0.16 * fade)),
           style: StrokeStyle(lineWidth: max(0.6, unit * 0.0016), lineCap: .round))
    }

    /// A colonist taking it: a short bar over their head that empties as the
    /// wounds land.
    private static func wounded(
        _ context: inout GraphicsContext, at p: CGPoint, harm: Double,
        unit: CGFloat, zoom: CGFloat
    ) {
        let w = 9 * zoom, h = 1.6 * zoom
        let y = p.y - 11 * zoom
        let bar = CGRect(x: p.x - w / 2, y: y, width: w, height: h)
        context.fill(Path(roundedRect: bar, cornerRadius: h / 2),
                     with: .color(Theme.ink.opacity(0.7)))
        let left = CGRect(x: bar.minX, y: y, width: w * CGFloat(1 - harm), height: h)
        context.fill(Path(roundedRect: left, cornerRadius: h / 2),
                     with: .color(harm > 0.6 ? Theme.danger : Theme.accent))
    }

    // MARK: - Figures

    /// A raider: a dark figure with a shield and a weapon, leaning into the
    /// advance and swinging when the record says a blow landed.
    private static func raider(
        _ context: inout GraphicsContext, at p: CGPoint, facing: (x: Double, y: Double),
        zoom: CGFloat, time: Double, phase: Double, swinging: Double
    ) {
        let s = 4.2 * zoom
        // The idle sway everyone has, plus the swing the fight actually calls
        // for. A rank striking together is the thing that reads as a fight.
        let sway = CGFloat(sin(time * 5 + phase)) * s * 0.16
        let blow = CGFloat(sin(swinging * .pi)) * s * 0.85
        let swing = sway + blow
        let skin = Color(red: 0.62, green: 0.30, blue: 0.27)
        let cloth = Color(red: 0.38, green: 0.18, blue: 0.18)
        // Which way they are facing: back down the line they came in on.
        let lean = CGFloat(-facing.x) * s * 0.18

        // Shadow first, so they stand on the ground.
        context.fill(Path(ellipseIn: CGRect(x: p.x - s * 0.5, y: p.y + s * 0.85,
                                            width: s, height: s * 0.34)),
                     with: .color(.black.opacity(0.28)))
        // Head, body, legs.
        context.fill(Path(ellipseIn: CGRect(x: p.x - s * 0.30 + lean, y: p.y - s * 1.15,
                                            width: s * 0.6, height: s * 0.6)),
                     with: .color(skin))
        var frame = Path()
        frame.move(to: CGPoint(x: p.x + lean * 0.5, y: p.y - s * 0.55))
        frame.addLine(to: CGPoint(x: p.x, y: p.y + s * 0.28))
        frame.move(to: CGPoint(x: p.x - s * 0.34 + swing * 0.2, y: p.y + s * 0.95))
        frame.addLine(to: CGPoint(x: p.x, y: p.y + s * 0.28))
        frame.addLine(to: CGPoint(x: p.x + s * 0.34 - swing * 0.2, y: p.y + s * 0.95))
        context.stroke(frame, with: .color(cloth),
                       style: StrokeStyle(lineWidth: max(1, s * 0.26), lineCap: .round))
        // A shield on the off arm — the thing a line of raiders reads as.
        let shield = CGRect(x: p.x - s * 0.95, y: p.y - s * 0.62,
                            width: s * 0.62, height: s * 0.98)
        context.fill(Path(ellipseIn: shield), with: .color(cloth.opacity(0.92)))
        context.stroke(Path(ellipseIn: shield),
                       with: .color(Theme.boneDim.opacity(0.55)), lineWidth: max(0.5, s * 0.10))
        // The weapon arm, over the shoulder and down through on the beat.
        let reach = s * (0.72 + Double(swinging) * 0.55)
        context.stroke(Path { path in
            path.move(to: CGPoint(x: p.x, y: p.y - s * 0.35))
            path.addLine(to: CGPoint(x: p.x + CGFloat(reach), y: p.y - s * 0.35 - swing))
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

    /// The line where the ranks meet: a bright band that flares as blades land
    /// rather than pulsing on a clock of its own.
    private static func contact(
        _ context: inout GraphicsContext, field: Field, rect: CGRect,
        log: BattleLog, progress: Double, strike: Double, unit: CGFloat
    ) {
        let count = max(2, log.line.count)
        let a = SettlementRenderer.point(field.defenderPost(index: 0, of: count), in: rect)
        let b = SettlementRenderer.point(field.defenderPost(index: count - 1, of: count), in: rect)
        let heat = progress < breakAt ? 1.0 : max(0, 1 - (progress - breakAt) / (1 - breakAt))
        context.stroke(Path { p in
            p.move(to: a)
            p.addLine(to: b)
        }, with: .color(Theme.danger.opacity(0.14 * heat * (0.5 + strike * 0.9))),
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
