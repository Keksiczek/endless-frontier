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

        /// How far out from the town this posture is willing to fight.
        ///
        /// This replaces the old `cover` multiplier, and the difference is the
        /// whole pivot: a posture no longer *says* how much of the wall counts,
        /// it says **where people stand**, and `SiegeField.cover(at:)` reads the
        /// wall off the ground they are standing on. Pressing loses the wall
        /// because it walks out from behind it.
        public var reach: Double {
            switch self {
            case .hold: return SiegeField.musterReach
            case .press: return SiegeField.originReach
            case .giveGround: return 0
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

    /// One figure on the field, and **where it is standing**.
    ///
    /// The fight used to be arithmetic on one strength number paired against a
    /// round index: raider seven fought colonist three because seven and three
    /// were opposite each other in two lists. Nobody walked anywhere, which is
    /// exactly why the rounds felt strange to stand in — the canvas drew an
    /// arrangement of people the simulation did not have.
    ///
    /// A combatant has a position the Core owns and moves. Contact is being
    /// close enough to reach, the approach is *not being close enough yet*
    /// rather than a step count, and an order to go somewhere is a thing the
    /// simulation can actually carry out.
    public struct Combatant: Codable, Sendable, Equatable, Identifiable {
        public enum Side: String, Codable, Sendable { case colony, raider }

        /// Whether this is somebody standing on the field or something the
        /// colony built that fights from where it stands.
        ///
        /// **The first thing in the game that is a building which acts.** A
        /// watchtower holds ground, has a line to what it is shooting at, and
        /// is worth attacking because of where it stands — none of which an
        /// abstract `defense` number can express (§11.27). It is a combatant
        /// rather than a special case in the resolver because everything the
        /// field already does — position, targeting, reach, the canvas reading
        /// where things are — is exactly what a turret needs.
        public enum Kind: String, Codable, Sendable { case person, emplacement }

        /// A colonist's pawn id, a raider's own stable id, or — for an
        /// emplacement — the id of the building itself.
        public let id: UUID
        public let side: Side
        /// What it is. Old saves have none and are people, which is what
        /// everything on a field before this was.
        public var kind: Kind = .person
        /// Where they are, in local-map coordinates.
        public var at: LocalPoint
        /// What a raider is still worth — their share of the warband, spent as
        /// the line cuts them down. A colonist's weight is their health, so
        /// this holds their opening power and is only read, never spent.
        public var strength: Double
        /// Who they have closed on, if anybody.
        public var target: UUID?
        /// Down, or gone from the field.
        public var down: Bool

        public init(id: UUID, side: Side, at: LocalPoint, strength: Double,
                    target: UUID? = nil, down: Bool = false,
                    kind: Kind = .person) {
            self.id = id
            self.side = side
            self.kind = kind
            self.at = at
            self.strength = strength
            self.target = target
            self.down = down
        }

        private enum CodingKeys: String, CodingKey {
            case id, side, kind, at, strength, target, down
        }

        /// Written by hand because a synthesised decoder does **not** fall back
        /// to a property's default value: a raid saved before turrets existed
        /// carries no `kind`, and the synthesised one would refuse to load it —
        /// which is a battle in progress lost to an app update.
        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decode(UUID.self, forKey: .id)
            side = try c.decode(Side.self, forKey: .side)
            kind = try c.decodeIfPresent(Kind.self, forKey: .kind) ?? .person
            at = try c.decode(LocalPoint.self, forKey: .at)
            strength = try c.decode(Double.self, forKey: .strength)
            target = try c.decodeIfPresent(UUID.self, forKey: .target)
            down = try c.decodeIfPresent(Bool.self, forKey: .down) ?? false
        }
    }

    /// What the player has told **one** colonist to do, by tapping them and
    /// then tapping the ground or an enemy.
    ///
    /// Recorded on the siege exactly as `posture` is, for exactly the same
    /// reason: the fight may depend on the player's orders, but given the same
    /// seed *and the same orders* it has to replay to the same dead. An order
    /// that lived in the view would be a hole in determinism.
    public enum Order: Codable, Sendable, Equatable {
        /// Go there and hold it.
        case moveTo(LocalPoint)
        /// Go for that one.
        case engage(UUID)
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
    /// How much of the stores this attacker can actually carry off, as a
    /// multiple of the usual share.
    ///
    /// A warband comes with sacks and mules; a wolf pack takes a sheep. Both
    /// used to take the same eight-to-thirty-five per cent of the granary, and
    /// with a pack arriving every few years that quietly emptied the colony —
    /// measured, 388 starved over two centuries in a town that was never short
    /// of hands. What an attacker *is* has to decide what it can steal.
    public var carriesOff: Double

    /// What the player has told the line to do, right now.
    public var posture: Posture
    /// Everyone on the field, with a place on it. Colonists first, in the order
    /// they took the line, then the raiders as they come over the ground.
    public var fighters: [Combatant]
    /// …and what individual colonists have been told, over the top of the
    /// posture. Empty is the normal case: a colony is run by standing orders
    /// and a battle should not demand that sixty people be steered one by one.
    public var orders: [UUID: Order]
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
        line: [UUID], posture: Posture = .hold, carriesOff: Double = 1
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
        self.carriesOff = carriesOff
        self.fighters = []
        self.orders = [:]
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

    // MARK: - The field, read

    public var raiders: [Combatant] { fighters.filter { $0.side == .raider } }
    /// The **people** holding the line. A tower is not one of them: it is not in
    /// the roster, it is not counted as somebody still standing, and it does not
    /// leave a body when it falls. See `emplacements`.
    public var defenders: [Combatant] {
        fighters.filter { $0.side == .colony && $0.kind == .person }
    }
    /// …and the things the colony built that fight from where they stand.
    public var emplacements: [Combatant] {
        fighters.filter { $0.kind == .emplacement }
    }

    /// Whether anybody is close enough to anybody to be fighting them. What
    /// "the ranks are in contact" means now that there is a ground to be on —
    /// the phase is read off the field rather than off a step number.
    public var inContact: Bool {
        let colony = fighters.filter { $0.side == .colony && !$0.down }
        guard !colony.isEmpty else { return false }
        return fighters.contains { raider in
            guard raider.side == .raider, !raider.down else { return false }
            return colony.contains { SiegeField.distance($0.at, raider.at) <= SiegeEngine.reach }
        }
    }

    /// Where a given fighter is standing, if they are on this field.
    public func place(of id: UUID) -> LocalPoint? {
        fighters.first { $0.id == id }?.at
    }

    // MARK: - Codable (resilient: sieges postdate the first battles)

    private enum CodingKeys: String, CodingKey {
        case id, startTick, advancedTo, openedAt, attackerName, attackerLabel
        case attackerTribeID
        case approach, attackers, openingStrength, strength, fortification, seed
        case line, withdrawn, posture, damage, moments, plundered, carriesOff
        case fighters, orders
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
        carriesOff = try c.decodeIfPresent(Double.self, forKey: .carriesOff) ?? 1
        // A raid saved before anybody had a position on the field: the engine
        // stages the roster on the next step it fights (rule 3 — every new
        // field optional, with a default that the code can actually work from).
        fighters = try c.decodeIfPresent([Combatant].self, forKey: .fighters) ?? []
        orders = try c.decodeIfPresent([UUID: Order].self, forKey: .orders) ?? [:]
        damage = try c.decodeIfPresent([UUID: Double].self, forKey: .damage) ?? [:]
        moments = try c.decodeIfPresent([BattleMoment].self, forKey: .moments) ?? []
        plundered = try c.decodeIfPresent(Double.self, forKey: .plundered) ?? 0
    }
}
