import Foundation

/// How the colony fights — with what's in its hands.
///
/// Before this, "militia" was a flat number: any weapon-slot item (a scythe,
/// a chainsaw) added the same +6, and a longbow defended no differently from
/// a pitchfork. Now arms have a class and a weight: **ranged** weapons loose
/// a volley before raiders ever reach the walls, **melee** decides the clash
/// at the palisade, and a courageous, healthy colonist counts for more than a
/// starving timid one. Pure and deterministic — no rolls live here.
public enum CombatEngine {
    /// What bare hands are worth…
    static let baseUnarmedPower = 1.5
    /// …and how much heart multiplies them (genes.courage is 0…1).
    static let couragePower = 2.0
    /// A bow is awkward once the fight is hand-to-hand: only half the bearer's
    /// base power joins the melee-side bucket.
    static let rangedBasePenalty = 0.5

    /// The colony's fighting strength, split by how it is delivered.
    public struct Militia: Equatable {
        public var melee: Double = 0
        public var ranged: Double = 0
        public var fighters: Int = 0

        /// Everything the settlement can bring to its walls.
        public var total: Double { melee + ranged }
    }

    /// The weapon a colonist actually holds, resolved to its fighting profile.
    ///
    /// Scaled by how well the piece was made: two iron swords off the same
    /// bench are the same sword only if the same hands made them. Without this
    /// a master smith's work was indistinguishable from an apprentice's the
    /// moment it left the workshop, and training anybody was purely about
    /// throughput.
    public static func weaponProfile(_ pawn: Pawn, registry: GameDataRegistry) -> CombatProfile? {
        guard let item = pawn.equipment[.weapon], !item.isBroken,
              let def = registry.item(item.definitionID),
              let combat = def.combat else { return nil }
        // Made well **and** kept well: `effectiveness` is quality times what is
        // left of the piece, so a blade that has been through four raids hits
        // like the cheaper blade it has become (§11.26 C).
        return CombatProfile(damage: combat.damage * item.effectiveness, kind: combat.kind)
    }

    /// How hard a wound lands on a colonist, given the armour they are wearing
    /// and how well it was made.
    public static func woundMultiplier(_ pawn: Pawn) -> Double {
        guard let armor = pawn.equipment[.armor], !armor.isBroken else { return 1 }
        // Plain armour halves a blow; a masterwork harness turns more aside,
        // and a shoddy one rather less. A battered harness turns aside what is
        // left of it — the straps go, the plates split, and the blow that
        // finishes the coat is the one that reaches the person inside it.
        return min(0.9, max(0.2, 0.5 / armor.effectiveness))
    }

    /// Everyone able to stand on the wall, weighed by health, heart and arms.
    public static func militia(_ pawns: [Pawn], registry: GameDataRegistry) -> Militia {
        var m = Militia()
        for pawn in pawns where !pawn.isBroken && pawn.health > 0 {
            let condition = pawn.health / 100
            let base = (baseUnarmedPower + pawn.genes.courage * couragePower) * condition
            if let weapon = weaponProfile(pawn, registry: registry) {
                switch weapon.kind {
                case .melee:
                    m.melee += base + weapon.damage * condition
                case .ranged:
                    m.ranged += base * rangedBasePenalty + weapon.damage * condition
                }
            } else {
                m.melee += base
            }
            m.fighters += 1
        }
        return m
    }

    /// The single defense number older call sites want: the whole militia.
    public static func defensePower(_ pawns: [Pawn], registry: GameDataRegistry) -> Double {
        militia(pawns, registry: registry).total
    }

    /// How hard a wound lands on a colonist: armor takes half of it.
    /// How many hunters in a crowd carry ranged arms — they thin the predators
    /// and soften a raid before it arrives.
    public static func rangedCount(_ pawns: [Pawn], registry: GameDataRegistry) -> Int {
        pawns.reduce(0) { count, pawn in
            guard !pawn.isBroken, pawn.health > 0,
                  weaponProfile(pawn, registry: registry)?.kind == .ranged else { return count }
            return count + 1
        }
    }

    // MARK: - Sub-tick timing

    /// Builds a battle's record as it resolves.
    ///
    /// Every beat is stamped with the **action step** it happened on — the
    /// simulation's own finer grain, not a decoration applied afterwards. The
    /// first cut of this spread beats evenly across the tick regardless of what
    /// happened, which made the timing a lie: two exchanges and eight looked
    /// identical on the clock. A round is an action step, so a long fight now
    /// genuinely occupies more of its tick than a short one.
    public struct BattleRecorder {
        private struct Pending {
            let step: Int
            let kind: BattleMoment.Kind
            let pawnID: UUID?
            let pawnName: String?
            let amount: Double
        }
        private var pending: [Pending] = []

        public init() {}

        /// Records a beat on a given action step. Steps beyond the tick's grid
        /// are clamped into it — a battle resolves inside one world tick.
        public mutating func record(
            _ kind: BattleMoment.Kind, step: Int = 0, pawnID: UUID? = nil,
            pawnName: String? = nil, amount: Double = 0
        ) {
            pending.append(Pending(
                step: min(max(0, step), WorldClock.actionStepsPerTick - 1),
                kind: kind, pawnID: pawnID, pawnName: pawnName, amount: amount))
        }

        /// Seals the record. Beats sharing a step are spread inside that step's
        /// slice in the order they were recorded, so simultaneous things stay
        /// distinguishable without pretending to be sequential.
        public func finish(
            id: UUID, tick: Int, attackerName: String, defenderName: String, repelled: Bool,
            attackerLabel: LocalizedText? = nil, approach: Double = 0,
            attackers: Int = 0, line: [UUID] = []
        ) -> BattleLog {
            let slice = 1.0 / Double(WorldClock.actionStepsPerTick)
            var seenInStep: [Int: Int] = [:]
            var countInStep: [Int: Int] = [:]
            for beat in pending { countInStep[beat.step, default: 0] += 1 }

            let moments = pending.enumerated().map { index, beat -> BattleMoment in
                let n = countInStep[beat.step] ?? 1
                let ordinal = seenInStep[beat.step, default: 0]
                seenInStep[beat.step] = ordinal + 1
                let within = (Double(ordinal) + 0.5) / Double(n)
                return BattleMoment(
                    id: index,
                    at: Double(beat.step) * slice + within * slice,
                    kind: beat.kind, pawnID: beat.pawnID,
                    pawnName: beat.pawnName, amount: beat.amount)
            }
            return BattleLog(id: id, tick: tick, attackerName: attackerName,
                             defenderName: defenderName, moments: moments, repelled: repelled,
                             attackerLabel: attackerLabel, approach: approach,
                             attackers: attackers, line: line)
        }

        public var isEmpty: Bool { pending.isEmpty }
    }
}
