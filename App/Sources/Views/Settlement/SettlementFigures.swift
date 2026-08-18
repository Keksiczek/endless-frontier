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

    static func draw(
        pawn: Pawn, pose: AgentMotion.Pose, at anchor: CGPoint,
        time: Double, ticksPerYear: Int, selected: Bool, zoom: CGFloat = 1,
        armed: Armament = .none,
        // How this body moves, out of `motions.json`. Defaulted so a caller
        // without the registry still draws a person; `.standing` is a body at
        // rest rather than a body that failed.
        motion: MotionDefinition = .standing,
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

        // Legs.
        var legs = Path()
        legs.move(to: CGPoint(x: p.x - 0.7 * scale, y: hipY))
        legs.addLine(to: CGPoint(x: p.x - 1.5 * scale + swing, y: p.y + 6 * scale))
        legs.move(to: CGPoint(x: p.x + 0.7 * scale, y: hipY))
        legs.addLine(to: CGPoint(x: p.x + 1.5 * scale - swing, y: p.y + 6 * scale))
        context.stroke(legs, with: .color(tunic.opacity(alpha)),
                       style: StrokeStyle(lineWidth: 1.1 * scale, lineCap: .round))

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
        arms.move(to: CGPoint(x: p.x - 1.3 * scale + lean * 0.6, y: shoulderY + 0.3))
        arms.addLine(to: CGPoint(x: p.x - 2.0 * scale - armSwing, y: p.y + 0.8 * scale))
        let handX = p.x + (CGFloat(motion.reach) + CGFloat(toolSwing)) * scale * mirror + armSwing
        let handY = p.y + CGFloat(motion.handHeight) * scale
        arms.move(to: CGPoint(x: p.x + 1.3 * scale + lean * 0.6, y: shoulderY + 0.3))
        arms.addLine(to: CGPoint(x: handX, y: handY))
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

        // A blade at the hip — equipment you can *see*, on the hip away from
        // the tool hand.
        if pawn.equipment[.weapon] != nil {
            context.stroke(Path { path in
                path.move(to: CGPoint(x: p.x - 1.2 * scale * mirror, y: hipY + 0.2))
                path.addLine(to: CGPoint(x: p.x - 2.6 * scale * mirror, y: hipY + 2.2 * scale))
            }, with: .color(Color(red: 0.78, green: 0.80, blue: 0.86).opacity(alpha)),
            lineWidth: 0.9 * scale)
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
        case bow
        case blade
        /// No weapon. They swing whatever their trade puts in their hand.
        case none
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

        if case .none = armed {
            improvisedArms(work: work, at: hand, scale: scale, alpha: alpha,
                           time: time, wood: wood, iron: iron, context: &context)
            return
        }
        guard case .bow = armed else {
            // A blade, swung: back over the shoulder, then down and through.
            let swing = sin(time * 7)
            let angle = -2.3 + swing * 1.5
            let reach = 4.2 * scale
            context.stroke(Path { p in
                p.move(to: hand)
                p.addLine(to: CGPoint(x: hand.x + CGFloat(cos(angle)) * reach,
                                      y: hand.y + CGFloat(sin(angle)) * reach))
            }, with: .color(iron), style: StrokeStyle(lineWidth: 1.1 * scale, lineCap: .round))
            // The arc it cuts, faint, so the swing reads at a glance.
            context.stroke(Path { p in
                p.addArc(center: hand, radius: reach,
                         startAngle: .radians(angle - 0.5), endAngle: .radians(angle),
                         clockwise: false)
            }, with: .color(Theme.bone.opacity(alpha * 0.22)), lineWidth: 0.8 * scale)
            return
        }

        // A bow, on a cycle: nock, draw, loose, and the arrow away.
        let cycle = (time * 1.6).truncatingRemainder(dividingBy: 1)
        let draw = cycle < 0.7 ? cycle / 0.7 : 0            // pulled back…
        let loosed = cycle >= 0.7 ? (cycle - 0.7) / 0.3 : 0 // …then gone
        let limb = 2.8 * scale

        context.stroke(Path { p in
            p.addArc(center: hand, radius: limb,
                     startAngle: .degrees(-58), endAngle: .degrees(58), clockwise: false)
        }, with: .color(wood), lineWidth: 0.9 * scale)
        // The string, bent back as far as the draw has come.
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
        // The arrow: on the string while drawing, in the air after.
        if loosed > 0 {
            let flight = CGFloat(loosed) * 9 * scale
            context.stroke(Path { p in
                p.move(to: CGPoint(x: hand.x + limb + flight, y: hand.y))
                p.addLine(to: CGPoint(x: hand.x + limb + flight + 2.2 * scale, y: hand.y))
            }, with: .color(Theme.bone.opacity(alpha * (1 - Double(loosed) * 0.5))),
               style: StrokeStyle(lineWidth: 0.6 * scale, lineCap: .round))
        } else {
            context.stroke(Path { p in
                p.move(to: CGPoint(x: hand.x - pull, y: hand.y))
                p.addLine(to: CGPoint(x: hand.x + limb * 1.1, y: hand.y))
            }, with: .color(Theme.bone.opacity(alpha * 0.8)), lineWidth: 0.5 * scale)
        }
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
}
