import Foundation

/// **Where the water runs through a region, and which way.**
///
/// The world map had no rivers at all, which is why `docs/ROADS.md` §9 could
/// not have bridges: a bridge is a road crossing water, and there was no water
/// on the map for a road to cross.
///
/// Held per region rather than per edge, and derived — like `RegionFeature` —
/// from the same elevation and moisture fields the generator already uses, so
/// the water can never disagree with the country it runs through. `from` and
/// `to` make it a *course* rather than a puddle: the map can draw a line
/// through the hex, and the road engine can tell a way that follows the bank
/// from one that has to get across.
public struct RiverCourse: Codable, Sendable, Equatable {
    /// The neighbour the water comes down from. `nil` at a spring.
    public let from: HexCoord?
    /// The neighbour it runs on to. `nil` where it ends — a basin, a lake, the
    /// sea, or ground too dry to carry it any further.
    public let to: HexCoord?

    public init(from: HexCoord?, to: HexCoord?) {
        self.from = from
        self.to = to
    }

    /// Whether the course itself joins this hex to that one — the two hexes a
    /// boatman would call consecutive.
    public func runsTo(_ coord: HexCoord) -> Bool {
        from == coord || to == coord
    }

    /// A spring: water starts here and nothing feeds it.
    public var isSource: Bool { from == nil && to != nil }
    /// A mouth: water arrives and goes no further.
    public var isMouth: Bool { to == nil && from != nil }
}
