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
            // The bound is the cut plus one fold: a stub is folded back into the
            // chapter before it, which adds its own span (under
            // `minChapterYears`) plus the year between them, and never
            // cascades.
            #expect(rows[cut.upperBound].year - rows[cut.lowerBound].year
                    <= Annals.maxChapterYears + Annals.minChapterYears)
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

    @Test("A stub is folded into the chapter before it, not left as a paragraph")
    func shortTailFolds() {
        // Twenty-seven rows: the first chapter closes at 25, leaving a tail far
        // too short to be an age of anything.
        let rows = (0...26).map { Self.record(year: $0) }
        let cuts = Annals.cuts(rows)
        #expect(cuts.count == 1)
        #expect(cuts.last?.upperBound == rows.count - 1)
    }

    @Test("An era that turns just after a cut does not leave a four-year age")
    func stubAtEraTurnFolds() {
        var rows = (0...29).map { Self.record(year: $0) }
        rows += (30...55).map { Self.record(year: $0, era: .ancient) }
        let cuts = Annals.cuts(rows)
        for cut in cuts {
            #expect(rows[cut.upperBound].year - rows[cut.lowerBound].year
                    >= Annals.minChapterYears)
        }
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

/// The people the annals remember by name.
@Suite("Lives the chronicle keeps")
struct ChronicleFigureTests {

    @Test("A new world already knows who founded it")
    func foundersAreRemembered() throws {
        let registry = try GameDataRegistry.bundled()
        let state = GameWorldFactory.newGame(registry: registry, seed: 4242)
        #expect(state.figures.count == state.settlements[0].pawns.count)
        #expect(state.figures.allSatisfy { $0.standing == .founder })
        #expect(state.figures.allSatisfy { $0.isAlive })
        // They were born before there was anywhere here to be born.
        #expect(state.figures.allSatisfy { $0.bornYear <= 0 })
        #expect(state.figures.contains { $0.name == "Mara" })
    }

    @Test("Somebody the chronicle was keeping is written down when they go")
    func deathIsRecorded() throws {
        let registry = try GameDataRegistry.bundled()
        var state = GameWorldFactory.newGame(registry: registry, seed: 4242)
        let doomed = state.settlements[0].pawns[0].id
        state.settlements[0].pawns.removeAll { $0.id == doomed }
        state.figures = ChronicleEngine.remember(
            state, year: 40, ticksPerYear: registry.config.ticksPerYear)
        let figure = state.figures.first { $0.id == doomed }
        #expect(figure?.diedYear == 40)
        #expect(figure?.isAlive == false)
        #expect(state.figures.filter { $0.id == doomed }.count == 1,
                "nobody is buried twice")
    }

    @Test("A long life is noticed even if nobody founded anything")
    func eldersAreNoticed() throws {
        let registry = try GameDataRegistry.bundled()
        var state = GameWorldFactory.newGame(registry: registry, seed: 4242)
        state.figures = []
        let ticksPerYear = registry.config.ticksPerYear
        state.settlements[0].pawns[0].age = (ChronicleEngine.rememberedAge + 3) * ticksPerYear
        let figures = ChronicleEngine.remember(state, year: 80, ticksPerYear: ticksPerYear)
        #expect(figures.count == 1)
        #expect(figures[0].standing == .elder)
        #expect(figures[0].bornYear == 80 - (ChronicleEngine.rememberedAge + 3))
    }

    @Test("A chapter names the people it buried")
    func chaptersCarryTheirDead() throws {
        let registry = try GameDataRegistry.bundled()
        var state = AnnalsTests.world((0...30).map { AnnalsTests.record(year: $0) }, registry)
        state.figures = [
            ChronicleFigure(id: UUID(), name: "Mara", bornYear: -22,
                            diedYear: 14, standing: .founder),
            ChronicleFigure(id: UUID(), name: "Osk", bornYear: 40,
                            diedYear: 99, standing: .elder)
        ]
        let chapters = Annals.chapters(state, registry: registry)
        let first = try #require(chapters.first)
        #expect(first.lives.map(\.name) == ["Mara"], "only the dead of these years")
        let text = StubNarrator(mapSeed: 5).annal(first, language: .en)
        #expect(text.contains("Mara"))
        #expect(!text.contains("Osk"))
    }

    @Test("The roll of names does not grow without bound")
    func figuresAreCapped() throws {
        let registry = try GameDataRegistry.bundled()
        var state = GameWorldFactory.newGame(registry: registry, seed: 4242)
        state.figures = (0..<(ChronicleEngine.maxFigures + 30)).map {
            ChronicleFigure(id: UUID(), name: "N\($0)", bornYear: 0,
                            diedYear: $0, standing: .elder)
        }
        let figures = ChronicleEngine.remember(
            state, year: 300, ticksPerYear: registry.config.ticksPerYear)
        #expect(figures.count <= ChronicleEngine.maxFigures)
    }
}
