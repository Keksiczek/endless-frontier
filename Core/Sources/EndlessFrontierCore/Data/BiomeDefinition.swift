import Foundation

/// A data-defined biome. Loaded from `biomes.json`. When a region of this
/// biome is revealed, `worldFlag` (if any) is set so events can gate on it
/// (e.g. `biome:plains_present`).
public struct BiomeDefinition: Codable, Sendable, Identifiable, Equatable {
    public let id: String
    public let name: LocalizedText
    public let baseHazard: Int
    public let resourceAffinity: Resources
    public let worldFlag: String?
    /// Relative chance this biome is the one the player wakes up in. Zero (the
    /// default) means never. The homeland used to be hardcoded to plains, so
    /// the map a player stares at for the whole game was the same country every
    /// single run — this is the knob that fixes it, in data rather than code.
    public let homelandWeight: Double
    /// Degrees this country runs above or below the ordinary seasonal swing.
    ///
    /// The biome had no temperature at all, so a tundra valley in January was
    /// exactly as cold as a coastal one and the word "tundra" meant nothing to
    /// anybody's body. This is what makes choosing where to live a decision:
    /// see `Climate`.
    public let temperatureShift: Double

    /// Where in the world this country belongs — the **land** it wants, not
    /// how often it turns up.
    ///
    /// The world map used to roll each hex's biome independently out of
    /// `biomeWeights`, so it came out as salt and pepper: a desert beside a
    /// tundra beside a coast, no ranges, no continents, nothing that reads as
    /// geography. That is the whole of "the tiles don't look like a map".
    ///
    /// A niche says what ground a biome sits on instead — how high, how wet,
    /// how warm — and `MapGenerator` samples those three as *smooth fields*
    /// across the map. Mountains then form ranges because height does; deserts
    /// gather where it is dry and hot; a coast is where the land runs out. The
    /// map is still generated one hex at a time from `(mapSeed, coord)` with no
    /// global pass, because a noise field is a pure function of position.
    ///
    /// Nil means a biome with no opinion, which is placed by weight as before —
    /// so adding a biome to `biomes.json` without a niche still works.
    public let niche: BiomeNiche?

    public init(
        id: String,
        name: LocalizedText,
        baseHazard: Int = 0,
        resourceAffinity: Resources = Resources(),
        worldFlag: String? = nil,
        homelandWeight: Double = 0,
        temperatureShift: Double = 0,
        niche: BiomeNiche? = nil
    ) {
        self.id = id
        self.name = name
        self.baseHazard = baseHazard
        self.resourceAffinity = resourceAffinity
        self.worldFlag = worldFlag
        self.homelandWeight = homelandWeight
        self.temperatureShift = temperatureShift
        self.niche = niche
    }

    private enum CodingKeys: String, CodingKey {
        case id, name
        case baseHazard = "base_hazard"
        case resourceAffinity = "resource_affinity"
        case worldFlag = "world_flag"
        case homelandWeight = "homeland_weight"
        case temperatureShift = "temperature_shift"
        case niche
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(LocalizedText.self, forKey: .name)
        baseHazard = try c.decodeIfPresent(Int.self, forKey: .baseHazard) ?? 0
        resourceAffinity = try c.decodeIfPresent(Resources.self, forKey: .resourceAffinity) ?? Resources()
        worldFlag = try c.decodeIfPresent(String.self, forKey: .worldFlag)
        homelandWeight = try c.decodeIfPresent(Double.self, forKey: .homelandWeight) ?? 0
        // A biome written before the land had weather is middling country.
        temperatureShift = try c.decodeIfPresent(Double.self, forKey: .temperatureShift) ?? 0
        // A biome written before the world had geography has no opinion about
        // where it belongs, and is placed by weight as it always was.
        niche = try c.decodeIfPresent(BiomeNiche.self, forKey: .niche)
    }

    /// The weather in this country, as an *average* year — see `Climate.mapSeed`.
    public var climate: Climate { Climate(shift: temperatureShift) }
}

/// The ground a biome wants: how high, how wet, how warm, each on a −1…1
/// scale. Distance from the middle of the niche is what picks a biome, so the
/// ranges may overlap and every point on the map still has an answer.
public struct BiomeNiche: Codable, Sendable, Equatable {
    public var elevation: Double
    public var moisture: Double
    public var warmth: Double
    /// How strongly this country insists. A biome that wants a *narrow* band —
    /// mountains want height and do not care much about rain — raises this so
    /// it wins its own ground rather than being crowded out by a biome that is
    /// vaguely close on all three.
    public var pull: Double

    public init(elevation: Double = 0, moisture: Double = 0,
                warmth: Double = 0, pull: Double = 1) {
        self.elevation = elevation
        self.moisture = moisture
        self.warmth = warmth
        self.pull = pull
    }

    private enum CodingKeys: String, CodingKey {
        case elevation, moisture, warmth, pull
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        elevation = try c.decodeIfPresent(Double.self, forKey: .elevation) ?? 0
        moisture = try c.decodeIfPresent(Double.self, forKey: .moisture) ?? 0
        warmth = try c.decodeIfPresent(Double.self, forKey: .warmth) ?? 0
        pull = try c.decodeIfPresent(Double.self, forKey: .pull) ?? 1
    }

    /// How badly this country wants the ground at `(e, m, w)`. Bigger is
    /// better; `pull` is what lets a decided biome beat a vague one.
    public func fit(elevation e: Double, moisture m: Double, warmth w: Double) -> Double {
        let de = e - elevation, dm = m - moisture, dw = w - warmth
        // Height counts double: a mountain range is the one feature that has to
        // survive being wet or dry, hot or cold.
        return pull / (0.15 + 2 * de * de + dm * dm + dw * dw)
    }
}
