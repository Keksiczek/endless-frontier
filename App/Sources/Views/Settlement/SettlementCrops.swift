import SwiftUI
import EndlessFrontierCore

/// The plots, drawn as ground somebody has broken.
///
/// The last half of the food chain to reach the canvas. `FarmEngine` grows a
/// crop on every plot a farm owns and a farmer walks out to reap it — and until
/// this, none of that was on screen: a farm was a barn with nothing around it,
/// and a farmer sent to furrow #7 stood on bare grass. The complaint that
/// started it was the inspector saying "out in the field" over a figure drawn
/// inside a building, and the honest fix is that there *is* a field.
///
/// Purely presentational. Everything comes off `LocalMap.crops`, which the
/// simulation owns: the furrows are where the Core put them, the ripeness is
/// the Core's number, and a plot mid-harvest shows it because `Crop.reaped` says
/// so. Nothing here is invented and nothing is written back (rule 1).
enum SettlementCrops {

    static func draw(
        _ context: inout GraphicsContext, rect: CGRect, map: LocalMap,
        season: Season, zoom: CGFloat
    ) {
        guard map.usesEntityFields else { return }
        for crop in map.crops where map.isExplored(crop.position) {
            plot(&context, crop, rect: rect, season: season, zoom: zoom)
        }
    }

    /// One plot: tilled earth, then whatever is standing on it.
    private static func plot(
        _ context: inout GraphicsContext, _ crop: Crop, rect: CGRect,
        season: Season, zoom: CGFloat
    ) {
        // The plot's own ground, mapped the same way any other point is. Its
        // size comes off the `Crop` rather than being invented here: the plot
        // is a piece of a lot, and the Core is the only thing that knows how
        // that lot was divided (rule 8).
        let p = SettlementRenderer.point(crop.position, in: rect)
        let edge = SettlementRenderer.point(
            LocalPoint(x: crop.position.x + crop.halfWidth,
                       y: crop.position.y + crop.halfHeight), in: rect)
        let half = max(2.0, edge.x - p.x)
        let halfDown = max(1.6, edge.y - p.y)
        let bed = CGRect(x: p.x - half, y: p.y - halfDown,
                         width: half * 2, height: halfDown * 2)

        // The broken earth underneath, always — a reaped plot is still a plot,
        // and a colony in January should be able to see where its fields are.
        context.fill(Path(roundedRect: bed, cornerRadius: half * 0.14),
                     with: .color(soil(season)))
        context.stroke(Path(roundedRect: bed, cornerRadius: half * 0.14),
                       with: .color(Theme.ink.opacity(0.45)), lineWidth: 0.7)

        // Furrows: ruled lines across the bed, so it reads as worked ground
        // rather than as a brown rectangle.
        let rows = 2
        for row in 0..<rows {
            let y = bed.minY + bed.height * (CGFloat(row) + 0.5) / CGFloat(rows)
            context.stroke(Path { path in
                path.move(to: CGPoint(x: bed.minX + half * 0.12, y: y))
                path.addLine(to: CGPoint(x: bed.maxX - half * 0.12, y: y))
            }, with: .color(Theme.ink.opacity(0.20)), lineWidth: 0.5)
        }

        guard crop.growth > 0.02, season != .winter || crop.growth > 0.5 else { return }

        // What is growing, by how far along it is. Green while it comes on and
        // the crop's own colour once it has turned, so a field ready to cut
        // reads as ready to cut from across the valley — which is the one thing
        // a player wants to know at a glance.
        let ripeness = min(1, crop.growth)
        let colour = shoot.blended(to: ripe(crop.species), by: ripeness)
        // Reaping eats the standing crop from one end, so a plot somebody is
        // halfway through looks halfway through.
        let standing = 1 - min(1, crop.reaped)
        guard standing > 0.02 else { return }

        let stalks = 5
        let height = halfDown * (0.30 + 0.55 * ripeness)
        for i in 0..<stalks {
            let u = (CGFloat(i) + 0.5) / CGFloat(stalks)
            guard u <= standing else { break }
            let x = bed.minX + bed.width * u
            for row in 0..<rows {
                let y = bed.minY + bed.height * (CGFloat(row) + 0.5) / CGFloat(rows)
                context.stroke(Path { path in
                    path.move(to: CGPoint(x: x, y: y + height * 0.18))
                    path.addLine(to: CGPoint(x: x, y: y - height * 0.5))
                }, with: .color(colour), lineWidth: 0.8)
            }
        }
        // The ear on top, once there is one to have.
        guard crop.isRipe else { return }
        for i in 0..<stalks {
            let u = (CGFloat(i) + 0.5) / CGFloat(stalks)
            guard u <= standing else { break }
            let x = bed.minX + bed.width * u
            for row in 0..<rows {
                let y = bed.minY + bed.height * (CGFloat(row) + 0.5) / CGFloat(rows)
                    - height * 0.5
                context.fill(Path(ellipseIn: CGRect(
                    x: x - 0.9 * zoom, y: y - 1.4 * zoom,
                    width: 1.8 * zoom, height: 2.2 * zoom)),
                    with: .color(colour))
            }
        }
    }

    // MARK: - Colour

    /// Turned earth, which is darker than the grass around it and darker still
    /// when it is wet. Snow is handled by the ground layer above — the plot
    /// keeps its own tone under it so a winter field is a field, not a hole.
    private static func soil(_ season: Season) -> Color {
        switch season {
        case .spring: return Color(red: 0.40, green: 0.30, blue: 0.20)
        case .summer: return Color(red: 0.45, green: 0.34, blue: 0.22)
        case .autumn: return Color(red: 0.42, green: 0.31, blue: 0.20)
        case .winter: return Color(red: 0.38, green: 0.34, blue: 0.30)
        }
    }

    /// The colours a crop passes through, held as plain components.
    ///
    /// Kept as numbers rather than as `Color`s on purpose: this is a per-frame
    /// draw path over every plot the colony owns, and resolving a `Color` back
    /// into channels costs a `UIColor` round-trip apiece. Blending three
    /// channels through `UIColor` was six of those per plot per frame.
    private struct RGB {
        let r, g, b: Double

        func blended(to other: RGB, by t: Double) -> Color {
            let u = min(1, max(0, t))
            return Color(red: r + (other.r - r) * u,
                         green: g + (other.g - g) * u,
                         blue: b + (other.b - b) * u)
        }
    }

    /// New growth: every crop starts the same shade of green.
    private static let shoot = RGB(r: 0.42, g: 0.58, b: 0.30)

    /// …and turns its own colour, so a field ready to cut reads as ready to cut
    /// from across the valley.
    private static func ripe(_ species: CropSpecies) -> RGB {
        switch species {
        case .grain: return RGB(r: 0.82, g: 0.70, b: 0.34)
        case .roots: return RGB(r: 0.56, g: 0.60, b: 0.30)
        case .greens: return RGB(r: 0.46, g: 0.66, b: 0.36)
        }
    }
}
