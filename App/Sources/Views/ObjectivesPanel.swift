import SwiftUI
import EndlessFrontierCore

/// The living to-do list — what to pursue next. Keeps the open-ended game
/// feeling directed.
struct ObjectivesPanel: View {
    @Bindable var game: GameViewModel
    /// Called when an objective wants to take the player somewhere, so whoever
    /// is presenting this can get out of the way first. Where they go is
    /// `GameViewModel.follow` — a tab was never the whole answer, and two
    /// places deciding it is how they came to disagree.
    var onLeave: () -> Void = {}

    var body: some View {
        let objectives = game.objectives
        if objectives.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: "Objectives")
                ForEach(objectives) { objective in
                    row(objective)
                }
            }
            .frontierCard()
        }
    }

    /// Objectives told you what to do and then left you to find it — the one
    /// screen that says "pick a research project" couldn't take you to the
    /// research. Every row is now the way there.
    ///
    /// And all the way there: `follow` opens the build picker for a housing
    /// objective and selects the colonist a `tend_` objective is about, rather
    /// than dropping the player on the right tab with everything shut.
    private func row(_ objective: Objective) -> some View {
        Button {
            onLeave()
            game.follow(objective)
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: icon(objective.category))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(color(objective.category))
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 3) {
                    Text(objective.title.resolve(AppStrings.language))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.text)
                    Text(objective.detail.resolve(AppStrings.language))
                        .font(.caption).foregroundStyle(Theme.textDim)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                    if let progress = objective.progress {
                        ProgressView(value: min(max(progress, 0), 1))
                            .tint(color(objective.category))
                            .padding(.top, 2)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Theme.textDim)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 10)
            .background(Theme.surfaceInset, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityHint(AppStrings.objectiveHint)
    }

    private func icon(_ category: Objective.Category) -> String {
        switch category {
        case .colonists: return "cross.case.fill"
        case .era: return "flag.checkered"
        case .research: return "lightbulb.fill"
        case .sites: return "flashlight.on.fill"
        case .explore: return "map.fill"
        case .expand: return "house.lodge.fill"
        }
    }

    private func color(_ category: Objective.Category) -> Color {
        switch category {
        case .colonists: return Theme.danger
        case .era: return Theme.accent
        case .research: return Theme.good
        case .sites: return Theme.accent
        case .explore: return Theme.good
        case .expand: return Theme.accent
        }
    }
}
