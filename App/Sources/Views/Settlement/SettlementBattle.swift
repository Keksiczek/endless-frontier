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

    /// **How long one beat of a fight stays on the screen**, as a share of the
    /// whole siege.
    ///
    /// One step of the fight and no longer. It was 0.12 — very nearly *three*
    /// steps — so three volleys were on screen at once, overlapping, each
    /// fading through the next. Keks: *"střílení je docela rychlé."* It was not
    /// the rate: a step is fifteen real seconds and at most one volley is
    /// loosed in it. It was that a volley outlived its own step threefold and
    /// the next began before the last had gone, which reads as continuous fire.
    ///
    /// Derived from the fight's own length rather than written down, so the
    /// two cannot drift apart (rule 35: a number that must equal another number
    /// should *be* that number) — and so a long siege's beats are not three
    /// times shorter on screen than a short one's just because it has more of
    /// them. A beat is one step, whatever the fight.
    static func momentLife(steps: Int) -> Double { 1 / Double(max(1, steps)) }

    /// The default beat, for a picture with no siege behind it.
    static var momentLife: Double { momentLife(steps: Siege.stepsTotal) }
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

    /// The same question, asked of a fight that is **happening**.
    ///
    /// A replay has only a clock to read the phase off, so it uses the fractions
    /// above. A live siege has a ground: "the ranks are in contact" is people
    /// being close enough to reach each other, and the caption stops being a
    /// guess about the fight and becomes a description of it.
    static func phase(of siege: Siege) -> Phase {
        if siege.isFinished || siege.progress >= breakAt { return .breaking }
        if siege.inContact { return .melee }
        return siege.moments.contains { $0.kind == .volley } ? .volley : .marching
    }

    /// The line across the top of the fight: who is on the field, at what
    /// stage, and what it has cost so far.
    static func caption(
        _ log: BattleLog, progress: Double, cs: Bool, siege: Siege? = nil
    ) -> String {
        let attacker = log.attacker(cs ? .cs : .en)
        // Live, both tallies are counted off the field rather than estimated
        // from the outcome — because there is a field to count.
        let standing = siege.map { $0.raiders.count { !$0.down } }
            ?? attackersStanding(log, at: progress)
        let holding = siege.map { $0.defenders.count { !$0.down } }
            ?? defendersStanding(log, at: progress)
        let head = "\(attacker) \(standing) — \(log.defenderName) \(holding)"
        let stage: String
        switch siege.map({ phase(of: $0) }) ?? phase(at: progress) {
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

    /// Where everything stands — **from the Core**.
    ///
    /// This used to be a struct of its own here, and it had to be: the fight
    /// was arithmetic on one strength number and a round index, so the canvas
    /// invented an arrangement of people to hang it on. `SiegeField` is the
    /// simulation's own geometry now (rule 8: one number, one place), and a
    /// live fight is *read* off real positions rather than choreographed.
    static func ground(_ log: BattleLog) -> SiegeField {
        SiegeField(approach: log.approach, heart: SettlementRenderer.colonyHeart,
                   edge: log.edge > 0 ? log.edge : SiegeField.wallReach)
    }

    /// Where a raider stands in a **replay**. A finished record has no
    /// positions in it — only who came, from where, and what happened when —
    /// so the old staging is kept for playing one back. `closed` walks the rank
    /// in to arm's length as the ranks meet.
    static func stagedAttackerPost(
        _ field: SiegeField, index: Int, of count: Int, closed: Double
    ) -> LocalPoint {
        let reach = field.musterAt + 0.040 - 0.018 * min(1, max(0, closed))
        return field.post(index: index, of: count, reach: reach)
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
        // A fight that is **still going on** outranks everything: this is not a
        // recording being played back, it is the thing itself, and the record
        // grows a beat at a time as the simulation writes it.
        if let siege = settlement.siege {
            return (log(of: siege, defender: settlement.name),
                    liveProgress(of: siege, continuousTick: continuousTick))
        }
        // A replay outranks the finished fight: the player asked for this one.
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

    /// **How far through a live fight the picture is, between steps.**
    ///
    /// `Siege.progress` is `step / steps`, and a step only moves when the
    /// simulation resolves one — eight to a tick, one every couple of real
    /// seconds. So the canvas was playing a fight that **jumped**: every beat
    /// was stamped at a progress the drawing arrived at in one leap, so an
    /// arrow never flew (`flight` went 0 → gone in a single frame), impacts
    /// appeared in a lump, and a volley loosed at the far edge of its own step
    /// was drawn as if it had already landed. Keks: *"souboje jsou rozhozené,
    /// efekty a grafika nesedí."*
    ///
    /// The replay path never had this — it interpolates against real seconds —
    /// which is exactly why a replayed fight looked better than the one you
    /// were standing in.
    ///
    /// The clock the canvas already holds is the fix: `continuousTick` is
    /// fractional, and `WorldClock.actionStepsPerTick` steps fit in a tick, so
    /// the share of the current step that has elapsed is a division. Nothing
    /// here changes what happens — the simulation still resolves a step at a
    /// time — it only draws the time *between* two of them.
    /// **How far a body is thrown by the blow it has just taken**, in map units.
    ///
    /// The fight had swings and it had blood on the ground and nothing in
    /// between: a blade went through somebody who walked on exactly as before,
    /// and the only sign of a hit was a stain appearing. Keks: *"radoby se
    /// mydlí."* The Core stamps the step a body was struck on and where the
    /// blow came from (`Siege.Combatant.struckAtStep`); this turns that into a
    /// jolt away from it that decays across the step, so a hit **lands**.
    ///
    /// Strictly presentational: it is an offset applied while drawing, and
    /// nothing here writes a position back (rule 1).
    static func flinch(
        _ who: Siege.Combatant, siege: Siege, within: Double
    ) -> (dx: Double, dy: Double) {
        guard who.struckAtStep == siege.step, let from = who.struckFrom else { return (0, 0) }
        let dx = who.at.x - from.x, dy = who.at.y - from.y
        let d = (dx * dx + dy * dy).squareRoot()
        guard d > 1e-6 else { return (0, 0) }
        // Hardest on the beat, gone by the end of the step.
        let fade = 1 - min(1, max(0, within))
        let throwBack = flinchReach * fade * fade
        return (dx / d * throwBack, dy / d * throwBack)
    }

    /// How far a body is knocked back on the beat, in map units. A third of an
    /// arm's length: enough to read as a body taking a blow, not so much that
    /// the line comes apart every time somebody swings.
    static let flinchReach = SiegeEngine.reach / 3

    /// How much of the current simulation step has elapsed, 0…1.
    static func withinStep(of siege: Siege, continuousTick: Double) -> Double {
        let perTick = Double(WorldClock.actionStepsPerTick)
        let resolvedAt = Double(siege.advancedTo) / perTick
        return min(1, max(0, (continuousTick - resolvedAt) * perTick))
    }

    static func liveProgress(of siege: Siege, continuousTick: Double) -> Double {
        let perTick = Double(WorldClock.actionStepsPerTick)
        // The tick the last resolved step sat in, as a fraction.
        let resolvedAt = Double(siege.advancedTo) / perTick
        let within = min(1, max(0, (continuousTick - resolvedAt) * perTick))
        return min(1, (Double(siege.step) + within) / Double(max(1, siege.steps)))
    }

    /// A live siege, read as the record the drawing already speaks.
    ///
    /// The choreography does not need to know whether a fight has finished —
    /// it needs to know who came, from where, who is holding the line and what
    /// has happened so far. A siege has all of that, mid-swing, so the same
    /// code draws a fight in progress and a fight being replayed.
    static func log(of siege: Siege, defender: String) -> BattleLog {
        BattleLog(
            id: siege.id, tick: siege.startTick,
            attackerName: siege.attackerName, defenderName: defender,
            moments: siege.moments, repelled: siege.repelled,
            attackerLabel: siege.attackerLabel, approach: siege.approach,
            edge: siege.edge, attackers: siege.attackers,
            // Anyone the player pulled out has left the wall, so the line the
            // canvas draws is the line that is actually standing in it.
            line: siege.standing)
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
        let field = ground(log)
        let post = field.defenderPost(index: index, of: log.line.count)
        // They run out while the raiders are still coming on, and hold from
        // the volley onward.
        let t = min(1, progress / volleyAt)
        let eased = t * t * (3 - 2 * t)
        return (LocalPoint(x: from.x + (post.x - from.x) * eased,
                           y: from.y + (post.y - from.y) * eased),
                t >= 1)
    }

    /// Where a colonist **is**, in a fight that is actually happening.
    ///
    /// This is the whole point of moving positions into the Core. `station`
    /// above interpolates a defender onto a post because a *record* has no
    /// positions in it; a live siege does, and the canvas reads them instead of
    /// guessing. Rule 5 holds either way — nothing here writes anything.
    /// `facing` is the x-component of the way they are looking, which is the
    /// unit `AgentMotion.Pose` speaks: −1 is left, +1 is right.
    static func post(for pawnID: UUID, siege: Siege,
                     within: Double = 1) -> (position: LocalPoint, facing: Double)? {
        guard let me = siege.fighters.first(where: { $0.id == pawnID && $0.side == .colony })
        else { return nil }
        // …thrown by whatever just hit them, so a colonist in the line reacts
        // to a blow the same way a raider does.
        let jolt = flinch(me, siege: siege, within: within)
        let at = LocalPoint(x: me.at.x + jolt.dx, y: me.at.y + jolt.dy)
        // Facing whoever they are on, and out along the attack if nobody.
        guard let mark = me.target.flatMap({ siege.place(of: $0) }) else {
            return (at, SiegeField(siege).axisX)
        }
        return (at, toward(me.at, mark).x)
    }

    private static func toward(_ a: LocalPoint, _ b: LocalPoint) -> (x: Double, y: Double) {
        let dx = b.x - a.x, dy = b.y - a.y
        let d = (dx * dx + dy * dy).squareRoot()
        guard d > 0 else { return (0, 0) }
        return (dx / d, dy / d)
    }

    // MARK: - Drawing

    static func draw(
        _ context: inout GraphicsContext, rect: CGRect, settlement: Settlement,
        continuousTick: Double, time: Double, zoom: CGFloat,
        secondsPerTick: Double = 60, replay: Replay? = nil,
        selectedPawnID: UUID? = nil
    ) {
        guard let (log, progress) = live(settlement, continuousTick: continuousTick,
                                         secondsPerTick: secondsPerTick,
                                         replay: replay) else { return }
        // A fight that is happening has real people standing in real places. A
        // record being played back has neither, and has to be staged.
        let siege = settlement.siege.flatMap { $0.id == log.id ? $0 : nil }
        // How far through the simulation's current step the drawing is, so a
        // body that was struck on this step is thrown by it and settles before
        // the next one. A replay has no step to be inside of.
        let within = siege.map { withinStep(of: $0, continuousTick: continuousTick) } ?? 1
        draw(&context, rect: rect, log: log, progress: progress, time: time,
             zoom: zoom, siege: siege, selectedPawnID: selectedPawnID, within: within)
    }

    /// **The torches a warband carries**, as lamps for the night wash.
    ///
    /// A raid that arrives at half past ten at night was a crowd of dark shapes
    /// in a dark field: the night wash goes over the fight, and the only layer
    /// drawn over the wash is the lamps. So the fight brings its own light —
    /// people crossing open country at night are carrying some. One pool on the
    /// muster line and one at the warband's own middle, which is what makes the
    /// two ranks legible without lighting the whole valley.
    ///
    /// Empty by day and empty with no fight on, so it costs one branch.
    static func torchlight(
        _ settlement: Settlement, rect: CGRect, continuousTick: Double,
        secondsPerTick: Double = 60, replay: Replay? = nil, zoom: CGFloat
    ) -> [SettlementLight.Lamp] {
        guard let (log, progress) = live(settlement, continuousTick: continuousTick,
                                         secondsPerTick: secondsPerTick,
                                         replay: replay) else { return [] }
        let siege = settlement.siege.flatMap { $0.id == log.id ? $0 : nil }
        let field = ground(log)
        // Guttering out as the fight ends, so a field does not stay lit after
        // everybody has gone home.
        let left = max(0, 1 - max(0, progress - 1) / max(0.001, lingerFraction))
        // **One wide, weak wash over the ground the fight is on**, and a small
        // flame in some of the warband's hands.
        //
        // Two bright pools were tried first and are wrong: at a lamp's ordinary
        // radius they came out as two suns with the fighting invisible
        // underneath them. What a night battle wants is enough light to read
        // the shapes by — the wash lifts the whole field a little, and the
        // hand torches say who is carrying it.
        var lamps: [SettlementLight.Lamp] = []
        let standing = siege.map { $0.raiders.filter { !$0.down } } ?? []
        let middle: LocalPoint
        if standing.isEmpty {
            middle = field.out(SiegeField.musterReach + 0.03)
        } else {
            let sum = standing.reduce(into: (x: 0.0, y: 0.0)) {
                $0.x += $1.at.x / Double(standing.count)
                $0.y += $1.at.y / Double(standing.count)
            }
            middle = LocalPoint(x: (sum.x + field.muster.x) / 2,
                                y: (sum.y + field.muster.y) / 2)
        }
        lamps.append(SettlementLight.Lamp(
            at: SettlementRenderer.point(middle, in: rect),
            radius: 190 * zoom, strength: 0.20 * left,
            colour: SettlementLight.hearth, phase: 0))
        // A torch every few hands, so the light has people in it.
        for (index, raider) in standing.enumerated() where index % 4 == 0 {
            guard lamps.count < 8 else { break }
            lamps.append(SettlementLight.Lamp(
                at: SettlementRenderer.point(raider.at, in: rect),
                radius: 26 * zoom, strength: 0.16 * left,
                colour: SettlementLight.hearth, phase: Double(index) * 0.7))
        }
        return lamps
    }

    /// The blood on the ground, drawn **before** the colonists.
    ///
    /// A pass of its own because of where it belongs in the stack: people stand
    /// on a stained field, they do not wear the stain. Everything else a battle
    /// draws goes over the figures, which is why the rest is one call after them
    /// and this is one call before.
    static func drawGround(
        _ context: inout GraphicsContext, rect: CGRect, settlement: Settlement,
        continuousTick: Double, zoom: CGFloat,
        secondsPerTick: Double = 60, replay: Replay? = nil
    ) {
        guard let (log, progress) = live(settlement, continuousTick: continuousTick,
                                         secondsPerTick: secondsPerTick,
                                         replay: replay) else { return }
        let siege = settlement.siege.flatMap { $0.id == log.id ? $0 : nil }
        SettlementBlood.ground(&context, rect: rect, log: log, progress: progress,
                               siege: siege, field: ground(log), zoom: zoom)
    }

    /// The fight itself, from a record and a point inside it. Split out so a
    /// test — and a replay — can drive it at any moment without a settlement.
    static func draw(
        _ context: inout GraphicsContext, rect: CGRect, log: BattleLog,
        progress: Double, time: Double, zoom: CGFloat, siege: Siege? = nil,
        selectedPawnID: UUID? = nil, within: Double = 1
    ) {
        let field = ground(log)
        let unit = min(rect.width, rect.height)
        let strike = strikeBeat(log, at: progress)

        if let siege {
            drawLive(&context, rect: rect, siege: siege, field: field,
                     time: time, zoom: zoom, strike: strike, unit: unit, within: within)
        } else {
            drawStaged(&context, rect: rect, log: log, field: field, progress: progress,
                       time: time, zoom: zoom, strike: strike, unit: unit)
        }

        // What the fight has done to the colonists holding the line, **on them**.
        //
        // This used to be a bar floating over every defender's head: twelve
        // readouts of a number, hovering above a field of people, which is the
        // aggregate habit at its purest. Harm belongs on the body that took it.
        // The bar survives for exactly one person — whoever the player has
        // selected — because that one is a readout they asked for.
        for (index, id) in log.line.enumerated() {
            let hurt = siege.map { min(0.95, ($0.damage[id] ?? 0) / 100) }
                ?? harm(log, pawn: id, at: progress)
            guard hurt > 0.01 else { continue }
            let post = siege?.place(of: id)
                ?? field.defenderPost(index: index, of: log.line.count)
            let screen = SettlementRenderer.point(post, in: rect)
            SettlementBlood.onBody(&context, at: screen, harm: hurt, zoom: zoom,
                                   seed: seed(of: id))
            guard id == selectedPawnID else { continue }
            wounded(&context, at: screen, harm: hurt, unit: unit, zoom: zoom)
        }

        // The beats: arrows away from the wall, and every blow on the two
        // bodies it happened between.
        // A beat is one step of *this* fight — a long siege has more of them,
        // not shorter ones.
        let beat = momentLife(steps: siege?.steps ?? log.steps)
        for moment in log.moments(upTo: progress) {
            let age = progress - moment.at
            guard age >= 0, age < beat else { continue }
            let fade = 1 - age / beat
            switch moment.kind {
            case .volley:
                // What was actually fired, when the record says. A fight
                // recorded before weapons had projectiles has neither end nor
                // kind, and falls back to the arrows this always drew.
                let landing = moment.spot ?? field.origin
                let origin = moment.from ?? LocalPoint(
                    x: landing.x - field.axisX * SiegeField.openReach * 0.35,
                    y: landing.y - field.axisY * SiegeField.openReach * 0.35)
                SettlementProjectiles.draw(
                    &context, rect: rect, kind: moment.projectile ?? .arrow,
                    from: origin, to: landing, flight: 1 - fade, fade: fade,
                    zoom: zoom, caliber: moment.caliber ?? 1,
                    shots: moment.shots ?? 6, seed: UInt64(moment.id) &+ 1)
            case .clash, .charge:
                // Nothing of its own. A clash is a tally of the whole line's
                // swings for one step, and the swings themselves are already
                // being drawn on the arms of the people taking them (`strike`).
                break
            case .wound, .death:
                guard let p = SettlementBlood.place(of: moment, log: log,
                                                    field: field, siege: siege)
                else { break }
                SettlementBlood.impact(
                    &context, at: SettlementRenderer.point(p, in: rect),
                    along: blow(of: moment, at: p, field: field, siege: siege),
                    age: age, fatal: moment.kind == .death, unit: unit, seed: moment.id)
            case .torch:
                torch(&context, rect: rect, fade: fade, unit: unit,
                      at: moment.spot ?? field.heart, seed: UInt64(moment.id))
            case .plunder:
                plunder(&context, field: field, rect: rect, fade: fade, unit: unit,
                        at: moment.spot)
            case .repelled:
                horn(&context, at: SettlementRenderer.point(field.muster, in: rect),
                     fade: fade, unit: unit)
            }
        }

        // And the bodies, lying where they fell for as long as the field stays.
        // A live fight lays out its own; a replay reads them from the record.
        if siege == nil {
            for (index, moment) in casualties(log, upTo: progress).enumerated() {
                guard let p = place(of: moment, log: log, field: field, siege: nil) else { continue }
                body(&context, at: SettlementRenderer.point(p, in: rect),
                     zoom: zoom, seed: UInt64(index &+ moment.id))
            }
        }

        banner(&context, rect: rect, log: log, progress: progress, siege: siege)
    }

    /// A fight that is **happening**: everybody is drawn where the simulation
    /// says they are, and nothing is interpolated.
    ///
    /// The colonists are not drawn here — they are drawn by the ordinary figure
    /// pass, because they *are* the ordinary colonists and they walked out to
    /// the line on the Core's own legs (`AgentMotion` reads `Siege.fighters`).
    /// What this adds is the warband, who is on whom, and the dead.
    private static func drawLive(
        _ context: inout GraphicsContext, rect: CGRect, siege: Siege, field: SiegeField,
        time: Double, zoom: CGFloat, strike: Double, unit: CGFloat, within: Double
    ) {
        // What one of them was worth when they arrived, so how badly a raider is
        // cut up can be read off what is left of them.
        let share = max(1, siege.openingStrength / Double(max(1, siege.attackers)))
        for (index, raider) in siege.raiders.enumerated() {
            // Where the blow they just took has thrown them. Zero for anybody
            // nobody has hit this step, which is nearly everybody.
            let jolt = flinch(raider, siege: siege, within: within)
            let screen = SettlementRenderer.point(
                LocalPoint(x: raider.at.x + jolt.dx, y: raider.at.y + jolt.dy), in: rect)
            guard !raider.down else {
                body(&context, at: screen, zoom: zoom, seed: UInt64(index &* 31))
                SettlementBlood.onBody(&context, at: screen, harm: 1, zoom: zoom,
                                       seed: seed(of: raider.id))
                continue
            }
            let mark = raider.target.flatMap { siege.place(of: $0) }
            let closed = mark.map { SiegeField.distance(raider.at, $0) <= SiegeEngine.reach }
                ?? false
            // A little jostle, so a rank of raiders is not a row of stamps.
            let jitter = sin(time * 3.4 + Double(index) * 1.7) * 0.0022
            raiderFigure(
                &context,
                at: CGPoint(x: screen.x + CGFloat(jitter) * rect.width,
                            y: screen.y + CGFloat(jitter) * 0.6 * rect.height),
                heading: mark.map { toward(raider.at, $0) } ?? (-field.axisX, -field.axisY),
                zoom: zoom, time: time, phase: Double(index) * 0.9,
                swinging: closed ? strike : 0)
            SettlementBlood.onBody(&context, at: screen,
                                   harm: max(0, 1 - raider.strength / share),
                                   zoom: zoom, seed: seed(of: raider.id))
            // Who they are on — drawn only once they have actually reached
            // them, so the thread means contact rather than intent.
            if closed, let mark {
                pairing(&context, from: screen,
                        to: SettlementRenderer.point(mark, in: rect),
                        fade: strike * 0.5 + 0.12, unit: unit)
            }
        }
        // Anybody who fell stays on the ground where they fell.
        for fallen in siege.defenders where fallen.down && !siege.withdrawn.isEmpty {
            guard siege.damage[fallen.id] ?? 0 > 0 else { continue }
            let screen = SettlementRenderer.point(fallen.at, in: rect)
            // Never `hashValue`: Swift seeds its hasher per process, so a body
            // seeded from one lies at a different angle every launch.
            body(&context, at: screen, zoom: zoom, seed: seed(of: fallen.id))
            SettlementBlood.onBody(&context, at: screen, harm: 1, zoom: zoom,
                                   seed: seed(of: fallen.id))
        }
        // And the orders the player has given, so a tap is visibly a thing that
        // happened rather than a thing you hope happened.
        for (pawn, order) in siege.orders {
            let spot: LocalPoint?
            switch order {
            case .moveTo(let point): spot = point
            case .engage(let mark): spot = siege.place(of: mark)
            }
            guard let spot, let from = siege.place(of: pawn) else { continue }
            marker(&context, at: SettlementRenderer.point(spot, in: rect),
                   from: SettlementRenderer.point(from, in: rect),
                   time: time, unit: unit)
        }
    }

    /// Where somebody has been told to be: a soft ring on the ground with a
    /// thread back to whoever was told.
    private static func marker(
        _ context: inout GraphicsContext, at p: CGPoint, from: CGPoint,
        time: Double, unit: CGFloat
    ) {
        let pulse = 0.5 + 0.5 * sin(time * 3)
        let r = unit * (0.010 + 0.004 * pulse)
        context.stroke(Path { path in
            path.move(to: from)
            path.addLine(to: p)
        }, with: .color(Theme.accent.opacity(0.22)),
           style: StrokeStyle(lineWidth: max(0.6, unit * 0.0014), dash: [3, 4]))
        context.stroke(
            Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)),
            with: .color(Theme.accent.opacity(0.5 + 0.3 * pulse)), lineWidth: 1.4)
    }

    /// A record being played back. There are no positions in a `BattleLog` —
    /// only who came, from where, and what happened when — so the ranks are
    /// staged onto the field and walked through the shape of the fight.
    private static func drawStaged(
        _ context: inout GraphicsContext, rect: CGRect, log: BattleLog, field: SiegeField,
        progress: Double, time: Double, zoom: CGFloat, strike: Double, unit: CGFloat
    ) {
        let stage = phase(at: progress)
        let closing = min(1, progress / volleyAt)
        let closed = stage == .marching ? 0
            : min(1, max(0, (progress - volleyAt) / (meleeAt - volleyAt)))

        let count = log.drawnAttackers
        let standing = attackersStanding(log, at: progress)
        let defenders = max(1, log.line.count)
        for i in 0..<count {
            let post = stagedAttackerPost(field, index: i, of: count, closed: closed)
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
            let jitter = sin(time * 3.4 + Double(i) * 1.7) * 0.0022
            raiderFigure(&context,
                         at: CGPoint(x: screen.x + CGFloat(jitter) * rect.width,
                                     y: screen.y + CGFloat(jitter) * 0.6 * rect.height),
                         heading: (-field.axisX, -field.axisY), zoom: zoom, time: time,
                         phase: Double(i) * 0.9, swinging: stage == .melee ? strike : 0)
            if stage == .melee, defenders > 0 {
                let opposite = defenders == 1 ? 0 : i * (defenders - 1) / max(1, count - 1)
                pairing(&context, from: screen,
                        to: SettlementRenderer.point(
                            field.defenderPost(index: opposite, of: defenders), in: rect),
                        fade: strike * 0.5 + 0.12, unit: unit)
            }
        }
    }

    /// Which way a blow travelled, so the blood goes the way it was thrown.
    ///
    /// Off the field if there is one — whoever is standing on the person it
    /// happened to is the one who swung — and otherwise in along the line of the
    /// attack, which is the direction every blow in a raid comes from.
    private static func blow(
        of moment: BattleMoment, at spot: LocalPoint, field: SiegeField, siege: Siege?
    ) -> (x: Double, y: Double) {
        let inward = (x: -field.axisX, y: -field.axisY)
        guard let siege, let victim = moment.pawnID else { return inward }
        let swinging = siege.raiders
            .filter { !$0.down && $0.target == victim }
            .min { SiegeField.distance($0.at, spot) < SiegeField.distance($1.at, spot) }
        guard let swinging else { return inward }
        let d = toward(swinging.at, spot)
        return d.x == 0 && d.y == 0 ? inward : d
    }

    /// A stable number for a pawn, for the deterministic wobble in a smear.
    /// Off the UUID's own bytes, never `hashValue` — Swift seeds its hasher per
    /// process, so blood would sit somewhere different on every launch.
    private static func seed(of id: UUID) -> UInt64 {
        withUnsafeBytes(of: id.uuid) { bytes in
            bytes.prefix(8).reduce(UInt64(0)) { $0 &* 31 &+ UInt64($1) }
        }
    }

    /// Where the fighting is, for the things that happen "at the front": the
    /// middle of the contact if there is one, and the muster line otherwise.
    private static func seam(siege: Siege?, field: SiegeField) -> LocalPoint {
        guard let siege else { return field.muster }
        let met = siege.raiders.filter { !$0.down }
            .compactMap { raider -> LocalPoint? in
                guard let mark = raider.target.flatMap({ siege.place(of: $0) }),
                      SiegeField.distance(raider.at, mark) <= SiegeEngine.reach * 1.5
                else { return nil }
                return LocalPoint(x: (raider.at.x + mark.x) / 2, y: (raider.at.y + mark.y) / 2)
            }
        guard !met.isEmpty else {
            return siege.raiders.first { !$0.down }?.at ?? field.muster
        }
        return LocalPoint(x: met.reduce(0) { $0 + $1.x } / Double(met.count),
                          y: met.reduce(0) { $0 + $1.y } / Double(met.count))
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

    /// Where a beat happened: on the person it happened to, if the fight knows
    /// where they are standing, and otherwise at the line.
    private static func place(
        of moment: BattleMoment, log: BattleLog, field: SiegeField, siege: Siege?
    ) -> LocalPoint? {
        guard let id = moment.pawnID else { return seam(siege: siege, field: field) }
        if let live = siege?.place(of: id) { return live }
        guard let index = log.line.firstIndex(of: id) else { return field.muster }
        return field.defenderPost(index: index, of: log.line.count)
    }

    private static func casualties(_ log: BattleLog, upTo progress: Double) -> [BattleMoment] {
        log.moments(upTo: progress).filter { $0.kind == .death }
    }

    // MARK: - Telling the player what they are watching

    /// The caption: who is fighting whom, how many of each are up, and which
    /// part of the fight this is. Drawn over the field, high enough to clear it.
    private static func banner(
        _ context: inout GraphicsContext, rect: CGRect, log: BattleLog,
        progress: Double, siege: Siege?
    ) {
        let text = Text(caption(log, progress: progress,
                                cs: AppStrings.language == .cs, siege: siege))
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
    private static func raiderFigure(
        _ context: inout GraphicsContext, at p: CGPoint, heading: (x: Double, y: Double),
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
        // Which way they are facing: toward whoever they are walking at.
        let lean = CGFloat(heading.x) * s * 0.18

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

    /// Arrows loosed from the colony's side, back down the road.
    /// Stores going the other way, on somebody's back.
    private static func plunder(
        _ context: inout GraphicsContext, field: SiegeField, rect: CGRect,
        fade: Double, unit: CGFloat, at spot: LocalPoint? = nil
    ) {
        // Where the sack is actually being filled, when the record says.
        let start = spot ?? field.muster
        for i in 0..<3 {
            let t = 0.3 + Double(i) * 0.14
            let p = SettlementRenderer.point(
                interpolate(start, field.origin, t: t), in: rect)
            let s = unit * 0.010
            context.fill(Path(CGRect(x: p.x - s / 2, y: p.y - s / 2, width: s, height: s)),
                         with: .color(Theme.accent.opacity(0.55 * fade)))
        }
    }

    /// **A roof going up.** Somebody came for this building and is standing on
    /// it — the fire is drawn where they are, which is where the Core says the
    /// harm is being done rather than at the middle of town.
    private static func torch(
        _ context: inout GraphicsContext, rect: CGRect,
        fade: Double, unit: CGFloat, at spot: LocalPoint, seed: UInt64
    ) {
        let p = SettlementRenderer.point(spot, in: rect)
        var hash = seed &* 0x9E37_79B9_7F4A_7C15 &+ 1
        for i in 0..<5 {
            hash = hash &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            let sway = (Double((hash >> 33) % 1000) / 1000 - 0.5) * 0.9
            let rise = 0.35 + Double(i) * 0.22
            let size = unit * CGFloat(0.016 * (1 - rise * 0.5))
            let x = p.x + CGFloat(sway) * unit * 0.012
            let y = p.y - CGFloat(rise) * unit * 0.020
            var flame = Path()
            flame.move(to: CGPoint(x: x, y: y + size))
            flame.addQuadCurve(to: CGPoint(x: x, y: y - size),
                               control: CGPoint(x: x - size * 0.9, y: y))
            flame.addQuadCurve(to: CGPoint(x: x, y: y + size),
                               control: CGPoint(x: x + size * 0.9, y: y))
            // Hotter at the base, going to smoke at the top.
            let heat = 1 - rise * 0.6
            context.fill(flame, with: .color(Color(red: 0.95, green: 0.45 + 0.25 * heat,
                                                   blue: 0.12).opacity(0.75 * fade * heat)))
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
