import SwiftUI
import EndlessFrontierCore

/// A small corner map of what's been explored, plus the settlement heart and
/// discovered points of interest. Mirrors the "world · territory" inset from
/// the civilisation sim.
struct MinimapView: View {
    let map: LocalMap

    var body: some View {
        Canvas { context, size in
            let rect = CGRect(origin: .zero, size: size)
            context.fill(Path(rect), with: .color(Theme.ink.opacity(0.9)))

            // Revealed ground.
            let cols = LocalMap.gridColumns, rows = LocalMap.gridRows
            let cw = size.width / CGFloat(cols), ch = size.height / CGFloat(rows)
            var revealed = Path()
            for index in map.exploredCells {
                let col = index % cols, row = index / cols
                revealed.addRect(CGRect(x: CGFloat(col) * cw, y: CGFloat(row) * ch,
                                        width: cw + 0.5, height: ch + 0.5))
            }
            context.fill(revealed, with: .color(Theme.boneFaint.opacity(0.5)))

            // Discovered points of interest.
            for poi in map.pois where poi.discovered {
                let p = CGPoint(x: poi.position.x * size.width, y: poi.position.y * size.height)
                context.fill(Path(ellipseIn: CGRect(x: p.x - 1.4, y: p.y - 1.4, width: 2.8, height: 2.8)),
                             with: .color(Theme.accent.opacity(0.9)))
            }

            // The settlement heart.
            let heart = CGPoint(x: size.width * 0.5, y: size.height * 0.52)
            context.fill(Path(ellipseIn: CGRect(x: heart.x - 2, y: heart.y - 2, width: 4, height: 4)),
                         with: .color(Theme.bone))
        }
        .frame(width: 96, height: 60)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(Theme.boneFaint.opacity(0.6), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .accessibilityHidden(true)
    }
}
