import SwiftUI
import EndlessFrontierCore

/// What is behind one number in the resource bar.
///
/// The bar states five figures and lets you follow none of them, and for food
/// that is not merely unhelpful — it is misleading. `storage[.food]` means
/// *meals ready to eat* and nothing else, so a player reading `food: 0` cannot
/// tell a colony with no crop from one whose harvest is lying in the fields
/// from one with a full granary and nobody cooking. Three different problems,
/// one number (§11.24).
///
/// The stages come from `StoreBreakdown` in the Core, so this card and the
/// simulation cannot disagree (rule 18). It draws them in the order the goods
/// actually move, and marks the first empty stage after a full one — which is
/// where the chain is broken.
struct StoreBreakdownCard: View {
    let resource: ResourceType
    let stages: [StoreStage]
    let capacity: Double
    var onClose: () -> Void

    private var cs: Bool { AppStrings.language == .cs }
    private var language: GameLanguage { AppStrings.language }

    /// The first stage that is empty while the one before it is not. That is
    /// the broken link — goods arrive and stop here — and it is exactly the
    /// reading that took a day to make by hand when the colony was starving.
    private var brokenAt: String? {
        for (index, stage) in stages.enumerated() where index > 0 {
            if stage.amount <= 0, stages[index - 1].amount > 0 { return stage.id }
        }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            VStack(spacing: 0) {
                ForEach(Array(stages.enumerated()), id: \.element.id) { index, stage in
                    if index > 0 { connector }
                    row(stage)
                }
            }
        }
        .padding(16)
        .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Theme.accent.opacity(0.20), lineWidth: 1)
        )
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Image(systemName: resource.symbolName)
                .foregroundStyle(Theme.accent)
            VStack(alignment: .leading, spacing: 1) {
                Text(resource.displayName)
                    .font(.system(.headline, design: .serif).weight(.semibold))
                    .foregroundStyle(Theme.text)
                if capacity > 0 {
                    Text("\(Int(stages.last?.amount ?? 0)) / \(Int(capacity))")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(Theme.textDim)
                }
            }
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(Theme.textDim)
            }
            .accessibilityLabel(cs ? "Zavřít" : "Close")
        }
    }

    /// The line between two links, so the card reads as a chain rather than a
    /// list of unrelated figures.
    private var connector: some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(Theme.textDim.opacity(0.25))
                .frame(width: 1, height: 12)
                .padding(.leading, 9)
            Spacer()
        }
    }

    private func row(_ stage: StoreStage) -> some View {
        let broken = stage.id == brokenAt
        return HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(broken ? Theme.danger : (stage.amount > 0 ? Theme.good : Theme.textDim.opacity(0.4)))
                .frame(width: 7, height: 7)
                .padding(.top, 5)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline) {
                    Text(stage.label.resolve(language))
                        .font(.subheadline.weight(broken ? .semibold : .regular))
                        .foregroundStyle(broken ? Theme.danger : Theme.text)
                    Spacer()
                    Text("\(Int(stage.amount))")
                        .font(.subheadline.monospacedDigit().weight(.medium))
                        .foregroundStyle(broken ? Theme.danger : Theme.text)
                }
                if let note = stage.note {
                    Text(note.resolve(language))
                        .font(.caption)
                        .foregroundStyle(Theme.textDim)
                }
                // **The kinds**, which is what was actually asked for: grain
                // against roots, timber against stone. The crafting bench was
                // the only screen in the game that named them, and that is the
                // one place you go when you already know what you want.
                if !stage.items.isEmpty {
                    FlowingKinds(items: stage.items, language: language)
                        .padding(.top, 2)
                }
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

/// The kinds at one stage, wrapping rather than truncating — a colony late in
/// the game holds a dozen goods and a single line would hide most of them.
private struct FlowingKinds: View {
    let items: [StoreItem]
    let language: GameLanguage

    var body: some View {
        ViewThatFits(in: .horizontal) {
            row(items)
            VStack(alignment: .leading, spacing: 3) {
                ForEach(chunks, id: \.first?.id) { chunk in row(chunk) }
            }
        }
    }

    /// Three to a line reads as a list; more reads as a paragraph of numbers.
    private var chunks: [[StoreItem]] {
        stride(from: 0, to: items.count, by: 3).map {
            Array(items[$0..<min($0 + 3, items.count)])
        }
    }

    private func row(_ some: [StoreItem]) -> some View {
        HStack(spacing: 6) {
            ForEach(some) { item in
                HStack(spacing: 3) {
                    Text(item.name.resolve(language))
                        .foregroundStyle(Theme.textDim)
                    Text("\(item.amount)")
                        .font(.caption2.monospacedDigit().weight(.medium))
                        .foregroundStyle(Theme.text)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Theme.surfaceInset, in: Capsule())
            }
        }
        .font(.caption2)
    }
}
