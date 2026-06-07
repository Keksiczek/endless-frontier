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
public struct Caravan: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public let originID: UUID
    public let destinationID: UUID
    public let resource: ResourceType
    public var cargo: Double
    public var guards: [Pawn]
    public var ticksRemaining: Int
    public let totalTicks: Int
    public var status: CaravanStatus

    public init(
        id: UUID = UUID(),
        originID: UUID,
        destinationID: UUID,
        resource: ResourceType,
        cargo: Double,
        guards: [Pawn],
        ticksRemaining: Int,
        totalTicks: Int,
        status: CaravanStatus = .traveling
    ) {
        self.id = id
        self.originID = originID
        self.destinationID = destinationID
        self.resource = resource
        self.cargo = cargo
        self.guards = guards
        self.ticksRemaining = ticksRemaining
        self.totalTicks = totalTicks
        self.status = status
    }

    /// 0…1 fraction of the journey completed, for progress UI.
    public var progress: Double {
        guard totalTicks > 0 else { return 1 }
        return Double(totalTicks - ticksRemaining) / Double(totalTicks)
    }
}
