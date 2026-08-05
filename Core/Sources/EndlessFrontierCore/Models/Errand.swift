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

    public init(kind: Kind, from: LocalPoint, to: LocalPoint,
                leftAt: Int, arrivesAt: Int, placementID: UUID? = nil) {
        self.kind = kind
        self.from = from
        self.to = to
        self.leftAt = leftAt
        self.arrivesAt = max(leftAt, arrivesAt)
        self.placementID = placementID
    }

    /// Where they are on the way, so the canvas draws somebody crossing the
    /// town rather than somebody blinking from a field to a granary.
    ///
    /// Takes a *continuous* tick, because the canvas runs between ticks and a
    /// walk that advanced once a minute would be a person teleporting slowly.
    public func position(at tick: Double) -> LocalPoint {
        let span = Double(max(1, arrivesAt - leftAt))
        let t = min(1, max(0, (tick - Double(leftAt)) / span))
        return LocalPoint(x: from.x + (to.x - from.x) * t,
                          y: from.y + (to.y - from.y) * t)
    }

    public func position(at tick: Int) -> LocalPoint { position(at: Double(tick)) }

    public func hasArrived(at tick: Int) -> Bool { tick >= arrivesAt }
}
