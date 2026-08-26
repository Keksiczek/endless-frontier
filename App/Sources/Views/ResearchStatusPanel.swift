import SwiftUI
import EndlessFrontierCore

/// What the colony is studying, and the way to the tree.
///
/// This was `TechBuildPanel` — research **and** a second build list, under a
/// heading of "Research & building" that was the only place in the drawer you
/// could actually raise anything. Both halves were duplicates: the build list
/// of the canvas picker (and a worse one — see `GameViewModel.buildRequest`),
/// the research list of the Science tab, which shows the same techs grouped by
/// era with their prerequisites and their tally.
///
/// What is left is the half that is not a duplicate: **the state of the
/// current study**, which is a thing you want at a glance beside the colony's
/// other numbers, and one door to the tree for choosing the next one.
struct ResearchStatusPanel: View {
    @Bindable var game: GameViewModel
    /// Called before the player is sent to the Science tab.
    var onLeave: () -> Void = {}

    private var cs: Bool { AppStrings.language == .cs }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let active = game.world.activeResearch, let tech = game.registry.tech(active) {
                let progress = min(1, game.world.researchProgress / max(1, tech.knowledgeCost))
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Image(systemName: "hourglass")
                            .font(.caption)
                            .foregroundStyle(Theme.accent)
                        Text(tech.name.resolve(AppStrings.language))
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Text("\(Int(game.world.researchProgress))/\(Int(tech.knowledgeCost))")
                            .font(.caption.monospacedDigit()).foregroundStyle(Theme.textDim)
                    }
                    StatBar(label: cs ? "Postup" : "Progress",
                            value: progress * 100, tint: Theme.accent)
                }
            } else {
                // Nothing being studied is not a neutral state — it is knowledge
                // income going nowhere, every tick.
                Label(AppStrings.noActiveResearch, systemImage: "exclamationmark.triangle.fill")
                    .font(.subheadline)
                    .foregroundStyle(Theme.danger)
            }
            door
        }
        .frontierCard()
    }

    private var door: some View {
        Button {
            onLeave()
            game.tab = .science
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "lightbulb.fill").font(.subheadline)
                Text(game.world.activeResearch == nil
                     ? (cs ? "Vybrat, co zkoumat" : "Choose what to study")
                     : (cs ? "Otevřít strom vědy" : "Open the tree"))
                    .font(.subheadline.weight(.semibold))
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Theme.textDim)
            }
            .foregroundStyle(Theme.accent)
            .padding(.vertical, 11).padding(.horizontal, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.accent.opacity(0.14),
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
