import Foundation

/// One thing the colony owns that carries a body or a load.
///
/// A mount and a cart are the same record. The only difference is `animalID`:
/// a mount is backed by a beast in `Settlement.tamed`, so it eats, can be hurt
/// and can die; a cart is not, so it wears out instead. Everything else — what
/// it carries, how fast, where it may go — is the same question asked of the
/// same fields, which is the whole reason `ConveyanceDefinition` exists.
///
/// See `docs/MOUNTS_AND_VEHICLES.md`.
public struct Conveyance: Codable, Sendable, Equatable, Identifiable {
    /// Stable across a save, and derived from the settlement and the tick it
    /// was made on — never a fresh `UUID()` per run, which is rule 3 and has
    /// bitten this repository once already.
    public let id: UUID
    /// The `conveyances.json` id this is one of.
    public let definitionID: String
    /// The beast, for a mount. Nil for anything with wheels.
    public var animalID: UUID?
    /// Who is on it or driving it. Nil when it is standing in the yard.
    public var riderID: UUID?
    /// How sound it is, 0…1 — the same scale buildings wear on. A mount reads
    /// its animal's health instead; this is what a cart has in place of one.
    public var condition: Double
    /// What it is carrying home.
    public var cargo: [HaulLoad]
    public let madeAtTick: Int

    public init(
        id: UUID,
        definitionID: String,
        animalID: UUID? = nil,
        riderID: UUID? = nil,
        condition: Double = 1,
        cargo: [HaulLoad] = [],
        madeAtTick: Int = 0
    ) {
        self.id = id
        self.definitionID = definitionID
        self.animalID = animalID
        self.riderID = riderID
        self.condition = min(1, max(0, condition))
        self.cargo = cargo
        self.madeAtTick = madeAtTick
    }

    /// Whether this is a beast rather than a machine.
    public var isMount: Bool { animalID != nil }

    // Resilient decode: every field but the first two postdates some save.
    private enum CodingKeys: String, CodingKey {
        case id, definitionID, animalID, riderID, condition, cargo, madeAtTick
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        definitionID = try c.decode(String.self, forKey: .definitionID)
        animalID = try c.decodeIfPresent(UUID.self, forKey: .animalID)
        riderID = try c.decodeIfPresent(UUID.self, forKey: .riderID)
        condition = min(1, max(0, try c.decodeIfPresent(Double.self, forKey: .condition) ?? 1))
        cargo = try c.decodeIfPresent([HaulLoad].self, forKey: .cargo) ?? []
        madeAtTick = try c.decodeIfPresent(Int.self, forKey: .madeAtTick) ?? 0
    }
}
