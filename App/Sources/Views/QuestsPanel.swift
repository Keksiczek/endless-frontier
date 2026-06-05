import SwiftUI
import EndlessFrontierCore

/// Active quest chains — multi-stage goals the player is pursuing, distinct
/// from the live Objectives hints.
struct QuestsPanel: View {
    @Bindable var game: GameViewModel

    var body: some View {
        let quests = game.activeQuests
        if quests.isEmpty && game.completedQuestCount == 0 {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    SectionHeader(title: "Quests")
                    Spacer()
                    if game.completedQuestCount > 0 {
                        Text("\(game.completedQuestCount) completed")
                            .font(.caption2.weight(.medium)).foregroundStyle(Theme.textDim)
                    }
                }
                if quests.isEmpty {
                    Text("New quests await as your colony grows.")
                        .font(.caption).foregroundStyle(Theme.textDim)
                }
                ForEach(quests, id: \.definition.id) { quest in
                    row(quest.definition, quest.progress)
                }
            }
            .frontierCard()
        }
    }

    private func row(_ definition: QuestDefinition, _ progress: QuestProgress) -> some View {
        let stageText = progress.stage < definition.stages.count
            ? definition.stages[progress.stage].description : "Complete"
        return HStack(alignment: .top, spacing: 12) {
            Image(systemName: "scroll.fill")
                .foregroundStyle(Theme.accent).frame(width: 24)
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(definition.name).font(.subheadline.weight(.semibold))
                    Spacer()
                    Text("Stage \(min(progress.stage + 1, definition.stages.count))/\(definition.stages.count)")
                        .font(.caption2.monospacedDigit()).foregroundStyle(Theme.textDim)
                }
                Text(stageText).font(.caption).foregroundStyle(Theme.textDim)
            }
        }
        .padding(.vertical, 8).padding(.horizontal, 10)
        .background(Theme.surfaceInset, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
