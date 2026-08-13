import SwiftUI
import EndlessFrontierCore

/// The country's own shapes, drawn from the cells they actually hold.
///
/// **These are not scenery.** A `SceneryProp` is a picture at a point; a
/// `Landform` occupies ground, and the blocking ones are ground a walker has to
/// go round (`ColonyRoute.Occupancy`). So this draws the *cells* — what is on
/// the canvas is the same set of cells the router refuses to cross, which is
/// the whole of "what is in the simulation is what is on the canvas".
///
/// Drawn under the wood and the buildings: a ravine is ground, and a tree on
/// its lip should stand in front of it.
enum SettlementLandforms {

    static func draw(
        _ context: inout GraphicsContext, rect: CGRect, map: LocalMap,
        season: Season, zoom: CGFloat, showLabels: Bool
    ) {
        guard !map.landforms.isEmpty else { return }
        let cw = rect.width / CGFloat(LocalMap.gridColumns)
        let ch = rect.height / CGFloat(LocalMap.gridRows)

        for form in map.landforms {
            // Under fog it does not exist, the same as everything else out
            // there — a ravine you have not walked to is not on your map.
            let seen = form.cells.filter { map.isExplored(centre(of: $0)) }
            guard !seen.isEmpty else { continue }

            var body = Path()
            for cell in seen.sorted() {
                let column = cell % LocalMap.gridColumns
                let row = cell / LocalMap.gridColumns
                body.addRect(CGRect(x: rect.minX + CGFloat(column) * cw,
                                    y: rect.minY + CGFloat(row) * ch,
                                    width: cw + 0.5, height: ch + 0.5))
            }
            paint(&context, form: form, body: body, season: season, zoom: zoom,
                  cellWidth: cw, cellHeight: ch, cells: seen, rect: rect)

            guard showLabels else { continue }
            let at = SettlementRenderer.point(form.centre, in: rect)
            let caption = Text(form.kind.displayName.resolve(AppStrings.language))
                .font(.system(size: 6, weight: .medium))
                .foregroundStyle(Theme.boneDim.opacity(0.85))
            context.draw(context.resolve(caption), at: CGPoint(x: at.x, y: at.y))
        }
    }

    /// The middle of a fog cell, in the normalised space the map speaks.
    private static func centre(of cell: Int) -> LocalPoint {
        LocalPoint(x: (Double(cell % LocalMap.gridColumns) + 0.5) / Double(LocalMap.gridColumns),
                   y: (Double(cell / LocalMap.gridColumns) + 0.5) / Double(LocalMap.gridRows))
    }

    private static func paint(
        _ context: inout GraphicsContext, form: Landform, body: Path,
        season: Season, zoom: CGFloat, cellWidth cw: CGFloat, cellHeight ch: CGFloat,
        cells: Set<Int>, rect: CGRect
    ) {
        switch form.kind {
        case .ravine:
            // A cut: dark, with a lit lip along the top so it reads as *down*
            // rather than as a dark patch of ground.
            context.fill(body, with: .color(Color(red: 0.13, green: 0.12, blue: 0.14)))
            context.stroke(body, with: .color(Theme.bone.opacity(0.22)), lineWidth: 0.7)
            for cell in cells.sorted() where !cells.contains(cell - LocalMap.gridColumns) {
                let column = cell % LocalMap.gridColumns, row = cell / LocalMap.gridColumns
                context.stroke(Path { p in
                    p.move(to: CGPoint(x: rect.minX + CGFloat(column) * cw,
                                       y: rect.minY + CGFloat(row) * ch))
                    p.addLine(to: CGPoint(x: rect.minX + CGFloat(column + 1) * cw,
                                          y: rect.minY + CGFloat(row) * ch))
                }, with: .color(Theme.bone.opacity(0.42)), lineWidth: max(0.8, zoom))
            }

        case .mesa:
            // A block of rock with a bright top and a shadow at its foot.
            context.fill(body, with: .color(Color(red: 0.34, green: 0.31, blue: 0.30)))
            context.stroke(body, with: .color(Theme.bone.opacity(0.34)), lineWidth: 0.8)
            for cell in cells.sorted() where !cells.contains(cell + LocalMap.gridColumns) {
                let column = cell % LocalMap.gridColumns, row = cell / LocalMap.gridColumns
                context.fill(Path(CGRect(x: rect.minX + CGFloat(column) * cw,
                                         y: rect.minY + CGFloat(row + 1) * ch - ch * 0.28,
                                         width: cw, height: ch * 0.28)),
                             with: .color(.black.opacity(0.30)))
            }

        case .oasis:
            // Water, and green round it — the one landform that is good news.
            context.fill(body, with: .color(Color(red: 0.16, green: 0.34, blue: 0.30).opacity(0.85)))
            let pool = body.boundingRect.insetBy(dx: cw * 0.9, dy: ch * 0.7)
            if pool.width > 1, pool.height > 1 {
                context.fill(Path(ellipseIn: pool),
                             with: .color(Color(red: 0.20, green: 0.45, blue: 0.55).opacity(0.9)))
                context.stroke(Path(ellipseIn: pool),
                               with: .color(Color(red: 0.55, green: 0.78, blue: 0.82).opacity(0.5)),
                               lineWidth: 0.8)
            }

        case .hollow:
            // A dish in the ground: a soft darker wash, no hard edge, because
            // you can walk into it.
            context.fill(body, with: .color(Color(red: 0.16, green: 0.17, blue: 0.15).opacity(0.5)))

        case .ruinField:
            // Low walls, roofless. Drawn as *walls on the cells* rather than as
            // filled ground, because the streets between them are walkable and
            // the drawing should say which is which.
            context.fill(body, with: .color(Color(red: 0.22, green: 0.21, blue: 0.20).opacity(0.45)))
            for cell in cells.sorted() where cell % 2 == 0 {
                let column = cell % LocalMap.gridColumns, row = cell / LocalMap.gridColumns
                let x = rect.minX + CGFloat(column) * cw
                let y = rect.minY + CGFloat(row) * ch
                context.fill(Path(CGRect(x: x + cw * 0.12, y: y + ch * 0.18,
                                         width: cw * 0.76, height: ch * 0.22)),
                             with: .color(Color(red: 0.52, green: 0.49, blue: 0.44).opacity(0.9)))
                if cell % 4 == 0 {
                    context.fill(Path(CGRect(x: x + cw * 0.12, y: y + ch * 0.18,
                                             width: cw * 0.20, height: ch * 0.62)),
                                 with: .color(Color(red: 0.46, green: 0.43, blue: 0.39).opacity(0.9)))
                }
            }
        }
    }
}
