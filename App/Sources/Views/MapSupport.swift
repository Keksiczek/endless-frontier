import SwiftUI
import EndlessFrontierCore

/// Biome → colour mapping. Deliberately varied and a little atmospheric, not
/// flat. New biomes fall back to a neutral tone until given a colour.
enum BiomePalette {
    static func color(_ biomeID: String) -> Color {
        switch biomeID {
        case "plains": return Color(red: 0.56, green: 0.70, blue: 0.36)
        case "forest": return Color(red: 0.25, green: 0.48, blue: 0.32)
        case "desert": return Color(red: 0.84, green: 0.72, blue: 0.42)
        case "tundra": return Color(red: 0.74, green: 0.80, blue: 0.85)
        case "mountains": return Color(red: 0.52, green: 0.52, blue: 0.56)
        case "coast": return Color(red: 0.36, green: 0.62, blue: 0.69)
        default: return Color(red: 0.45, green: 0.47, blue: 0.45)
        }
    }

    /// Top (lit) and bottom (shadowed) colours for the terrain gradient.
    static func gradient(_ biomeID: String) -> (Color, Color) {
        let base = color(biomeID)
        return (base.adjusted(by: 0.12), base.adjusted(by: -0.14))
    }

    /// Colour for decorative terrain detail (trees, peaks, dunes, …).
    static func detail(_ biomeID: String) -> Color {
        switch biomeID {
        case "plains": return Color(red: 0.40, green: 0.55, blue: 0.24)
        case "forest": return Color(red: 0.16, green: 0.34, blue: 0.22)
        case "desert": return Color(red: 0.70, green: 0.58, blue: 0.32)
        case "tundra": return Color.white
        case "mountains": return Color(red: 0.38, green: 0.38, blue: 0.42)
        case "coast": return Color(red: 0.85, green: 0.92, blue: 0.97)
        default: return Color.black.opacity(0.5)
        }
    }
}

private extension Color {
    /// Lighten (positive) or darken (negative) a colour in sRGB.
    func adjusted(by amount: Double) -> Color {
        #if canImport(UIKit)
        let ui = UIColor(self)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ui.getRed(&r, green: &g, blue: &b, alpha: &a)
        let d = CGFloat(amount)
        return Color(red: min(max(r + d, 0), 1), green: min(max(g + d, 0), 1), blue: min(max(b + d, 0), 1))
        #else
        return self
        #endif
    }
}

extension RegionKind {
    /// SF Symbol marking special sites on the map (nil = plain region).
    var mapSymbol: String? {
        switch self {
        case .homeland: return "house.fill"
        case .ruins: return "building.columns.fill"
        case .dungeon: return "shippingbox.fill"
        case .anomaly: return "sparkles"
        case .wilderness: return nil
        }
    }
}

/// A flat-top hexagon inscribed in its rect.
struct HexTileShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        let cx = rect.midX
        let cy = rect.midY
        // Flat-top hexagon corners at 0°, 60°, … 300°.
        var path = Path()
        for i in 0..<6 {
            let angle = CGFloat(i) * .pi / 3
            let point = CGPoint(x: cx + (w / 2) * cos(angle), y: cy + (h / 2) * sin(angle))
            if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()
        return path
    }
}

/// Hex layout geometry (flat-top axial → pixel). `size` is centre-to-corner.
enum HexLayout {
    static func center(for coord: HexCoord, size: CGFloat) -> CGPoint {
        let x = size * 1.5 * CGFloat(coord.q)
        let y = size * sqrt(3) * (CGFloat(coord.r) + CGFloat(coord.q) / 2)
        return CGPoint(x: x, y: y)
    }

    static func tileSize(for size: CGFloat) -> CGSize {
        CGSize(width: size * 2, height: size * sqrt(3))
    }
}
