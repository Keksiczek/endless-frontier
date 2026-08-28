import SwiftUI
import EndlessFrontierCore

/// The wild, drawn: the deer herd the hunters live off grazes its way around
/// the valley, and when predator pressure climbs, something grey prowls the
/// tree line.
///
/// **Where a beast is and what it is doing both come from the simulation.**
/// `Animal.position` (and `walk`, for the ground between two thinks) says
/// where; `Animal.activity` says whether it is at grass, has stopped to look,
/// or is running. The frame clock is left with what it is for — the gait, the
/// breathing, the head coming up — and never decides *which* pose. It used to
/// decide both, which is how a deer came to graze in mid-flight from a wolf.
/// Nothing here writes back: the sim stays untouched.
/// The abstract herd below is the fallback for saves made before the wild had
/// bodies, and is the one place positions are still a function of the clock.
enum SettlementWildlife {
    /// Predator pressure above which a prowler appears at the fringe…
    static let prowlerPressure: Double = 15
    /// …and above which a second joins it.
    static let packPressure: Double = 30
    /// The most deer ever drawn — a full herd, thinned as hunters cull it.
    static let maxVisibleDeer = 5

    /// Where the herd is right now. Hunters anchor to this, so the figures
    /// chase the same deer you see.
    ///
    /// Where there are real beasts this is simply *where they are* — the wild
    /// walks its own valley now, and a herd worked hard has genuinely moved to
    /// the far side of it. The old slow figure-eight is left as the answer for
    /// maps generated before the wild had bodies.
    static func herdCenter(map: LocalMap, time: Double) -> LocalPoint {
        let prey = map.wildlife.animals.filter { !$0.isPredator }
        if !prey.isEmpty {
            return LocalPoint(x: prey.reduce(0) { $0 + $1.position.x } / Double(prey.count),
                              y: prey.reduce(0) { $0 + $1.position.y } / Double(prey.count))
        }
        let seed = Double(map.terrainSeed % 977) / 977 * 2 * .pi
        let t = time / 90 + seed          // one slow lap ≈ a minute and a half
        return LocalPoint(
            x: 0.5 + cos(t) * 0.30,
            y: 0.52 + sin(t * 2) * 0.20)  // lissajous keeps it off the houses
    }

    /// Draws the wild. Where there are real `Animal`s on the map each one is
    /// drawn as itself — its own species, its own wander, and visibly the worse
    /// for a hard winter — and the abstract herd is only the fallback for saves
    /// that predate them. Everything is skipped under fog.
    /// The beasts that belong to the colony, drawn among its buildings rather
    /// than out in the wild.
    ///
    /// A tamed animal is the same `Animal` the valley is made of, so it is
    /// drawn the same way — and then marked, because the one thing you need to
    /// know at a glance is that this wolf is *yours*. It wanders its own small
    /// circuit of the town instead of the herd's lap of the valley.
    /// Where a kept beast is walking its round of the yard right now.
    ///
    /// Shared with hit-testing, so a tap lands on the animal that is drawn
    /// rather than on where it was a moment ago.
    static func tamedPosition(_ kept: TamedAnimal, index: Int, time: Double) -> LocalPoint {
        let heart = SettlementGeometry.heart
        let phase = Double(hash(kept.animal.id) % 6199) / 6199 * 2 * .pi
        let radius = 0.05 + Double(index % 3) * 0.022
        let angle = time * 0.06 + phase
        return LocalPoint(x: heart.x + cos(angle) * radius,
                          y: heart.y + sin(angle) * radius * 0.7)
    }

    /// One beast, drawn wherever the caller says.
    ///
    /// Split out of `drawTamed` so a mount can be drawn under the colonist
    /// riding it: a horse with somebody on its back belongs beside that person
    /// on the road, not circling the heart with the stock. The wild and the
    /// pen and the saddle are then one drawing each, which is what stops a
    /// ridden elk being a second, worse elk.
    static func body(
        _ build: AnimalDefinition.Build, at: CGPoint, s: CGFloat, time: Double,
        phase: Double, walking: Bool, context: inout GraphicsContext
    ) {
        let doing: AnimalActivity = walking ? .wary : .grazing
        // **The build, not the species.**
        //
        // This switched on eleven species by name, so the eight bodies the
        // canvas can draw were reachable only by being one of eleven enum
        // cases — a twelfth beast would have come out as whatever the fallback
        // was. Species are `animals.json` now and each names the build it
        // wears (`AnimalDefinition.Build`).
        switch build {
        case .deer: deer(&context, at: at, s: s, time: time, phase: phase,
                         doing: doing, urgency: 1, crown: .antlersIfStag)
        case .elk:  deer(&context, at: at, s: s, time: time, phase: phase,
                         doing: doing, urgency: 1, crown: .heavyAntlers)
        case .goat: deer(&context, at: at, s: s, time: time, phase: phase,
                         doing: doing, urgency: 1, crown: .curvedHorns)
        case .boar: boar(&context, at: at, s: s, time: time, phase: phase,
                         doing: doing, urgency: 1)
        case .small:
            hare(&context, at: at, s: s, time: time, phase: phase, doing: doing)
        case .canid:
            prowler(&context, at: at, s: s, time: time, hungry: false)
        case .lynx:
            lynx(&context, at: at, s: s, time: time, doing: doing, urgency: 1)
        case .badger:
            badger(&context, at: at, s: s, time: time, doing: doing, urgency: 1)
        }
    }

    static func drawTamed(
        _ context: inout GraphicsContext, rect: CGRect, settlement: Settlement,
        map: LocalMap, time: Double, zoom: CGFloat
    ) {
        for (index, kept) in settlement.tamed.enumerated() {
            // A beast somebody is on is not in the pen. It is drawn under its
            // rider by `SettlementConveyances`, and drawing it here as well
            // put the same horse in two places at once.
            if settlement.conveyances.contains(where: {
                $0.animalID == kept.id && $0.riderID != nil
            }) { continue }
            let phase = Double(hash(kept.animal.id) % 6199) / 6199 * 2 * .pi
            let position = tamedPosition(kept, index: index, time: time)
            guard map.isExplored(position) else { continue }
            let at = SettlementRenderer.point(position, in: rect)
            let s = size(kept.animal) * zoom

            // Kept stock is not roamed by `AnimalEngine`, so its `activity`
            // is whatever it held when it was gentled. A beast in the pen is a
            // beast at grass, and saying so beats reading a stale field.
            // A kept beast walks its round of the pen, so it has a side too:
            // sampled off the same circle the drawing puts it on.
            let ago = SettlementRenderer.point(
                tamedPosition(kept, index: index, time: time - 0.6), in: rect)
            var penned = facing(context, at.x < ago.x ? -1 : 1, about: at)
            body(kept.animal.build, at: at, s: s, time: time, phase: phase,
                 walking: false, context: &penned)
            // The collar: a small ring under it, in the colony's own amber, so
            // a tamed wolf never reads as one that came out of the trees.
            context.stroke(
                Path(ellipseIn: CGRect(x: at.x - s * 0.9, y: at.y + s * 0.5,
                                       width: s * 1.8, height: s * 0.5)),
                with: .color(Theme.accent.opacity(0.55)), lineWidth: max(0.6, zoom * 0.5))
            // And a pack on the ones that carry.
            if kept.role == .beastOfBurden {
                context.fill(Path(roundedRect: CGRect(x: at.x - s * 0.5, y: at.y - s * 0.85,
                                                      width: s, height: s * 0.5),
                                  cornerRadius: s * 0.14),
                             with: .color(Color(red: 0.46, green: 0.36, blue: 0.25)))
            }
        }
    }

    static func draw(
        _ context: inout GraphicsContext, rect: CGRect, map: LocalMap, time: Double,
        continuousStep: Double = 0, zoom: CGFloat = 1
    ) {
        guard map.wildlife.animals.isEmpty else {
            entities(&context, rect: rect, map: map, time: time,
                     continuousStep: continuousStep, zoom: zoom)
            return
        }
        abstractHerd(&context, rect: rect, map: map, time: time)
    }

    /// How big each beast is drawn, in screen points at zoom 1.
    ///
    /// Sized against the *colonists*, not against the canvas. Everything here
    /// used to be a fraction of the map's short side, which made a deer wider
    /// than a house: a one-tile hut covers about 2% of the canvas and a deer
    /// was drawn at 2.7% of it. Animals are people-sized things standing among
    /// people-sized things, so they take their scale from the same place people
    /// do — a deer a little lower than a colonist, a hare you have to look for,
    /// a bear you do not.
    /// How big a beast is drawn against a person.
    ///
    /// Read off the animal rather than a table of eleven names — a beast
    /// carries its own size (`AnimalDefinition.size`), so a species the content
    /// adds is drawn at the size the content gave it instead of at whatever
    /// the fallback happened to be.
    static func size(_ animal: Animal) -> CGFloat { CGFloat(animal.size) }

    /// Every beast the simulation is actually running, standing where the
    /// simulation says it is standing.
    ///
    /// This used to be derived from `(animal.id, frame clock)` — the right
    /// answer for decoration and the wrong one for a thing with a body. The
    /// wild has positions now (`AnimalEngine.roam`), so a deer is somewhere a
    /// hunter can walk to, bolts when one gets close, and lies where it fell.
    /// The frame clock is left with what it is actually for: the breathing,
    /// the gait, the head coming up.
    private static func entities(
        _ context: inout GraphicsContext, rect: CGRect, map: LocalMap, time: Double,
        continuousStep: Double, zoom: CGFloat
    ) {
        // Back to front, so a beast in front overlaps the one behind it. Sorted
        // on where they *are on this frame*, or a beast crossing in front of
        // another would keep the stacking it had on the last think.
        let standing = map.wildlife.animals
            .map { (animal: $0, at: $0.position(at: continuousStep)) }
            .sorted { $0.at.y < $1.at.y }
        for (animal, where_) in standing {
            let phase = Double(hash(animal.id) % 6199) / 6199 * 2 * .pi
            guard map.isExplored(where_) else { continue }
            let at = SettlementRenderer.point(where_, in: rect)
            let ailing = !animal.conditions.isEmpty
                || animal.health < animal.baseHealth * 0.55
            // …with one thing the clock **is** allowed to settle: whether the
            // running is over.
            //
            // A think lasts four real minutes and a bolt is over in seconds, so
            // a beast that fled kept the running pose long after it had stopped
            // moving — a deer standing perfectly still in a flat sprint with
            // nothing anywhere near it. Keks: *"zvířata prchají, i když okolo
            // nic není, a skoro se nehýbou."* The walk knows when it arrived;
            // a beast that has arrived is watching, not running.
            let stillRunning = animal.walk.map { continuousStep < Double($0.arrivesAt) } ?? false
            let doing: AnimalActivity = animal.activity == .fleeing && !stillRunning
                ? .wary : animal.activity
            // A running beast is drawn running — but *not* by speeding the
            // clock up. `time * urgency` looks right until the activity
            // changes, at which point the phase jumps by (urgency − 1) × time,
            // which after a few minutes of play is an enormous discontinuity:
            // the beast snaps into a different pose every time it takes fright
            // or calms down. That snap is the stutter. The clock runs at one
            // rate for everybody and *how far* the legs swing carries the
            // urgency instead.
            let urgency = doing == .fleeing ? 3.4
                : (doing == .stalking ? 1.8 : 1.0)
            let beat = time
            let s = size(animal) * zoom * (1 + (urgency - 1) * 0.06)

            // **What it is doing is the simulation's to say.** `activity` is set
            // by `AnimalEngine.roam` — the enum's own cases spell out the poses
            // ("head down", "stopped to look", "running") — and the canvas used
            // to ignore it and invent the pose from the frame clock instead. A
            // deer put its head in the grass whenever `sin(time)` said so, mid
            // flight from a wolf; a hare bolted on a timer with nothing chasing
            // it. The clock's job is *when, within* a pose — a grazing deer
            // still lifts its head now and then — never *which* pose.
            // **The build, not the species.** Eleven names, eight bodies —
            // and a twelfth beast could only ever have come out as the
            // fallback. A species names its build in `animals.json` and is
            // drawn as the animal it says it is.
            // Turned to face the way it is walking. The alarm mark below is
            // drawn in the *unmirrored* context: a beast can be going left and
            // the mark over its head still reads left to right.
            do {
            var context = facing(context, heading(of: animal, at: continuousStep), about: at)
            switch animal.build {
            case .deer:
                deer(&context, at: at, s: s, time: beat, phase: phase,
                     doing: doing, urgency: urgency, crown: .antlersIfStag)
            case .elk:
                // Always antlered, and heavy with it — an elk is the thing you
                // see across the valley and decide not to walk towards.
                deer(&context, at: at, s: s, time: beat, phase: phase,
                     doing: doing, urgency: urgency, crown: .heavyAntlers)
            case .goat:
                deer(&context, at: at, s: s, time: beat, phase: phase,
                     doing: doing, urgency: urgency, crown: .curvedHorns)
            case .boar:
                boar(&context, at: at, s: s, time: beat, phase: phase,
                     doing: doing, urgency: urgency)
            case .small:
                // Something a snare takes: it sits tight and then breaks
                // cover, which is the hare's crouch-and-bolt and the grouse's
                // alike, at whatever size the beast is drawn.
                hare(&context, at: at, s: s, time: beat, phase: phase, doing: doing)
            case .lynx:
                lynx(&context, at: at, s: s, time: beat, doing: doing, urgency: urgency)
            case .badger:
                badger(&context, at: at, s: s, time: beat, doing: doing, urgency: urgency)
            case .canid:
                // A dog's outline. Whether it looks hungry is the beast's own
                // condition, not its name — a starving fox prowls like a
                // starving wolf.
                prowler(&context, at: at, s: s, time: beat, hungry: ailing,
                        doing: doing, urgency: urgency)
            }
            }
            // Something has spooked it: a mark over the head, the way a herd
            // lifting all at once tells you a wolf came down the valley.
            if animal.activity == .fleeing {
                context.stroke(Path { p in
                    p.move(to: CGPoint(x: at.x, y: at.y - s * 2.2))
                    p.addLine(to: CGPoint(x: at.x, y: at.y - s * 1.5))
                }, with: .color(Theme.bone.opacity(0.55)),
                   style: StrokeStyle(lineWidth: max(0.8, zoom), lineCap: .round))
            }

            // A beast that is hurt, ill or frozen says so, so a hard winter is
            // something you can see happening rather than read about later.
            if ailing {
                let r = max(0.9, zoom * 0.9)
                context.fill(
                    Path(ellipseIn: CGRect(x: at.x - r, y: at.y - s * 2.4,
                                           width: r * 2, height: r * 2)),
                    with: .color(Theme.danger.opacity(0.75)))
            }
        }
    }

    /// The old behaviour, for maps generated before the wild had bodies.
    private static func abstractHerd(
        _ context: inout GraphicsContext, rect: CGRect, map: LocalMap, time: Double
    ) {
        let unit = min(rect.width, rect.height)
        let herd = herdCenter(map: map, time: time)
        let count = min(maxVisibleDeer,
                        Int((map.wildlife.herdFraction * Double(maxVisibleDeer)).rounded(.up)))
        for i in 0..<max(0, count) {
            let phase = Double(i) * 2.1
            let p = LocalPoint(
                x: herd.x + cos(time * 0.18 + phase) * 0.035,
                y: herd.y + sin(time * 0.14 + phase * 1.7) * 0.028)
            guard map.isExplored(p) else { continue }
            deer(&context, at: SettlementRenderer.point(p, in: rect),
                 s: unit * 0.010, time: time, phase: phase,
                 doing: .grazing, urgency: 1)
        }

        let pressure = map.wildlife.predatorPressure
        guard pressure > prowlerPressure else { return }
        let prowlers = pressure > packPressure ? 2 : 1
        for i in 0..<prowlers {
            let angle = time * 0.05 + Double(i) * .pi + Double(map.terrainSeed % 7)
            let p = LocalPoint(x: 0.5 + cos(angle) * 0.42,
                               y: 0.52 + sin(angle) * 0.36)
            guard map.isExplored(p) else { continue }
            prowler(&context, at: SettlementRenderer.point(p, in: rect),
                    s: unit * 0.011, time: time, hungry: pressure > packPressure)
        }
    }

    /// A stable number per beast, so its wander is its own and never jitters.
    /// **Which way a beast is going**, −1 walking left, +1 walking right.
    ///
    /// Every animal in the game was drawn facing right, so half of them walked
    /// backwards: a deer crossing the valley westward moved left across the
    /// screen with its head pointing east. The colonists have had this since
    /// they were drawn (`AgentMotion.Pose.facing`) and the beasts never did —
    /// their bodies were drawn from a fixed outline with no side to them.
    ///
    /// Taken from the walk itself rather than from a field, so it cannot
    /// disagree with where the beast actually is: two samples of the same
    /// `position(at:)` the drawing uses. A beast standing still keeps a side of
    /// its own, from its id, so a meadow of grazing deer does not all look one
    /// way — and does not flicker between frames either.
    static func heading(of animal: Animal, at step: Double) -> CGFloat {
        if let walk = animal.walk, step < Double(walk.arrivesAt) {
            let dx = animal.position(at: step + 0.08).x - animal.position(at: step).x
            if abs(dx) > 1e-6 { return dx < 0 ? -1 : 1 }
            let straight = walk.to.x - walk.from.x
            if abs(straight) > 1e-6 { return straight < 0 ? -1 : 1 }
        }
        return hash(animal.id) % 2 == 0 ? -1 : 1
    }

    /// Mirror a drawing about the point it stands on. The body is drawn facing
    /// right and turned round here, which is what `SettlementFigures` does for
    /// a colonist walking west.
    static func facing(_ context: GraphicsContext, _ heading: CGFloat,
                       about at: CGPoint) -> GraphicsContext {
        guard heading < 0 else { return context }
        var mirrored = context
        mirrored.translateBy(x: at.x, y: 0)
        mirrored.scaleBy(x: -1, y: 1)
        mirrored.translateBy(x: -at.x, y: 0)
        return mirrored
    }

    static func hash(_ id: UUID) -> UInt64 {
        var h: UInt64 = 0xCBF2_9CE4_8422_2325
        let b = id.uuid
        for byte in [b.0, b.1, b.2, b.3, b.4, b.5, b.6, b.7] {
            h = (h ^ UInt64(byte)) &* 0x0100_0000_01B3
        }
        return h
    }

    /// A boar: low, heavy, snout down, with a bristled back.
    private static func boar(
        _ context: inout GraphicsContext, at p: CGPoint, s: CGFloat,
        time: Double, phase: Double, doing: AnimalActivity, urgency: Double
    ) {
        let hide = Color(red: 0.33, green: 0.27, blue: 0.23)
        let body = CGRect(x: p.x - s * 1.0, y: p.y - s * 0.5, width: s * 2.0, height: s * 0.95)
        context.fill(Path(ellipseIn: CGRect(x: p.x - s * 0.9, y: p.y + s * 0.4,
                                            width: s * 1.8, height: s * 0.4)),
                     with: .color(.black.opacity(0.2)))
        context.fill(Path(ellipseIn: body), with: .color(hide))
        // A wedge of a head, always rooting at the ground.
        context.fill(Path { q in
            q.move(to: CGPoint(x: body.minX + s * 0.1, y: p.y - s * 0.3))
            q.addLine(to: CGPoint(x: body.minX - s * 0.75, y: p.y + s * 0.42))
            q.addLine(to: CGPoint(x: body.minX + s * 0.2, y: p.y + s * 0.4))
            q.closeSubpath()
        }, with: .color(hide))
        // Bristles.
        for i in 0..<4 {
            let x = body.minX + body.width * (CGFloat(i) + 0.8) / 5
            context.stroke(Path { q in
                q.move(to: CGPoint(x: x, y: body.minY + s * 0.06))
                q.addLine(to: CGPoint(x: x + s * 0.06, y: body.minY - s * 0.24))
            }, with: .color(Theme.bone.opacity(0.4)), lineWidth: 0.6)
        }
        // Four short legs, working — harder when it is running, still when it
        // has lain down. Amplitude carries the urgency, never the clock rate.
        let gait = doing == .resting ? 0
            : CGFloat(sin(time * 3 + phase)) * s * 0.16 * CGFloat(urgency)
        for i in 0..<4 {
            let x = body.minX + body.width * (CGFloat(i) + 0.5) / 4
            context.stroke(Path { q in
                q.move(to: CGPoint(x: x, y: body.maxY - s * 0.1))
                q.addLine(to: CGPoint(x: x + (i % 2 == 0 ? gait : -gait), y: body.maxY + s * 0.42))
            }, with: .color(hide), lineWidth: max(0.7, s * 0.2))
        }
    }

    /// A hare: small, still, then suddenly not.
    private static func hare(
        _ context: inout GraphicsContext, at p: CGPoint, s: CGFloat,
        time: Double, phase: Double, doing: AnimalActivity
    ) {
        let fur = Color(red: 0.62, green: 0.55, blue: 0.44)
        // It sits, then bolts — but it bolts because **something scared it**,
        // not because a sine came round again. This used to run off the clock
        // alone, so a hare with nothing within half the valley would suddenly
        // leg it, and one genuinely running from a fox would sit there.
        // Grazing keeps the odd startled hop; a wary hare freezes flat.
        let bolt: Double
        switch doing {
        case .fleeing:  bolt = 1
        case .grazing:  bolt = max(0, sin(time * 0.9 + phase) - 0.93) * 6
        case .wary, .resting, .stalking: bolt = 0
        }
        let hop = CGFloat(abs(sin(time * 9 + phase))) * s * CGFloat(bolt)
        let c = CGPoint(x: p.x + CGFloat(bolt) * s * 0.8, y: p.y - hop)
        context.fill(Path(ellipseIn: CGRect(x: c.x - s * 0.8, y: c.y - s * 0.5,
                                            width: s * 1.6, height: s * 1.0)),
                     with: .color(fur))
        // Two long ears, laid back when it runs.
        for side in [-1.0, 1.0] {
            let lean = CGFloat(side) * s * (0.18 + CGFloat(bolt) * 0.5)
            context.stroke(Path { q in
                q.move(to: CGPoint(x: c.x + s * 0.4, y: c.y - s * 0.35))
                q.addLine(to: CGPoint(x: c.x + s * 0.4 + lean, y: c.y - s * 1.15))
            }, with: .color(fur), lineWidth: max(0.6, s * 0.2))
        }
        context.fill(Path(ellipseIn: CGRect(x: c.x - s * 0.95, y: c.y - s * 0.3,
                                            width: s * 0.4, height: s * 0.4)),
                     with: .color(Theme.bone.opacity(0.75)))   // the scut
    }

    /// A grazing deer — a stag lifts an antlered head now and then, a doe just
    /// grazes. Filled hide, four legs, a soft shadow, a white scut: an animal,
    /// not a mark on the grass.
    /// What a grazer carries on its head. Three species share this body — the
    /// silhouette across a valley is the head, so that is what differs.
    enum Crown {
        /// A stag has them, a doe does not — the deer's own rule.
        case antlersIfStag
        /// An elk: always, and heavy.
        case heavyAntlers
        /// A goat: a swept-back pair, close to the skull.
        case curvedHorns
    }

    private static func deer(
        _ context: inout GraphicsContext, at p: CGPoint, s: CGFloat,
        time: Double, phase: Double, doing: AnimalActivity, urgency: Double,
        crown: Crown = .antlersIfStag
    ) {
        let hide = Color(red: 0.72, green: 0.62, blue: 0.46)
        let dark = Color(red: 0.53, green: 0.44, blue: 0.32)
        // Head down only when it is actually grazing — and even then it lifts
        // now and again, which is what the clock is for. A deer that is wary,
        // running or lying up keeps its head up: that is what those words mean.
        let grazing = doing == .grazing && sin(time * 0.6 + phase) > 0.3
        let stag = Int(phase.rounded()) % 2 == 0
        let headY = grazing ? p.y + s * 0.55 : p.y - s * 0.95
        let headX = p.x + s * 1.35

        // Shadow.
        context.fill(Path(ellipseIn: CGRect(x: p.x - s * 1.1, y: p.y + s * 1.05,
                                            width: s * 2.4, height: s * 0.5)),
                     with: .color(Theme.ink.opacity(0.18)))
        // Four legs, and this is where the urgency goes — *amplitude*, not a
        // faster clock. (The clock rate is one for everybody: multiplying it
        // makes the phase jump by (urgency − 1) × time the moment the activity
        // changes, so the beast snaps into a different pose every time it takes
        // fright.) `urgency` was computed and then dropped on the floor, so a
        // deer running for its life had the same rigid legs as one at grass.
        let swing = doing == .resting ? 0
            : CGFloat(sin(time * 3.2 + phase)) * s * 0.09 * CGFloat(urgency)
        for (i, dx) in ([-0.65, -0.45, 0.45, 0.65] as [CGFloat]).enumerated() {
            let lead = i % 2 == 0 ? swing : -swing
            context.fill(Path(CGRect(x: p.x + dx * s - s * 0.09 + lead, y: p.y + s * 0.2,
                                     width: s * 0.18, height: s * 1.15)),
                         with: .color(dark))
        }
        // Body.
        context.fill(Path(ellipseIn: CGRect(x: p.x - s, y: p.y - s * 0.55,
                                            width: s * 2, height: s * 1.1)),
                     with: .color(hide))
        // A white scut at the tail.
        context.fill(Path(ellipseIn: CGRect(x: p.x - s * 1.12, y: p.y - s * 0.3,
                                            width: s * 0.4, height: s * 0.4)),
                     with: .color(.white.opacity(0.5)))
        // Neck + head.
        context.fill(Path { n in
            n.move(to: CGPoint(x: p.x + s * 0.55, y: p.y - s * 0.35))
            n.addLine(to: CGPoint(x: p.x + s * 1.0, y: p.y - s * 0.1))
            n.addLine(to: CGPoint(x: headX, y: headY))
            n.addLine(to: CGPoint(x: headX - s * 0.3, y: headY + s * 0.25))
            n.closeSubpath()
        }, with: .color(hide))
        context.fill(Path(ellipseIn: CGRect(x: headX - s * 0.32, y: headY - s * 0.28,
                                            width: s * 0.62, height: s * 0.52)),
                     with: .color(hide))
        if !grazing {
            context.stroke(Path { e in
                e.move(to: CGPoint(x: headX, y: headY - s * 0.2))
                e.addLine(to: CGPoint(x: headX + s * 0.32, y: headY - s * 0.55))
            }, with: .color(dark), lineWidth: 0.7)
            switch crown {
            case .antlersIfStag where stag, .heavyAntlers:
                // Branching antlers — wider and with an extra tine on an elk,
                // which is the whole of telling one from the other at distance.
                let heavy = crown == .heavyAntlers
                let spread: CGFloat = heavy ? 1.5 : 1.0
                context.stroke(Path { a in
                    a.move(to: CGPoint(x: headX - s * 0.05, y: headY - s * 0.25))
                    a.addLine(to: CGPoint(x: headX + s * 0.05, y: headY - s * 0.98 * spread))
                    a.move(to: CGPoint(x: headX, y: headY - s * 0.6 * spread))
                    a.addLine(to: CGPoint(x: headX - s * 0.35 * spread, y: headY - s * 0.82 * spread))
                    a.move(to: CGPoint(x: headX + s * 0.02, y: headY - s * 0.8 * spread))
                    a.addLine(to: CGPoint(x: headX + s * 0.42 * spread, y: headY - s * 1.02 * spread))
                    if heavy {
                        a.move(to: CGPoint(x: headX - s * 0.02, y: headY - s * 1.05))
                        a.addLine(to: CGPoint(x: headX - s * 0.55, y: headY - s * 1.28))
                    }
                }, with: .color(dark),
                style: StrokeStyle(lineWidth: heavy ? 0.9 : 0.7, lineCap: .round))
            case .curvedHorns:
                // Swept back and close to the skull, so a goat never reads as a
                // small deer.
                for side in [-1.0, 1.0] as [CGFloat] {
                    context.stroke(Path { h in
                        h.move(to: CGPoint(x: headX + side * s * 0.06, y: headY - s * 0.28))
                        h.addQuadCurve(
                            to: CGPoint(x: headX - s * 0.42, y: headY - s * 0.62),
                            control: CGPoint(x: headX + side * s * 0.30, y: headY - s * 0.78))
                    }, with: .color(dark),
                    style: StrokeStyle(lineWidth: 0.7, lineCap: .round))
                }
            case .antlersIfStag:
                break   // a doe
            }
        }
    }

    /// A lynx: short in the body, long in the leg, with the ear tufts and the
    /// stub tail that are the only things you can read at this size.
    ///
    /// Drawn apart from the wolf on purpose. Routing every cat and mustelid
    /// through `prowler` at a different size was honest but lazy — it gave the
    /// valley two more names and no more animals to look at.
    private static func lynx(
        _ context: inout GraphicsContext, at p: CGPoint, s: CGFloat,
        time: Double, doing: AnimalActivity, urgency: Double
    ) {
        let coat = Color(red: 0.66, green: 0.60, blue: 0.48)
        let dark = Color(red: 0.42, green: 0.37, blue: 0.30)
        let drive = doing == .resting ? 0 : CGFloat(urgency)
        let step = CGFloat(sin(time * 2.6)) * s * 0.18 * drive

        context.fill(Path(ellipseIn: CGRect(x: p.x - s * 1.1, y: p.y + s * 0.72,
                                            width: s * 2.2, height: s * 0.36)),
                     with: .color(.black.opacity(0.18)))
        // Long legs — the cat stands tall for its length.
        for (i, dx) in ([-0.62, -0.30, 0.34, 0.66] as [CGFloat]).enumerated() {
            let lead = i % 2 == 0 ? step : -step
            context.fill(Path(CGRect(x: p.x + dx * s - s * 0.08 + lead, y: p.y - s * 0.05,
                                     width: s * 0.17, height: s * 0.95)),
                         with: .color(i < 2 ? dark : coat))
        }
        // A short, deep body.
        context.fill(Path(ellipseIn: CGRect(x: p.x - s * 0.85, y: p.y - s * 0.55,
                                            width: s * 1.7, height: s * 0.95)),
                     with: .color(coat))
        // Head, high and round, with the tufts.
        let head = CGPoint(x: p.x + s * 0.95, y: p.y - s * 0.62)
        context.fill(Path(ellipseIn: CGRect(x: head.x - s * 0.34, y: head.y - s * 0.32,
                                            width: s * 0.68, height: s * 0.62)),
                     with: .color(coat))
        for side in [-1.0, 1.0] as [CGFloat] {
            context.stroke(Path { t in
                t.move(to: CGPoint(x: head.x + side * s * 0.20, y: head.y - s * 0.22))
                t.addLine(to: CGPoint(x: head.x + side * s * 0.30, y: head.y - s * 0.72))
            }, with: .color(dark), style: StrokeStyle(lineWidth: 0.7, lineCap: .round))
        }
        // The stub tail, which is the other half of "not a wolf".
        context.fill(Path(roundedRect: CGRect(x: p.x - s * 1.05, y: p.y - s * 0.42,
                                              width: s * 0.34, height: s * 0.22),
                          cornerRadius: s * 0.1), with: .color(dark))
        // Spots, only enough to break the coat up.
        for k in 0..<3 {
            let dx = (CGFloat(k) - 1) * s * 0.34
            context.fill(Path(ellipseIn: CGRect(x: p.x + dx - s * 0.07, y: p.y - s * 0.3,
                                                width: s * 0.14, height: s * 0.14)),
                         with: .color(dark.opacity(0.7)))
        }
    }

    /// A badger: low, wide and short-legged, and the whole read is the stripe
    /// down its face. Everything else about it at this size is "grey lump".
    private static func badger(
        _ context: inout GraphicsContext, at p: CGPoint, s: CGFloat,
        time: Double, doing: AnimalActivity, urgency: Double
    ) {
        let coat = Color(red: 0.44, green: 0.43, blue: 0.42)
        let dark = Color(red: 0.20, green: 0.19, blue: 0.19)
        let drive = doing == .resting ? 0 : CGFloat(urgency)
        let step = CGFloat(sin(time * 3.2)) * s * 0.12 * drive

        context.fill(Path(ellipseIn: CGRect(x: p.x - s * 1.1, y: p.y + s * 0.40,
                                            width: s * 2.2, height: s * 0.32)),
                     with: .color(.black.opacity(0.20)))
        // Stubby legs, barely clearing the ground.
        for (i, dx) in ([-0.55, 0.55] as [CGFloat]).enumerated() {
            let lead = i == 0 ? step : -step
            context.fill(Path(CGRect(x: p.x + dx * s - s * 0.1 + lead, y: p.y + s * 0.16,
                                     width: s * 0.2, height: s * 0.42)),
                         with: .color(dark))
        }
        // A long low body.
        context.fill(Path(roundedRect: CGRect(x: p.x - s * 1.0, y: p.y - s * 0.34,
                                              width: s * 2.0, height: s * 0.72),
                          cornerRadius: s * 0.34), with: .color(coat))
        // The head, and the two black bands with the white between them.
        let head = CGPoint(x: p.x + s * 1.02, y: p.y - s * 0.02)
        context.fill(Path(ellipseIn: CGRect(x: head.x - s * 0.36, y: head.y - s * 0.30,
                                            width: s * 0.76, height: s * 0.58)),
                     with: .color(Theme.bone.opacity(0.85)))
        for side in [-1.0, 1.0] as [CGFloat] {
            context.fill(Path(CGRect(x: head.x - s * 0.06 + side * s * 0.20,
                                     y: head.y - s * 0.30,
                                     width: s * 0.14, height: s * 0.58)),
                         with: .color(dark))
        }
    }

    /// Something grey at the tree line — a filled wolf, head low, loping. At
    /// pack pressure the eye catches red and the colony should be worried.
    private static func prowler(
        _ context: inout GraphicsContext, at p: CGPoint, s: CGFloat,
        time: Double, hungry: Bool,
        doing: AnimalActivity = .grazing, urgency: Double = 1
    ) {
        let coat = Color(red: 0.50, green: 0.51, blue: 0.55)
        let dark = Color(red: 0.36, green: 0.37, blue: 0.41)
        // A wolf closing on a deer is a wolf *moving*; one lying up is not.
        // The engine says which (`.stalking`, `.resting`) and this reads it —
        // before, every prowler loped identically whatever it was doing.
        let drive = doing == .resting ? 0 : CGFloat(urgency)
        let lope = CGFloat(sin(time * 2.2)) * s * 0.15 * drive
        let sw = CGFloat(sin(time * 2.2)) * s * 0.22 * drive

        // Shadow.
        context.fill(Path(ellipseIn: CGRect(x: p.x - s * 1.4, y: p.y + s * 0.9,
                                            width: s * 3.1, height: s * 0.5)),
                     with: .color(Theme.ink.opacity(0.16)))
        // Legs — the far pair darker, the near pair in coat.
        context.fill(Path(CGRect(x: p.x - s * 0.85 - sw, y: p.y + s * 0.1, width: s * 0.2, height: s * 0.95)), with: .color(dark))
        context.fill(Path(CGRect(x: p.x + s * 0.55 + sw, y: p.y + s * 0.1, width: s * 0.2, height: s * 0.95)), with: .color(dark))
        context.fill(Path(CGRect(x: p.x - s * 0.55 + sw, y: p.y + s * 0.1, width: s * 0.18, height: s * 0.9)), with: .color(coat))
        context.fill(Path(CGRect(x: p.x + s * 0.85 - sw, y: p.y + s * 0.1, width: s * 0.18, height: s * 0.9)), with: .color(coat))
        // Tail sweeping off the rump.
        context.fill(Path { t in
            t.move(to: CGPoint(x: p.x - s * 1.05, y: p.y - s * 0.05))
            t.addLine(to: CGPoint(x: p.x - s * 1.75, y: p.y - s * 0.5 + lope))
            t.addLine(to: CGPoint(x: p.x - s * 1.5, y: p.y - s * 0.15 + lope))
            t.addLine(to: CGPoint(x: p.x - s * 1.0, y: p.y + s * 0.15))
            t.closeSubpath()
        }, with: .color(coat))
        // Body: rump, spine, low head, snout, jaw, belly.
        context.fill(Path { b in
            b.move(to: CGPoint(x: p.x - s * 1.1, y: p.y - s * 0.1))
            b.addLine(to: CGPoint(x: p.x + s * 0.9, y: p.y - s * 0.28))
            b.addLine(to: CGPoint(x: p.x + s * 1.5, y: p.y + s * 0.15))
            b.addLine(to: CGPoint(x: p.x + s * 1.7, y: p.y + s * 0.35))
            b.addLine(to: CGPoint(x: p.x + s * 1.2, y: p.y + s * 0.5))
            b.addLine(to: CGPoint(x: p.x + s * 0.7, y: p.y + s * 0.42))
            b.addLine(to: CGPoint(x: p.x - s * 1.0, y: p.y + s * 0.45))
            b.closeSubpath()
        }, with: .color(coat))
        // Ear.
        context.fill(Path { e in
            e.move(to: CGPoint(x: p.x + s * 0.98, y: p.y - s * 0.28))
            e.addLine(to: CGPoint(x: p.x + s * 1.1, y: p.y - s * 0.62))
            e.addLine(to: CGPoint(x: p.x + s * 1.24, y: p.y - s * 0.22))
            e.closeSubpath()
        }, with: .color(dark))
        // Eye — red and larger when the pack is hungry.
        context.fill(Path(ellipseIn: CGRect(x: p.x + s * 1.4, y: p.y + s * 0.14,
                                            width: hungry ? 2.0 : 1.4, height: hungry ? 2.0 : 1.4)),
                     with: .color(hungry ? Theme.danger.opacity(0.95) : Theme.ink.opacity(0.85)))
    }
}
