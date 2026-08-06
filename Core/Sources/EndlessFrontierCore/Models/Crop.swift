import Foundation

/// The harvest as *things*, and the last of the five trades that still turned
/// worker-ticks straight into an abstract pool.
///
/// The wood became `Tree`, the stone became `Rock`, the wild became `Animal` —
/// and farming stayed exactly what it always was: a `.field` `ResourceNode` with
/// an `amount` that a farmer's presence quietly subtracted from, while the food
/// itself appeared in the granary out of `skill × 0.15`. Nobody ever sowed
/// anything, nothing ever ripened, and there was no such thing as a harvest.
///
/// Worse, it was the arithmetic behind the famine. Field nodes regrew at
/// `capacity × 0.0009` a tick and each farmer drew `0.45`, so the equilibrium
/// was **under one farmer**: any real colony stripped its fields to nothing
/// within a season and stayed there, with `gatheringFactors` pinned at
/// `depositFloorFactor` for the next two hundred years. More farmers made it
/// worse, which is why food income stopped scaling with mouths (rule 14).
///
/// A `Crop` is one **plot of tilled ground**. It belongs to a farm building, it
/// carries a crop that grows with the season and the weather, and when it is
/// ripe somebody has to walk out and reap it. What that yields is *grain* — a
/// raw ingredient lying at the plot, hauled in by the same `HaulEngine` that
/// brings the timber home. It is not food yet; see `CookingEngine`.
public enum CropSpecies: String, Codable, Sendable, CaseIterable {

    /// Bread grain — the staple. Slow, and the only thing every meal is happy
    /// to be built on.
    case grain
    /// Roots and tubers. Quicker than grain and hardier in the cold, which is
    /// what makes a northern colony survivable.
    case roots
    /// Greens and pot-herbs. Fast, small, and worth little on their own.
    case greens

    /// The raw ingredient a reaped plot leaves on the ground.
    public var itemID: String {
        switch self {
        case .grain: return "grain"
        case .roots: return "roots"
        case .greens: return "greens"
        }
    }

    /// Units of ingredient a fully ripe plot gives up.
    public var yield: Double {
        switch self {
        case .grain: return 8
        case .roots: return 6
        case .greens: return 4
        }
    }

    /// Growth-ticks from sowing to ripe, at a growth factor of 1.
    ///
    /// A year is `ticksPerYear` (60) and a season a quarter of it, so grain is
    /// a little over one season of good weather and greens are most of one.
    public var ripenTicks: Double {
        switch self {
        case .grain: return 18
        case .roots: return 14
        case .greens: return 10
        }
    }

    /// Worker-ticks to get the crop off a ripe plot. Reaping is *work*: a plot
    /// standing ripe with nobody to cut it is a plot that yields nothing, which
    /// is what makes the number of farmers matter rather than the number of
    /// fields alone.
    public var reapWork: Double {
        switch self {
        case .grain: return 4
        case .roots: return 3
        case .greens: return 2
        }
    }

    /// Below this, in °C, the crop does not grow at all. Roots take a frost;
    /// greens do not.
    public var coldFloor: Double {
        switch self {
        case .roots: return -6
        case .grain: return 0
        case .greens: return 3
        }
    }

    public var displayName: LocalizedText {
        switch self {
        case .grain: return LocalizedText(values: [.en: "Grain", .cs: "Obilí"])
        case .roots: return LocalizedText(values: [.en: "Roots", .cs: "Okopaniny"])
        case .greens: return LocalizedText(values: [.en: "Greens", .cs: "Zelenina"])
        }
    }

    /// What a farm sows in its Nth plot. Grain first and mostly — a colony eats
    /// bread — with roots and greens filling out the rotation, so a settlement
    /// with a single farm still has more than one thing on the shelf and its
    /// cooks have something better than gruel to make.
    public static func sown(inPlot index: Int) -> CropSpecies {
        switch index % 4 {
        case 0, 1: return .grain
        case 2: return .roots
        default: return .greens
        }
    }
}

/// One plot of tilled ground with something growing on it.
///
/// The plot is permanent — it belongs to a farm and stays tilled — while the
/// crop on it cycles: sown, ripening, reaped, sown again. That is why `growth`
/// resets rather than the plot being destroyed and rebuilt, and it is the
/// reason a `Crop` can keep a stable `id` derived from its farm (rule 2).
public struct Crop: Codable, Sendable, Equatable, Identifiable {
    public let id: Int
    public let species: CropSpecies
    public let position: LocalPoint
    /// The building whose ground this is. A farm that falls down takes its
    /// plots with it.
    public let farmID: UUID
    /// Ripeness, 0…1. Advanced by the season and the weather, never by the
    /// clock alone — a winter plot genuinely does not grow, which is the whole
    /// reason a granary is worth building.
    public var growth: Double
    /// Reaping done so far, 0…1. Banked in the plot exactly as axe-work is
    /// banked in a `Tree`, so a harvest interrupted by a raid is not lost.
    public var reaped: Double

    public init(id: Int, species: CropSpecies, position: LocalPoint, farmID: UUID,
                growth: Double = 0, reaped: Double = 0) {
        self.id = id
        self.species = species
        self.position = position
        self.farmID = farmID
        self.growth = growth
        self.reaped = reaped
    }

    public var isRipe: Bool { growth >= 1 }

    /// What is standing on it right now, in ingredient units. A plot cut early
    /// gives proportionally less, which is what stops a starving colony from
    /// simply reaping everything green.
    public var standing: Double { species.yield * min(1, growth) }
}
