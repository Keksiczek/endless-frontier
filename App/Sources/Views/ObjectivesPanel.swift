import SwiftUI
import EndlessFrontierCore

/// The living to-do list — what to pursue next. Keeps the open-ended game
/// feeling directed.
struct ObjectivesPanel: View {
    @Bindable var game: GameViewModel

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

    private func row(_ objective: Objective) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon(objective.category))
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(color(objective.category))
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 3) {
                Text(objective.title).font(.subheadline.weight(.semibold))
                Text(objective.detail).font(.caption).foregroundStyle(Theme.textDim)
                if let progress = objective.progress {
                    ProgressView(value: min(max(progress, 0), 1))
                        .tint(color(objective.category))
                        .padding(.top, 2)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(Theme.surfaceInset, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
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
