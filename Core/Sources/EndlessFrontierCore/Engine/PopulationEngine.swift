import Foundation

/// Why a colonist died — tallied per settlement for the chronicle and the
/// analytics charts ("deaths by cause").
public enum PawnDeathCause: String, Codable, Sendable, CaseIterable {
    case starvation
    case sickness
    case oldAge = "old_age"
    case beast
    case battle
    /// Killed by the work itself — a cave roof, a wall of a dead city.
    case accident

    /// Player-facing label, for the journal and the chronicle.
    public var label: LocalizedText {
        switch self {
        case .starvation: return LocalizedText(values: [.en: "starvation", .cs: "hlad"])
        case .sickness: return LocalizedText(values: [.en: "sickness", .cs: "nemoc"])
        case .oldAge: return LocalizedText(values: [.en: "old age", .cs: "stáří"])
        case .beast: return LocalizedText(values: [.en: "a beast", .cs: "šelma"])
        case .battle: return LocalizedText(values: [.en: "battle", .cs: "boj"])
        case .accident: return LocalizedText(values: [.en: "an accident", .cs: "neštěstí"])
        }
    }
}

/// The deterministic life cycle of a settlement's inhabitants: aging, death
/// (with cause and inheritance), pregnancy and birth with gene mutation.
///
/// Runs once per tick per settlement, after `PawnEngine` has updated needs
/// and health. All randomness comes from a seed derived from
/// `(mapSeed, settlement.id, tick)`, so identical worlds live identical lives.
public enum PopulationEngine {
    // MARK: - Fertility is a person's own, and it tapers

    /// The years a colonist *may* be able to have children, at the widest.
    ///
    /// A hard 16–46 for everybody was a cliff, and it showed: a founding party
    /// who were all twenty-five left the window in the same year, and a colony
    /// with three marriages had **one** that could have children, measured, for
    /// two centuries. Nobody's body works to the same calendar.
    ///
    /// So the window is drawn from the colonist's own `genes.fertility`, and it
    /// does not end in a wall — `fertilityAt` tapers it over the last quarter,
    /// so a couple in their forties are less likely to have a child rather than
    /// forbidden one.
    static let fertileMinYears = 15
    static let fertileMaxYears = 52

    /// This colonist's own last fertile year: 40 at the low end of the gene,
    /// 52 at the high. The first year is 15 or 16, which matters less.
    static func lastFertileYear(_ genes: Genes) -> Double {
        40 + genes.fertility * 12
    }

    static func firstFertileYear(_ genes: Genes) -> Double {
        17 - genes.fertility * 2
    }

    /// How fertile this colonist is *right now*, 0…1.
    ///
    /// Flat through the middle of their window and tapering to nothing over the
    /// last quarter of it, so the end of a life's fertility is a slope somebody
    /// lives down rather than a birthday they fall off.
    static func fertilityAt(years: Double, genes: Genes) -> Double {
        let first = firstFertileYear(genes), last = lastFertileYear(genes)
        guard years >= first, years < last else { return 0 }
        let taperFrom = first + (last - first) * 0.75
        guard years > taperFrom else { return 1 }
        return max(0, (last - years) / (last - taperFrom))
    }
    /// How long a pregnancy lasts, in ticks (half a year at 60 ticks/year).
    static let pregnancyTicks = 30
    // MARK: - Children come out of a bond, not out of a birth rate

    /// How long a settled, happy couple takes to have a child, in years.
    ///
    /// This replaces `baseBirthChancePerTick`, and the difference is not the
    /// number — it is *what is rolled*. Every fertile colonist used to roll a
    /// private dice each tick and being married multiplied it by 1.6, so a
    /// colony's children were a coefficient with a marriage bonus stapled on:
    /// people who had never met each other had babies at nearly the rate of
    /// people who had spent a life together.
    ///
    /// Now the roll is on the **bond**. Two colonists meet, chat, grow close,
    /// wed (`SocialEngine`), and *then* the couple may have a child — sooner
    /// the stronger the bond, and not at all until it is one. The colony's
    /// growth is a consequence of its social life rather than a parallel number
    /// running beside it, which is the same move the wood, the stone, the wild
    /// and the harvest have all already made.
    ///
    /// Three years, so a couple who marry young have a family and a couple who
    /// marry late have a child or two. Still a per-tick chance underneath —
    /// this is a tick-based simulation — but it is a chance *this couple* takes,
    /// and it is stated as the thing a player could actually observe.
    static let yearsToConceive = 2.5

    /// A bond has to be this strong before a couple starts a family, and this
    /// strong to be as ready as a couple gets.
    ///
    /// Weddings happen at 45 and set the bond to at least 70, so a newly
    /// married couple starts two-thirds of the way up this ramp and a settled
    /// one is at the top of it. The first cut put the floor at 60 against a
    /// ceiling of 100, which made a wedding worth a quarter of a family and the
    /// colony died out in a hundred and thirty years.
    static let readyStrength = 50.0
    static let settledStrength = 80.0

    /// …and this long between children, in years. A couple with a baby in the
    /// house is not looking for another one. Held on the bond
    /// (`Relationship.lastChildTick`), because it is a fact about them.
    static let yearsBetweenChildren = 2.5
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
        birthRateMultiplier: Double = 1,
        language: GameLanguage = .cs
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
                let years = death.pawn.ageYears(ticksPerYear: ticksPerYear)
                s.journal.append(tick: tick, kind: .death, text: LocalizedText(values: [
                    .en: "\(death.pawn.name) has died at \(years) — \(death.cause.label.resolve(.en)).",
                    .cs: "\(death.pawn.name) zemřel(a) v \(years) letech — \(death.cause.label.resolve(.cs))."
                ]))
                // Those who loved them grieve, and their bonds are laid to rest.
                s = SocialEngine.mourn(s, dead: death.pawn, tick: tick)
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
                // The other parent, where there is one — a child takes after
                // both, which is also what makes the gene drift in the chronicle
                // a story about a *colony* rather than about one bloodline.
                let partnerID = s.partnerID(of: s.pawns[index].id)
                let partnerGenes = partnerID
                    .flatMap { id in s.pawns.first { $0.id == id } }?.genes
                let child = newborn(parent: &s.pawns[index], other: partnerGenes,
                                    rng: &rng, language: language)
                let names = partnerID
                    .flatMap { id in s.pawns.first { $0.id == id } }
                    .map { "\(s.pawns[index].name) and \($0.name)" } ?? s.pawns[index].name
                let namesCS = partnerID
                    .flatMap { id in s.pawns.first { $0.id == id } }
                    .map { "\(s.pawns[index].name) a \($0.name)" } ?? s.pawns[index].name
                s.journal.append(tick: tick, kind: .birth, text: LocalizedText(values: [
                    .en: "\(names) welcomed a child — \(child.name).",
                    .cs: "\(namesCS) přivedli na svět dítě — \(child.name)."
                ]))
                s.pawns.append(child)
                // The bond remembers. It is what spaces the next one.
                if let partnerID,
                   let bond = s.relationships.firstIndex(where: {
                       $0.kind == .partner && $0.involves(s.pawns[index].id)
                           && $0.involves(partnerID) }) {
                    s.relationships[bond].lastChildTick = tick
                }
            }
        }

        // 4. Children, out of the bonds that make them.
        //
        //    Walked over the **couples**, not over the colonists. Crowding still
        //    cools things gradually — families slow long before the last hut is
        //    full — but the thing being rolled is a partnership: two people who
        //    met, grew close and married, and are now ready.
        let headroom = headroomFactor(population: s.population, capacity: capacity)
        if headroom > 0 {
            s = conceive(s, rng: &rng, tick: tick, ticksPerYear: ticksPerYear,
                         headroom: headroom, multiplier: birthRateMultiplier)
        }

        return s
    }

    /// Gives the colony's couples their chance at a child, in bond order.
    ///
    /// Deterministic: the bonds are walked in their stored order and every roll
    /// comes off the settlement's own stream, so the same world raises the same
    /// families. Which of the two carries the child is decided by their genes
    /// and broken on id — never by the array, which reorders as people die.
    static func conceive(
        _ settlement: Settlement, rng: inout SeededRNG, tick: Int, ticksPerYear: Int,
        headroom: Double, multiplier: Double
    ) -> Settlement {
        var s = settlement
        let perTick = 1 / (yearsToConceive * Double(max(1, ticksPerYear)))
        let spacing = Int(yearsBetweenChildren * Double(max(1, ticksPerYear)))
        var index: [UUID: Int] = [:]
        for (i, pawn) in s.pawns.enumerated() { index[pawn.id] = i }

        for bond in s.relationships where bond.kind == .partner {
            // A family already on the way, or one only just begun.
            if let last = bond.lastChildTick, tick - last < spacing { continue }
            guard let ai = index[bond.a], let bi = index[bond.b] else { continue }
            let first = s.pawns[ai], second = s.pawns[bi]
            guard first.pregnancyTicksRemaining == 0,
                  second.pregnancyTicksRemaining == 0 else { continue }
            // Both of them have to be on their feet, and both able.
            guard [first, second].allSatisfy({ !$0.isBroken && $0.health > 0 })
            else { continue }
            // Each brings their own fertility, and it is a slope rather than a
            // birthday: a couple in their forties are less likely, not barred.
            let able = [first, second].map {
                fertilityAt(years: Double($0.ageYears(ticksPerYear: ticksPerYear)),
                            genes: $0.genes)
            }
            guard let least = able.min(), least > 0 else { continue }

            // How ready they are: a new marriage is not a family yet, and a
            // bond that has grown into one is.
            let readiness = min(1, (bond.strength - readyStrength)
                                / (settledStrength - readyStrength))
            guard readiness > 0 else { continue }

            // The couple is as fertile as the less fertile of them.
            let fertility = least * (able[0] + able[1]) / 2
            let mood = min(1.4, max(0.3, (first.mood + second.mood) / 140))
            let chance = perTick * readiness * fertility * mood * headroom * multiplier
            guard rng.nextUnit() < chance else { continue }

            // Whichever of them carries it — decided, not drawn, so a replay
            // puts the child in the same arms.
            let carrier = first.genes.fertility == second.genes.fertility
                ? (first.id.uuidString < second.id.uuidString ? ai : bi)
                : (first.genes.fertility > second.genes.fertility ? ai : bi)
            s.pawns[carrier].pregnancyTicksRemaining = pregnancyTicks
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
    /// A child of one parent, or — where there is a partner — of two.
    ///
    /// Genes are the midpoint of both lines before the mutation, so a colony's
    /// drift is the drift of everybody in it rather than of whoever happened to
    /// carry the most children. Before this a newborn was a mutated copy of one
    /// parent and the other might as well not have existed.
    static func newborn(
        parent: inout Pawn, other: Genes? = nil,
        rng: inout SeededRNG, language: GameLanguage = .cs
    ) -> Pawn {
        let dowry = parent.wealth * dowryShare
        parent.wealth -= dowry
        let traits = PawnTrait.allCases
        let inherited = other.map { parent.genes.blended(with: $0) } ?? parent.genes
        return Pawn(
            id: rng.nextUUID(),
            name: PawnFactory.name(using: &rng, language: language),
            trait: traits[Int(rng.next() % UInt64(traits.count))],
            age: 0,
            genes: inherited.mutated(using: &rng),
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
