import Foundation

/// Derives the player's current objectives from world state. Pure and
/// deterministic; recomputed whenever the UI needs it.
///
/// **Every line here ships in both languages.** It did not: the whole file was
/// English string literals, printed straight by `ObjectivesPanel` — so the one
/// surface in the game that answers *"what should I do next"* answered a Czech
/// player in English. The bilingual guard walks `GameData`, and none of this is
/// in `GameData`; it is Swift in an engine, which is exactly the blind spot.
/// `ObjectivesLanguageTests` closes it.
public enum ObjectivesEngine {
    /// Returns up to `limit` prioritised objectives.
    public static func current(_ state: WorldState, registry: GameDataRegistry, limit: Int = 6) -> [Objective] {
        var objectives: [Objective] = []
        objectives += colonistObjectives(state)
        objectives += defenseObjectives(state, registry: registry)
        objectives += housingObjectives(state, registry: registry)
        objectives += eraObjectives(state, registry: registry)
        objectives += researchObjectives(state, registry: registry)
        objectives += siteObjectives(state)
        objectives += explorationObjectives(state)
        objectives += expansionObjectives(state)
        objectives += tradeObjectives(state)
        objectives += specializationObjectives(state)

        return Array(objectives.sorted { $0.priority < $1.priority }.prefix(limit))
    }

    /// One line, said twice. Short enough to keep each objective readable as a
    /// pair rather than as two paragraphs of ceremony.
    private static func t(_ en: String, _ cs: String) -> LocalizedText {
        LocalizedText(values: [.en: en, .cs: cs])
    }

    private static func housingObjectives(_ state: WorldState, registry: GameDataRegistry) -> [Objective] {
        for settlement in state.settlements {
            let capacity = ResourceLoop.housingCapacity(settlement, registry: registry)
            if capacity > 0, settlement.population >= capacity * 0.85 {
                let now = Int(settlement.population), room = Int(capacity)
                return [Objective(
                    id: "build_housing",
                    title: t("Build more housing", "Postavit další bydlení"),
                    detail: t("\(settlement.name) is filling up (\(now)/\(room)). Crowding stalls growth and dents morale.",
                              "\(settlement.name) se plní (\(now)/\(room)). V těsnu se přestává rodit a klesá morálka."),
                    progress: min(1, settlement.population / capacity),
                    category: .expand, priority: 4
                )]
            }
        }
        return []
    }

    // MARK: - Sources

    private static func defenseObjectives(_ state: WorldState, registry: GameDataRegistry) -> [Objective] {
        guard state.globalStats.threatLevel >= 50, let capital = state.settlements.first else { return [] }
        let effectiveDefense = capital.stats.defense + EffectApplier.militiaDefense(capital.pawns, registry: registry)
        guard effectiveDefense < 25 else { return [] }
        return [Objective(
            id: "prepare_defense",
            title: t("Prepare your defenses", "Připravit obranu"),
            detail: t("Threat is rising and \(capital.name) is poorly defended. Build walls, arm colonists with weapons, or raise the threat away.",
                      "Hrozba roste a \(capital.name) je špatně bráněná. Postav hradby, dej lidem do rukou zbraně, nebo hrozbu odvrať."),
            progress: min(1, effectiveDefense / 25),
            category: .colonists, priority: 2
        )]
    }

    private static func colonistObjectives(_ state: WorldState) -> [Objective] {
        var result: [Objective] = []
        let allPawns = state.settlements.flatMap(\.pawns)
        if let hurt = allPawns.filter({ $0.health < 40 }).min(by: { $0.health < $1.health }) {
            let health = Int(hurt.health)
            result.append(Objective(
                id: "tend_\(hurt.id)",
                title: t("Tend to \(hurt.name)", "Ošetřit \(hurt.name)"),
                detail: t("A colonist is badly hurt (health \(health)). Find care before it's too late.",
                          "Osadník je těžce zraněný (zdraví \(health)). Sežeň pomoc, než bude pozdě."),
                progress: hurt.health / 100,
                category: .colonists, priority: 0
            ))
        }
        if allPawns.contains(where: { $0.isBroken }) {
            result.append(Objective(
                id: "morale_break",
                title: t("Lift the colony's spirits", "Zvednout náladu v osadě"),
                detail: t("A colonist has broken under the strain. Improve food, rest and morale.",
                          "Někomu to přerostlo přes hlavu. Přidej jídlo, odpočinek a důvod k radosti."),
                category: .colonists, priority: 1
            ))
        }
        return result
    }

    private static func eraObjectives(_ state: WorldState, registry: GameDataRegistry) -> [Objective] {
        guard let nextEra = state.era.next,
              let definition = registry.eraDefinition(nextEra) else { return [] }
        return definition.milestones
            .filter { !EraEngine.isSatisfied($0, in: state) }
            .map { milestone in objective(for: milestone, nextEra: nextEra, state: state, registry: registry) }
    }

    /// What a global stat is called to somebody who does not read the engine.
    ///
    /// The era objectives printed the raw key — *"Raise threatLevel to 60"* —
    /// which is a field name, in English, in a sentence.
    private static func statName(_ stat: String) -> LocalizedText {
        switch stat {
        case "prosperity":       return t("prosperity", "prosperitu")
        case "stability":        return t("stability", "stabilitu")
        case "threatLevel":      return t("the threat level", "úroveň hrozby")
        case "knowledgeOutput":  return t("knowledge output", "přísun vědění")
        case "influenceOutput":  return t("influence", "vliv")
        case "population":       return t("population", "počet obyvatel")
        default:
            if let resource = ResourceType(rawValue: stat) { return resource.displayNameLocalized }
            return LocalizedText(stat)
        }
    }

    private static func objective(
        for milestone: EraMilestone,
        nextEra: Era,
        state: WorldState,
        registry: GameDataRegistry
    ) -> Objective {
        // The age's own name, in the player's language — this used to be the
        // enum's raw value with the underscores taken out.
        let eraEN = nextEra.displayName.resolve(.en)
        let eraCS = nextEra.displayName.resolve(.cs)
        switch milestone {
        case let .techResearched(id):
            let tech = registry.tech(id)
            return Objective(
                id: "era_tech_\(id)",
                title: t("Research \(tech?.name.resolve(.en) ?? id)",
                         "Vyzkoumat \(tech?.name.resolve(.cs) ?? id)"),
                detail: t("A key advance toward the \(eraEN) era.",
                          "Klíčový krok k éře \(eraCS)."),
                category: .era, priority: 10
            )
        case let .globalStat(stat, min):
            let current = WorldQuery.globalValue(stat, in: state)
            let name = statName(stat)
            return Objective(
                id: "era_stat_\(stat)",
                title: t("Raise \(name.resolve(.en)) to \(Int(min))",
                         "Zvednout \(name.resolve(.cs)) na \(Int(min))"),
                detail: t("Now \(Int(current)). Needed for the \(eraEN) era.",
                          "Teď \(Int(current)). Bez toho éra \(eraCS) nepřijde."),
                progress: min > 0 ? current / min : nil,
                category: .era, priority: 11
            )
        case let .settlementCount(min):
            return Objective(
                id: "era_settlements",
                title: t("Hold \(min) settlements", "Držet \(min) osad"),
                detail: t("Now \(state.settlements.count). Expand toward the \(eraEN) era.",
                          "Teď \(state.settlements.count). Rozšiř se k éře \(eraCS)."),
                progress: Double(state.settlements.count) / Double(min),
                category: .era, priority: 12
            )
        case let .populationTotal(min):
            return Objective(
                id: "era_population",
                title: t("Grow to \(Int(min)) population", "Dorůst na \(Int(min)) duší"),
                detail: t("Now \(Int(state.totalPopulation)). Needed for the \(eraEN) era.",
                          "Teď \(Int(state.totalPopulation)). Bez toho éra \(eraCS) nepřijde."),
                progress: state.totalPopulation / min,
                category: .era, priority: 12
            )
        }
    }

    private static func researchObjectives(_ state: WorldState, registry: GameDataRegistry) -> [Objective] {
        guard state.activeResearch == nil,
              !registry.availableTechs(researched: state.researchedTechs).isEmpty else { return [] }
        return [Objective(
            id: "pick_research",
            title: t("Choose a research project", "Vybrat, co zkoumat"),
            detail: t("Your scholars are idle. Pick the next technology to pursue.",
                      "Učenci zahálejí. Vyber jim další věc, po které mají jít."),
            category: .research, priority: 5
        )]
    }

    private static func siteObjectives(_ state: WorldState) -> [Objective] {
        guard let site = state.regions.first(where: { $0.hasActiveSite }) else { return [] }
        let verb: LocalizedText
        switch site.kind {
        case .ruins:   verb = t("Excavate the ruins", "Prokopat zříceniny")
        case .dungeon: verb = t("Delve the dungeon", "Sestoupit do podzemí")
        case .anomaly: verb = t("Probe the anomaly", "Prozkoumat anomálii")
        default:       verb = t("Investigate", "Podívat se na to")
        }
        return [Objective(
            id: "site_\(site.id)",
            title: t("\(verb.resolve(.en)) at \(site.name)", "\(verb.resolve(.cs)) — \(site.name)"),
            detail: t("An uncovered site awaits — risk and reward both grow with distance.",
                      "Odkryté místo čeká — čím dál, tím větší riziko i kořist."),
            category: .sites, priority: 20
        )]
    }

    private static func explorationObjectives(_ state: WorldState) -> [Objective] {
        guard state.activeExpedition == nil,
              !ExplorationEngine.exploreableRegions(state).isEmpty else { return [] }
        return [Objective(
            id: "explore",
            title: t("Push the frontier", "Posunout hranici"),
            detail: t("Unknown land lies just beyond your borders. Send an expedition.",
                      "Hned za hranicí leží neprochozená země. Vyprav výpravu."),
            category: .explore, priority: 25
        )]
    }

    private static func expansionObjectives(_ state: WorldState) -> [Objective] {
        guard !ExpansionEngine.foundableRegions(state).isEmpty else { return [] }
        return [Objective(
            id: "found_outpost",
            title: t("Found a new outpost", "Založit novou osadu"),
            detail: t("Charted land is ready to settle. Expand your reach.",
                      "Zmapovaná země je připravená k osídlení. Rozšiř svůj dosah."),
            category: .expand, priority: 30
        )]
    }

    /// Nudges the player to supply a settlement that is cut off from the
    /// capital (and isn't already the target of a caravan) — it loses stability
    /// while isolated.
    private static func tradeObjectives(_ state: WorldState) -> [Objective] {
        guard state.settlements.count > 1 else { return [] }
        let connected = MultiCityEngine.connectedSettlementIDs(state)
        guard let stranded = state.settlements.first(where: { settlement in
            settlement.kind != .capital
                && !connected.contains(settlement.id)
                && !state.caravans.contains { $0.destinationID == settlement.id }
        }) else { return [] }
        return [Objective(
            id: "supply_\(stranded.id)",
            title: t("Supply \(stranded.name)", "Zásobit \(stranded.name)"),
            detail: t("\(stranded.name) is cut off from the capital and bleeding stability. Run a trade route or send a caravan.",
                      "\(stranded.name) je odříznutá od hlavního města a ztrácí stabilitu. Zaveď obchodní cestu nebo pošli karavanu."),
            category: .expand, priority: 27
        )]
    }

    /// Suggests giving an established, still-balanced settlement an economic
    /// focus, surfacing the specialisation mechanic.
    private static func specializationObjectives(_ state: WorldState) -> [Objective] {
        guard let target = state.settlements.first(where: {
            $0.specialization == .balanced && $0.population >= 20
        }) else { return [] }
        return [Objective(
            id: "specialise_\(target.id)",
            title: t("Specialise \(target.name)", "Zaměřit \(target.name)"),
            detail: t("Give \(target.name) an economic focus — farming, industry, scholarship, defense or trade — to sharpen its output.",
                      "Dej osadě \(target.name) zaměření — hospodářství, průmysl, učení, obrana nebo obchod — ať v něčem vyniká."),
            category: .expand, priority: 34
        )]
    }
}
