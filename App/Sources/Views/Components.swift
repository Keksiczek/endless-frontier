import SwiftUI
import EndlessFrontierCore

/// What a cart is carrying, said in the player's language.
///
/// A caravan used to carry one of five pools and nothing else, so every panel
/// that drew one asked the resource directly. It can carry **goods** now
/// (`CaravanCargo`) — timber, charcoal, ore — and a cart of timber has no
/// resource to ask. The name comes out of the registry, so a good is called
/// what the content calls it in both languages rather than by its id.
extension CaravanCargo {
    var symbolName: String {
        switch self {
        case let .resource(resource): return resource.symbolName
        case .goods: return "shippingbox.fill"
        }
    }

    func displayName(_ registry: GameDataRegistry?) -> String {
        switch self {
        case let .resource(resource):
            return resource.displayName
        case let .goods(item):
            return registry?.item(item)?.name.resolve(AppStrings.language) ?? item
        }
    }
}

extension ResourceType {
    var symbolName: String {
        switch self {
        case .food: return "leaf.fill"
        case .materials: return "cube.fill"
        case .energy: return "bolt.fill"
        case .knowledge: return "book.fill"
        case .influence: return "crown.fill"
        }
    }
    /// The resource's name in the player's language.
    ///
    /// This was `rawValue.capitalized` — so a Czech game said "Food",
    /// "Materials", "Knowledge" in the middle of otherwise Czech sentences, in
    /// every panel that named a resource. The five most-repeated words in the
    /// game were the five that were never translated.
    var displayName: String {
        let cs = AppStrings.language == .cs
        switch self {
        case .food:      return cs ? "jídlo" : "food"
        case .materials: return cs ? "materiál" : "materials"
        case .energy:    return cs ? "energie" : "energy"
        case .knowledge: return cs ? "vědění" : "knowledge"
        case .influence: return cs ? "vliv" : "influence"
        }
    }

    /// The same, capitalised for the head of a line or a column.
    var displayTitle: String {
        let name = displayName
        return name.prefix(1).uppercased() + name.dropFirst()
    }
}

/// A labelled 0–100 indicator bar with a semantic colour.
struct StatBar: View {
    let label: String
    let value: Double
    var tint: Color = Theme.accent

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Theme.textDim)
                Spacer()
                Text("\(Int(value.rounded()))")
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(Theme.text)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.surfaceInset)
                    Capsule()
                        .fill(tint)
                        .frame(width: geo.size.width * CGFloat(min(max(value, 0), 100) / 100))
                }
            }
            .frame(height: 6)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(Int(value.rounded())) out of 100")
    }
}

/// A compact resource chip with icon, amount and capacity hint.
struct ResourceChip: View {
    let type: ResourceType
    let amount: Double
    let capacity: Double

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: type.symbolName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(type.displayName)
                    .font(.caption2)
                    .foregroundStyle(Theme.textDim)
                Text("\(Int(amount.rounded()))")
                    .font(.subheadline.monospacedDigit().weight(.semibold))
                    .foregroundStyle(Theme.text)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(Theme.surfaceInset, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(type.displayName): \(Int(amount.rounded()))")
    }
}

/// Section header with editorial scale contrast.
struct SectionHeader: View {
    let title: String
    var body: some View {
        Text(title.uppercased())
            .font(.caption.weight(.bold))
            .tracking(1.5)
            .foregroundStyle(Theme.textDim)
    }
}
