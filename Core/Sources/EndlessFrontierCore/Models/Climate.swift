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

    /// The world this weather belongs to, and the moment in it.
    ///
    /// Nil-ish defaults (0, 0) mean **the ordinary run of things** — the
    /// average year, with no weather on top. That is the right answer for the
    /// questions that are about a *climate* rather than about a day:
    /// `CropSpecies.sown(inPlot:climate:)` and `thrives(in:)` are decisions a
    /// farm makes once about the country it stands in, and they must not be
    /// re-made every time a warm week comes along. Everything that asks what it
    /// is like *outside right now* goes through `Climate.of`, which carries the
    /// tick and therefore carries the weather.
    public let mapSeed: UInt64
    public let tick: Int
    /// The calendar this weather is reckoned against.
    ///
    /// Carried rather than passed, so `temperature(_:)` keeps the signature its
    /// ten callers already use and the length of a year is stated in exactly
    /// one place — `WorldConfig`, by way of `Climate.of` (rule 8). The 60 here
    /// is only ever reached by a climate that has no world behind it, and such
    /// a climate has no weather either.
    public let ticksPerYear: Int

    public init(shift: Double = 0, mapSeed: UInt64 = 0, tick: Int = 0,
                ticksPerYear: Int = 60) {
        self.shift = shift
        self.mapSeed = mapSeed
        self.tick = tick
        self.ticksPerYear = max(1, ticksPerYear)
    }

    /// The middling country the game used to assume everywhere was.
    public static let temperate = Climate()

    /// The weather where a settlement actually stands, on the day it is.
    ///
    /// One lookup, used by everything that asks — the pawns' comfort, the
    /// beasts' comfort, the crops and the status strip — so a colonist can
    /// never be freezing in a valley where the deer are comfortable, and a bad
    /// year is a bad year for all of them at once.
    public static func of(
        _ settlement: Settlement, in state: WorldState, registry: GameDataRegistry
    ) -> Climate {
        guard let regionID = settlement.regionID,
              let region = state.regions.first(where: { $0.id == regionID }),
              let biome = registry.biome(region.biomeID)
        else {
            return Climate(mapSeed: state.mapSeed, tick: state.tick,
                           ticksPerYear: registry.config.ticksPerYear)
        }
        return Climate(shift: biome.temperatureShift, mapSeed: state.mapSeed,
                       tick: state.tick, ticksPerYear: registry.config.ticksPerYear)
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

    // MARK: - Weather

    /// How far a *year* can run from the ordinary, in °C. A hard winter and a
    /// kind one are both this far out and no further.
    public static let yearSwing: Double = 4.5
    /// …and how far a spell inside a year can, on top of it.
    public static let spellSwing: Double = 5.0
    /// How long a spell of weather holds, in ticks. A tick is about six days,
    /// so this is a month or so of the same sky rather than a new one every
    /// time anybody looks up.
    public static let spellTicks = 5
    /// Once in a while a year is not merely hard but *remembered*, and this is
    /// how much further out that goes. The tail is what makes a granary worth
    /// its materials — an even spread never produces the winter people talk
    /// about, it produces a slightly colder average.
    public static let hardYearSwing: Double = 7.0
    /// How often such a year comes. Roughly one in nine.
    public static let hardYearOdds: Double = 0.11

    /// The day's temperature in this country, in °C.
    ///
    /// `Climate.base(season) + shift` was the whole of it, so every spring in a
    /// colony's life was exactly 11°. Consistent, and not weather. Three things
    /// are laid over it now, and all three come off `(mapSeed, tick)` so the
    /// same world has the same weather every time it is replayed — a save
    /// reloaded mid-winter comes back to the same winter (rule 2).
    ///
    /// - **The year**, which is milder or harder than usual and stays that way
    ///   from one spring to the next, so a bad year is a *year*.
    /// - **The spell**, a month or so of the same sky, interpolated between its
    ///   neighbours rather than switched — weather that teleports every tick
    ///   reads as a broken thermometer, not as weather.
    /// - **The hard year**, rarely, which is the one anybody remembers.
    ///
    /// Everything downstream already reads this: `FarmEngine.growthStep`
    /// measures the distance outside a crop's range at *both* ends,
    /// `ComfortEngine` decides who is freezing, `AnimalEngine` decides which
    /// beasts suffer, and the status strip says it out loud. So a hard year is
    /// a bad harvest, cold colonists and a thin wild all at once, without any
    /// of them being told about each other.
    ///
    /// Cheap on purpose: this is called per pawn per tick, so it is a handful
    /// of integer mixes and no allocation (rule 4).
    public func temperature(_ season: Season) -> Double {
        Self.base(season) + shift + weather(season)
    }

    /// What the sky is doing, over and above the season and the country.
    public func weather(_ season: Season) -> Double {
        // A climate with no world behind it is the ordinary run of things —
        // see `mapSeed`. This is also the fast path for every sowing decision.
        guard mapSeed != 0 || tick != 0 else { return 0 }
        let year = Int(floor(Double(tick) / Double(ticksPerYear)))

        // The year, held for its whole length.
        var swing = Self.wobble(Self.mix(mapSeed, UInt64(bitPattern: Int64(year)), 0x59_45_41_52))
            * Self.yearSwing
        // …and once in a while, the one people talk about. Signed toward the
        // season, so a hard summer bakes and a hard winter bites.
        let roll = (Self.wobble(Self.mix(mapSeed, UInt64(bitPattern: Int64(year)), 0x48_41_52_44)) + 1) / 2
        if roll < Self.hardYearOdds {
            swing += (season == .summer ? 1 : -1) * Self.hardYearSwing
        }

        // The spell, eased between its two anchors so the sky changes rather
        // than jumps.
        let spell = Double(tick) / Double(Self.spellTicks)
        let index = Int(floor(spell))
        let t = spell - Double(index)
        let a = Self.wobble(Self.mix(mapSeed, UInt64(bitPattern: Int64(index)), 0x53_50_45_4C))
        let b = Self.wobble(Self.mix(mapSeed, UInt64(bitPattern: Int64(index + 1)), 0x53_50_45_4C))
        let ease = t * t * (3 - 2 * t)
        swing += (a + (b - a) * ease) * Self.spellSwing
        return swing
    }

    /// How this year is running against the ordinary, for the status strip.
    ///
    /// Read off the *year* alone, not the spell: "a hard year" is a thing the
    /// colony says in autumn about the whole of it, and a cold fortnight is
    /// not one.
    public func yearLabel() -> LocalizedText? {
        guard mapSeed != 0 || tick != 0 else { return nil }
        let year = Int(floor(Double(tick) / Double(ticksPerYear)))
        let roll = (Self.wobble(Self.mix(mapSeed, UInt64(bitPattern: Int64(year)), 0x48_41_52_44)) + 1) / 2
        let swing = Self.wobble(Self.mix(mapSeed, UInt64(bitPattern: Int64(year)), 0x59_45_41_52))
        if roll < Self.hardYearOdds {
            return LocalizedText(values: [.en: "a year to remember", .cs: "rok, na který se nezapomíná"])
        }
        switch swing {
        case ..<(-0.55): return LocalizedText(values: [.en: "a hard year", .cs: "zlý rok"])
        case 0.55...: return LocalizedText(values: [.en: "a kind year", .cs: "vlídný rok"])
        default: return nil
        }
    }

    // MARK: - Deterministic value noise

    /// A stable −1…1 out of a seed. SplitMix64's finaliser, which is cheap,
    /// well-distributed and — unlike `hashValue` — the same on every run and
    /// every machine (rule 1).
    static func wobble(_ seed: UInt64) -> Double {
        var z = seed &+ 0x9E37_79B9_7F4A_7C15
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        z = z ^ (z >> 31)
        // `z >> 11` is a **53**-bit value, so the divisor is 2^53. Dividing by
        // 2^52 — which is what a first cut did — yields 0…2 and then −1…3, so
        // every swing here silently ran to three times the number written next
        // to it and a "4.5° year" could be 13.5° out. Caught by the sky jumping
        // 5.6° in a tick against a 5° spell.
        return Double(z >> 11) / Double(1 << 53) * 2 - 1
    }

    static func mix(_ a: UInt64, _ b: UInt64, _ salt: UInt64) -> UInt64 {
        var h = a &* 0x9E37_79B9_7F4A_7C15
        h = (h ^ b) &* 0xD1B5_4A32_D192_ED03
        return h ^ salt
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
