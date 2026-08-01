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
        ranged: Bool = false,
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
        let scale: CGFloat = (child ? 0.7 : (elder ? 0.94 : 1.0)) * zoom * bodyScale

        let tunic = Theme.roleShade(pawn.assignedWork)
        var alpha = max(0.45, pawn.health / 100)
        if pose.activity == .sleeping { alpha *= 0.6 }
        if pose.activity == .resting { alpha *= 0.8 }

        // Walk cycle: legs swing only in proportion to how much they move.
        let gait = AgentMotion.gaitPhase(for: pawn, time: time)
        let swing = CGFloat(sin(gait) * pose.stride) * 1.7 * scale

        // Which way they are going. Everything that hangs off one side of the
        // body — the tool arm, the blade at the hip, an elder's stick — is
        // mirrored by this, so a colonist walking west walks *forwards*.
        let mirror: CGFloat = pose.facing < -0.2 ? -1 : 1
        // A walker leans into the walk and rises on each step. Two strokes'
        // worth of work, and the difference between someone walking and
        // someone being slid across the ground.
        let travelling = pose.stride > 0.5
        let lean = travelling ? CGFloat(pose.facing) * scale * 0.55 : 0
        if travelling {
            p.y -= CGFloat(abs(sin(gait))) * scale * 0.42
        }

        // The sick and the broken slouch; everyone else stands tall.
        let slouch: CGFloat = (pose.activity == .resting || pawn.isBroken) ? 1.1 : 0
        let headY = p.y - 4.9 * scale + slouch
        let shoulderY = p.y - 2.4 * scale + slouch * 0.6
        let hipY = p.y + 1.7 * scale

        // Tunic — a small filled coat in the trade's colour, leaning the way
        // they are walking.
        var torso = Path()
        torso.move(to: CGPoint(x: p.x - 1.5 * scale + lean, y: shoulderY))
        torso.addLine(to: CGPoint(x: p.x + 1.5 * scale + lean, y: shoulderY))
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
        let toolSwing = working ? sin(time * 5 + Double(AgentMotion.hash(pawn.id) % 7)) * 0.35 : 0
        let armSwing = travelling ? -swing * 0.55 : 0
        var arms = Path()
        arms.move(to: CGPoint(x: p.x - 1.3 * scale + lean * 0.6, y: shoulderY + 0.3))
        arms.addLine(to: CGPoint(x: p.x - 2.0 * scale - armSwing, y: p.y + 0.8 * scale))
        let handX = p.x + (2.1 + CGFloat(toolSwing)) * scale * mirror + armSwing
        let handY = p.y + (working ? -0.6 : 0.8) * scale
        arms.move(to: CGPoint(x: p.x + 1.3 * scale + lean * 0.6, y: shoulderY + 0.3))
        arms.addLine(to: CGPoint(x: handX, y: handY))
        context.stroke(arms, with: .color(tunic.opacity(alpha)),
                       style: StrokeStyle(lineWidth: 1.0 * scale, lineCap: .round))

        // Head — skin, not tunic: a face in the crowd, carried by the lean.
        let headX = p.x + lean
        context.fill(
            Path(ellipseIn: CGRect(x: headX - 1.7 * scale, y: headY - 1.7 * scale,
                                   width: 3.4 * scale, height: 3.4 * scale)),
            with: .color(skin.opacity(alpha)))

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
                fightingArms(ranged: ranged, at: hand,
                             scale: scale, alpha: alpha, time: time, context: &ctx)
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

    /// What a colonist does with their hands when there is fighting to do.
    ///
    /// The same distinction the simulation already draws — `CombatEngine`
    /// splits a colony's strength into what it looses and what it swings —
    /// finally visible on the person doing it. Someone with a bow is drawn
    /// nocking, drawing and loosing on a cycle; someone without is drawn
    /// swinging. It is also what a hunter does, because a hunt is the same
    /// question asked of a deer: reach it from over there, or walk up to it.
    private static func fightingArms(
        ranged: Bool, at hand: CGPoint, scale: CGFloat, alpha: Double,
        time: Double, context: inout GraphicsContext
    ) {
        let wood = Color(red: 0.60, green: 0.48, blue: 0.34).opacity(alpha)
        let iron = Color(red: 0.80, green: 0.83, blue: 0.88).opacity(alpha)

        guard ranged else {
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
