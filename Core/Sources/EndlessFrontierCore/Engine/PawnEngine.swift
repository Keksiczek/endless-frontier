import Foundation

/// Per-tick simulation of individual colonists (pawns): need decay, eating,
/// mood, skill-based work output, and the colony morale they drive.
///
/// Pure and deterministic. Tuning lives as named constants here for now; it
/// can move into `WorldConfig` once the values settle.
public enum PawnEngine {
    // Need decay per tick (points lost).
    static let hungerDecay: Double = 0.6
    static let restDecay: Double = 0.4
    static let recreationDecay: Double = 0.3
    // Passive recovery per tick for rest/recreation (sleep & downtime, abstracted).
    static let restRecovery: Double = 0.5
    static let recreationRecovery: Double = 0.35
    // Eating: food consumed per pawn per tick to restore hunger.
    static let foodPerMeal: Double = 0.2
    static let hungerPerMeal: Double = 3.0
    // Work output per skill point per tick for the assigned resource.
    static let outputPerSkill: Double = 0.15
    // How strongly colony morale tracks average pawn mood.
    static let moraleFollowRate: Double = 0.1
    // Health: starvation damage when hunger is empty, passive recovery otherwise.
    static let starvationHealthDamage: Double = 2.0
    static let healthRecovery: Double = 0.3
    // Colony morale hit when a colonist dies.
    static let deathMoralePenalty: Double = 10.0
    // Skill growth: XP gained per tick of assigned work, XP per level, and cap.
    static let xpPerTickWorking: Double = 0.5
    static let xpPerLevel: Double = 100
    static let maxSkill: Int = 20
    // Mood break thresholds (hysteresis) and the morale drain while broken.
    static let breakEnterMood: Double = 20
    static let breakExitMood: Double = 40
    static let brokenMoraleDrain: Double = 0.3

    /// Advances every pawn in a settlement one tick and returns the updated
    /// settlement (needs, mood, eaten food, work output, morale drift).
    public static func advanceOneTick(_ settlement: Settlement) -> Settlement {
        guard !settlement.pawns.isEmpty else { return settlement }
        var s = settlement
        var food = s.storage[.food]
        var output = Resources()

        s.pawns = s.pawns.map { pawn in
            var p = pawn
            // Needs decay.
            p.needs.hunger -= hungerDecay
            p.needs.rest = p.needs.rest - restDecay + restRecovery
            p.needs.recreation = p.needs.recreation - recreationDecay + recreationRecovery

            // Eat if food is available.
            if food >= foodPerMeal, p.needs.hunger < 100 {
                food -= foodPerMeal
                p.needs.hunger += hungerPerMeal
            }
            p.needs = p.needs.clamped()

            // Health: starvation hurts, otherwise the body slowly recovers.
            if p.needs.hunger <= 0 {
                p.health -= starvationHealthDamage
            } else {
                p.health = min(100, p.health + healthRecovery)
            }
            p.health = max(0, p.health)

            // Mood from needs + trait, clamped.
            p.mood = min(max(p.needs.average + p.trait.moodModifier, 0), 100)

            // Mental break with hysteresis: break at very low mood, recover
            // only once mood climbs back above the higher threshold.
            if p.mood < breakEnterMood {
                p.isBroken = true
            } else if p.mood >= breakExitMood {
                p.isBroken = false
            }

            // Work output + learning-by-doing, only when working (not broken).
            if !p.isBroken, let resource = p.assignedWork.resource {
                let moodFactor = 0.5 + 0.5 * (p.mood / 100)   // 0.5…1.0
                output[resource] = output[resource]
                    + Double(p.skill(p.assignedWork)) * outputPerSkill * moodFactor

                var xp = (p.skillXP[p.assignedWork] ?? 0) + xpPerTickWorking
                let level = p.skill(p.assignedWork)
                if xp >= xpPerLevel, level < maxSkill {
                    p.skills[p.assignedWork] = level + 1
                    xp -= xpPerLevel
                }
                p.skillXP[p.assignedWork] = xp
            }
            return p
        }

        // Commit eaten food and work output to storage.
        s.storage[.food] = food
        for resource in ResourceType.allCases where output[resource] != 0 {
            s.storage[resource] = min(s.storage[resource] + output[resource], s.storageCapacity)
        }

        // Remove colonists who have died; each death wounds colony morale and
        // the macro headcount.
        let deaths = s.pawns.filter { $0.health <= 0 }.count
        if deaths > 0 {
            s.pawns.removeAll { $0.health <= 0 }
            s.population = max(0, s.population - Double(deaths))
            s.stats.morale -= deathMoralePenalty * Double(deaths)
        }

        // Colony morale drifts toward the colonists' average mood.
        if !s.pawns.isEmpty {
            let averageMood = s.pawns.reduce(0) { $0 + $1.mood } / Double(s.pawns.count)
            s.stats.morale += (averageMood - s.stats.morale) * moraleFollowRate
        }
        // Colonists in a mental break weigh on the whole colony.
        let brokenCount = s.pawns.filter(\.isBroken).count
        if brokenCount > 0 {
            s.stats.morale -= brokenMoraleDrain * Double(brokenCount)
        }
        s.stats = s.stats.clamped()

        return s
    }
}
