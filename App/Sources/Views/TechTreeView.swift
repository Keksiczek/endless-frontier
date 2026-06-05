import SwiftUI
import EndlessFrontierCore

/// The tech tree as a readable, era-grouped plan: each node shows its status,
/// cost and prerequisites, and available techs can be selected for research.
struct TechTreeView: View {
    @Bindable var game: GameViewModel

    var body: some View {
        ZStack {
            Theme.surface.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    ForEach(game.techsByEra, id: \.era) { group in
                        VStack(alignment: .leading, spacing: 10) {
                            SectionHeader(title: eraTitle(group.era))
                            ForEach(group.techs) { tech in
                                node(tech)
                            }
                        }
                    }
                }
                .padding(20)
            }
        }
        .foregroundStyle(Theme.text)
    }

    private func node(_ tech: TechDefinition) -> some View {
        let status = game.techStatus(tech)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Image(systemName: icon(status)).foregroundStyle(color(status)).frame(width: 22)
                VStack(alignment: .leading, spacing: 1) {
                    Text(tech.name).font(.subheadline.weight(.semibold))
                    Text("\(Int(tech.knowledgeCost)) knowledge").font(.caption).foregroundStyle(Theme.textDim)
                }
                Spacer()
                trailing(tech, status)
            }
            if !tech.requires.isEmpty {
                Text("Needs: " + tech.requires.map(game.techName).joined(separator: ", "))
                    .font(.caption2).foregroundStyle(Theme.textDim)
            }
            if let progress = game.researchProgressFraction(tech) {
                ProgressView(value: progress).tint(Theme.accent)
            }
        }
        .padding(.vertical, 10).padding(.horizontal, 12)
        .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(color(status).opacity(0.3), lineWidth: 1))
    }

    @ViewBuilder
    private func trailing(_ tech: TechDefinition, _ status: GameViewModel.TechStatus) -> some View {
        switch status {
        case .researched: badge("Done", Theme.good)
        case .active: badge("Researching", Theme.accent)
        case .available:
            Button("Research") { game.setResearch(tech.id) }
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(Theme.accent.opacity(0.18), in: Capsule())
                .foregroundStyle(Theme.accent)
                .buttonStyle(.plain)
        case .locked: badge("Locked", Theme.textDim)
        }
    }

    private func badge(_ text: String, _ tint: Color) -> some View {
        Text(text).font(.caption2.weight(.bold))
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(tint.opacity(0.16), in: Capsule()).foregroundStyle(tint)
    }

    private func icon(_ status: GameViewModel.TechStatus) -> String {
        switch status {
        case .researched: return "checkmark.seal.fill"
        case .active: return "hourglass"
        case .available: return "lightbulb.fill"
        case .locked: return "lock.fill"
        }
    }

    private func color(_ status: GameViewModel.TechStatus) -> Color {
        switch status {
        case .researched: return Theme.good
        case .active: return Theme.accent
        case .available: return Theme.accent
        case .locked: return Theme.textDim
        }
    }

    private func eraTitle(_ era: Era) -> String {
        era.rawValue.split(separator: "_").map { $0.capitalized }.joined(separator: " ")
    }
}
