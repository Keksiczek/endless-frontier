import Foundation

/// **The assembly, one colonist at a time.**
///
/// Keks: *"sněm by mohl být dynamický, že by lidé volili dle svých vlastností,
/// zkušeností, názorů."* The vote already walked the roster — what it read of
/// each person was their four genes and their wealth, against a random term
/// half again as wide as everything else put together, so the tally was mostly
/// a coin flip with a lean on it, and nothing anybody had *lived through* came
/// into the room.
///
/// Six terms now, and every one of them is read off something the simulation
/// already keeps:
///
/// | term | what it reads |
/// |---|---|
/// | nature | `LawDefinition.voteBias` against `Pawn.genes` |
/// | standing | their wealth class, and which way the law cuts |
/// | trade | `LawDefinition.tradeFavour` against what they do for a living |
/// | experience | their years and their skill at that trade |
/// | hardship | hunger, health, mood, and whether they have a roof |
/// | household | who they are married to, and how that person is voting |
///
/// **Experience is not a seventh opinion, it is how loudly the others are
/// held.** A colonist of nineteen with no trade behind them is mostly the
/// random term; one of fifty who has farmed all their life is almost entirely
/// their own reasons. That is what makes a colony's politics *change* as it
/// ages rather than staying a fixed distribution with noise on top.
///
/// Deterministic throughout: one `SeededRNG`, walked in roster order.
public enum AssemblyEngine {

    /// How many named voices a motion carries into the save.
    ///
    /// The tallies are the whole colony; these are the people the council
    /// screen can actually print. A town of four hundred would otherwise write
    /// four hundred lines into every save for a decision that lasts one sitting.
    public static let voicesKept = 10

    /// The widest stake any law in `laws.json` puts on a single trade.
    ///
    /// Read off the data rather than guessed: 113 trade favours, |0.1| to
    /// |0.45|, median 0.2. Guarded by "No law asks more of a trade than the
    /// die can answer" so a new law of 0.9 is caught in the test rather than
    /// in a colony that votes as one body.
    static let widestLivelihood = 0.45

    /// The widest the die can swing somebody who has nothing behind them.
    ///
    /// It was `0.4 + U × 0.3` against a bias term that rarely reaches 0.2 —
    /// so the die decided most votes and the reasons decorated them. Rule 23's
    /// shape: a threshold set against a distribution nobody had looked at.
    ///
    /// And then the same fault the other way round. **Half of this has to be
    /// wider than the widest stake somebody green can hold**
    /// (`widestLivelihood × greenShare` = 0.20), or a trade's boys are
    /// unanimous about their own trade before they know anything about it:
    /// measured at 0.34, sixty loggers who had never felled a tree voted
    /// 60–0 for a hewing law, because ±0.17 of doubt cannot cross 0.18 of
    /// livelihood. A master still votes his own reasons — `seasoning` takes
    /// three quarters of the die away from him.
    static let widestDoubt = 0.5

    /// How far a spouse pulls somebody who was not sure.
    ///
    /// Deliberately small and deliberately *only* applied to the undecided: a
    /// household that votes as a bloc whatever its members think is not an
    /// opinion spreading, it is one person voting twice.
    static let householdPull = 0.12

    /// Where the line is. Above it, they are for.
    static let carries = 0.5

    /// How much of a trade's stake in a law somebody feels who has no standing
    /// in that trade. The rest of it is earned.
    static let greenShare = 0.45

    /// **How much of "what kind of person they are" is the colony's own
    /// character rather than this person's difference from their neighbours.**
    ///
    /// Genes drift toward a common stock, so a settled colony's four averages
    /// are nearly everybody's four numbers — and read absolutely, every
    /// colonist then gets the same `nature` term and the room votes as one
    /// body. Measured on a colony of sixty-nine at year fifty: **eight of the
    /// thirty laws came out unanimous**, every one of them reported "nature".
    /// A law nobody can be against is not a decision (rule 23: set a term
    /// against the distribution it is actually read from).
    ///
    /// So most of the weight is *relative*. Somebody braver than their
    /// neighbours speaks for the watch; a colony that is uniformly brave has
    /// no argument about it, which is right — the argument is about who
    /// dissents, and the level only tilts the floor.
    static let colonyCharacterShare = 0.35

    /// The colony's own four averages, and how far its people spread around
    /// them. Computed once per assembly, not once per voter.
    struct GeneStock {
        var mean = Genes(industry: 0.5, fertility: 0.5, sociability: 0.5, courage: 0.5)
        var spread = Genes(industry: 0.1, fertility: 0.1, sociability: 0.1, courage: 0.1)

        /// The narrowest spread worth dividing by. A colony whose people are
        /// genuinely identical must not have its last hundredth of variation
        /// amplified into a political faction.
        static let floor = 0.08

        init(of pawns: [Pawn]) {
            guard !pawns.isEmpty else { return }
            let n = Double(pawns.count)
            func average(_ pick: (Genes) -> Double) -> Double {
                pawns.reduce(0) { $0 + pick($1.genes) } / n
            }
            func deviation(_ pick: (Genes) -> Double, _ mean: Double) -> Double {
                (pawns.reduce(0) { $0 + pow(pick($1.genes) - mean, 2) } / n).squareRoot()
            }
            let m = Genes(industry: average(\.industry), fertility: average(\.fertility),
                          sociability: average(\.sociability), courage: average(\.courage))
            mean = m
            spread = Genes(industry: deviation(\.industry, m.industry),
                           fertility: deviation(\.fertility, m.fertility),
                           sociability: deviation(\.sociability, m.sociability),
                           courage: deviation(\.courage, m.courage))
        }

        /// One gene as a number on the same −1…1 scale whatever the colony is
        /// like: partly how far from the middle of humanity, mostly how far
        /// from the people standing next to them.
        func standing(_ gene: Double, mean: Double, spread: Double) -> Double {
            let level = (gene - 0.5) * 2
            let relative = min(1.2, max(-1.2, (gene - mean) / max(Self.floor, spread)))
            return level * colonyCharacterShare + relative * (1 - colonyCharacterShare)
        }
    }

    /// What one colonist thinks, broken into its parts.
    struct Reasoning {
        var terms: [VoteReason: Double] = [:]
        var inclination: Double = carries

        /// The part that moved them furthest from the middle — what they would
        /// say if somebody asked them why.
        ///
        /// Walked in the enum's own order rather than the dictionary's, which
        /// is not stable between two runs of the same program: two terms of
        /// equal weight would otherwise be reported differently on a replay,
        /// and a replayed world that disagrees with itself is the determinism
        /// invariant broken (rule 2). Caught by "Catch-up in slices lands on
        /// the same world as catch-up in one go".
        var loudest: VoteReason {
            var best: (reason: VoteReason, weight: Double)?
            for reason in VoteReason.allCases {
                guard let value = terms[reason], abs(value) > 0.02 else { continue }
                if abs(value) > (best?.weight ?? 0) { best = (reason, abs(value)) }
            }
            return best?.reason ?? .undecided
        }
    }

    /// **The whole assembly, sitting.** Every adult in the settlement weighs
    /// the motion; the result is the tally, and the loudest handful of the
    /// people who made it.
    public static func vote(
        on law: LawDefinition, in settlement: Settlement, state: WorldState,
        registry: GameDataRegistry, rng: inout SeededRNG
    ) -> LawProposal {
        let ticksPerYear = max(1, registry.config.ticksPerYear)
        let adults = settlement.pawns.filter { $0.isAdult(ticksPerYear: ticksPerYear) }

        // What this colony is like, so a person can be read against their own
        // neighbours rather than against an abstraction.
        let stock = GeneStock(of: adults)

        // First pass: what each of them makes of it on their own.
        var reasoning: [UUID: Reasoning] = [:]
        for pawn in adults {
            reasoning[pawn.id] = weigh(law, by: pawn, in: settlement, stock: stock,
                                       ticksPerYear: ticksPerYear, rng: &rng)
        }

        // Second pass: households. Somebody who is genuinely torn goes the way
        // their husband or wife is going, which is how an opinion travels
        // through a village rather than being held one head at a time.
        //
        // Off the *first* pass for everybody, so the order the roster happens
        // to be in cannot decide who persuaded whom.
        let opening = reasoning
        for bond in settlement.relationships
        where bond.kind == .partner || bond.kind == .rival {
            // A rival pulls the other way, and only half as hard: disagreeing
            // with somebody is a weaker reason than agreeing with the person
            // you live with, and it is still a reason.
            let sign: Double = bond.kind == .partner ? 1 : -0.5
            for (mine, theirs) in [(bond.a, bond.b), (bond.b, bond.a)] {
                guard var mineReasoning = reasoning[mine],
                      let theirsReasoning = opening[theirs] else { continue }
                let ownConviction = abs(mineReasoning.inclination - carries)
                guard ownConviction < householdPull else { continue }
                let theirLean = (theirsReasoning.inclination - carries) > 0 ? 1.0 : -1.0
                let pull = theirLean * householdPull * sign
                mineReasoning.inclination += pull
                mineReasoning.terms[.household] = pull
                reasoning[mine] = mineReasoning
            }
        }

        var votesFor = 0, votesAgainst = 0
        var voices: [AssemblyVoice] = []
        for pawn in adults {
            guard let thinking = reasoning[pawn.id] else { continue }
            let cls = settlement.society.wealthClass(of: pawn.wealth)
            let forIt = thinking.inclination > carries
            if forIt { votesFor += cls.votes } else { votesAgainst += cls.votes }
            voices.append(AssemblyVoice(
                pawnID: pawn.id, name: pawn.name, trade: pawn.assignedWork,
                wealth: cls, forIt: forIt, reason: thinking.loudest,
                conviction: min(1, abs(thinking.inclination - carries) * 2)))
        }

        // The loudest, and not merely the first ten on the roster — with the
        // tie broken on id so the same assembly always prints the same people.
        voices.sort {
            $0.conviction == $1.conviction
                ? $0.pawnID.uuidString < $1.pawnID.uuidString
                : $0.conviction > $1.conviction
        }
        return LawProposal(
            definitionID: law.id, settlementID: settlement.id,
            proposedTick: state.tick, votesFor: votesFor, votesAgainst: votesAgainst,
            voices: Array(voices.prefix(voicesKept)), turnout: adults.count)
    }

    /// **What one colonist makes of one motion.**
    static func weigh(
        _ law: LawDefinition, by pawn: Pawn, in settlement: Settlement,
        stock: GeneStock, ticksPerYear: Int, rng: inout SeededRNG
    ) -> Reasoning {
        var out = Reasoning()
        let cls = settlement.society.wealthClass(of: pawn.wealth)

        // What kind of person they are — read against the people they live
        // among, or a colony with one temperament votes with one voice.
        out.terms[.nature] =
            stock.standing(pawn.genes.industry, mean: stock.mean.industry,
                           spread: stock.spread.industry) * law.voteBias.industry
            + stock.standing(pawn.genes.fertility, mean: stock.mean.fertility,
                             spread: stock.spread.fertility) * law.voteBias.fertility
            + stock.standing(pawn.genes.sociability, mean: stock.mean.sociability,
                             spread: stock.spread.sociability) * law.voteBias.sociability
            + stock.standing(pawn.genes.courage, mean: stock.mean.courage,
                             spread: stock.spread.courage) * law.voteBias.courage

        // Where they stand. Kept apart from nature because they are different
        // answers to "why" and the council screen has to be able to say which.
        switch cls {
        case .poor: out.terms[.standing] = law.voteBias.poorFavour
        case .wealthy: out.terms[.standing] = -law.voteBias.poorFavour
        case .middle: break
        }

        // What it would mean for their work — and how much they know about it.
        // A law about the wood matters more to somebody who has been felling it
        // for thirty years than to the boy who started last spring, which is
        // the difference between an opinion and a position.
        // **Experience is not a seventh opinion, it is how firmly the others
        // are held.** A flat trade term made a boy who started last spring as
        // certain about the wood as a man who has felled it for thirty years,
        // and — measured — that saturated the room: sixty green loggers voted
        // unanimously for a hewing law, because 0.40 of livelihood cannot be
        // crossed by a doubt of 0.17. Rule 23 in the assembly. So the *trade*
        // term is what somebody with no standing in the work thinks, and
        // mastery is what is added on top of it.
        let mastery = min(1.0, Double(pawn.skills[pawn.assignedWork] ?? 0) / 10)
        let livelihood = law.voteBias.favour(of: pawn.assignedWork)
        if livelihood != 0 {
            out.terms[.trade] = livelihood * greenShare
            out.terms[.experience] = livelihood * (1 - greenShare) * mastery
        }

        // What their own life is like. Somebody hungry, hurt, miserable or
        // sleeping rough wants *something* to change, whatever it is — which
        // is the one term that does not need a law to have an opinion about
        // them, and the one that makes a bad decade legible in the assembly.
        let hardship = self.hardship(of: pawn)
        if hardship > 0.05 { out.terms[.hardship] = hardship * 0.22 }

        if pawn.id == settlement.leaderID { out.terms[.leader] = 0.10 }

        // …and the doubt, narrowed by everything they have lived through. The
        // young and the unpractised are swayable; somebody with fifty years and
        // a trade behind them votes their own reasons.
        let years = Double(pawn.age) / Double(max(1, ticksPerYear))
        let seasoning = min(1, max(0, (years - 16) / 34) * 0.6 + mastery * 0.4)
        let doubt = (rng.nextUnit() - 0.5) * widestDoubt * (1 - seasoning * 0.75)
        out.terms[.undecided] = doubt

        // Walked in the enum's own order, not the dictionary's: `Dictionary`
        // iteration depends on a hash seed that is drawn afresh for every
        // process, so summing `terms.values` gave a different *rounding* of
        // the same six numbers on a replay — and a colonist one ulp from the
        // line then voted the other way. Rule 2, and the same fault `loudest`
        // had. Caught by "The same assembly reaches the same result twice".
        out.inclination = carries + VoteReason.allCases.reduce(0) { $0 + (out.terms[$1] ?? 0) }
        return out
    }

    /// How badly life is going for somebody, 0…1. Every part of it is a field
    /// the simulation already keeps and already acts on elsewhere.
    static func hardship(of pawn: Pawn) -> Double {
        var sum = 0.0
        // `PawnNeeds.hunger` is **satiety**: 100 is a full belly, and `<= 0`
        // is how somebody starves to death in `PawnEngine`. Read the wrong way
        // round it made a well-fed colony the one that wanted change. The line
        // is the one the rest of the game already uses for "hungry".
        let hungry = ErrandEngine.hungryBelow
        sum += min(1, max(0, (hungry - pawn.needs.hunger) / hungry)) * 0.35
        sum += min(1, max(0, (100 - pawn.health) / 100)) * 0.25
        sum += min(1, max(0, (60 - pawn.mood) / 60)) * 0.25
        if pawn.homeID == nil { sum += 0.15 }
        return min(1, sum)
    }
}
