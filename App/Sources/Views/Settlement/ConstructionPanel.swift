import SwiftUI
import EndlessFrontierCore

/// Building, in the drawer: the way in, and what is already going up.
///
/// The section used to be called Construction and could not start one. It
/// showed progress bars for work already under way and nothing else, while
/// **the button that actually raises a building sat four sections further
/// down, inside "Research & building"** — a heading nobody opens looking for a
/// granary. Worse, that list was a second build flow: it sited the building
/// itself, and it was missing every early-settlement building besides. Keks:
/// *"je těžké tam něco vydolovat i když je to docela důležité."*
///
/// So the door comes first, and it leads to the canvas — where you pick the
/// ground, with the footprint drawn on the colony you are looking at.
struct ConstructionPanel: View {
    @Bindable var game: GameViewModel
    /// Called before the player is sent to the canvas, so whoever is presenting
    /// this drawer can get out of the way of it.
    var onLeave: () -> Void = {}

    private var cs: Bool { AppStrings.language == .cs }

    private var projects: [ConstructionProject] {
        game.selectedSettlement?.constructions ?? []
    }

    private var builderCount: Int {
        game.selectedSettlement?.pawns.filter { $0.assignedWork == .building }.count ?? 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            startButton
            if !projects.isEmpty {
                HStack {
                    SectionHeader(title: cs ? "Ve výstavbě" : "Under construction")
                    Spacer()
                    Label("\(builderCount)", systemImage: "hammer.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(builderCount > 0 ? Theme.textDim : Theme.danger)
                        .accessibilityLabel(cs ? "\(builderCount) stavitelů" : "\(builderCount) builders")
                }
                // A row of bars that never move is worse than no bars: say why
                // before the player waits a year on it.
                if builderCount == 0 {
                    Label(cs ? "Nikdo nestaví — nic nepokročí."
                             : "Nobody is building — none of this moves.",
                          systemImage: "exclamationmark.triangle.fill")
                        .font(.caption2)
                        .foregroundStyle(Theme.danger)
                }
                ForEach(projects) { project in
                    row(project)
                }
            }
        }
        .frontierCard()
    }

    private var startButton: some View {
        Button {
            onLeave()
            game.askToBuild()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "hammer.fill")
                    .font(.subheadline)
                VStack(alignment: .leading, spacing: 1) {
                    Text(cs ? "Postavit něco" : "Build something")
                        .font(.subheadline.weight(.semibold))
                    Text(cs ? "Vybereš místo přímo v osadě"
                            : "You choose the ground, out in the settlement")
                        .font(.caption2)
                        .foregroundStyle(Theme.textDim)
                }
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

    private func row(_ project: ConstructionProject) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(game.buildingName(project.definitionID))
                    .font(.subheadline.weight(.medium))
                Spacer()
                Text("\(Int(project.fraction * 100)) %")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(Theme.textDim)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.surfaceInset)
                    Capsule().fill(Theme.accent.opacity(0.85))
                        .frame(width: geo.size.width * CGFloat(project.fraction))
                }
            }
            .frame(height: 5)
        }
        .padding(.vertical, 2)
    }
}
