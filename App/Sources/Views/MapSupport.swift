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
