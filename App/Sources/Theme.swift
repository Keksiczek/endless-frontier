import SwiftUI
import EndlessFrontierCore

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

    // MARK: - Living-world canvas ("observatory" line-art)
    //
    // The settlement view is drawn as monochrome line-art on near-black ink,
    // in the spirit of the civilisation sim: no image assets, everything a
    // stroke. These tokens keep that layer coherent and easy to extend.

    /// The canvas backdrop — deeper than `surface` so the world reads as a
    /// window into night.
    static let ink = Color(red: 0.04, green: 0.045, blue: 0.06)
    /// Primary hairline stroke — bone white.
    static let bone = Color(red: 0.91, green: 0.90, blue: 0.86)
    /// Muted stroke for secondary detail.
    static let boneDim = Color(red: 0.52, green: 0.53, blue: 0.55)
    /// Faintest stroke — distant scenery, grid.
    static let boneFaint = Color(red: 0.28, green: 0.29, blue: 0.32)

    /// A distinct-but-muted shade per colonist trade, so a glance reads the
    /// mix of work without a legend shouting for attention.
    static func roleShade(_ work: WorkKind) -> Color {
        switch work {
        case .farming:  return Color(red: 0.82, green: 0.80, blue: 0.62) // wheat
        case .logging:  return Color(red: 0.66, green: 0.76, blue: 0.66) // pine
        case .mining:   return Color(red: 0.68, green: 0.70, blue: 0.78) // slate
        case .foraging: return Color(red: 0.74, green: 0.80, blue: 0.70) // herb
        case .hunting:  return Color(red: 0.80, green: 0.72, blue: 0.62) // hide
        case .research: return Color(red: 0.72, green: 0.78, blue: 0.86) // ink-blue
        case .healing:  return Color(red: 0.86, green: 0.74, blue: 0.74) // rose
        case .trade:    return Color(red: 0.84, green: 0.78, blue: 0.60) // coin
        case .priest:   return Color(red: 0.82, green: 0.78, blue: 0.86) // vestment
        case .building: return Color(red: 0.78, green: 0.78, blue: 0.76) // stone
        case .scouting: return Color(red: 0.88, green: 0.88, blue: 0.82) // pale
        case .idle:     return boneDim
        }
    }

    /// A resource deposit's line colour on the canvas.
    static func depositShade(_ kind: LocalResourceKind) -> Color {
        switch kind {
        case .field:  return Color(red: 0.72, green: 0.68, blue: 0.44)
        case .forest: return Color(red: 0.42, green: 0.56, blue: 0.44)
        case .stone:  return Color(red: 0.56, green: 0.58, blue: 0.64)
        case .herbs:  return Color(red: 0.54, green: 0.68, blue: 0.56)
        case .ironOre: return Color(red: 0.70, green: 0.48, blue: 0.38)
        case .clay:    return Color(red: 0.68, green: 0.52, blue: 0.42)
        }
    }

    /// A gentle full-canvas wash tinting the world by season.
    static func seasonTint(_ season: Season) -> Color {
        switch season {
        case .spring: return Color(red: 0.60, green: 0.85, blue: 0.66).opacity(0.05)
        case .summer: return Color(red: 0.95, green: 0.86, blue: 0.55).opacity(0.06)
        case .autumn: return Color(red: 0.90, green: 0.62, blue: 0.42).opacity(0.07)
        case .winter: return Color(red: 0.70, green: 0.80, blue: 0.98).opacity(0.09)
        }
    }
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
