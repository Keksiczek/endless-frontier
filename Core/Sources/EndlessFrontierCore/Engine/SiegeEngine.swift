import Foundation

/// Fights a raid **while the player is watching**, one action step at a time.
///
/// The whole of the difference from `BattleResolver`: that one takes a
/// settlement and hands back a finished outcome, and this one takes a
/// settlement mid-fight and hands back a settlement one step further into it.
/// Between two calls the player can change the colony's posture or pull a
/// bleeding colonist out of the line, and the next step reads what they did.
///
/// Three properties this has to keep, all of them load-bearing:
///
/// 1. **Determinism.** Each step's rolls come from `(siege.seed, step)`, so a
///    step is a pure function of where it sits in the fight — never of when it
///    was asked for. Orders live in `Siege`, which is saved, so the same world
///    plus the same orders replays to the same dead. This is why posture is a
///    field and not a callback.
/// 2. **Leaving is allowed.** A step is fought once, by whoever reaches it
///    first. The app drives the siege ahead of the world clock at a pace a
///    person can act at; if the app is not there, `ActionLoop` walks the world
///    clock over the top and the rest is fought exactly as it would have been.
///    Backgrounding an app mid-raid must never be a tactic, and must never be a
///    punishment.
/// 3. **The Core owes the canvas a record.** Moments accumulate as they happen,
///    so the fight can be drawn while it is still going on rather than replayed
///    once it is finished.
public enum SiegeEngine {

    /// Rounds only start landing once they have crossed the ground.
    static let approachSteps = 4
    /// The share of its power the line delivers each step.
    ///
    /// Derived from the number of steps it actually fights for, not written
    /// down: across a whole fight at `hold` the line delivers its full weight
    /// exactly once, which is what the one-tick resolver credited it with. A
    /// hand-picked 1/12 over twenty fighting steps quietly made every line
    /// two-thirds stronger, and an *undefended* colony started turning back
    /// warbands that used to walk through it.
    static var linePerStep: Double { 1 / Double(Siege.stepsTotal - approachSteps) }
    /// How hard the attackers answer, per point of strength, per step.
    static let attackerDamagePerStrength = 0.14
    /// The fortification at which a wall turns aside half of what is thrown at
    /// it. Used as a *share*, never as a subtraction — see `wallShare`.
    static let fortificationHalfPoint = 24.0
    /// …and the most a wall can ever turn aside, however high it is built.
    static let fortificationCeiling = 0.85
    /// What a wall contributes to *breaking* an assault, beyond soaking.
    static let fortificationBite = 0.05
    /// Food carried off per step while the colony is giving ground, as a
    /// share of the store. Giving ground is cheap in blood and dear in grain —
    /// that is the entire trade, and it has to actually bite.
    static let plunderPerStep = 0.035

    // MARK: - Opening

    /// Starts a raid the player can fight, in place of resolving one.
    ///
    /// Takes the same inputs `BattleResolver.resolve` does, so the two are
    /// interchangeable at the call site: a raid becomes a siege where somebody
    /// might be watching, and stays a resolved battle where nobody can be.
    public static func begin(
        _ settlement: Settlement,
        attackerStrength: Double,
        attackerName: String,
        attackerLabel: LocalizedText? = nil,
        attackerTribeID: UUID? = nil,
        fortification: Double,
        tick: Int,
        registry: GameDataRegistry,
        seed: UInt64
    ) -> Settlement {
        var rng = SeededRNG(seed: seed)
        var s = settlement
        let line = BattleResolver.defenders(s.pawns, registry: registry)
            .prefix(12).map(\.id)
        let id = rng.nextUUID()
        let approach = rng.nextUnit() * 2 * .pi
        s.siege = Siege(
            id: id, startTick: tick,
            openedAt: WorldClock(tick: tick, step: 0).absoluteStep,
            attackerName: attackerName, attackerLabel: attackerLabel,
            attackerTribeID: attackerTribeID, approach: approach,
            attackers: BattleResolver.drawnStrength(attackerStrength),
            openingStrength: attackerStrength, fortification: fortification,
            seed: rng.next(), line: Array(line))
        return s
    }

    // MARK: - Fighting it

    /// Carries the settlement's siege forward to a given absolute action step.
    ///
    /// Idempotent by construction: a step already fought is never fought again,
    /// so the app running ahead of the world clock and the world clock catching
    /// up later add up to exactly one fight.
    public static func advance(
        _ settlement: Settlement, to absoluteStep: Int, registry: GameDataRegistry
    ) -> Settlement {
        fight(settlement, to: absoluteStep, registry: registry).settlement
    }

    /// The same, but also handing back the siege **as it finished**.
    ///
    /// The world needs the final numbers — what is left of the warband, what
    /// they carried off — and `conclude` clears the siege off the settlement,
    /// so a caller that only watched `settlement.siege` go from set to nil is
    /// left holding the state from *before* the last step. That is how the
    /// tribes came to be charged for a fight they had not finished yet.
    public static func fight(
        _ settlement: Settlement, to absoluteStep: Int, registry: GameDataRegistry
    ) -> (settlement: Settlement, concluded: Siege?) {
        guard var siege = settlement.siege else { return (settlement, nil) }
        guard absoluteStep > siege.advancedTo else { return (settlement, nil) }
        var s = settlement

        var reached = siege.advancedTo
        while reached < absoluteStep, !siege.isFinished {
            reached += 1
            siege.advancedTo = reached
            s = fightOneStep(s, siege: &siege, registry: registry)
        }
        siege.advancedTo = max(siege.advancedTo, min(absoluteStep, reached))
        s.siege = siege

        guard siege.isFinished else { return (s, nil) }
        return (conclude(s, registry: registry), siege)
    }

    /// One exchange. The line answers, the attackers answer back, and whatever
    /// gets past the wall lands on somebody.
    private static func fightOneStep(
        _ settlement: Settlement, siege: inout Siege, registry: GameDataRegistry
    ) -> Settlement {
        var s = settlement
        let step = siege.step
        // A step's rolls depend on where it sits in the fight and nothing else.
        var rng = SeededRNG(seed: siege.seed
                            &+ UInt64(bitPattern: Int64(step)) &* 0x9E37_79B9_7F4A_7C15)
        let posture = siege.posture

        // Coming over the ground. The wall looses once before they are close
        // enough to answer, and nobody is hurt yet.
        guard step >= approachSteps else {
            if step == approachSteps - 1 {
                let volley = line(of: s, siege: siege, registry: registry).ranged
                if volley > 0 {
                    siege.strength = max(0, siege.strength - volley * 0.8)
                    siege.moments.append(moment(siege, .volley, amount: volley * 0.8))
                }
                siege.moments.append(moment(siege, .charge, amount: siege.strength))
            }
            return s
        }

        // The line fights.
        let strengthOfLine = line(of: s, siege: siege, registry: registry)
        let dealt = (strengthOfLine.melee + strengthOfLine.ranged * 0.35
                     + siege.fortification * fortificationBite)
            * posture.bite * (0.85 + rng.nextUnit() * 0.3)
        siege.strength = max(0, siege.strength - dealt * linePerStep)
        siege.moments.append(moment(siege, .clash, amount: dealt))

        // Giving ground means they reach the stores. The cost of not bleeding.
        if posture == .giveGround, siege.strength > 0 {
            let taken = s.storage[.food] * plunderPerStep
            if taken > 0 {
                s.storage[.food] -= taken
                siege.plundered += taken
                siege.moments.append(moment(siege, .plunder, amount: taken))
            }
        }

        guard siege.strength > 0 else { return s }

        // They answer. The wall takes the brunt — as much of it as the posture
        // leaves standing between them and the colony.
        let incoming = siege.strength * attackerDamagePerStrength * posture.exposure
        let past = incoming * (1 - wallShare(fortification: siege.fortification,
                                             cover: posture.cover))
        guard past > 0 else { return s }

        // It lands on whoever is most exposed: the weakest still in the line.
        // Someone the player pulled out is not there to be hit.
        let inLine = siege.standing
        guard let targetID = inLine
            .compactMap({ id -> (UUID, Double)? in
                guard let pawn = s.pawns.first(where: { $0.id == id }), pawn.health > 0
                else { return nil }
                return (id, pawn.health)
            })
            .min(by: { $0.1 == $1.1 ? $0.0.uuidString < $1.0.uuidString : $0.1 < $1.1 })?.0,
              let index = s.pawns.firstIndex(where: { $0.id == targetID }) else { return s }

        let hit = past * CombatEngine.woundMultiplier(s.pawns[index])
        let name = s.pawns[index].name
        // A blow lands *somewhere*: an arm, a leg — not a smaller number.
        s.pawns[index] = MedicineEngine.wound(s.pawns[index], amount: hit,
                                              tick: s.siege?.startTick ?? 0, rng: &rng)
        siege.damage[targetID, default: 0] += hit
        let down = s.pawns[index].health <= 0
        siege.moments.append(moment(siege, down ? .death : .wound,
                                    pawnID: targetID, pawnName: name, amount: hit))
        // Whoever falls is out of the line. They are not removed from the
        // colony until the fighting stops — a body on the ground is still a
        // body the canvas has to draw where it fell.
        if down { siege.withdrawn.insert(targetID) }
        return s
    }

    /// How much of a blow the wall turns aside, 0…`fortificationCeiling`.
    ///
    /// A **share**, deliberately, and not the flat `defense × k` subtraction
    /// the one-tick resolver used. A flat subtraction has a threshold above
    /// which the whole attack is cancelled — a palisade of twenty made a
    /// sixty-strong warband literally unable to hurt anybody, which is the
    /// recurring bug in this project wearing armour: a number that crosses
    /// zero and takes the mechanic with it. A raid on a strong wall should be
    /// survivable. It should never be free.
    static func wallShare(fortification: Double, cover: Double) -> Double {
        let standing = max(0, fortification) * max(0, cover)
        return min(fortificationCeiling, standing / (standing + fortificationHalfPoint))
    }

    /// The weight the line brings this step, counting only those in it.
    private static func line(
        of settlement: Settlement, siege: Siege, registry: GameDataRegistry
    ) -> CombatEngine.Militia {
        let holding = Set(siege.standing)
        return CombatEngine.militia(
            settlement.pawns.filter { holding.contains($0.id) && $0.health > 0 },
            registry: registry)
    }

    /// Stamps a beat where it happened inside the fight.
    ///
    /// Placed at the *middle* of its step, so no beat ever lands on 0 or 1:
    /// those are the edges of the window the canvas plays against, and a beat
    /// sitting exactly on one is a beat that has either always happened or
    /// never happened.
    static func momentPosition(step: Int) -> Double {
        min(0.995, max(0.005, (Double(step) + 0.5) / Double(Siege.stepsTotal)))
    }

    private static func moment(
        _ siege: Siege, _ kind: BattleMoment.Kind, pawnID: UUID? = nil,
        pawnName: String? = nil, amount: Double = 0
    ) -> BattleMoment {
        BattleMoment(id: siege.moments.count, at: momentPosition(step: siege.step),
                     kind: kind, pawnID: pawnID, pawnName: pawnName, amount: amount)
    }

    // MARK: - Ending it

    /// Settles a finished siege: the dead are buried, the record is written,
    /// and the raiders take home whatever they got past the door with.
    public static func conclude(
        _ settlement: Settlement, registry: GameDataRegistry
    ) -> Settlement {
        guard let siege = settlement.siege, siege.isFinished else { return settlement }
        var s = settlement
        s.siege = nil

        // The record, sealed. A siege that broke says so as its last beat.
        var moments = siege.moments
        if siege.repelled {
            moments.append(BattleMoment(id: moments.count, at: 0.995, kind: .repelled))
        }
        s.lastBattle = BattleLog(
            id: siege.id, tick: siege.startTick,
            attackerName: siege.attackerName, defenderName: s.name,
            moments: moments, repelled: siege.repelled,
            attackerLabel: siege.attackerLabel, approach: siege.approach,
            attackers: siege.attackers, line: siege.line)

        // The dead leave the roster once the fighting is over, not during it.
        let deaths = s.pawns.filter { $0.health <= 0 }.count
        if deaths > 0 {
            s.pawns.removeAll { $0.health <= 0 }
            s.deathTallies[PawnDeathCause.battle.rawValue, default: 0] += deaths
        }

        // A raid turned back carries nothing home; one that got through takes
        // what its surviving strength could carry, on top of anything it
        // helped itself to while the colony was giving ground.
        if !siege.repelled {
            let share = min(0.35, 0.08 + siege.strength / 200)
            let loot = s.storage[.food] * share
            s.storage[.food] -= loot
        }

        let entry: LocalizedText
        if siege.repelled {
            entry = LocalizedText(values: [
                .en: "\(siege.attackerName) came for the walls and were turned back.",
                .cs: "\(siege.attackerName) přišli na hradby a byli odraženi."])
        } else if deaths > 0 {
            entry = LocalizedText(values: [
                .en: "\(siege.attackerName) broke the line — \(deaths) did not get up.",
                .cs: "\(siege.attackerName) prolomili řadu — \(deaths) už nevstali."])
        } else {
            entry = LocalizedText(values: [
                .en: "\(siege.attackerName) took what they came for and left.",
                .cs: "\(siege.attackerName) si vzali, pro co přišli, a odešli."])
        }
        s.journal.append(tick: siege.startTick, kind: .danger, text: entry)
        s.stats.morale = max(0, s.stats.morale - (siege.repelled ? 0 : 8))
        return s
    }

    /// Charges the people who sent the warband for what the attempt cost them.
    ///
    /// Deliberately *after* the fighting rather than when the raid was
    /// declared: how much of a warband walks home is exactly what the player's
    /// orders decide, so pressing them hurts the neighbours and giving ground
    /// leaves them strong enough to come again.
    public static func chargeAttacker(_ state: WorldState, for siege: Siege) -> WorldState {
        guard let tribeID = siege.attackerTribeID,
              let index = state.tribes.firstIndex(where: { $0.id == tribeID })
        else { return state }
        var s = state
        let spent = max(0, siege.openingStrength - siege.strength)
        s.tribes[index].population = max(4, s.tribes[index].population - spent * 0.12)
        // What they got past the door with goes into their own stores.
        s.tribes[index].stores += siege.plundered
        return s
    }

    // MARK: - Orders

    /// Sets what the line is doing. Recorded on the siege, so it is an input to
    /// the fight rather than a thing that happened outside it.
    public static func order(
        _ settlement: Settlement, posture: Siege.Posture
    ) -> Settlement {
        guard var siege = settlement.siege, !siege.isFinished else { return settlement }
        var s = settlement
        siege.posture = posture
        s.siege = siege
        return s
    }

    /// Pulls one colonist out of the line, or puts them back in.
    ///
    /// The line is who is *taking* the blows as well as who is dealing them,
    /// so this is a real decision: a bleeding smith you pull out stops being
    /// the weakest target, and the next weakest becomes it.
    public static func withdraw(
        _ settlement: Settlement, pawnID: UUID, out: Bool = true
    ) -> Settlement {
        guard var siege = settlement.siege, !siege.isFinished,
              siege.line.contains(pawnID) else { return settlement }
        var s = settlement
        // Someone already down cannot be sent back in.
        let isDown = s.pawns.first { $0.id == pawnID }?.health ?? 0 <= 0
        if out {
            siege.withdrawn.insert(pawnID)
        } else if !isDown {
            siege.withdrawn.remove(pawnID)
        }
        s.siege = siege
        return s
    }
}
