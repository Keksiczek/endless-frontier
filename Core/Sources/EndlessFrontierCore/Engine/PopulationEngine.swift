import Foundation

/// Why a colonist died — tallied per settlement for the chronicle and the
/// analytics charts ("deaths by cause").
public enum PawnDeathCause: String, Codable, Sendable, CaseIterable {
    case starvation
    case sickness
    case oldAge = "old_age"
    case beast
    case battle
}

/// The deterministic life cycle of a settlement's inhabitants: aging, death
/// (with cause and inheritance), pregnancy and birth with gene mutation.
///
/// Runs once per tick per settlement, after `PawnEngine` has updated needs
/// and health. All randomness comes from a seed derived from
/// `(mapSeed, settlement.id, tick)`, so identical worlds live identical lives.
public enum PopulationEngine {
    // Fertility window (in years).
    static let fertileMinYears = 16
    static let fertileMaxYears = 46
    /// How long a pregnancy lasts, in ticks (half a year at 60 ticks/year).
    static let pregnancyTicks = 30
    /// Per-tick conception chance for a fertile adult at neutral genes/mood,
    /// in an empty settlement. Crowding damps it long before the housing cap
    /// (see `headroomFactor`), so growth is an S-curve rather than a wall.
    static let baseBirthChancePerTick = 0.0018
    /// Everyone lives at least this long; genes stretch it further.
    static let baseLifespanYears = 60.0
    static let lifespanCourageYears = 10.0
    static let lifespanIndustryYears = 8.0
    /// Per-tick chance of passing away once beyond one's lifespan.
    static let oldAgeDeathChancePerTick = 0.002
    /// Colony morale hit per death.
    static let deathMoralePenalty = 8.0
    /// Fraction of a dead colonist's wealth passed to a living kin
    /// (the rest is lost with them).
    static let inheritanceShare = 0.7
    /// Fraction of the parent's wealth a newborn receives as a dowry.
    static let dowryShare = 0.15

    /// Advances one settlement's population one tick.
    public static func advanceOneTick(
        _ settlement: Settlement,
        registry: GameDataRegistry,
        tick: Int,
        mapSeed: UInt64,
        birthRateMultiplier: Double = 1
    ) -> Settlement {
        guard !settlement.pawns.isEmpty else { return settlement }
        var s = settlement
        var rng = SeededRNG(seed: populationSeed(mapSeed: mapSeed, settlementID: s.id, tick: tick))
        let ticksPerYear = registry.config.ticksPerYear

        // 1. Everyone ages one tick.
        for index in s.pawns.indices {
            s.pawns[index].age += 1
        }

        // 2. Deaths: exhausted health (starvation or sickness) and old age.
        var deaths: [(pawn: Pawn, cause: PawnDeathCause)] = []
        for pawn in s.pawns {
            if pawn.health <= 0 {
                deaths.append((pawn, pawn.needs.hunger <= 0 ? .starvation : .sickness))
            } else if Double(pawn.ageYears(ticksPerYear: ticksPerYear)) > lifespanYears(pawn.genes),
                      rng.nextUnit() < oldAgeDeathChancePerTick {
                deaths.append((pawn, .oldAge))
            }
        }
        if !deaths.isEmpty {
            let deadIDs = Set(deaths.map(\.pawn.id))
            s.pawns.removeAll { deadIDs.contains($0.id) }
            for death in deaths {
                s.deathTallies[death.cause.rawValue, default: 0] += 1
                // Inheritance: most of the estate passes to a living kin.
                if death.pawn.wealth > 0, !s.pawns.isEmpty {
                    let heir = Int(rng.next() % UInt64(s.pawns.count))
                    s.pawns[heir].wealth += death.pawn.wealth * inheritanceShare
                }
            }
            s.stats.morale -= deathMoralePenalty * Double(deaths.count)
            s.stats = s.stats.clamped()
        }

        // 3. Births: pregnancies come to term.
        let capacity = ResourceLoop.housingCapacity(s, registry: registry)
        for index in s.pawns.indices {
            guard s.pawns[index].pregnancyTicksRemaining > 0 else { continue }
            s.pawns[index].pregnancyTicksRemaining -= 1
            if s.pawns[index].pregnancyTicksRemaining == 0 {
                let child = newborn(parent: &s.pawns[index], rng: &rng)
                s.pawns.append(child)
            }
        }

        // 4. Conception: fertile, housed, in the mood. Crowding cools ardour
        //    gradually — families slow long before the last hut is full.
        let headroom = headroomFactor(population: s.population, capacity: capacity)
        if headroom > 0 {
            for index in s.pawns.indices {
                let pawn = s.pawns[index]
                guard pawn.pregnancyTicksRemaining == 0 else { continue }
                let years = pawn.ageYears(ticksPerYear: ticksPerYear)
                guard years >= fertileMinYears, years <= fertileMaxYears else { continue }
                let moodFactor = min(1.5, max(0.3, pawn.mood / 70))
                let chance = baseBirthChancePerTick * (pawn.genes.fertility * 2)
                    * moodFactor * birthRateMultiplier * headroom
                if rng.nextUnit() < chance {
                    s.pawns[index].pregnancyTicksRemaining = pregnancyTicks
                }
            }
        }

        return s
    }

    /// How freely a settlement breeds, given how full it already is: full
    /// vigour when empty, tapering to nothing as the housing fills. Squaring
    /// the fraction makes the last quarter of capacity fill slowly, which is
    /// what stops a colony exploding into the thousands.
    static func headroomFactor(population: Double, capacity: Double) -> Double {
        guard capacity > 0 else { return 0 }
        let free = max(0, 1 - population / capacity)
        return free * free
    }

    /// The lifespan a colonist's genes grant, in years.
    static func lifespanYears(_ genes: Genes) -> Double {
        baseLifespanYears + genes.courage * lifespanCourageYears + genes.industry * lifespanIndustryYears
    }

    /// A newborn child: mutated genes, a dowry from the parent, no skills yet.
    static func newborn(parent: inout Pawn, rng: inout SeededRNG) -> Pawn {
        let dowry = parent.wealth * dowryShare
        parent.wealth -= dowry
        let traits = PawnTrait.allCases
        return Pawn(
            id: rng.nextUUID(),
            name: PawnFactory.names[Int(rng.next() % UInt64(PawnFactory.names.count))],
            trait: traits[Int(rng.next() % UInt64(traits.count))],
            age: 0,
            genes: parent.genes.mutated(using: &rng),
            wealth: dowry
        )
    }

    static func populationSeed(mapSeed: UInt64, settlementID: UUID, tick: Int) -> UInt64 {
        var h: UInt64 = mapSeed &* 0x9E37_79B9_7F4A_7C15
        let b = settlementID.uuid
        let hi = UInt64(b.0) << 56 | UInt64(b.1) << 48 | UInt64(b.2) << 40 | UInt64(b.3) << 32
            | UInt64(b.4) << 24 | UInt64(b.5) << 16 | UInt64(b.6) << 8 | UInt64(b.7)
        h ^= hi
        h = (h ^ UInt64(bitPattern: Int64(tick))) &* 0x0100_0000_01B3
        return h ^ (h >> 29)
    }
}
