import Foundation

/// A heap of goods lying where the work happened, waiting for somebody to
/// carry it home.
///
/// Felled timber and broken stone used to arrive in the ledger the instant the
/// axe or the pick finished — a tree came down half a valley away and the
/// storehouse simply knew. It is the last place where work was a number rather
/// than a thing done at a place: the logger you watch chopping walked back
/// empty-handed and the wood teleported.
///
/// A pile is that wood, on the ground, at the stump. Somebody has to pick it up
/// and carry it, and until they do it is out there — visible, claimable, and
/// not yet yours.
public struct HaulPile: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    /// Where it lies.
    public var position: LocalPoint
    /// The concrete good it is made of — `wood`, `rough_stone`, `iron_ore`,
    /// `clay`. Piles carry *things*, which is why they feed the crafting tree
    /// and not the abstract materials pool.
    public let itemID: String
    /// How many whole units are in it.
    public var amount: Int
    /// The colonist on their way to it, if one is. A claim keeps two haulers
    /// from walking to the same heap and one of them arriving to nothing.
    public var claimedBy: UUID?
    /// The tick it was dropped — how the oldest pile is fetched first, so a
    /// far corner does not keep its timber for ever.
    public let droppedTick: Int

    public init(id: UUID, position: LocalPoint, itemID: String, amount: Int,
                claimedBy: UUID? = nil, droppedTick: Int = 0) {
        self.id = id
        self.position = position
        self.itemID = itemID
        self.amount = max(0, amount)
        self.claimedBy = claimedBy
        self.droppedTick = droppedTick
    }
}

/// What a colonist is carrying right now.
///
/// Presentation reads it to draw a bundle on their back; the engine reads it to
/// know what to credit when they reach the store. A load exists only between
/// picking a pile up and putting it down.
public struct HaulLoad: Codable, Sendable, Equatable {
    public let itemID: String
    public var amount: Int
    /// Where it is going — the store's spot on the map.
    public var destination: LocalPoint

    public init(itemID: String, amount: Int, destination: LocalPoint) {
        self.itemID = itemID
        self.amount = max(0, amount)
        self.destination = destination
    }
}
