import SwiftUI
import EndlessFrontierCore

/// The wood and the rock, drawn as the *things they are* rather than as
/// decoration that fades when a number drops.
///
/// The scenery pass fakes this: props near a forest deposit turn to stumps and
/// then vanish as the abstract `amount` falls, so a clearing spreads without
/// anything ever being felled. These draw `map.trees` and `map.rocks` — real
/// entities with an age, a species and their own half-finished axe-work — so
/// what you see standing is what a logger will actually walk to and cut.
///
/// Presentation only: nothing here writes back, and a tree's *position* comes
/// from the simulation while its sway comes from the frame clock.
enum SettlementFlora {

    /// Trees below this growth are drawn as saplings rather than trunks.
    static let saplingGrowth = 0.35

    static func draw(
        _ context: inout GraphicsContext, rect: CGRect, map: LocalMap,
        season: Season, time: Double,
        sun: SettlementLight.Sun = SettlementLight.sun(time: 0),
        registry: GameDataRegistry
    ) {
        let unit = min(rect.width, rect.height)
        let standing = map.trees.sorted(by: { $0.position.y < $1.position.y })
            .filter { map.isExplored($0.position) }
        let outcrops = map.rocks.filter { map.isExplored($0.position) }

        // Every shadow the wood throws, in one path filled once — before any
        // trunk is drawn, so a tree's shadow lies on the ground rather than
        // across the tree standing behind it.
        if sun.strength > 0.01 {
            var shadows = Path()
            for rock in outcrops {
                let s = unit * 0.014 * (0.45 + CGFloat(rock.remaining) * 0.75)
                let c = SettlementRenderer.point(rock.position, in: rect)
                shadows.addPath(SettlementLight.blobShadow(
                    at: CGPoint(x: c.x, y: c.y + s * 0.2), halfWidth: s * 0.72,
                    height: s * 1.1, sun: sun))
            }
            for tree in standing {
                let s = unit * 0.013 * (0.35 + CGFloat(tree.growth) * 0.95)
                let c = SettlementRenderer.point(tree.position, in: rect)
                shadows.addPath(SettlementLight.blobShadow(
                    at: CGPoint(x: c.x, y: c.y + s * 0.1), halfWidth: s * 0.5,
                    height: s * 2.1, sun: sun))
            }
            if !shadows.isEmpty {
                context.fill(shadows, with: .color(SettlementLight.shadowColour(sun)))
            }
        }

        // Rock first: a tree in front of an outcrop should overlap it.
        for rock in outcrops {
            outcrop(&context, rock, at: SettlementRenderer.point(rock.position, in: rect),
                    unit: unit, season: season, registry: registry)
        }
        // Back to front, so nearer trees overlap the ones behind them.
        for tree in standing {
            trunk(&context, tree, at: SettlementRenderer.point(tree.position, in: rect),
                  unit: unit, season: season, time: time, registry: registry)
        }
    }

    // MARK: - Trees

    /// A tree, sized by how grown it is and marked by how far the axe has got.
    private static func trunk(
        _ context: inout GraphicsContext, _ tree: Tree, at c: CGPoint,
        unit: CGFloat, season: Season, time: Double, registry: GameDataRegistry
    ) {
        let growth = CGFloat(tree.growth)
        let s = unit * 0.013 * (0.35 + growth * 0.95)
        // Evergreens keep their leaves; everything else stands bare in winter.
        //
        // Read off the **crown** rather than a list of species names, which is
        // the same fix as the silhouette below it: a needle-bearing shape keeps
        // its needles, whatever the species is called. A new conifer added to
        // `flora.json` is green in January without anybody remembering to add
        // it to a set here.
        let evergreen: Set<FloraDefinition.Crown> = [.conifer, .scrub]
        let bare = season == .winter && !evergreen.contains(tree.crown)
        let wood = Color(red: 0.34, green: 0.26, blue: 0.19)
        let leaf = canopyColour(tree.species, season: season, registry: registry)

        // A slow sway, out of phase per tree so a wood breathes rather than
        // marching. Leaning trees lean the same way every frame.
        let phase = Double(tree.id) * 1.37
        let sway = CGFloat(sin(time * 0.5 + phase)) * s * 0.06

        groundShadow(&context, at: CGPoint(x: c.x, y: c.y + s * 0.1), halfWidth: s * 0.55)

        // The trunk.
        let trunkTop = CGPoint(x: c.x + sway, y: c.y - s * 1.05)
        context.stroke(Path { p in
            p.move(to: CGPoint(x: c.x, y: c.y + s * 0.15))
            p.addQuadCurve(to: trunkTop, control: CGPoint(x: c.x, y: c.y - s * 0.5))
        }, with: .color(wood), style: StrokeStyle(lineWidth: max(0.8, s * 0.22), lineCap: .round))

        // **The crown, not the species.**
        //
        // This switched on the eight species by name, so the five silhouettes
        // the canvas can draw were reachable only by being one of eight enum
        // cases — a ninth kind of tree would have come out as whatever the
        // `default` was. Species are `flora.json` now and each one names the
        // crown it wears, so a generated tree has a real shape on the day it
        // ships (`FloraDefinition.Crown`).
        switch tree.crown {
        case .conifer:
            // A conifer: stacked skirts, narrowing to a point.
            let tiers = tree.growth < saplingGrowth ? 2 : 3
            for tier in 0..<tiers {
                let t = CGFloat(tier) / CGFloat(tiers)
                let y = c.y - s * (0.5 + CGFloat(tier) * 0.62)
                let half = s * (0.82 - t * 0.42)
                let skirt = Path { p in
                    p.move(to: CGPoint(x: c.x - half + sway * t, y: y))
                    p.addLine(to: CGPoint(x: c.x + sway * (t + 0.4), y: y - s * 0.78))
                    p.addLine(to: CGPoint(x: c.x + half + sway * t, y: y))
                    p.closeSubpath()
                }
                context.fill(skirt, with: .color(leaf))
                context.stroke(skirt, with: .color(Theme.bone.opacity(0.30)), lineWidth: 0.5)
            }
        case .broadleaf:
            if bare {
                // Winter: a bare crown of branches, which is why a birch wood
                // reads as winter at a glance.
                for limb in 0..<5 {
                    let a = -.pi / 2 + (Double(limb) - 2) * 0.42
                    context.stroke(Path { p in
                        p.move(to: trunkTop)
                        p.addLine(to: CGPoint(x: trunkTop.x + CGFloat(cos(a)) * s * 0.75,
                                              y: trunkTop.y + CGFloat(sin(a)) * s * 0.75))
                    }, with: .color(wood), lineWidth: max(0.5, s * 0.09))
                }
            } else {
                // A broadleaf crown: three overlapping lobes, so it reads full
                // rather than as a lollipop.
                for lobe in 0..<3 {
                    let dx = CGFloat([-0.42, 0.0, 0.44][lobe]) * s
                    let dy = CGFloat([0.06, -0.34, 0.02][lobe]) * s
                    let r = s * CGFloat([0.62, 0.72, 0.58][lobe])
                    let centre = CGPoint(x: trunkTop.x + dx, y: trunkTop.y + dy)
                    context.fill(
                        Path(ellipseIn: CGRect(x: centre.x - r, y: centre.y - r,
                                               width: r * 2, height: r * 2)),
                        with: .color(leaf))
                }
                context.stroke(
                    Path(ellipseIn: CGRect(x: trunkTop.x - s * 0.86, y: trunkTop.y - s * 0.82,
                                           width: s * 1.72, height: s * 1.5)),
                    with: .color(Theme.bone.opacity(0.26)), lineWidth: 0.5)
            }

        case .scrub:
            // Scrub: wider than it is tall, and it keeps its needles. Drawn low
            // so a tundra reads as a place where nothing grows *up*.
            for tier in 0..<2 {
                let y = c.y - s * (0.25 + CGFloat(tier) * 0.42)
                let half = s * (0.92 - CGFloat(tier) * 0.30)
                let skirt = Path { p in
                    p.move(to: CGPoint(x: c.x - half, y: y))
                    p.addQuadCurve(to: CGPoint(x: c.x + half, y: y),
                                   control: CGPoint(x: c.x + sway, y: y - s * 0.72))
                    p.closeSubpath()
                }
                context.fill(skirt, with: .color(leaf))
                context.stroke(skirt, with: .color(Theme.bone.opacity(0.24)), lineWidth: 0.45)
            }

        case .column:
            // A column. The whole point of a poplar on a canvas this size is
            // the silhouette — tall and narrow, so a line of them along a river
            // reads as a line of them and not as a hedge.
            if bare {
                for limb in 0..<4 {
                    let a = -.pi / 2 + (Double(limb) - 1.5) * 0.16
                    context.stroke(Path { p in
                        p.move(to: CGPoint(x: trunkTop.x, y: trunkTop.y + s * 0.5))
                        p.addLine(to: CGPoint(x: trunkTop.x + CGFloat(cos(a)) * s * 0.9,
                                              y: trunkTop.y + CGFloat(sin(a)) * s * 0.9))
                    }, with: .color(wood), lineWidth: max(0.5, s * 0.08))
                }
            } else {
                let crown = Path { p in
                    p.move(to: CGPoint(x: trunkTop.x - s * 0.34, y: trunkTop.y + s * 0.55))
                    p.addQuadCurve(to: CGPoint(x: trunkTop.x + sway * 0.6, y: trunkTop.y - s * 1.5),
                                   control: CGPoint(x: trunkTop.x - s * 0.5, y: trunkTop.y - s * 0.6))
                    p.addQuadCurve(to: CGPoint(x: trunkTop.x + s * 0.34, y: trunkTop.y + s * 0.55),
                                   control: CGPoint(x: trunkTop.x + s * 0.5, y: trunkTop.y - s * 0.6))
                    p.closeSubpath()
                }
                context.fill(crown, with: .color(leaf))
                context.stroke(crown, with: .color(Theme.bone.opacity(0.24)), lineWidth: 0.5)
            }

        case .weeping:
            // Weeping: a low round crown with strands hanging out of it. Belongs
            // to wet ground, and says so without a label.
            if !bare {
                context.fill(
                    Path(ellipseIn: CGRect(x: trunkTop.x - s * 0.85, y: trunkTop.y - s * 0.55,
                                           width: s * 1.7, height: s * 1.05)),
                    with: .color(leaf))
            }
            for strand in 0..<5 {
                let dx = (CGFloat(strand) - 2) * s * 0.34
                let drop = s * (0.9 + CGFloat(strand % 2) * 0.35)
                context.stroke(Path { p in
                    p.move(to: CGPoint(x: trunkTop.x + dx, y: trunkTop.y + s * 0.1))
                    p.addQuadCurve(to: CGPoint(x: trunkTop.x + dx + sway * 0.5,
                                               y: trunkTop.y + drop),
                                   control: CGPoint(x: trunkTop.x + dx + s * 0.16,
                                                    y: trunkTop.y + drop * 0.5))
                }, with: .color(bare ? wood : leaf), lineWidth: max(0.4, s * 0.08))
            }
        }

        // The axe, if anyone has started: a wedge cut out of the trunk, deeper
        // as the work goes on. This is the visible half of work being banked in
        // the tree rather than in the colonist.
        guard tree.chopped > 0.02 else { return }
        let bite = s * 0.42 * CGFloat(min(1, tree.chopped))
        context.fill(Path { p in
            p.move(to: CGPoint(x: c.x - s * 0.14, y: c.y - s * 0.05))
            p.addLine(to: CGPoint(x: c.x - s * 0.14 + bite, y: c.y - s * 0.22))
            p.addLine(to: CGPoint(x: c.x - s * 0.14 + bite, y: c.y + s * 0.10))
            p.closeSubpath()
        }, with: .color(Color(red: 0.78, green: 0.68, blue: 0.50)))
    }

    /// The colour of a canopy, out of `scenery.json`.
    ///
    /// The rule that made this switch worth reading is now a property of each
    /// tree rather than a case in a table: a broadleaf states what it turns to
    /// in autumn and an evergreen states nothing, so the wood changes *around*
    /// the conifers instead of all at once. Adding a species is an entry and a
    /// drawing routine, not a third place to remember.
    private static func canopyColour(_ species: String, season: Season,
                                     registry: GameDataRegistry) -> Color {
        let (r, g, b) = registry.scenery(species).colour(in: season)
        return Color(red: r, green: g, blue: b)
    }

    // MARK: - Rock

    /// An outcrop, visibly eaten into as it is worked out. A spent one stays —
    /// a worked-out quarry is a feature of the ground, not a hole in the save.
    private static func outcrop(
        _ context: inout GraphicsContext, _ rock: Rock, at c: CGPoint,
        unit: CGFloat, season: Season, registry: GameDataRegistry
    ) {
        let left = CGFloat(rock.remaining)
        let s = unit * 0.014 * (0.45 + left * 0.75)
        // `SettlementStone` owns what a rock is coloured, for every rock. This
        // used to be a private copy that answered a *different* grey (granite
        // 0.34 against 0.34) and took no season at all — and the renderer draws
        // both files one line apart, so a stone massif and an outcrop of the
        // same granite stood side by side in two shades, and only the massif
        // went pale under snow. The snow cap below is an outcrop's own detail
        // and stays; the body is not its to decide.
        let body = SettlementStone.stoneColour(rock.kind, season: season, registry: registry)

        groundShadow(&context, at: CGPoint(x: c.x, y: c.y + s * 0.2), halfWidth: s * 0.8)

        // A blocky mass, faceted rather than a blob. The facets are fixed per
        // rock id, so an outcrop keeps its shape between frames.
        var h = UInt64(bitPattern: Int64(rock.id)) &* 0x9E37_79B9_7F4A_7C15
        func roll() -> CGFloat {
            h ^= h >> 33; h = h &* 0xFF51_AFD7_ED55_8CCD
            return CGFloat(Double((h >> 40) & 0xFFFF) / 65535)
        }
        let mass = Path { p in
            let points = 6
            for i in 0..<points {
                let a = Double(i) / Double(points) * 2 * .pi - .pi / 2
                let r = s * (0.6 + roll() * 0.5)
                let pt = CGPoint(x: c.x + CGFloat(cos(a)) * r,
                                 y: c.y + CGFloat(sin(a)) * r * 0.72)
                i == 0 ? p.move(to: pt) : p.addLine(to: pt)
            }
            p.closeSubpath()
        }
        context.fill(mass, with: .color(body))
        context.stroke(mass, with: .color(Theme.bone.opacity(0.42)), lineWidth: 0.7)

        // A worked face: the flat, bright scar where it has been cut into.
        if left < 0.92 {
            context.fill(Path { p in
                p.move(to: CGPoint(x: c.x - s * 0.1, y: c.y - s * 0.55))
                p.addLine(to: CGPoint(x: c.x + s * 0.62, y: c.y - s * 0.2))
                p.addLine(to: CGPoint(x: c.x + s * 0.5, y: c.y + s * 0.42))
                p.addLine(to: CGPoint(x: c.x - s * 0.1, y: c.y + s * 0.2))
                p.closeSubpath()
            }, with: .color(body.opacity(0.55)))
        }
        // An ore seam still shows what it is worth.
        if rock.kind == .ironSeam, left > 0.05 {
            context.stroke(Path { p in
                p.move(to: CGPoint(x: c.x - s * 0.4, y: c.y + s * 0.12))
                p.addLine(to: CGPoint(x: c.x + s * 0.34, y: c.y - s * 0.24))
            }, with: .color(Color(red: 0.62, green: 0.44, blue: 0.28)), lineWidth: max(0.8, s * 0.16))
        }
        if season == .winter {
            // A cap of snow on the top facets.
            context.fill(Path { p in
                p.move(to: CGPoint(x: c.x - s * 0.5, y: c.y - s * 0.28))
                p.addQuadCurve(to: CGPoint(x: c.x + s * 0.5, y: c.y - s * 0.26),
                               control: CGPoint(x: c.x, y: c.y - s * 0.72))
                p.closeSubpath()
            }, with: .color(Theme.bone.opacity(0.34)))
        }
    }

    /// The dark right at the foot of a thing — contact, not cast. The long
    /// shadow is `SettlementLight`'s job and swings with the sun; this one is
    /// always there, including at midnight, and is what keeps a trunk from
    /// looking like a sticker.
    private static func groundShadow(
        _ context: inout GraphicsContext, at c: CGPoint, halfWidth: CGFloat
    ) {
        context.fill(
            Path(ellipseIn: CGRect(x: c.x - halfWidth, y: c.y - halfWidth * 0.26,
                                   width: halfWidth * 2, height: halfWidth * 0.52)),
            with: .color(.black.opacity(0.15)))
    }
}
