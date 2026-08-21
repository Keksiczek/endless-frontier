import Foundation

/// One event a chapter remembers — carried by name, in every language the game
/// speaks, so a snapshot handed to a narrator needs nothing else to read it.
public struct ChapterEvent: Codable, Sendable, Equatable {
    public let templateID: String
    public let name: LocalizedText
    public let type: EventType
    public let year: Int

    public init(templateID: String, name: LocalizedText, type: EventType, year: Int) {
        self.templateID = templateID
        self.name = name
        self.type = type
        self.year = year
    }
}

/// How far one disposition moved across a chapter.
public struct GeneDrift: Codable, Sendable, Equatable {
    /// The stable key — `industry`, `fertility`, `sociability`, `courage`.
    public let trait: String
    public let from: Double
    public let to: Double

    public init(trait: String, from: Double, to: Double) {
        self.trait = trait
        self.from = from
        self.to = to
    }

    public var shift: Double { to - from }
}

/// A stretch of history, compacted into the **only** thing Layer 3 is ever
/// handed.
///
/// It is deliberately small (the `docs/architecture/LAYERS.md` budget is about
/// five hundred tokens of JSON), deliberately `Codable`, and deliberately
/// carries no `WorldState`, no entity ids a narrator could act on, and nothing
/// mutable. A narrator gets facts and gives back prose; that is the whole
/// contract, and it is what keeps an optional layer optional.
public struct ChapterSnapshot: Codable, Sendable, Equatable, Identifiable {
    public let firstYear: Int
    public let lastYear: Int
    public let era: Era
    public let settlementName: String

    public let populationFirst: Int
    public let populationLast: Int
    public let populationPeak: Int
    public let peakYear: Int

    /// Deaths **within the span**, by cause. `Settlement.deathTallies` runs
    /// cumulatively, so these are the running totals differenced — a chapter
    /// that says "nineteen were buried" means nineteen in those years, not
    /// nineteen since the founding.
    public let deaths: [String: Int]

    public let moraleMean: Double
    public let giniLast: Double
    public let faithLast: Double
    /// The year the stores were thinnest, and what was in them.
    public let leanestYear: Int
    public let leanestFood: Double

    public let drifts: [GeneDrift]
    public let events: [ChapterEvent]

    public var id: Int { firstYear }
    public var years: Int { lastYear - firstYear }
    public var deathCount: Int { deaths.values.reduce(0, +) }

    /// The disposition that moved furthest, if any of them moved at all.
    public var largestDrift: GeneDrift? {
        drifts.max { abs($0.shift) < abs($1.shift) }
    }

    public init(
        firstYear: Int, lastYear: Int, era: Era, settlementName: String,
        populationFirst: Int, populationLast: Int, populationPeak: Int, peakYear: Int,
        deaths: [String: Int], moraleMean: Double, giniLast: Double, faithLast: Double,
        leanestYear: Int, leanestFood: Double,
        drifts: [GeneDrift], events: [ChapterEvent]
    ) {
        self.firstYear = firstYear
        self.lastYear = lastYear
        self.era = era
        self.settlementName = settlementName
        self.populationFirst = populationFirst
        self.populationLast = populationLast
        self.populationPeak = populationPeak
        self.peakYear = peakYear
        self.deaths = deaths
        self.moraleMean = moraleMean
        self.giniLast = giniLast
        self.faithLast = faithLast
        self.leanestYear = leanestYear
        self.leanestFood = leanestFood
        self.drifts = drifts
        self.events = events
    }
}
