import SwiftUI
import EndlessFrontierCore

/// Per-biome painted terrain for a hex tile, drawn procedurally with `Canvas`
/// (no image assets — fully offline). Decorative detail is seeded by the hex
/// coordinate so each tile is varied but stable across redraws.
struct HexTerrainView: View {
    let region: Region

    var body: some View {
        Canvas { context, size in
            let rect = CGRect(origin: .zero, size: size)
            let hex = HexTerrain.path(in: rect)

            // Base gradient — light from the top for a sense of relief.
            let (top, bottom) = BiomePalette.gradient(region.biomeID)
            context.fill(
                hex,
                with: .linearGradient(
                    Gradient(colors: [top, bottom]),
                    startPoint: CGPoint(x: rect.midX, y: rect.minY),
                    endPoint: CGPoint(x: rect.midX, y: rect.maxY)
                )
            )

            // Decorative terrain, clipped to the hex.
            var inner = context
            inner.clip(to: hex)
            HexTerrain.drawDetail(for: region, in: rect, context: &inner)

            // Inner shadow at the bottom for depth.
            inner.fill(
                hex,
                with: .linearGradient(
                    Gradient(colors: [.clear, .black.opacity(0.22)]),
                    startPoint: CGPoint(x: rect.midX, y: rect.midY),
                    endPoint: CGPoint(x: rect.midX, y: rect.maxY)
                )
            )

            // Top highlight rim.
            context.stroke(hex, with: .color(.white.opacity(0.10)), lineWidth: 1.5)
        }
    }
}

/// Terrain drawing helpers.
enum HexTerrain {
    /// Flat-top hexagon inscribed in `rect`.
    static func path(in rect: CGRect) -> Path {
        var path = Path()
        let cx = rect.midX, cy = rect.midY
        let rx = rect.width / 2, ry = rect.height / 2
        for i in 0..<6 {
            let a = CGFloat(i) * .pi / 3
            let p = CGPoint(x: cx + rx * cos(a), y: cy + ry * sin(a))
            if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
        }
        path.closeSubpath()
        return path
    }

    private static func seed(_ coord: HexCoord) -> UInt64 {
        var h: UInt64 = 0x9E37_79B9
        h = (h ^ UInt64(bitPattern: Int64(coord.q))) &* 0x0100_0000_01B3
        h = (h ^ UInt64(bitPattern: Int64(coord.r))) &* 0x0100_0000_01B3
        return h ^ (h >> 17)
    }

    /// Scatters `count` jittered points inside the hex's inset bounding area.
    private static func scatter(_ count: Int, in rect: CGRect, rng: inout SeededRNG) -> [CGPoint] {
        let inset = rect.insetBy(dx: rect.width * 0.16, dy: rect.height * 0.16)
        return (0..<count).map { _ in
            CGPoint(x: inset.minX + rng.nextUnit() * inset.width,
                    y: inset.minY + rng.nextUnit() * inset.height)
        }
    }

    static func drawDetail(for region: Region, in rect: CGRect, context: inout GraphicsContext) {
        var rng = SeededRNG(seed: seed(region.coord))
        let s = min(rect.width, rect.height)
        let detail = BiomePalette.detail(region.biomeID)

        switch region.biomeID {
        case "forest":
            for p in scatter(7, in: rect, rng: &rng) {
                tree(at: p, scale: s * 0.07, color: detail, context: &context)
            }
        case "mountains":
            for p in scatter(4, in: rect, rng: &rng) {
                peak(at: p, scale: s * 0.16, color: detail, context: &context)
            }
        case "desert":
            for p in scatter(4, in: rect, rng: &rng) {
                dune(at: p, width: s * 0.32, color: detail, context: &context)
            }
        case "tundra":
            for p in scatter(10, in: rect, rng: &rng) {
                let r = s * 0.035
                context.fill(Path(ellipseIn: CGRect(x: p.x, y: p.y, width: r, height: r)),
                             with: .color(detail.opacity(0.8)))
            }
        case "coast":
            for i in 0..<3 {
                let y = rect.minY + rect.height * (0.45 + CGFloat(i) * 0.16)
                var wave = Path()
                wave.move(to: CGPoint(x: rect.minX, y: y))
                wave.addCurve(to: CGPoint(x: rect.maxX, y: y),
                              control1: CGPoint(x: rect.midX - s * 0.2, y: y - s * 0.05),
                              control2: CGPoint(x: rect.midX + s * 0.2, y: y + s * 0.05))
                context.stroke(wave, with: .color(detail.opacity(0.6)), lineWidth: 1.5)
            }
        default: // plains & fallback — soft grass tufts
            for p in scatter(8, in: rect, rng: &rng) {
                var blade = Path()
                blade.move(to: p)
                blade.addLine(to: CGPoint(x: p.x, y: p.y - s * 0.06))
                context.stroke(blade, with: .color(detail.opacity(0.6)), lineWidth: 1.2)
            }
        }
    }

    private static func tree(at p: CGPoint, scale: CGFloat, color: Color, context: inout GraphicsContext) {
        var tri = Path()
        tri.move(to: CGPoint(x: p.x, y: p.y - scale))
        tri.addLine(to: CGPoint(x: p.x - scale * 0.7, y: p.y + scale))
        tri.addLine(to: CGPoint(x: p.x + scale * 0.7, y: p.y + scale))
        tri.closeSubpath()
        context.fill(tri, with: .color(color.opacity(0.85)))
    }

    private static func peak(at p: CGPoint, scale: CGFloat, color: Color, context: inout GraphicsContext) {
        var tri = Path()
        tri.move(to: CGPoint(x: p.x, y: p.y - scale))
        tri.addLine(to: CGPoint(x: p.x - scale * 0.8, y: p.y + scale * 0.7))
        tri.addLine(to: CGPoint(x: p.x + scale * 0.8, y: p.y + scale * 0.7))
        tri.closeSubpath()
        context.fill(tri, with: .color(color.opacity(0.9)))
        // snow cap
        var cap = Path()
        cap.move(to: CGPoint(x: p.x, y: p.y - scale))
        cap.addLine(to: CGPoint(x: p.x - scale * 0.28, y: p.y - scale * 0.4))
        cap.addLine(to: CGPoint(x: p.x + scale * 0.28, y: p.y - scale * 0.4))
        cap.closeSubpath()
        context.fill(cap, with: .color(.white.opacity(0.85)))
    }

    private static func dune(at p: CGPoint, width: CGFloat, color: Color, context: inout GraphicsContext) {
        var arc = Path()
        arc.move(to: CGPoint(x: p.x - width / 2, y: p.y))
        arc.addQuadCurve(to: CGPoint(x: p.x + width / 2, y: p.y),
                         control: CGPoint(x: p.x, y: p.y - width * 0.28))
        context.stroke(arc, with: .color(color.opacity(0.7)), lineWidth: 1.5)
    }
}
