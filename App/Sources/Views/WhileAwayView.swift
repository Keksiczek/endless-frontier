import SwiftUI
import EndlessFrontierCore

/// "While you were away" — the chronicle of events that fired during offline
/// ticks. In Phase 3 the LLM narrator will replace these hints with prose.
struct WhileAwayView: View {
    let events: [HistoricalEvent]
    let registry: GameDataRegistry
    let onDismiss: () -> Void

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.surface.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(grouped, id: \.tick) { entry in
                            chronicleRow(entry)
                        }
                    }
                    .padding(20)
                }
            }
            .foregroundStyle(Theme.text)
            .navigationTitle("While You Were Away")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Continue", action: onDismiss)
                        .foregroundStyle(Theme.accent)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private struct Entry { let tick: Int; let templateID: String; let template: EventTemplate?; let type: EventType }

    private var grouped: [Entry] {
        events.map { e in
            Entry(tick: e.tick, templateID: e.templateID,
                  template: registry.events.first { $0.id == e.templateID }, type: e.type)
        }
    }

    /// Copy for engine-emitted "system" events that have no storyteller
    /// template (caravans, discoveries). Falls back to a title-cased id.
    private func systemCopy(_ id: String) -> (name: String, hint: String) {
        switch id {
        case "caravan_arrived":
            return ("Caravan Arrived", "An escorted shipment reached its destination; its guards settled in.")
        case "caravan_ambushed":
            return ("Caravan Ambushed", "Raiders struck a caravan on the road — cargo and lives were lost.")
        case "caravan_skirmish":
            return ("Caravan Skirmish", "A caravan's escort beat off an ambush and pressed on.")
        case "caravan_lost":
            return ("Caravan Lost", "A caravan was overrun and taken — its goods and escort are gone.")
        case "region_discovered":
            return ("New Region Discovered", "Your explorers charted new ground at the frontier.")
        default:
            return (id.replacingOccurrences(of: "_", with: " ").capitalized, "")
        }
    }

    private func chronicleRow(_ entry: Entry) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon(entry.type))
                .foregroundStyle(color(entry.type))
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.template?.name ?? systemCopy(entry.templateID).name)
                    .font(.subheadline.weight(.semibold))
                Text(entry.template?.narrativeHint ?? systemCopy(entry.templateID).hint)
                    .font(.footnote)
                    .foregroundStyle(Theme.textDim)
                Text("Tick \(entry.tick)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(Theme.textDim.opacity(0.7))
            }
            Spacer(minLength: 0)
        }
        .frontierCard()
    }

    private func icon(_ type: EventType) -> String {
        switch type {
        case .disaster: return "flame.fill"
        case .threat: return "exclamationmark.triangle.fill"
        case .opportunity: return "sparkles"
        case .quest: return "scroll.fill"
        case .flavor: return "text.quote"
        }
    }

    private func color(_ type: EventType) -> Color {
        switch type {
        case .disaster, .threat: return Theme.danger
        case .opportunity, .quest: return Theme.good
        case .flavor: return Theme.textDim
        }
    }
}
