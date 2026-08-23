import Foundation

/// **What the council wants to build next, and why.**
///
/// Keks, watching his own town: *"steward staví knihovny a univerzity několikrát
/// a nijaké výrobní nebo obranné budovy ne… chtělo by, aby stavěli nějak
/// rozumně, ideálně zase dle předpokladů lidí z rady."*
///
/// He is describing one line. `StewardEngine.nextBuilding`'s last clause —
/// the one that runs for the whole of the late game, once the fields, roofs,
/// stores, larder and lights are answered — was:
///
/// ```swift
/// let novel = affordable.filter { !standing.contains($0.id) }
/// return (novel.isEmpty ? affordable : novel).min { cheapest by materials }
/// ```
///
/// **Breadth first, then the cheapest thing on the shelf, for ever.** Once one
/// of every kind stands, `novel` is empty and the colony spends every surplus
/// on whatever happens to cost least — and an observatory is cheap, so the
/// town gets a fifth one while the smithy it has no room for and the wall it
/// has no soldiers behind are never chosen. Nothing in that line asks what the
/// colony is short of, and nothing asks who is on the council.
///
/// This is the answer to both. Every affordable building is scored, and the
/// score has five parts:
///
/// | part | question |
/// |---|---|
/// | `wants` | what does this colony not make enough of? |
/// | `hands` | is there a trade with people in it and nowhere to work? |
/// | `walls` | is there anything out there, and can we meet it? |
/// | `again` | how many of these are already standing? |
/// | `taste` | **who is on the council**, and what do they think matters? |
///
/// `taste` is the part Keks asked for by name, and it is deliberately the
/// smallest: a council of brave people builds the wall *sooner*, not instead
/// of the granary. The colony's needs decide what is possible; its people
/// decide the order.
public enum CouncilAppetite {

    /// How far the council's own character may tilt a score, either way.
    /// Small on purpose — it colours the choice, it does not make it.
    static let tasteReach = 0.35

    /// The score below which the council would rather keep the materials.
    /// Nothing is *always* worth building.
    static let worthBuilding = 0.15

    /// How much of the colony works a trade before it wants a second place to
    /// do it in.
    static let handsPerWorkplace = 6.0

    /// Defence the colony wants per soul, when there is anything out there.
    /// Read against `SettlementStats.defense`, which is what a siege actually
    /// consults.
    static let defencePerSoul = 0.9

    // MARK: - The score

    /// What this building is worth to this colony, now. Zero means "no reason
    /// at all"; `StewardEngine` only builds above `worthBuilding`.
    public static func score(
        _ def: BuildingDefinition, for settlement: Settlement,
        in state: WorldState, registry: GameDataRegistry
    ) -> Double {
        let people = max(1, settlement.population)
        let standing = Double(settlement.buildings
            .first { $0.definitionID == def.id }?.count ?? 0)

        var want = wants(def, settlement: settlement, registry: registry, people: people)
        want += hands(def, settlement: settlement, registry: registry)
        want += walls(def, settlement: settlement, in: state, people: people)
        want += breadth(def, standing: standing)
        guard want > 0 else { return 0 }

        // **Diminishing returns, and this is the whole of the observatory
        // problem.** The fifth of a thing is worth a fifth of the first: a
        // colony that keeps answering the same want with the same building has
        // stopped answering it.
        want /= (1 + standing)

        // What the people in the room make of it.
        want *= 1 + taste(def, settlement: settlement, registry: registry)

        // …and what it costs to get. Not a divisor on its own — a colony that
        // always buys the cheapest is the fault this replaces — but a dear
        // building has to be proportionally more wanted than a cheap one.
        let price = max(10, def.cost[.materials])
        return want * (60 / (40 + price))
    }

    // MARK: - What the colony is short of

    /// **What it does not make enough of.** Read against what it already
    /// produces per soul rather than against a constant, so a big town wanting
    /// a second smithy and a hamlet wanting its first are the same question.
    static func wants(
        _ def: BuildingDefinition, settlement: Settlement,
        registry: GameDataRegistry, people: Double
    ) -> Double {
        var out = 0.0
        for resource in ResourceType.allCases {
            let made = def.production[resource]
            guard made > 0 else { continue }
            let already = production(of: resource, at: settlement, registry: registry)
            // Per twenty souls, which is roughly one working building's worth.
            let perHead = already / max(1, people / 20)
            out += made * scarcity(perHead) * appetite(for: resource)
        }
        return out
    }

    /// A falling curve: the first of something is worth much, the tenth little.
    static func scarcity(_ perHead: Double) -> Double { 1 / (1 + max(0, perHead)) }

    /// What a colony cares about, by resource. Materials and food build and
    /// feed; knowledge and standing are worth having and are not worth a fifth
    /// library.
    static func appetite(for resource: ResourceType) -> Double {
        switch resource {
        case .materials: return 1.0
        case .food: return 1.0
        case .energy: return 0.8
        case .knowledge: return 0.55
        case .influence: return 0.45
        }
    }

    /// What the colony's standing buildings already make of a resource, per
    /// tick. The honest denominator for "do we need another one of these".
    static func production(
        of resource: ResourceType, at settlement: Settlement, registry: GameDataRegistry
    ) -> Double {
        settlement.buildings.reduce(0) { total, instance in
            guard let def = registry.building(instance.definitionID) else { return total }
            return total + def.production[resource] * Double(instance.count)
        }
    }

    // MARK: - Hands with nowhere to work

    /// **A trade with people in it and nowhere to do it.** This is the clause
    /// that gets a smithy built: `LaborEngine` puts colonists into crafting,
    /// and a crafter with no bench is a colonist standing in a field pretending.
    static func hands(
        _ def: BuildingDefinition, settlement: Settlement, registry: GameDataRegistry
    ) -> Double {
        guard let work = def.work else { return 0 }
        let workers = Double(settlement.pawns.count { $0.assignedWork == work })
        guard workers > 0 else { return 0 }
        let places = settlement.buildings.reduce(0.0) { total, instance in
            guard let other = registry.building(instance.definitionID),
                  other.work == work else { return total }
            return total + Double(other.workers * instance.count)
        }
        let wanted = workers / handsPerWorkplace
        guard places < wanted else { return 0 }
        // How short, as a share of what the trade wants — so a town with eight
        // crafters and one bench asks louder than one with two and none.
        return min(1.4, (wanted - places) / max(0.5, wanted)) * 1.2
    }

    // MARK: - Whether anything is out there

    /// Defence is only worth building against something. A valley with no
    /// camps, no soured neighbours and a quiet wood does not want a wall, and
    /// a council that builds one anyway is the same fault as the observatory.
    static func walls(
        _ def: BuildingDefinition, settlement: Settlement,
        in state: WorldState, people: Double
    ) -> Double {
        guard def.defense > 0 else { return 0 }
        let camps = Double(state.camps.count { $0.isActive(at: state.tick) })
        let soured = Double(state.tribes.count { $0.standing < 0 })
        let beasts = (settlement.localMap?.wildlife.predatorPressure ?? 0) / 40
        let threat = min(2.5, camps * 0.5 + soured * 0.6 + beasts)
        guard threat > 0 else { return 0 }
        let held = settlement.stats.defense / max(1, people)
        guard held < defencePerSoul else { return 0 }
        let short = (defencePerSoul - held) / defencePerSoul
        return min(1.6, def.defense / 20 * short * threat)
    }

    /// A kind the colony has none of is worth something for its own sake — a
    /// town with no temple and no market is a poorer place than the ledger
    /// says. Small, and only for the first one.
    ///
    /// **A wall is not breadth.** A building whose only gift is defence is an
    /// answer to something being out there, and `walls` is where that question
    /// is asked; letting it in here would have a peaceful valley raising a
    /// palisade for the look of the thing, which is the same fault as the
    /// fifth observatory wearing armour.
    static func breadth(_ def: BuildingDefinition, standing: Double) -> Double {
        guard standing == 0 else { return 0 }
        let onlyDefends = def.defense > 0
            && def.housing == 0
            && def.storage.amounts.allSatisfy { $0.value <= 0 }
            && ResourceType.allCases.allSatisfy { def.production[$0] <= 0 }
        return onlyDefends ? 0 : 0.35
    }

    // MARK: - Who is on the council

    /// **The people in the room.**
    ///
    /// Keks: *"ideálně dle předpokladů lidí z rady."* The colony already has
    /// everything this needs — the assembly reads `Pawn.genes` to vote
    /// (`AssemblyEngine`), the leader is a real person with a trade — and
    /// nothing at all read them when it came to what to build.
    ///
    /// Read as a *tilt*, never a decision: `tasteReach` caps it at about a
    /// third either way, so a council of soldiers builds the wall sooner than
    /// a council of scholars would, and neither of them lets the fields go.
    ///
    /// The leader counts double, because it is their name on it.
    static func taste(
        _ def: BuildingDefinition, settlement: Settlement, registry: GameDataRegistry
    ) -> Double {
        let ticksPerYear = max(1, registry.config.ticksPerYear)
        let council = settlement.pawns.filter { $0.isAdult(ticksPerYear: ticksPerYear) }
        guard !council.isEmpty else { return 0 }

        var industry = 0.0, courage = 0.0, sociability = 0.0, weight = 0.0
        var scholars = 0.0
        for pawn in council {
            let mine = pawn.id == settlement.leaderID ? 2.0 : 1.0
            industry += pawn.genes.industry * mine
            courage += pawn.genes.courage * mine
            sociability += pawn.genes.sociability * mine
            if pawn.assignedWork == .research { scholars += mine }
            weight += mine
        }
        industry /= weight; courage /= weight; sociability /= weight
        let learned = scholars / weight

        // Each gene reads as its distance from the middle, so an ordinary
        // council tilts nothing at all.
        var tilt = 0.0
        if def.production[.materials] > 0 || def.work == .crafting {
            tilt += (industry - 0.5) * 2
        }
        if def.defense > 0 {
            tilt += (courage - 0.5) * 2
        }
        if def.moraleEffect > 0 || def.production[.influence] > 0 {
            tilt += (sociability - 0.5) * 2
        }
        if def.production[.knowledge] > 0 {
            // Not a gene: a colony that has put people into study is a colony
            // whose council contains them.
            tilt += (learned - 0.10) * 4
        }
        return max(-tasteReach, min(tasteReach, tilt * tasteReach))
    }
}
