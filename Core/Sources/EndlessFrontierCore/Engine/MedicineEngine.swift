import Foundation

/// Bleeding, mending, and somebody to do the mending.
///
/// The healer's trade produced nothing and did nothing: a colonist assigned to
/// `healing` was a colonist not producing food, and health crept back at a flat
/// rate whether or not anyone tended them. Nobody was ever *hurt* in a way that
/// could be treated — health was one number and it always went up.
///
/// Now a wound is a thing on a named part. Untreated it bleeds, and bleeding is
/// what kills people after a fight rather than during it. A healer with herbs
/// and a bench tends what they can reach, worst first; a tended wound stops
/// bleeding and closes five times faster. A colony with nobody on healing and a
/// raid behind it will bury people it could have kept.
///
/// Everything here is pure and on the per-tick path, so it stays cheap: one
/// pass over the pawns, and the tending pass is bounded by how many hurt people
/// there are rather than by how many colonists.
public enum MedicineEngine {

    /// How many patients one healer can see per tick.
    public static let patientsPerHealer = 2
    /// How much of an ailment a session of tending puts right, on top of
    /// marking it tended.
    public static let tendRelief: Double = 0.08
    /// A herb bundle used per tending session, if the colony has any. Without
    /// them the healer still works, just worse.
    public static let herbItemID = "herb_bundle"
    public static let untreatedPenalty: Double = 0.55
    /// Below this, a colonist is too badly hurt to work at all.
    public static let incapacitatedBelow: Double = 0.25

    /// One tick of the body: bleeding, mending, and the parts coming back.
    public static func advanceOneTick(
        _ settlement: Settlement, registry: GameDataRegistry, tick: Int
    ) -> Settlement {
        var s = settlement
        var anyoneHurt = false
        for i in s.pawns.indices where !s.pawns[i].body.ailments.isEmpty {
            anyoneHurt = true
            var body = s.pawns[i].body

            // What is still open takes its toll.
            let bleed = body.bleeding
            if bleed > 0 {
                s.pawns[i].health = max(0, s.pawns[i].health - bleed)
            }

            // …and what is closing, closes.
            var kept: [Ailment] = []
            for var ailment in body.ailments {
                let rate = Body.healPerTick * (ailment.tended ? Body.tendedHealMultiplier : 1)
                ailment.severity -= rate
                if ailment.severity > 0 { kept.append(ailment) }
            }
            body.ailments = kept

            // A part mends alongside the wound on it — slowly, and never a
            // part that was lost outright. An arm you no longer have does not
            // grow back.
            for p in body.parts.indices where !body.parts[p].missing {
                guard body.parts[p].condition < 1 else { continue }
                let onIt = body.ailments.contains { $0.part == body.parts[p].kind }
                let rate = Body.healPerTick * (onIt ? 0.5 : 2.0)
                body.parts[p].condition = min(1, body.parts[p].condition + rate)
            }

            s.pawns[i].body = body
            // A body that has lost something vital is a death, not a wound.
            if !body.isAlive { s.pawns[i].health = 0 }
        }
        guard anyoneHurt else { return settlement }
        return tendTheWounded(s, registry: registry, tick: tick)
    }

    /// Puts the healers to work on whoever is worst off.
    ///
    /// Anyone can bind a wound in a pinch — a colony of eight with nobody on
    /// healing should not simply watch a bleeding man die — but a healer does
    /// it properly, and herbs make it stick.
    public static func tendTheWounded(
        _ settlement: Settlement, registry: GameDataRegistry, tick: Int
    ) -> Settlement {
        let ticksPerYear = max(1, registry.config.ticksPerYear)
        let healers = settlement.pawns.count {
            $0.assignedWork == .healing && $0.isAdult(ticksPerYear: ticksPerYear)
                && !$0.isBroken && !$0.isAway && $0.body.canWork
        }
        // Somebody always does *something*; a healer does much more of it.
        var sessions = max(1, healers * patientsPerHealer)

        // Worst first: the one bleeding hardest gets seen first, which is the
        // whole of triage and the only ordering that saves anybody.
        let queue = settlement.pawns.indices
            .filter { settlement.pawns[$0].body.needsTending && !settlement.pawns[$0].isAway }
            .sorted { settlement.pawns[$0].body.bleeding > settlement.pawns[$1].body.bleeding }
        guard !queue.isEmpty else { return settlement }

        var s = settlement
        var herbs = s.stockpile[herbItemID] ?? 0
        for index in queue {
            guard sessions > 0 else { break }
            sessions -= 1
            let withHerbs = herbs > 0
            if withHerbs { herbs -= 1 }
            var body = s.pawns[index].body
            for a in body.ailments.indices where !body.ailments[a].tended {
                body.ailments[a].tended = true
                body.ailments[a].severity = max(
                    0, body.ailments[a].severity - tendRelief * (withHerbs ? 2 : 1))
            }
            body.ailments.removeAll { $0.severity <= 0 }
            s.pawns[index].body = body
        }
        if herbs != (s.stockpile[herbItemID] ?? 0) {
            s.stockpile[herbItemID] = herbs
        }
        return s
    }

    // MARK: - Harm coming in

    /// Lands a wound on a colonist, on a part decided by the roll.
    ///
    /// The one place damage becomes a *thing that happened to somebody*. Every
    /// caller that used to do `pawn.health -= x` should come through here, so
    /// that a mauling leaves a mauled arm and the inspector can say so.
    /// What a blow with nothing named behind it turns out to have been.
    ///
    /// A scuffle, a fall down a shaft, a beam coming down: mostly edges and
    /// blunt force, some of it going deep. Rolled rather than fixed so a fight
    /// leaves a *variety* of harm on a line of people — which is the whole of
    /// what Keks asked for after watching one.
    static func ordinaryWound(_ roll: Double) -> WoundKind {
        switch roll {
        case ..<0.48: return .cut
        case ..<0.78: return .bruise
        default:      return .stab
        }
    }

    public static func wound(
        _ pawn: Pawn, amount: Double, tick: Int, rng: inout SeededRNG,
        from kind: WoundKind? = nil
    ) -> Pawn {
        guard amount > 0 else { return pawn }
        var p = pawn
        let part = Body.struckPart(roll: rng.nextUnit())
        // What made it, so the card can say "a stab to the left arm" rather
        // than "wound" for everything from a wolf to a falling beam. Drawn
        // before the id so the stream stays in a fixed order (rule 2).
        let made = kind ?? ordinaryWound(rng.nextUnit())
        p.body.injure(part, by: amount, id: rng.nextUUID(), tick: tick, from: made)
        p.health = max(0, p.health - amount)
        if !p.body.isAlive { p.health = 0 }
        return p
    }

    /// How much of a day's work a colonist is actually good for, given what has
    /// happened to them. What the economy reads instead of assuming everyone is
    /// whole.
    public static func workCapacity(_ pawn: Pawn) -> Double {
        let body = pawn.body.capacity
        guard body >= incapacitatedBelow else { return 0 }
        return body
    }
}
