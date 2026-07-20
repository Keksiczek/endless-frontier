import Foundation

/// Faith: a prophet stirs the people, a temple is raised, a cult takes root, and
/// devotion rises or wanes with the priests who tend it. Belief lifts spirits in
/// good years and softens the blow in bad ones.
///
/// Deterministic — rolls come from `(mapSeed, settlement.id, year)`.
public enum FaithEngine {
    /// Devotion a newborn cult starts with.
    static let foundingFaith: Double = 20
    /// Faith each priest sustains per year.
    static let faithPerPriestPerYear: Double = 4
    /// Faith bleeds away without tending.
    static let faithDecayPerYear: Double = 2
    /// A great rite is held every few years, if the cult has priests.
    static let riteIntervalYears = 4
    static let riteFaithGain: Double = 10
    static let riteMoraleGain: Double = 6
    /// Chance per year that a prophet appears in a temple-less settlement.
    static let prophetChance = 0.12
    /// Chance a prophet in a settled cult turns the people to a new faith.
    static let conversionChance = 0.35

    /// A year of faith for every settlement. Called from `SocietyEngine`'s year.
    public static func advanceYear(_ state: WorldState, registry: GameDataRegistry) -> WorldState {
        guard !registry.cults.isEmpty else { return state }
        var s = state
        let year = s.year(registry.config)
        let ticksPerYear = registry.config.ticksPerYear

        for i in s.settlements.indices {
            var rng = SeededRNG(seed: faithSeed(mapSeed: s.mapSeed,
                                                settlementID: s.settlements[i].id, year: year))
            var faith = s.settlements[i].faith

            // A temple, once raised by law, gives a cult somewhere to live.
            if faith.cultID == nil, SocietyEngine.hasLaw(s.settlements[i], "temple") {
                let cults = registry.cults.keys.sorted()
                let pick = cults[Int(rng.next() % UInt64(cults.count))]
                faith.cultID = pick
                faith.faith = foundingFaith
                faith.prophetStirring = false
            }

            let priests = s.settlements[i].pawns.filter {
                $0.assignedWork == .priest && $0.isAdult(ticksPerYear: ticksPerYear)
            }.count

            if faith.hasTemple {
                faith.faith += Double(priests) * faithPerPriestPerYear - faithDecayPerYear
                faith.faith = min(100, max(0, faith.faith))

                // A great rite: the whole settlement gathers, and takes heart.
                if year > 0, year % riteIntervalYears == 0, priests > 0 {
                    faith.faith = min(100, faith.faith + riteFaithGain)
                    faith.rites += 1
                    s.settlements[i].stats.morale = min(
                        100, s.settlements[i].stats.morale + riteMoraleGain)
                }

                // A prophet may yet turn the people to another faith entirely.
                if rng.nextUnit() < prophetChance {
                    if rng.nextUnit() < conversionChance {
                        let cults = registry.cults.keys.sorted().filter { $0 != faith.cultID }
                        if !cults.isEmpty {
                            faith.cultID = cults[Int(rng.next() % UInt64(cults.count))]
                            faith.faith = max(10, faith.faith - 15)   // a schism costs devotion
                        }
                    } else {
                        faith.faith = max(0, faith.faith - 20)        // a false prophet sows doubt
                    }
                }
            } else if rng.nextUnit() < prophetChance {
                // No temple: a prophet walks in and starts preaching for one.
                faith.prophetStirring = true
            }

            s.settlements[i].faith = faith
        }
        return s
    }

    /// The morale a settlement's devotion adds — belief is comfort.
    public static func moraleBonus(_ settlement: Settlement, registry: GameDataRegistry) -> Double {
        guard let cultID = settlement.faith.cultID, let cult = registry.cult(cultID) else { return 0 }
        return cult.moraleAtFullFaith * (settlement.faith.faith / 100)
    }

    /// How much a settlement's faith softens a blow (0…1). Used to damp the
    /// tension spike a disaster leaves behind.
    public static func solace(_ settlement: Settlement, registry: GameDataRegistry) -> Double {
        guard let cultID = settlement.faith.cultID, let cult = registry.cult(cultID) else { return 0 }
        return cult.solace * (settlement.faith.faith / 100)
    }

    static func faithSeed(mapSeed: UInt64, settlementID: UUID, year: Int) -> UInt64 {
        var h: UInt64 = mapSeed &* 0xCBF2_9CE4_8422_2325
        let b = settlementID.uuid
        let lo = UInt64(b.8) << 56 | UInt64(b.9) << 48 | UInt64(b.10) << 40 | UInt64(b.11) << 32
            | UInt64(b.12) << 24 | UInt64(b.13) << 16 | UInt64(b.14) << 8 | UInt64(b.15)
        h ^= lo
        h = (h ^ UInt64(bitPattern: Int64(year))) &* 0x0100_0000_01B3
        return h ^ (h >> 23)
    }
}
