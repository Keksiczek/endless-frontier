import SwiftUI
import EndlessFrontierCore

/// A moment that needs the Leader's word: migrants at the gate, a caravan in the
/// square, refugees in flight. The storyteller queues these; here the player
/// actually decides, and the choice's effects finally run.
struct EventDecisionCard: View {
    @Bindable var game: GameViewModel
    let template: EventTemplate
    /// How many more decisions are waiting behind this one.
    let queued: Int

    private var cs: Bool { AppStrings.language == .cs }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            Text(template.narrativeHint ?? template.name)
                .font(.callout)
                .foregroundStyle(Theme.textDim)
                .fixedSize(horizontal: false, vertical: true)
            VStack(spacing: 8) {
                ForEach(template.choices) { choice in
                    choiceButton(choice)
                }
                Button {
                    game.dismissEvent(template.id)
                } label: {
                    Text(cs ? "Nechat být" : "Let it pass")
                        .font(.caption)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.textDim)
                .padding(.top, 2)
            }
        }
        .padding(16)
        .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(tint.opacity(0.5), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.45), radius: 20, y: 8)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: icon).font(.caption).foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(typeLabel.uppercased())
                    .font(.caption2.weight(.bold)).tracking(1.2)
                    .foregroundStyle(tint)
                Text(template.name)
                    .font(.system(.title3, design: .serif).weight(.semibold))
                    .foregroundStyle(Theme.text)
            }
            Spacer()
            deadlinePill
            if queued > 0 {
                Text("+\(queued)")
                    .font(.caption.monospacedDigit().weight(.bold))
                    .foregroundStyle(Theme.textDim)
                    .padding(.vertical, 3).padding(.horizontal, 7)
                    .background(Theme.surfaceInset, in: Capsule())
                    .accessibilityLabel(cs ? "\(queued) dalších rozhodnutí čeká"
                                           : "\(queued) more decisions waiting")
            }
        }
    }

    /// How long the Leader has left. A decision used to wait indefinitely — and
    /// a choice with no deadline is a suggestion, not a decision.
    @ViewBuilder
    private var deadlinePill: some View {
        if let pending = game.pendingEvents.first(where: { $0.templateID == template.id }) {
            let left = game.ticksLeft(for: pending)
            let years = Double(left) / Double(max(1, game.ticksPerYear))
            let urgent = years < 1
            Label(String(format: "%.1f %@", years, AppStrings.years), systemImage: "hourglass")
                .font(.caption2.weight(.semibold).monospacedDigit())
                .foregroundStyle(urgent ? Theme.danger : Theme.textDim)
                .padding(.vertical, 3).padding(.horizontal, 7)
                .background((urgent ? Theme.danger : Theme.textDim).opacity(0.14), in: Capsule())
                .accessibilityLabel("\(AppStrings.decisionDeadline) \(String(format: "%.1f", years)) \(AppStrings.years)")
        }
    }

    private func choiceButton(_ choice: EventChoice) -> some View {
        let affordable = game.canAfford(choice: choice.id, event: template.id)
        return Button {
            game.resolveEventChoice(event: template.id, choice: choice.id)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(choice.label)
                    .font(.subheadline.weight(.semibold))
                if let description = choice.description {
                    Text(description)
                        .font(.caption2)
                        .foregroundStyle(Theme.textDim)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !choice.cost.amounts.isEmpty {
                    Text(costLabel(choice.cost))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(affordable ? Theme.accent : Theme.danger)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 9).padding(.horizontal, 12)
            .background(Theme.surfaceInset, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .foregroundStyle(Theme.text)
        .disabled(!affordable)
        .opacity(affordable ? 1 : 0.45)
    }

    private func costLabel(_ cost: Resources) -> String {
        ResourceType.allCases
            .filter { cost[$0] > 0 }
            .map { "−\(Int(cost[$0])) \($0.displayName.lowercased())" }
            .joined(separator: " · ")
    }

    private var typeLabel: String {
        switch template.type {
        case .disaster: return cs ? "Pohroma" : "Disaster"
        case .threat: return cs ? "Hrozba" : "Threat"
        case .opportunity: return cs ? "Příležitost" : "Opportunity"
        case .quest: return cs ? "Úkol" : "Quest"
        case .flavor: return cs ? "Událost" : "Event"
        }
    }

    private var tint: Color {
        switch template.type {
        case .disaster, .threat: return Theme.danger
        case .opportunity: return Theme.good
        case .quest, .flavor: return Theme.accent
        }
    }

    private var icon: String {
        switch template.type {
        case .disaster: return "exclamationmark.triangle.fill"
        case .threat: return "shield.lefthalf.filled"
        case .opportunity: return "sparkles"
        case .quest: return "scroll.fill"
        case .flavor: return "bubble.left.fill"
        }
    }
}
