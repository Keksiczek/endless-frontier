import SwiftUI
import EndlessFrontierCore

/// **What grows and what lies about** — trees, rocks, reeds, the sea.
///
/// `drawProp` is the long one and deliberately so: it is the single switch over
/// every kind of thing that stands on the ground, and a prop drawn in two
/// places is a prop that drifts (rule 92). It is the next seam if this file
/// grows again.
extension SettlementRenderer {
    static func scenery(
        _ context: inout GraphicsContext, rect: CGRect, map: LocalMap, season: Season
    ) {
        for prop in map.scenery where map.isExplored(prop.position) {
            let c = point(prop.position, in: rect)
            let s = CGFloat(prop.scale) * min(rect.width, rect.height) * 0.012
            // The land is stock, not wallpaper: trees standing near a forest
            // deposit are *that forest* — as the loggers eat it, they come
            // down (stump first, then bare ground). Rocks near a quarry
            // shrink the same way. Which prop falls first is stable per prop,
            // so the clearing spreads instead of flickering.
            var kind = prop.kind
            var size = s
            if kind == .tree || kind == .pine {
                if let fraction = nearestNodeFraction(map: map, kind: .forest, to: prop.position) {
                    // A wood that has real trees in it draws those instead —
                    // otherwise the same copse is drawn twice, once as standing
                    // stock and once as furniture that only pretends to be cut.
                    if !map.trees.isEmpty { continue }
                    let threshold = propRoll(prop.id)
                    if fraction < threshold * 0.5 { continue }        // felled and hauled
                    if fraction < threshold * 0.9 { kind = .stump }   // fresh-cut
                }
            } else if kind == .rock || kind == .boulder {
                if let fraction = nearestNodeFraction(map: map, kind: .stone, to: prop.position) {
                    if !map.rocks.isEmpty { continue }
                    let threshold = propRoll(prop.id)
                    if fraction < threshold * 0.4 { continue }        // quarried away
                    size *= CGFloat(0.6 + fraction * 0.4)             // being cut down
                }
            }
            drawProp(kind, at: c, s: size, season: season, context: &context)
        }
    }

    /// How full the nearest deposit of a kind is around a point (within a
    /// working radius), or nil if none is close enough to claim the prop.
    static func nearestNodeFraction(
        map: LocalMap, kind: LocalResourceKind, to position: LocalPoint
    ) -> Double? {
        var best: (d2: Double, fraction: Double)?
        for node in map.nodes where node.kind == kind {
            let dx = node.position.x - position.x
            let dy = node.position.y - position.y
            let d2 = dx * dx + dy * dy
            if d2 < 0.045 * 0.045 * 16, d2 < (best?.d2 ?? .infinity) {   // ~0.18 reach
                best = (d2, node.capacity > 0 ? node.amount / node.capacity : 1)
            }
        }
        return best?.fraction
    }

    /// A stable 0.35…0.95 roll per prop — the order the clearing takes them.
    static func propRoll(_ id: Int) -> Double {
        var h = UInt64(bitPattern: Int64(id)) &* 0x9E37_79B9_7F4A_7C15
        h ^= h >> 29
        return 0.35 + Double(h % 1000) / 1000 * 0.6
    }

    /// The deciduous canopy through the year.
    static func canopyColor(_ season: Season) -> Color {
        switch season {
        case .spring: return Color(red: 0.44, green: 0.62, blue: 0.42)
        case .summer: return Color(red: 0.38, green: 0.55, blue: 0.40)
        case .autumn: return Color(red: 0.72, green: 0.50, blue: 0.28)
        case .winter: return Color(red: 0.50, green: 0.52, blue: 0.56)
        }
    }

    static func drawProp(
        _ kind: SceneryKind, at c: CGPoint, s: CGFloat, season: Season,
        context: inout GraphicsContext
    ) {
        switch kind {
        case .tree:
            // A shadow, a filled trunk, and a lobed canopy with real mass —
            // not an outline the terrain shows straight through.
            context.fill(Path(ellipseIn: CGRect(x: c.x - s * 0.85, y: c.y + s * 0.72,
                                                width: s * 1.7, height: s * 0.5)),
                         with: .color(Theme.ink.opacity(0.20)))
            context.fill(Path { p in
                p.move(to: CGPoint(x: c.x - s * 0.15, y: c.y + s * 0.9))
                p.addLine(to: CGPoint(x: c.x - s * 0.06, y: c.y - s * 0.1))
                p.addLine(to: CGPoint(x: c.x + s * 0.06, y: c.y - s * 0.1))
                p.addLine(to: CGPoint(x: c.x + s * 0.15, y: c.y + s * 0.9))
                p.closeSubpath()
            }, with: .color(Color(red: 0.34, green: 0.27, blue: 0.20)))
            if season == .winter {
                // Bare branches instead of a canopy.
                context.stroke(Path { p in
                    p.move(to: CGPoint(x: c.x, y: c.y + s * 0.2))
                    p.addLine(to: CGPoint(x: c.x - s * 0.7, y: c.y - s * 1.0))
                    p.move(to: CGPoint(x: c.x, y: c.y - s * 0.1))
                    p.addLine(to: CGPoint(x: c.x + s * 0.65, y: c.y - s * 1.15))
                    p.move(to: CGPoint(x: c.x, y: c.y - s * 0.4))
                    p.addLine(to: CGPoint(x: c.x - s * 0.3, y: c.y - s * 1.4))
                }, with: .color(Color(red: 0.34, green: 0.27, blue: 0.20)), lineWidth: 0.9)
            } else {
                let canopy = canopyColor(season)
                let lobes: [(CGFloat, CGFloat, CGFloat)] =
                    [(-0.5, -0.75, 0.8), (0.5, -0.8, 0.78), (0, -1.25, 0.92)]
                for (dx, dy, r) in lobes {
                    context.fill(Path(ellipseIn: CGRect(x: c.x + dx * s - r * s, y: c.y + dy * s - r * s,
                                                        width: r * s * 2, height: r * s * 2)),
                                 with: .color(canopy))
                }
                // A sunlit highlight on the crown gives the foliage form.
                context.fill(Path(ellipseIn: CGRect(x: c.x - s * 0.55, y: c.y - s * 1.55,
                                                    width: s * 0.7, height: s * 0.7)),
                             with: .color(.white.opacity(0.12)))
                if season == .autumn {
                    for i in 0..<3 {
                        let lx = c.x + CGFloat(i - 1) * s * 0.5
                        context.fill(Path(ellipseIn: CGRect(x: lx, y: c.y + s * 0.8,
                                                            width: 1.6, height: 1.1)),
                                     with: .color(canopy.opacity(0.8)))
                    }
                }
            }
        case .pine:
            let pine = season == .winter
                ? Color(red: 0.36, green: 0.46, blue: 0.44)
                : Color(red: 0.28, green: 0.44, blue: 0.33)
            context.fill(Path(ellipseIn: CGRect(x: c.x - s * 0.7, y: c.y + s * 0.78,
                                                width: s * 1.4, height: s * 0.42)),
                         with: .color(Theme.ink.opacity(0.20)))
            context.fill(Path(CGRect(x: c.x - s * 0.09, y: c.y + s * 0.45,
                                     width: s * 0.18, height: s * 0.65)),
                         with: .color(Color(red: 0.32, green: 0.25, blue: 0.19)))
            for tier in 0..<3 {
                let t = CGFloat(tier)
                let top = c.y - s * 1.4 + t * s * 0.55
                let w = s * (0.42 + t * 0.3)
                context.fill(Path { p in
                    p.move(to: CGPoint(x: c.x - w, y: top + s * 0.58))
                    p.addLine(to: CGPoint(x: c.x, y: top))
                    p.addLine(to: CGPoint(x: c.x + w, y: top + s * 0.58))
                    p.closeSubpath()
                }, with: .color(pine.opacity(1 - t * 0.08)))
            }
            if season == .winter {
                // Snow settled on the crown.
                context.fill(Path { p in
                    p.move(to: CGPoint(x: c.x - s * 0.32, y: c.y - s * 0.95))
                    p.addLine(to: CGPoint(x: c.x, y: c.y - s * 1.4))
                    p.addLine(to: CGPoint(x: c.x + s * 0.32, y: c.y - s * 0.95))
                    p.closeSubpath()
                }, with: .color(.white.opacity(0.5)))
            }
        case .bush:
            context.fill(Path(ellipseIn: CGRect(x: c.x - s * 0.7, y: c.y + s * 0.32,
                                                width: s * 1.4, height: s * 0.34)),
                         with: .color(Theme.ink.opacity(0.16)))
            let bushC = canopyColor(season)
            let lobes: [(CGFloat, CGFloat, CGFloat)] = [(-0.4, 0, 0.55), (0.4, 0, 0.55), (0, -0.2, 0.66)]
            for (dx, dy, r) in lobes {
                context.fill(Path(ellipseIn: CGRect(x: c.x + dx * s - r * s, y: c.y + dy * s - r * s,
                                                    width: r * s * 2, height: r * s * 2)),
                             with: .color(bushC.opacity(0.92)))
            }
        case .rock:
            context.fill(Path(ellipseIn: CGRect(x: c.x - s * 0.6, y: c.y + s * 0.3,
                                                width: s * 1.2, height: s * 0.3)),
                         with: .color(Theme.ink.opacity(0.18)))
            let face = Path { p in
                p.move(to: CGPoint(x: c.x - s * 0.5, y: c.y + s * 0.4))
                p.addLine(to: CGPoint(x: c.x - s * 0.2, y: c.y - s * 0.4))
                p.addLine(to: CGPoint(x: c.x + s * 0.4, y: c.y - s * 0.25))
                p.addLine(to: CGPoint(x: c.x + s * 0.55, y: c.y + s * 0.4))
                p.closeSubpath()
            }
            context.fill(face, with: .color(Color(red: 0.55, green: 0.57, blue: 0.61)))
            // A shaded facet turns the flat stone into a solid.
            context.fill(Path { p in
                p.move(to: CGPoint(x: c.x - s * 0.2, y: c.y - s * 0.4))
                p.addLine(to: CGPoint(x: c.x + s * 0.4, y: c.y - s * 0.25))
                p.addLine(to: CGPoint(x: c.x + s * 0.55, y: c.y + s * 0.4))
                p.closeSubpath()
            }, with: .color(Color(red: 0.42, green: 0.44, blue: 0.48)))
            context.stroke(face, with: .color(Color(red: 0.70, green: 0.72, blue: 0.76).opacity(0.5)), lineWidth: 0.6)
        case .boulder:
            context.fill(Path(ellipseIn: CGRect(x: c.x - s * 0.95, y: c.y + s * 0.5,
                                                width: s * 1.9, height: s * 0.4)),
                         with: .color(Theme.ink.opacity(0.2)))
            let boulder = Path { p in
                p.move(to: CGPoint(x: c.x - s * 0.9, y: c.y + s * 0.7))
                p.addLine(to: CGPoint(x: c.x - s * 0.5, y: c.y - s * 0.6))
                p.addLine(to: CGPoint(x: c.x + s * 0.3, y: c.y - s * 0.85))
                p.addLine(to: CGPoint(x: c.x + s * 0.95, y: c.y + s * 0.2))
                p.addLine(to: CGPoint(x: c.x + s * 0.6, y: c.y + s * 0.7))
                p.closeSubpath()
            }
            context.fill(boulder, with: .color(Color(red: 0.50, green: 0.52, blue: 0.57)))
            context.fill(Path { p in
                p.move(to: CGPoint(x: c.x + s * 0.3, y: c.y - s * 0.85))
                p.addLine(to: CGPoint(x: c.x + s * 0.95, y: c.y + s * 0.2))
                p.addLine(to: CGPoint(x: c.x + s * 0.6, y: c.y + s * 0.7))
                p.closeSubpath()
            }, with: .color(Color(red: 0.38, green: 0.40, blue: 0.45)))
            context.stroke(boulder, with: .color(Color(red: 0.66, green: 0.68, blue: 0.72).opacity(0.45)), lineWidth: 0.7)
        case .flowers:
            // Blooms in spring and summer; bare stems otherwise.
            let blooming = season == .spring || season == .summer
            let bloom = season == .spring
                ? Color(red: 0.85, green: 0.70, blue: 0.75)
                : Color(red: 0.84, green: 0.76, blue: 0.52)
            for i in 0..<4 {
                let a = Double(i) * 1.9
                let px = c.x + CGFloat(cos(a)) * s * 0.6
                let py = c.y + CGFloat(sin(a)) * s * 0.4
                context.stroke(Path { p in
                    p.move(to: CGPoint(x: px, y: py + s * 0.4))
                    p.addLine(to: CGPoint(x: px, y: py))
                }, with: .color(Color(red: 0.42, green: 0.54, blue: 0.42)), lineWidth: 0.8)
                if blooming {
                    context.fill(Path(ellipseIn: CGRect(x: px - 1, y: py - 1.6, width: 2, height: 2)),
                                 with: .color(bloom))
                }
            }
        case .reeds:
            let reed = Color(red: 0.54, green: 0.62, blue: 0.48)
            for i in 0..<5 {
                let px = c.x + CGFloat(i - 2) * s * 0.28
                let lean = CGFloat(i - 2) * 0.6
                context.stroke(Path { p in
                    p.move(to: CGPoint(x: px, y: c.y + s * 0.6))
                    p.addLine(to: CGPoint(x: px + lean, y: c.y - s * 0.9))
                }, with: .color(reed), lineWidth: 1)
            }
        case .stump:
            context.stroke(Path(CGRect(x: c.x - s * 0.4, y: c.y - s * 0.2,
                                       width: s * 0.8, height: s * 0.5)),
                           with: .color(Color(red: 0.44, green: 0.36, blue: 0.28)), lineWidth: 1)
        case .pond:
            let water = season == .winter
                ? Color(red: 0.60, green: 0.70, blue: 0.80)
                : Color(red: 0.32, green: 0.46, blue: 0.56)
            context.fill(Path(ellipseIn: CGRect(x: c.x - s * 1.3, y: c.y - s * 0.7,
                                                width: s * 2.6, height: s * 1.4)),
                         with: .color(water.opacity(0.35)))
            context.stroke(Path(ellipseIn: CGRect(x: c.x - s * 1.3, y: c.y - s * 0.7,
                                                  width: s * 2.6, height: s * 1.4)),
                           with: .color(water), lineWidth: 1)
        case .cactus:
            let green = Color(red: 0.46, green: 0.60, blue: 0.46)
            context.stroke(Path { p in
                p.move(to: CGPoint(x: c.x, y: c.y + s * 0.9))
                p.addLine(to: CGPoint(x: c.x, y: c.y - s * 1.1))
                p.move(to: CGPoint(x: c.x, y: c.y - s * 0.2))
                p.addLine(to: CGPoint(x: c.x - s * 0.6, y: c.y - s * 0.2))
                p.addLine(to: CGPoint(x: c.x - s * 0.6, y: c.y - s * 0.7))
                p.move(to: CGPoint(x: c.x, y: c.y - s * 0.5))
                p.addLine(to: CGPoint(x: c.x + s * 0.55, y: c.y - s * 0.5))
                p.addLine(to: CGPoint(x: c.x + s * 0.55, y: c.y - s * 0.95))
            }, with: .color(green), style: StrokeStyle(lineWidth: 1.2, lineCap: .round))
        case .snowdrift:
            context.fill(Path { p in
                p.move(to: CGPoint(x: c.x - s, y: c.y + s * 0.35))
                p.addQuadCurve(to: CGPoint(x: c.x + s, y: c.y + s * 0.35),
                               control: CGPoint(x: c.x, y: c.y - s * 0.6))
                p.closeSubpath()
            }, with: .color(Color(red: 0.74, green: 0.80, blue: 0.88).opacity(0.32)))
        case .ruinPillar:
            context.stroke(Path(CGRect(x: c.x - s * 0.25, y: c.y - s * 1.1,
                                       width: s * 0.5, height: s * 1.5)),
                           with: .color(Theme.boneDim), lineWidth: 1)

        case .cliff:
            // A face with a lit top edge and a deep shadow at its foot, so it
            // reads as ground you could not walk up.
            let face = Path { p in
                p.move(to: CGPoint(x: c.x - s * 1.3, y: c.y + s * 0.7))
                p.addLine(to: CGPoint(x: c.x - s * 0.9, y: c.y - s * 0.9))
                p.addLine(to: CGPoint(x: c.x + s * 0.3, y: c.y - s * 1.1))
                p.addLine(to: CGPoint(x: c.x + s * 1.3, y: c.y - s * 0.3))
                p.addLine(to: CGPoint(x: c.x + s * 1.1, y: c.y + s * 0.7))
                p.closeSubpath()
            }
            context.fill(face, with: .color(Color(red: 0.30, green: 0.29, blue: 0.31)))
            context.stroke(Path { p in
                p.move(to: CGPoint(x: c.x - s * 0.9, y: c.y - s * 0.9))
                p.addLine(to: CGPoint(x: c.x + s * 0.3, y: c.y - s * 1.1))
                p.addLine(to: CGPoint(x: c.x + s * 1.3, y: c.y - s * 0.3))
            }, with: .color(Theme.bone.opacity(0.5)), lineWidth: 1)
            // Strata, and the dark at the base.
            for band in 1...2 {
                let y = c.y - s * 0.6 + CGFloat(band) * s * 0.45
                context.stroke(Path { p in
                    p.move(to: CGPoint(x: c.x - s * 1.1, y: y))
                    p.addLine(to: CGPoint(x: c.x + s * 1.1, y: y))
                }, with: .color(.black.opacity(0.22)), lineWidth: 0.7)
            }
            context.fill(Path(ellipseIn: CGRect(x: c.x - s * 1.2, y: c.y + s * 0.5,
                                                width: s * 2.4, height: s * 0.45)),
                         with: .color(.black.opacity(0.25)))

        case .crag:
            // A spire — two jagged teeth, the taller one lit down one side.
            let spire = Path { p in
                p.move(to: CGPoint(x: c.x - s * 0.8, y: c.y + s * 0.7))
                p.addLine(to: CGPoint(x: c.x - s * 0.2, y: c.y - s * 1.4))
                p.addLine(to: CGPoint(x: c.x + s * 0.25, y: c.y - s * 0.2))
                p.addLine(to: CGPoint(x: c.x + s * 0.6, y: c.y - s * 0.95))
                p.addLine(to: CGPoint(x: c.x + s * 0.95, y: c.y + s * 0.7))
                p.closeSubpath()
            }
            context.fill(spire, with: .color(Color(red: 0.33, green: 0.32, blue: 0.35)))
            context.stroke(spire, with: .color(Theme.bone.opacity(0.42)), lineWidth: 0.8)

        case .dune:
            // A long low ridge with a bright windward face.
            let ridge = Path { p in
                p.move(to: CGPoint(x: c.x - s * 1.5, y: c.y + s * 0.45))
                p.addQuadCurve(to: CGPoint(x: c.x + s * 1.5, y: c.y + s * 0.45),
                               control: CGPoint(x: c.x + s * 0.3, y: c.y - s * 0.85))
                p.closeSubpath()
            }
            context.fill(ridge, with: .color(Color(red: 0.66, green: 0.57, blue: 0.38).opacity(0.5)))
            context.stroke(Path { p in
                p.move(to: CGPoint(x: c.x - s * 1.5, y: c.y + s * 0.45))
                p.addQuadCurve(to: CGPoint(x: c.x + s * 1.5, y: c.y + s * 0.45),
                               control: CGPoint(x: c.x + s * 0.3, y: c.y - s * 0.85))
            }, with: .color(Theme.bone.opacity(0.3)), lineWidth: 0.7)

        case .deadTree:
            // A bare snag: a pale forked trunk, no crown at all.
            let bone = Color(red: 0.62, green: 0.58, blue: 0.50)
            context.stroke(Path { p in
                p.move(to: CGPoint(x: c.x, y: c.y + s * 0.7))
                p.addLine(to: CGPoint(x: c.x - s * 0.1, y: c.y - s * 1.2))
                p.move(to: CGPoint(x: c.x - s * 0.08, y: c.y - s * 0.5))
                p.addLine(to: CGPoint(x: c.x + s * 0.7, y: c.y - s * 1.0))
                p.move(to: CGPoint(x: c.x - s * 0.09, y: c.y - s * 0.85))
                p.addLine(to: CGPoint(x: c.x - s * 0.75, y: c.y - s * 1.25))
            }, with: .color(bone), lineWidth: max(0.7, s * 0.16))

        case .tallGrass:
            // Tufts leaning one way, so a meadow has a wind in it.
            for blade in 0..<5 {
                let dx = (CGFloat(blade) - 2) * s * 0.32
                context.stroke(Path { p in
                    p.move(to: CGPoint(x: c.x + dx, y: c.y + s * 0.5))
                    p.addQuadCurve(to: CGPoint(x: c.x + dx + s * 0.42, y: c.y - s * 0.75),
                                   control: CGPoint(x: c.x + dx, y: c.y - s * 0.2))
                }, with: .color(Color(red: 0.44, green: 0.52, blue: 0.30).opacity(0.75)),
                   lineWidth: 0.8)
            }

        case .mushroom:
            // A little cluster in the leaf litter.
            for (dx, scale) in [(-0.45, 0.8), (0.0, 1.0), (0.4, 0.65)] {
                let m = CGPoint(x: c.x + CGFloat(dx) * s, y: c.y + s * 0.35)
                let r = s * 0.42 * CGFloat(scale)
                context.stroke(Path { p in
                    p.move(to: CGPoint(x: m.x, y: m.y))
                    p.addLine(to: CGPoint(x: m.x, y: m.y - r * 0.9))
                }, with: .color(Theme.bone.opacity(0.55)), lineWidth: 0.7)
                context.fill(Path { p in
                    p.move(to: CGPoint(x: m.x - r, y: m.y - r * 0.85))
                    p.addQuadCurve(to: CGPoint(x: m.x + r, y: m.y - r * 0.85),
                                   control: CGPoint(x: m.x, y: m.y - r * 2.1))
                    p.closeSubpath()
                }, with: .color(Color(red: 0.60, green: 0.34, blue: 0.28)))
            }

        case .driftwood:
            // Bleached wood above the tideline, lying down.
            context.stroke(Path { p in
                p.move(to: CGPoint(x: c.x - s * 1.1, y: c.y + s * 0.3))
                p.addQuadCurve(to: CGPoint(x: c.x + s * 1.1, y: c.y + s * 0.05),
                               control: CGPoint(x: c.x, y: c.y - s * 0.3))
            }, with: .color(Color(red: 0.68, green: 0.64, blue: 0.57)),
               style: StrokeStyle(lineWidth: max(1, s * 0.28), lineCap: .round))
            context.stroke(Path { p in
                p.move(to: CGPoint(x: c.x + s * 0.3, y: c.y + s * 0.1))
                p.addLine(to: CGPoint(x: c.x + s * 0.8, y: c.y - s * 0.5))
            }, with: .color(Color(red: 0.68, green: 0.64, blue: 0.57)), lineWidth: max(0.7, s * 0.16))

        case .hotSpring:
            // Steaming water in a rim of mineral stone.
            context.fill(Path(ellipseIn: CGRect(x: c.x - s * 0.9, y: c.y - s * 0.4,
                                                width: s * 1.8, height: s * 0.9)),
                         with: .color(Color(red: 0.76, green: 0.72, blue: 0.60).opacity(0.5)))
            context.fill(Path(ellipseIn: CGRect(x: c.x - s * 0.62, y: c.y - s * 0.26,
                                                width: s * 1.24, height: s * 0.6)),
                         with: .color(Color(red: 0.34, green: 0.62, blue: 0.66).opacity(0.8)))
            for wisp in 0..<2 {
                let dx = CGFloat(wisp) * s * 0.4 - s * 0.2
                context.stroke(Path { p in
                    p.move(to: CGPoint(x: c.x + dx, y: c.y - s * 0.35))
                    p.addQuadCurve(to: CGPoint(x: c.x + dx + s * 0.2, y: c.y - s * 1.2),
                                   control: CGPoint(x: c.x + dx - s * 0.3, y: c.y - s * 0.8))
                }, with: .color(Theme.bone.opacity(0.22)), lineWidth: 0.8)
            }

        case .fallenLog:
            // A trunk lying across the litter, with the pale end-grain showing
            // at the near end — that circle is the whole read: without it a log
            // is a brown bar and could be anything.
            let bark = Color(red: 0.36, green: 0.28, blue: 0.20)
            context.fill(Path(ellipseIn: CGRect(x: c.x - s * 1.3, y: c.y + s * 0.18,
                                                width: s * 2.6, height: s * 0.34)),
                         with: .color(.black.opacity(0.20)))
            context.fill(Path(roundedRect: CGRect(x: c.x - s * 1.25, y: c.y - s * 0.28,
                                                  width: s * 2.5, height: s * 0.56),
                              cornerRadius: s * 0.26), with: .color(bark))
            context.fill(Path(ellipseIn: CGRect(x: c.x + s * 1.02, y: c.y - s * 0.28,
                                                width: s * 0.42, height: s * 0.56)),
                         with: .color(Color(red: 0.62, green: 0.51, blue: 0.36)))
            // A couple of stubs where branches broke off.
            for stub in [-0.5, 0.35] as [CGFloat] {
                context.stroke(Path { p in
                    p.move(to: CGPoint(x: c.x + stub * s, y: c.y - s * 0.2))
                    p.addLine(to: CGPoint(x: c.x + stub * s + s * 0.18, y: c.y - s * 0.62))
                }, with: .color(bark), lineWidth: 0.9)
            }

        case .cairn:
            // Stacked stones, biggest at the bottom. Man-made, so the stones
            // sit square rather than scattered — that is the whole difference
            // between this and a pile of rocks.
            let stone = Color(red: 0.46, green: 0.45, blue: 0.44)
            context.fill(Path(ellipseIn: CGRect(x: c.x - s * 0.8, y: c.y + s * 0.5,
                                                width: s * 1.6, height: s * 0.3)),
                         with: .color(.black.opacity(0.22)))
            for (i, w) in [0.82, 0.60, 0.42, 0.26].enumerated() {
                let y = c.y + s * (0.42 - CGFloat(i) * 0.38)
                context.fill(Path(roundedRect: CGRect(x: c.x - s * CGFloat(w), y: y - s * 0.2,
                                                      width: s * CGFloat(w) * 2, height: s * 0.36),
                                  cornerRadius: s * 0.08),
                             with: .color(stone.opacity(0.92 - Double(i) * 0.06)))
            }

        case .standingStone:
            // A menhir: tall, leaning a little, lit down one edge. Older than
            // anything the colony has built, and drawn to say so.
            let lean = s * 0.16
            let slab = Path { p in
                p.move(to: CGPoint(x: c.x - s * 0.42, y: c.y + s * 0.75))
                p.addLine(to: CGPoint(x: c.x - s * 0.30 + lean, y: c.y - s * 1.55))
                p.addLine(to: CGPoint(x: c.x + s * 0.26 + lean, y: c.y - s * 1.62))
                p.addLine(to: CGPoint(x: c.x + s * 0.44, y: c.y + s * 0.75))
                p.closeSubpath()
            }
            context.fill(Path(ellipseIn: CGRect(x: c.x - s * 0.7, y: c.y + s * 0.62,
                                                width: s * 1.4, height: s * 0.3)),
                         with: .color(.black.opacity(0.26)))
            context.fill(slab, with: .color(Color(red: 0.40, green: 0.39, blue: 0.40)))
            context.stroke(Path { p in
                p.move(to: CGPoint(x: c.x - s * 0.30 + lean, y: c.y - s * 1.55))
                p.addLine(to: CGPoint(x: c.x - s * 0.42, y: c.y + s * 0.75))
            }, with: .color(Theme.bone.opacity(0.40)), lineWidth: 0.8)

        case .brambles:
            // A low tangle: arcs crossing each other, with berries on it in
            // the seasons that have them.
            let cane = Color(red: 0.28, green: 0.30, blue: 0.22)
            for k in 0..<4 {
                let dx = (CGFloat(k) - 1.5) * s * 0.44
                context.stroke(Path { p in
                    p.move(to: CGPoint(x: c.x + dx - s * 0.5, y: c.y + s * 0.5))
                    p.addQuadCurve(to: CGPoint(x: c.x + dx + s * 0.55, y: c.y + s * 0.5),
                                   control: CGPoint(x: c.x + dx + CGFloat(k % 2) * s * 0.2,
                                                    y: c.y - s * (0.5 + CGFloat(k % 3) * 0.22)))
                }, with: .color(cane), lineWidth: 0.85)
            }
            if season == .summer || season == .autumn {
                for k in 0..<3 {
                    let bx = c.x + (CGFloat(k) - 1) * s * 0.5
                    context.fill(Path(ellipseIn: CGRect(x: bx - s * 0.09, y: c.y - s * 0.28,
                                                        width: s * 0.18, height: s * 0.18)),
                                 with: .color(Color(red: 0.24, green: 0.10, blue: 0.22)))
                }
            }

        case .anthill:
            // A cone of needles with traffic on it. The dots are the point —
            // a bare mound is a molehill.
            context.fill(Path { p in
                p.move(to: CGPoint(x: c.x - s * 0.78, y: c.y + s * 0.52))
                p.addQuadCurve(to: CGPoint(x: c.x + s * 0.78, y: c.y + s * 0.52),
                               control: CGPoint(x: c.x, y: c.y - s * 1.05))
                p.closeSubpath()
            }, with: .color(Color(red: 0.38, green: 0.30, blue: 0.18)))
            for k in 0..<5 {
                let a = Double(k) * 1.9
                let r = s * (0.2 + CGFloat(k % 3) * 0.16)
                context.fill(Path(ellipseIn: CGRect(
                    x: c.x + CGFloat(cos(a)) * r - s * 0.05,
                    y: c.y + s * 0.2 + CGFloat(sin(a)) * r * 0.4 - s * 0.05,
                    width: s * 0.1, height: s * 0.1)),
                    with: .color(.black.opacity(0.45)))
            }

        case .iceFloe:
            // A flat slab with a cracked, lit rim — read as ice rather than as
            // a pale rock because the top face is bright and the edge is not.
            let slabRect = CGRect(x: c.x - s * 1.05, y: c.y - s * 0.34,
                                  width: s * 2.1, height: s * 0.78)
            context.fill(Path(roundedRect: slabRect, cornerRadius: s * 0.16),
                         with: .color(Color(red: 0.72, green: 0.81, blue: 0.88).opacity(0.85)))
            context.stroke(Path(roundedRect: slabRect, cornerRadius: s * 0.16),
                           with: .color(Color(red: 0.88, green: 0.94, blue: 0.98).opacity(0.8)),
                           lineWidth: 0.8)
            context.stroke(Path { p in
                p.move(to: CGPoint(x: c.x - s * 0.5, y: c.y - s * 0.3))
                p.addLine(to: CGPoint(x: c.x - s * 0.1, y: c.y + s * 0.1))
                p.addLine(to: CGPoint(x: c.x + s * 0.55, y: c.y - s * 0.08))
            }, with: .color(Color(red: 0.45, green: 0.58, blue: 0.70).opacity(0.7)),
            lineWidth: 0.7)
        }
    }

    /// Open water along one edge of a coastal map, with a beach fading into it
    /// and a surf line that breathes.
    ///
    /// A coast used to be a field with a stream through it, exactly like the
    /// plains — the one country whose whole character is the water had none.
    static func sea(
        _ context: inout GraphicsContext, rect: CGRect, shore: ShoreShape?,
        season: Season, time: Double
    ) {
        guard let shore else { return }
        // Walk the coast in steps, so the waterline wanders rather than ruling
        // a straight edge across the map.
        let steps = 64
        func waterPoint(_ t: Double, reach: Double) -> CGPoint {
            let p: LocalPoint
            switch shore.side {
            case .north: p = LocalPoint(x: t, y: reach)
            case .south: p = LocalPoint(x: t, y: 1 - reach)
            case .west:  p = LocalPoint(x: reach, y: t)
            case .east:  p = LocalPoint(x: 1 - reach, y: t)
            }
            return point(p, in: rect)
        }
        func edgePoint(_ t: Double) -> CGPoint { waterPoint(t, reach: 0) }

        // The tide breathes: the whole waterline creeps in and out a little.
        let tide = sin(time * 0.09) * 0.006

        var water = Path()
        water.move(to: edgePoint(0))
        for step in 0...steps {
            let t = Double(step) / Double(steps)
            water.addLine(to: waterPoint(t, reach: shore.reach(at: t) + tide))
        }
        water.addLine(to: edgePoint(1))
        water.closeSubpath()

        let deep = season == .winter
            ? Color(red: 0.13, green: 0.22, blue: 0.30)
            : Color(red: 0.12, green: 0.26, blue: 0.36)
        context.fill(water, with: .color(deep))

        // The shallows: a paler band just inside the waterline.
        var shallow = Path()
        shallow.move(to: waterPoint(0, reach: shore.reach(at: 0) + tide))
        for step in 0...steps {
            let t = Double(step) / Double(steps)
            shallow.addLine(to: waterPoint(t, reach: shore.reach(at: t) + tide))
        }
        for step in stride(from: steps, through: 0, by: -1) {
            let t = Double(step) / Double(steps)
            shallow.addLine(to: waterPoint(t, reach: shore.reach(at: t) + tide - 0.035))
        }
        shallow.closeSubpath()
        context.fill(shallow, with: .color(Color(red: 0.22, green: 0.44, blue: 0.52).opacity(0.55)))

        // Surf, running along the coast rather than sitting still.
        var surf = Path()
        for step in 0...steps {
            let t = Double(step) / Double(steps)
            let foam = shore.reach(at: t) + tide + sin(t * 26 + time * 0.9) * 0.004
            let p = waterPoint(t, reach: foam)
            step == 0 ? surf.move(to: p) : surf.addLine(to: p)
        }
        context.stroke(surf, with: .color(Theme.bone.opacity(0.42)), lineWidth: 1.1)

        if season == .winter {
            // Ice hugging the shore.
            context.stroke(surf, with: .color(Color(red: 0.80, green: 0.86, blue: 0.92).opacity(0.3)),
                           lineWidth: 3)
        }
    }

    // MARK: - Resource deposits

}
