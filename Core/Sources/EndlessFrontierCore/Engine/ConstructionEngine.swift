import Foundation

/// Raises queued buildings tick by tick. Buildings used to appear the instant
/// they were paid for — there was no moment where the colony *worked* on
/// anything, no scaffolding to watch, and the `.building` trade did nothing.
/// Now a paid building is a site: builders push it forward, the site is drawn
/// on the canvas, and the roof going on is a moment the journal records.
///
/// Pure and deterministic — progress is a function of who is assigned to
/// `.building` work, with no randomness at all.
public enum ConstructionEngine {
    /// Work points a site accrues per tick even with nobody assigned — the
    /// colony as a whole chips in between other chores. Keeps a site from
    /// stalling forever in a tiny colony.
    static let baseProgressPerTick = 0.4
    /// Work points each working builder adds per tick…
    static let progressPerBuilder = 1.0
    /// …plus a little more for every point of building skill.
    static let progressPerSkillPoint = 0.08
    /// Bounds on how much work a building takes, whatever it cost. The floor
    /// keeps a hut from finishing before anyone walked to the site; the cap
    /// keeps a wonder from taking a decade.
    static let minimumWork = 5.0
    static let maximumWork = 140.0
    /// One resource unit of build cost translates to this many work points.
    static let workPerCostUnit = 0.6

    /// How many builders the sites currently justify — used by the labour
    /// quota so the trade only draws hands while there is something to raise.
    static let buildersPerSite = 2
    static let maxDraftedBuilders = 4

    /// Total work required to raise one instance of a building.
    public static func workRequired(for def: BuildingDefinition) -> Double {
        let totalCost = ResourceType.allCases.reduce(0.0) { $0 + def.cost[$1] }
        return min(maximumWork, max(minimumWork, totalCost * workPerCostUnit))
    }

    /// Advances every open site in a settlement one tick: drafts hands if the
    /// sites stand idle, adds progress, and completes what's finished —
    /// incrementing the economy ledger, unveiling the grid placement, freeing
    /// the builders and writing the journal.
    public static func advanceOneTick(
        _ settlement: Settlement,
        registry: GameDataRegistry,
        tick: Int
    ) -> Settlement {
        guard !settlement.constructions.isEmpty else { return settlement }
        var s = settlement
        let ticksPerYear = max(1, registry.config.ticksPerYear)
        let adultAgeTicks = Pawn.adultAgeYears * ticksPerYear

        // Who is actually swinging a hammer this tick.
        var builders = s.pawns.enumerated().filter { _, pawn in
            pawn.assignedWork == .building && !pawn.isBroken && pawn.age >= adultAgeTicks
        }

        // A site with nobody on it drafts hands from the biggest gathering
        // trade — deterministically, lowest relevant skill first, so the
        // farmhand goes to the site before the master farmer does.
        let wanted = min(maxDraftedBuilders, s.constructions.count * buildersPerSite)
        if builders.count < wanted {
            let draftable = s.pawns.enumerated().filter { _, pawn in
                pawn.age >= adultAgeTicks && !pawn.isBroken
                    && [.farming, .logging, .mining, .foraging, .idle].contains(pawn.assignedWork)
            }
            .sorted { a, b in
                let sa = a.element.skill(a.element.assignedWork)
                let sb = b.element.skill(b.element.assignedWork)
                return sa != sb ? sa < sb : a.element.id.uuidString < b.element.id.uuidString
            }
            for (index, _) in draftable.prefix(wanted - builders.count) {
                s.pawns[index].assignedWork = .building
                builders.append((index, s.pawns[index]))
            }
        }

        // Everyone on site works the *first* open project — one roof at a time
        // goes on faster than four half-raised frames.
        let rate = baseProgressPerTick + builders.reduce(0.0) { total, entry in
            total + progressPerBuilder + Double(entry.element.skill(.building)) * progressPerSkillPoint
        }

        guard !s.constructions.isEmpty else { return s }
        s.constructions[0].progress += rate

        // Builders learn the trade by doing it.
        for (index, _) in builders {
            var xp = (s.pawns[index].skillXP[.building] ?? 0) + PawnEngine.xpPerTickWorking
            let level = s.pawns[index].skill(.building)
            if xp >= PawnEngine.xpPerLevel, level < PawnEngine.maxSkill {
                s.pawns[index].skills[.building] = level + 1
                xp -= PawnEngine.xpPerLevel
            }
            s.pawns[index].skillXP[.building] = xp
        }

        // Raise what's finished.
        while let first = s.constructions.first, first.progress >= first.required {
            s.constructions.removeFirst()
            s = complete(first, in: s, registry: registry, tick: tick)
        }

        // The last roof is on: release the crew back into the labour pool, so
        // the quota engine can spread them where the colony needs hands next.
        if s.constructions.isEmpty {
            for i in s.pawns.indices where s.pawns[i].assignedWork == .building {
                s.pawns[i].assignedWork = .idle
            }
        }
        return s
    }

    /// Adds the finished building to the economy ledger, unveils its grid
    /// placement, and records the moment.
    static func complete(
        _ project: ConstructionProject,
        in settlement: Settlement,
        registry: GameDataRegistry,
        tick: Int
    ) -> Settlement {
        var s = settlement
        if let i = s.buildings.firstIndex(where: { $0.definitionID == project.definitionID }) {
            s.buildings[i].count += 1
        } else {
            // The instance id must be derived, not random: completion happens
            // inside the tick path, where a fresh `UUID()` would make two
            // identical worlds diverge — the determinism invariant.
            s.buildings.append(BuildingInstance(
                id: instanceID(definitionID: project.definitionID, projectID: project.id, tick: tick),
                definitionID: project.definitionID, count: 1))
        }
        if let placementID = project.placementID, var map = s.colony,
           let pi = map.placements.firstIndex(where: { $0.id == placementID }) {
            map.placements[pi].underConstruction = false
            s.colony = map
        }
        // Each language gets the building's name *in that language* — the
        // diary should not say "Stavba dokončena: Foundry".
        let name = registry.building(project.definitionID)?.name
            ?? LocalizedText(project.definitionID)
        s.journal.append(tick: tick, kind: .construction, text: LocalizedText(values: [
            .en: "The \(name.resolve(.en)) is finished — the builders lay down their tools.",
            .cs: "Stavba dokončena: \(name.resolve(.cs)). Stavitelé odkládají nářadí."
        ]), subject: project.placementID.map { .building($0) })
        return s
    }

    /// A stable id for a completed building's ledger entry, hashed from what
    /// finished and when (FNV-1a style, matching the engine's other ids).
    static func instanceID(definitionID: String, projectID: Int, tick: Int) -> UUID {
        var h: UInt64 = 0x9E37_79B9_7F4A_7C15
        for byte in definitionID.utf8 {
            h = (h ^ UInt64(byte)) &* 0x0100_0000_01B3
        }
        h = (h ^ UInt64(bitPattern: Int64(projectID))) &* 0x0100_0000_01B3
        h = (h ^ UInt64(bitPattern: Int64(tick))) &* 0x0100_0000_01B3
        var rng = SeededRNG(seed: h ^ (h >> 31))
        return rng.nextUUID()
    }

    /// Queues a project for a building (already paid for), returning the new
    /// settlement. The journal notes that ground was broken.
    public static func enqueue(
        _ settlement: Settlement,
        definitionID: String,
        placementID: UUID?,
        registry: GameDataRegistry,
        tick: Int
    ) -> Settlement {
        guard let def = registry.building(definitionID) else { return settlement }
        var s = settlement
        s.constructions.append(ConstructionProject(
            id: s.constructionSequence,
            definitionID: definitionID,
            placementID: placementID,
            startedTick: tick,
            required: workRequired(for: def)))
        s.constructionSequence += 1
        s.journal.append(tick: tick, kind: .construction, text: LocalizedText(values: [
            .en: "Ground is broken for a \(def.name.resolve(.en)).",
            .cs: "Začala stavba: \(def.name.resolve(.cs))."
        ]), subject: placementID.map { .building($0) })
        return s
    }
}
