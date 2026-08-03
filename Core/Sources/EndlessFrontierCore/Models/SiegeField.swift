import Foundation

/// The ground a raid is fought over, in local-map coordinates.
///
/// This used to live in the app, as `SettlementBattle.Field`, because the only
/// thing that needed to know where anybody stood was the drawing: the fight
/// itself was arithmetic on one strength number and a round index, and the
/// canvas invented a plausible arrangement of people to hang it on.
///
/// It is in the Core now because the fight has positions of its own. A raider
/// walks in from the edge of the map, a colonist walks out to meet them, and
/// contact is **proximity** rather than "step ≥ 4". Once that is true the
/// geometry is simulation, not decoration — CLAUDE.md rule 8: two numbers that
/// must agree live in one place, and "where the line forms" is now one of them.
///
/// The precedent is `Pawn.currentJob.position` and `HaulEngine.haulPosition`:
/// Core-owned positions the renderer *reads*. Rule 5 is untouched — the canvas
/// still never writes any of this.
public struct SiegeField: Sendable, Equatable {

    /// Off the edge of the map, where the attackers come from.
    public static let originReach = 0.48
    /// The line the colony holds: just outside the palisade, where the ground
    /// is still open. The old canvas drew the front here and it looked right;
    /// it is the simulation's number now.
    public static let musterReach = 0.30
    /// The palisade itself, at the edge of the built town. Inside it a raider
    /// is among the stores and a colonist is behind cover.
    public static let wallReach = 0.26
    /// Past this the wall is behind you and counts for nothing.
    public static let openReach = 0.40
    /// Where the watch turns out from — in among the houses, so they are seen
    /// running to the line rather than already standing on it.
    public static let formUpReach = 0.20
    /// How much room one body takes in a rank.
    public static let rankSpacing = 0.019

    /// What is being defended.
    public let heart: LocalPoint
    /// The unit vector pointing out along the bearing the attack came in on.
    public let axisX: Double
    public let axisY: Double

    public init(approach: Double, heart: LocalPoint = SettlementGeometry.heart) {
        self.heart = heart
        axisX = cos(approach)
        axisY = sin(approach)
    }

    /// A point `reach` out from the heart along the line of the attack.
    public func out(_ reach: Double) -> LocalPoint {
        LocalPoint(x: heart.x + axisX * reach, y: heart.y + axisY * reach)
    }

    public var origin: LocalPoint { out(Self.originReach) }
    public var muster: LocalPoint { out(Self.musterReach) }
    public var wall: LocalPoint { out(Self.wallReach) }

    /// A place in a rank of `count` bodies abreast, `reach` out from the heart.
    ///
    /// Fanned into a shallow crescent — the ends of a line sag back toward the
    /// town — so a rank reads as people rather than as a fence.
    public func post(index: Int, of count: Int, reach: Double) -> LocalPoint {
        let offset = count <= 1 ? 0 : (Double(index) / Double(count - 1) - 0.5)
        let width = Self.rankSpacing * Double(max(1, count - 1))
        let sag = abs(offset) * 0.014
        let px = -axisY, py = axisX
        let along = reach - sag
        return LocalPoint(x: heart.x + px * offset * width + axisX * along,
                          y: heart.y + py * offset * width + axisY * along)
    }

    /// Where a defender holds the line…
    public func defenderPost(index: Int, of count: Int) -> LocalPoint {
        post(index: index, of: count, reach: Self.musterReach)
    }

    /// …where the watch turns out from…
    public func musterPost(index: Int, of count: Int) -> LocalPoint {
        post(index: index, of: count, reach: Self.formUpReach)
    }

    /// …and where a raider first sets foot on the map.
    public func attackerPost(index: Int, of count: Int) -> LocalPoint {
        post(index: index, of: count, reach: Self.originReach)
    }

    /// How much of the wall stands between somebody at `p` and the enemy —
    /// 1 among the buildings, nothing out at the muster line.
    ///
    /// **Cover is a place you stand.** It used to be a number attached to an
    /// order (`Posture.cover`), which is why pressing them could be tuned to
    /// cost the wall without anybody actually leaving it. Now pressing costs
    /// the wall because it takes you out from behind it, and giving ground
    /// keeps the wall because it puts you back inside. That is the pivot in one
    /// function.
    public func cover(at p: LocalPoint) -> Double {
        let d = Self.distance(heart, p)
        guard d > Self.wallReach else { return 1 }
        let span = Self.openReach - Self.wallReach
        guard span > 0 else { return 0 }
        return max(0, min(1, 1 - (d - Self.wallReach) / span))
    }

    /// Whether somebody at `p` is in among the buildings — for a raider, that
    /// is standing in the stores; for a colonist, it is being indoors.
    public func isInside(_ p: LocalPoint) -> Bool {
        Self.distance(heart, p) <= Self.wallReach
    }

    public func reachFromHeart(_ p: LocalPoint) -> Double { Self.distance(heart, p) }

    public static func distance(_ a: LocalPoint, _ b: LocalPoint) -> Double {
        let dx = a.x - b.x, dy = a.y - b.y
        return (dx * dx + dy * dy).squareRoot()
    }

    /// A stride of at most `pace` from `a` toward `b`, stopping on it rather
    /// than overshooting — which is what makes two people closing on each other
    /// meet instead of oscillating around the gap between them.
    public static func stride(from a: LocalPoint, toward b: LocalPoint, pace: Double) -> LocalPoint {
        let dx = b.x - a.x, dy = b.y - a.y
        let d = (dx * dx + dy * dy).squareRoot()
        guard d > pace, d > 0 else { return b }
        return LocalPoint(x: a.x + dx / d * pace, y: a.y + dy / d * pace)
    }
}
