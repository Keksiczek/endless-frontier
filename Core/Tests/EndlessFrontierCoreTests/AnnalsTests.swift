import Testing
import Foundation
@testable import EndlessFrontierCore

/// The chronicle's chapters and the narrator seam above them.
@Suite("The annals")
struct AnnalsTests {

    /// A row of history, with only the fields a test cares about set.
    static func record(
        year: Int, population: Int = 40, era: Era = .earlySettlement,
        food: Double = 100, gini: Double = 0.2, morale: Double = 60,
        faith: Double = 0, industry: Double = 0.5, courage: Double = 0.5,
        deaths: [String: Int] = [:]
    ) -> WorldRecord {
        WorldRecord(
            year: year, population: population, food: food, materials: 100,
            morale: morale, stability: 60, gini: gini, faith: faith,
            industry: industry, fertility: 0.5, sociability: 0.5, courage: courage,
            deaths: deaths, era: era)
    }

    // MARK: - Where the history is cut

    @Test("A long age is cut into chapters a reader can hold")
    func longAgeIsCut() {
        let rows = (0..<60).map { Self.record(year: $0) }
        let cuts = Annals.cuts(rows)
        #expect(cuts.count >= 2)
        for cut in cuts {
            #expect(rows[cut.upperBound].year - rows[cut.lowerBound].year
                    <= Annals.maxChapterYears)
        }
    }

    @Test("Chapters are disjoint and cover the whole history")
    func chaptersTile() {
        let rows = (0..<60).map { Self.record(year: $0) }
        let cuts = Annals.cuts(rows)
        #expect(cuts.first?.lowerBound == 0)
        #expect(cuts.last?.upperBound == rows.count - 1)
        for (a, b) in zip(cuts, cuts.dropFirst()) {
            #expect(b.lowerBound == a.upperBound + 1)
        }
    }

    @Test("An era that turns closes the chapter before it")
    func eraTurnCuts() {
        var rows = (0..<20).map { Self.record(year: $0) }
        rows += (20..<30).map { Self.record(year: $0, era: .ancient) }
        let cuts = Annals.cuts(rows)
        #expect(cuts.count == 2)
        #expect(rows[cuts[0].upperBound].era == .earlySettlement)
        #expect(rows[cuts[1].lowerBound].era == .ancient)
    }

    @Test("A one-year tail is folded into the chapter before it, not left alone")
    func shortTailFolds() {
        // Twenty-six rows: the first chapter closes at 25, leaving one row over.
        let rows = (0...26).map { Self.record(year: $0) }
        let cuts = Annals.cuts(rows)
        #expect(cuts.allSatisfy { $0.count >= 2 })
        #expect(cuts.last?.upperBound == rows.count - 1)
    }

    // MARK: - What a chapter says

    @Test("A chapter counts its own dead, not everybody who ever died")
    func deathsAreDifferenced() throws {
        let registry = try GameDataRegistry.bundled()
        // The tallies run cumulatively. A chapter opening on a colony that has
        // already buried thirty must not claim those thirty as its own.
        var rows = (0...25).map { Self.record(year: $0, deaths: ["old_age": 30]) }
        rows += (26...50).map { Self.record(year: $0, deaths: ["old_age": 44]) }
        let state = Self.world(rows, registry)
        let chapters = Annals.chapters(state, registry: registry)
        #expect(chapters.count >= 2)
        #expect(chapters[0].deaths["old_age"] == 30)
        #expect(chapters[1].deaths["old_age"] == 14)
    }

    @Test("A chapter remembers the peak the two ends do not show")
    func peakIsKept() throws {
        let registry = try GameDataRegistry.bundled()
        var rows = [Self.record(year: 0, population: 40)]
        rows += (1...12).map { Self.record(year: $0, population: 90) }
        rows += (13...24).map { Self.record(year: $0, population: 42) }
        let state = Self.world(rows, registry)
        let chapters = Annals.chapters(state, registry: registry)
        #expect(chapters.first?.populationPeak == 90)
    }

    // MARK: - The narrator

    @Test("The stub always answers, in both languages")
    func stubAlwaysAnswers() async throws {
        let registry = try GameDataRegistry.bundled()
        let rows = (0...30).map {
            Self.record(year: $0, population: 40 + $0, deaths: ["old_age": $0])
        }
        let state = Self.world(rows, registry)
        let chapters = Annals.chapters(state, registry: registry)
        let narrator = StubNarrator(mapSeed: 99)
        #expect(narrator.isAvailable)
        for chapter in chapters {
            for language in GameLanguage.allCases {
                let text = await narrator.narrate(chapter, language: language)
                #expect(text?.isEmpty == false)
            }
        }
    }

    @Test("The same history reads the same way twice")
    func stubIsDeterministic() throws {
        let registry = try GameDataRegistry.bundled()
        let rows = (0...30).map { Self.record(year: $0, population: 40 + $0) }
        let state = Self.world(rows, registry)
        let chapters = Annals.chapters(state, registry: registry)
        let narrator = StubNarrator(mapSeed: 7)
        for chapter in chapters {
            #expect(narrator.annal(chapter, language: .cs)
                    == narrator.annal(chapter, language: .cs))
        }
    }

    @Test("A chapter that lost people does not read as one that grew")
    func riseAndFallReadDifferently() {
        let rise = Self.chapter(from: 20, to: 90)
        let fall = Self.chapter(from: 90, to: 20)
        let narrator = StubNarrator(mapSeed: 1)
        for language in GameLanguage.allCases {
            #expect(narrator.annal(rise, language: language)
                    != narrator.annal(fall, language: language))
        }
    }

    @Test("A drift too small to matter is not reported as a change")
    func tinyDriftIsSilent() throws {
        let registry = try GameDataRegistry.bundled()
        var rows = (0...25).map { Self.record(year: $0, industry: 0.500) }
        rows[25] = Self.record(year: 25, industry: 0.505)
        let state = Self.world(rows, registry)
        let chapters = Annals.chapters(state, registry: registry)
        let text = StubNarrator(mapSeed: 3).annal(chapters[0], language: .en)
        #expect(!text.contains("diligence"))
    }

    // MARK: - Fixtures

    static func world(_ rows: [WorldRecord], _ registry: GameDataRegistry) -> WorldState {
        var state = GameWorldFactory.newGame(registry: registry, seed: 1)
        state.records = rows
        return state
    }

    static func chapter(from first: Int, to last: Int) -> ChapterSnapshot {
        ChapterSnapshot(
            firstYear: 10, lastYear: 34, era: .earlySettlement, settlementName: "Test",
            populationFirst: first, populationLast: last,
            populationPeak: max(first, last), peakYear: 30,
            deaths: ["old_age": 5], moraleMean: 60, giniLast: 0.2, faithLast: 0,
            leanestYear: 20, leanestFood: 100,
            drifts: [], events: [])
    }
}
