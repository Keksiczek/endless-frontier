import SwiftUI
import EndlessFrontierCore

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
    var displayName: String { rawValue.capitalized }
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
