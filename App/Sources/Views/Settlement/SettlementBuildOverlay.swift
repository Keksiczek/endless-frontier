import SwiftUI
import EndlessFrontierCore

/// What the player is currently trying to put down, and where.
///
/// `coord` is nil until they have tapped somewhere: the ghost only appears once
/// there is ground to show it on. Placing is deliberately two steps — tap to
/// aim, then confirm — because the whole problem this solves is not being able
/// to tell where a building will land until it has already landed.
struct BuildPlan: Equatable {
    let definitionID: String
    var coord: TileCoord?
}

/// The build grid, drawn over the living settlement.
///
/// Building used to happen on a separate abstract tile screen, so you chose a
/// spot on one picture and saw the result on another — there was no way to tell
/// what would end up next to what. This puts the grid, the ground already
/// taken, and a full-size ghost of the footprint on the *same* canvas the
/// colony is drawn on.
///
/// Presentation only: it reads the colony's placements and answers whether a
/// footprint fits, and never writes anything.
enum SettlementBuildOverlay {

    static func draw(
        _ context: inout GraphicsContext, rect: CGRect,
        settlement: Settlement, registry: GameDataRegistry, plan: BuildPlan
    ) {
        guard let colony = settlement.colony else { return }
        let footprint = registry.building(plan.definitionID)?.footprint ?? TileSize()

        grid(&context, rect: rect, colony: colony)
        taken(&context, rect: rect, colony: colony)
        if let coord = plan.coord {
            ghost(&context, rect: rect, colony: colony, at: coord, footprint: footprint,
                  fits: ColonyBuilder.canPlace(settlement, definitionID: plan.definitionID,
                                               at: coord, registry: registry))
        }
    }

    /// Where a tap on the canvas lands on the build grid, snapped so a
    /// multi-tile building is centred on the finger rather than hanging off it.
    static func aim(
        at point: LocalPoint, colony: ColonyMap, footprint: TileSize
    ) -> TileCoord? {
        guard let hit = SettlementRenderer.tile(at: point, in: colony) else { return nil }
        // The tap names the middle of the building; `coord` is its top-left.
        let x = hit.x - (footprint.width - 1) / 2
        let y = hit.y - (footprint.height - 1) / 2
        return TileCoord(min(max(0, x), max(0, colony.width - footprint.width)),
                         min(max(0, y), max(0, colony.height - footprint.height)))
    }

    // MARK: - Pieces

    private static func tileRect(
        _ coord: TileCoord, size: TileSize, colony: ColonyMap, rect: CGRect
    ) -> CGRect {
        let origin = SettlementRenderer.canvasPoint(for: coord, in: colony)
        let tw = SettlementRenderer.colonySpan / Double(max(1, colony.width))
        let th = SettlementRenderer.colonySpan / Double(max(1, colony.height))
        // `canvasPoint` answers the tile's centre, so step back half a tile to
        // get its corner before growing to the footprint.
        let topLeft = LocalPoint(x: origin.x - tw / 2, y: origin.y - th / 2)
        let p = SettlementRenderer.point(topLeft, in: rect)
        return CGRect(x: p.x, y: p.y,
                      width: tw * Double(size.width) * rect.width,
                      height: th * Double(size.height) * rect.height)
    }

    private static func grid(
        _ context: inout GraphicsContext, rect: CGRect, colony: ColonyMap
    ) {
        let span = SettlementRenderer.colonySpan
        let heart = SettlementRenderer.colonyHeart
        let x0 = heart.x - span / 2, y0 = heart.y - span / 2
        let area = CGRect(
            x: rect.minX + x0 * rect.width, y: rect.minY + y0 * rect.height,
            width: span * rect.width, height: span * rect.height)

        // The buildable ground, lifted out of the landscape.
        context.fill(Path(area), with: .color(Theme.bone.opacity(0.04)))
        context.stroke(Path(area), with: .color(Theme.accent.opacity(0.45)), lineWidth: 1.2)

        var lines = Path()
        for column in 1..<max(1, colony.width) {
            let x = area.minX + area.width * CGFloat(column) / CGFloat(colony.width)
            lines.move(to: CGPoint(x: x, y: area.minY))
            lines.addLine(to: CGPoint(x: x, y: area.maxY))
        }
        for row in 1..<max(1, colony.height) {
            let y = area.minY + area.height * CGFloat(row) / CGFloat(colony.height)
            lines.move(to: CGPoint(x: area.minX, y: y))
            lines.addLine(to: CGPoint(x: area.maxX, y: y))
        }
        context.stroke(lines, with: .color(Theme.bone.opacity(0.13)), lineWidth: 0.5)
    }

    /// The ground already spoken for, so "there is no room" is something you can
    /// see rather than something the game refuses to explain.
    private static func taken(
        _ context: inout GraphicsContext, rect: CGRect, colony: ColonyMap
    ) {
        for placement in colony.placements {
            let r = tileRect(placement.coord,
                             size: TileSize(width: placement.width, height: placement.height),
                             colony: colony, rect: rect)
            context.fill(Path(r.insetBy(dx: 0.5, dy: 0.5)),
                         with: .color(Theme.bone.opacity(placement.underConstruction ? 0.06 : 0.12)))
        }
    }

    /// The building as it will actually stand: full footprint, in the colour of
    /// whether it can go there.
    private static func ghost(
        _ context: inout GraphicsContext, rect: CGRect, colony: ColonyMap,
        at coord: TileCoord, footprint: TileSize, fits: Bool
    ) {
        let r = tileRect(coord, size: footprint, colony: colony, rect: rect)
        let tint = fits ? Theme.good : Theme.danger
        context.fill(Path(roundedRect: r.insetBy(dx: 1, dy: 1), cornerRadius: 3),
                     with: .color(tint.opacity(0.22)))
        context.stroke(Path(roundedRect: r.insetBy(dx: 1, dy: 1), cornerRadius: 3),
                       with: .color(tint.opacity(0.95)),
                       style: StrokeStyle(lineWidth: 1.6, dash: fits ? [] : [4, 3]))

        // Corner ticks, so a 3×3 reads as three-by-three at a glance.
        let arm = min(r.width, r.height) * 0.28
        var ticks = Path()
        for (cx, cy, sx, sy) in [(r.minX, r.minY, 1.0, 1.0), (r.maxX, r.minY, -1.0, 1.0),
                                 (r.minX, r.maxY, 1.0, -1.0), (r.maxX, r.maxY, -1.0, -1.0)] {
            ticks.move(to: CGPoint(x: cx + arm * sx, y: cy))
            ticks.addLine(to: CGPoint(x: cx, y: cy))
            ticks.addLine(to: CGPoint(x: cx, y: cy + arm * sy))
        }
        context.stroke(ticks, with: .color(tint), lineWidth: 2)
    }
}
