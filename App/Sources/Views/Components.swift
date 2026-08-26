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
    ///
    /// The words themselves live on `ResourceType.displayNameLocalized` in the
    /// Core, because the engines write sentences that have to name a resource
    /// too. Two copies of five words is two copies too many (rule 35).
    var displayName: String {
        displayNameLocalized.resolve(AppStrings.language)
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

// `ResourceChip` stood here: an icon, an amount, and a `capacity` it took as a
// parameter and never drew — a "capacity hint" that was never written. Nothing
// in the app ever constructed one. `StatusStrip` and `StoreBreakdownCard` do
// this job and do it against real storage caps.

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

/// A wrapping row: lays its children left to right and drops to a new line
/// rather than squeezing or running off the edge.
///
/// Two places need this and both learned it the hard way. Ingredient lists are
/// a handful of short chips of unknowable total width; the diplomacy verbs are
/// up to eight buttons that could not shrink below 56pt and so simply left the
/// screen. An `HStack` handles neither — it compresses what it can and clips
/// what it cannot, and a clipped button is a feature the player never finds.
struct FlowRow: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, lineHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += lineHeight + spacing
                lineHeight = 0
            }
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
        return CGSize(width: proposal.width ?? x, height: y + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize,
                       subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, lineHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += lineHeight + spacing
                lineHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}
