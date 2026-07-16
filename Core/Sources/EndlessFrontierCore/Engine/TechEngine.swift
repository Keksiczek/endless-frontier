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
        s.researchProgress += drawKnowledge(&s)
        guard s.researchProgress >= cost(of: tech, in: s, config: registry.config) else { return s }

        // Complete the research. A repeatable study is never struck off the
        // board — it banks a completion, which makes the next run dearer and
        // stacks its effect again.
        s.researchedTechs.insert(tech.id)
        if tech.repeatable {
            s.techCompletions[tech.id, default: 0] += 1
        }
        s.researchProgress = 0
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

    /// Spends every settlement's banked knowledge on the active study, and
    /// returns how much was drawn. With nothing being researched, knowledge
    /// simply accumulates — so a colony can stockpile before committing.
    static func drawKnowledge(_ s: inout WorldState) -> Double {
        var drawn = 0.0
        for index in s.settlements.indices {
            let banked = s.settlements[index].storage[.knowledge]
            guard banked > 0 else { continue }
            s.settlements[index].storage[.knowledge] = 0
            drawn += banked
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
