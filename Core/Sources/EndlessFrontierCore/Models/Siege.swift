import Foundation

/// A fight that is **still happening**.
///
/// `BattleResolver` settles a raid inside one tick: eight rounds of arithmetic
/// run between two frames, the outcome is decided, and the `BattleLog` is a
/// recording played back afterwards. That is why a raid could be *watched* and
/// never *fought* — by the time the canvas was told anything, it was over.
///
/// A siege is the same fight with its middle left open. It is live state on the
/// settlement: the attackers' remaining strength, who is standing in the line,
/// which action step the fighting has reached, and — the point of all of it —
/// **what the player has told the line to do**. Orders are recorded here, so
/// they are an *input* to the resolution rather than a hole in it: the same
/// seed and the same orders replay to the same dead.
///
/// Pacing is not the model's business. A siege advances by absolute action
/// step, and whoever reaches a step first advances it: the app drives it at a
/// pace a person can act at, and if nobody is watching, `ActionLoop` walks the
/// world clock over the top of it and the rest is fought exactly as it would
/// have been. This is what makes leaving mid-battle safe.
public struct Siege: Codable, Sendable, Equatable, Identifiable {

    /// What the colony has been told to do. The one lever the player holds
    /// while the fighting is going on, and a real choice rather than a
    /// difficulty slider: what you save costs what you spend.
    public enum Posture: String, Codable, Sendable, CaseIterable {
        /// Stand at the wall. The fortification does its work; the line trades
        /// evenly. What the colony does with nobody steering it.
        case hold
        /// Push out past the wall and break them. Much more damage dealt, and
        /// the wall stops covering the people who left it.
        case press
        /// Fall back into the town. Almost nobody is hurt — and the granaries
        /// are open, so the raiders take what they came for.
        case giveGround

        /// How hard the line hits at this posture.
        public var bite: Double {
            switch self {
            case .hold: return 1
            case .press: return 1.75
            case .giveGround: return 0.25
            }
        }

        /// …and how much of what comes back actually lands on somebody.
        public var exposure: Double {
            switch self {
            case .hold: return 1
            case .press: return 1.6
            case .giveGround: return 0.2
            }
        }

        /// How much of the wall still counts. Nobody behind it while pressing,
        /// all of it while giving ground.
        public var cover: Double {
            switch self {
            case .hold: return 1
            case .press: return 0.35
            case .giveGround: return 1.2
            }
        }

        public var label: LocalizedText {
            switch self {
            case .hold: return LocalizedText(values: [
                .en: "Hold the wall", .cs: "Držet hradbu"])
            case .press: return LocalizedText(values: [
                .en: "Press them", .cs: "Vyrazit na ně"])
            case .giveGround: return LocalizedText(values: [
                .en: "Give ground", .cs: "Ustoupit"])
            }
        }

        public var note: LocalizedText {
            switch self {
            case .hold: return LocalizedText(values: [
                .en: "The wall does its work.", .cs: "Hradba dělá svoje."])
            case .press: return LocalizedText(values: [
                .en: "Break them faster — and out from behind the wall.",
                .cs: "Zlomit je rychleji — a zpoza hradby ven."])
            case .giveGround: return LocalizedText(values: [
                .en: "Nobody dies for grain.", .cs: "Za obilí se neumírá."])
            }
        }
    }

    /// How many action steps a siege runs before it is decided one way or the
    /// other. Three world ticks' worth on the shared grid — long enough that
    /// the player's orders can change it twice, short enough to be a fight
    /// rather than a chore.
    public static let stepsTotal = 24

    public let id: UUID
    /// The world tick the attack arrived on.
    public let startTick: Int
    /// The absolute action step the fighting has been carried up to. The whole
    /// pacing contract: a step is fought once, by whoever reaches it first.
    public var advancedTo: Int
    /// The absolute action step the siege opened on.
    public let openedAt: Int

    public let attackerName: String
    public let attackerLabel: LocalizedText?
    /// The people who sent them, when a people did. What the attempt cost them
    /// is only known when the fighting stops, so the tribe is charged at the
    /// end rather than when the raid was declared.
    public let attackerTribeID: UUID?
    /// The bearing they came in on, so the canvas draws the same fight the
    /// simulation is running.
    public let approach: Double
    /// How many figures the raid puts on the field.
    public let attackers: Int
    /// What the attack was worth when it arrived, and what is left of it.
    public let openingStrength: Double
    public var strength: Double
    /// The colony's standing defence — walls do not swing, but they absorb.
    public let fortification: Double
    /// Rolls come from this and the step index, so a step's outcome is a pure
    /// function of where it sits in the fight.
    public let seed: UInt64

    /// Everyone who turned out, in the order they took the line.
    public var line: [UUID]
    /// …and the ones the player has pulled out of it. They stop being a target
    /// and stop counting toward the line's weight.
    public var withdrawn: Set<UUID>
    /// What the player has told the line to do, right now.
    public var posture: Posture
    /// Damage dealt so far, by pawn — applied to the colonists as it lands.
    public var damage: [UUID: Double]
    /// The record as it accumulates, so the canvas can draw a fight that has
    /// not finished yet.
    public var moments: [BattleMoment]
    /// Food carried off while the colony gave ground.
    public var plundered: Double

    public init(
        id: UUID, startTick: Int, openedAt: Int,
        attackerName: String, attackerLabel: LocalizedText? = nil,
        attackerTribeID: UUID? = nil,
        approach: Double, attackers: Int,
        openingStrength: Double, fortification: Double, seed: UInt64,
        line: [UUID], posture: Posture = .hold
    ) {
        self.id = id
        self.startTick = startTick
        self.openedAt = openedAt
        self.advancedTo = openedAt
        self.attackerName = attackerName
        self.attackerLabel = attackerLabel
        self.attackerTribeID = attackerTribeID
        self.approach = approach
        self.attackers = attackers
        self.openingStrength = max(0, openingStrength)
        self.strength = max(0, openingStrength)
        self.fortification = max(0, fortification)
        self.seed = seed
        self.line = line
        self.withdrawn = []
        self.posture = posture
        self.damage = [:]
        self.moments = []
        self.plundered = 0
    }

    /// Which step of its own fight the siege is on, `0 ..< stepsTotal`.
    public var step: Int { max(0, advancedTo - openedAt) }

    /// How far through the fight it is, 0…1 — what the canvas plays against.
    public var progress: Double {
        min(1, Double(step) / Double(Self.stepsTotal))
    }

    /// Whether the fighting is over: they broke, or they ran out of fight.
    public var isFinished: Bool {
        strength <= 0 || step >= Self.stepsTotal || standing.isEmpty
    }

    /// The colonists actually holding the line right now.
    public var standing: [UUID] {
        line.filter { !withdrawn.contains($0) }
    }

    /// Whether the colony held. Only meaningful once it is finished.
    public var repelled: Bool { strength <= 0 }

    // MARK: - Codable (resilient: sieges postdate the first battles)

    private enum CodingKeys: String, CodingKey {
        case id, startTick, advancedTo, openedAt, attackerName, attackerLabel
        case attackerTribeID
        case approach, attackers, openingStrength, strength, fortification, seed
        case line, withdrawn, posture, damage, moments, plundered
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        startTick = try c.decode(Int.self, forKey: .startTick)
        openedAt = try c.decodeIfPresent(Int.self, forKey: .openedAt) ?? 0
        advancedTo = try c.decodeIfPresent(Int.self, forKey: .advancedTo) ?? openedAt
        attackerName = try c.decode(String.self, forKey: .attackerName)
        attackerLabel = try c.decodeIfPresent(LocalizedText.self, forKey: .attackerLabel)
        attackerTribeID = try c.decodeIfPresent(UUID.self, forKey: .attackerTribeID)
        approach = try c.decodeIfPresent(Double.self, forKey: .approach) ?? 0
        attackers = try c.decodeIfPresent(Int.self, forKey: .attackers) ?? 1
        openingStrength = try c.decodeIfPresent(Double.self, forKey: .openingStrength) ?? 0
        strength = try c.decodeIfPresent(Double.self, forKey: .strength) ?? 0
        fortification = try c.decodeIfPresent(Double.self, forKey: .fortification) ?? 0
        seed = try c.decodeIfPresent(UInt64.self, forKey: .seed) ?? 1
        line = try c.decodeIfPresent([UUID].self, forKey: .line) ?? []
        withdrawn = try c.decodeIfPresent(Set<UUID>.self, forKey: .withdrawn) ?? []
        posture = try c.decodeIfPresent(Posture.self, forKey: .posture) ?? .hold
        damage = try c.decodeIfPresent([UUID: Double].self, forKey: .damage) ?? [:]
        moments = try c.decodeIfPresent([BattleMoment].self, forKey: .moments) ?? []
        plundered = try c.decodeIfPresent(Double.self, forKey: .plundered) ?? 0
    }
}
