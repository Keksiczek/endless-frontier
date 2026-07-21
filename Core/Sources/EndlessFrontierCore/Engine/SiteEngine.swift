import Foundation

/// The result of interacting with a special site, for the UI and history.
public struct SiteOutcome: Sendable, Equatable {
    public let kind: RegionKind
    public let regionName: String
    public let rewards: Resources
    public let casualtyName: String?   // a colonist hurt (dungeon)
    public let died: Bool              // …or killed
    public let threatGain: Double      // anomaly stirs danger
    public let itemFound: String?      // name of an item recovered, if any
    public let narrative: String

    public init(kind: RegionKind, regionName: String, rewards: Resources,
                casualtyName: String? = nil, died: Bool = false, threatGain: Double = 0,
                itemFound: String? = nil, narrative: String) {
        self.kind = kind
        self.regionName = regionName
        self.rewards = rewards
        self.casualtyName = casualtyName
        self.died = died
        self.threatGain = threatGain
        self.itemFound = itemFound
        self.narrative = narrative
    }
}

/// Makes the map's special sites worth visiting: ruins, dungeons and
/// anomalies each offer a distinct risk/reward interaction, with loot scaling
/// by hazard (and therefore by distance from the homeland). Deterministic —
/// outcomes are seeded by `(mapSeed, coord, tick)`.
public enum SiteEngine {
    /// Interacts with the special site in `regionID`. Returns the updated world
    /// and an outcome, or `nil` if there's no active site there.
    public static func interact(
        _ state: WorldState,
        regionID: UUID,
        registry: GameDataRegistry
    ) -> (WorldState, SiteOutcome)? {
        guard let index = state.regions.firstIndex(where: { $0.id == regionID }),
              state.regions[index].hasActiveSite else {
            return nil
        }
        var s = state
        let region = s.regions[index]
        let hazard = Double(region.hazardLevel)
        var rng = SeededRNG(seed: siteSeed(mapSeed: s.mapSeed, coord: region.coord, tick: s.tick))

        let visitsSoFar = region.siteVisits ?? 0
        let outcome: SiteOutcome
        switch region.kind {
        case .ruins:
            outcome = excavateRuins(&s, region: region, hazard: hazard, registry: registry, rng: &rng)
        case .dungeon:
            outcome = delveDungeon(&s, region: region, hazard: hazard, registry: registry, rng: &rng)
        case .anomaly:
            outcome = probeAnomaly(&s, region: region, hazard: hazard)
        case .sanctuary:
            outcome = makePilgrimage(&s, region: region, hazard: hazard)
        case .lostCity:
            outcome = salvageLostCity(&s, region: region, hazard: hazard,
                                      visits: visitsSoFar, registry: registry, rng: &rng)
        default:
            return nil
        }

        // A dead city is too big to strip in one run: it stays workable for
        // several salvages, each poorer than the last, before it's picked
        // clean. Everything else is a one-time interaction.
        s.regions[index].siteVisits = visitsSoFar + 1
        if region.kind == .lostCity, visitsSoFar + 1 < lostCityVisits {
            s.regions[index].siteCleared = false
        } else {
            s.regions[index].siteCleared = true
            s.worldFlags["cleared:\(region.kind.rawValue)"] = true   // enables quest goals
        }
        let record = HistoricalEvent(templateID: "site_\(region.kind.rawValue)", type: siteEventType(region.kind), tick: s.tick)
        s.eventHistory.append(record)
        // The day belongs in the colony's own diary too — and from there, the
        // toasts.
        if let capital = s.settlements.indices.first {
            s.settlements[capital].journal.append(
                tick: s.tick, kind: .discovery,
                text: journalLine(for: region.kind, regionName: region.name))
        }
        return (s, outcome)
    }

    /// The diary's line for a cleared site, in both languages.
    static func journalLine(for kind: RegionKind, regionName: String) -> LocalizedText {
        switch kind {
        case .ruins:
            return LocalizedText(values: [
                .en: "Scholars sifted the ruins of \(regionName) and carried home what the ages left.",
                .cs: "Učenci prohledali zříceniny v kraji \(regionName) a odnesli, co po věcích zbylo."])
        case .dungeon:
            return LocalizedText(values: [
                .en: "A delving party returned from the dark beneath \(regionName).",
                .cs: "Výprava se vrátila z podzemí kraje \(regionName)."])
        case .anomaly:
            return LocalizedText(values: [
                .en: "The anomaly at \(regionName) yielded strange insight — and stirred.",
                .cs: "Anomálie v kraji \(regionName) vydala zvláštní poznání — a pohnula se."])
        case .sanctuary:
            return LocalizedText(values: [
                .en: "Pilgrims returned from the sanctuary of \(regionName), lighter of heart.",
                .cs: "Poutníci se vrátili ze svatyně v kraji \(regionName) s lehčím srdcem."])
        case .lostCity:
            return LocalizedText(values: [
                .en: "The dead city of \(regionName) gave up its hoards to the salvage crews.",
                .cs: "Mrtvé město v kraji \(regionName) vydalo své poklady."])
        default:
            return LocalizedText(values: [
                .en: "An expedition returned from \(regionName).",
                .cs: "Výprava se vrátila z kraje \(regionName)."])
        }
    }

    // MARK: - Site behaviours

    private static func excavateRuins(_ s: inout WorldState, region: Region, hazard: Double, registry: GameDataRegistry, rng: inout SeededRNG) -> SiteOutcome {
        let rewards = Resources([
            .knowledge: 40 + hazard * 8,
            .influence: 20 + hazard * 4
        ])
        grant(&s, rewards)
        let item = dropItem(&s, registry: registry, hazard: hazard, rng: &rng)
        let found = item.map { " Amid the rubble lies \($0)." } ?? ""
        return SiteOutcome(
            kind: .ruins, regionName: region.name, rewards: rewards,
            itemFound: item,
            narrative: "Your scholars sift the ruins of \(region.name), recovering lost knowledge and relics of influence.\(found)"
        )
    }

    private static func delveDungeon(_ s: inout WorldState, region: Region, hazard: Double, registry: GameDataRegistry, rng: inout SeededRNG) -> SiteOutcome {
        let rewards = Resources([
            .materials: 60 + hazard * 12,
            .influence: 30 + hazard * 6
        ])
        grant(&s, rewards)
        let item = dropItem(&s, registry: registry, hazard: hazard, rng: &rng)

        // Risk: the deeper (more hazardous) the dungeon, the worse the danger.
        var casualtyName: String?
        var died = false
        if let capital = s.settlements.indices.first, !s.settlements[capital].pawns.isEmpty {
            let injuryRoll = rng.nextUnit()
            let injuryChance = min(0.85, 0.25 + hazard * 0.06)
            if injuryRoll < injuryChance {
                // Hurt the healthiest colonist (the one who went in).
                let pawnIndex = s.settlements[capital].pawns.indices
                    .max { s.settlements[capital].pawns[$0].health < s.settlements[capital].pawns[$1].health }!
                let damage = 20 + hazard * 5
                var pawn = s.settlements[capital].pawns[pawnIndex]
                pawn.health = max(0, pawn.health - damage)
                casualtyName = pawn.name
                if pawn.health <= 0 {
                    died = true
                    s.settlements[capital].pawns.remove(at: pawnIndex)
                    s.settlements[capital].deathTallies[PawnDeathCause.beast.rawValue, default: 0] += 1
                    s.settlements[capital].stats.morale = max(0, s.settlements[capital].stats.morale - 10)
                } else {
                    s.settlements[capital].pawns[pawnIndex] = pawn
                }
            }
        }

        let fate = died ? " \(casualtyName!) did not return."
            : (casualtyName != nil ? " \(casualtyName!) was wounded in the dark." : "")
        let loot = item.map { " They hauled out \($0)." } ?? ""
        return SiteOutcome(
            kind: .dungeon, regionName: region.name, rewards: rewards,
            casualtyName: casualtyName, died: died, threatGain: 0,
            itemFound: item,
            narrative: "A delving party plunders \(region.name) for materials and influence.\(fate)\(loot)"
        )
    }

    private static func probeAnomaly(_ s: inout WorldState, region: Region, hazard: Double) -> SiteOutcome {
        let rewards = Resources([.knowledge: 50 + hazard * 10])
        grant(&s, rewards)
        let threatGain = hazard * 2
        s.globalStats = s.globalStats.applying(delta: threatGain, to: "threatLevel")
        return SiteOutcome(
            kind: .anomaly, regionName: region.name, rewards: rewards,
            casualtyName: nil, died: false, threatGain: threatGain,
            narrative: "Studying the anomaly at \(region.name) yields strange insight — but stirs something best left sleeping."
        )
    }

    /// A pilgrimage to a sacred valley: no loot to speak of, but the whole
    /// colony comes home lighter — rest, health, devotion, and standing for
    /// the Leader who ordered the walk.
    private static func makePilgrimage(_ s: inout WorldState, region: Region, hazard: Double) -> SiteOutcome {
        let rewards = Resources([.influence: 25 + hazard * 5])
        grant(&s, rewards)
        if let capital = s.settlements.indices.first {
            for i in s.settlements[capital].pawns.indices {
                s.settlements[capital].pawns[i].needs.recreation =
                    min(100, s.settlements[capital].pawns[i].needs.recreation + 10)
                s.settlements[capital].pawns[i].health =
                    min(100, s.settlements[capital].pawns[i].health + 5)
            }
            if s.settlements[capital].faith.cultID != nil {
                s.settlements[capital].faith.faith = min(100, s.settlements[capital].faith.faith + 8)
            }
            s.settlements[capital].stats.morale = min(100, s.settlements[capital].stats.morale + 6)
        }
        return SiteOutcome(
            kind: .sanctuary, regionName: region.name, rewards: rewards,
            narrative: "Pilgrims walk to the sanctuary of \(region.name) and return rested, healed, and surer of their Leader."
        )
    }

    /// How many salvage runs a dead city holds before it's picked clean.
    public static let lostCityVisits = 3

    /// Salvaging a dead city: the richest haul on the map, a real chance of a
    /// find — and a real chance the rubble takes someone's blood for it. Each
    /// return trip digs deeper for less.
    private static func salvageLostCity(_ s: inout WorldState, region: Region, hazard: Double, visits: Int, registry: GameDataRegistry, rng: inout SeededRNG) -> SiteOutcome {
        let depletion = max(0.4, 1 - Double(visits) * 0.3)   // 1.0 → 0.7 → 0.4
        let rewards = Resources([
            .materials: (50 + hazard * 10) * depletion,
            .knowledge: (30 + hazard * 6) * depletion
        ])
        grant(&s, rewards)
        // The bones of a city hide better things than a plain ruin does.
        let item = dropItem(&s, registry: registry, hazard: hazard + 3, rng: &rng)

        var casualtyName: String?
        if let capital = s.settlements.indices.first, !s.settlements[capital].pawns.isEmpty,
           rng.nextUnit() < min(0.5, 0.15 + hazard * 0.03) {
            let pawnIndex = s.settlements[capital].pawns.indices
                .max { s.settlements[capital].pawns[$0].health < s.settlements[capital].pawns[$1].health }!
            let wound = (15 + hazard * 4)
                * CombatEngine.woundMultiplier(s.settlements[capital].pawns[pawnIndex])
            s.settlements[capital].pawns[pawnIndex].health = max(
                1, s.settlements[capital].pawns[pawnIndex].health - wound)   // hurt, never killed
            casualtyName = s.settlements[capital].pawns[pawnIndex].name
        }

        let fate = casualtyName.map { " A wall came down on \($0)." } ?? ""
        let loot = item.map { " Among the bones of the city: \($0)." } ?? ""
        let remaining = lostCityVisits - visits - 1
        let more = remaining > 0
            ? " The ruins clearly hold more — worth \(remaining) more run\(remaining == 1 ? "" : "s")."
            : " The city is picked clean."
        return SiteOutcome(
            kind: .lostCity, regionName: region.name, rewards: rewards,
            casualtyName: casualtyName, died: false,
            itemFound: item,
            narrative: "Salvage crews strip the dead city of \(region.name) of what its builders left behind.\(fate)\(loot)\(more)"
        )
    }

    // MARK: - Helpers

    /// Adds rewards to the capital's storage (clamped to capacity).
    private static func grant(_ s: inout WorldState, _ rewards: Resources) {
        for resource in ResourceType.allCases where rewards[resource] != 0 {
            EffectApplier.applyResourceDelta(&s, resource: resource, delta: rewards[resource], scope: .global)
        }
    }

    /// Rolls a single item drop (rarer the deeper the site), adds it to the
    /// capital's inventory, and returns its display name. Deterministic.
    private static func dropItem(_ s: inout WorldState, registry: GameDataRegistry, hazard: Double, rng: inout SeededRNG) -> String? {
        let defs = lootPool(registry: registry)
        guard !defs.isEmpty, let capital = s.settlements.indices.first else { return nil }
        let weights = defs.map { rarityWeight($0.rarity, hazard) }
        guard let index = rng.weightedIndex(weights) else { return nil }
        let def = defs[index]
        s.settlements[capital].inventory.append(ItemInstance(id: rng.nextUUID(), definitionID: def.id))
        return "the \(def.name.resolve(.en)) (\(def.rarity.rawValue))"
    }

    /// Drop weight shifts toward rarer items as hazard (distance) rises.
    static func rarityWeight(_ rarity: ItemRarity, _ hazard: Double) -> Double {
        rarity.dropWeight + hazard * Double(rarity.index) * 0.6
    }

    /// What a dead city or a buried cache can plausibly hold.
    ///
    /// Gear and artifacts always; a *material* only when the colony has no
    /// other way to get it. Once ordinary materials became things you dig up
    /// and process, leaving them in the loot table turned every treasure into
    /// a sack of clay — and made the rare alloys that gate the deep recipes
    /// vanishingly unlikely. Derived from the data rather than a hand-kept
    /// list, so a new craftable material stops being treasure the moment
    /// someone writes its recipe.
    public static func lootPool(registry: GameDataRegistry) -> [ItemDefinition] {
        let produced = Set(registry.recipes.values.map(\.outputItemID))
        let gathered = Set(LocalResourceKind.allCases.compactMap(\.rawMaterialID))
            .union([ResourceLoop.hideItemID])
        return registry.items.values
            .filter { item in
                guard item.slot == .material else { return true }
                return !produced.contains(item.id) && !gathered.contains(item.id)
            }
            .sorted { $0.id < $1.id }
    }

    static func siteSeed(mapSeed: UInt64, coord: HexCoord, tick: Int) -> UInt64 {
        var h = mapSeed &* 0x9E37_79B9_7F4A_7C15
        h = (h ^ UInt64(bitPattern: Int64(coord.q))) &* 0xD1B5_4A32_D192_ED03
        h = (h ^ UInt64(bitPattern: Int64(coord.r))) &* 0xCBF2_9CE4_8422_2325
        h = (h ^ UInt64(bitPattern: Int64(tick))) &* 0x1000_0000_01B3
        return h ^ (h >> 31)
    }

    private static func siteEventType(_ kind: RegionKind) -> EventType {
        switch kind {
        case .dungeon: return .threat
        case .anomaly: return .threat
        default: return .opportunity
        }
    }
}
