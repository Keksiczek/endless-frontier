import SwiftUI
import EndlessFrontierCore

/// The colonists of the capital — each with a mood and an assignable job.
/// This is the RimWorld-style micro layer the player reads and steers.
struct ColonistsPanel: View {
    @Bindable var game: GameViewModel

    var body: some View {
        if game.capitalPawns.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "Colonists")
                ForEach(game.capitalPawns) { pawn in
                    pawnRow(pawn)
                }
            }
            .frontierCard()
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
                        Text("Mood \(Int(pawn.mood.rounded()))")
                        Text("·").foregroundStyle(Theme.textDim.opacity(0.5))
                        Label("\(Int(pawn.health.rounded()))", systemImage: "heart.fill")
                            .foregroundStyle(pawn.health < 40 ? Theme.danger : Theme.textDim)
                    }
                    .font(.caption).foregroundStyle(Theme.textDim)
                }
                Spacer()
                workMenu(pawn)
            }
            moodBar(pawn.mood)
            if let equipment = pawn.equipment, let def = game.itemDefinition(equipment) {
                Button {
                    game.unequip(pawn.id)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "shield.lefthalf.filled")
                        Text(def.name).font(.caption2.weight(.medium))
                        Spacer()
                        Text("Unequip").font(.caption2)
                    }
                    .foregroundStyle(def.rarity.color)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 10).padding(.horizontal, 12)
        .background(Theme.surfaceInset, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
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
        case .idle: return "moon.zzz.fill"
        }
    }

    private func traitLabel(_ trait: PawnTrait) -> String {
        trait.rawValue.replacingOccurrences(of: "_", with: " ").capitalized
    }
}
