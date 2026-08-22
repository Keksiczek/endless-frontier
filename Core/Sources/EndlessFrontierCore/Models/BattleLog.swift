import Foundation

/// One thing that happened inside a battle, stamped with *when* inside the tick
/// it happened.
public struct BattleMoment: Codable, Sendable, Equatable, Identifiable {
    /// What kind of beat this is — the canvas picks an animation by it.
    public enum Kind: String, Codable, Sendable {
        case volley      // archers loose from the wall
        case charge      // the attackers reach the line
        case clash       // melee at the palisade
        case wound       // a named defender is hurt
        case death       // …or killed
        case plunder     // stores carried off
        case torch       // a roof they came for, going up
        case repelled    // the attack breaks
    }

    public let id: Int
    /// Position inside the tick, 0…1. A tick is a real minute; this is what
    /// lets a battle be *watched* instead of appearing as a finished result.
    public let at: Double
    public let kind: Kind
    /// The colonist this beat happened to, when it happened to someone.
    public let pawnID: UUID?
    public let pawnName: String?
    /// How much was dealt, taken or carried off — damage, or goods.
    public let amount: Double
    /// **Where on the ground it landed** — the point of impact, between the two
    /// people who were touching.
    ///
    /// A beat used to be a time and a name, so the drawing had to guess a place
    /// for it and guessed the same place for all of them: a bright seam across
    /// the whole line, sparks at a computed "front". Colour standing in for
    /// events. A blow happens *somewhere*, and blood stays where it fell, so
    /// the place is part of the record — and a replay of a finished fight, which
    /// has no positions in it at all, gets its blood in the right places too.
    public let spot: LocalPoint?

    /// **Where it was fired from**, when it was fired at all.
    ///
    /// A volley knew where it landed and nothing about where it came from, so
    /// the canvas worked the other end out by stepping back along the field's
    /// axis — an arrow drawn from a place chosen by arithmetic rather than
    /// from the archer. With a hundred yards between a pistol and a rifle that
    /// stops being close enough: the length of the shot *is* the weapon.
    public let from: LocalPoint?

    /// What was fired. Nil in every fight recorded before weapons had
    /// projectiles, and read as an arrow — which is what those fights drew.
    public let projectile: ProjectileKind?
    /// **Where it landed, and what made it.**
    ///
    /// The anatomy has been in `Body` since animals got one — head, torso, two
    /// arms, two legs, each with its own condition and its own `missing` — and
    /// the battle record threw all of it away: a beat said a name and a number.
    /// Keks: *"chybi detailni log boju ze nekdo zasahl nekoho nekam."*
    public let part: BodyPartKind?
    public let wound: WoundKind?

    /// How big the thing was, against an arrow at 1. Carried on the moment
    /// rather than looked up, because a replay has no fighters left to ask.
    public let caliber: Double?

    /// How many left the weapon in this beat. A bow looses one.
    public let shots: Int?

    public init(id: Int, at: Double, kind: Kind, pawnID: UUID? = nil,
                pawnName: String? = nil, amount: Double = 0,
                spot: LocalPoint? = nil, from: LocalPoint? = nil,
                projectile: ProjectileKind? = nil, caliber: Double? = nil,
                shots: Int? = nil, part: BodyPartKind? = nil,
                wound: WoundKind? = nil) {
        self.id = id
        self.at = min(1, max(0, at))
        self.kind = kind
        self.pawnID = pawnID
        self.pawnName = pawnName
        self.amount = amount
        self.spot = spot
        self.from = from
        self.projectile = projectile
        self.caliber = caliber
        self.shots = shots
        self.part = part
        self.wound = wound
    }

    // MARK: - Codable (resilient: the place postdates the first battles)

    private enum CodingKeys: String, CodingKey {
        case id, at, kind, pawnID, pawnName, amount, spot
        case from, projectile, caliber, shots, part, wound
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        at = try c.decode(Double.self, forKey: .at)
        kind = try c.decode(Kind.self, forKey: .kind)
        pawnID = try c.decodeIfPresent(UUID.self, forKey: .pawnID)
        pawnName = try c.decodeIfPresent(String.self, forKey: .pawnName)
        amount = try c.decodeIfPresent(Double.self, forKey: .amount) ?? 0
        spot = try c.decodeIfPresent(LocalPoint.self, forKey: .spot)
        from = try c.decodeIfPresent(LocalPoint.self, forKey: .from)
        projectile = try c.decodeIfPresent(ProjectileKind.self, forKey: .projectile)
        caliber = try c.decodeIfPresent(Double.self, forKey: .caliber)
        shots = try c.decodeIfPresent(Int.self, forKey: .shots)
        part = try c.decodeIfPresent(BodyPartKind.self, forKey: .part)
        wound = try c.decodeIfPresent(WoundKind.self, forKey: .wound)
    }
}

/// A battle as an ordered sequence of moments within a single tick.
///
/// Combat used to resolve as one arithmetic step: a strength number met a
/// defense number, some colonists lost health, and the player was told the
/// outcome. There was nothing to *watch*, and nothing a renderer could animate,
/// because no intermediate state ever existed.
///
/// This is the sub-tick layer the animated combat needs. The simulation still
/// resolves the battle entirely within one whole tick — determinism is
/// untouched, the outcome is identical whether or not anyone is looking — but
/// it now records the order and timing of what happened, so presentation can
/// play it back over real seconds. Sub-tick time lives in the *record*, not in
/// the tick loop.
public struct BattleLog: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    /// The tick this battle happened on.
    public let tick: Int
    /// Who attacked, for the headline. A proper noun — a tribe's own name —
    /// which is why it is a plain string and not translated.
    public let attackerName: String
    /// …except when the attacker is not a someone but a something. "A beast"
    /// is not a name, and printing it untranslated into a Czech card is how a
    /// carefully bilingual game says *A beast* at you. Set for generic
    /// attackers; nil when `attackerName` is a real name.
    public let attackerLabel: LocalizedText?
    public let defenderName: String
    public let moments: [BattleMoment]
    public let repelled: Bool

    /// The bearing the attack came in on, in radians about the settlement's
    /// heart. Fixed for the battle, so a raid does not swing around the map
    /// while it is being watched, and *stored* rather than derived from a hash
    /// so the same fight always comes from the same side of the valley.
    public let approach: Double
    /// How many steps the fight it records ran for, so a replay beats at the
    /// same rate the live fight did.
    public let steps: Int
    /// How many came. The canvas draws this many raiders; the simulation
    /// settles the fight on strength alone, so this is the strength made
    /// countable rather than a second source of truth.
    public let attackers: Int
    /// The colonists who turned out to meet them, in the order they took the
    /// line. This is what makes defence something to watch: these are the very
    /// pawns the canvas sends running to the wall, so the line that holds is
    /// made of people you know by name.
    public let line: [UUID]
    /// **Where they came from**, when it was an outlaw camp (`OutlawCamp`).
    ///
    /// The record is what survives the fight — `Settlement.siege` is gone the
    /// moment it ends — so anything that wants to ask *who attacked us over
    /// the last two centuries* has to be able to ask it here. Without this a
    /// probe can only count the raids that happen to be live at the instant it
    /// samples, which measured **14 raids in two hundred years** for a colony
    /// that had far more than fourteen.
    public var attackerCampID: UUID?

    public init(id: UUID, tick: Int, attackerName: String, defenderName: String,
                moments: [BattleMoment], repelled: Bool,
                attackerLabel: LocalizedText? = nil, approach: Double = 0,
                steps: Int = Siege.stepsTotal,
                attackers: Int = 0, line: [UUID] = [],
                attackerCampID: UUID? = nil) {
        self.id = id
        self.tick = tick
        self.attackerName = attackerName
        self.attackerLabel = attackerLabel
        self.defenderName = defenderName
        self.moments = moments.sorted { $0.at == $1.at ? $0.id < $1.id : $0.at < $1.at }
        self.repelled = repelled
        self.approach = approach
        self.steps = max(1, steps)
        self.attackers = attackers
        self.line = line
        self.attackerCampID = attackerCampID
    }

    // MARK: - Codable (resilient: the staging postdates the first battles)

    private enum CodingKeys: String, CodingKey {
        case id, tick, attackerName, attackerLabel, defenderName, moments, repelled
        case approach, attackers, line, steps, attackerCampID
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        tick = try c.decode(Int.self, forKey: .tick)
        attackerName = try c.decode(String.self, forKey: .attackerName)
        attackerLabel = try c.decodeIfPresent(LocalizedText.self, forKey: .attackerLabel)
        defenderName = try c.decode(String.self, forKey: .defenderName)
        moments = try c.decode([BattleMoment].self, forKey: .moments)
        repelled = try c.decode(Bool.self, forKey: .repelled)
        approach = try c.decodeIfPresent(Double.self, forKey: .approach) ?? 0
        steps = try c.decodeIfPresent(Int.self, forKey: .steps) ?? Siege.stepsTotal
        attackers = try c.decodeIfPresent(Int.self, forKey: .attackers) ?? 0
        line = try c.decodeIfPresent([UUID].self, forKey: .line) ?? []
        attackerCampID = try c.decodeIfPresent(UUID.self, forKey: .attackerCampID)
    }

    /// The attacker as the player should read it: the translated word for a
    /// thing, the plain name of a people.
    public func attacker(_ language: GameLanguage) -> String {
        attackerLabel?.resolve(language) ?? attackerName
    }

    /// How many figures to put on the raiders' side — always at least one, and
    /// capped so a horde is a crowd rather than a screen of dots.
    public var drawnAttackers: Int { min(14, max(1, attackers)) }

    /// The moments that have played by a given point inside the tick.
    public func moments(upTo progress: Double) -> [BattleMoment] {
        moments.filter { $0.at <= progress }
    }

    public var deaths: Int { moments.count { $0.kind == .death } }
    public var wounded: Int { moments.count { $0.kind == .wound } }
    public var plunder: Double { moments.first { $0.kind == .plunder }?.amount ?? 0 }
}
