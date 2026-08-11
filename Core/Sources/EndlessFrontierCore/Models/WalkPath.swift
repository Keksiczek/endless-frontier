import Foundation

/// Somebody crossing the colony between two ticks.
///
/// A tick is two real minutes (`realSecondsPerTick`), so anything that stores
/// only *where a walker is now* and advances it once a tick is a person
/// standing still for two minutes and then jumping — which is exactly what
/// `Errand` was built to stop happening ("a walk that advanced once a minute
/// would be a person teleporting slowly"). This is that shape, lifted out so
/// the errand and the hauler share one answer instead of two.
///
/// The walk is decided **once, when it begins**: where from, where to, when
/// they left, when they arrive, and the corners they go round. Nothing is
/// recomputed per tick (rule 4), and the canvas gets a continuous position by
/// asking with a fractional tick.
public struct WalkPath: Codable, Sendable, Equatable {
    /// Where they set off from.
    public let from: LocalPoint
    /// …and what they are walking to.
    public let to: LocalPoint
    public let leftAt: Int
    /// The tick they get there. Distance made into time, which is the point:
    /// a far granary costs real minutes of nobody working.
    public let arrivesAt: Int
    /// The corners they go round on the way, when the straight line would have
    /// taken them through somebody's house. Empty is the common case and means
    /// "walk at it". Worked out once by `ColonyRoute` when the walk begins.
    public let via: [LocalPoint]

    public init(from: LocalPoint, to: LocalPoint, leftAt: Int, arrivesAt: Int,
                via: [LocalPoint] = []) {
        self.from = from
        self.to = to
        self.leftAt = leftAt
        self.arrivesAt = max(leftAt, arrivesAt)
        self.via = via
    }

    /// Where they are on the way, so the canvas draws somebody crossing the
    /// town rather than somebody blinking from a field to a granary.
    ///
    /// Takes a *continuous* tick, because the canvas runs between ticks.
    public func position(at tick: Double) -> LocalPoint {
        let span = Double(max(1, arrivesAt - leftAt))
        let t = min(1, max(0, (tick - Double(leftAt)) / span))
        guard !via.isEmpty else {
            return LocalPoint(x: from.x + (to.x - from.x) * t,
                              y: from.y + (to.y - from.y) * t)
        }
        // Spread the walk over the legs by their length, so somebody rounding a
        // long barn does not sprint one side and dawdle the other.
        let legs = zip([from] + via, via + [to]).map { SiegeField.distance($0, $1) }
        let total = legs.reduce(0, +)
        guard total > 0 else { return to }
        var travelled = t * total
        var here = from
        for (index, leg) in legs.enumerated() {
            let next = index < via.count ? via[index] : to
            if travelled <= leg {
                let f = leg > 0 ? travelled / leg : 1
                return LocalPoint(x: here.x + (next.x - here.x) * f,
                                  y: here.y + (next.y - here.y) * f)
            }
            travelled -= leg
            here = next
        }
        return to
    }

    public func position(at tick: Int) -> LocalPoint { position(at: Double(tick)) }

    public func hasArrived(at tick: Int) -> Bool { tick >= arrivesAt }

    /// Which way they are facing at `tick` — the heading of the leg they are
    /// on, so somebody who turns a corner turns with it.
    public func heading(at tick: Double) -> LocalPoint {
        let ahead = position(at: tick + 0.05)
        let here = position(at: tick)
        return LocalPoint(x: ahead.x - here.x, y: ahead.y - here.y)
    }

    /// A walk that takes however long the ground under it is, at `pace` per
    /// tick — distance made into time, the same bargain `Errand` strikes.
    ///
    /// `via` is asked of `ColonyRoute` **here**, once, rather than every tick
    /// the walker is under way.
    public static func across(
        from: LocalPoint, to: LocalPoint, leavingAt tick: Int, pace: Double,
        in colony: ColonyMap?, occupancy: ColonyRoute.Occupancy? = nil
    ) -> WalkPath {
        let via = ColonyRoute.corners(from: from, to: to, in: colony, occupancy: occupancy)
        let span = ColonyRoute.length(from: from, through: via, to: to)
        // At least one tick: a walk that arrives on the tick it left is a
        // teleport, and `position(at:)` would divide by nothing.
        let ticks = max(1, Int((span / max(0.0001, pace)).rounded(.up)))
        return WalkPath(from: from, to: to, leftAt: tick, arrivesAt: tick + ticks, via: via)
    }
}
