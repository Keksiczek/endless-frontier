import Foundation

/// What happened to a caravan on its most recent travel tick — surfaced to the
/// UI so a journey reads as a small story rather than an invisible transfer.
public enum CaravanStatus: String, Codable, Sendable, Equatable {
    case traveling        // an uneventful leg
    case skirmished       // an ambush was beaten off by the escort
    case raided           // an ambush got through: cargo and/or guards were lost
}

/// A batch shipment in transit between two settlements, escorted by real
/// colonists. Unlike a standing `TradeRoute` (a frictionless per-tick trickle),
/// a caravan carries a lump of cargo over several ticks, can be ambushed on the
/// road, and delivers its surviving guards to the destination — so trade,
/// combat, and colonist migration meet in one object.
/// **What is in the cart.**
///
/// A caravan could carry one of the five abstract resources and nothing else,
/// which meant a realm could ship *food* and *materials* between its own towns
/// and could never ship a single **thing**. Keks, on a colony whose whole
/// industry was starved of timber: *"taky můžeme posílat dřevo z jiných osad."*
/// He is right, and it was not possible — `wood`, `timber_bundle`, `charcoal`,
/// ore and brick all live in `Settlement.stockpile`, which no cart had ever
/// heard of.
///
/// An enum rather than a second field beside `resource`, because "a resource
/// *or* a good" is one fact about a cart and two fields for one fact is how a
/// caravan ends up carrying both and neither (rule 8).
public enum CaravanCargo: Codable, Sendable, Equatable {
    /// One of the five pools — food, materials, and in principle the rest.
    case resource(ResourceType)
    /// A good on the shelf, by item id: timber, charcoal, ore, brick.
    case goods(String)

    /// What it is called, for a journal line or a card.
    public var label: String {
        switch self {
        case let .resource(resource): return resource.rawValue
        case let .goods(item): return item
        }
    }

    /// The resource pool this cargo lands in, if it is one. Nil for goods.
    public var resource: ResourceType? {
        switch self {
        case let .resource(resource): return resource
        case .goods: return nil
        }
    }

    /// The item id this cargo is, if it is a thing. Nil for a resource.
    public var itemID: String? {
        switch self {
        case .resource: return nil
        case let .goods(item): return item
        }
    }

    private enum CodingKeys: String, CodingKey { case resource, goods }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let item = try c.decodeIfPresent(String.self, forKey: .goods) {
            self = .goods(item)
            return
        }
        self = .resource(try c.decode(ResourceType.self, forKey: .resource))
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .resource(resource): try c.encode(resource, forKey: .resource)
        case let .goods(item): try c.encode(item, forKey: .goods)
        }
    }
}

public struct Caravan: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public let originID: UUID
    public let destinationID: UUID
    /// What is in the cart. Decoded resiliently: a save written before carts
    /// could carry goods has a bare `resource` at this level, and that is a
    /// `.resource` cargo.
    public let load: CaravanCargo
    public var cargo: Double
    public var guards: [Pawn]
    public var ticksRemaining: Int
    public let totalTicks: Int
    public var status: CaravanStatus
    /// The ambush on the road, beat by beat, if one happened. An attack out in
    /// the country is not the settlement's battle — it belongs to the caravan,
    /// and travels home with it.
    public var lastBattle: BattleLog?

    public init(
        id: UUID = UUID(),
        originID: UUID,
        destinationID: UUID,
        load: CaravanCargo,
        cargo: Double,
        guards: [Pawn],
        ticksRemaining: Int,
        totalTicks: Int,
        status: CaravanStatus = .traveling
    ) {
        self.id = id
        self.originID = originID
        self.destinationID = destinationID
        self.load = load
        self.cargo = cargo
        self.guards = guards
        self.ticksRemaining = ticksRemaining
        self.totalTicks = totalTicks
        self.status = status
    }

    /// The convenience every existing caller wants: a cart of one resource.
    public init(
        id: UUID = UUID(), originID: UUID, destinationID: UUID,
        resource: ResourceType, cargo: Double, guards: [Pawn],
        ticksRemaining: Int, totalTicks: Int, status: CaravanStatus = .traveling
    ) {
        self.init(id: id, originID: originID, destinationID: destinationID,
                  load: .resource(resource), cargo: cargo, guards: guards,
                  ticksRemaining: ticksRemaining, totalTicks: totalTicks,
                  status: status)
    }

    /// What the cart is carrying, as the resource pool it lands in — `nil`
    /// when it is carrying goods.
    ///
    /// Kept for the three drawing call sites that want a resource's symbol and
    /// name; a cart of timber answers `nil` and they say what it really is.
    public var resource: ResourceType? { load.resource }

    /// 0…1 fraction of the journey completed, for progress UI.
    public var progress: Double {
        guard totalTicks > 0 else { return 1 }
        return Double(totalTicks - ticksRemaining) / Double(totalTicks)
    }

    private enum CodingKeys: String, CodingKey {
        case id, originID, destinationID, load, cargo, guards
        case ticksRemaining, totalTicks, status, lastBattle
        /// What a cart's cargo was called before it could be a thing.
        case resource
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        originID = try c.decode(UUID.self, forKey: .originID)
        destinationID = try c.decode(UUID.self, forKey: .destinationID)
        // A cart on the road in an older save carries a resource, and says so
        // in the old spelling. Read either, so a shipment in flight when the
        // player updated does not arrive carrying nothing.
        if let stated = try c.decodeIfPresent(CaravanCargo.self, forKey: .load) {
            load = stated
        } else {
            load = .resource(try c.decodeIfPresent(ResourceType.self, forKey: .resource) ?? .food)
        }
        cargo = try c.decode(Double.self, forKey: .cargo)
        guards = try c.decodeIfPresent([Pawn].self, forKey: .guards) ?? []
        ticksRemaining = try c.decode(Int.self, forKey: .ticksRemaining)
        totalTicks = try c.decode(Int.self, forKey: .totalTicks)
        status = try c.decodeIfPresent(CaravanStatus.self, forKey: .status) ?? .traveling
        lastBattle = try c.decodeIfPresent(BattleLog.self, forKey: .lastBattle)
    }

    /// Written in the new spelling only — `resource` is a key this reads and
    /// never writes, so a save round-trips forward and the legacy key dies out
    /// on its own.
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(originID, forKey: .originID)
        try c.encode(destinationID, forKey: .destinationID)
        try c.encode(load, forKey: .load)
        try c.encode(cargo, forKey: .cargo)
        try c.encode(guards, forKey: .guards)
        try c.encode(ticksRemaining, forKey: .ticksRemaining)
        try c.encode(totalTicks, forKey: .totalTicks)
        try c.encode(status, forKey: .status)
        try c.encodeIfPresent(lastBattle, forKey: .lastBattle)
    }
}
