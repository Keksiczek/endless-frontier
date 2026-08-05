import Foundation

/// What the weather does to a person.
///
/// The wild has had comfort bands since animals got bodies — a deer suffers a
/// hard winter, a bear suffers high summer — and colonists had nothing at all.
/// A colony on the tundra was exactly as comfortable in January as one on the
/// plains in June, which made winter, the season the whole calendar is shaped
/// around, a change of palette.
///
/// Warmth is a *comfort*, not a temperature: it is what the season is doing to
/// them, less what their clothes, their roof and their hearth give back. Let it
/// run out and they take frostbite, which costs health until they get warm
/// again. Everything here is pure and deterministic.
public enum ComfortEngine {

    /// The band a clothed person is comfortable in, in °C. Narrower than any
    /// animal's, because a person without a coat is a poorly insulated animal.
    public static let comfortLow: Double = 2
    public static let comfortHigh: Double = 30

    /// Warmth lost per degree the day is below the band, and per degree above.
    public static let coldPerDegree = 3.6
    public static let heatPerDegree = 3.2
    /// How fast comfort moves toward what the day is offering.
    public static let adjustRate = 0.06
    /// Below this, they are cold enough to be hurt by it.
    public static let freezingBelow: Double = 18
    /// Health lost per tick at zero warmth, scaling with how far down they are.
    public static let exposureDamage = 0.45
    /// What a roof over their head is worth against the cold, in warmth points.
    public static let shelterWarmth: Double = 26
    /// …and a fire in the settlement, per hearth-bearing building.
    public static let hearthWarmth: Double = 7
    public static let maxHearthWarmth: Double = 21
    /// What one piece of worn kit keeps out.
    public static let clothingWarmth: Double = 11

    /// How warm a settlement's shelter and fires make it, before the person's
    /// own clothes. Computed once per settlement per tick rather than per pawn.
    public static func shelter(_ settlement: Settlement, registry: GameDataRegistry) -> Double {
        var hearths = 0.0
        for instance in settlement.buildings {
            guard let def = registry.building(instance.definitionID) else { continue }
            // Anything that houses people or works metal has a fire in it.
            if def.housing > 0 || def.pollution > 0 {
                hearths += Double(instance.count)
            }
        }
        return min(maxHearthWarmth, hearths * hearthWarmth)
    }

    /// Why a colonist is as warm as they are — the same four terms `target`
    /// adds up, kept apart so the inspector can say them out loud.
    ///
    /// The whole of the second half of "the temperature is cosmetic": the only
    /// reading anywhere was a "Warmth" bar, so a player could not connect the
    /// season, the valley, the roof and the coat to the number. Every one of
    /// these was already computed and none of them was ever shown.
    public struct Reckoning: Sendable, Equatable {
        /// What the thermometer says outside, in °C.
        public let outside: Double
        /// What being that far out of the comfort band costs, in warmth points
        /// — negative.
        public let weather: Double
        /// …and what is given back.
        public let roof: Double
        public let clothes: Double
        public let fires: Double
        /// Where all that leaves them, 0…100.
        public let warmth: Double
    }

    /// The warmth a colonist settles at, given the season, the country they
    /// are in, and what they have.
    ///
    /// A hundred is comfortable. Winter on its own is well under zero, so
    /// surviving one is a matter of having built something and put a coat on —
    /// which is the point, and on a tundra it is the point twice over.
    public static func target(
        season: Season, housed: Bool, clothing: Int, shelter: Double,
        climate: Climate = .temperate
    ) -> Double {
        reckon(season: season, housed: housed, clothing: clothing,
               shelter: shelter, climate: climate).warmth
    }

    /// The same sum, itemised.
    public static func reckon(
        season: Season, housed: Bool, clothing: Int, shelter: Double,
        climate: Climate = .temperate
    ) -> Reckoning {
        let outside = climate.temperature(season)
        // How far outside the band the day is, in degrees.
        let deficit = outside < comfortLow ? comfortLow - outside : 0
        let excess = outside > comfortHigh ? outside - comfortHigh : 0
        // `coldPerDegree` has to be steep enough that a hard winter actually
        // reaches past `freezingBelow` for someone with nothing. At 2.6 it did
        // not: winter is −22, so the deficit is 24 degrees and a bare colonist
        // settled at 37 — comfortably above the threshold meant to hurt them,
        // and the whole mechanic was a dead letter. This is the recurring bug
        // shape in this codebase (a threshold beyond the reach of the rate
        // meant to cross it), and `winterIsReachable` pins it.
        let weather = -(deficit * coldPerDegree + excess * heatPerDegree)
        // Only the cold is something you can put a wall or a coat against.
        let roof = deficit > 0 && housed ? shelterWarmth : 0
        let clothes = deficit > 0 ? Double(clothing) * clothingWarmth : 0
        let fires = deficit > 0 ? shelter : 0
        return Reckoning(
            outside: outside, weather: weather, roof: roof,
            clothes: clothes, fires: fires,
            warmth: min(100, max(0, 100 + weather + roof + clothes + fires)))
    }

    /// Moves one colonist's warmth toward what the day is offering, and takes
    /// the cost of being out in it. Returns the pawn.
    public static func advanceOneTick(
        _ pawn: Pawn, season: Season, shelter: Double, climate: Climate = .temperate
    ) -> Pawn {
        var p = pawn
        // Anything worn counts: armour is a coat when it is cold enough.
        let clothing = p.equipment.count
        let want = target(season: season, housed: p.homeID != nil,
                          clothing: clothing, shelter: shelter, climate: climate)
        p.needs.warmth += (want - p.needs.warmth) * adjustRate
        p.needs.warmth = min(100, max(0, p.needs.warmth))

        if p.needs.warmth < freezingBelow {
            let severity = (freezingBelow - p.needs.warmth) / freezingBelow
            p.health = max(0, p.health - exposureDamage * severity)
        }
        return p
    }

    /// Whether this colonist is presently suffering from the cold — what the
    /// inspector shows and what the journal would report.
    public static func isFreezing(_ pawn: Pawn) -> Bool {
        pawn.needs.warmth < freezingBelow
    }
}

/// One reason a colonist feels the way they do.
public struct MoodFactor: Sendable, Equatable, Identifiable {
    public let id: String
    public let label: LocalizedText
    /// Mood points, signed.
    public let amount: Double

    public init(id: String, label: LocalizedText, amount: Double) {
        self.id = id
        self.label = label
        self.amount = amount
    }
}

/// Why a colonist feels the way they do.
///
/// Mood was a single number computed inline in the tick loop, so the game could
/// tell you someone was miserable and never why. This recomputes the same terms
/// as a list, purely for reading — the tick loop is untouched and stays the one
/// place mood is actually set.
public enum MoodLedger {

    public static func factors(
        for pawn: Pawn, registry: GameDataRegistry
    ) -> [MoodFactor] {
        var factors: [MoodFactor] = []

        func need(_ id: String, _ value: Double, _ en: String, _ cs: String) {
            // Each need pulls mood toward itself; what the player wants to see
            // is how far from contented it is.
            let delta = (value - 70) / 4
            guard abs(delta) >= 0.5 else { return }
            factors.append(MoodFactor(id: id,
                                      label: LocalizedText(values: [.en: en, .cs: cs]),
                                      amount: delta))
        }
        need("hunger", pawn.needs.hunger,
             pawn.needs.hunger < 70 ? "Hungry" : "Well fed",
             pawn.needs.hunger < 70 ? "Hlad" : "Najedený")
        need("rest", pawn.needs.rest,
             pawn.needs.rest < 70 ? "Tired" : "Rested",
             pawn.needs.rest < 70 ? "Únava" : "Odpočatý")
        need("recreation", pawn.needs.recreation,
             pawn.needs.recreation < 70 ? "No time to himself" : "Time to himself",
             pawn.needs.recreation < 70 ? "Málo odpočinku" : "Má čas na sebe")
        need("warmth", pawn.needs.warmth,
             pawn.needs.warmth < 70 ? "Cold" : "Warm enough",
             pawn.needs.warmth < 70 ? "Zima" : "V teple")

        if pawn.homeID == nil {
            factors.append(MoodFactor(
                id: "roofless",
                label: LocalizedText(values: [.en: "Sleeping rough",
                                              .cs: "Spí pod širým nebem"]),
                amount: -HouseholdEngine.roughSleepMood))
        }
        if pawn.trait != .none, pawn.trait.moodModifier != 0 {
            factors.append(MoodFactor(
                id: "trait", label: pawn.trait.displayName,
                amount: pawn.trait.moodModifier))
        }
        let gear = ItemEngine.moodBonus(pawn, registry: registry)
        if abs(gear) >= 0.5 {
            factors.append(MoodFactor(
                id: "equipment",
                label: LocalizedText(values: [.en: "What they carry",
                                              .cs: "Výbava"]),
                amount: gear))
        }
        return factors.sorted { abs($0.amount) > abs($1.amount) }
    }
}
