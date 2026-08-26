import Foundation

/// The wood as something that grows and is felled, rather than a number that
/// dips and recovers.
///
/// Trees age every tick — growth is *derived* from age, so nothing has to be
/// recomputed or stored — and loggers' work is banked into the tree itself, so
/// a half-chopped oak stays half-chopped when the shift ends. What comes down
/// is gone; what is planted takes an oak's lifetime to replace, which is the
/// whole point of making a forest out of objects.
///
/// Deterministic and linear in the number of trees. The abstract `forest`
/// deposits still drive the economy; this is the layer taking it over.
public enum FloraEngine {

    /// Axe-work one logger lands on a tree in one tick.
    static let chopPerTick = 0.06
    /// Below this the wood is too thin to be worth working — loggers move on.
    ///
    /// **Raised to bearing age.** It was 0.35 and `bearingGrowth` is 0.5, so
    /// every tree in the valley was felled *before it had ever set seed*. That
    /// is overfishing, and it is invisible in the tree count: measured on
    /// Keks's save with the seed stand and the faster seeding already in, the
    /// wood came back from seven trees to forty-eight over fifty years and had
    /// **zero bearing trees the whole way** — every sapling that reached 0.35
    /// met an axe within seventeen ticks. A wood that can only ever be
    /// replenished by seed blowing over the valley wall is not a wood the
    /// colony is keeping; it is one it is being given.
    ///
    /// At bearing age the two numbers agree: anything worth felling has
    /// already dropped seed at least once, and `seedStand` keeps enough of them
    /// standing to go on doing it.
    static let minimumWorkableGrowth = bearingGrowth

    /// **How many trees a colony leaves standing, whatever it needs.**
    ///
    /// Measured on Keks's save (tick 6805, 113 years in): **seven trees left in
    /// the whole valley, every one of them at growth 0.0**, with nine loggers
    /// assigned. Nothing was workable, so no `wood` reached the shelf, so
    /// `saw_timber` and `burn_charcoal` had no input, so there were no timber
    /// bundles and no charcoal — and with no charcoal `smelt_iron` had never
    /// run once in a hundred years: the iron ore on his shelf stood at exactly
    /// 193 across a decade of replay. **Every building in the book with a
    /// crafted cost, every generator, and the whole iron-and-steel half of the
    /// item tree were unreachable**, and had been for most of the colony's
    /// life. Twenty-eight of fifty-nine buildings need no made thing, and those
    /// twenty-eight are precisely what his town is built of.
    ///
    /// The arithmetic was never survivable. Nine loggers at `chopPerTick` fell
    /// a tree apiece every seventeen ticks — about half a tree a tick — while
    /// `reseeded` planted **one sapling every hundred ticks**, and a sapling
    /// needs five hundred to seventeen hundred ticks to be worth an axe. Two
    /// rates two orders of magnitude apart with no floor between them: rule 6's
    /// shape, and the state it runs to is absorbing. A colony cannot recover
    /// from having felled its last tree, because there is nothing left to seed
    /// from and nothing it can build to fix it.
    ///
    /// So a stand is kept back. Not a comfort — a **hard floor**, because the
    /// alternative is a colony that has quietly ended its own industry and has
    /// no way to be told. A tree the player marked is still felled: clearing
    /// ground you want to build on is a decision, and a mark the colony ignores
    /// is worse than no mark (`Designation`).
    static let seedStand = 16

    /// Ages every tree by a tick. Cheap on purpose: growth is a function of
    /// age, so this is one increment per tree and no allocation when the wood
    /// is empty.
    public static func advanceOneTick(_ map: LocalMap, by ticks: Int = 1) -> LocalMap {
        guard !map.trees.isEmpty, ticks > 0 else { return map }
        var updated = map
        for i in updated.trees.indices {
            updated.trees[i].age += ticks
        }
        return updated
    }

    /// Puts `loggers` to the axe for one tick and returns the timber they
    /// brought down. Work goes into the biggest workable tree first — nobody
    /// fells a sapling while an oak is standing — and a tree that comes down is
    /// removed from the map.
    public static func fell(
        _ map: LocalMap, loggers: Int, marked: Set<Int> = [],
        /// What `spareToFell` already answered, when the caller asked first.
        spare: Int? = nil
    ) -> (map: LocalMap, timber: Double, felled: Int, stumps: [LocalPoint]) {
        guard loggers > 0, !map.trees.isEmpty else { return (map, 0, 0, []) }

        // The standing wood worth an axe. **A tree the player marked comes
        // first** (`Designation`), and after that the biggest — nobody fells a
        // sapling while an oak is standing. Ties break on id so the same world
        // always fells the same tree.
        // What the axes may take before the stand is down to its seed
        // (`seedStand`). Counted over the trees that actually **bear**, not
        // over the whole wood: forty saplings and no parent is a wood with no
        // future, and a count that cannot tell those apart will happily let the
        // colony fell the last four trees that were holding it up. Marked trees
        // are outside the reckoning entirely — the player pointing at a thicket
        // is a decision, not an appetite.
        // Counted by the caller when it has already had to ask — `fell` and
        // `spareToFell` were walking the whole wood one after the other every
        // tick, which on a valley that can now reach `woodCeiling` is twice the
        // work on three times the trees.
        let spare = spare ?? spareToFell(map)
        var takenFromTheStand = 0
        let workable = map.trees.indices
            // A sapling is not worth an axe — **unless somebody pointed at it.**
            // Clearing a thicket off the ground you want to build on is a real
            // reason to fell a small tree, and a mark the colony silently
            // ignores is worse than no mark at all.
            .filter { map.trees[$0].growth >= minimumWorkableGrowth
                        || marked.contains(map.trees[$0].id) }
            .sorted {
                let a = map.trees[$0], b = map.trees[$1]
                let wantedA = marked.contains(a.id), wantedB = marked.contains(b.id)
                if wantedA != wantedB { return wantedA }
                if a.timberYield != b.timberYield { return a.timberYield > b.timberYield }
                return a.id < b.id
            }
        guard !workable.isEmpty else { return (map, 0, 0, []) }

        var updated = map
        var timber = 0.0
        var downed: Set<Int> = []
        // Where each trunk came down, so the timber can be left at the stump
        // for somebody to carry in rather than appearing in the storehouse.
        var stumps: [LocalPoint] = []
        for (worker, index) in workable.prefix(loggers).enumerated() {
            _ = worker
            // The wood is down to its seed and nobody asked for this one: the
            // axe goes elsewhere. Checked before the work goes in, so a colony
            // at the floor does not leave half-chopped trees standing round the
            // valley for ever.
            if !marked.contains(map.trees[index].id) {
                guard takenFromTheStand < spare else { continue }
                takenFromTheStand += 1
            }
            updated.trees[index].chopped += chopPerTick
            if updated.trees[index].chopped >= 1 {
                timber += updated.trees[index].timberYield
                stumps.append(updated.trees[index].position)
                downed.insert(index)
            }
        }
        if !downed.isEmpty {
            updated.trees = updated.trees.enumerated()
                .filter { !downed.contains($0.offset) }
                .map(\.element)
        }
        return (updated, timber, downed.count, stumps)
    }

    /// Puts `miners` to the rock for one tick and returns what they broke out,
    /// and **where it is lying**.
    ///
    /// Harder stone gives up less for the same work, and a spent outcrop is
    /// left behind rather than removed — a worked-out quarry is a feature of
    /// the ground, not a hole in the save.
    ///
    /// `broken` is the half of this that was missing for as long as outcrops
    /// have existed. The caller took `.map` and dropped `.yield` on the floor,
    /// and nothing anywhere turned a worked outcrop into goods — so a valley
    /// with no massif in it (every coast, most plains) had its miners grind
    /// nine clay banks to nothing over four hundred ticks and bank *not one
    /// unit of clay*. Wood falls at the stump and hewn stone falls at the face;
    /// this is the same rule for the third and commonest kind of working.
    public static func quarry(
        _ map: LocalMap, miners: Int, marked: Set<Int> = []
    ) -> (map: LocalMap, yield: [LocalResourceKind: Double],
          broken: [(kind: LocalResourceKind, amount: Double, at: LocalPoint)]) {
        guard miners > 0, !map.rocks.isEmpty else { return (map, [:], []) }
        // Marked rock first, then the softest — the seam somebody pointed at
        // is worth more than the one that is easiest to break.
        let workable = map.rocks.indices
            .filter { !map.rocks[$0].isSpent }
            .sorted {
                let a = map.rocks[$0], b = map.rocks[$1]
                let wantedA = marked.contains(a.id), wantedB = marked.contains(b.id)
                if wantedA != wantedB { return wantedA }
                if a.kind.hardness != b.kind.hardness { return a.kind.hardness < b.kind.hardness }
                return a.id < b.id
            }
        guard !workable.isEmpty else { return (map, [:], []) }

        var updated = map
        var yield: [LocalResourceKind: Double] = [:]
        var broken: [(kind: LocalResourceKind, amount: Double, at: LocalPoint)] = []
        for index in workable.prefix(miners) {
            let rock = updated.rocks[index]
            let taken = min(rock.amount, 1 / rock.kind.hardness)
            updated.rocks[index].amount = max(0, rock.amount - taken)
            yield[rock.kind.deposit, default: 0] += taken
            broken.append((kind: rock.kind.deposit, amount: taken, at: rock.position))
        }
        return (updated, yield, broken)
    }

    /// How far from a deposit's centre the things standing on it count as
    /// belonging to it. Generation scatters a wood inside 0.07 and outcrops
    /// inside 0.05, so this comfortably covers both with room for the fringe.
    public static let claimRadius: Double = 0.10

    static func within(_ a: LocalPoint, _ b: LocalPoint, _ radius: Double) -> Bool {
        let dx = a.x - b.x, dy = a.y - b.y
        return dx * dx + dy * dy <= radius * radius
    }

    /// Rewrites every deposit's `amount` from what is actually standing on it.
    ///
    /// A forest node used to be an independent number that dipped when someone
    /// worked it and crept back in spring, while the trees drawn over it were
    /// scenery that only *pretended* to thin out. Now the number **is** the
    /// wood: fell the trees and the deposit falls with them, let them grow and
    /// it recovers on its own. Stone is the same, except it never comes back.
    ///
    /// Deposits with nothing standing on them — an old save, a field, a herb
    /// patch — are left exactly as they were, so this can be applied to any map.
    public static func syncDeposits(_ map: LocalMap) -> LocalMap {
        guard map.usesEntityLand else { return map }
        var updated = map
        for i in updated.nodes.indices {
            let node = updated.nodes[i]
            switch node.kind {
            case .forest:
                let standing = map.trees
                    .filter { within($0.position, node.position, claimRadius) }
                    .reduce(0.0) { $0 + $1.timberYield }
                updated.nodes[i].amount = min(node.capacity, standing)
            case .stone, .ironOre, .clay, .coal, .oilSeep:
                let left = map.rocks
                    .filter { $0.kind.deposit == node.kind
                              && within($0.position, node.position, claimRadius) }
                    .reduce(0.0) { $0 + $1.amount }
                updated.nodes[i].amount = min(node.capacity, left)
            case .field, .herbs:
                continue    // nothing stands on these; they keep the old arithmetic
            }
        }
        return updated
    }

    /// Whether a deposit kind is backed by real things, and so should neither
    /// be depleted nor regrown by the old node arithmetic.
    public static func isEntityBacked(_ kind: LocalResourceKind, in map: LocalMap) -> Bool {
        // Fields answer to their own layer, on their own flag: a map can have
        // plots without having trees (an old save whose colony has since raised
        // a farm) and trees without plots. See `LocalMap.usesEntityFields`.
        if kind == .field { return map.usesEntityFields }
        guard map.usesEntityLand else { return false }
        switch kind {
        case .forest, .stone, .ironOre, .clay, .coal, .oilSeep: return true
        case .field, .herbs: return false
        }
    }

    /// How many trees a valley will carry. The generator lays down roughly
    /// eleven to nineteen per forest centre plus scattered ones, so this is a
    /// ceiling a generated map starts well under and a cleared one climbs back
    /// toward — not a target.
    static let woodCeiling = 160

    /// Below this share of the ceiling, seed blows in from outside the valley.
    /// Without it a colony that fells its **last** tree has nothing left to
    /// seed from and the wood is gone for ever, which is the lock this whole
    /// function exists to break.
    ///
    /// **Raised past the seed stand.** It was 0.12 of the ceiling — nineteen
    /// trees — while `seedStand` keeps twenty-four back, so a wood held at its
    /// floor by the axes was permanently *above* the wind-borne threshold and
    /// permanently below bearing age: no parent to seed from, no wind to seed
    /// without one, and nothing growing. Two guards that each look correct and
    /// between them leave a gap the game sits in for ever.
    static let windBorneBelow = 0.30

    /// Grown enough to bear seed. Not `isMature` — a tree drops seed long
    /// before it is worth an axe, and asking for full growth is what made the
    /// wood need a *mature* parent it was never allowed to keep.
    static let bearingGrowth = 0.5

    /// How many saplings one pass may set, at most.
    ///
    /// One, before this — every hundred ticks — against nine loggers taking
    /// about half a tree a tick. Two rates two orders of magnitude apart
    /// (`seedStand`). A wood thickens from its own edges, so the number scales
    /// with what is standing and bearing, and the ceiling keeps a mature forest
    /// from filling the valley in a season.
    static let mostSaplingsPerPass = 8

    /// How many bearing trees it takes to set one sapling in a pass.
    static let bearersPerSapling = 6

    /// How much seed a **thin** wood gets regardless of what is bearing.
    ///
    /// The scaled rate alone is not enough to bring a stripped valley back
    /// inside a lifetime, and that is the case that matters: a colony with no
    /// wood can build nothing with a crafted cost, so "wait forty years"
    /// is the same answer as "never". Measured on Keks's save, seeding from
    /// bearers alone took his valley from seven trees to seventeen in a decade
    /// — and the seed stand meant not one of them could be felled. Open ground
    /// takes seed readily; a closed wood does not, which is why this is the
    /// floor and not the rate.
    static let thinWoodSaplings = 4

    /// Lets the wood come back on its own.
    ///
    /// **`plant` had no callers.** Its own doc comment called it "the only way a
    /// wood that has been cleared ever comes back inside a colony's lifetime",
    /// and nothing in the engine ever called it — so a valley was felled once
    /// and stayed bare forever. That is not a cosmetic loss: `wood` is what the
    /// `saw_timber` recipe turns into `timber_bundle`, and a `timber_bundle` is
    /// what most buildings in `buildings.json` list under `material_cost`. When
    /// the wood ran out, **every building with a crafted cost became permanently
    /// unbuildable**.
    ///
    /// Measured by `ZZStewardProbe`, seed 2025: `timber_bundle` on the shelf
    /// went 16 at year seventy to **zero at year eighty and stayed there for the
    /// remaining hundred and twenty years**, and `buildableHere` returned an
    /// **empty list** for almost all of it, while the materials store climbed to
    /// 5500. The council was not idle and it was not poor — it was standing on a
    /// mountain of raw stone and timber it had no way to turn into anything. It
    /// is also why the brownout clause added the same day never fired once:
    /// `nextBuilding` returns at its first `guard !affordable.isEmpty`, so no
    /// clause below it is ever reached.
    ///
    /// Seed lands next to standing trees, so a wood grows back from its own
    /// edges and a genuinely cleared corner stays cleared. Deterministic from
    /// `(mapSeed, tick)` per rule 3.
    public static func reseeded(
        _ map: LocalMap, mapSeed: UInt64, tick: Int, registry: GameDataRegistry
    ) -> LocalMap {
        guard map.usesEntityLand, map.trees.count < woodCeiling else { return map }
        var rng = SeededRNG(seed: mapSeed &* 0x9E37_79B9 &+ UInt64(bitPattern: Int64(tick)) &* 0x85EB_CA6B)

        // A parent to seed from: any tree grown enough to bear.
        //
        // Counted and walked rather than filtered and sorted. The first cut did
        // `filter { $0.isMature }.sorted { $0.id < $1.id }` — an allocation and
        // an O(n log n) sort of the whole wood, every pass — and the wood *grows
        // over a run*, so the cost grew with it. That is the shape
        // `OfflineCatchUpTests.catchUpScalesLinearly` exists to catch, and it
        // caught it. `map.trees` is append-only with increasing ids, so index
        // order is already id order and there is nothing to sort.
        var bearers: [Tree] = []
        for tree in map.trees where tree.growth >= bearingGrowth { bearers.append(tree) }

        // How much seed there is to set this pass. A thick wood spreads faster
        // than a thin one, and a bare valley gets the one seed the wind brings.
        let updatedCount = map.trees.count
        let windBorne = bearers.isEmpty
        if windBorne, Double(updatedCount) >= Double(woodCeiling) * windBorneBelow {
            return map
        }
        // **What this valley grows.** Empty means the book has no tree for this
        // country *and* no tree at all — a registry built without `flora.json`,
        // which every hand-made test registry is. Nothing can be seeded out of
        // an empty book, and picking a species out of it by remainder is a
        // divide by zero rather than a silent wrong answer, so this leaves
        // rather than guessing.
        let palette = FloraFactory.species(for: map.biomeID, registry: registry)
        guard !palette.isEmpty else { return map }
        // A thin wood is mostly open ground, and open ground takes seed — from
        // its own few bearers and from over the valley wall alike.
        let thin = Double(updatedCount) < Double(woodCeiling) * windBorneBelow
        let fromBearers = bearers.count / bearersPerSapling
        let wanted = min(mostSaplingsPerPass,
                         max(thin ? thinWoodSaplings : 1, fromBearers))

        var updated = map
        for _ in 0..<wanted {
            guard updated.trees.count < woodCeiling else { break }
            let origin: LocalPoint
            let species: FloraDefinition
            if windBorne {
                species = palette[Int(rng.nextUnit() * Double(palette.count)) % palette.count]
                origin = LocalPoint(x: rng.nextUnit(), y: rng.nextUnit())
            } else {
                let parent = bearers[Int(rng.nextUnit() * Double(bearers.count)) % bearers.count]
                origin = parent.position
                // A seed falls from *this* tree, so it is this tree's kind —
                // and if the content has since dropped that kind, the wood
                // seeds from whatever the valley still grows.
                species = registry.tree(parent.species)
                    ?? palette[Int(rng.nextUnit() * Double(palette.count)) % palette.count]
            }
            // Close to the parent — a wood thickens at its edge rather than
            // teleporting a sapling across the valley.
            let spread = 0.06
            let at = LocalPoint(
                x: min(0.98, max(0.02, origin.x + (rng.nextUnit() - 0.5) * spread * 2)),
                y: min(0.98, max(0.02, origin.y + (rng.nextUnit() - 0.5) * spread * 2)))
            // Never under a roof or on broken ground: a colony does not have to
            // weed its own streets, and a sapling in a wall would be a tree the
            // router has to path around for no reason anybody chose. A seed
            // that falls badly is simply a seed that did not take.
            guard isClearGround(updated, at) else { continue }
            updated = plant(updated, species: species, at: at)
        }
        return updated
    }

    /// **A woodsman at a wood with nothing to fell plants instead.**
    ///
    /// The reseeding above is nature's, and nature's rate cannot answer a
    /// colony. Measured over two centuries by `WoodProbe`, seed 4242: the
    /// bearing count pinned at **exactly `seedStand`, 16, from year thirty to
    /// year two hundred** — the axes take every tree the moment it bears, so
    /// `spare` is zero for a hundred and seventy years and the stand never
    /// thickens. Which kills the one term that was supposed to make seed scale:
    /// `fromBearers` is `bearers / bearersPerSapling` = 16/6 = **2**, for ever,
    /// always under the `thinWoodSaplings` floor of 4. Two guards that each
    /// read correctly — keep sixteen parents; seed in proportion to parents —
    /// and between them a rate that can never move.
    ///
    /// So wood supply was a **constant** of four saplings a pass while the
    /// colony went from thirty-nine people to two hundred and ninety-eight.
    /// Rule 16 in a new place. Demand crossed supply around year 135 and the
    /// shelf went 276 → 39 → 3 → 1 and stayed there: eight standing orders all
    /// reading "short of materials", and a hundred and twenty-three of the four
    /// hundred and eleven recipes — thirty per cent of the book — permanently
    /// unmakeable.
    ///
    /// The fix is not a bigger constant. It is that **the colony gets a lever**:
    /// a logger sent to a wood that is down to its seed stand has nothing to
    /// cut, and a woodsman standing at a floor-bound wood plants. The rate
    /// therefore scales with loggers — the one number the player actually
    /// controls — and it is self-balancing at both ends: plant while `spare` is
    /// zero, fell once the stand bears again, and stop at `woodCeiling`.
    ///
    /// No new magnitude: a logger sets one sapling in the pass they would
    /// otherwise have spent felling.
    public static func tended(
        _ map: LocalMap, foresters: Int, mapSeed: UInt64, tick: Int,
        registry: GameDataRegistry
    ) -> LocalMap {
        guard map.usesEntityLand, foresters > 0, map.trees.count < woodCeiling else { return map }
        let palette = FloraFactory.species(for: map.biomeID, registry: registry)
        guard !palette.isEmpty else { return map }

        var rng = SeededRNG(
            seed: mapSeed &* 0xC2B2_AE35 &+ UInt64(bitPattern: Int64(tick)) &* 0x27D4_EB2F)
        var updated = map
        for _ in 0..<foresters {
            guard updated.trees.count < woodCeiling else { break }
            // Beside what is already standing where there is anything standing,
            // and out on the open ground when the valley has been stripped —
            // a planted wood spreads from its own edge exactly as a seeded one
            // does, and a bare valley has no edge to spread from.
            let origin: LocalPoint
            let species: FloraDefinition
            if updated.trees.isEmpty {
                species = palette[Int(rng.nextUnit() * Double(palette.count)) % palette.count]
                origin = LocalPoint(x: rng.nextUnit(), y: rng.nextUnit())
            } else {
                let parent = updated.trees[Int(rng.nextUnit() * Double(updated.trees.count))
                                           % updated.trees.count]
                origin = parent.position
                species = registry.tree(parent.species)
                    ?? palette[Int(rng.nextUnit() * Double(palette.count)) % palette.count]
            }
            let spread = 0.06
            let at = LocalPoint(
                x: min(0.98, max(0.02, origin.x + (rng.nextUnit() - 0.5) * spread * 2)),
                y: min(0.98, max(0.02, origin.y + (rng.nextUnit() - 0.5) * spread * 2)))
            guard isClearGround(updated, at) else { continue }
            updated = plant(updated, species: species, at: at)
        }
        return updated
    }

    /// **How many unmarked trees the axes may take**: bearing trees over the
    /// stand kept back to seed the next one.
    ///
    /// Public because the caller has to know whether there is anything to fell
    /// *before* it decides between the axe and the seedling bag, and reading
    /// `fell`'s empty result afterwards cannot tell "nothing spare" from
    /// "nobody sent". Passing the answer back into `fell` is what stops the two
    /// of them walking the whole wood one after the other every tick.
    ///
    /// Marked trees are **not** in this number: a mark is a decision and is
    /// felled at the floor (`Designation`), so it is outside the reckoning
    /// exactly as it is inside `fell`. What the caller wants when deciding how
    /// many axes are worth sending is `worthFelling`.
    public static func spareToFell(_ map: LocalMap) -> Int {
        var bearing = 0
        for tree in map.trees where tree.growth >= bearingGrowth { bearing += 1 }
        return max(0, bearing - seedStand)
    }

    /// How many trees are worth sending somebody to at all — the spare stand
    /// plus anything the player pointed at, which is felled whatever the floor
    /// says.
    public static func worthFelling(_ map: LocalMap, marked: Set<Int>) -> Int {
        spareToFell(map) + marked.count
    }

    /// Whether a sapling may take root here — nothing standing on it, and not
    /// tilled.
    static func isClearGround(_ map: LocalMap, _ p: LocalPoint) -> Bool {
        if map.crops.contains(where: { within($0.position, p, 0.03) }) { return false }
        if map.trees.contains(where: { within($0.position, p, 0.02) }) { return false }
        if map.rocks.contains(where: { within($0.position, p, 0.03) }) { return false }
        if let shore = map.shore, shore.isWater(p) { return false }
        return true
    }

    /// Plants a sapling — the other half of felling, and the only way a wood
    /// that has been cleared ever comes back inside a colony's lifetime.
    public static func plant(
        _ map: LocalMap, species: FloraDefinition, at position: LocalPoint
    ) -> LocalMap {
        var updated = map
        // **The last id, not the largest of all of them.** This was
        // `trees.map(\.id).max()` — an array of every id in the wood, allocated
        // and scanned, for *each* sapling set. `trees` is append-only with
        // increasing ids and `fell` removes in place without reordering, so the
        // last one is the largest by construction. The same allocation-per-pass
        // shape `reseeded` was already fixed for, one function further down.
        let nextID = (updated.trees.last?.id ?? -1) + 1
        updated.trees.append(Tree(id: nextID, definition: species, position: position, age: 0))
        return updated
    }
}
