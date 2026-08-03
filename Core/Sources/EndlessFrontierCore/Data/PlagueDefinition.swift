import Foundation

/// A sickness that can go through a colony.
///
/// Content, like everything else (CLAUDE.md rule 2): adding a new one is adding
/// a line to `plagues.json`, not writing Swift.
///
/// The reason this exists at all: measured over two hundred years, **nothing
/// killed anybody but old age**. Every threat the game had scaled with the
/// colony's own strength — a warband of a hundred and forty is nothing to four
/// hundred people, and that is *correct*, so the answer could never be a bigger
/// warband. A sickness is the threat that runs the other way: the bigger and
/// more crowded the town, the worse it is, and no number of spears helps.
public struct PlagueDefinition: Codable, Sendable, Identifiable, Equatable {
    public let id: String
    public let name: LocalizedText
    public let description: LocalizedText
    /// The earliest age this one appears in.
    public let eraFrom: Era
    /// How readily it passes from one person to another, per exposure.
    public let contagion: Double
    /// How hard it rides whoever has it, 0…1.
    public let virulence: Double
    /// Seasons it likes. A fever runs through a winter house; a flux comes off
    /// warm water.
    public let winterBias: Double
    public let summerBias: Double

    public init(id: String, name: LocalizedText, description: LocalizedText = LocalizedText(""),
                eraFrom: Era = .earlySettlement, contagion: Double = 0.06,
                virulence: Double = 0.5, winterBias: Double = 1, summerBias: Double = 1) {
        self.id = id
        self.name = name
        self.description = description
        self.eraFrom = eraFrom
        self.contagion = contagion
        self.virulence = virulence
        self.winterBias = winterBias
        self.summerBias = summerBias
    }

    /// How much more likely this one is to take hold in a given season.
    public func seasonalBias(_ season: Season) -> Double {
        switch season {
        case .winter: return winterBias
        case .summer: return summerBias
        default: return 1
        }
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, description, contagion, virulence
        case eraFrom = "era_from"
        case winterBias = "winter_bias"
        case summerBias = "summer_bias"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(LocalizedText.self, forKey: .name)
        description = try c.decodeIfPresent(LocalizedText.self, forKey: .description)
            ?? LocalizedText("")
        eraFrom = try c.decodeIfPresent(Era.self, forKey: .eraFrom) ?? .earlySettlement
        contagion = try c.decodeIfPresent(Double.self, forKey: .contagion) ?? 0.06
        virulence = try c.decodeIfPresent(Double.self, forKey: .virulence) ?? 0.5
        winterBias = try c.decodeIfPresent(Double.self, forKey: .winterBias) ?? 1
        summerBias = try c.decodeIfPresent(Double.self, forKey: .summerBias) ?? 1
    }
}

/// A sickness actually running through a settlement, right now.
public struct Outbreak: Codable, Sendable, Equatable {
    public let id: UUID
    /// Which sickness, by definition id.
    public let plagueID: String
    public let startedTick: Int
    /// Who has it. The *course* of it lives on each pawn's own body as an
    /// `Ailment(.sickness)` — this is only the register of who is on the list,
    /// so the engine does not have to scan every body every tick.
    public var infected: Set<UUID>
    /// Everyone it has already been through, so a colony builds immunity and an
    /// outbreak genuinely burns out instead of going round for ever.
    public var recovered: Set<UUID>
    public var deaths: Int
    /// Whether the colony has shut itself in. Cuts the spread hard and costs
    /// the work of everybody staying home.
    public var quarantined: Bool

    public init(id: UUID, plagueID: String, startedTick: Int,
                infected: Set<UUID> = [], recovered: Set<UUID> = [],
                deaths: Int = 0, quarantined: Bool = false) {
        self.id = id
        self.plagueID = plagueID
        self.startedTick = startedTick
        self.infected = infected
        self.recovered = recovered
        self.deaths = deaths
        self.quarantined = quarantined
    }

    /// Nobody left carrying it.
    public var isOver: Bool { infected.isEmpty }

    private enum CodingKeys: String, CodingKey {
        case id, plagueID, startedTick, infected, recovered, deaths, quarantined
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        plagueID = try c.decode(String.self, forKey: .plagueID)
        startedTick = try c.decodeIfPresent(Int.self, forKey: .startedTick) ?? 0
        infected = try c.decodeIfPresent(Set<UUID>.self, forKey: .infected) ?? []
        recovered = try c.decodeIfPresent(Set<UUID>.self, forKey: .recovered) ?? []
        deaths = try c.decodeIfPresent(Int.self, forKey: .deaths) ?? 0
        quarantined = try c.decodeIfPresent(Bool.self, forKey: .quarantined) ?? false
    }
}
