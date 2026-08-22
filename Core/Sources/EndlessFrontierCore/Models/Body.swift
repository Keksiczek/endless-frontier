import Foundation

/// A colonist's body, part by part.
///
/// Animals have had one since they became pawns — a head, a torso, four legs,
/// each of which can be hurt, lost, or frozen — and colonists have had a single
/// number called `health`. So a hunter gored by a boar and a hunter who had a
/// bad winter were the same colonist at 60, and nothing that happened to a
/// person ever left a mark you could name.
///
/// This is the same layer, asked of people. A wound lands *somewhere*: an arm
/// that cannot swing an axe, a leg that cannot cross the valley, an eye that
/// cannot see the deer. Bleeding kills if nobody treats it, and treating it is
/// what the healer's trade is finally for.
///
/// `Pawn.health` stays the aggregate everything already balances on — combat,
/// morale, work — and the body *drives* it. Nothing that read `health` before
/// has to change; there is simply now an answer to "what happened to them".
public enum BodyPartKind: String, Codable, Sendable, CaseIterable {
    case head, torso
    case leftArm, rightArm
    case leftLeg, rightLeg

    /// A part whose loss is fatal.
    public var isVital: Bool { self == .head || self == .torso }

    /// Losing one of these costs you work.
    public var isArm: Bool { self == .leftArm || self == .rightArm }
    /// …and one of these costs you the walk.
    public var isLeg: Bool { self == .leftLeg || self == .rightLeg }

    /// How likely a blow that lands at random lands here. A torso is a big
    /// target and a head is not, which is why most wounds are survivable and
    /// the occasional one is not.
    public var exposure: Double {
        switch self {
        case .torso: return 0.38
        case .head: return 0.10
        case .leftArm, .rightArm: return 0.15
        case .leftLeg, .rightLeg: return 0.11
        }
    }

    public var displayName: LocalizedText {
        switch self {
        case .head: return LocalizedText(values: [.en: "Head", .cs: "Hlava"])
        case .torso: return LocalizedText(values: [.en: "Torso", .cs: "Trup"])
        case .leftArm: return LocalizedText(values: [.en: "Left arm", .cs: "Levá paže"])
        case .rightArm: return LocalizedText(values: [.en: "Right arm", .cs: "Pravá paže"])
        case .leftLeg: return LocalizedText(values: [.en: "Left leg", .cs: "Levá noha"])
        case .rightLeg: return LocalizedText(values: [.en: "Right leg", .cs: "Pravá noha"])
        }
    }
}

public struct BodyPart: Codable, Sendable, Equatable {
    public let kind: BodyPartKind
    /// 0…1: 1 whole, 0 destroyed.
    public var condition: Double
    public var missing: Bool

    public init(kind: BodyPartKind, condition: Double = 1, missing: Bool = false) {
        self.kind = kind
        self.condition = min(1, max(0, condition))
        self.missing = missing
    }

    /// Whether this part still does its job at all.
    public var isUsable: Bool { !missing && condition > 0.2 }
}

/// What a colonist is carrying in the way of harm.
public enum AilmentKind: String, Codable, Sendable, CaseIterable {
    /// An open wound. Bleeds until treated or until it closes on its own.
    case wound
    /// An illness that runs its course — or does not.
    case sickness
    /// The cold got into them.
    case frostbite
    /// Set and healing, thanks to somebody's work.
    case tended

    public var displayName: LocalizedText {
        switch self {
        case .wound: return LocalizedText(values: [.en: "Wound", .cs: "Rána"])
        case .sickness: return LocalizedText(values: [.en: "Sickness", .cs: "Nemoc"])
        case .frostbite: return LocalizedText(values: [.en: "Frostbite", .cs: "Omrzliny"])
        case .tended: return LocalizedText(values: [.en: "Tended", .cs: "Ošetřeno"])
        }
    }
}

/// What *made* a wound — the difference between a cut and a broken bone.
///
/// Keks, after a fight: *"se souboji by se možná hodilo víc popisů zranění a
/// typu, jako v RimWorldu."* The body already knew a blow landed on the left
/// arm and how badly; what it could not say was what kind of blow it was, so
/// every injury in the game read as the same word. A spear through the shoulder
/// and a club across the ribs are not the same story, and telling them apart
/// costs nothing but the name.
///
/// Derived from the weapon that dealt it, not rolled — see
/// `MedicineEngine.wound`. A wound with no weapon behind it is a `.bruise`,
/// which is what falling over gives you.
public enum WoundKind: String, Codable, Sendable, CaseIterable {
    /// An edge: a long, shallow, bleeding thing.
    case cut
    /// A point, gone deep. Bleeds worst of the three.
    case stab
    /// Something blunt. Bleeds least and breaks most.
    case bruise
    /// Teeth or claws — a beast, or a dog set on somebody.
    case bite
    /// Fire, or something that had been in it.
    case burn

    /// How freely this kind bleeds, against an ordinary cut.
    ///
    /// The number that makes the name mean something rather than decorate a
    /// line of text: a stab is what kills somebody an hour after the fighting
    /// stopped, and a bruise is what they walk off.
    /// **What a given shot leaves behind.**
    ///
    /// A wound used to be rolled — `MedicineEngine.ordinaryWound` off a die —
    /// so an arrow, a musket ball and a sword all left whatever came up. What
    /// hurt somebody is known at the moment it happens, and it is the
    /// difference between "a cut to the left arm" and "wound".
    public static func from(_ projectile: ProjectileKind) -> WoundKind {
        switch projectile {
        // Nothing left the weapon: it was swung.
        case .none: return .cut
        case .arrow, .bolt, .dart, .bullet: return .stab
        case .stone, .ball, .shot: return .bruise
        case .shell, .grenade, .rocket, .beam: return .burn
        }
    }

    public var bleedFactor: Double {
        switch self {
        case .cut:    return 1.0
        case .stab:   return 1.35
        case .bruise: return 0.35
        case .bite:   return 1.15
        case .burn:   return 0.55
        }
    }

    public var displayName: LocalizedText {
        switch self {
        case .cut:    return LocalizedText(values: [.en: "Cut", .cs: "Řezná rána"])
        case .stab:   return LocalizedText(values: [.en: "Stab", .cs: "Bodná rána"])
        case .bruise: return LocalizedText(values: [.en: "Bruise", .cs: "Pohmožděnina"])
        case .bite:   return LocalizedText(values: [.en: "Bite", .cs: "Kousnutí"])
        case .burn:   return LocalizedText(values: [.en: "Burn", .cs: "Popálenina"])
        }
    }
}

/// One thing wrong with a colonist, on a named part where it belongs on one.
public struct Ailment: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public var kind: AilmentKind
    /// What made it, when something did. Nil for anything that is not a wound —
    /// a sickness has no edge and no point.
    public var wound: WoundKind?
    /// Where it is, when it is anywhere in particular.
    public var part: BodyPartKind?
    /// 0…1 — how bad it is.
    public var severity: Double
    /// Whether somebody has seen to it. A tended wound stops bleeding and
    /// closes far faster; an untended one is what kills people after a fight
    /// rather than during it.
    public var tended: Bool
    /// The tick it was taken, so the inspector can say how long ago.
    public let sinceTick: Int

    public init(id: UUID, kind: AilmentKind, part: BodyPartKind? = nil,
                severity: Double, tended: Bool = false, sinceTick: Int = 0,
                wound: WoundKind? = nil) {
        self.id = id
        self.kind = kind
        self.part = part
        self.severity = min(1, max(0, severity))
        self.tended = tended
        self.sinceTick = sinceTick
        self.wound = wound
    }

    /// How fast this bleeds a colonist out, in health per tick.
    public var bleedRate: Double {
        guard kind == .wound, !tended else { return 0 }
        return severity * Body.bleedPerSeverity * (wound?.bleedFactor ?? 1)
    }

    /// What this reads as on a card: "Stab — left arm", or just "Sickness".
    public var title: LocalizedText {
        let head = wound?.displayName ?? kind.displayName
        guard let part else { return head }
        return LocalizedText(values: [
            .en: "\(head.resolve(.en)) — \(part.displayName.resolve(.en).lowercased())",
            .cs: "\(head.resolve(.cs)) — \(part.displayName.resolve(.cs).lowercased())"])
    }

    // MARK: - Codable (resilient: wounds had no kind before)

    private enum CodingKeys: String, CodingKey {
        case id, kind, part, severity, tended, sinceTick, wound
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        kind = try c.decode(AilmentKind.self, forKey: .kind)
        part = try c.decodeIfPresent(BodyPartKind.self, forKey: .part)
        severity = try c.decode(Double.self, forKey: .severity)
        tended = try c.decodeIfPresent(Bool.self, forKey: .tended) ?? false
        sinceTick = try c.decodeIfPresent(Int.self, forKey: .sinceTick) ?? 0
        // A wound saved before anybody asked what made it keeps bleeding at
        // exactly the rate it used to — `bleedFactor` falls back to 1 (rule 3).
        wound = try c.decodeIfPresent(WoundKind.self, forKey: .wound)
    }
}

/// A whole body, and what can be asked of it.
public struct Body: Codable, Sendable, Equatable {
    /// Health lost per tick per point of untended wound severity.
    public static let bleedPerSeverity: Double = 0.9
    /// How fast an untended wound closes by itself…
    public static let healPerTick: Double = 0.0025
    /// …and how much faster once somebody has seen to it.
    public static let tendedHealMultiplier: Double = 5.0
    /// Below this a part is as good as gone for the work it does.
    public static let crippledBelow: Double = 0.2

    public var parts: [BodyPart]
    public var ailments: [Ailment]

    public init(parts: [BodyPart]? = nil, ailments: [Ailment] = []) {
        self.parts = parts ?? BodyPartKind.allCases.map { BodyPart(kind: $0) }
        self.ailments = ailments
    }

    public func part(_ kind: BodyPartKind) -> BodyPart? {
        parts.first { $0.kind == kind }
    }

    /// Whether they are alive at all: a lost head or torso is not survivable.
    public var isAlive: Bool {
        part(.head)?.missing != true && part(.torso)?.missing != true
    }

    /// Whether they can still get about. One good leg limps; none does not.
    public var canWalk: Bool {
        parts.contains { $0.kind.isLeg && $0.isUsable }
    }

    /// Whether they can still do a day's work with their hands.
    public var canWork: Bool {
        parts.contains { $0.kind.isArm && $0.isUsable }
    }

    /// How much of a day's work they are good for, 0…1 — what the economy
    /// actually reads. A man with one arm works; a man with none does not.
    public var capacity: Double {
        let arms = parts.filter { $0.kind.isArm }
        let legs = parts.filter { $0.kind.isLeg }
        let armShare = arms.isEmpty ? 1 : arms.reduce(0.0) {
            $0 + ($1.missing ? 0 : $1.condition)
        } / Double(arms.count)
        let legShare = legs.isEmpty ? 1 : legs.reduce(0.0) {
            $0 + ($1.missing ? 0 : $1.condition)
        } / Double(legs.count)
        // Arms matter most to work; legs matter to getting to it.
        let sick = ailments.filter { $0.kind == .sickness }.reduce(0.0) { $0 + $1.severity }
        return max(0, min(1, armShare * 0.65 + legShare * 0.35 - min(0.5, sick * 0.4)))
    }

    /// Everything untreated that somebody could do something about.
    public var untended: [Ailment] {
        ailments.filter { !$0.tended && $0.kind != .tended }
    }

    /// How fast they are losing blood right now.
    public var bleeding: Double {
        ailments.reduce(0) { $0 + $1.bleedRate }
    }

    /// Whether this body needs a healer at all.
    public var needsTending: Bool { !untended.isEmpty }

    // MARK: - Harm

    /// Lands a blow on a named part and leaves a wound where it landed.
    /// Returns whether the body is still alive.
    @discardableResult
    public mutating func injure(
        _ kind: BodyPartKind, by amount: Double, id: UUID, tick: Int,
        from wound: WoundKind? = nil
    ) -> Bool {
        guard amount > 0 else { return isAlive }
        if let i = parts.firstIndex(where: { $0.kind == kind }), !parts[i].missing {
            parts[i].condition = max(0, parts[i].condition - amount / 45)
            if parts[i].condition <= 0 { parts[i].missing = true }
        }
        ailments.append(Ailment(id: id, kind: .wound, part: kind,
                                severity: min(1, amount / 50), sinceTick: tick,
                                wound: wound))
        return isAlive
    }

    /// Where a blow that was not aimed lands. Deterministic in `roll` (0…1), so
    /// the same fight always hurts the same person in the same place.
    public static func struckPart(roll: Double) -> BodyPartKind {
        let total = BodyPartKind.allCases.reduce(0.0) { $0 + $1.exposure }
        var pick = min(0.999, max(0, roll)) * total
        for kind in BodyPartKind.allCases {
            pick -= kind.exposure
            if pick <= 0 { return kind }
        }
        return .torso
    }
}
