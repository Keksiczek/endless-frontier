import SwiftUI
import EndlessFrontierCore

/// The colonists of the capital — each with a mood and an assignable job.
/// This is the RimWorld-style micro layer the player reads and steers.
///
/// It used to be one flat list of every soul in the colony, which is fine at
/// eighteen and unreadable at a hundred and twenty: to find the one person who
/// needs you, you scrolled past everyone who didn't. The colony is a *workforce*
/// long before it's a cast, so it reads as trades — how many farm, how many
/// hunt — and opens only where you want to look.
struct ColonistsPanel: View {
    @Bindable var game: GameViewModel
    @State private var expanded: Set<WorkKind> = []
    /// Typing a name, because at a hundred and twenty people the way you find
    /// somebody is by knowing who you are looking for. Everything below reads
    /// this: with a search running the trades collapse into one flat answer,
    /// because grouping is for browsing and this is not browsing.
    @State private var query = ""
    @State private var lens: Lens = .everyone

    /// What to cut the colony down to. Not a filter menu for its own sake —
    /// each of these is a question the player actually turns up with.
    enum Lens: String, CaseIterable, Identifiable {
        case everyone, hurt, unhappy, unarmed, idle
        var id: String { rawValue }

        var label: String {
            let cs = AppStrings.language == .cs
            switch self {
            case .everyone: return cs ? "Všichni" : "Everyone"
            case .hurt:     return cs ? "Zranění" : "Hurt"
            case .unhappy:  return cs ? "Nespokojení" : "Unhappy"
            case .unarmed:  return cs ? "Bez zbraně" : "Unarmed"
            case .idle:     return cs ? "Nečinní" : "Idle"
            }
        }

        var symbol: String {
            switch self {
            case .everyone: return "person.3.fill"
            case .hurt:     return "cross.case.fill"
            case .unhappy:  return "cloud.rain.fill"
            case .unarmed:  return "figure.stand"
            case .idle:     return "zzz"
            }
        }
    }

    var body: some View {
        if game.viewedPawns.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    SectionHeader(title: AppStrings.colonists)
                    Spacer()
                    Text("\(game.viewedPawns.count)")
                        .font(.caption.monospacedDigit().weight(.semibold))
                        .foregroundStyle(Theme.textDim)
                }
                finder
                if isSearching {
                    matches
                } else {
                    needsAttention
                    ForEach(game.workforce, id: \.work) { group in
                        tradeSection(group)
                    }
                }
            }
            .frontierCard()
        }
    }

    /// Whether the list is answering a question rather than showing the town.
    private var isSearching: Bool {
        !query.trimmingCharacters(in: .whitespaces).isEmpty || lens != .everyone
    }

    /// A name to type and five questions to ask. This is the whole of "I cannot
    /// find a colonist": the panel grouped by trade, which is right for reading
    /// the shape of a workforce and useless for finding the one person who is
    /// bleeding.
    private var finder: some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.caption).foregroundStyle(Theme.textDim)
                TextField(AppStrings.language == .cs ? "Hledat jméno" : "Find a name",
                          text: $query)
                    .font(.caption)
                    .textFieldStyle(.plain)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                if !query.isEmpty {
                    Button { query = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.caption).foregroundStyle(Theme.textDim)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(Theme.surfaceInset, in: Capsule())

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(Lens.allCases) { option in
                        Button {
                            withAnimation(.snappy(duration: 0.15)) {
                                lens = lens == option ? .everyone : option
                            }
                        } label: {
                            Label(option.label, systemImage: option.symbol)
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 9).padding(.vertical, 6)
                                .background(lens == option ? Theme.accent.opacity(0.2)
                                                           : Theme.surfaceInset,
                                            in: Capsule())
                                .foregroundStyle(lens == option ? Theme.accent : Theme.textDim)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 1)
            }
        }
    }

    /// Everyone the question turns up, worst off first — the order you want
    /// when the question was "who needs me".
    private var found: [Pawn] {
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        return game.viewedPawns
            .filter { pawn in
                guard needle.isEmpty || pawn.name.lowercased().contains(needle) else { return false }
                switch lens {
                case .everyone: return true
                case .hurt:     return pawn.health < 100 || pawn.isBroken
                case .unhappy:  return pawn.mood < 45
                case .unarmed:  return pawn.equipment[.weapon] == nil
                case .idle:     return pawn.assignedWork == .idle
                        && pawn.isAdult(ticksPerYear: game.ticksPerYear)
                }
            }
            .sorted {
                $0.health != $1.health ? $0.health < $1.health
                                       : $0.name.localizedCompare($1.name) == .orderedAscending
            }
    }

    @ViewBuilder
    private var matches: some View {
        let people = found
        if people.isEmpty {
            Text(AppStrings.language == .cs ? "Nikdo takový tu není."
                                            : "Nobody here answers to that.")
                .font(.caption).foregroundStyle(Theme.textDim)
                .padding(.vertical, 6)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text("\(people.count)")
                    .font(.caption2.monospacedDigit().weight(.semibold))
                    .foregroundStyle(Theme.textDim)
                // Capped: a search that matches everybody should not render the
                // whole town into one scroll view.
                ForEach(people.prefix(30)) { pawn in pawnRow(pawn) }
                if people.count > 30 {
                    Text(AppStrings.language == .cs
                         ? "…a dalších \(people.count - 30). Zkus přesnější jméno."
                         : "…and \(people.count - 30) more. Try a narrower name.")
                        .font(.caption2).foregroundStyle(Theme.textDim)
                }
            }
        }
    }

    /// The people the colony actually needs a decision about, lifted out of the
    /// crowd: the hurt, the wretched, and any adult the labour engine somehow
    /// left standing about.
    @ViewBuilder
    private var needsAttention: some View {
        let urgent = game.colonistsNeedingAttention
        if !urgent.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Label(AppStrings.needsYou, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Theme.danger)
                ForEach(urgent) { pawn in pawnRow(pawn) }
            }
            .padding(.bottom, 4)
        }
    }

    /// One trade: its headcount, and its people when you ask for them.
    private func tradeSection(_ group: GameViewModel.TradeGroup) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.snappy) {
                    if expanded.contains(group.work) { expanded.remove(group.work) }
                    else { expanded.insert(group.work) }
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: workIcon(group.work))
                        .foregroundStyle(Theme.roleShade(group.work))
                        .frame(width: 22)
                    Text(workLabel(group.work))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.text)
                    Spacer()
                    Text("\(group.pawns.count)")
                        .font(.subheadline.monospacedDigit().weight(.semibold))
                        .foregroundStyle(Theme.textDim)
                    Image(systemName: expanded.contains(group.work) ? "chevron.down" : "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Theme.textDim)
                }
                .padding(.vertical, 8).padding(.horizontal, 10)
                .background(Theme.surfaceInset, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(workLabel(group.work)), \(group.pawns.count)")

            if expanded.contains(group.work) {
                ForEach(group.pawns) { pawn in pawnRow(pawn) }
            }
        }
    }

    private func pawnRow(_ pawn: Pawn) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Image(systemName: "person.fill")
                    .foregroundStyle(moodColor(pawn.mood))
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text(pawn.name).font(.subheadline.weight(.semibold))
                        if pawn.trait != .none {
                            Text(traitLabel(pawn.trait))
                                .font(.caption2.weight(.medium))
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Theme.surface, in: Capsule())
                                .foregroundStyle(Theme.textDim)
                        }
                    }
                    HStack(spacing: 8) {
                        Text("\(age(pawn)) \(AppStrings.years)")
                        Text("·").foregroundStyle(Theme.textDim.opacity(0.5))
                        Text("\(AppStrings.mood) \(Int(pawn.mood.rounded()))")
                        Text("·").foregroundStyle(Theme.textDim.opacity(0.5))
                        Label("\(Int(pawn.health.rounded()))", systemImage: "heart.fill")
                            .foregroundStyle(pawn.health < 40 ? Theme.danger : Theme.textDim)
                    }
                    .font(.caption).foregroundStyle(Theme.textDim)
                }
                Spacer()
                // A child reads as "Idle" with a work menu beside it, exactly
                // like an adult the labour engine has failed to employ — which
                // is why a colony full of children looks like broken automation.
                // They're not idle; they're seven.
                if isChild(pawn) {
                    Label(AppStrings.child, systemImage: "figure.child")
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(Theme.surface, in: Capsule())
                        .foregroundStyle(Theme.textDim)
                } else {
                    workMenu(pawn)
                }
            }
            moodBar(pawn.mood)
            // Three slots you can fill from here. It used to be three lines
            // that could only ever take something *off*: to put something on
            // you went to the Items panel, found the sword, and picked this
            // person out of a menu of everyone in the town.
            EquipmentStrip(
                pawn: pawn,
                store: game.equippableStore,
                onEquip: { game.equip($0, toPawn: pawn.id) },
                onUnequip: { game.unequip(pawn.id, slot: $0) },
                compact: true,
                definitionOf: { game.itemDefinition($0) })
        }
        .padding(.vertical, 10).padding(.horizontal, 12)
        .background(Theme.surfaceInset, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func age(_ pawn: Pawn) -> Int {
        pawn.ageYears(ticksPerYear: game.ticksPerYear)
    }

    /// Too young to be put to work — `LaborEngine` only ever employs adults.
    private func isChild(_ pawn: Pawn) -> Bool {
        !pawn.isAdult(ticksPerYear: game.ticksPerYear)
    }

    private func workMenu(_ pawn: Pawn) -> some View {
        Menu {
            ForEach(WorkKind.allCases, id: \.self) { work in
                Button {
                    game.assignWork(pawnID: pawn.id, to: work)
                } label: {
                    Label(workLabel(work), systemImage: pawn.assignedWork == work ? "checkmark" : workIcon(work))
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: workIcon(pawn.assignedWork))
                Text(workLabel(pawn.assignedWork)).font(.caption.weight(.medium))
                Image(systemName: "chevron.up.chevron.down").font(.caption2)
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(Theme.surface, in: Capsule())
            .foregroundStyle(Theme.accent)
        }
    }

    private func moodBar(_ mood: Double) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.surface)
                Capsule().fill(moodColor(mood))
                    .frame(width: geo.size.width * CGFloat(min(max(mood, 0), 100) / 100))
            }
        }
        .frame(height: 5)
    }

    private func moodColor(_ mood: Double) -> Color {
        switch mood {
        case ..<35: return Theme.danger
        case ..<65: return Theme.accent
        default: return Theme.good
        }
    }

    private func workLabel(_ work: WorkKind) -> String { work.rawValue.capitalized }

    private func workIcon(_ work: WorkKind) -> String {
        switch work {
        case .farming: return "leaf.fill"
        case .logging: return "tree.fill"
        case .mining: return "mountain.2.fill"
        case .research: return "book.fill"
        case .trade: return "bag.fill"
        case .foraging: return "camera.macro"
        case .hunting: return "hare.fill"
        case .healing: return "cross.case.fill"
        case .building: return "hammer.fill"
        case .scouting: return "binoculars.fill"
        case .garrison: return "shield.lefthalf.filled"
        case .priest: return "sparkles"
        case .crafting: return "hammer.circle.fill"
        case .cooking: return "flame.fill"
        case .idle: return "moon.zzz.fill"
        }
    }

    private func traitLabel(_ trait: PawnTrait) -> String {
        trait.rawValue.replacingOccurrences(of: "_", with: " ").capitalized
    }

    private func slotIcon(_ slot: EquipmentSlot) -> String {
        switch slot {
        case .weapon: return "hammer.fill"
        case .armor: return "shield.lefthalf.filled"
        case .trinket: return "sparkles"
        }
    }
}
