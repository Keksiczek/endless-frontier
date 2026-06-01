import SwiftUI

/// Deliberate visual direction: a "frontier ledger" — deep slate night sky,
/// warm parchment text, amber lantern accent. Not a default template.
enum Theme {
    // Palette (oklch-inspired, expressed in sRGB for SwiftUI).
    static let surface = Color(red: 0.09, green: 0.10, blue: 0.13)       // near-black slate
    static let surfaceRaised = Color(red: 0.13, green: 0.15, blue: 0.19) // card
    static let surfaceInset = Color(red: 0.07, green: 0.08, blue: 0.10)  // track
    static let text = Color(red: 0.93, green: 0.91, blue: 0.85)          // parchment
    static let textDim = Color(red: 0.62, green: 0.62, blue: 0.60)
    static let accent = Color(red: 0.95, green: 0.66, blue: 0.27)        // amber
    static let danger = Color(red: 0.88, green: 0.35, blue: 0.32)
    static let good = Color(red: 0.50, green: 0.78, blue: 0.52)

    static let cardRadius: CGFloat = 18
    static let spacing: CGFloat = 16
}

extension View {
    /// A raised surface card with consistent depth.
    func frontierCard() -> some View {
        self
            .padding(Theme.spacing)
            .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.05), lineWidth: 1)
            )
    }
}
