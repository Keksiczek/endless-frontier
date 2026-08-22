import Foundation

/// The harvest, as work done on ground that exists.
///
/// What this replaces is worth stating plainly, because it was the largest
/// measured failure in the game. Food came from `PawnEngine`:
/// `output[.food] += skill × 0.15 × season × gatherFactor`, where `gatherFactor`
/// read how full the `.field` deposits were. Those deposits regrew at
/// `capacity × 0.0009` a tick and every farmer drew `0.45` off them, so the
/// equilibrium was **under one farmer**. Any colony past its first decade
/// stripped its fields inside a season and left them there, `gatherFactor`
/// pinned at `depositFloorFactor` for the next two centuries — and every extra
/// farmer made it worse rather than better. That is precisely rule 14: a rate
/// multiplied by an entity count nobody bounded, and it is why the probe
/// reported 182 dead of starvation against 134 of old age.
///
/// Here instead: a farm building owns **plots** (`BuildingDefinition.plots`,
/// derived from its footprint the way `sleepers` is). A plot carries a crop
/// that ripens with the season and the weather, and a farmer has to walk out
/// and reap it. What comes off is `grain`, `roots` or `greens` lying at the
/// plot — raw ingredients, not food — carried in by the same `HaulEngine` that
/// brings the timber home, and turned into meals by `CookingEngine`.
///
/// The ceiling that used to be a fixed patch of wild ground is now *the farms
/// the colony builds*, which is a thing it can do more of. That is the whole
/// fix: food income scales with mouths because mouths build farms.
///
/// Deterministic and cheap: no randomness at all, one pass over the plots on a
/// cadence (rule 4).
public enum FarmEngine {

    /// How often the plots are reconciled against the standing farms. Building
    /// a farm is not a per-tick event; walking every placement every tick on a
    /// 24×24 grid is exactly the superlinear cost rule 4 exists for.
    public static let reconcileInterval = 10

    /// Worker-ticks a farmer of no skill puts into a plot each tick, and what a
    /// full twenty of skill adds. Mirrors `CraftingEngine.effort` deliberately:
    /// a master is a little over twice a beginner at any trade.
    static let effortPerFarmer = 1.0
    static let skillEffort = 1.3

    /// Growth per season, at the plot. Winter is **zero**: nothing ripens under
    /// snow, which is the entire reason a granary is worth its materials. The
    /// old `seasonFoodYield` winter of 0.3 meant a colony kept harvesting in
    /// January at a discount and never had a reason to store anything.
    static let seasonGrowth: [Season: Double] = [
        .spring: 1.0, .summer: 1.3, .autumn: 0.6, .winter: 0
    ]

    /// How far outside a crop's range — frost below, heat above — kills its
    /// growth outright. Inside this band it slows; past it, nothing at all.
    static let outsideRange: Double = 8

    /// How many mouths one plot of tilled ground feeds, with a season's slack.
    ///
    /// Worked out rather than guessed, because the number the council builds
    /// against has to be *true* or the colony discovers it is short of fields
    /// only once it is already starving — which is exactly how the first cut of
    /// this died at t=6 500 with two farms and seventy-four people:
    ///
    /// - A plot averages `yield / ripenTicks` = 0.43 ingredient units per
    ///   growth-tick across the sown rotation (half grain, a quarter each of
    ///   roots and greens).
    /// - Growth-ticks per real tick average `(1.0 + 1.3 + 0.6 + 0) / 4` = 0.725
    ///   over the four seasons — winter grows nothing.
    /// - A cook turns a unit into a shade under two food.
    ///
    /// So a plot is worth about 0.56 food a tick and a colonist eats 0.1 —
    /// call it five and a half. Four was that with a winter's headroom on it.
    ///
    /// **And the colony starved at a hundred and ten anyway.** The arithmetic
    /// above is the *ceiling* of a plot, and it is not what a plot delivers: a
    /// crop only counts once a farmer has walked out and cut it, what is cut
    /// waits to be hauled, and what is hauled waits for a cook. Every one of
    /// those is a valve, and four assumed all three were open.
    ///
    /// Measured once the fertility clock was fixed (§11.19, §11.21) and a colony
    /// could finally get large, seed 4242: plots stood at **38 from year sixty
    /// to year two hundred** while the population went 72 → 127, because
    /// `plotsWanted` said 127 mouths wanted 32 and the colony had 38 — no
    /// shortage, so the council never raised another farm. A century of surplus
    /// piled up as raw crops (`shelf` at 2 500–2 900), the population passed
    /// what the fields actually delivered somewhere near a hundred and ten, and
    /// then the backlog drained in a decade and took sixty-nine people with it.
    ///
    /// So: **2.5**, which is the measured figure — thirty-eight plots carrying
    /// about a hundred and ten mouths at break-even — with a winter on top. Rule
    /// 24's sibling: a constant derived from a rate has to be checked against
    /// what the simulation *realises*, not against what the rate permits. The
    /// arithmetic above is left standing because it is still the right way to
    /// reason about the ceiling; it is simply not the floor the council needs.
    public static let peoplePerPlot: Double = 2.5

    /// Plots this settlement ought to have under crop for the mouths it has.
    public static func plotsWanted(for population: Double) -> Int {
        Int((population / peoplePerPlot).rounded(.up))
    }

    /// Plots it actually has.
    public static func plotsStanding(_ settlement: Settlement) -> Int {
        settlement.localMap?.crops.count ?? 0
    }

    // MARK: - The tick

    /// Plots ripen, farmers reap, and what they cut is left at the plot.
    public static func advanceOneTick(
        _ settlement: Settlement, registry: GameDataRegistry, tick: Int,
        climate: Climate = .temperate, mapSeed: UInt64 = 0,
        /// What the colony's studies have done to what comes off a plot. The
        /// most visible number research can move: the same field, the same
        /// season, more grain on the ground.
        yieldFactor: Double = 1
    ) -> Settlement {
        var s = settlement
        if tick % reconcileInterval == 0 {
            s = reconcile(s, registry: registry, climate: climate)
        }
        guard var map = s.localMap, map.usesEntityFields, !map.crops.isEmpty else { return s }

        let season = Season(tick: tick, ticksPerYear: registry.config.ticksPerYear)
        let temperature = climate.temperature(season)
        // What the settlement has made of itself. An agricultural town used to
        // out-grow a balanced one by multiplying `production[.food]` on its
        // farm buildings — and farms stopped having any, so the whole
        // specialisation quietly stopped meaning anything for food. It applies
        // to the *growing* now, which is the thing an agricultural town is
        // actually better at.
        let bent = s.specialization.profile.productionMultiplier(.food)

        // Growth first, then reaping — a plot that comes ripe this tick may be
        // cut this tick, which is what stops a harvest sitting a full cadence
        // in a colony that is hungry now.
        for i in map.crops.indices {
            map.crops[i].growth = min(1, map.crops[i].growth
                                      + growthStep(map.crops[i].species,
                                                   season: season, temperature: temperature)
                                      * bent)
        }

        // **Each farmer reaps the plot they are standing in.**
        //
        // The whole point of `JobKind.workPlot`: a farmer the job board sent to
        // furrow #7 must be the one who cuts furrow #7, or the canvas is
        // drawing a person at a place where nothing they do is happening. That
        // was the complaint — "je uvnitř, píše to venku" — and pooling every
        // farmer's effort over the ripest plots is the version of it that would
        // have survived posting the jobs.
        //
        // What is left over — a farmer with no job yet, an old save, the ticks
        // before the board's cadence comes round — falls into a pool spent on
        // the ripe plots nearest the store, so a colony still brings its harvest
        // in while the board catches up.
        var byPlot: [Int: Double] = [:]
        var pooled = 0.0
        let shut = workFactor(of: s)
        if shut > 0 {
            for pawn in s.pawns where pawn.assignedWork == .farming {
                let hands = effort(of: pawn, registry: registry) * shut
                guard hands > 0 else { continue }
                if let job = pawn.currentJob, job.kind == .workPlot, let plot = job.cropID {
                    byPlot[plot, default: 0] += hands
                } else {
                    pooled += hands
                }
            }
        }

        let store = HaulEngine.storePosition(s)
        let ripe = map.crops.indices
            .filter { map.crops[$0].isRipe }
            .sorted {
                let a = SiegeField.distance(map.crops[$0].position, store)
                let b = SiegeField.distance(map.crops[$1].position, store)
                return a == b ? map.crops[$0].id < map.crops[$1].id : a < b
            }

        var cut: [(itemID: String, amount: Double, at: LocalPoint)] = []
        func reap(_ index: Int, with hands: Double) -> Double {
            let crop = map.crops[index]
            guard crop.isRipe, hands > 0 else { return hands }
            let owed = (1 - crop.reaped) * crop.species.reapWork
            let spent = min(hands, owed)
            let reaped = crop.reaped + spent / crop.species.reapWork
            guard reaped >= 1 else {
                map.crops[index].reaped = reaped
                return hands - spent
            }
            // Off the plot, onto the ground, and the plot is sown again. The
            // ground is permanent; the crop on it is what cycles.
            cut.append((crop.species.itemID, crop.standing * yieldFactor, crop.position))
            map.crops[index].reaped = 0
            map.crops[index].growth = 0
            return hands - spent
        }

        // Their own furrow first. Effort a farmer puts into a plot that is not
        // ripe yet is *tending* — it does nothing, and it should not: a plot
        // is not brought on faster by standing in it.
        for (plot, hands) in byPlot.sorted(by: { $0.key < $1.key }) {
            guard let index = map.crops.firstIndex(where: { $0.id == plot }) else {
                pooled += hands
                continue
            }
            pooled += reap(index, with: hands)
        }
        for index in ripe where pooled > 0 {
            pooled = reap(index, with: pooled)
        }

        // Part-units bank against the map exactly as broken rock does
        // (`quarryCredit`). Flooring every harvest would lose a small colony its
        // whole margin; rounding up would pay it for work nobody did.
        if !cut.isEmpty {
            var rng = SeededRNG(seed: ResourceLoop.societyLikeSeed(
                mapSeed: mapSeed, settlementID: s.id, tick: tick) ^ 0x46_41_52_4D)
            for take in cut {
                let owed = map.harvestCredit[take.itemID, default: 0] + take.amount
                let whole = Int(owed)
                map.harvestCredit[take.itemID] = owed - Double(whole)
                if whole > 0 {
                    map = HaulEngine.drop(map, itemID: take.itemID, amount: whole,
                                          at: take.at, tick: tick, rng: &rng)
                }
            }
        }

        s.localMap = map
        return s
    }

    // MARK: - Pieces

    /// How fast a crop ripens this tick.
    ///
    /// Season and cold both gate it, and cold is checked against the crop's own
    /// floor — which is what makes *where you settle* a decision about food and
    /// not only about warmth. Roots take a frost that finishes greens.
    static func growthStep(
        _ species: CropSpecies, season: Season, temperature: Double
    ) -> Double {
        let bySeason = seasonGrowth[season] ?? 1
        guard bySeason > 0 else { return 0 }
        // How far outside the crop's range the day is — cold below, heat above.
        // Heat was missing entirely, and it is why a desert summer of 42° did
        // nothing to a field of greens whose ceiling is 28.
        let outside = max(species.coldFloor - temperature,
                          temperature - species.heatCeiling)
        guard outside > 0 else { return bySeason / species.ripenTicks }
        guard outside < outsideRange else { return 0 }
        return bySeason * (1 - outside / outsideRange) / species.ripenTicks
    }

    /// The worker-ticks the colony's farmers put into reaping this tick.
    ///
    /// Only people actually assigned to farming, adult, standing and here — the
    /// same guards `CraftingEngine.effort` applies, and for the same reason: a
    /// trade is a claim on real people, not a multiplier on a headcount.
    static func reapingEffort(of settlement: Settlement, registry: GameDataRegistry) -> Double {
        let shut = workFactor(of: settlement)
        guard shut > 0 else { return 0 }
        return shut * settlement.pawns.reduce(0.0) { total, pawn in
            guard pawn.assignedWork == .farming else { return total }
            return total + effort(of: pawn, registry: registry)
        }
    }

    /// What one farmer is worth at the harvest this tick.
    ///
    /// Zero for anybody who cannot work: broken, away, a child, or too badly
    /// hurt to stand. The same shape as `CraftingEngine.effort` and
    /// `CookingEngine.effort` — one idea of what a trained pair of hands is
    /// worth, in the three places that each need it.
    static func effort(of pawn: Pawn, registry: GameDataRegistry) -> Double {
        guard pawn.isAdult(ticksPerYear: registry.config.ticksPerYear),
              !pawn.isBroken, !pawn.isAway, pawn.health > 0 else { return 0 }
        let skill = Double(pawn.skill(.farming)) / 20
        let condition = min(1, max(0.35, pawn.health / 100))
        return (effortPerFarmer + skill * skillEffort) * condition
    }

    /// What the colony's own troubles do to the harvest.
    ///
    /// A strike stops it outright and shutting the gates against a sickness
    /// slows it. Both used to reach food through `gatheringFactors`, which
    /// reaping does not go anywhere near — so without this a struck colony
    /// would go on bringing the crop in, which is the one thing a strike is for.
    static func workFactor(of settlement: Settlement) -> Double {
        guard settlement.strikeTicksRemaining == 0 else { return 0 }
        return PlagueEngine.workFactor(settlement)
    }

    // MARK: - The ground itself

    /// Brings the plots into line with the farms that are standing.
    ///
    /// A finished farm gets its plots; a farm that has fallen down or been
    /// demolished takes its plots with it. Existing plots are left exactly as
    /// they are — a reconcile in the middle of a growing season must not reset
    /// anybody's harvest.
    public static func reconcile(
        _ settlement: Settlement, registry: GameDataRegistry,
        climate: Climate = .temperate
    ) -> Settlement {
        guard var map = settlement.localMap, let colony = settlement.colony else {
            return settlement
        }
        var wanted: [Crop] = []
        // Sorted by placement id so the plot order — and therefore every id —
        // is the same in two runs of the same seed (rule 2).
        for placement in colony.placements.sorted(by: { $0.id.uuidString < $1.id.uuidString }) {
            // Ground under crop, not a working building. A farm whose roof has
            // gone is still a farm with fields on it, and `BuildingEngine`'s
            // condition already docks what a run-down building produces.
            //
            // Gating the plots on `isWorking` — which is what this did — meant
            // a farm falling into disrepair **deleted its own harvest**, and
            // any crop that had been growing on it went with it. Measured: four
            // standing farms whose plots fell 26 → 20 → 8 → 0 while the
            // buildings were still there, food at the cap right up to the tick
            // it hit zero, and eighty dead of hunger. A building site has no
            // fields yet; everything else does.
            guard !placement.underConstruction,
                  let def = registry.building(placement.definitionID),
                  def.plots > 0 else { continue }
            // The plots tile the lot **below the barn**.
            //
            // Laid out over the whole footprint at first, which put every plot
            // squarely underneath the building drawn on top of it — six fields
            // that existed, ripened, were reaped, and could not be seen. The
            // top row of the lot is the yard the shed stands in; the rest is
            // ground under crop, which is what a farm mostly is.
            let rows = max(1, placement.height - 1)
            let firstRow = placement.height > 1 ? placement.coord.y + 1 : placement.coord.y
            let columns = max(1, Int((Double(def.plots) / Double(rows)).rounded(.up)))
            let tileW = Double(placement.width) / Double(columns)
            // **The plots tile the ground; they do not dot it.**
            //
            // Keks, looking at a farm: *"budovy stále nemají úplně ok
            // footprint, hlavně políčko."* At 0.40 and 0.38 of a tile each plot
            // was four fifths of its own square with a gap of wild grass all
            // round it, so six plots read as six green patches lying near a
            // shed rather than as one field the shed stands at the top of.
            // Half a tile is edge-to-edge; a hair under it keeps the furrow
            // between two plots visible, which is what a field looks like.
            let halfWidth = SettlementGeometry.span * tileW / Double(max(1, colony.width)) * 0.485
            let halfHeight = SettlementGeometry.span / Double(max(1, colony.height)) * 0.475
            for index in 0..<def.plots {
                let column = Double(index % columns)
                let row = Double(min(rows - 1, index / columns))
                wanted.append(Crop(
                    id: plotID(farm: placement.id, index: index),
                    species: CropSpecies.sown(inPlot: index, climate: climate),
                    position: SettlementGeometry.canvasPoint(
                        tileX: Double(placement.coord.x) + (column + 0.5) * tileW,
                        tileY: Double(firstRow) + row + 0.5,
                        in: colony),
                    farmID: placement.id,
                    halfWidth: halfWidth, halfHeight: halfHeight))
            }
        }
        // Keep what is already growing; the reconcile is about which plots
        // exist, never about what is on them.
        let standing = Dictionary(map.crops.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        map.crops = wanted.map { plot in
            guard let existing = standing[plot.id], existing.species == plot.species else {
                return plot
            }
            var kept = plot
            kept.growth = existing.growth
            kept.reaped = existing.reaped
            return kept
        }
        // Rule 5: `crops.isEmpty` is not "no plot layer". A colony between
        // harvests, or one whose only farm has just burned, still lives in a
        // world where food comes off plots — flipping this back would put the
        // old abstract-field arithmetic under it and quietly double-feed it.
        map.usesEntityFields = map.usesEntityFields || !map.crops.isEmpty
        var s = settlement
        s.localMap = map
        return s
    }

    /// A stable id for one plot of one farm.
    ///
    /// Derived from the placement's own bytes, never from `hashValue` — Swift
    /// seeds its hasher per process, so a hashed id is a different id on every
    /// launch and the whole world diverges from it (rule 2, the bug that cost
    /// this project two sessions).
    static func plotID(farm: UUID, index: Int) -> Int {
        let b = farm.uuid
        var h: UInt64 = 0xCBF2_9CE4_8422_2325
        for byte in [b.0, b.1, b.2, b.3, b.4, b.5, b.6, b.7] {
            h = (h ^ UInt64(byte)) &* 0x100_0000_01B3
        }
        h = (h ^ UInt64(bitPattern: Int64(index))) &* 0x100_0000_01B3
        return Int(bitPattern: UInt(truncatingIfNeeded: h >> 1))
    }
}
