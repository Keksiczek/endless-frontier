import Foundation

/// The threat that gets **worse** as the colony gets better.
///
/// Measured over two hundred years of a real world: every death was old age.
/// Not because the fighting was weak — it had just been retuned and a warband
/// can kill twelve bare-handed colonists — but because **every threat in the
/// game scaled with the colony's own strength**. Four hundred people with walls
/// and iron turn back a hundred and forty raiders, and they *should*. A bigger
/// warband is not the answer; it is the same answer written larger.
///
/// A sickness runs the other way. It comes for a town because the town is big,
/// crowded, fed by trade and full of people sleeping four to a room. No number
/// of spears helps and no wall keeps it out. What helps is exactly what a
/// prosperous colony has been putting off: healers, herbs, a clinic, and the
/// willingness to shut the gates and lose a season of work.
///
/// The systems it stands on already existed with almost nothing to do:
/// `AilmentKind.sickness`, `MedicineEngine`'s tending, and the healer's trade.
public enum PlagueEngine {

    /// How often the sickness is stepped, in ticks. Rule 4: the per-tick path is
    /// replayed tens of thousands of times and this is O(pawns).
    public static let interval = 10

    /// A colony smaller than this does not get an epidemic. Not mercy — a
    /// dozen people in three huts is not a place a sickness can *run*, and a
    /// threat that wipes a starting colony is a threat that ends the game
    /// rather than one that shapes it.
    public static let minimumPopulation = 22

    /// The base odds, per step, that something starts. Multiplied by how
    /// crowded, how big and how well-connected the colony is.
    /// Tuned against `DangerProbe`, not chosen: this and `sizeCeiling` together
    /// give a large town something roughly every twenty-five to forty years.
    /// The first cut let the odds grow with population without a ceiling, and a
    /// colony of three hundred and fifty caught something every five years —
    /// 782 people sick across two centuries, and the place starved because it
    /// was never well enough to farm.
    static let sparkChance = 0.0013
    /// The most the colony's sheer size may multiply those odds by. Unbounded,
    /// the rate grows with the town for ever and a big colony is *permanently*
    /// ill — measured, 782 people took sick across two hundred years and the
    /// place starved because it was never well enough to farm. A city is a
    /// worse place to be than a village; it is not a hospice.
    static let sizeCeiling = 3.5
    /// How long after one burns out before another can take hold, in ticks.
    /// Roughly four years: the survivors are the people who survive things,
    /// and the town has just found out where the bad water was.
    static let respiteTicks = 240
    /// Crowding is the whole mechanism: people per bed the colony actually has.
    /// A town living at its housing ceiling is the one that gets sick.
    static let crowdingWeight = 1.4
    /// How much of the spread shutting the gates takes away.
    static let quarantineShield = 0.72
    /// …and what that costs, as a share of every trade's output.
    public static let quarantineWorkPenalty = 0.45
    /// How fast a sickness runs its course, as severity per step.
    static let coursePerStep = 0.055
    /// How much of a sick colonist's health it takes per step at full severity.
    static let harmPerStep = 3.4

    // MARK: - The step

    public static func advanceOneTick(
        _ settlement: Settlement, registry: GameDataRegistry, tick: Int,
        era: Era, season: Season, mapSeed: UInt64
    ) -> Settlement {
        guard tick % interval == 0 else { return settlement }
        var s = settlement
        var rng = SeededRNG(seed: seed(mapSeed: mapSeed, settlementID: s.id, tick: tick))

        if s.outbreak == nil {
            s = maybeStart(s, registry: registry, tick: tick, era: era,
                           season: season, rng: &rng)
        }
        guard var outbreak = s.outbreak,
              let plague = registry.plague(outbreak.plagueID) else { return s }

        s = spread(s, outbreak: &outbreak, plague: plague, season: season, rng: &rng)
        s = run(s, outbreak: &outbreak, plague: plague, tick: tick, rng: &rng)

        if outbreak.isOver {
            s.outbreak = nil
            s.lastOutbreakTick = tick
            s = burnedOut(s, outbreak: outbreak, plague: plague, tick: tick)
        } else {
            s.outbreak = outbreak
        }
        return s
    }

    // MARK: - Where it comes from

    /// Whether something takes hold, and what.
    ///
    /// The odds are the colony's own success: how many people, how tightly they
    /// are living, and how much of the world walks in through the gate.
    static func maybeStart(
        _ settlement: Settlement, registry: GameDataRegistry, tick: Int,
        era: Era, season: Season, rng: inout SeededRNG
    ) -> Settlement {
        var s = settlement
        let people = s.pawns.count
        guard people >= minimumPopulation else { return s }
        if let last = s.lastOutbreakTick, tick - last < respiteTicks { return s }

        let strains = registry.plagues.values
            .filter { $0.eraFrom.index <= era.index }
            .sorted { $0.id < $1.id }
        guard !strains.isEmpty else { return s }
        let plague = strains[Int(rng.nextUnit() * Double(strains.count)) % strains.count]

        let odds = sparkChance
            * min(sizeCeiling, (Double(people) / Double(minimumPopulation)).squareRoot())
            * crowding(s, registry: registry)
            * plague.seasonalBias(season)
            * traffic(s)
        guard rng.nextUnit() < min(0.25, odds) else { return s }

        // It starts with one person, and it is somebody in particular.
        let candidates = s.pawns.filter { $0.health > 0 }
        guard let first = candidates.min(by: {
            $0.id.uuidString < $1.id.uuidString
        }).map({ _ in candidates[Int(rng.nextUnit() * Double(candidates.count)) % candidates.count] })
        else { return s }

        var outbreak = Outbreak(id: rng.nextUUID(), plagueID: plague.id, startedTick: tick)
        outbreak.infected.insert(first.id)
        s = infect(s, pawnID: first.id, plague: plague, tick: tick, rng: &rng)
        s.outbreak = outbreak
        s.journal.append(tick: tick, kind: .danger, text: LocalizedText(values: [
            .en: "\(plague.name.resolve(.en)) has started in the colony — \(first.name) first.",
            .cs: "V osadě se objevila nemoc: \(plague.name.resolve(.cs)) — první je \(first.name)."]))
        return s
    }

    /// People per bed. One is a colony with room; past one it is a colony
    /// sleeping on floors, and that is where a sickness lives.
    static func crowding(_ settlement: Settlement, registry: GameDataRegistry) -> Double {
        let beds = ResourceLoop.housingCapacity(settlement, registry: registry)
        guard beds > 0 else { return 1 + crowdingWeight }
        let ratio = Double(settlement.pawns.count) / beds
        return 1 + max(0, ratio - 0.6) * crowdingWeight
    }

    /// How much of the world comes through the gate. Trade is good for you and
    /// it is also how a sickness arrives.
    static func traffic(_ settlement: Settlement) -> Double {
        1 + Double(settlement.localMap?.visitors.count ?? 0) * 0.25
    }

    // MARK: - How it moves

    private static func spread(
        _ settlement: Settlement, outbreak: inout Outbreak, plague: PlagueDefinition,
        season: Season, rng: inout SeededRNG
    ) -> Settlement {
        var s = settlement
        // Anyone who has already had it does not take it again.
        let open = s.pawns.filter {
            $0.health > 0 && !outbreak.infected.contains($0.id)
                && !outbreak.recovered.contains($0.id)
        }
        guard !open.isEmpty else { return s }

        let shield = outbreak.quarantined ? (1 - quarantineShield) : 1
        let rate = plague.contagion * plague.seasonalBias(season)
            * crowdingFactor(s) * shield
        // Every carrier is an exposure. A big colony is *more* dangerous to be
        // in, which is the whole point of this system existing.
        let exposures = Double(outbreak.infected.count)
        for pawn in open {
            let odds = min(0.5, rate * exposures / Double(max(1, open.count)) * 4)
            guard rng.nextUnit() < odds else { continue }
            outbreak.infected.insert(pawn.id)
            s = infect(s, pawnID: pawn.id, plague: plague,
                       tick: outbreak.startedTick, rng: &rng)
        }
        return s
    }

    /// Sleeping rough and sleeping four to a room are the same thing to a
    /// sickness.
    private static func crowdingFactor(_ settlement: Settlement) -> Double {
        let roofless = settlement.pawns.count { $0.homeID == nil }
        guard settlement.pawns.count > 0 else { return 1 }
        return 1 + Double(roofless) / Double(settlement.pawns.count)
    }

    private static func infect(
        _ settlement: Settlement, pawnID: UUID, plague: PlagueDefinition,
        tick: Int, rng: inout SeededRNG
    ) -> Settlement {
        var s = settlement
        guard let index = s.pawns.firstIndex(where: { $0.id == pawnID }) else { return s }
        var body = s.pawns[index].body
        guard !body.ailments.contains(where: { $0.kind == .sickness }) else { return s }
        body.ailments.append(Ailment(
            id: rng.nextUUID(), kind: .sickness,
            severity: 0.3 + rng.nextUnit() * 0.3 * plague.virulence, sinceTick: tick))
        s.pawns[index].body = body
        return s
    }

    // MARK: - What it does

    /// The course of it: each carrier gets worse, gets seen to, or gets over
    /// it. Tending is what decides which.
    private static func run(
        _ settlement: Settlement, outbreak: inout Outbreak, plague: PlagueDefinition,
        tick: Int, rng: inout SeededRNG
    ) -> Settlement {
        var s = settlement
        var died: [String] = []
        for id in outbreak.infected.sorted(by: { $0.uuidString < $1.uuidString }) {
            guard let index = s.pawns.firstIndex(where: { $0.id == id }) else {
                outbreak.infected.remove(id)
                continue
            }
            guard let slot = s.pawns[index].body.ailments
                .firstIndex(where: { $0.kind == .sickness }) else {
                // Somebody tended them through it: `MedicineEngine` closed the
                // ailment, so they are over it and cannot take it again.
                outbreak.infected.remove(id)
                outbreak.recovered.insert(id)
                continue
            }
            let ailment = s.pawns[index].body.ailments[slot]
            // A tended sickness passes. An untended one deepens.
            let step = ailment.tended ? -coursePerStep * 1.6 : coursePerStep * plague.virulence
            let severity = ailment.severity + step
            if severity <= 0 {
                s.pawns[index].body.ailments.remove(at: slot)
                outbreak.infected.remove(id)
                outbreak.recovered.insert(id)
                continue
            }
            s.pawns[index].body.ailments[slot].severity = min(1, severity)
            s.pawns[index].health = max(0, s.pawns[index].health
                                        - harmPerStep * severity * plague.virulence)
            if s.pawns[index].health <= 0 {
                died.append(s.pawns[index].name)
                outbreak.infected.remove(id)
                outbreak.deaths += 1
            }
        }
        guard !died.isEmpty else { return s }
        s.pawns.removeAll { $0.health <= 0 }
        s.deathTallies[PawnDeathCause.sickness.rawValue, default: 0] += died.count
        s.stats.morale = max(0, s.stats.morale - Double(died.count) * 1.6)
        s.journal.append(tick: tick, kind: .death, text: LocalizedText(values: [
            .en: died.count == 1
                ? "\(died[0]) did not get up. The sickness is still in the colony."
                : "\(died.count) went in one round of the sickness.",
            .cs: died.count == 1
                ? "\(died[0]) už nevstal(a). Nemoc je v osadě dál."
                : "\(died.count) lidí odešlo v jednom kole nemoci."]))
        return s
    }

    private static func burnedOut(
        _ settlement: Settlement, outbreak: Outbreak, plague: PlagueDefinition, tick: Int
    ) -> Settlement {
        var s = settlement
        let entry: LocalizedText
        if outbreak.deaths == 0 {
            entry = LocalizedText(values: [
                .en: "\(plague.name.resolve(.en)) has passed, and it took nobody.",
                .cs: "\(plague.name.resolve(.cs)) přešla a nikoho si nevzala."])
            s.stats.morale = min(100, s.stats.morale + 4)
        } else {
            entry = LocalizedText(values: [
                .en: "\(plague.name.resolve(.en)) has burned itself out. \(outbreak.deaths) are buried.",
                .cs: "\(plague.name.resolve(.cs)) vyhořela. \(outbreak.deaths) pohřbených."])
        }
        s.journal.append(tick: tick, kind: .danger, text: entry)
        return s
    }

    // MARK: - The one order the player has

    /// Shuts the gates, or opens them again. A real decision: it cuts the
    /// spread hard and it costs the work of everybody staying home.
    public static func setQuarantine(_ settlement: Settlement, _ on: Bool) -> Settlement {
        guard var outbreak = settlement.outbreak else { return settlement }
        var s = settlement
        outbreak.quarantined = on
        s.outbreak = outbreak
        return s
    }

    /// What the colony's trades are multiplied by while the gates are shut.
    public static func workFactor(_ settlement: Settlement) -> Double {
        (settlement.outbreak?.quarantined ?? false) ? 1 - quarantineWorkPenalty : 1
    }

    /// From the id's **bytes**, never from `hashValue`: Swift seeds its hasher
    /// per process, so a hash-derived seed replays differently on every launch
    /// and quietly breaks the one invariant the whole simulation rests on.
    /// Puts a named sickness on a named person. Exposed for the tests, which
    /// need to *start* an outbreak rather than wait for one.
    static func testInfect(
        _ settlement: Settlement, pawnID: UUID, plague: PlagueDefinition,
        tick: Int, rng: inout SeededRNG
    ) -> Settlement {
        infect(settlement, pawnID: pawnID, plague: plague, tick: tick, rng: &rng)
    }

    static func seed(mapSeed: UInt64, settlementID: UUID, tick: Int) -> UInt64 {
        var h = mapSeed &* 0x9E37_79B9_7F4A_7C15
        let b = settlementID.uuid
        h ^= UInt64(b.0) << 56 | UInt64(b.1) << 48 | UInt64(b.2) << 40 | UInt64(b.3) << 32
            | UInt64(b.4) << 24 | UInt64(b.5) << 16 | UInt64(b.6) << 8 | UInt64(b.7)
        h = (h ^ UInt64(bitPattern: Int64(tick))) &* 0xD1B5_4A32_D192_ED03
        return (h ^ (h >> 29)) | 1
    }
}
