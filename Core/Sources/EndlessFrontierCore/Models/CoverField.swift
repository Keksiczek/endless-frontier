import Foundation

/// **What the world has to say about the line between two people.**
///
/// Combat already has positions in the Core — `SiegeEngine` walks fighters over
/// real ground and decides contact by proximity — so a shot has a *line*, and
/// until now the world had no opinion about it. An archer on the far side of a
/// mesa hit exactly as often as one across an open field.
///
/// This is that opinion, and it is a **field, not a query**. The discipline is
/// the one `ColonyRoute.Occupancy` established when routing was going quadratic
/// (§11.23): asking "what stands at this point" by walking every tree, rock and
/// landform is affordable once and ruinous per sample. So the map is stamped
/// into one flat array of cover fractions, once, and a trace is then a walk
/// along a line of cells.
///
/// Cover itself is derived from height and substance — see `Cover`, which is
/// where the rule lives. This type only knows *where*.
public struct CoverField: Sendable, Equatable {

    private let columns: Int
    private let rows: Int
    /// Cell index → how much of a shot crossing it is stopped, `0…1`.
    private let value: [Double]

    /// An empty field: nothing anywhere stops anything. What a map with no
    /// terrain answers, and what tests that do not care about cover can pass.
    public init() {
        columns = 0
        rows = 0
        value = []
    }

    /// Stamps everything standing on a local map into one grid.
    ///
    /// Linear in the things on the map, and each thing writes the **greater**
    /// of what is already there and its own cover: two bushes on one cell are
    /// one bush's worth of shelter, not two, because cover is a wall and walls
    /// do not add up.
    public init(_ map: LocalMap, colony: ColonyMap? = nil) {
        let columns = LocalMap.gridColumns
        let rows = LocalMap.gridRows
        var grid = [Double](repeating: 0, count: columns * rows)

        func index(of point: LocalPoint) -> Int {
            let column = min(columns - 1, max(0, Int(point.x * Double(columns))))
            let row = min(rows - 1, max(0, Int(point.y * Double(rows))))
            return row * columns + column
        }
        func stamp(_ point: LocalPoint, _ body: Cover.Body) {
            let fraction = Cover.fraction(body.stature, body.substance)
            guard fraction > 0 else { return }
            let cell = index(of: point)
            grid[cell] = max(grid[cell], fraction)
        }

        // The grown things. A sapling is not a trunk yet, so cover grows with
        // the wood — which is the sort of thing that has to fall out of the
        // model rather than being written down twice.
        for tree in map.trees {
            stamp(tree.position, tree.isMature ? tree.species.body : (.knee, .foliage))
        }
        for rock in map.rocks { stamp(rock.position, (.waist, .stone)) }
        for prop in map.scenery { stamp(prop.position, prop.kind.body) }

        // Country. A landform owns cells outright, so it stamps every one of
        // them rather than a point — the walls of a ruin field are spread over
        // its whole extent, which is exactly why a ruin is worth fighting in.
        for landform in map.landforms {
            let body = landform.kind.body
            for cell in landform.cells where cell >= 0 && cell < grid.count {
                let fraction = Cover.fraction(body.stature, body.substance)
                grid[cell] = max(grid[cell], fraction)
            }
        }
        // The massif: solid rock, and total.
        if !map.stone.isEmpty {
            let massif = Cover.fraction(Cover.massif.stature, Cover.massif.substance)
            for row in 0..<rows {
                for column in 0..<columns {
                    let middle = LocalPoint(x: (Double(column) + 0.5) / Double(columns),
                                            y: (Double(row) + 0.5) / Double(rows))
                    guard map.stone.block(at: middle) != nil else { continue }
                    grid[row * columns + column] = max(grid[row * columns + column], massif)
                }
            }
        }
        // …and everything the colony has built. A building is a wall whatever
        // it is: you see the ground floor, and `floors` measures upward and is
        // never drawn (`Cover`).
        if let colony {
            let building = Cover.fraction(Cover.building.stature, Cover.building.substance)
            for placement in colony.placements {
                let width = max(1, placement.width), height = max(1, placement.height)
                for y in placement.coord.y..<(placement.coord.y + height) {
                    for x in placement.coord.x..<(placement.coord.x + width) {
                        let middle = SettlementGeometry.canvasPoint(tileX: x, tileY: y, in: colony)
                        grid[index(of: middle)] = building
                    }
                }
            }
        }
        self.columns = columns
        self.rows = rows
        self.value = grid
    }

    public var isEmpty: Bool { value.isEmpty }

    /// What stands on the cell this point falls in.
    public func at(_ point: LocalPoint) -> Double {
        guard columns > 0, rows > 0 else { return 0 }
        let column = min(columns - 1, max(0, Int(point.x * Double(columns))))
        let row = min(rows - 1, max(0, Int(point.y * Double(rows))))
        return value[row * columns + column]
    }

    /// How much of a shot from `shooter` to `target` the world takes, `0…1`.
    ///
    /// The **greatest** thing on the line, not the sum: three hedges in a row
    /// are one hedge's worth of shelter. A shooter is not blocked by the cell
    /// they are standing in — you shoot *over* your own parapet — and neither
    /// is the target sheltered by their own cell alone, because a defender who
    /// has put a wall at their back has put it in the wrong place.
    public func between(_ shooter: LocalPoint, _ target: LocalPoint) -> Double {
        guard columns > 0, rows > 0 else { return 0 }
        let dx = target.x - shooter.x, dy = target.y - shooter.y
        let span = (dx * dx + dy * dy).squareRoot()
        guard span > 1e-6 else { return 0 }
        // One sample per cell crossed, so a long shot is sampled more finely
        // than a short one and nothing is stepped over.
        let samples = max(2, Int((span * Double(columns)).rounded(.up)))
        let ownCell = cell(of: shooter)
        let targetCell = cell(of: target)
        var worst = 0.0
        for i in 1..<samples {
            let t = Double(i) / Double(samples)
            let here = LocalPoint(x: shooter.x + dx * t, y: shooter.y + dy * t)
            let index = cell(of: here)
            guard index != ownCell, index != targetCell else { continue }
            worst = max(worst, value[index])
            if worst >= 1 { break }
        }
        return worst
    }

    private func cell(of point: LocalPoint) -> Int {
        let column = min(columns - 1, max(0, Int(point.x * Double(columns))))
        let row = min(rows - 1, max(0, Int(point.y * Double(rows))))
        return row * columns + column
    }
}
