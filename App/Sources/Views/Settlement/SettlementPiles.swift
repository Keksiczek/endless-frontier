import SwiftUI
import EndlessFrontierCore

/// Goods lying where the work happened.
///
/// The last place work was still a number: a tree came down half a valley away
/// and the storehouse simply knew. A heap of timber at the stump is the visible
/// half of hauling — you can see what the colony has cut and not yet carried
/// in, and watch it go one load at a time.
///
/// Purely presentational; everything comes off `LocalMap.piles`.
enum SettlementPiles {

    static func draw(
        _ context: inout GraphicsContext, rect: CGRect, map: LocalMap, zoom: CGFloat
    ) {
        for pile in map.piles where map.isExplored(pile.position) {
            heap(&context, pile, at: SettlementRenderer.point(pile.position, in: rect),
                 zoom: zoom)
        }
    }

    /// A heap, sized by what is in it and drawn as the thing it is made of:
    /// stacked logs for timber, tumbled blocks for stone.
    private static func heap(
        _ context: inout GraphicsContext, _ pile: HaulPile, at p: CGPoint, zoom: CGFloat
    ) {
        let s = (2.4 + min(3.0, CGFloat(pile.amount) * 0.35)) * zoom
        let colour = goodsColour(pile.itemID)

        context.fill(Path(ellipseIn: CGRect(x: p.x - s, y: p.y + s * 0.25,
                                            width: s * 2, height: s * 0.55)),
                     with: .color(.black.opacity(0.24)))

        if pile.itemID == "wood" {
            // Logs stacked end-on, two courses.
            for course in 0..<2 {
                let y = p.y + s * 0.2 - CGFloat(course) * s * 0.55
                let count = course == 0 ? 3 : 2
                for i in 0..<count {
                    let x = p.x - CGFloat(count - 1) * s * 0.34 + CGFloat(i) * s * 0.68
                    let r = s * 0.30
                    context.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r,
                                                        width: r * 2, height: r * 2)),
                                 with: .color(colour))
                    context.stroke(Path(ellipseIn: CGRect(x: x - r, y: y - r,
                                                          width: r * 2, height: r * 2)),
                                   with: .color(Theme.ink.opacity(0.45)), lineWidth: 0.5)
                }
            }
        } else {
            // Broken rock: a few tumbled blocks.
            for i in 0..<3 {
                let dx = CGFloat([-0.55, 0.10, 0.60][i]) * s
                let dy = CGFloat([0.10, -0.35, 0.14][i]) * s
                let w = s * CGFloat([0.62, 0.55, 0.50][i])
                let block = CGRect(x: p.x + dx - w / 2, y: p.y + dy - w / 2,
                                   width: w, height: w * 0.78)
                context.fill(Path(roundedRect: block, cornerRadius: w * 0.16),
                             with: .color(colour))
                context.stroke(Path(roundedRect: block, cornerRadius: w * 0.16),
                               with: .color(Theme.bone.opacity(0.32)), lineWidth: 0.5)
            }
        }

        // A claimed heap is on its way — a faint mark so you can tell the ones
        // nobody has got to yet.
        if pile.claimedBy != nil {
            context.stroke(
                Path(ellipseIn: CGRect(x: p.x - s * 1.2, y: p.y - s * 1.0,
                                       width: s * 2.4, height: s * 2.0)),
                with: .color(Theme.accent.opacity(0.30)), lineWidth: 0.7)
        }
    }

    /// What a given good looks like in a heap or on somebody's back.
    static func goodsColour(_ itemID: String) -> Color {
        switch itemID {
        case "wood": return Color(red: 0.46, green: 0.34, blue: 0.22)
        case "rough_stone": return Color(red: 0.42, green: 0.42, blue: 0.45)
        case "iron_ore": return Color(red: 0.40, green: 0.31, blue: 0.27)
        case "clay": return Color(red: 0.48, green: 0.34, blue: 0.26)
        default: return Color(red: 0.44, green: 0.40, blue: 0.34)
        }
    }
}
