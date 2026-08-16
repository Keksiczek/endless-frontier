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
    /// …and which building's footprint put it there, where one did.
    ///
    /// A shot that is stopped has to be able to say **what stopped it**, or
    /// arrows fall out of the sky into a palisade that never notices them —
    /// which is the same dead mechanic as a sword that never dulls (§11.26).
    /// Only buildings are named: nobody repairs a bush.
    private let owner: [UUID?]

    /// An empty field: nothing anywhere stops anything. What a map with no
    /// terrain answers, and what tests that do not care about cover can pass.
    public init() {
        columns = 0
        rows = 0
        value = []
        owner = []
    }

    /// Stamps everything standing on a local map into one grid.
    ///
    /// Linear in the things on the map, and each thing writes the **greater**
    /// of what is already there and its own cover: two bushes on one cell are
    /// one bush's worth of shelter, not two, because cover is a wall and walls
    /// do not add up.
    public init(_ map: LocalMap, colony: ColonyMap? = nil, registry: GameDataRegistry? = nil) {
        let columns = LocalMap.gridColumns
        let rows = LocalMap.gridRows
        var grid = [Double](repeating: 0, count: columns * rows)
        var built = [UUID?](repeating: nil, count: columns * rows)

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
        // …and everything the colony has built, each according to what it is:
        // a palisade is chest-high timber and mortared ramparts are chest-high
        // stone, while anything with a roof on it is total. `floors` measures
        // upward and is never drawn, so it says nothing here (`Cover`).
        if let colony {
            for placement in colony.placements {
                let body = registry.flatMap { r in
                    r.building(placement.definitionID).map { Cover.body(of: $0, registry: r) }
                } ?? Cover.building
                let fraction = Cover.fraction(body.stature, body.substance)
                guard fraction > 0 else { continue }
                let width = max(1, placement.width), height = max(1, placement.height)
                for y in placement.coord.y..<(placement.coord.y + height) {
                    for x in placement.coord.x..<(placement.coord.x + width) {
                        let middle = SettlementGeometry.canvasPoint(tileX: x, tileY: y, in: colony)
                        let cell = index(of: middle)
                        // A building wins its own cells outright even against
                        // a taller tree, because the tree is not standing in
                        // the middle of the granary — the map put it there
                        // before the colony did.
                        grid[cell] = fraction
                        built[cell] = placement.id
                    }
                }
            }
        }
        self.columns = columns
        self.rows = rows
        self.value = grid
        self.owner = built
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
        struck(shooter, target).fraction
    }

    /// The same trace, and **what it ran into** — a placement id when the thing
    /// on the line was something the colony built, `nil` when it was a tree, a
    /// boulder or the old walls.
    ///
    /// A shot has to know this to be worth stopping: an arrow that thuds into a
    /// palisade should mark the palisade, and a palisade that soaks a hundred
    /// raids without a scratch is a mechanic with nothing at stake in it.
    public func struck(_ shooter: LocalPoint, _ target: LocalPoint) -> (fraction: Double, building: UUID?) {
        guard columns > 0, rows > 0 else { return (0, nil) }
        let dx = target.x - shooter.x, dy = target.y - shooter.y
        let span = (dx * dx + dy * dy).squareRoot()
        guard span > 1e-6 else { return (0, nil) }
        // One sample per cell crossed, so a long shot is sampled more finely
        // than a short one and nothing is stepped over.
        let samples = max(2, Int((span * Double(columns)).rounded(.up)))
        let ownCell = cell(of: shooter)
        let targetCell = cell(of: target)
        var worst = 0.0
        var hit: UUID?
        for i in 1..<samples {
            let t = Double(i) / Double(samples)
            let here = LocalPoint(x: shooter.x + dx * t, y: shooter.y + dy * t)
            let index = cell(of: here)
            guard index != ownCell, index != targetCell else { continue }
            guard value[index] > worst else { continue }
            worst = value[index]
            hit = owner[index]
            if worst >= 1 { break }
        }
        return (worst, hit)
    }

    /// What a person at `defender` has between them and somebody swinging at
    /// them from `attacker`.
    ///
    /// `struck` cannot answer this and must not be asked to: two people in
    /// contact are inside one cell of each other, so the line between them
    /// crosses nothing and every fight at the wall would read as fought in the
    /// open. What matters at arm's length is the **parapet at your shoulder** —
    /// the ground immediately on the attacker's side of you — so that is what
    /// is sampled, one cell out and half a cell out, whichever is better.
    ///
    /// This is the number that makes "hold the line at the palisade" mean
    /// standing *at the palisade* rather than standing within a radius of the
    /// middle of town.
    public func shelter(at defender: LocalPoint, from attacker: LocalPoint) -> (fraction: Double, building: UUID?) {
        guard columns > 0, rows > 0 else { return (0, nil) }
        let dx = attacker.x - defender.x, dy = attacker.y - defender.y
        let span = (dx * dx + dy * dy).squareRoot()
        guard span > 1e-6 else { return (0, nil) }
        // The cells are wider than they are tall (40 × 25), so a step of one
        // *column* would never leave the row a person is standing in and cover
        // to the north or south would be invisible. A step is the larger of the
        // two, which crosses a cell whichever way you are facing.
        let step = max(1 / Double(columns), 1 / Double(rows))
        let mine = cell(of: defender)
        let theirs = cell(of: attacker)
        var best = 0.0
        var hit: UUID?
        for reach in [step * 0.5, step] {
            let here = LocalPoint(x: defender.x + dx / span * reach,
                                  y: defender.y + dy / span * reach)
            let index = cell(of: here)
            guard index != mine, index != theirs, value[index] > best else { continue }
            best = value[index]
            hit = owner[index]
        }
        return (best, hit)
    }

    private func cell(of point: LocalPoint) -> Int {
        let column = min(columns - 1, max(0, Int(point.x * Double(columns))))
        let row = min(rows - 1, max(0, Int(point.y * Double(rows))))
        return row * columns + column
    }
}
