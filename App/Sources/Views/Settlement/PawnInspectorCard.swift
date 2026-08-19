import SwiftUI
import EndlessFrontierCore

/// A tap-to-inspect card for a single colonist.
///
/// It used to say health, mood and four inherited numbers, which told you what
/// a colonist *was* and nothing about how they were getting on. A colony sim is
/// about people having a bad time in interesting ways — so this now leads with
/// the four needs, says plainly **why** their mood is where it is, and names
/// the two things that had never been on screen at all: the bed they sleep in
/// and the piece of work they are on.
struct PawnInspectorCard: View {
    /// One bond, resolved to a living name for display.
    struct BondLine: Identifiable {
        let id: UUID
        let name: String
        let kind: RelationKind
    }

    let pawn: Pawn
    let ticksPerYear: Int
    /// What they are visibly doing **right now**, asked again every second.
    ///
    /// A value rather than a closure was the bug the card was reported for: the
    /// line is derived from the frame clock and the colonist's pose, and the
    /// card is a plain SwiftUI view, so it was computed once when you tapped
    /// and then stood still. Tapping somebody walking to the field left the
    /// card saying *walking to the field* for as long as it was open — through
    /// the walk, the work, the walk home and the night — and the only way to
    /// see the truth was to close it and tap them again.
    ///
    /// So the card asks, on its own clock. See `liveActivity`, which is where
    /// the ticking happens; nothing else on the card needs it, because
    /// everything else on it changes when the *simulation* changes and that
    /// arrives through `@Observable` on its own.
    var activity: () -> String? = { nil }
    var bonds: [BondLine] = []
    /// Why their mood is what it is, from `MoodLedger`.
    var moodFactors: [MoodFactor] = []
    /// Whether the engine has given them a roof.
    var housed: Bool = true
    /// Why they are as warm as they are — the day, the roof, the coat, the
    /// fires. Nil when the card is shown without a world around it.
    var warmth: ComfortEngine.Reckoning?
    /// What the settlement has spare, and how to hand it over. Left empty the
    /// card simply does not offer a kit — a card that can *see* a colonist and
    /// not arm them is the thing this fixes.
    var store: [(instance: ItemInstance, definition: ItemDefinition)] = []
    var definitionOf: (ItemInstance) -> ItemDefinition? = { _ in nil }
    var onEquip: (UUID) -> Void = { _ in }
    var onUnequip: (EquipmentSlot) -> Void = { _ in }
    var onClose: () -> Void

    /// How far past the fold the card is opened.
    ///
    /// Everything used to be on screen at once — needs, six body parts, the
    /// mood ledger, bonds, craft and four disposition bars — which on a phone
    /// came to a card **taller than the phone**. It grew upward off the top of
    /// the screen and took its own close button with it, so tapping a colonist
    /// was a trap: you could not read the head of the card and you could not
    /// shut it.
    ///
    /// What a card owes you at a glance is who this is, how they are and what
    /// is wrong. The rest is a page you ask for.
    @State private var expanded = false

    private var cs: Bool { AppStrings.language == .cs }

    /// The most of the screen the opened card may take. Beyond this the detail
    /// scrolls inside the card rather than pushing the header off the top.
    private static let detailMaxHeight: CGFloat = 260

    /// The one line on this card that runs off the frame clock rather than off
    /// the simulation, and therefore the one that needs a clock of its own.
    ///
    /// A second is the right beat: the pose changes when a colonist arrives
    /// somewhere or picks up a load, which happens on the scale of seconds, and
    /// a line of text redrawn sixty times a second to say the same four words
    /// is sixty times the work for none of the benefit. Scoped to this row, so
    /// opening a card does not put the rest of it — the mood ledger, the
    /// equipment list — on a repeating render.
    @ViewBuilder private var liveActivity: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            if let now = activity() {
                HStack(spacing: 4) {
                    Image(systemName: "location.fill").font(.system(size: 8))
                    Text(now)
                }
                .font(.caption)
                .foregroundStyle(Theme.accent.opacity(0.9))
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            HStack(spacing: 10) {
                vital(icon: "heart.fill", label: "HP", value: pawn.health, tint: Theme.good)
                vital(icon: "face.smiling", label: cs ? "Nálada" : "Mood",
                      value: pawn.mood, tint: Theme.accent)
                if pawn.wealth > 0 {
                    vital(icon: "circle.hexagongrid.fill",
                          label: cs ? "Jmění" : "Wealth",
                          value: nil, text: "\(Int(pawn.wealth))", tint: Theme.textDim)
                }
            }
            needs
            // What is *wrong* is never behind a fold: a colonist with a torn
            // leg is the reason you tapped them.
            if !pawn.body.ailments.isEmpty || pawn.body.capacity < 0.99 { condition }
            // Above the fold, deliberately: what somebody is carrying is a
            // decision you make *about them*, on the card you opened to look
            // at them, and not a trip to a warehouse screen.
            EquipmentStrip(pawn: pawn, store: store,
                           onEquip: onEquip, onUnequip: onUnequip,
                           definitionOf: definitionOf)
            moreToggle
            if expanded { detail }
        }
        .padding(16)
        .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Theme.roleShade(pawn.assignedWork).opacity(0.35), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.4), radius: 18, y: 8)
    }

    /// The rest of the person, when you ask for it — and never taller than the
    /// space it was given.
    private var detail: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                bodyParts
                if !moodFactors.isEmpty { moodBreakdown }
                if !bonds.isEmpty { bondRows }
                skills
                genes
            }
            .padding(.bottom, 2)
        }
        .frame(maxHeight: Self.detailMaxHeight)
        .scrollBounceBehavior(.basedOnSize)
        .transition(.opacity)
    }

    private var moreToggle: some View {
        Button {
            withAnimation(.snappy(duration: 0.2)) { expanded.toggle() }
        } label: {
            HStack(spacing: 6) {
                Text(expanded ? (cs ? "Méně" : "Less") : (cs ? "Celá karta" : "Full card"))
                    .font(.caption.weight(.semibold))
                Image(systemName: expanded ? "chevron.up" : "chevron.down")
                    .font(.caption2.weight(.bold))
                Spacer()
            }
            .foregroundStyle(Theme.accent)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// The four needs, with the ones that are biting marked.
    private var needs: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionTitle(cs ? "Potřeby" : "Needs")
            NeedBar(label: cs ? "Hlad" : "Food", value: pawn.needs.hunger,
                    icon: "fork.knife", tint: Color(red: 0.85, green: 0.72, blue: 0.42))
            NeedBar(label: cs ? "Spánek" : "Rest", value: pawn.needs.rest,
                    icon: "moon.fill", tint: Color(red: 0.62, green: 0.70, blue: 0.88))
            NeedBar(label: cs ? "Teplo" : "Warmth", value: pawn.needs.warmth,
                    icon: "flame.fill", tint: Color(red: 0.88, green: 0.55, blue: 0.36))
            NeedBar(label: cs ? "Odpočinek" : "Leisure", value: pawn.needs.recreation,
                    icon: "leaf.fill", tint: Color(red: 0.60, green: 0.80, blue: 0.62))
            warmthReckoning
            if !housed {
                HStack(spacing: 5) {
                    Image(systemName: "house.slash").font(.caption2)
                    Text(cs ? "Nemá kde spát" : "Nowhere to sleep")
                        .font(.caption)
                }
                .foregroundStyle(Theme.danger)
            }
        }
    }

    /// Why the warmth bar reads what it reads.
    ///
    /// The bar on its own is a comfort with no explanation: a player could see
    /// a colonist at fourteen and had no way to learn whether the answer was a
    /// coat, a roof, a fire or moving the whole colony out of the tundra.
    /// `ComfortEngine` has always added up exactly these four terms and shown
    /// none of them.
    @ViewBuilder
    private var warmthReckoning: some View {
        if let warmth {
            let degrees = Int(warmth.outside.rounded())
            HStack(spacing: 5) {
                Image(systemName: "thermometer.medium").font(.caption2)
                Text(cs ? "Venku \(degrees) °C" : "\(degrees) °C outside")
                    .font(.caption.monospacedDigit())
                Spacer(minLength: 0)
                ForEach(gains(of: warmth), id: \.0) { label, amount in
                    Text("\(label) +\(Int(amount.rounded()))")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(Theme.textDim)
                }
            }
            .foregroundStyle(warmth.outside < ComfortEngine.comfortLow
                             ? Theme.frost : Theme.textDim)
        }
    }

    /// What is keeping the cold off them, biggest first — and only the terms
    /// that are actually worth something, so a summer card is not a row of
    /// zeroes.
    private func gains(of warmth: ComfortEngine.Reckoning) -> [(String, Double)] {
        [(cs ? "střecha" : "roof", warmth.roof),
         (cs ? "oděv" : "coat", warmth.clothes),
         (cs ? "ohně" : "fires", warmth.fires)]
            .filter { $0.1 >= 1 }
            .sorted { $0.1 > $1.1 }
    }

    /// What has happened to them, part by part.
    ///
    /// A number called health could tell you a colonist was at sixty and never
    /// whether that was a bad winter or a boar. This says which arm, whether
    /// anybody has seen to it, and what it is costing them — which is the whole
    /// How bad a thing is, in a word rather than a decimal.
    private func severityWord(_ ailment: Ailment) -> String {
        switch ailment.severity {
        case ..<0.2:  return cs ? "škrábnutí" : "a scratch"
        case ..<0.45: return cs ? "lehké" : "slight"
        case ..<0.7:  return cs ? "vážné" : "bad"
        default:      return cs ? "těžké" : "grave"
        }
    }

    /// reason to give a person a body.
    private var condition: some View {
        VStack(alignment: .leading, spacing: 5) {
            sectionTitle(cs ? "Zranění" : "Condition")
            ForEach(pawn.body.ailments.sorted { $0.severity > $1.severity }) { ailment in
                HStack(spacing: 6) {
                    Image(systemName: ailment.tended ? "bandage.fill" : "drop.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(ailment.tended ? Theme.good : Theme.danger)
                        .frame(width: 12)
                    // What it is *and* where — "Bodná rána — levá paže". This
                    // named only the part, so every injury in the game read as
                    // a body part with no story: a wolf's bite and a spear
                    // through the shoulder were both "Left arm".
                    Text(ailment.title.resolve(AppStrings.language))
                        .font(.caption)
                        .foregroundStyle(Theme.text)
                    Spacer(minLength: 6)
                    // How bad, then what is being done about it. A wound that
                    // bleeds fast is the one that kills somebody after the
                    // fighting stopped, and it should be the one that shouts.
                    Text(severityWord(ailment))
                        .font(.caption2)
                        .foregroundStyle(Theme.textDim)
                    Text(ailment.tended
                         ? (cs ? "ošetřeno" : "tended")
                         : (cs ? "krvácí" : "bleeding"))
                        .font(.caption2)
                        .foregroundStyle(ailment.tended ? Theme.textDim : Theme.danger)
                }
            }
            // What is left of them for a day's work.
            if pawn.body.capacity < 0.99 {
                HStack(spacing: 6) {
                    Image(systemName: "figure.walk").font(.system(size: 9))
                        .foregroundStyle(Theme.textDim).frame(width: 12)
                    Text(cs ? "Zvládne \(Int(pawn.body.capacity * 100)) % práce"
                            : "Good for \(Int(pawn.body.capacity * 100))% of a day")
                        .font(.caption2)
                        .foregroundStyle(Theme.textDim)
                }
            }
            if !pawn.body.canWalk {
                Text(cs ? "Nemůže chodit" : "Cannot walk")
                    .font(.caption).foregroundStyle(Theme.danger)
            }
        }
    }

    /// The body itself, part by part — six rows, always, so you can see at a
    /// glance which arm is the ruined one rather than only that something is.
    ///
    /// Animals have had this since they became pawns; this is the same page
    /// asked of a person, and the reason a wound is a *thing that happened*
    /// rather than a smaller number.
    private var bodyParts: some View {
        VStack(alignment: .leading, spacing: 3) {
            sectionTitle(cs ? "Tělo" : "Body")
            ForEach(BodyPartKind.allCases, id: \.self) { kind in
                let part = pawn.body.part(kind)
                let condition = part?.missing == true ? 0 : (part?.condition ?? 1)
                HStack(spacing: 6) {
                    Text(kind.displayName.resolve(AppStrings.language))
                        .font(.caption2)
                        .foregroundStyle(condition < 0.99 ? Theme.text : Theme.textDim)
                        .frame(width: 74, alignment: .leading)
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Theme.surfaceInset)
                            Capsule()
                                .fill(partTint(condition, missing: part?.missing == true))
                                .frame(width: geo.size.width * CGFloat(condition))
                        }
                    }
                    .frame(height: 4)
                    Text(part?.missing == true
                         ? (cs ? "pryč" : "gone")
                         : "\(Int(condition * 100))")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(condition < 0.99 ? Theme.danger : Theme.textDim)
                        .frame(width: 32, alignment: .trailing)
                }
            }
        }
    }

    private func partTint(_ condition: Double, missing: Bool) -> Color {
        if missing { return Theme.danger }
        if condition < 0.5 { return Theme.danger }
        if condition < 0.99 { return Theme.accent }
        return Theme.good.opacity(0.7)
    }

    /// What they are actually good at, and what they are on right now — the two
    /// facts about a worker the card never carried.
    private var skills: some View {
        VStack(alignment: .leading, spacing: 4) {
            sectionTitle(cs ? "Řemeslo" : "Craft")
            // The three they are best at. A full table of thirteen trades is a
            // spreadsheet; the top of it is a person.
            let best = pawn.skills.sorted { $0.value > $1.value }.prefix(3)
                .filter { $0.value > 0 }
            if best.isEmpty {
                Text(cs ? "Zatím se nic nenaučil." : "Nothing learned yet.")
                    .font(.caption).foregroundStyle(Theme.textDim)
            } else {
                ForEach(Array(best), id: \.key) { entry in
                    HStack(spacing: 6) {
                        Circle().fill(Theme.roleShade(entry.key)).frame(width: 6, height: 6)
                        Text(AppStrings.roleName(entry.key))
                            .font(.caption).foregroundStyle(Theme.text)
                        Spacer(minLength: 6)
                        Text("\(entry.value)")
                            .font(.caption.monospacedDigit().weight(.semibold))
                            .foregroundStyle(Theme.textDim)
                    }
                }
            }
            // Where they sleep, and what is in their hands — small facts, but
            // they are what makes a colonist somebody rather than a worker.
            HStack(spacing: 10) {
                Label(housed ? (cs ? "má postel" : "has a bed")
                             : (cs ? "spí venku" : "sleeps rough"),
                      systemImage: housed ? "bed.double.fill" : "house.slash")
                    .foregroundStyle(housed ? Theme.textDim : Theme.danger)
                if let load = pawn.carrying {
                    Label("\(load.amount)", systemImage: "shippingbox.fill")
                        .foregroundStyle(Theme.accent)
                }
                if !pawn.equipment.isEmpty {
                    Label("\(pawn.equipment.count)", systemImage: "shield.lefthalf.filled")
                        .foregroundStyle(Theme.textDim)
                }
            }
            .font(.caption2)
        }
    }

    /// Why they feel the way they do — the thing a mood number can never say.
    private var moodBreakdown: some View {
        VStack(alignment: .leading, spacing: 4) {
            sectionTitle(cs ? "Proč" : "Why")
            ForEach(moodFactors.prefix(5)) { factor in
                HStack(spacing: 6) {
                    Text(factor.label.resolve(AppStrings.language))
                        .font(.caption)
                        .foregroundStyle(Theme.text)
                    Spacer(minLength: 8)
                    Text(factor.amount >= 0
                         ? "+\(Int(factor.amount.rounded()))"
                         : "\(Int(factor.amount.rounded()))")
                        .font(.caption.monospacedDigit().weight(.semibold))
                        .foregroundStyle(factor.amount >= 0 ? Theme.good : Theme.danger)
                }
            }
        }
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.caption2.weight(.bold)).tracking(1.2)
            .foregroundStyle(Theme.textDim)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(pawn.name)
                    .font(.system(.title3, design: .serif).weight(.semibold))
                    .foregroundStyle(Theme.text)
                HStack(spacing: 6) {
                    Circle().fill(Theme.roleShade(pawn.assignedWork)).frame(width: 7, height: 7)
                    Text(AppStrings.roleName(pawn.assignedWork))
                        .foregroundStyle(Theme.textDim)
                    Text("· \(pawn.ageYears(ticksPerYear: ticksPerYear)) \(AppStrings.language == .cs ? "let" : "yrs")")
                        .foregroundStyle(Theme.textDim)
                }
                .font(.caption)
                // What they're visibly doing on the canvas this moment.
                liveActivity
            }
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(Theme.textDim)
            }
            .accessibilityLabel("Close")
        }
    }

    /// Who this colonist's life is entangled with.
    private var bondRows: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(AppStrings.language == .cs ? "Vztahy" : "Bonds")
                .font(.caption2.weight(.bold)).tracking(1.2)
                .foregroundStyle(Theme.textDim)
            ForEach(bonds) { bond in
                HStack(spacing: 6) {
                    Image(systemName: bondIcon(bond.kind))
                        .font(.caption2)
                        .foregroundStyle(bondTint(bond.kind))
                        .frame(width: 14)
                    Text(bond.name)
                        .font(.caption)
                        .foregroundStyle(Theme.text)
                    Text(bondLabel(bond.kind))
                        .font(.caption2)
                        .foregroundStyle(Theme.textDim)
                }
            }
        }
    }

    private func bondIcon(_ kind: RelationKind) -> String {
        switch kind {
        case .partner: return "heart.fill"
        case .friend: return "person.2.fill"
        case .rival: return "bolt.fill"
        }
    }

    private func bondTint(_ kind: RelationKind) -> Color {
        switch kind {
        case .partner: return Theme.danger.opacity(0.85)
        case .friend: return Theme.good
        case .rival: return Theme.accent
        }
    }

    private func bondLabel(_ kind: RelationKind) -> String {
        let cs = AppStrings.language == .cs
        switch kind {
        case .partner: return cs ? "manžel(ka)" : "spouse"
        case .friend: return cs ? "přítel" : "friend"
        case .rival: return cs ? "sok" : "rival"
        }
    }

    private func vital(icon: String, label: String, value: Double?, text: String? = nil, tint: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon).font(.caption).foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 0) {
                Text(label).font(.caption2).foregroundStyle(Theme.textDim)
                Text(text ?? "\(Int((value ?? 0).rounded()))")
                    .font(.subheadline.monospacedDigit().weight(.semibold))
                    .foregroundStyle(Theme.text)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(Theme.surfaceInset, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var genes: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(AppStrings.language == .cs ? "Vlohy" : "Disposition")
                .font(.caption2.weight(.bold)).tracking(1.2)
                .foregroundStyle(Theme.textDim)
            GeneBar(label: AppStrings.language == .cs ? "Píle" : "Industry", value: pawn.genes.industry)
            GeneBar(label: AppStrings.language == .cs ? "Plodnost" : "Fertility", value: pawn.genes.fertility)
            GeneBar(label: AppStrings.language == .cs ? "Družnost" : "Sociability", value: pawn.genes.sociability)
            GeneBar(label: AppStrings.language == .cs ? "Odvaha" : "Courage", value: pawn.genes.courage)
        }
    }
}

/// A need, 0…100, with the colour warning you when it is running out.
private struct NeedBar: View {
    let label: String
    let value: Double
    let icon: String
    let tint: Color

    /// A need under this is doing them harm, and is drawn as such — the point
    /// of a bar is that you can see trouble without reading the number.
    private var urgent: Bool { value < 30 }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 9))
                .foregroundStyle(urgent ? Theme.danger : tint)
                .frame(width: 12)
            Text(label)
                .font(.caption2)
                .foregroundStyle(Theme.textDim)
                .frame(width: 62, alignment: .leading)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.surfaceInset)
                    Capsule()
                        .fill(urgent ? Theme.danger : tint)
                        .frame(width: geo.size.width * CGFloat(min(max(value / 100, 0), 1)))
                }
            }
            .frame(height: 5)
            Text("\(Int(value.rounded()))")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(urgent ? Theme.danger : Theme.textDim)
                .frame(width: 26, alignment: .trailing)
        }
    }
}

/// A slim 0…1 disposition bar.
private struct GeneBar: View {
    let label: String
    let value: Double

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(Theme.textDim)
                .frame(width: 78, alignment: .leading)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.surfaceInset)
                    Capsule().fill(Theme.bone.opacity(0.7))
                        .frame(width: geo.size.width * CGFloat(min(max(value, 0), 1)))
                }
            }
            .frame(height: 4)
            Text(String(format: "%.2f", value))
                .font(.caption2.monospacedDigit())
                .foregroundStyle(Theme.textDim)
                .frame(width: 34, alignment: .trailing)
        }
    }
}
