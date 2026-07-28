import SwiftUI
import EndlessFrontierCore

/// The mountain, drawn as the blocks it is made of.
///
/// This is the layer that makes a hillside a *place with a shape* rather than a
/// grey polygon on the grass. Each block of a `StoneField` is drawn as a solid
/// slab: a lit top edge where the light falls on it, a dark face below, and a
/// hard shadow thrown onto whatever is next to it. Only the blocks on the
/// outside get an outline, so a massif reads as one mass with a cliff around
/// it rather than as a wall of tiles.
///
/// The working shows. A block somebody has started on carries the pale scar of
/// cut stone across the share of it that is done, and a face — a block with
/// open ground beside it, the only kind that can be worked — is marked, so you
/// can see where the colony is going to eat into the hill next.
///
/// Strictly presentational; everything comes off the field the engine keeps.
enum SettlementStone {

    /// How far the top of a block is drawn above its floor, as a share of the
    /// cell's height. This is the whole of the third dimension: enough to read
    /// as standing rock, not enough to pretend the game is isometric.
    static let rise: CGFloat = 0.42

    static func draw(
        _ context: inout GraphicsContext, rect: CGRect, map: LocalMap,
        season: Season, zoom: CGFloat
    ) {
        let field = map.stone
        guard field.usesBlocks, !field.isEmpty else { return }
        let cols = LocalMap.gridColumns, rows = LocalMap.gridRows
        let cw = rect.width / CGFloat(cols), ch = rect.height / CGFloat(rows)
        let lift = ch * rise

        // Only rock the colony has actually seen. A mountain in the fog is
        // exactly as invisible as everything else out there.
        let visible = field.solid.filter { map.exploredCells.contains($0) }.sorted()
        guard !visible.isEmpty else { return }

        func frame(_ index: Int) -> CGRect {
            CGRect(x: rect.minX + CGFloat(StoneField.column(of: index)) * cw,
                   y: rect.minY + CGFloat(StoneField.row(of: index)) * ch,
                   width: cw, height: ch)
        }
        func solid(_ column: Int, _ row: Int) -> Bool {
            guard column >= 0, column < cols, row >= 0, row < rows else { return false }
            return field.solid.contains(StoneField.index(column: column, row: row))
        }

        // The shadow the mass throws, under everything, in one pass.
        var shadow = Path()
        for index in visible {
            let f = frame(index)
            shadow.addRect(CGRect(x: f.minX + cw * 0.10, y: f.minY + lift * 0.5,
                                  width: cw + 0.6, height: ch + 0.6))
        }
        context.fill(shadow, with: .color(.black.opacity(0.30)))

        // The rock itself, front face first, then the lit top.
        for index in visible {
            let f = frame(index)
            let kind = field.kind(of: index)
            let body = stoneColour(kind, season: season)
            let column = StoneField.column(of: index), row = StoneField.row(of: index)

            // The face: the block's body, standing.
            context.fill(Path(CGRect(x: f.minX, y: f.minY - lift + ch * 0.2,
                                     width: cw + 0.5, height: ch + lift)),
                         with: .color(body))
            // The top, where the light lands — only drawn where nothing stands
            // behind it, so the inside of a massif stays a mass.
            if !solid(column, row - 1) {
                context.fill(Path(CGRect(x: f.minX, y: f.minY - lift + ch * 0.2,
                                         width: cw + 0.5, height: lift * 0.75)),
                             with: .color(litColour(kind, season: season, by: 0.11)))
            }
            // A worked seam still shows what it is worth going in for.
            if kind == .ironSeam {
                context.stroke(Path { p in
                    p.move(to: CGPoint(x: f.minX + cw * 0.18, y: f.midY + ch * 0.18))
                    p.addLine(to: CGPoint(x: f.maxX - cw * 0.16, y: f.midY - ch * 0.12))
                }, with: .color(Color(red: 0.66, green: 0.46, blue: 0.28).opacity(0.75)),
                   lineWidth: max(0.8, cw * 0.10))
            }

            // What the pick has done to it so far: a pale, flat scar eating up
            // from the floor, so a half-cut block reads as half cut.
            if let progress = field.cut[index], progress > 0.02 {
                let height = (ch + lift) * CGFloat(min(1, progress))
                context.fill(Path(CGRect(x: f.minX + cw * 0.12,
                                         y: f.maxY + ch * 0.2 - height,
                                         width: cw * 0.76, height: height)),
                             with: .color(litColour(kind, season: season, by: 0.17).opacity(0.85)))
            }
        }

        // The cliff line: only the outer edges, so the massif is one shape.
        var outline = Path()
        for index in visible {
            let f = frame(index)
            let column = StoneField.column(of: index), row = StoneField.row(of: index)
            let top = f.minY - lift + ch * 0.2
            if !solid(column, row - 1) {
                outline.move(to: CGPoint(x: f.minX, y: top))
                outline.addLine(to: CGPoint(x: f.maxX, y: top))
            }
            if !solid(column, row + 1) {
                outline.move(to: CGPoint(x: f.minX, y: f.maxY + ch * 0.2))
                outline.addLine(to: CGPoint(x: f.maxX, y: f.maxY + ch * 0.2))
            }
            if !solid(column - 1, row) {
                outline.move(to: CGPoint(x: f.minX, y: top))
                outline.addLine(to: CGPoint(x: f.minX, y: f.maxY + ch * 0.2))
            }
            if !solid(column + 1, row) {
                outline.move(to: CGPoint(x: f.maxX, y: top))
                outline.addLine(to: CGPoint(x: f.maxX, y: f.maxY + ch * 0.2))
            }
        }
        context.stroke(outline, with: .color(Theme.bone.opacity(0.38)),
                       lineWidth: max(0.6, zoom * 0.5))
    }

    /// The raw tones of each rock, before the season touches them. Kept as
    /// components so a lit face can actually be computed rather than faked with
    /// an opacity — a `Color` will not hand its channels back.
    static func stoneTone(_ kind: RockKind, season: Season) -> (r: Double, g: Double, b: Double) {
        var (r, g, b): (Double, Double, Double)
        switch kind {
        case .granite:   (r, g, b) = (0.31, 0.31, 0.34)
        case .limestone: (r, g, b) = (0.42, 0.41, 0.37)
        case .ironSeam:  (r, g, b) = (0.30, 0.27, 0.26)
        case .clayBank:  (r, g, b) = (0.40, 0.30, 0.23)
        }
        if season == .winter {
            r = r * 0.7 + 0.16; g = g * 0.7 + 0.17; b = b * 0.7 + 0.21
        }
        return (r, g, b)
    }

    static func stoneColour(_ kind: RockKind, season: Season) -> Color {
        let t = stoneTone(kind, season: season)
        return Color(red: t.r, green: t.g, blue: t.b)
    }

    /// The same rock with the light on it.
    static func litColour(_ kind: RockKind, season: Season, by amount: Double) -> Color {
        let t = stoneTone(kind, season: season)
        return Color(red: min(1, t.r + amount),
                     green: min(1, t.g + amount),
                     blue: min(1, t.b + amount))
    }
}
