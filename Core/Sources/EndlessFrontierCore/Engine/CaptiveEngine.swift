import Foundation

/// What happens to the people a broken raid leaves on the ground.
///
/// The third door into a colony that cannot grow out of its own cradle
/// (§11.10), and the only one that is not a gift: a raid turned back leaves
/// attackers down but not dead, and a colony that has somewhere to put them
/// takes them. From there it is entirely about what the place is like to live
/// in — a colony that keeps its prisoners fed, in good heart and with something
/// to believe in wins people over; one that wins its fights and then starves
/// them loses them over the wall, and should.
///
/// Three rules the design leans on, each of which this project has paid for:
///
/// - **Rule 14** — a rate multiplied by an entity count is a rate with no
///   ceiling. Conversion is per captive, so the number of captives has to be
///   bounded by something, and it is bounded by the colony that has to watch
///   them (`capacity`). Without that, a colony that gets good at defending
///   itself farms raids for population.
/// - **Rule 13** — a loop needs an input from outside itself. This is that
///   input: the people come from the world, not from the colony's own couples.
/// - **Rule 4** — the per-tick path is replayed tens of thousands of times, so
///   the reckoning is on a cadence and the common case (nobody held) is a
///   single `isEmpty` check.
///
/// Deterministic: every roll comes from `(mapSeed, settlement, tick)`.
public enum CaptiveEngine {

    /// How often prisoners are reckoned with, in ticks. A season-ish.
    public static let interval = 15

    /// The share of a broken warband that is taken alive rather than killed or
    /// let go. Deliberately well under half: most of a beaten raid runs.
    static let takenShare = 0.34

    /// How many the colony can hold at once, per colonist.
    ///
    /// Somebody has to watch them, and a village of twelve cannot guard eight
    /// prisoners. This is what stops a colony that has learned to win its
    /// fights turning raids into a population faucet — rule 14's ceiling, and
    /// the reason the door stays a trickle.
    static let heldPerColonist = 1.0 / 9
    static let heldCeiling = 6

    /// What a prisoner eats against what a colonist does. They are not working,
    /// and they are being kept alive.
    public static let upkeepShare = 0.85

    /// Trust gained per reckoning in a colony that is doing everything right,
    /// and lost in one that is not.
    ///
    /// Sized so coming round takes **years, not seasons**: a captive in a good
    /// colony is one of us in something like a decade, which is long enough
    /// that the player watches it happen and short enough to be worth doing.
    static let warmth = 0.055
    /// …and what a temple adds, because that is what a faith is for.
    static let devotionWarmth = 0.045
    /// What being held in a miserable, hungry place does instead.
    static let resentment = 0.075

    /// The colony people are won over by, stated once: fed, and not wretched.
    static let contentMorale: Double = 55
    static let fedPerHead: Double = 8

    /// Below this they are over the wall on the first dark night.
    static let escapeTrust = -1.0
    /// …and at this they are one of us.
    static let joinTrust = 1.0

    // MARK: - Taking them

    /// Takes the living off the field when a raid has broken.
    ///
    /// Only from an attacker that was **people**. A wolf pack leaves no
    /// prisoners, and `attackerTribeID` is the honest test of which it was —
    /// the alternative is a colony that converts a bear.
    public static func take(
        _ settlement: Settlement, siege: Siege, registry: GameDataRegistry,
        language: GameLanguage = .cs
    ) -> Settlement {
        guard siege.repelled, siege.attackerTribeID != nil else { return settlement }
        var s = settlement
        let room = capacity(s) - s.captives.count
        guard room > 0 else { return s }

        // Everybody who went down and did not get back up. Counted off the
        // field rather than off `siege.attackers`, so what the player's orders
        // did to the fight is what decides how many there are to take.
        let downed = siege.fighters.count { $0.side == .raider && $0.down }
        let taken = min(room, Int((Double(downed) * takenShare).rounded(.down)))
        guard taken > 0 else { return s }

        // Off the siege's **own** seed, which is already stable per fight — who
        // was taken is a property of that raid, so a replay of the same battle
        // carries in the same people (rule 2).
        var rng = SeededRNG(seed: siege.seed ^ 0x4341_5054_4956_4553)
        let tick = siege.startTick
        // A prisoner ought to carry their own people's character in with them
        // (`Genes.drawn(from:using:)`), and does not yet: `Siege` knows the
        // attacker's id but not their genes, and the tribes are not in scope
        // anywhere on the path from `begin` to here. Left alone rather than
        // threaded through four signatures for the rarest way anybody arrives.
        for _ in 0..<taken {
            // A prisoner is a whole person from the moment they are carried in,
            // so the day they come round is a move between two lists rather
            // than somebody being invented on the spot.
            var pawn = PawnFactory.generate(seed: rng.next(), language: language)
            pawn.assignedWork = .idle     // they do no work while they are held
            s.captives.append(Captive(pawn: pawn, takenFrom: siege.attackerName,
                                      takenFromTribeID: siege.attackerTribeID,
                                      takenTick: tick))
        }
        s.journal.append(tick: tick, kind: .danger, text: LocalizedText(values: [
            .en: "\(taken) of \(siege.attackerName) were taken alive and are being held.",
            .cs: "\(taken) z \(siege.attackerName) padli živí do zajetí."]))
        return s
    }

    /// How many prisoners this colony can watch at once.
    public static func capacity(_ settlement: Settlement) -> Int {
        min(heldCeiling, Int(settlement.population * heldPerColonist))
    }

    // MARK: - The reckoning

    public static func advanceOneTick(
        _ state: WorldState, registry: GameDataRegistry, mapSeed: UInt64
    ) -> WorldState {
        // The overwhelmingly common case, and it must cost nothing: nobody is
        // held, so nothing is copied and nothing is written back.
        guard state.settlements.contains(where: { !$0.captives.isEmpty }) else { return state }
        var s = state
        for index in s.settlements.indices where !s.settlements[index].captives.isEmpty {
            s.settlements[index] = reckon(s.settlements[index], registry: registry,
                                          tick: s.tick, mapSeed: mapSeed)
        }
        return s
    }

    /// One settlement's prisoners for one tick: they eat every tick, and the
    /// question of what becomes of them is asked on the cadence.
    static func reckon(
        _ settlement: Settlement, registry: GameDataRegistry, tick: Int, mapSeed: UInt64
    ) -> Settlement {
        var s = settlement
        // They eat. Every tick, out of the same larder, because a prisoner the
        // colony does not have to feed is not a decision about anything.
        let upkeep = registry.config.foodPerPersonPerTick * upkeepShare
            * Double(s.captives.count)
        s.storage[.food] = max(0, s.storage[.food] - upkeep)
        guard tick % interval == 0 else { return s }

        // What the place is like to live in, which is the whole mechanism.
        let mouths = max(1, s.population)
        let fed = s.storage[.food] / mouths >= fedPerHead
        let content = s.stats.morale >= contentMorale
        let devotion = s.faith.hasTemple ? devotionWarmth * s.faith.faith / 100 : 0
        let drift = (fed && content) ? warmth + devotion : -resentment

        var joined: [Pawn] = []
        var escaped = 0
        var held: [Captive] = []
        held.reserveCapacity(s.captives.count)
        for var captive in s.captives {
            captive.trust += drift
            if captive.trust >= joinTrust {
                var pawn = captive.pawn
                // They come in idle and the labour engine finds them a trade
                // like anybody who has just come of age.
                pawn.assignedWork = .idle
                joined.append(pawn)
            } else if captive.trust <= escapeTrust {
                escaped += 1
            } else {
                held.append(captive)
            }
        }
        s.captives = held

        if !joined.isEmpty {
            let names = joined.map(\.name)
            s.pawns.append(contentsOf: joined)
            s.stats.morale = min(100, s.stats.morale + 2)
            s.journal.append(tick: tick, kind: .arrival, text: LocalizedText(values: [
                .en: "\(names.joined(separator: " and ")) stopped being prisoners and started being neighbours.",
                .cs: "\(names.joined(separator: " a ")) přestali být zajatci a stali se sousedy."]))
        }
        if escaped > 0 {
            s.stats.morale = max(0, s.stats.morale - 3)
            s.journal.append(tick: tick, kind: .danger, text: LocalizedText(values: [
                .en: "\(escaped) went over the wall in the night. Nobody here blamed them.",
                .cs: "\(escaped) v noci přelezli hradbu. Nikdo se jim tu nedivil."]))
        }
        return s
    }
}
