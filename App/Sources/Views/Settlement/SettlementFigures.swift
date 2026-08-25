import SwiftUI
import EndlessFrontierCore

/// Draws the colonists themselves — and the small breath of life around them
/// (chimney smoke, passing birds). Split from `SettlementRenderer` so the
/// world and its people each stay a readable file.
///
/// A figure is still line-art, but a person now: a tunic in their trade's
/// colour, a warm face, the tool of their work in hand, a blade at the hip if
/// they carry one. Children are small, elders walk with a stick, the sick
/// droop. What the sim knows about a colonist, the canvas shows.
enum SettlementFigures {
    /// Warm skin tone for faces — people, not markers.
    static let skin = Color(red: 0.89, green: 0.83, blue: 0.72)

    // MARK: - One colonist

    /// How big a grown colonist is drawn, against the buildings they live in.
    static let bodyScale: CGFloat = 0.82

    /// How tall a grown colonist stands, in points, at a given zoom.
    ///
    /// The figure is drawn in body units — the head sits at `-4.9 * scale` and
    /// the feet at `+6 * scale` — so this is that span. Anything drawn *beside*
    /// a person (a cart, a beast under a rider) sizes itself against this, or
    /// it ends up scaled against the buildings and a handcart comes out the
    /// size of a barn.
    static func bodyHeight(zoom: CGFloat) -> CGFloat { 10.9 * bodyScale * zoom }

    static func draw(
        pawn: Pawn, pose: AgentMotion.Pose, at anchor: CGPoint,
        time: Double, ticksPerYear: Int, selected: Bool, zoom: CGFloat = 1,
        armed: Armament = .none,
        // How this body moves, out of `motions.json`. Defaulted so a caller
        // without the registry still draws a person; `.standing` is a body at
        // rest rather than a body that failed.
        motion: MotionDefinition = .standing,
        /// What the content says. Needed only to look up what this colonist is
        /// *wearing and carrying* — a body draws fine without it, which is why
        /// it is optional rather than a new requirement on every call site.
        registry: GameDataRegistry? = nil,
        context: inout GraphicsContext
    ) {
        var p = anchor
        let years = pawn.ageYears(ticksPerYear: ticksPerYear)
        let child = years < Pawn.adultAgeYears
        let elder = years >= 56
        // Every stroke of the figure is `scale`-relative, so folding the
        // camera in here scales the whole person — zooming in no longer grows
        // the town around doll-sized colonists.
        //
        // `bodyScale` shrank people a notch once buildings gained insides: at
        // full size a colonist stood as tall as the hut they came out of, and
        // a household at its hearth was one blob. Small enough now to fit in a
        // room with the furniture, big enough to still read as a person.
        // Who this particular person is: hair, beard, build, height, skin —
        // derived from their id and their age, never stored (§11.20, `PawnLook`).
        let look = PawnLook.of(pawn, ageYears: years)
        // …and what has happened to them since. `PawnLook` says who somebody
        // is; this says what the world has done to them (`PawnHarm`).
        let harm = PawnHarm.of(pawn)
        let scale: CGFloat = (child ? 0.7 : (elder ? 0.94 : 1.0))
            * CGFloat(look.height) * zoom * bodyScale

        let tunic = Theme.roleShade(pawn.assignedWork)
        var alpha = max(0.45, pawn.health / 100)
        alpha *= motion.opacity

        // Walk cycle: legs swing only in proportion to how much they move, and
        // how far they swing at full stride is the motion's to say. A hauler's
        // step is shorter than a walker's because their arms are full, and that
        // is now a number in `motions.json` rather than a branch in here.
        let gait = AgentMotion.gaitPhase(for: pawn, time: time)
        let swing = CGFloat(sin(gait * motion.legs.frequency + motion.legs.phase)
                            * pose.stride) * CGFloat(motion.legs.amplitude) * scale

        // Which way they are going. Everything that hangs off one side of the
        // body — the tool arm, the blade at the hip, an elder's stick — is
        // mirrored by this, so a colonist walking west walks *forwards*.
        let mirror: CGFloat = pose.facing < -0.2 ? -1 : 1
        // A walker leans into the walk and rises on each step. Two strokes'
        // worth of work, and the difference between someone walking and
        // someone being slid across the ground.
        // Still gated on actually being under way: a body leans *into* a
        // movement, and a figure standing at a bench that tips over because its
        // clip says `lean` reads as a person falling.
        let travelling = pose.stride > 0.5
        let lean = travelling ? CGFloat(pose.facing) * scale * CGFloat(motion.lean) : 0
        if travelling {
            p.y -= CGFloat(abs(sin(gait))) * scale * CGFloat(motion.bob)
        }

        // The sick and the broken slouch — and so, a little, does age. A colony
        // whose real problem is everybody growing old together should look it
        // without opening a panel (§11.17, §11.20).
        let slouch: CGFloat = CGFloat(motion.slouch) + (pawn.isBroken ? 1.1 : 0)
            + CGFloat(look.stoop) * 0.9 * scale
        let headY = p.y - 4.9 * scale + slouch
        let shoulderY = p.y - 2.4 * scale + slouch * 0.6
        let hipY = p.y + 1.7 * scale

        // Tunic — a small filled coat in the trade's colour, leaning the way
        // they are walking.
        // Shoulders carry the build: a heavy colonist is wider at the top than
        // at the hip, a slight one barely tapers.
        let shoulder = 1.5 * scale * CGFloat(look.build)
        var torso = Path()
        torso.move(to: CGPoint(x: p.x - shoulder + lean, y: shoulderY))
        torso.addLine(to: CGPoint(x: p.x + shoulder + lean, y: shoulderY))
        torso.addLine(to: CGPoint(x: p.x + 1.1 * scale, y: hipY))
        torso.addLine(to: CGPoint(x: p.x - 1.1 * scale, y: hipY))
        torso.closeSubpath()
        context.fill(torso, with: .color(tunic.opacity(alpha * 0.9)))

        // Legs — and what is left of them.
        //
        // A leg that is gone ends at the knee and the body leans on a stick; a
        // hurt one barely swings, which is what a limp *is* at this size. The
        // whole of "the wounds match what we see" starts here: the engine has
        // known about missing legs since the medical model went in, and the
        // figure walked on two good ones regardless.
        let leftDrop: CGFloat = harm.leftLeg.isGone ? 3.1 : 6
        let rightDrop: CGFloat = harm.rightLeg.isGone ? 3.1 : 6
        let leftSwing = harm.leftLeg == .whole ? swing : swing * 0.25
        let rightSwing = harm.rightLeg == .whole ? swing : swing * 0.25
        var legs = Path()
        legs.move(to: CGPoint(x: p.x - 0.7 * scale, y: hipY))
        legs.addLine(to: CGPoint(x: p.x - 1.5 * scale + leftSwing, y: p.y + leftDrop * scale))
        legs.move(to: CGPoint(x: p.x + 0.7 * scale, y: hipY))
        legs.addLine(to: CGPoint(x: p.x + 1.5 * scale - rightSwing, y: p.y + rightDrop * scale))
        context.stroke(legs, with: .color(tunic.opacity(alpha)),
                       style: StrokeStyle(lineWidth: 1.1 * scale, lineCap: .round))
        if harm.leftLeg.isGone || harm.rightLeg.isGone {
            // The crutch, on the side that still works.
            let side: CGFloat = harm.leftLeg.isGone ? 1 : -1
            context.stroke(Path { stick in
                stick.move(to: CGPoint(x: p.x + side * 2.0 * scale, y: shoulderY + 0.6 * scale))
                stick.addLine(to: CGPoint(x: p.x + side * 2.6 * scale, y: p.y + 6 * scale))
            }, with: .color(Color(red: 0.44, green: 0.35, blue: 0.24).opacity(alpha)),
            style: StrokeStyle(lineWidth: 0.7 * scale, lineCap: .round))
        }

        // Arms: the tool arm works, and while walking both arms counter-swing
        // against the legs. Stiff arms on a moving body is the tell that a
        // figure is a picture rather than a person.
        let working = pose.activity == .working
        // The tool hand runs on its own clock, offset per colonist so a row of
        // people at the same bench are not one person drawn five times.
        let toolSwing = motion.toolArm.offset(
            at: time + Double(AgentMotion.hash(pawn.id) % 7))
        let armSwing = travelling ? -swing * CGFloat(motion.freeArmCounterSwing) : 0
        var arms = Path()
        // The free arm. Gone, it ends above the elbow — a stump, drawn short
        // rather than not drawn at all, because an arm that is simply absent
        // reads as a rendering fault instead of as an injury.
        let freeShoulder = CGPoint(x: p.x - 1.3 * scale + lean * 0.6, y: shoulderY + 0.3)
        let freeReach: CGFloat = harm.leftArm.isGone ? 0.35 : 1
        arms.move(to: freeShoulder)
        arms.addLine(to: CGPoint(
            x: freeShoulder.x + (-0.7 * scale - armSwing) * freeReach,
            y: freeShoulder.y + (p.y + 0.8 * scale - freeShoulder.y) * freeReach))
        let handX = p.x + (CGFloat(motion.reach) + CGFloat(toolSwing)) * scale * mirror + armSwing
        let handY = p.y + CGFloat(motion.handHeight) * scale
        let toolShoulder = CGPoint(x: p.x + 1.3 * scale + lean * 0.6, y: shoulderY + 0.3)
        let toolReach: CGFloat = harm.rightArm.isGone ? 0.35 : 1
        arms.move(to: toolShoulder)
        arms.addLine(to: CGPoint(x: toolShoulder.x + (handX - toolShoulder.x) * toolReach,
                                 y: toolShoulder.y + (handY - toolShoulder.y) * toolReach))
        context.stroke(arms, with: .color(tunic.opacity(alpha)),
                       style: StrokeStyle(lineWidth: 1.0 * scale, lineCap: .round))

        // Head — their own skin, not one tone for the whole colony.
        let headX = p.x + lean
        context.fill(
            Path(ellipseIn: CGRect(x: headX - 1.7 * scale, y: headY - 1.7 * scale,
                                   width: 3.4 * scale, height: 3.4 * scale)),
            with: .color(look.skin.opacity(alpha)))

        // Hair and beard, under the helmet if there is one. This is most of
        // what makes a crowd read as people rather than as one drawing repeated
        // (§11.20) — and the grey in it is the colony's age, visible.
        if pawn.equipment[.armor] == nil {
            hair(look, at: CGPoint(x: headX, y: headY), scale: scale,
                 alpha: alpha, mirror: mirror, context: &context)
        }
        beard(look, at: CGPoint(x: headX, y: headY), scale: scale,
              alpha: alpha, context: &context)

        // The dressings and the open wounds, on the body that took them. Drawn
        // over the tunic and under the gear, so a bandaged arm shows and a
        // bracer over it hides it — which is the right way round.
        if harm.isHurt {
            marks(harm, at: p, headY: headY, shoulderY: shoulderY, hipY: hipY,
                  scale: scale, alpha: alpha, lean: lean, context: &context)
        }

        // A helmet if they wear armor into the day.
        if pawn.equipment[.armor] != nil {
            context.stroke(Path { path in
                path.addArc(center: CGPoint(x: headX, y: headY),
                            radius: 1.9 * scale,
                            startAngle: .degrees(180), endAngle: .degrees(360),
                            clockwise: false)
            }, with: .color(Color(red: 0.62, green: 0.66, blue: 0.72).opacity(alpha)),
            lineWidth: 1.1 * scale)
        }

        // What they are carrying, on their back — the visible half of hauling.
        // A colonist walking home under a load of timber is the whole point of
        // the piles being on the ground in the first place.
        if let load = pawn.carrying {
            let w = 2.4 * scale, h = 1.9 * scale
            let bundle = CGRect(x: p.x - w / 2, y: shoulderY - h * 0.35, width: w, height: h)
            context.fill(Path(roundedRect: bundle, cornerRadius: 0.5 * scale),
                         with: .color(SettlementPiles.goodsColour(load.itemID).opacity(alpha)))
            context.stroke(Path(roundedRect: bundle, cornerRadius: 0.5 * scale),
                           with: .color(Theme.ink.opacity(0.45)), lineWidth: 0.5)
            // A strap over the shoulder, so it reads as carried and not worn.
            context.stroke(Path { path in
                path.move(to: CGPoint(x: p.x - 1.2 * scale, y: shoulderY + 0.4 * scale))
                path.addLine(to: CGPoint(x: p.x + 1.2 * scale, y: shoulderY - 0.2 * scale))
            }, with: .color(Theme.boneDim.opacity(alpha * 0.8)), lineWidth: 0.6 * scale)
        }

        // The tool of the trade, in the working hand — or the weapon, when the
        // day has been interrupted by something that wants killing.
        // A hunter at work is a hunter fighting something: the bow comes up the
        // same way whether the thing in front of them is a raider or a deer.
        // Every one of these is drawn reaching to the *right* of the hand, so
        // a figure facing left has its context mirrored about the hand rather
        // than each shape rewritten. A hoe that crosses its owner's chest is
        // the second half of the "everyone faces right" problem.
        let hand = CGPoint(x: handX, y: handY)
        if pose.activity == .fighting || (working && pawn.assignedWork == .hunting) {
            mirrored(&context, about: handX, by: mirror) { ctx in
                fightingArms(armed, work: pawn.assignedWork, at: hand,
                             scale: scale, alpha: alpha, time: time,
                             skin: look.skin, context: &ctx)
            }
        } else if working {
            mirrored(&context, about: handX, by: mirror) { ctx in
                tool(for: pawn.assignedWork, at: hand,
                     scale: scale, alpha: alpha, time: time, context: &ctx)
            }
        }

        // **What they are wearing**, over the tunic and under everything else.
        //
        // Drawn from the piece's own `ArmourProfile` — what it is made of, how
        // much of them it wraps, whether there is anything on their head. Every
        // coat in the game used to be this same figure in this same tunic, with
        // one steel line at the hip standing in for the whole of a person's
        // equipment.
        if let worn = pawn.equipment[.armor], !worn.isBroken,
           let def = registry?.item(worn.definitionID) {
            armour(ArmourLook(def, quality: worn.quality),
                   at: p, shoulderY: shoulderY, hipY: hipY, headY: headY,
                   shoulder: shoulder, lean: lean, scale: scale, alpha: alpha,
                   context: &context)
        }

        // A weapon at the hip — equipment you can *see*, on the side away from
        // the tool hand, and **shaped like the weapon it is**: a knife rides
        // short and steep, a longsword hangs the length of a thigh, a slung
        // firearm crosses the back. One steel line stood for all eighty-two.
        if let held = pawn.equipment[.weapon], !held.isBroken {
            sheathed(registry?.item(held.definitionID)?.combat,
                     at: p, hipY: hipY, shoulderY: shoulderY,
                     mirror: mirror, scale: scale, alpha: alpha, context: &context)
        }

        // An elder's walking stick, planted ahead of them.
        if elder {
            context.stroke(Path { path in
                path.move(to: CGPoint(x: p.x + 2.4 * scale * mirror, y: shoulderY + 1))
                path.addLine(to: CGPoint(x: p.x + 2.9 * scale * mirror, y: p.y + 6 * scale))
            }, with: .color(Color(red: 0.55, green: 0.46, blue: 0.35).opacity(alpha)),
            lineWidth: 0.8 * scale)
        }

        // Sleep reads as a dimmed figure and a drifting 'z'.
        if pose.activity == .sleeping {
            let rise = (time * 8).truncatingRemainder(dividingBy: 6)
            let text = Text("z").font(.system(size: 5)).foregroundStyle(Theme.boneDim.opacity(0.7))
            context.draw(context.resolve(text),
                         at: CGPoint(x: p.x + 3 * scale, y: headY - 3 - rise * 0.4))
        }

        if selected {
            context.stroke(
                Path(ellipseIn: CGRect(x: p.x - 8, y: p.y - 9, width: 16, height: 16)),
                with: .color(Theme.bone), lineWidth: 1.2)
            // Their name over their head — you're following a person, and the
            // canvas says which one.
            let name = Text(pawn.name)
                .font(.system(size: 6, weight: .semibold))
                .foregroundStyle(Theme.bone)
            context.draw(context.resolve(name), at: CGPoint(x: p.x, y: headY - 8))
        }
    }

    /// Hair, drawn over the skull rather than beside it.
    ///
    /// The head is a circle of radius `1.7 * scale`, so the cap is an arc a
    /// little outside it and everything that falls — a length of hair, a braid
    /// — hangs off the **back**, which is whichever side they are not facing.
    private static func hair(
        _ look: PawnLook, at head: CGPoint, scale: CGFloat, alpha: Double,
        mirror: CGFloat, context: inout GraphicsContext
    ) {
        guard look.hair != .bald else { return }
        let colour = look.hairColour.opacity(alpha)
        let r = 1.7 * scale
        let back = -mirror          // the side away from the way they face

        // The cap: an arc over the crown, thicker on the fuller styles.
        let thickness: CGFloat
        switch look.hair {
        case .cropped:  thickness = 0.55
        case .short:    thickness = 0.8
        case .tousled:  thickness = 0.85
        case .long, .braided: thickness = 0.9
        case .bald:     thickness = 0
        }
        context.stroke(Path { cap in
            cap.addArc(center: head, radius: r * 0.86,
                       startAngle: .degrees(190), endAngle: .degrees(350),
                       clockwise: false)
        }, with: .color(colour),
        style: StrokeStyle(lineWidth: thickness * scale, lineCap: .round))

        switch look.hair {
        case .bald, .cropped:
            break
        case .short:
            // A sideburn down the back edge of the jaw.
            context.stroke(Path { s in
                s.move(to: CGPoint(x: head.x + back * r * 0.82, y: head.y - r * 0.3))
                s.addLine(to: CGPoint(x: head.x + back * r * 0.78, y: head.y + r * 0.35))
            }, with: .color(colour), lineWidth: 0.45 * scale)
        case .tousled:
            // Three short tufts off the crown — the difference between hair
            // and a helmet liner.
            for (i, angle) in [212.0, 250.0, 292.0].enumerated() {
                let a = Angle.degrees(angle).radians
                let from = CGPoint(x: head.x + cos(a) * r * 0.86,
                                   y: head.y + sin(a) * r * 0.86)
                let out = r * (0.45 + CGFloat(i % 2) * 0.2)
                context.stroke(Path { t in
                    t.move(to: from)
                    t.addLine(to: CGPoint(x: from.x + cos(a) * out * 0.7,
                                          y: from.y + sin(a) * out))
                }, with: .color(colour),
                style: StrokeStyle(lineWidth: 0.4 * scale, lineCap: .round))
            }
        case .long:
            // A fall of hair down the back of the neck.
            context.fill(Path { l in
                l.move(to: CGPoint(x: head.x + back * r * 0.9, y: head.y - r * 0.45))
                l.addLine(to: CGPoint(x: head.x + back * r * 1.15, y: head.y + r * 1.5))
                l.addLine(to: CGPoint(x: head.x + back * r * 0.5, y: head.y + r * 1.5))
                l.addLine(to: CGPoint(x: head.x + back * r * 0.35, y: head.y - r * 0.3))
                l.closeSubpath()
            }, with: .color(colour))
        case .braided:
            // A braid, with two ties down it.
            let x = head.x + back * r * 0.85
            context.stroke(Path { b in
                b.move(to: CGPoint(x: x, y: head.y - r * 0.2))
                b.addLine(to: CGPoint(x: x + back * r * 0.2, y: head.y + r * 1.8))
            }, with: .color(colour),
            style: StrokeStyle(lineWidth: 0.55 * scale, lineCap: .round))
            for k in 1...2 {
                let y = head.y + r * (0.5 + CGFloat(k) * 0.5)
                context.stroke(Path { t in
                    t.move(to: CGPoint(x: x - r * 0.18, y: y))
                    t.addLine(to: CGPoint(x: x + r * 0.18, y: y))
                }, with: .color(colour.opacity(alpha * 0.7)), lineWidth: 0.3 * scale)
            }
        }
    }

    /// A beard, under the jaw. Adults only — `PawnLook` gives children `.none`.
    private static func beard(
        _ look: PawnLook, at head: CGPoint, scale: CGFloat, alpha: Double,
        context: inout GraphicsContext
    ) {
        guard look.beard != .none else { return }
        let colour = look.hairColour.opacity(alpha)
        let r = 1.7 * scale
        switch look.beard {
        case .none:
            break
        case .stubble:
            context.stroke(Path { j in
                j.addArc(center: head, radius: r * 0.82,
                         startAngle: .degrees(25), endAngle: .degrees(155),
                         clockwise: false)
            }, with: .color(colour.opacity(alpha * 0.45)), lineWidth: 0.4 * scale)
        case .short:
            context.fill(Path { b in
                b.addArc(center: head, radius: r * 0.95,
                         startAngle: .degrees(20), endAngle: .degrees(160),
                         clockwise: false)
                b.addArc(center: head, radius: r * 0.6,
                         startAngle: .degrees(160), endAngle: .degrees(20),
                         clockwise: true)
                b.closeSubpath()
            }, with: .color(colour))
        case .full:
            context.fill(Path { b in
                b.move(to: CGPoint(x: head.x - r * 0.9, y: head.y - r * 0.15))
                b.addQuadCurve(to: CGPoint(x: head.x + r * 0.9, y: head.y - r * 0.15),
                               control: CGPoint(x: head.x, y: head.y + r * 1.75))
                b.addQuadCurve(to: CGPoint(x: head.x - r * 0.9, y: head.y - r * 0.15),
                               control: CGPoint(x: head.x, y: head.y + r * 0.5))
                b.closeSubpath()
            }, with: .color(colour))
        }
    }

    /// Draws `content` flipped left-to-right about `x` when `by` is negative.
    ///
    /// Everything a colonist holds is written reaching to the right of the
    /// hand. Rather than give every hoe, bow and pick a signed variant, the
    /// context is mirrored about the hand for anyone facing the other way —
    /// one place to get right, and the tools cannot drift apart.
    private static func mirrored(
        _ context: inout GraphicsContext, about x: CGFloat, by direction: CGFloat,
        content: (inout GraphicsContext) -> Void
    ) {
        guard direction < 0 else {
            content(&context)
            return
        }
        var flipped = context
        flipped.translateBy(x: x, y: 0)
        flipped.scaleBy(x: -1, y: 1)
        flipped.translateBy(x: -x, y: 0)
        content(&flipped)
    }

    /// What somebody with no weapon fights with.
    ///
    /// Not a sword. A colony's militia is its farmers and its miners, and the
    /// thing in their hands when the horn goes is the thing that was in them a
    /// moment before: an axe off the stump, a pick off the face, a scythe out
    /// of the field. `CombatEngine` has always priced them as unarmed —
    /// `baseUnarmedPower` — and this is what unarmed actually looks like.
    private static func improvisedArms(
        work: WorkKind, at hand: CGPoint, scale: CGFloat, alpha: Double,
        time: Double, wood: Color, iron: Color, context: inout GraphicsContext
    ) {
        let swing = sin(time * 6.2)
        let angle = -2.1 + swing * 1.3

        // What their trade puts in their hand, if anything does.
        let haft: CGFloat
        let head: CGFloat
        switch work {
        case .logging:  haft = 3.4; head = 1.0     // an axe
        case .mining:   haft = 3.8; head = 1.2     // a pick
        case .farming:  haft = 4.0; head = 1.4     // a scythe, unwieldy and long
        case .hunting:  haft = 3.2; head = 0.7     // a knife on a shaft
        case .crafting, .building: haft = 3.0; head = 0.9   // a hammer
        default:
            // Nothing at all: fists. Two short jabs, and they read as somebody
            // who should not be in the line.
            let reach = 1.5 * scale + CGFloat(abs(swing)) * 0.9 * scale
            for side in [-0.5, 0.35] as [Double] {
                let a = angle + side
                let fist = CGPoint(x: hand.x + CGFloat(cos(a)) * reach,
                                   y: hand.y + CGFloat(sin(a)) * reach)
                context.stroke(Path { p in
                    p.move(to: hand)
                    p.addLine(to: fist)
                }, with: .color(skin.opacity(alpha * 0.9)),
                   style: StrokeStyle(lineWidth: 0.9 * scale, lineCap: .round))
                context.fill(Path(ellipseIn: CGRect(
                    x: fist.x - 0.45 * scale, y: fist.y - 0.45 * scale,
                    width: 0.9 * scale, height: 0.9 * scale)),
                    with: .color(skin.opacity(alpha)))
            }
            return
        }

        // The haft, in wood, and the working end in iron across the tip. A
        // tool swung in anger is still a tool: shorter reach than a blade and
        // visibly the wrong shape for this.
        let tip = CGPoint(x: hand.x + CGFloat(cos(angle)) * haft * scale,
                          y: hand.y + CGFloat(sin(angle)) * haft * scale)
        context.stroke(Path { p in
            p.move(to: hand)
            p.addLine(to: tip)
        }, with: .color(wood), style: StrokeStyle(lineWidth: 0.9 * scale, lineCap: .round))
        let across = angle + .pi / 2
        context.stroke(Path { p in
            p.move(to: CGPoint(x: tip.x - CGFloat(cos(across)) * head * scale * 0.5,
                               y: tip.y - CGFloat(sin(across)) * head * scale * 0.5))
            p.addLine(to: CGPoint(x: tip.x + CGFloat(cos(across)) * head * scale * 0.5,
                                  y: tip.y + CGFloat(sin(across)) * head * scale * 0.5))
        }, with: .color(iron), style: StrokeStyle(lineWidth: 1.0 * scale, lineCap: .round))
    }

    /// What a colonist does with their hands when there is fighting to do.
    ///
    /// The same distinction the simulation already draws — `CombatEngine`
    /// splits a colony's strength into what it looses and what it swings —
    /// finally visible on the person doing it. Someone with a bow is drawn
    /// nocking, drawing and loosing on a cycle; someone without is drawn
    /// swinging. It is also what a hunter does, because a hunt is the same
    /// question asked of a deer: reach it from over there, or walk up to it.
    /// What is actually in a colonist's hands when the fighting starts.
    ///
    /// This used to be a `Bool` — bow or blade — and *everybody* without a bow
    /// was drawn swinging a bar of iron, including the sixty people in the
    /// colony who own nothing at all. A militia of farmers looked like a
    /// company of swordsmen. What a colonist brings to a fight is what they
    /// were already holding: a hunter's bow, a smith's sword if they have one,
    /// otherwise the axe or the pick or the scythe they work with — and if
    /// their trade has no edge on it, their fists.
    enum Armament {
        /// Something they actually own, drawn as what it is.
        case held(CombatProfile)
        /// No weapon. They swing whatever their trade puts in their hand.
        case none

        /// A bare bow, for callers that have no item to hand (tests, and the
        /// old two-shape world).
        static let bow = Armament.held(CombatProfile(damage: 1, kind: .ranged))
        static let blade = Armament.held(CombatProfile(damage: 1, kind: .melee))
    }

    /// **What a weapon looks like, worked out from what it is.**
    ///
    /// The same move `StructureVariant` makes for buildings and
    /// `SettlementConveyances` makes for carts: there are eighty-two weapons
    /// and there will be more, so the difference between them has to fall out
    /// of their own fields rather than out of a drawing per weapon. Keks:
    /// *"vsichni by meli mit svou vyzbroj viditelnou pokud nejakou maji."*
    ///
    /// `projectile` decides the family, `damage` decides how long and heavy the
    /// haft is, and `caliber` decides how big the business end looks.
    struct WeaponLook {
        let projectile: ProjectileKind
        /// How much weapon there is, 0…1 — a knife against a poleaxe.
        let heft: Double
        let caliber: Double

        init(_ profile: CombatProfile) {
            projectile = profile.projectile
            // Damage runs from about 2 for a knife to about 40 for the heavy
            // end of the book. Rooted rather than linear, so the difference
            // between a knife and a sword is visible and the difference
            // between a rifle and a heavier rifle is not absurd.
            heft = min(1, max(0, (profile.damage / 30).squareRoot()))
            caliber = profile.caliber ?? 1
        }
    }

    /// `skin` is the fighter's *own* tone — bare fists belong to the face above
    /// them, and drawing every colony's hands one colour was the same "one
    /// drawing repeated" problem `PawnLook` exists to fix.
    private static func fightingArms(
        _ armed: Armament, work: WorkKind, at hand: CGPoint, scale: CGFloat,
        alpha: Double, time: Double, skin: Color = SettlementFigures.skin,
        context: inout GraphicsContext
    ) {
        let wood = Color(red: 0.60, green: 0.48, blue: 0.34).opacity(alpha)
        let iron = Color(red: 0.80, green: 0.83, blue: 0.88).opacity(alpha)

        guard case .held(let profile) = armed else {
            improvisedArms(work: work, at: hand, scale: scale, alpha: alpha,
                           time: time, wood: wood, iron: iron, context: &context)
            return
        }
        let look = WeaponLook(profile)
        switch look.projectile {
        case .none:
            melee(look, at: hand, scale: scale, time: time,
                  wood: wood, iron: iron, context: &context)
        case .arrow:
            bow(look, at: hand, scale: scale, alpha: alpha, time: time,
                wood: wood, crossbow: false, context: &context)
        case .bolt:
            bow(look, at: hand, scale: scale, alpha: alpha, time: time,
                wood: wood, crossbow: true, context: &context)
        case .stone:
            sling(look, at: hand, scale: scale, alpha: alpha, time: time,
                  context: &context)
        case .dart:
            tube(look, at: hand, scale: scale, time: time, colour: wood,
                 bore: 0.5, context: &context)
        case .ball, .bullet, .shot:
            firearm(look, at: hand, scale: scale, alpha: alpha, time: time,
                    wood: wood, iron: iron, context: &context)
        case .shell, .grenade, .rocket:
            tube(look, at: hand, scale: scale, time: time, colour: iron,
                 bore: 1.6, context: &context)
        case .beam:
            emitter(look, at: hand, scale: scale, alpha: alpha, time: time,
                    context: &context)
        }
    }

    // MARK: - The families

    /// Swung: how long the haft is, and how heavy the head, comes from `heft` —
    /// a knife is a stub with an edge, a poleaxe is a shaft you can see across
    /// the valley.
    private static func melee(
        _ look: WeaponLook, at hand: CGPoint, scale: CGFloat, time: Double,
        wood: Color, iron: Color, context: inout GraphicsContext
    ) {
        let swing = sin(time * 7)
        let angle = -2.3 + swing * 1.5
        let reach = (2.2 + 3.4 * CGFloat(look.heft)) * scale
        let tip = CGPoint(x: hand.x + CGFloat(cos(angle)) * reach,
                          y: hand.y + CGFloat(sin(angle)) * reach)
        // A heavy weapon is hafted: wood most of the way, iron at the end.
        if look.heft > 0.55 {
            let joint = CGPoint(x: hand.x + CGFloat(cos(angle)) * reach * 0.62,
                                y: hand.y + CGFloat(sin(angle)) * reach * 0.62)
            context.stroke(Path { p in p.move(to: hand); p.addLine(to: joint) },
                           with: .color(wood),
                           style: StrokeStyle(lineWidth: 1.0 * scale, lineCap: .round))
            context.stroke(Path { p in p.move(to: joint); p.addLine(to: tip) },
                           with: .color(iron),
                           style: StrokeStyle(lineWidth: 1.5 * scale, lineCap: .round))
        } else {
            context.stroke(Path { p in p.move(to: hand); p.addLine(to: tip) },
                           with: .color(iron),
                           style: StrokeStyle(lineWidth: (0.8 + 0.6 * CGFloat(look.heft)) * scale,
                                              lineCap: .round))
        }
        // The arc it cuts, faint, so the swing reads at a glance.
        context.stroke(Path { p in
            p.addArc(center: hand, radius: reach,
                     startAngle: .radians(angle - 0.5), endAngle: .radians(angle),
                     clockwise: false)
        }, with: .color(Theme.bone.opacity(0.22)), lineWidth: 0.8 * scale)
    }

    /// A bow on a cycle — nock, draw, loose — or a crossbow, which is the same
    /// limbs laid across a stock and does not bend in the hand.
    private static func bow(
        _ look: WeaponLook, at hand: CGPoint, scale: CGFloat, alpha: Double,
        time: Double, wood: Color, crossbow: Bool, context: inout GraphicsContext
    ) {
        let cycle = (time * (crossbow ? 0.9 : 1.6)).truncatingRemainder(dividingBy: 1)
        let draw = cycle < 0.7 ? cycle / 0.7 : 0
        let loosed = cycle >= 0.7 ? (cycle - 0.7) / 0.3 : 0
        let limb = (2.2 + 1.2 * CGFloat(look.heft)) * scale

        if crossbow {
            // The stock, held level, with the limbs across the front of it.
            context.stroke(Path { p in
                p.move(to: CGPoint(x: hand.x - limb * 0.8, y: hand.y))
                p.addLine(to: CGPoint(x: hand.x + limb, y: hand.y))
            }, with: .color(wood), style: StrokeStyle(lineWidth: 1.1 * scale, lineCap: .round))
            context.stroke(Path { p in
                p.move(to: CGPoint(x: hand.x + limb, y: hand.y - limb * 0.7))
                p.addLine(to: CGPoint(x: hand.x + limb, y: hand.y + limb * 0.7))
            }, with: .color(wood), lineWidth: 0.9 * scale)
        } else {
            context.stroke(Path { p in
                p.addArc(center: hand, radius: limb,
                         startAngle: .degrees(-58), endAngle: .degrees(58), clockwise: false)
            }, with: .color(wood), lineWidth: 0.9 * scale)
            let pull = CGFloat(draw) * 1.7 * scale
            let limbAngle = 58.0 * Double.pi / 180
            let top = CGPoint(x: hand.x + limb * CGFloat(cos(-limbAngle)),
                              y: hand.y + limb * CGFloat(sin(-limbAngle)))
            let bottom = CGPoint(x: hand.x + limb * CGFloat(cos(limbAngle)),
                                 y: hand.y + limb * CGFloat(sin(limbAngle)))
            context.stroke(Path { p in
                p.move(to: top)
                p.addQuadCurve(to: bottom, control: CGPoint(x: hand.x - pull, y: hand.y))
            }, with: .color(Theme.boneDim.opacity(alpha)), lineWidth: 0.5)
        }
        // What is on the string, or in the air.
        if loosed > 0 {
            let flight = CGFloat(loosed) * 9 * scale
            context.stroke(Path { p in
                p.move(to: CGPoint(x: hand.x + limb + flight, y: hand.y))
                p.addLine(to: CGPoint(x: hand.x + limb + flight + 2.2 * scale, y: hand.y))
            }, with: .color(Theme.bone.opacity(alpha * (1 - Double(loosed) * 0.5))),
               style: StrokeStyle(lineWidth: 0.6 * scale * CGFloat(look.caliber), lineCap: .round))
        } else {
            let pull = CGFloat(draw) * 1.7 * scale
            context.stroke(Path { p in
                p.move(to: CGPoint(x: hand.x - (crossbow ? 0 : pull), y: hand.y))
                p.addLine(to: CGPoint(x: hand.x + limb * 1.1, y: hand.y))
            }, with: .color(Theme.bone.opacity(alpha * 0.8)), lineWidth: 0.5 * scale)
        }
    }

    /// A sling: a cord whirled, and the stone away.
    private static func sling(
        _ look: WeaponLook, at hand: CGPoint, scale: CGFloat, alpha: Double,
        time: Double, context: inout GraphicsContext
    ) {
        let whirl = time * 5
        let radius = 2.4 * scale
        let pouch = CGPoint(x: hand.x + CGFloat(cos(whirl)) * radius,
                            y: hand.y + CGFloat(sin(whirl)) * radius)
        context.stroke(Path { p in p.move(to: hand); p.addLine(to: pouch) },
                       with: .color(Theme.boneDim.opacity(alpha * 0.8)), lineWidth: 0.5 * scale)
        context.fill(Path(ellipseIn: CGRect(
            x: pouch.x - 0.7 * scale, y: pouch.y - 0.7 * scale,
            width: 1.4 * scale, height: 1.4 * scale)),
            with: .color(Theme.bone.opacity(alpha)))
    }

    /// Anything with a barrel and a stock: the barrel's length comes from the
    /// heft, and the smoke is most of what black powder looks like.
    private static func firearm(
        _ look: WeaponLook, at hand: CGPoint, scale: CGFloat, alpha: Double,
        time: Double, wood: Color, iron: Color, context: inout GraphicsContext
    ) {
        let barrel = (2.6 + 3.2 * CGFloat(look.heft)) * scale
        let muzzle = CGPoint(x: hand.x + barrel, y: hand.y)
        context.stroke(Path { p in
            p.move(to: CGPoint(x: hand.x - 1.6 * scale, y: hand.y + 0.5 * scale))
            p.addLine(to: hand)
        }, with: .color(wood), style: StrokeStyle(lineWidth: 1.2 * scale, lineCap: .round))
        context.stroke(Path { p in p.move(to: hand); p.addLine(to: muzzle) },
                       with: .color(iron),
                       style: StrokeStyle(lineWidth: (0.7 + 0.5 * CGFloat(look.caliber)) * scale,
                                          lineCap: .round))
        // The report, on its own beat.
        let shot = (time * 2.2).truncatingRemainder(dividingBy: 1)
        guard shot < 0.18 else { return }
        let bloom = CGFloat(1 - shot / 0.18)
        context.fill(Path(ellipseIn: CGRect(
            x: muzzle.x - 1.4 * scale * bloom, y: muzzle.y - 1.4 * scale * bloom,
            width: 2.8 * scale * bloom, height: 2.8 * scale * bloom)),
            with: .color(Theme.bone.opacity(alpha * 0.35 * Double(bloom))))
    }

    /// A tube held to the shoulder or the lips — a blowpipe at one end of the
    /// ages and a launcher at the other, the same silhouette at two sizes.
    private static func tube(
        _ look: WeaponLook, at hand: CGPoint, scale: CGFloat, time: Double,
        colour: Color, bore: CGFloat, context: inout GraphicsContext
    ) {
        let length = (3.0 + 2.6 * CGFloat(look.heft)) * scale
        context.stroke(Path { p in
            p.move(to: CGPoint(x: hand.x - 1.2 * scale, y: hand.y - 0.6 * scale))
            p.addLine(to: CGPoint(x: hand.x + length, y: hand.y - 1.0 * scale))
        }, with: .color(colour),
           style: StrokeStyle(lineWidth: bore * scale, lineCap: .round))
    }

    /// Nothing is thrown: a line that exists for an instant, and a lit core.
    private static func emitter(
        _ look: WeaponLook, at hand: CGPoint, scale: CGFloat, alpha: Double,
        time: Double, context: inout GraphicsContext
    ) {
        let length = 3.4 * scale
        context.stroke(Path { p in
            p.move(to: hand)
            p.addLine(to: CGPoint(x: hand.x + length, y: hand.y))
        }, with: .color(Theme.textDim.opacity(alpha)),
           style: StrokeStyle(lineWidth: 1.2 * scale, lineCap: .round))
        let pulse = 0.5 + 0.5 * sin(time * 9)
        context.fill(Path(ellipseIn: CGRect(
            x: hand.x + length - 0.6 * scale, y: hand.y - 0.6 * scale,
            width: 1.2 * scale, height: 1.2 * scale)),
            with: .color(Theme.accent.opacity(alpha * (0.4 + 0.6 * pulse))))
    }

    /// A few strokes of the trade's tool at the hand position.
    private static func tool(
        for work: WorkKind, at hand: CGPoint, scale: CGFloat, alpha: Double,
        time: Double, context: inout GraphicsContext
    ) {
        let wood = Color(red: 0.60, green: 0.48, blue: 0.34).opacity(alpha)
        let iron = Color(red: 0.74, green: 0.77, blue: 0.83).opacity(alpha)
        switch work {
        case .farming:
            // A hoe: shaft down-right, blade at the foot.
            context.stroke(Path { p in
                p.move(to: hand)
                p.addLine(to: CGPoint(x: hand.x + 1.6 * scale, y: hand.y + 4.6 * scale))
            }, with: .color(wood), lineWidth: 0.9 * scale)
            context.stroke(Path { p in
                p.move(to: CGPoint(x: hand.x + 1.6 * scale, y: hand.y + 4.6 * scale))
                p.addLine(to: CGPoint(x: hand.x + 3.0 * scale, y: hand.y + 4.9 * scale))
            }, with: .color(iron), lineWidth: 1.1 * scale)
        case .logging:
            // An axe raised over the shoulder.
            context.stroke(Path { p in
                p.move(to: hand)
                p.addLine(to: CGPoint(x: hand.x + 2.6 * scale, y: hand.y - 2.6 * scale))
            }, with: .color(wood), lineWidth: 0.9 * scale)
            context.fill(Path { p in
                p.move(to: CGPoint(x: hand.x + 2.6 * scale, y: hand.y - 2.6 * scale))
                p.addLine(to: CGPoint(x: hand.x + 3.8 * scale, y: hand.y - 2.2 * scale))
                p.addLine(to: CGPoint(x: hand.x + 2.9 * scale, y: hand.y - 1.4 * scale))
                p.closeSubpath()
            }, with: .color(iron))
        case .mining:
            // A pick.
            context.stroke(Path { p in
                p.move(to: hand)
                p.addLine(to: CGPoint(x: hand.x + 2.4 * scale, y: hand.y - 2.4 * scale))
            }, with: .color(wood), lineWidth: 0.9 * scale)
            context.stroke(Path { p in
                p.move(to: CGPoint(x: hand.x + 1.4 * scale, y: hand.y - 3.4 * scale))
                p.addQuadCurve(to: CGPoint(x: hand.x + 3.6 * scale, y: hand.y - 1.6 * scale),
                               control: CGPoint(x: hand.x + 3.2 * scale, y: hand.y - 3.2 * scale))
            }, with: .color(iron), lineWidth: 1.0 * scale)
        case .foraging:
            // A gathering basket.
            context.stroke(Path { p in
                p.move(to: CGPoint(x: hand.x, y: hand.y + 0.6 * scale))
                p.addLine(to: CGPoint(x: hand.x + 2.4 * scale, y: hand.y + 0.6 * scale))
                p.addLine(to: CGPoint(x: hand.x + 1.9 * scale, y: hand.y + 2.2 * scale))
                p.addLine(to: CGPoint(x: hand.x + 0.5 * scale, y: hand.y + 2.2 * scale))
                p.closeSubpath()
            }, with: .color(wood), lineWidth: 0.8 * scale)
        case .hunting:
            // A strung bow.
            context.stroke(Path { p in
                p.addArc(center: hand, radius: 2.6 * scale,
                         startAngle: .degrees(-55), endAngle: .degrees(55), clockwise: false)
            }, with: .color(wood), lineWidth: 0.9 * scale)
            context.stroke(Path { p in
                p.move(to: CGPoint(x: hand.x + 2.6 * scale * cos(-55 * .pi / 180),
                                   y: hand.y + 2.6 * scale * sin(-55 * .pi / 180)))
                p.addLine(to: CGPoint(x: hand.x + 2.6 * scale * cos(55 * .pi / 180),
                                      y: hand.y + 2.6 * scale * sin(55 * .pi / 180)))
            }, with: .color(Theme.boneDim.opacity(alpha)), lineWidth: 0.5)
        case .research:
            // An open scroll.
            context.stroke(Path { p in
                p.move(to: CGPoint(x: hand.x - 0.4 * scale, y: hand.y))
                p.addLine(to: CGPoint(x: hand.x + 2.6 * scale, y: hand.y))
            }, with: .color(Theme.bone.opacity(alpha)), lineWidth: 1.6 * scale)
        case .building:
            // A hammer, mid-swing.
            let a = sin(time * 6) * 0.5
            context.stroke(Path { p in
                p.move(to: hand)
                p.addLine(to: CGPoint(x: hand.x + 2.2 * scale, y: hand.y - (2.0 + a) * scale))
            }, with: .color(wood), lineWidth: 0.9 * scale)
            context.fill(Path(CGRect(x: hand.x + 1.7 * scale, y: hand.y - (2.8 + a) * scale,
                                     width: 1.6 * scale, height: 1.1 * scale)),
                         with: .color(iron))
        case .healing:
            // The healer's satchel.
            context.fill(Path(CGRect(x: hand.x, y: hand.y, width: 2.2 * scale, height: 1.7 * scale)),
                         with: .color(Color(red: 0.72, green: 0.5, blue: 0.5).opacity(alpha)))
            context.stroke(Path { p in
                p.move(to: CGPoint(x: hand.x + 0.5 * scale, y: hand.y + 0.85 * scale))
                p.addLine(to: CGPoint(x: hand.x + 1.7 * scale, y: hand.y + 0.85 * scale))
                p.move(to: CGPoint(x: hand.x + 1.1 * scale, y: hand.y + 0.3 * scale))
                p.addLine(to: CGPoint(x: hand.x + 1.1 * scale, y: hand.y + 1.4 * scale))
            }, with: .color(Theme.bone.opacity(alpha)), lineWidth: 0.5)
        case .trade:
            // A shouldered sack.
            context.fill(Path(ellipseIn: CGRect(x: hand.x, y: hand.y - 1.4 * scale,
                                                width: 2.4 * scale, height: 2.0 * scale)),
                         with: .color(wood))
        case .scouting:
            // A spear taller than its bearer.
            context.stroke(Path { p in
                p.move(to: CGPoint(x: hand.x + 0.6 * scale, y: hand.y + 4.4 * scale))
                p.addLine(to: CGPoint(x: hand.x + 0.6 * scale, y: hand.y - 6.4 * scale))
            }, with: .color(wood), lineWidth: 0.8 * scale)
            context.fill(Path { p in
                p.move(to: CGPoint(x: hand.x + 0.6 * scale, y: hand.y - 7.6 * scale))
                p.addLine(to: CGPoint(x: hand.x + 0.1 * scale, y: hand.y - 6.2 * scale))
                p.addLine(to: CGPoint(x: hand.x + 1.1 * scale, y: hand.y - 6.2 * scale))
                p.closeSubpath()
            }, with: .color(iron))
        case .crafting:
            // A hammer, coming down on the beat of the work.
            let blow = CGFloat(abs(sin(time * 4.5))) * 1.6 * scale
            context.stroke(Path { p in
                p.move(to: hand)
                p.addLine(to: CGPoint(x: hand.x + 2.2 * scale, y: hand.y - 2.4 * scale + blow))
            }, with: .color(wood), lineWidth: 0.9 * scale)
            context.fill(Path(CGRect(x: hand.x + 1.9 * scale,
                                     y: hand.y - 3.2 * scale + blow,
                                     width: 1.9 * scale, height: 1.1 * scale)),
                         with: .color(iron))
        case .cooking:
            // A long spoon turning in a pot, on the slow beat of a stew rather
            // than the hammer's quick one.
            let stir = CGFloat(sin(time * 2.2))
            context.stroke(Path { p in
                p.move(to: hand)
                p.addLine(to: CGPoint(x: hand.x + (1.2 + stir * 0.9) * scale,
                                      y: hand.y + 3.4 * scale))
            }, with: .color(wood), lineWidth: 0.8 * scale)
            context.fill(Path(ellipseIn: CGRect(
                x: hand.x + (0.4 + stir * 0.9) * scale, y: hand.y + 3.2 * scale,
                width: 1.6 * scale, height: 1.0 * scale)), with: .color(wood))
        case .priest:
            // A raised staff with a small flame.
            context.stroke(Path { p in
                p.move(to: CGPoint(x: hand.x, y: hand.y + 3 * scale))
                p.addLine(to: CGPoint(x: hand.x, y: hand.y - 4.4 * scale))
            }, with: .color(wood), lineWidth: 0.8 * scale)
            context.fill(Path(ellipseIn: CGRect(x: hand.x - 0.8 * scale, y: hand.y - 5.6 * scale,
                                                width: 1.6 * scale, height: 1.6 * scale)),
                         with: .color(Theme.accent.opacity(0.8)))
        case .idle:
            break
        case .garrison:
            // A grounded spear and a shield on the arm — a watch stands, where
            // a scout's spear is carried. The butt rests on the ground.
            context.stroke(Path { p in
                p.move(to: CGPoint(x: hand.x + 0.9 * scale, y: hand.y + 5.2 * scale))
                p.addLine(to: CGPoint(x: hand.x + 0.9 * scale, y: hand.y - 5.8 * scale))
            }, with: .color(wood), lineWidth: 0.8 * scale)
            context.fill(Path { p in
                p.move(to: CGPoint(x: hand.x + 0.9 * scale, y: hand.y - 7.0 * scale))
                p.addLine(to: CGPoint(x: hand.x + 0.4 * scale, y: hand.y - 5.6 * scale))
                p.addLine(to: CGPoint(x: hand.x + 1.4 * scale, y: hand.y - 5.6 * scale))
                p.closeSubpath()
            }, with: .color(iron))
            let shield = CGRect(x: hand.x - 2.6 * scale, y: hand.y - 1.4 * scale,
                                width: 2.4 * scale, height: 3.2 * scale)
            context.fill(Path(ellipseIn: shield), with: .color(iron.opacity(0.85)))
            context.stroke(Path(ellipseIn: shield),
                           with: .color(Theme.bone.opacity(alpha)), lineWidth: 0.5)
        }
    }

    // MARK: - Smoke

    /// Hearth smoke drifting from the houses — the surest sign a town is
    /// inhabited. Deterministic per chimney, animated by the frame clock.
    static func smoke(
        _ context: inout GraphicsContext,
        houses: [SettlementRenderer.PlacedBuilding],
        time: Double, zoom: CGFloat = 1
    ) {
        for house in houses.prefix(10) {
            let phase = Double(house.id % 7) * 0.9
            let chimney = CGPoint(x: house.center.x + house.size * 0.55,
                                  y: house.center.y - house.size * 1.35)
            for k in 0..<3 {
                let t = (time * 0.22 + phase + Double(k) * 0.33)
                    .truncatingRemainder(dividingBy: 1)
                let y = chimney.y - CGFloat(t) * 13 * zoom
                let x = chimney.x + CGFloat(sin(t * 6 + phase + Double(k))) * 2.2 * zoom
                let r = (0.8 + CGFloat(t) * 2.2) * zoom
                context.fill(
                    Path(ellipseIn: CGRect(x: x - r / 2, y: y - r / 2, width: r, height: r)),
                    with: .color(Theme.boneDim.opacity((1 - t) * 0.28)))
            }
        }
    }

    // MARK: - Birds

    /// Now and then a small flock crosses the valley. Gone in winter.
    static func birds(
        _ context: inout GraphicsContext, rect: CGRect, season: Season,
        time: Double, zoom: CGFloat = 1
    ) {
        guard season != .winter else { return }
        let cycle = 43.0
        let t = time.truncatingRemainder(dividingBy: cycle)
        guard t < 14 else { return }
        let progress = t / 14
        let baseX = rect.minX + rect.width * CGFloat(progress)
        let baseY = rect.minY + rect.height * CGFloat(0.16 + sin(progress * 2.6) * 0.03)
        for i in 0..<3 {
            let bx = baseX - CGFloat(i) * 7 * zoom
            let by = baseY + CGFloat(i % 2) * 4 * zoom
            let flap = CGFloat(abs(sin(time * 7 + Double(i)))) * 1.6 * zoom
            context.stroke(Path { p in
                p.move(to: CGPoint(x: bx - 2.4 * zoom, y: by - flap))
                p.addLine(to: CGPoint(x: bx, y: by))
                p.addLine(to: CGPoint(x: bx + 2.4 * zoom, y: by - flap))
            }, with: .color(Theme.boneDim.opacity(0.55)), lineWidth: 0.8)
        }
    }

    // MARK: - What they are wearing

    /// **What a coat looks like, worked out from what it is.**
    ///
    /// The same move `WeaponLook` makes above: the difference between
    /// thirty-eight coats falls out of their own fields rather than out of a
    /// drawing apiece. `ArmourProfile.material` decides how it is stroked,
    /// `coverage` decides how much of the body it wraps, and the *piece's*
    /// quality decides how well it sits — a masterwork harness is trim where a
    /// shoddy one is lumpy, which is the one thing a player can read at this
    /// size that says somebody good made it.
    ///
    /// A piece with nothing authored still gets a look: its rarity stands in
    /// for its material and it covers the trunk. So a coat added tomorrow is
    /// drawn as *something* the day it exists and as *itself* the day somebody
    /// says what it is.
    struct ArmourLook {
        let material: ArmourProfile.Material
        let coverage: ArmourProfile.Coverage
        let helm: Bool
        let tint: Double?
        /// How trim it sits, 0…1.
        let fit: Double

        init(_ def: ItemDefinition, quality: ItemQuality) {
            if let stated = def.armour {
                material = stated.material
                coverage = stated.coverage
                helm = stated.helm
                tint = stated.tint
            } else {
                // Nothing authored. Rarity is the only honest signal of what a
                // thing is likely made of, and it is better than drawing every
                // undescribed coat as the same hide jerkin.
                switch def.rarity {
                case .common:    material = .cloth
                case .uncommon:  material = .leather
                case .rare:      material = .mail
                case .epic:      material = .plate
                case .legendary: material = .powered
                }
                coverage = .torso
                helm = false
                tint = nil
            }
            fit = min(1, max(0, Double(quality.index) / 3))
        }

        /// The colour the material is, before any tint.
        var colour: Color {
            switch material {
            case .cloth:     return Color(red: 0.72, green: 0.68, blue: 0.58)
            case .hide:      return Color(red: 0.55, green: 0.42, blue: 0.30)
            case .leather:   return Color(red: 0.45, green: 0.31, blue: 0.20)
            case .wood:      return Color(red: 0.60, green: 0.48, blue: 0.34)
            case .bone:      return Color(red: 0.86, green: 0.84, blue: 0.76)
            case .bronze:    return Color(red: 0.72, green: 0.53, blue: 0.28)
            case .mail:      return Color(red: 0.68, green: 0.71, blue: 0.76)
            case .plate:     return Color(red: 0.82, green: 0.85, blue: 0.90)
            case .composite: return Color(red: 0.30, green: 0.33, blue: 0.36)
            case .powered:   return Color(red: 0.52, green: 0.72, blue: 0.82)
            }
        }

        /// How hard the material reads. Cloth is drawn soft and wide, plate
        /// narrow and bright.
        var weight: CGFloat {
            switch material {
            case .cloth:                     return 0.5
            case .hide, .leather, .wood:     return 0.8
            case .bone, .bronze:             return 1.0
            case .mail:                      return 1.1
            case .plate, .composite:         return 1.4
            case .powered:                   return 1.6
            }
        }
    }

    /// Draws the coat over the tunic already painted underneath.
    private static func armour(
        _ look: ArmourLook, at p: CGPoint, shoulderY: CGFloat, hipY: CGFloat,
        headY: CGFloat, shoulder: CGFloat, lean: CGFloat, scale: CGFloat,
        alpha: Double, context: inout GraphicsContext
    ) {
        var body = look.colour
        if let tint = look.tint {
            // A dyed or painted piece keeps its material's weight and takes its
            // own hue, so two reed capes of different tints are two capes.
            body = Color(hue: tint, saturation: 0.34, brightness: 0.74)
        }
        let ink = body.opacity(alpha)
        // A well-made piece sits close; a shoddy one stands off the body.
        let slack = (1 - CGFloat(look.fit)) * 0.35 * scale

        func trunk(_ topWidth: CGFloat, _ bottom: CGFloat) -> Path {
            var path = Path()
            path.move(to: CGPoint(x: p.x - topWidth + lean, y: shoulderY - slack))
            path.addLine(to: CGPoint(x: p.x + topWidth + lean, y: shoulderY - slack))
            path.addLine(to: CGPoint(x: p.x + 1.1 * scale + slack, y: bottom))
            path.addLine(to: CGPoint(x: p.x - 1.1 * scale - slack, y: bottom))
            path.closeSubpath()
            return path
        }

        switch look.coverage {
        case .mantle:
            // A cloak hangs off the shoulders and falls clear of the body.
            var cape = Path()
            cape.move(to: CGPoint(x: p.x - shoulder - slack + lean, y: shoulderY - slack))
            cape.addLine(to: CGPoint(x: p.x + shoulder + slack + lean, y: shoulderY - slack))
            cape.addLine(to: CGPoint(x: p.x + 1.7 * scale, y: hipY + 1.1 * scale))
            cape.addLine(to: CGPoint(x: p.x - 1.7 * scale, y: hipY + 1.1 * scale))
            cape.closeSubpath()
            context.fill(cape, with: .color(ink.opacity(alpha * 0.78)))
        case .head:
            break                                   // the helm below is the whole of it
        case .torso:
            context.fill(trunk(shoulder * 0.94, hipY), with: .color(ink))
        case .torsoArms:
            context.fill(trunk(shoulder * 0.94, hipY), with: .color(ink))
            // Sleeves: a short stroke down each upper arm, so the coat reads as
            // having arms in it rather than as a painted chest.
            context.stroke(Path { path in
                path.move(to: CGPoint(x: p.x - 1.3 * scale + lean * 0.6, y: shoulderY + 0.3))
                path.addLine(to: CGPoint(x: p.x - 1.9 * scale, y: p.y - 0.2 * scale))
                path.move(to: CGPoint(x: p.x + 1.3 * scale + lean * 0.6, y: shoulderY + 0.3))
                path.addLine(to: CGPoint(x: p.x + 1.9 * scale, y: p.y - 0.2 * scale))
            }, with: .color(ink), style: StrokeStyle(lineWidth: look.weight * 0.8 * scale,
                                                     lineCap: .round))
        case .full:
            context.fill(trunk(shoulder * 0.94, hipY), with: .color(ink))
            context.stroke(Path { path in
                path.move(to: CGPoint(x: p.x - 1.3 * scale + lean * 0.6, y: shoulderY + 0.3))
                path.addLine(to: CGPoint(x: p.x - 1.9 * scale, y: p.y - 0.2 * scale))
                path.move(to: CGPoint(x: p.x + 1.3 * scale + lean * 0.6, y: shoulderY + 0.3))
                path.addLine(to: CGPoint(x: p.x + 1.9 * scale, y: p.y - 0.2 * scale))
                // Greaves, down to the shin.
                path.move(to: CGPoint(x: p.x - 0.7 * scale, y: hipY))
                path.addLine(to: CGPoint(x: p.x - 1.2 * scale, y: p.y + 3.4 * scale))
                path.move(to: CGPoint(x: p.x + 0.7 * scale, y: hipY))
                path.addLine(to: CGPoint(x: p.x + 1.2 * scale, y: p.y + 3.4 * scale))
            }, with: .color(ink), style: StrokeStyle(lineWidth: look.weight * 0.8 * scale,
                                                     lineCap: .round))
        }

        // What the material does on top of the shape. This is most of what
        // tells a mail shirt from a plate cuirass at this size.
        switch look.material {
        case .mail:
            // A mesh: three short rows of dots across the chest.
            for row in 0..<3 {
                let y = shoulderY + (hipY - shoulderY) * (0.25 + Double(row) * 0.25)
                for column in -1...1 {
                    let x = p.x + CGFloat(column) * 0.62 * scale
                        + (row.isMultiple(of: 2) ? 0 : 0.3 * scale) + lean
                    context.fill(Path(ellipseIn: CGRect(x: x - 0.16 * scale, y: y - 0.16 * scale,
                                                        width: 0.32 * scale, height: 0.32 * scale)),
                                 with: .color(Theme.ink.opacity(alpha * 0.4)))
                }
            }
        case .plate, .bronze:
            // Hard segments, and a highlight down one side of the breastplate.
            context.stroke(Path { path in
                for band in 1...2 {
                    let y = shoulderY + (hipY - shoulderY) * Double(band) / 3
                    path.move(to: CGPoint(x: p.x - 1.0 * scale + lean, y: y))
                    path.addLine(to: CGPoint(x: p.x + 1.0 * scale + lean, y: y))
                }
            }, with: .color(Theme.ink.opacity(alpha * 0.35)), lineWidth: 0.3 * scale)
            context.stroke(Path { path in
                path.move(to: CGPoint(x: p.x - 0.5 * scale + lean, y: shoulderY + 0.3 * scale))
                path.addLine(to: CGPoint(x: p.x - 0.5 * scale + lean, y: hipY - 0.3 * scale))
            }, with: .color(.white.opacity(alpha * 0.5)), lineWidth: 0.32 * scale)
        case .composite, .powered:
            // Panels, and for a powered harness a lit seam — the one thing on a
            // colonist that says *this age is not the last one*.
            context.stroke(Path { path in
                path.move(to: CGPoint(x: p.x - 0.9 * scale + lean, y: shoulderY + 0.8 * scale))
                path.addLine(to: CGPoint(x: p.x + 0.9 * scale + lean, y: shoulderY + 0.8 * scale))
            }, with: .color(Theme.ink.opacity(alpha * 0.45)), lineWidth: 0.34 * scale)
            if look.material == .powered {
                context.stroke(Path { path in
                    path.move(to: CGPoint(x: p.x + 0.7 * scale + lean, y: shoulderY + 0.5 * scale))
                    path.addLine(to: CGPoint(x: p.x + 0.7 * scale + lean, y: hipY - 0.4 * scale))
                }, with: .color(Color(red: 0.55, green: 0.90, blue: 1.0).opacity(alpha * 0.85)),
                lineWidth: 0.36 * scale)
            }
        case .hide, .leather, .wood, .bone:
            // Stitching, or lashings: a seam down the middle that says somebody
            // sewed this rather than forged it.
            context.stroke(Path { path in
                path.move(to: CGPoint(x: p.x + lean, y: shoulderY + 0.4 * scale))
                path.addLine(to: CGPoint(x: p.x + lean, y: hipY - 0.3 * scale))
            }, with: .color(Theme.ink.opacity(alpha * 0.32)),
            style: StrokeStyle(lineWidth: 0.26 * scale, dash: [0.5 * scale, 0.5 * scale]))
        case .cloth:
            break                                   // a soft fill is the whole of it
        }

        // And whatever is on their head, over the hair.
        if look.helm || look.coverage == .head {
            let brim = look.material == .cloth ? 1.5 : 1.05
            context.fill(Path(ellipseIn: CGRect(
                x: p.x - brim * scale + lean, y: headY - 1.5 * scale,
                width: brim * 2 * scale, height: 1.7 * scale)),
                         with: .color(ink))
            if look.material == .plate || look.material == .powered {
                // A visor slit, which is what makes a helm read as a helm.
                context.stroke(Path { path in
                    path.move(to: CGPoint(x: p.x - 0.6 * scale + lean, y: headY - 0.5 * scale))
                    path.addLine(to: CGPoint(x: p.x + 0.6 * scale + lean, y: headY - 0.5 * scale))
                }, with: .color(Theme.ink.opacity(alpha * 0.7)), lineWidth: 0.3 * scale)
            }
        }
    }

    /// **The weapon at rest**, shaped like the weapon it is.
    ///
    /// A knife rides short and steep on the belt, a sword hangs the length of a
    /// thigh, a polearm stands past the shoulder, and anything with a barrel is
    /// slung across the back. Derived from the same `CombatProfile` the drawn
    /// fighting arms read, so what a colonist carries at rest and what they
    /// raise in a fight are the same weapon.
    private static func sheathed(
        _ profile: CombatProfile?, at p: CGPoint, hipY: CGFloat, shoulderY: CGFloat,
        mirror: CGFloat, scale: CGFloat, alpha: Double, context: inout GraphicsContext
    ) {
        let iron = Color(red: 0.78, green: 0.80, blue: 0.86).opacity(alpha)
        let wood = Color(red: 0.55, green: 0.44, blue: 0.31).opacity(alpha)
        guard let profile else {
            // Nothing said about it: the old single line, which is the right
            // answer for "they have something and we do not know what".
            context.stroke(Path { path in
                path.move(to: CGPoint(x: p.x - 1.2 * scale * mirror, y: hipY + 0.2))
                path.addLine(to: CGPoint(x: p.x - 2.6 * scale * mirror, y: hipY + 2.2 * scale))
            }, with: .color(iron), lineWidth: 0.9 * scale)
            return
        }
        let look = WeaponLook(profile)
        let hip = CGPoint(x: p.x - 1.2 * scale * mirror, y: hipY + 0.2)

        switch look.projectile {
        case .ball, .bullet, .shot, .shell, .grenade, .rocket, .beam:
            // Slung: a barrel across the back, from the off shoulder to the
            // near hip, which is how a long arm is carried when it is not up.
            let muzzle = CGPoint(x: p.x + 1.9 * scale * mirror, y: shoulderY - 0.6 * scale)
            let butt = CGPoint(x: p.x - 1.6 * scale * mirror, y: hipY + 1.9 * scale)
            context.stroke(Path { path in path.move(to: butt); path.addLine(to: muzzle) },
                           with: .color(look.projectile == .beam ? iron : wood),
                           style: StrokeStyle(lineWidth: (0.8 + 0.5 * CGFloat(look.heft)) * scale,
                                              lineCap: .round))
            // The strap it hangs on.
            context.stroke(Path { path in
                path.move(to: CGPoint(x: p.x + 1.1 * scale * mirror, y: shoulderY + 0.1))
                path.addLine(to: CGPoint(x: p.x - 0.9 * scale * mirror, y: hipY + 0.4 * scale))
            }, with: .color(wood.opacity(alpha * 0.6)), lineWidth: 0.3 * scale)
        case .arrow, .bolt:
            // A bow over the shoulder is a curve, not a line, and a quiver
            // stands up behind it.
            context.stroke(Path { path in
                path.move(to: CGPoint(x: p.x - 0.4 * scale * mirror, y: shoulderY - 0.9 * scale))
                path.addQuadCurve(
                    to: CGPoint(x: p.x - 1.5 * scale * mirror, y: hipY + 1.8 * scale),
                    control: CGPoint(x: p.x - 2.6 * scale * mirror, y: p.y - 0.2 * scale))
            }, with: .color(wood), style: StrokeStyle(lineWidth: 0.6 * scale, lineCap: .round))
            context.stroke(Path { path in
                path.move(to: CGPoint(x: p.x + 0.9 * scale * mirror, y: shoulderY - 1.2 * scale))
                path.addLine(to: CGPoint(x: p.x + 1.3 * scale * mirror, y: hipY + 0.2 * scale))
            }, with: .color(iron), style: StrokeStyle(lineWidth: 0.7 * scale, lineCap: .round))
        case .stone, .dart:
            // Coiled or tucked at the belt — barely anything, and that is the
            // point of it.
            context.stroke(Path { path in
                path.addArc(center: CGPoint(x: hip.x - 0.4 * scale * mirror,
                                            y: hip.y + 0.9 * scale),
                            radius: 0.7 * scale, startAngle: .radians(0),
                            endAngle: .radians(.pi * 1.6), clockwise: false)
            }, with: .color(wood), lineWidth: 0.4 * scale)
        case .none:
            // Hung at the belt, as long as the blade is long. A haft past
            // `heft` 0.7 is a polearm and stands up behind the shoulder.
            if look.heft > 0.7 {
                context.stroke(Path { path in
                    path.move(to: CGPoint(x: p.x - 1.0 * scale * mirror, y: hipY + 2.4 * scale))
                    path.addLine(to: CGPoint(x: p.x - 1.7 * scale * mirror,
                                             y: shoulderY - 2.4 * scale))
                }, with: .color(wood),
                style: StrokeStyle(lineWidth: 0.7 * scale, lineCap: .round))
                context.stroke(Path { path in
                    path.move(to: CGPoint(x: p.x - 1.55 * scale * mirror,
                                          y: shoulderY - 1.4 * scale))
                    path.addLine(to: CGPoint(x: p.x - 1.7 * scale * mirror,
                                             y: shoulderY - 2.4 * scale))
                }, with: .color(iron),
                style: StrokeStyle(lineWidth: 1.1 * scale, lineCap: .round))
                return
            }
            let drop = (1.0 + 2.2 * CGFloat(look.heft)) * scale
            context.stroke(Path { path in
                path.move(to: hip)
                path.addLine(to: CGPoint(x: hip.x - 0.9 * scale * mirror, y: hip.y + drop))
            }, with: .color(iron),
            style: StrokeStyle(lineWidth: (0.7 + 0.5 * CGFloat(look.heft)) * scale,
                               lineCap: .round))
            // A crossguard, on anything long enough to have one.
            if look.heft > 0.3 {
                context.stroke(Path { path in
                    path.move(to: CGPoint(x: hip.x - 0.5 * scale, y: hip.y + 0.2 * scale))
                    path.addLine(to: CGPoint(x: hip.x + 0.5 * scale, y: hip.y + 0.2 * scale))
                }, with: .color(iron), lineWidth: 0.34 * scale)
            }
        }
    }

    /// **Linen and blood, on the parts that have them.**
    ///
    /// A band of clean cloth where somebody has been tended, a dark mark where
    /// nobody has. Two strokes apiece, and only for a body that has any: the
    /// ordinary case is a whole colonist and costs one branch (rule 4 — this
    /// runs per figure per frame).
    private static func marks(
        _ harm: PawnHarm, at p: CGPoint, headY: CGFloat, shoulderY: CGFloat,
        hipY: CGFloat, scale: CGFloat, alpha: Double, lean: CGFloat,
        context: inout GraphicsContext
    ) {
        let linen = Color(red: 0.90, green: 0.88, blue: 0.82)
        let blood = Color(red: 0.55, green: 0.11, blue: 0.10)
        func spot(_ at: CGPoint, tended: Bool, wide: CGFloat) {
            if tended {
                context.stroke(Path { band in
                    band.move(to: CGPoint(x: at.x - wide, y: at.y))
                    band.addLine(to: CGPoint(x: at.x + wide, y: at.y))
                }, with: .color(linen.opacity(alpha)),
                style: StrokeStyle(lineWidth: 0.9 * scale, lineCap: .round))
            } else {
                context.fill(
                    Path(ellipseIn: CGRect(x: at.x - wide * 0.5, y: at.y - 0.4 * scale,
                                           width: wide, height: 0.9 * scale)),
                    with: .color(blood.opacity(alpha * 0.9)))
            }
        }
        for part in BodyPartKind.allCases {
            let tended = harm.bandaged.contains(part)
            guard tended || harm.open.contains(part) else { continue }
            switch part {
            case .head:
                spot(CGPoint(x: p.x + lean, y: headY - 0.2 * scale),
                     tended: tended, wide: 1.7 * scale)
            case .torso:
                spot(CGPoint(x: p.x + lean * 0.6, y: (shoulderY + hipY) / 2),
                     tended: tended, wide: 1.6 * scale)
            case .leftArm:
                spot(CGPoint(x: p.x - 1.7 * scale, y: shoulderY + 1.1 * scale),
                     tended: tended, wide: 1.0 * scale)
            case .rightArm:
                spot(CGPoint(x: p.x + 1.7 * scale, y: shoulderY + 1.1 * scale),
                     tended: tended, wide: 1.0 * scale)
            case .leftLeg:
                spot(CGPoint(x: p.x - 1.1 * scale, y: hipY + 1.8 * scale),
                     tended: tended, wide: 1.0 * scale)
            case .rightLeg:
                spot(CGPoint(x: p.x + 1.1 * scale, y: hipY + 1.8 * scale),
                     tended: tended, wide: 1.0 * scale)
            }
        }
    }

}
