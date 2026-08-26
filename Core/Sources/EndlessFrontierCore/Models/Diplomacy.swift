import Foundation

/// Where a neighbouring people stands with you, read off the relations score.
public enum DiplomaticStanding: String, Codable, Sendable, CaseIterable {
    case allied
    case friendly
    case neutral
    case tense
    case war

    public init(score: Double) {
        switch score {
        case 60...: self = .allied
        case 25..<60: self = .friendly
        case -25..<25: self = .neutral
        case -60..<(-25): self = .tense
        default: self = .war
        }
    }
}

/// **A war that has been declared and is still on.**
///
/// War used to be a verb with no noun behind it: `standing < -30` rolled a raid
/// each year, `Tribe.wars` counted how many had happened, and a "fragile peace"
/// clause quietly set the number back to −5. Nothing in the world could be
/// asked *whether the colony was at war* — so nothing showed it. Keks: *"války
/// mi neprojdou propojené nikde, je nevidím, jen v diplomacii."* He was right,
/// and the reason is that there was nothing to see: the only thing a war left
/// behind was an integer that went up.
///
/// A war is a **state with a beginning, a tally and an end**, so the world map
/// can mark it, the town's status strip can carry it, the chronicle can record
/// it, and the storyteller can lean on it. Rule 8: the thing every surface asks
/// about lives in one place.
public struct WarState: Codable, Sendable, Equatable {
    /// The tick it was declared on — a war has a length, and the length is
    /// what makes it a war rather than a bad year.
    public var declaredTick: Int
    /// Who declared it. A war the colony started is a different story from one
    /// it was handed, and the chronicle should not confuse them.
    public var declaredByColony: Bool
    /// How many times they have come over the ground since.
    public var raids: Int
    /// …and how many of those the wall turned back.
    public var repelled: Int
    /// Colonists who did not get up.
    public var colonistsLost: Int
    /// What the attempts have cost *them*, in the strength they spent.
    public var strengthSpent: Double
    /// Food carried out of the granary by raiders who got through.
    public var lootLost: Double

    // MARK: - What we did to them
    //
    // **A war used to be a thing that happened to you.** Every field above
    // counts a raid *they* made: how many came, how many the wall turned back,
    // what it cost us. There was no counterpart, because there was no verb —
    // `declareWar` set a flag and then the player waited to be attacked, which
    // is a war with one party in it. Keks: *"nevím, jak udělat nájezd na
    // město."* He could not, and it was not hidden. See `TribeWarEngine`.

    /// Parties we have sent over the ground at them.
    public var sorties: Int = 0
    /// …and how many of those broke into the place rather than being turned
    /// back at its edge.
    public var sortiesWon: Int = 0
    /// What our marches have cost *them*, in the strength we put down.
    public var theirStrengthSpent: Double = 0
    /// What we carried home out of their stores.
    public var plunder: Double = 0

    public init(
        declaredTick: Int,
        declaredByColony: Bool = false,
        raids: Int = 0,
        repelled: Int = 0,
        colonistsLost: Int = 0,
        strengthSpent: Double = 0,
        lootLost: Double = 0,
        sorties: Int = 0,
        sortiesWon: Int = 0,
        theirStrengthSpent: Double = 0,
        plunder: Double = 0
    ) {
        self.declaredTick = declaredTick
        self.declaredByColony = declaredByColony
        self.raids = raids
        self.repelled = repelled
        self.colonistsLost = colonistsLost
        self.strengthSpent = strengthSpent
        self.lootLost = lootLost
        self.sorties = sorties
        self.sortiesWon = sortiesWon
        self.theirStrengthSpent = theirStrengthSpent
        self.plunder = plunder
    }

    // MARK: - Codable
    //
    // Hand-written so a war saved before the colony could march decodes to one
    // it has not marched in, rather than failing the whole save (rule 3).

    private enum CodingKeys: String, CodingKey {
        case declaredTick, declaredByColony, raids, repelled, colonistsLost
        case strengthSpent, lootLost
        case sorties, sortiesWon, theirStrengthSpent, plunder
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        declaredTick = try c.decode(Int.self, forKey: .declaredTick)
        declaredByColony = try c.decodeIfPresent(Bool.self, forKey: .declaredByColony) ?? false
        raids = try c.decodeIfPresent(Int.self, forKey: .raids) ?? 0
        repelled = try c.decodeIfPresent(Int.self, forKey: .repelled) ?? 0
        colonistsLost = try c.decodeIfPresent(Int.self, forKey: .colonistsLost) ?? 0
        strengthSpent = try c.decodeIfPresent(Double.self, forKey: .strengthSpent) ?? 0
        lootLost = try c.decodeIfPresent(Double.self, forKey: .lootLost) ?? 0
        sorties = try c.decodeIfPresent(Int.self, forKey: .sorties) ?? 0
        sortiesWon = try c.decodeIfPresent(Int.self, forKey: .sortiesWon) ?? 0
        theirStrengthSpent = try c.decodeIfPresent(Double.self, forKey: .theirStrengthSpent) ?? 0
        plunder = try c.decodeIfPresent(Double.self, forKey: .plunder) ?? 0
    }

    /// How long it has been going, in whole years.
    public func years(now tick: Int, ticksPerYear: Int) -> Int {
        max(0, (tick - declaredTick) / max(1, ticksPerYear))
    }
}

/// A neighbouring people — not a settlement you command, but one that grew from
/// your own: colonists who walked out and founded their own hearth. They trade,
/// they marry, they raid, and they take in your malcontents.
///
/// Deliberately lighter than `Settlement`: diplomacy only needs their numbers,
/// their character, their faith and their spears.
public struct Tribe: Codable, Sendable, Identifiable, Equatable {
    public let id: UUID
    public var name: String
    public var regionID: UUID?
    public let foundedTick: Int
    /// Why they left — chronicle flavour.
    public let originStory: LocalizedText

    public var population: Double
    /// The average disposition of their people — how alike you are decides how
    /// well you get on.
    public var genes: Genes
    public var cultID: String?
    public var defense: Double
    /// Their granary — what a raid can carry off, and what a caravan can bring.
    public var stores: Double

    /// Relations with the player's civilisation, −100…100.
    public var standing: Double
    /// Old wounds that keep relations from healing.
    public var grudge: Double
    /// Whether the leaders' houses have been joined by marriage.
    /// **What we pay them every year to leave us alone**, in materials.
    ///
    /// Zero means no arrangement. Unlike an embassy — which is a colonist and
    /// therefore already recorded on the colonist — tribute is a standing
    /// charge with no other home, so it lives here.
    ///
    /// The verb pointing outward (`demandTribute`) has existed since the
    /// beginning; the one pointing in had no counterpart, so a colony that
    /// could not fight had no way to buy peace except a gift — a single payment
    /// against a grievance that keeps growing. This is the verb a losing player
    /// needs, and it is what makes losing interesting rather than terminal.
    ///
    /// Optional in the decoder, so saves written before it decode to nobody
    /// paying anybody (rule 3).
    public var tributePerYear: Double = 0
    public var married: Bool
    /// How many wars this people has fought with you, over all time.
    public var wars: Int
    /// **The one they are fighting now, if they are fighting one.**
    ///
    /// Nil is peace. Everything that wants to know whether there is a war on
    /// asks this rather than reading `standing` and guessing — which is what
    /// let the panel say TENSE (a pill drawn at −60) while a people was
    /// raiding the colony every year (a raid rolled at −30).
    public var war: WarState?
    public var defections: Int
    /// A people who were in the valley long before you came — seeded at world
    /// creation, unlike the tribes that secede out of your own settlement.
    public var isNative: Bool
    /// Whether you have actually met them. Native peoples start hidden and are
    /// found by expeditions; everything diplomatic waits for first contact.
    public var discovered: Bool

    /// Where they stand with you.
    ///
    /// A declared war outranks the score: the two used to disagree — the pill
    /// was drawn at −60 and the raid rolled at −30 — so a people could be
    /// burning your fields under a label that said "tense" (rule 35, the same
    /// number in two places).
    public var status: DiplomaticStanding {
        war != nil ? .war : DiplomaticStanding(score: standing)
    }

    /// Whether there is a war on with this people.
    public var atWar: Bool { war != nil }

    public init(
        id: UUID,
        name: String,
        regionID: UUID? = nil,
        foundedTick: Int,
        originStory: LocalizedText,
        population: Double,
        genes: Genes,
        cultID: String? = nil,
        defense: Double = 10,
        stores: Double = 60,
        standing: Double = 0,
        grudge: Double = 0,
        tributePerYear: Double = 0,
        married: Bool = false,
        wars: Int = 0,
        war: WarState? = nil,
        defections: Int = 0,
        isNative: Bool = false,
        discovered: Bool = true
    ) {
        self.id = id
        self.name = name
        self.regionID = regionID
        self.foundedTick = foundedTick
        self.originStory = originStory
        self.population = population
        self.genes = genes
        self.cultID = cultID
        self.defense = defense
        self.stores = stores
        self.standing = standing
        self.grudge = grudge
        self.tributePerYear = tributePerYear
        self.married = married
        self.wars = wars
        self.war = war
        self.defections = defections
        self.isNative = isNative
        self.discovered = discovered
    }

    // MARK: - Codable (resilient: native peoples arrived after the first V2 cut)

    private enum CodingKeys: String, CodingKey {
        case id, name, regionID, foundedTick, originStory, population, genes
        case cultID, defense, stores, standing, grudge, married, wars, defections
        case isNative, discovered, tributePerYear, war
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        regionID = try c.decodeIfPresent(UUID.self, forKey: .regionID)
        foundedTick = try c.decode(Int.self, forKey: .foundedTick)
        originStory = try c.decode(LocalizedText.self, forKey: .originStory)
        population = try c.decode(Double.self, forKey: .population)
        genes = try c.decode(Genes.self, forKey: .genes)
        cultID = try c.decodeIfPresent(String.self, forKey: .cultID)
        defense = try c.decode(Double.self, forKey: .defense)
        stores = try c.decode(Double.self, forKey: .stores)
        standing = try c.decode(Double.self, forKey: .standing)
        grudge = try c.decode(Double.self, forKey: .grudge)
        married = try c.decode(Bool.self, forKey: .married)
        wars = try c.decode(Int.self, forKey: .wars)
        defections = try c.decode(Int.self, forKey: .defections)
        // Tribes saved before natives existed are emergent — and already met.
        isNative = try c.decodeIfPresent(Bool.self, forKey: .isNative) ?? false
        discovered = try c.decodeIfPresent(Bool.self, forKey: .discovered) ?? true
        // Saves from before anybody could buy peace: nobody was paying.
        tributePerYear = try c.decodeIfPresent(Double.self, forKey: .tributePerYear) ?? 0
        // …and from before a war was a thing you could be in: nobody is at war,
        // whatever their standing. The next year's roll declares one properly,
        // with a date and a journal line, rather than a save waking up mid-war
        // with no beginning to point at (rule 3).
        war = try c.decodeIfPresent(WarState.self, forKey: .war)
    }
}
