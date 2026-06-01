import SwiftUI
import EndlessFrontierCore

/// Research selection and construction — the player's two main levers.
struct TechBuildPanel: View {
    @Bindable var game: GameViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            researchSection
            buildSection
        }
    }

    private var researchSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Research")

            if let active = game.world.activeResearch, let tech = game.registry.tech(active) {
                let progress = min(1, game.world.researchProgress / max(1, tech.knowledgeCost))
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Image(systemName: "hourglass")
                        Text(tech.name).font(.subheadline.weight(.semibold))
                        Spacer()
                        Text("\(Int(game.world.researchProgress))/\(Int(tech.knowledgeCost))")
                            .font(.caption.monospacedDigit()).foregroundStyle(Theme.textDim)
                    }
                    StatBar(label: "Progress", value: progress * 100, tint: Theme.accent)
                }
            } else {
                Text("No active research").font(.subheadline).foregroundStyle(Theme.textDim)
            }

            ForEach(game.availableTechs) { tech in
                Button {
                    game.setResearch(tech.id)
                } label: {
                    rowLabel(
                        title: tech.name,
                        subtitle: "\(Int(tech.knowledgeCost)) knowledge",
                        systemImage: "lightbulb.fill",
                        selected: game.world.activeResearch == tech.id
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .frontierCard()
    }

    private var buildSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Build")
            if game.buildableBuildings.isEmpty {
                Text("Research unlocks new buildings.")
                    .font(.subheadline).foregroundStyle(Theme.textDim)
            }
            ForEach(game.buildableBuildings) { building in
                Button {
                    game.build(building.id)
                } label: {
                    rowLabel(
                        title: building.name,
                        subtitle: costSummary(building.cost),
                        systemImage: "hammer.fill",
                        selected: false
                    )
                }
                .buttonStyle(.plain)
                .disabled(!canAfford(building.cost))
                .opacity(canAfford(building.cost) ? 1 : 0.45)
            }
        }
        .frontierCard()
    }

    private func rowLabel(title: String, subtitle: String, systemImage: String, selected: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .foregroundStyle(selected ? Theme.accent : Theme.textDim)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.subheadline.weight(.medium)).foregroundStyle(Theme.text)
                Text(subtitle).font(.caption).foregroundStyle(Theme.textDim)
            }
            Spacer()
            if selected {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.accent)
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(Theme.surfaceInset, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func costSummary(_ cost: Resources) -> String {
        let parts = ResourceType.allCases
            .filter { cost[$0] > 0 }
            .map { "\(Int(cost[$0])) \($0.displayName.lowercased())" }
        return parts.isEmpty ? "Free" : parts.joined(separator: ", ")
    }

    private func canAfford(_ cost: Resources) -> Bool {
        guard let capital = game.capital else { return false }
        return ResourceType.allCases.allSatisfy { capital.storage[$0] >= cost[$0] }
    }
}
