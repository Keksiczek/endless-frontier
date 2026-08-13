import Foundation

/// Research progression and tech effects.
public enum TechEngine {
    /// Accumulates one tick of knowledge output into the active research and
    /// completes it when the cost is met. Returns the new state.
    public static func advanceResearch(_ state: WorldState, registry: GameDataRegistry) -> WorldState {
        var s = state
        guard let activeID = s.activeResearch, let tech = registry.tech(activeID) else {
            return s
        }
        // Research is paid for with knowledge the settlements actually banked —
        // scholars at their desks, not an abstract output figure. (Before V2
        // this read `globalStats.knowledgeOutput`, which only counts *buildings*;
        // once colonists became the source of knowledge that number was zero in
        // a library-less colony, and research silently never moved.)
        let price = cost(of: tech, in: s, config: registry.config)
        // Draw only what this study still lacks. Taking every settlement's bank
        // outright and then resetting progress to zero destroyed the surplus: a
        // colony holding 5,000 that finished a 100-cost tech burned 4,900 of it,
        // which made stockpiling knowledge actively harmful and left the stores
        // reading empty forever.
        // …down to `knowledgeReserve`, and no further. Taking the last point
        // every tick left `storage[.knowledge]` permanently at zero, and a
        // colony with nothing banked can never *buy* anything priced in
        // knowledge — which is every generator above the windmill, the bank,
        // the university and the research campus. See `WorldConfig.knowledgeReserve`.
        s.researchProgress += drawKnowledge(&s, upTo: price - s.researchProgress,
                                            leaving: registry.config.knowledgeReserve)
        guard s.researchProgress >= price else { return s }

        // Complete the research. A repeatable study is never struck off the
        // board — it banks a completion, which makes the next run dearer and
        // stacks its effect again.
        s.researchedTechs.insert(tech.id)
        if tech.repeatable {
            s.techCompletions[tech.id, default: 0] += 1
        }
        s.researchProgress -= price   // carry the overshoot into the next study
        s.activeResearch = nil
        return applyEffects(of: tech, to: s)
    }

    /// What a tech costs to research right now.
    ///
    /// A finite tech costs what its data says. A repeatable one grows by
    /// `repeatableTechCostGrowth` with every completion, so an endless study
    /// keeps pace with a colony whose knowledge output is itself growing —
    /// otherwise it would be a sink only until the scholars caught up with it.
    public static func cost(of tech: TechDefinition, in state: WorldState, config: WorldConfig) -> Double {
        guard tech.repeatable else { return tech.knowledgeCost }
        let completions = state.techCompletions[tech.id] ?? 0
        return tech.knowledgeCost * pow(config.repeatableTechCostGrowth, Double(completions))
    }

    /// Spends up to `limit` of the settlements' banked knowledge on the active
    /// study and returns how much was drawn, taking from each in turn until the
    /// study is paid for. With nothing being researched, knowledge simply
    /// accumulates — so a colony can stockpile before committing, and what it
    /// banks beyond the price stays banked.
    static func drawKnowledge(
        _ s: inout WorldState, upTo limit: Double, leaving reserve: Double = 0
    ) -> Double {
        guard limit > 0 else { return 0 }
        var drawn = 0.0
        for index in s.settlements.indices {
            let remaining = limit - drawn
            guard remaining > 0 else { break }
            let banked = s.settlements[index].storage[.knowledge]
            // The reserve is per settlement, not per realm: it is what makes a
            // *town* able to pay for its own library, and a capital's bank is
            // no use to an outpost that wants one.
            let spendable = banked - reserve
            guard spendable > 0 else { continue }
            let take = min(spendable, remaining)
            s.settlements[index].storage[.knowledge] = banked - take
            drawn += take
        }
        return drawn
    }

    /// Selects the next tech to research, if its prerequisites are met and it
    /// isn't already researched. Resets progress. Returns unchanged state for
    /// an invalid selection.
    public static func setResearch(_ state: WorldState, techID: String, registry: GameDataRegistry) -> WorldState {
        guard let tech = registry.tech(techID),
              !state.researchedTechs.contains(techID) || tech.repeatable,
              tech.requires.allSatisfy(state.researchedTechs.contains) else {
            return state
        }
        var s = state
        s.activeResearch = techID
        s.researchProgress = 0
        return s
    }

    /// Applies a tech's effects (building unlocks, stat modifiers, event
    /// category unlocks) to the world.
    public static func applyEffects(of tech: TechDefinition, to state: WorldState) -> WorldState {
        var s = state
        for effect in tech.effects {
            switch effect {
            case let .unlockBuilding(buildingID):
                s.unlockedBuildings.insert(buildingID)
            case let .modifier(stat, delta, multiplicative):
                let name = stat.hasPrefix("global.") ? String(stat.dropFirst("global.".count)) : stat
                if multiplicative {
                    let current = WorldQuery.globalValue(name, in: s)
                    s.globalStats = s.globalStats.applying(delta: current * (delta - 1), to: name)
                } else {
                    // Banked as a standing bonus as well as applied now: the
                    // output stats are rebuilt from buildings every tick, so a
                    // bump written only onto `globalStats` is erased before the
                    // player ever sees it (`recomputeGlobalStats` re-adds these).
                    s.statModifiers[name, default: 0] += delta
                    s.globalStats = s.globalStats.applying(delta: delta, to: name)
                }
            case let .unlockEventCategory(category):
                s.worldFlags["eventcat:\(category)"] = true
            }
        }
        return s
    }
}
