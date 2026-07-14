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
    // Eating: colonists eat once hunger dips below the threshold. At steady
    // state this costs decay/hungerPerMeal × foodPerMeal ≈ 0.1 food per
    // person per tick — the whole settlement's food upkeep, now that every
    // inhabitant is a pawn.
    static let foodPerMeal: Double = 1.0
    static let hungerPerMeal: Double = 6.0
    static let mealHungerThreshold: Double = 70
    // Work output per skill point per tick for the assigned resource.
    static let outputPerSkill: Double = 0.15
    // How strongly colony morale tracks average pawn mood.
    static let moraleFollowRate: Double = 0.1
    // Health: starvation damage when hunger is empty, passive recovery otherwise.
    static let starvationHealthDamage: Double = 2.0
    static let healthRecovery: Double = 0.3
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
    /// `registry` resolves equipment buffs; an empty registry = no items.
    public static func advanceOneTick(
        _ settlement: Settlement,
        registry: GameDataRegistry = GameDataRegistry(),
        tick: Int = 0,
        gatheringFactors: [WorkKind: Double] = [:]
    ) -> Settlement {
        guard !settlement.pawns.isEmpty else { return settlement }
        var s = settlement
        var food = s.storage[.food]
        var output = Resources()
        let ticksPerYear = registry.config.ticksPerYear
        let adultAgeTicks = Pawn.adultAgeYears * ticksPerYear
        // Season factors are constant across the settlement's pawns this tick.
        var seasonByResource: [ResourceType: Double] = [:]
        for resource in ResourceType.allCases {
            seasonByResource[resource] = registry.config.seasonYieldMultiplier(for: resource, tick: tick)
        }

        // Mutate pawns in place (index loop) to avoid rebuilding the array and
        // copying every pawn's dictionaries each tick — this runs up to 43,200
        // times on offline catch-up, so allocation churn matters.
        for i in s.pawns.indices {
            // Needs decay.
            s.pawns[i].needs.hunger -= hungerDecay
            s.pawns[i].needs.rest = s.pawns[i].needs.rest - restDecay + restRecovery
            s.pawns[i].needs.recreation = s.pawns[i].needs.recreation - recreationDecay + recreationRecovery

            // Eat if hungry and food is available.
            if food >= foodPerMeal, s.pawns[i].needs.hunger < mealHungerThreshold {
                food -= foodPerMeal
                s.pawns[i].needs.hunger += hungerPerMeal
            }
            s.pawns[i].needs = s.pawns[i].needs.clamped()

            // Health: starvation hurts, otherwise the body slowly recovers.
            let hasEquipment = !s.pawns[i].equipment.isEmpty
            if s.pawns[i].needs.hunger <= 0 {
                s.pawns[i].health -= starvationHealthDamage
            } else {
                let regen = hasEquipment ? ItemEngine.healthRegenBonus(s.pawns[i], registry: registry) : 0
                s.pawns[i].health = min(100, s.pawns[i].health + healthRecovery + regen)
            }
            s.pawns[i].health = max(0, s.pawns[i].health)

            // Mood from needs + trait + equipment, clamped.
            let moodBonus = hasEquipment ? ItemEngine.moodBonus(s.pawns[i], registry: registry) : 0
            s.pawns[i].mood = min(max(s.pawns[i].needs.average + s.pawns[i].trait.moodModifier + moodBonus, 0), 100)

            // Mental break with hysteresis.
            if s.pawns[i].mood < breakEnterMood {
                s.pawns[i].isBroken = true
            } else if s.pawns[i].mood >= breakExitMood {
                s.pawns[i].isBroken = false
            }

            // Work output + learning-by-doing — adults only, and not broken.
            if !s.pawns[i].isBroken, s.pawns[i].age >= adultAgeTicks,
               let resource = s.pawns[i].assignedWork.resource {
                let work = s.pawns[i].assignedWork
                let moodFactor = 0.5 + 0.5 * (s.pawns[i].mood / 100)   // 0.5…1.0
                let skillBonus = hasEquipment ? ItemEngine.skillBonus(s.pawns[i], work: work, registry: registry) : 0
                let effectiveSkill = s.pawns[i].skill(work) + skillBonus
                let seasonFactor = seasonByResource[resource] ?? 1
                let gatherFactor = gatheringFactors[work] ?? 1.0
                output[resource] = output[resource]
                    + Double(effectiveSkill) * outputPerSkill * moodFactor * seasonFactor * gatherFactor

                var xp = (s.pawns[i].skillXP[work] ?? 0) + xpPerTickWorking
                let level = s.pawns[i].skill(work)
                if xp >= xpPerLevel, level < maxSkill {
                    s.pawns[i].skills[work] = level + 1
                    xp -= xpPerLevel
                }
                s.pawns[i].skillXP[work] = xp
            }
        }

        // Commit eaten food and work output to storage.
        s.storage[.food] = food
        for resource in ResourceType.allCases where output[resource] != 0 {
            s.storage[resource] = min(s.storage[resource] + output[resource], s.storageCapacity)
        }

        // Death (removal, cause tallies, inheritance, morale) is handled by
        // `PopulationEngine`, which runs right after this engine each tick.

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
