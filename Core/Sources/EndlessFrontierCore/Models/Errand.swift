import Foundation

/// Somewhere a colonist is going **because of something they need**.
///
/// Needs existed and they bit — mood, health, frostbite — but they never caused
/// a decision, because they were satisfied by teleportation. A hungry colonist
/// ate out of the settlement's store wherever they happened to be standing;
/// warmth was a comfort number that went up because a hearth existed somewhere
/// in the colony. Nobody ever walked to a granary or to a fire. That is exactly
/// what "there is no dynamism" means: sixty people working, and not one of them
/// doing anything *because of* their own state.
///
/// An errand is the missing middle. It has a place to go, a moment it will
/// arrive, and the need is satisfied **on arrival** — so a colony whose granary
/// is on the far side of town genuinely feeds people more slowly, and one whose
/// granary burned genuinely fails to feed them at all.
///
/// It is not a `Job`. A job is work of a trade, handed out by `JobBoard` and
/// matched against `assignedWork`; an errand is a person's own business and
/// outranks whatever they were doing. Keeping the two apart is what lets a need
/// *interrupt* work instead of competing with it for the same slot.
public struct Errand: Codable, Sendable, Equatable {

    /// What they are going for.
    public enum Kind: String, Codable, Sendable, CaseIterable {
        /// A meal, at whatever holds the colony's food.
        case eat
        /// A fire, at whatever has one.
        case warmUp

        /// What the canvas should say they are up to.
        public var label: LocalizedText {
            switch self {
            case .eat: return LocalizedText(values: [
                .en: "Going for a meal", .cs: "Jde se najíst"])
            case .warmUp: return LocalizedText(values: [
                .en: "Going to the fire", .cs: "Jde se ohřát"])
            }
        }
    }

    public let kind: Kind
    /// Where they set off from — the work they left.
    public let from: LocalPoint
    /// …and what they are walking to.
    public let to: LocalPoint
    public let leftAt: Int
    /// The tick they get there. Distance made into time, which is the whole
    /// point: a far granary costs real minutes of nobody working.
    public let arrivesAt: Int
    /// The building they are going to, when it is a building.
    public let placementID: UUID?
    /// The corners they go round on the way, when the straight line would have
    /// taken them through somebody's house. Empty is the common case and means
    /// exactly what it used to: walk at it. Worked out once by `ColonyRoute`
    /// when the walk begins, never per tick (rule 4).
    public let via: [LocalPoint]

    public init(kind: Kind, from: LocalPoint, to: LocalPoint,
                leftAt: Int, arrivesAt: Int, placementID: UUID? = nil,
                via: [LocalPoint] = []) {
        self.kind = kind
        self.from = from
        self.to = to
        self.leftAt = leftAt
        self.arrivesAt = max(leftAt, arrivesAt)
        self.placementID = placementID
        self.via = via
    }

    /// Where they are on the way, so the canvas draws somebody crossing the
    /// town rather than somebody blinking from a field to a granary.
    ///
    /// Takes a *continuous* tick, because the canvas runs between ticks and a
    /// walk that advanced once a minute would be a person teleporting slowly.
    ///
    /// Walks the corners when there are any. `from → to` used to be a straight
    /// line, which is why colonists went **through the houses** — the shortest
    /// way across a town runs over whatever is standing in it. `via` is worked
    /// out once, by `ColonyRoute`, when the walk begins.
    /// The walk itself. The geometry lives in `WalkPath`, because an errand and
    /// a hauler cross the same colony the same way and only ever differed in
    /// that one of them had been taught to do it smoothly.
    public var path: WalkPath {
        WalkPath(from: from, to: to, leftAt: leftAt, arrivesAt: arrivesAt, via: via)
    }

    public func position(at tick: Double) -> LocalPoint { path.position(at: tick) }

    public func position(at tick: Int) -> LocalPoint { position(at: Double(tick)) }

    public func hasArrived(at tick: Int) -> Bool { tick >= arrivesAt }

    // MARK: - Codable (resilient: walks used to be straight lines)

    private enum CodingKeys: String, CodingKey {
        case kind, from, to, leftAt, arrivesAt, placementID, via
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        kind = try c.decode(Kind.self, forKey: .kind)
        from = try c.decode(LocalPoint.self, forKey: .from)
        to = try c.decode(LocalPoint.self, forKey: .to)
        leftAt = try c.decode(Int.self, forKey: .leftAt)
        arrivesAt = try c.decode(Int.self, forKey: .arrivesAt)
        placementID = try c.decodeIfPresent(UUID.self, forKey: .placementID)
        // A walk saved before anybody went round a house is a straight line,
        // which is exactly what an empty `via` means (rule 3).
        via = try c.decodeIfPresent([LocalPoint].self, forKey: .via) ?? []
    }
}
