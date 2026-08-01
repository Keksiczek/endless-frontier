import Foundation

/// What a battle did to the two sides that fought it.
public struct BattleOutcome: Sendable, Equatable {
    /// Attacker strength still standing when it ended. Zero means broken.
    public let attackerRemaining: Double
    /// Damage dealt to each defender, by pawn id — applied by the caller, so
    /// the resolver stays a pure function of the numbers it was handed.
    public let damageByPawn: [UUID: Double]
    /// Whether the defenders held.
    public let repelled: Bool
    /// How many rounds it took.
    public let rounds: Int
    public let log: BattleLog
}

/// Fights a battle out **inside a tick**.
///
/// Combat used to be one arithmetic step: a strength number met a defense
/// number, a formula decided the loot fraction, and up to three colonists were
/// hurt by the same margin. `BattleLog` gave that a record, but the record was
/// cosmetic — beats were spread evenly across the tick after the fact, and the
/// outcome had already been decided by a single line of algebra.
///
/// This resolves the battle as **rounds that advance a clock**. Each round both
/// sides act, damage lands, and the next round starts from what the last one
/// left; a side that loses its archers stops shooting, a defender who falls
/// stops defending, and the fight ends when one side breaks rather than when a
/// formula says so. The moments carry the clock they actually happened on.
///
/// Still entirely within one whole tick, and still deterministic from
/// `(seed, tick)`: sub-tick time is *simulated*, not *observed*. Nothing here
/// reads a frame clock, so a battle plays out identically whether or not
/// anyone is watching it — which is what lets the canvas replay it later.
public enum BattleResolver {
    /// One combatant on the defending side.
    public struct Defender: Sendable, Equatable {
        public let id: UUID
        public let name: String
        public var health: Double
        /// Damage this defender deals per round at range and in the line.
        public let ranged: Double
        public let melee: Double
        /// How much a hit is blunted by armour.
        public let woundMultiplier: Double

        public init(id: UUID, name: String, health: Double,
                    ranged: Double, melee: Double, woundMultiplier: Double) {
            self.id = id
            self.name = name
            self.health = health
            self.ranged = ranged
            self.melee = melee
            self.woundMultiplier = woundMultiplier
        }
    }

    /// The most rounds a battle can run before it is called.
    ///
    /// A round *is* an action step: a battle occupies at most one world tick,
    /// and the grid inside that tick is what bounds it. A fight that cannot
    /// resolve in a tick is a stalemate, not an infinite loop.
    public static let maxRounds = WorldClock.actionStepsPerTick
    /// The share of its power the defending line delivers each round.
    ///
    /// Set to `1 / maxRounds` on purpose: across a full battle the line does
    /// exactly the damage the old single comparison credited it with, so a
    /// fight that used to be won is still won — it just takes rounds to get
    /// there, and the attackers get to answer in between.
    static let attackerLossPerRound: Double = 1 / Double(maxRounds)
    /// How much a wall contributes to *breaking* an assault each round, on top
    /// of soaking damage. A palisade is not only cover — it is why a charge
    /// stalls where the defenders can reach it.
    static let fortificationBite: Double = 0.12
    /// How hard the attackers hit back each round, per point of strength.
    static let attackerDamagePerStrength: Double = 0.42
    /// Standing fortification soaks this share of a round's incoming damage.
    static let fortificationSoak: Double = 0.6

    /// Fights it out. `fortification` is the settlement's standing defence —
    /// walls do not swing, but they absorb.
    public static func resolve(
        attackerStrength: Double,
        attackerName: String,
        defenders: [Defender],
        defenderName: String,
        fortification: Double,
        tick: Int,
        seed: UInt64
    ) -> BattleOutcome {
        var rng = SeededRNG(seed: seed)
        var record = CombatEngine.BattleRecorder()
        var strength = max(0, attackerStrength)
        var standing = defenders
        var damage: [UUID: Double] = [:]
        var rounds = 0

        // The opening volley: everyone who can shoot, shoots once, before the
        // attackers are close enough to answer.
        let opening = standing.reduce(0) { $0 + $1.ranged }
        if opening > 0 {
            strength = max(0, strength - opening * 0.8)
            record.record(.volley, step: 0, amount: opening * 0.8)
        }
        record.record(.charge, step: 0, amount: strength)

        while strength > 0, rounds < maxRounds,
              standing.contains(where: { $0.health > 0 }) {
            rounds += 1

            // The line fights: ranged fire thins the charge, blades hold it.
            let line = standing.filter { $0.health > 0 }
            let dealt = (line.reduce(0) { $0 + $1.melee + $1.ranged * 0.35 }
                         + fortification * fortificationBite)
                * (0.85 + rng.nextUnit() * 0.3)
            strength = max(0, strength - dealt * attackerLossPerRound)
            // Round `rounds` happens on action step `rounds - 1`.
            let step = rounds - 1
            record.record(.clash, step: step, amount: dealt)

            guard strength > 0 else { break }

            // The attackers answer. Walls take the brunt; whatever gets past
            // lands on whoever is most exposed — the weakest still standing.
            let incoming = strength * attackerDamagePerStrength
            let past = max(0, incoming - fortification * fortificationSoak)
            guard past > 0 else { continue }

            guard let target = standing.indices
                .filter({ standing[$0].health > 0 })
                .min(by: { standing[$0].health < standing[$1].health }) else { break }
            let hit = past * standing[target].woundMultiplier
            standing[target].health = max(0, standing[target].health - hit)
            damage[standing[target].id, default: 0] += hit
            record.record(standing[target].health <= 0 ? .death : .wound,
                          step: step, pawnID: standing[target].id,
                          pawnName: standing[target].name, amount: hit)
        }

        let repelled = strength <= 0
        if repelled { record.record(.repelled, step: max(0, rounds - 1)) }

        // The staging, so the fight can be *watched* rather than reported: how
        // many came, who met them, and from which side of the valley.
        //
        // Both draws come after every roll the fight itself made — a new draw
        // inserted earlier would change the outcome of every battle in every
        // existing world.
        let id = rng.nextUUID()
        let approach = rng.nextUnit() * 2 * .pi
        return BattleOutcome(
            attackerRemaining: strength,
            damageByPawn: damage,
            repelled: repelled,
            rounds: rounds,
            log: record.finish(id: id, tick: tick,
                               attackerName: attackerName, defenderName: defenderName,
                               repelled: repelled,
                               approach: approach,
                               attackers: drawnStrength(attackerStrength),
                               line: defenders.filter { $0.health > 0 }.prefix(12).map(\.id)))
    }

    /// How many raiders a given strength puts on the field. Purely for the
    /// canvas — the fight is settled on `attackerStrength` alone — but it has
    /// to be a *function* of the strength, or a warband of forty would arrive
    /// looking exactly like a scouting party of three.
    public static func drawnStrength(_ strength: Double) -> Int {
        min(14, max(1, Int((max(0, strength) / 8).rounded(.up))))
    }

    /// Builds the defending line from a settlement's colonists.
    public static func defenders(
        _ pawns: [Pawn], registry: GameDataRegistry
    ) -> [Defender] {
        pawns.filter { $0.health > 0 && !$0.isBroken }.map { pawn in
            // One colonist's share of the militia, so a line built here fights
            // with the same weights the rest of the game already balances on.
            let one = CombatEngine.militia([pawn], registry: registry)
            return Defender(
                id: pawn.id,
                name: pawn.name,
                health: pawn.health,
                ranged: one.ranged,
                melee: one.melee,
                woundMultiplier: CombatEngine.woundMultiplier(pawn))
        }
    }
}
