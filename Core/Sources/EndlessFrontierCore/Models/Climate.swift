import Foundation

/// What the weather is actually like **here**.
///
/// The world had a temperature and it was a four-case switch on `Season`, so a
/// tundra valley in January was exactly as cold as a coastal one. The map said
/// "tundra", the body said "same as everywhere", and the two did not agree —
/// which is the whole of "the temperature is there but it does not match and is
/// rather cosmetic". A biome that does not change the weather is a colour.
///
/// One climate, read by **both** people (`ComfortEngine`) and beasts
/// (`AnimalEngine`). Rule 8: the temperature outside is one number, so it lives
/// in one place. A second switch statement somewhere else is how a colonist
/// comes to be freezing in a valley where the deer are comfortable.
public struct Climate: Sendable, Equatable {

    /// Degrees added to the season's base temperature. Negative in the cold
    /// places, positive in the hot ones.
    public let shift: Double

    public init(shift: Double = 0) {
        self.shift = shift
    }

    /// The middling country the game used to assume everywhere was.
    public static let temperate = Climate()

    /// The weather where a settlement actually stands.
    ///
    /// One lookup, used by everything that asks — the pawns' comfort, the
    /// beasts' comfort and the status strip — so a colonist can never be
    /// freezing in a valley where the deer are comfortable.
    public static func of(
        _ settlement: Settlement, in state: WorldState, registry: GameDataRegistry
    ) -> Climate {
        guard let regionID = settlement.regionID,
              let region = state.regions.first(where: { $0.id == regionID }),
              let biome = registry.biome(region.biomeID)
        else { return .temperate }
        return biome.climate
    }

    /// The bare seasonal swing, before the land has its say.
    ///
    /// These have to actually *reach past* the comfort bands they are measured
    /// against or frostbite and heatstroke are dead letters — a first pass had
    /// winter at −12 against a hardiest floor of −15, so nothing on the map
    /// could ever be cold. The spread is chosen so the soft-skinned (boar,
    /// deer, fox) suffer a hard winter while the hare and the big predators
    /// shrug it off, and the thick-coated (bear, wolf) are the ones that suffer
    /// high summer. `bandsAreReachable` pins it.
    public static func base(_ season: Season) -> Double {
        switch season {
        case .spring: return 11
        case .summer: return 31
        case .autumn: return 9
        case .winter: return -22
        }
    }

    /// The day's temperature in this country, in °C.
    public func temperature(_ season: Season) -> Double {
        Self.base(season) + shift
    }

    /// How this land reads on a thermometer against the ordinary run of
    /// things — what the status strip says next to the season.
    public var label: LocalizedText? {
        switch shift {
        case ..<(-7): return LocalizedText(values: [.en: "bitter", .cs: "krutá zima"])
        case ..<(-2): return LocalizedText(values: [.en: "raw", .cs: "syrovo"])
        case 7...: return LocalizedText(values: [.en: "scorching", .cs: "výheň"])
        case 2...: return LocalizedText(values: [.en: "close", .cs: "dusno"])
        default: return nil
        }
    }
}
