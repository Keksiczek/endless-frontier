import Foundation

/// A party sent out of the valley entirely, to a ruin or an anomaly somewhere
/// on the world map.
///
/// The valley's own places became journeys with a middle (`SiteEncounter`,
/// `SiteVisitEngine`) — but the *world* map's ruins, dungeons, anomalies and
/// lost cities were still a button. `SiteEngine.interact` took a region id and
/// handed back an outcome in one call: nobody went, nobody was gone, nobody
/// could fail, and a lost city three regions away cost exactly as much as one
/// next door.
///
/// This is the same shape as `POIExpedition`, one scale up: hands leave the
/// colony, they are gone for as long as the country is wide, something happens
/// at the far end, and what comes home is what they managed to take.
public struct RegionExpedition: Codable, Sendable, Equatable, Identifiable {

    public enum Phase: String, Codable, Sendable {
        case outbound, working, returning
    }

    public let id: UUID
    public let regionID: UUID
    /// The settlement that sent them, and that they walk back into.
    public let fromSettlementID: UUID
    public let memberIDs: [UUID]
    public let departedTick: Int
    /// Ticks of travel **each way** — a function of how far the region is.
    public let travelTicks: Int
    public let workTicks: Int
    /// The place itself, once they get there.
    public var site: SiteEncounter?

    public init(id: UUID, regionID: UUID, fromSettlementID: UUID, memberIDs: [UUID],
                departedTick: Int, travelTicks: Int, workTicks: Int,
                site: SiteEncounter? = nil) {
        self.id = id
        self.regionID = regionID
        self.fromSettlementID = fromSettlementID
        self.memberIDs = memberIDs
        self.departedTick = departedTick
        self.travelTicks = max(1, travelTicks)
        self.workTicks = max(1, workTicks)
        self.site = site
    }

    // MARK: - Where they are

    public var totalTicks: Int { travelTicks * 2 + workTicks }

    public func elapsed(at tick: Int) -> Int { max(0, tick - departedTick) }

    public func phase(at tick: Int) -> Phase {
        let gone = elapsed(at: tick)
        if gone < travelTicks { return .outbound }
        if gone < travelTicks + workTicks { return .working }
        return .returning
    }

    /// The exact tick they walk up to the place — when what is in it is laid
    /// out, once.
    public func arrives(at tick: Int) -> Bool { elapsed(at: tick) == travelTicks }

    public func isFinished(at tick: Int) -> Bool { elapsed(at: tick) >= totalTicks }

    /// How far through the whole journey, 0…1 — a bar that only ever fills.
    public func progress(at tick: Int) -> Double {
        guard totalTicks > 0 else { return 1 }
        return min(1, Double(elapsed(at: tick)) / Double(totalTicks))
    }

    public func ticksRemaining(at tick: Int) -> Int {
        max(0, totalTicks - elapsed(at: tick))
    }

    private enum CodingKeys: String, CodingKey {
        case id, regionID, fromSettlementID, memberIDs, departedTick
        case travelTicks, workTicks, site
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        regionID = try c.decode(UUID.self, forKey: .regionID)
        fromSettlementID = try c.decode(UUID.self, forKey: .fromSettlementID)
        memberIDs = try c.decodeIfPresent([UUID].self, forKey: .memberIDs) ?? []
        departedTick = try c.decodeIfPresent(Int.self, forKey: .departedTick) ?? 0
        travelTicks = max(1, try c.decodeIfPresent(Int.self, forKey: .travelTicks) ?? 1)
        workTicks = max(1, try c.decodeIfPresent(Int.self, forKey: .workTicks) ?? 1)
        site = try c.decodeIfPresent(SiteEncounter.self, forKey: .site)
    }
}
