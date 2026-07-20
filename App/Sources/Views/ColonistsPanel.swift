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
                needsAttention
                ForEach(game.workforce, id: \.work) { group in
                    tradeSection(group)
                }
            }
            .frontierCard()
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
                        Text("Mood \(Int(pawn.mood.rounded()))")
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
            ForEach(EquipmentSlot.allCases, id: \.self) { slot in
                if let instance = pawn.equipment[slot], let def = game.itemDefinition(instance) {
                    Button {
                        game.unequip(pawn.id, slot: slot)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: slotIcon(slot))
                            Text(def.name).font(.caption2.weight(.medium))
                            Spacer()
                            Text("Unequip").font(.caption2)
                        }
                        .foregroundStyle(def.rarity.color)
                    }
                    .buttonStyle(.plain)
                }
            }
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
        case .priest: return "sparkles"
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
