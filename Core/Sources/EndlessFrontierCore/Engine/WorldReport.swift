import Foundation

/// A full, copy-pasteable readout of why the world is the way it is.
///
/// The old diagnostic logged births, deaths and event names — which answers
/// "what happened" but never "why is nothing happening", and every serious bug
/// in this game so far has been the second question. It could not have shown
/// that tension was pinned at 0, that no disaster could reach the board, that
/// scouts had a job nothing performed, or that an expedition button was lit
/// over an empty woodpile.
///
/// So this reports **state and its reasons**, and ends with the one section
/// that matters most here: what currently *cannot happen at all*. This
/// codebase's signature bug is a threshold set above anything the system
/// driving it can produce — a gate at 70 under a ceiling of 57 — and those are
/// invisible in a log of events that fired.
public enum WorldReport {
    /// A system that cannot fire right now, and the number that proves it.
    public struct Blocker: Sendable, Equatable {
        public let system: String
        public let reason: String
    }

    // MARK: - Reachability

    /// Systems that cannot currently fire, with the measurement that says so.
    public static func blockers(_ s: WorldState, registry: GameDataRegistry) -> [Blocker] {
        var found: [Blocker] = []
        let config = registry.config
        let tension = TensionCalculator.calculate(s, config: config)

        // Disasters are weighted by band, so a colony parked in the calmest band
        // sees them at 0.5× — rare by design. Silent forever is not.
        if let band = config.tensionBands.first(where: { tension <= $0.maxTension }),
           band.disasterWeight <= 0 {
            found.append(Blocker(
                system: "disasters",
                reason: "tension \(Int(tension)) selects a band with disasterWeight 0"))
        }

        // The classic: a friendly gate above what relations can climb to.
        let ceiling = DiplomacyEngine.baseCompatibility + DiplomacyEngine.faithAffinity
        if DiplomacyEngine.marriageStanding > ceiling {
            found.append(Blocker(
                system: "tribe marriage",
                reason: "needs standing > \(Int(DiplomacyEngine.marriageStanding)) but compatibility tops out at \(Int(ceiling))"))
        }

        // Native peoples wait beyond the fog; until one is met (or malcontents
        // walk out), the diplomacy layer is scenery.
        if !s.tribes.contains(where: \.discovered), !s.tribes.isEmpty {
            found.append(Blocker(
                system: "diplomacy",
                reason: "\(s.tribes.count) native people(s) live beyond the fog — send expeditions to make first contact"))
        }
        if s.tribes.isEmpty, let seat = s.settlements.first {
            let gini = seat.society.gini
            if gini <= DiplomacyEngine.secessionGiniThreshold
                && seat.stats.morale >= DiplomacyEngine.secessionMoraleThreshold {
                found.append(Blocker(
                    system: "tribes / all diplomacy",
                    reason: "no neighbours yet; gini \(fmt(gini)) < \(DiplomacyEngine.secessionGiniThreshold) and morale \(Int(seat.stats.morale)) > \(Int(DiplomacyEngine.secessionMoraleThreshold)), so nobody has cause to leave"))
            }
        }

        // Scouts with nothing to chart, or ground nobody is charting.
        if let seat = s.settlements.first, let map = seat.localMap {
            let scouts = seat.pawns.filter { $0.assignedWork == .scouting }.count
            if scouts == 0 && map.exploredFraction < 1 {
                found.append(Blocker(
                    system: "settlement map",
                    reason: "\(Int(map.exploredFraction * 100))% charted and no scouts assigned — the fog will not move"))
            }
        }

        // An expedition button over an empty woodpile.
        if s.activeExpedition == nil {
            let reachable = ExplorationEngine.exploreableRegions(s)
            if reachable.isEmpty {
                found.append(Blocker(
                    system: "world exploration",
                    reason: "no unknown region borders explored ground"))
            } else if !reachable.contains(where: {
                ExplorationEngine.canAfford(expeditionTo: $0, in: s, registry: registry)
            }) {
                let cost = ExplorationEngine.expeditionCost(to: reachable[0], config: config)
                found.append(Blocker(
                    system: "world exploration",
                    reason: "\(reachable.count) region(s) in reach but none affordable — cheapest wants \(costText(cost))"))
            }
        }

        // Research that can never finish because nobody makes knowledge.
        if s.activeResearch != nil, s.globalStats.knowledgeOutput <= 0,
           s.settlements.allSatisfy({ $0.storage[.knowledge] <= 0 }) {
            found.append(Blocker(
                system: "research",
                reason: "a study is set but knowledge output is 0 and nothing is banked"))
        }

        // Era gates nobody can see.
        if let next = s.era.next, let definition = registry.eraDefinition(next) {
            let unmet = definition.milestones.filter { !EraEngine.isSatisfied($0, in: s) }
            if unmet.count == definition.milestones.count, !definition.milestones.isEmpty {
                found.append(Blocker(
                    system: "era \(next.rawValue)",
                    reason: "none of its \(definition.milestones.count) milestones met"))
            }
        }
        return found
    }

    // MARK: - The report

    public static func generate(_ s: WorldState, registry: GameDataRegistry) -> String {
        let config = registry.config
        var out: [String] = []
        func section(_ title: String) { out.append(""); out.append("── \(title) ──") }
        func row(_ label: String, _ value: String) {
            out.append("  " + label.padding(toLength: max(22, label.count + 1), withPad: " ", startingAt: 0) + value)
        }

        let year = s.year(config)
        out.append("ENDLESS FRONTIER — WORLD REPORT")
        out.append("seed \(s.mapSeed) · tick \(s.tick) · year \(year) · \(s.season(config)) · schema v\(s.schemaVersion)")

        // --- Why the storyteller is doing what it's doing -----------------
        section("TENSION \(Int(TensionCalculator.calculate(s, config: config)))")
        let stats = s.globalStats
        row("base", fmt(TensionCalculator.baseTension))
        row("+ threat", fmt(stats.threatLevel * config.threatMultiplier) + "  (threat \(Int(stats.threatLevel)))")
        row("− comfort", fmt(TensionCalculator.comfort(prosperity: stats.prosperity, config: config))
            + "  (prosperity \(Int(stats.prosperity)) vs neutral \(Int(config.prosperityNeutral)))")
        row("+ disaster spike", fmt(TensionCalculator.disasterSpike(s, config: config)))
        row("− boom damper", fmt(TensionCalculator.boomDampener(s, config: config)))
        row("+ shortages", fmt(Double(TensionCalculator.shortageCount(s, config: config)) * config.deficitSpikePerResource)
            + "  (\(TensionCalculator.shortageCount(s, config: config)) resource(s) under \(Int(config.shortageFraction * 100))%)")
        row("+ era ramp", fmt(Double(s.era.index) * config.eraRampPerEra))
        row("+ scale", fmt(TensionCalculator.scalePressure(population: s.totalPopulation, config: config))
            + "  (pop \(Int(s.totalPopulation)))")
        let tension = TensionCalculator.calculate(s, config: config)
        if let band = config.tensionBands.first(where: { tension <= $0.maxTension }) {
            row("band", "≤\(Int(band.maxTension)) · disaster ×\(fmt(band.disasterWeight)) · opportunity ×\(fmt(band.opportunityWeight)) · flavour ×\(fmt(band.flavorWeight))")
        }

        // --- The colony ----------------------------------------------------
        for settlement in s.settlements {
            section("SETTLEMENT \(settlement.name)")
            let housing = ResourceLoop.housingCapacity(settlement, registry: registry)
            row("population", "\(Int(settlement.population)) / \(Int(housing)) housed")
            row("morale / stability", "\(Int(settlement.stats.morale)) / \(Int(settlement.stats.stability))")
            row("gini", fmt(settlement.society.gini) + (settlement.society.gini > 0.45 ? "  ← unequal" : ""))
            for resource in ResourceType.allCases {
                let held = settlement.storage[resource]
                let roof = settlement.storageCapacity[resource]
                let pct = roof > 0 ? Int(held / roof * 100) : 0
                var note = ""
                if pct >= 99 { note = "  ← PINNED at cap" }
                if held <= 0 { note = "  ← EMPTY" }
                row("  \(resource)", "\(Int(held)) / \(Int(roof))  (\(pct)%)" + note)
            }
            // Labour: the question "does the automation work?" answered.
            let ticksPerYear = max(1, config.ticksPerYear)
            let adults = settlement.pawns.filter { $0.isAdult(ticksPerYear: ticksPerYear) }
            let children = settlement.pawns.count - adults.count
            row("adults / children", "\(adults.count) / \(children)")
            let byWork = Dictionary(grouping: adults, by: \.assignedWork)
                .map { "\($0.key)=\($0.value.count)" }.sorted()
            row("workforce", byWork.joined(separator: " "))
            let idle = adults.filter { $0.assignedWork == .idle }.count
            if idle > 0 { row("IDLE ADULTS", "\(idle)  ← the labour engine left these standing") }
            if let map = settlement.localMap {
                let scouts = adults.filter { $0.assignedWork == .scouting }.count
                row("ground charted", "\(Int(map.exploredFraction * 100))%  (\(scouts) scout(s))")
            }
            if let colony = settlement.colony {
                row("build grid", "\(colony.placements.count) placed · \(colony.zones.count) zoned")
            } else {
                row("build grid", "none laid out yet")
            }
        }

        // --- The world -----------------------------------------------------
        section("WORLD")
        row("era", "\(s.era.rawValue) → \(s.era.next?.rawValue ?? "—")")
        if let next = s.era.next, let definition = registry.eraDefinition(next) {
            for milestone in definition.milestones {
                let met = EraEngine.isSatisfied(milestone, in: s)
                row("  \(met ? "✓" : "✗") \(milestone)", "")
            }
        }
        let known = s.regions.filter { $0.explorationState != .unknown }.count
        row("regions", "\(known) charted of \(s.regions.count) known")
        let reachable = ExplorationEngine.exploreableRegions(s)
        row("in reach", "\(reachable.count)")
        for region in reachable.prefix(6) {
            let cost = ExplorationEngine.expeditionCost(to: region, config: config)
            let can = ExplorationEngine.canAfford(expeditionTo: region, in: s, registry: registry)
            row("  \(region.name)", "hazard \(region.hazardLevel) · \(costText(cost)) · \(can ? "affordable" : "TOO DEAR")")
        }
        if let expedition = s.activeExpedition {
            row("expedition", "→ \(s.regions.first { $0.id == expedition.targetRegionID }?.name ?? "?") · \(expedition.ticksRemaining) ticks left")
        } else {
            row("expedition", "none out")
        }

        // --- Research ------------------------------------------------------
        section("RESEARCH")
        row("researched", "\(s.researchedTechs.count) of \(registry.techs.count)")
        if let active = s.activeResearch, let tech = registry.tech(active) {
            let price = TechEngine.cost(of: tech, in: s, config: config)
            row("studying", "\(tech.name) · \(Int(s.researchProgress)) / \(Int(price))")
        } else {
            row("studying", "nothing — scholars idle")
        }
        row("knowledge output", fmt(s.globalStats.knowledgeOutput))
        if !s.techCompletions.isEmpty {
            row("endless studies", s.techCompletions.map { "\($0.key)×\($0.value)" }.sorted().joined(separator: " "))
        }

        // --- Neighbours ----------------------------------------------------
        section("NEIGHBOURS")
        if s.tribes.isEmpty {
            row("tribes", "none — the whole diplomacy layer is asleep")
        } else {
            for tribe in s.tribes where tribe.discovered {
                row(tribe.name, "standing \(Int(tribe.standing)) (\(tribe.status)) · pop \(Int(tribe.population)) · wars \(tribe.wars) · married \(tribe.married) · defectors \(tribe.defections)")
            }
            let hidden = s.tribes.filter { !$0.discovered }.count
            if hidden > 0 {
                row("beyond the fog", "\(hidden) native people(s) not yet met")
            }
        }

        // --- Decisions -----------------------------------------------------
        section("DECISIONS")
        if s.pendingEvents.isEmpty {
            row("queued", "none")
        } else {
            for pending in s.pendingEvents {
                let deadline = registry.events.first { $0.id == pending.templateID }?.decisionTicks
                    ?? config.decisionDeadlineTicks
                let left = deadline - (s.tick - pending.tick)
                row("  \(pending.templateID)", "\(left) ticks left" + (left < 0 ? "  ← overdue" : ""))
            }
        }
        row("law motion", s.pendingLawProposal.map { "\($0.definitionID) (council \($0.councilApproves ? "for" : "against"))" } ?? "none")

        // --- What cannot happen --------------------------------------------
        section("CANNOT HAPPEN RIGHT NOW")
        let found = blockers(s, registry: registry)
        if found.isEmpty {
            out.append("  (nothing blocked — every system can fire)")
        } else {
            for blocker in found { out.append("  ✗ \(blocker.system): \(blocker.reason)") }
        }

        return out.joined(separator: "\n")
    }

    // MARK: - Helpers

    static func fmt(_ value: Double) -> String {
        String(format: abs(value) < 10 ? "%.2f" : "%.0f", value)
    }

    static func costText(_ cost: Resources) -> String {
        ResourceType.allCases
            .filter { cost[$0] > 0 }
            .map { "\($0) \(Int(cost[$0].rounded()))" }
            .joined(separator: " + ")
    }
}
