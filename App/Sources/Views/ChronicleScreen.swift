import SwiftUI
import EndlessFrontierCore

/// The world's chronicle: the events that have shaped this settlement, newest
/// first, stamped with the in-game year. Analytics and gene-drift insights join
/// it in a later phase; for now it's the running history the player can scroll.
struct ChronicleScreen: View {
    @Bindable var game: GameViewModel

    var body: some View {
        ZStack {
            Theme.surface.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    if entries.isEmpty {
                        empty
                    } else {
                        ForEach(entries) { entry in
                            row(entry)
                        }
                    }
                }
                .padding(20)
            }
        }
        .foregroundStyle(Theme.text)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(AppStrings.tabChronicle)
                .font(.system(.largeTitle, design: .serif).weight(.bold))
            Text(AppStrings.language == .cs
                 ? "Letopisy tvého lidu."
                 : "The annals of your people.")
                .font(.subheadline).foregroundStyle(Theme.textDim)
        }
    }

    private var empty: some View {
        VStack(spacing: 8) {
            Image(systemName: "book.closed").font(.largeTitle).foregroundStyle(Theme.textDim)
            Text(AppStrings.language == .cs
                 ? "Zatím se nic nezapsalo. Dějiny se teprve píší."
                 : "Nothing recorded yet. History is still being written.")
                .font(.callout).foregroundStyle(Theme.textDim)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    private func row(_ entry: ChronicleEntry) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 2) {
                Text("\(entry.year)")
                    .font(.caption.monospacedDigit().weight(.bold))
                    .foregroundStyle(Theme.accent)
                Text(AppStrings.language == .cs ? "rok" : "yr")
                    .font(.system(size: 8)).foregroundStyle(Theme.textDim)
            }
            .frame(width: 34)
            Rectangle().fill(tint(entry.type)).frame(width: 2).cornerRadius(1)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.title).font(.subheadline.weight(.medium))
                Text(entry.typeLabel).font(.caption2).foregroundStyle(tint(entry.type))
            }
            Spacer()
        }
        .padding(.vertical, 10).padding(.horizontal, 14)
        .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var entries: [ChronicleEntry] {
        game.world.eventHistory.reversed().map { event in
            let name = game.registry.events.first { $0.id == event.templateID }?.name
                ?? event.templateID.replacingOccurrences(of: "_", with: " ").capitalized
            return ChronicleEntry(
                id: event.id,
                year: Season.year(tick: event.tick, ticksPerYear: game.ticksPerYear),
                title: name, type: event.type)
        }
    }

    private func tint(_ type: EventType) -> Color {
        switch type {
        case .disaster, .threat: return Theme.danger
        case .opportunity: return Theme.good
        case .quest: return Theme.accent
        case .flavor: return Theme.textDim
        }
    }
}

private struct ChronicleEntry: Identifiable {
    let id: String
    let year: Int
    let title: String
    let type: EventType

    var typeLabel: String {
        let cs = AppStrings.language == .cs
        switch type {
        case .disaster: return cs ? "pohroma" : "disaster"
        case .threat: return cs ? "hrozba" : "threat"
        case .opportunity: return cs ? "příležitost" : "opportunity"
        case .quest: return cs ? "úkol" : "quest"
        case .flavor: return cs ? "událost" : "event"
        }
    }
}
