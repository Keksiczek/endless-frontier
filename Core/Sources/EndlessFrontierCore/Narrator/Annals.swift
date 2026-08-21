import Foundation

/// Cuts the chronicle's yearly rows into **chapters** a narrator can speak to.
///
/// Two hundred rows is a spreadsheet, not a history. A chapter is a stretch of
/// years under one era, no longer than `maxChapterYears`, summarised into a
/// `ChapterSnapshot`.
///
/// Pure and derived: nothing here is stored in `WorldState`. The test of
/// whether something belongs in `WorldRecord` is whether it could be recomputed
/// from the rows later — everything in this file could be, so none of it is
/// persisted. See `docs/CHRONICLE.md`.
public enum Annals {
    /// The longest a chapter may run. An era can last centuries; a chapter that
    /// long says "the population went from 20 to 300" and nothing a reader can
    /// hold on to.
    public static let maxChapterYears = 25

    /// …and the shortest one worth writing. Below this a chapter is a
    /// paragraph about four quiet years, which is padding with a heading on it.
    public static let minChapterYears = 8

    /// Every chapter of the world's history, oldest first.
    public static func chapters(
        _ state: WorldState, registry: GameDataRegistry
    ) -> [ChapterSnapshot] {
        let records = state.records
        guard records.count >= 2 else { return [] }
        let name = state.settlements.first?.name ?? ""
        let ticksPerYear = max(1, registry.config.ticksPerYear)

        return cuts(records).map { range in
            snapshot(records: records, from: range.lowerBound, to: range.upperBound,
                     previous: range.lowerBound > 0 ? records[range.lowerBound - 1] : nil,
                     settlementName: name, state: state,
                     registry: registry, ticksPerYear: ticksPerYear)
        }
    }

    /// Where the history is cut, as disjoint index ranges over the rows.
    ///
    /// Split apart from the summarising so the *shape* of a history can be
    /// tested without a world: an era that turns closes the chapter before it,
    /// a chapter that has run `maxChapterYears` closes itself, and a tail too
    /// short to be a chapter joins the one before it rather than becoming a
    /// paragraph about a single year.
    static func cuts(_ records: [WorldRecord]) -> [ClosedRange<Int>] {
        guard records.count >= 2 else { return [] }
        var out: [ClosedRange<Int>] = []
        var start = 0
        for i in 1..<records.count {
            let isLast = i == records.count - 1
            if records[i].era != records[start].era {
                if i - 1 >= start { out.append(start...(i - 1)) }
                start = i
                if isLast { out.append(start...i) }
                continue
            }
            if records[i].year - records[start].year >= maxChapterYears || isLast {
                out.append(start...i)
                start = i + 1
            }
        }
        // **A stub is not a chapter.** An era turning a few years after the
        // last cut leaves a paragraph about four quiet years, which reads as
        // padding — so anything shorter than `minChapterYears` is folded back
        // into the chapter before it. Only backwards, and only once per
        // chapter, so the fold cannot cascade into one enormous age.
        var folded: [ClosedRange<Int>] = []
        for cut in out {
            let years = records[cut.upperBound].year - records[cut.lowerBound].year
            if years < minChapterYears, let previous = folded.last {
                folded.removeLast()
                folded.append(previous.lowerBound...cut.upperBound)
            } else {
                folded.append(cut)
            }
        }
        return folded
    }

    /// One chapter, out of the rows between two indices.
    ///
    /// `previous` is the row before the chapter opens: the cumulative death
    /// tallies are differenced against it, so a chapter reports its **own**
    /// dead rather than everybody who ever died.
    static func snapshot(
        records: [WorldRecord], from: Int, to: Int, previous: WorldRecord?,
        settlementName: String, state: WorldState,
        registry: GameDataRegistry, ticksPerYear: Int
    ) -> ChapterSnapshot {
        let span = Array(records[from...to])
        let first = span[0], last = span[span.count - 1]
        let peak = span.max { $0.population < $1.population } ?? last
        let leanest = span.min { $0.food < $1.food } ?? last

        // The tallies run cumulatively, so a chapter's dead are the difference.
        // The baseline is the row *before* the chapter, and the chapter's own
        // first row where there is none — a colony's very first chapter counts
        // from nothing, which is correct.
        let baseline = previous?.deaths ?? [:]
        var deaths: [String: Int] = [:]
        for (cause, total) in last.deaths {
            let before = baseline[cause] ?? 0
            if total - before > 0 { deaths[cause] = total - before }
        }

        let drifts = [
            GeneDrift(trait: "industry", from: first.industry, to: last.industry),
            GeneDrift(trait: "fertility", from: first.fertility, to: last.fertility),
            GeneDrift(trait: "sociability", from: first.sociability, to: last.sociability),
            GeneDrift(trait: "courage", from: first.courage, to: last.courage)
        ]

        let events = state.eventHistory.compactMap { event -> ChapterEvent? in
            let year = Season.year(tick: event.tick, ticksPerYear: ticksPerYear)
            guard year >= first.year, year <= last.year else { return nil }
            guard event.type != .flavor else { return nil }
            let name = registry.events.first { $0.id == event.templateID }?.name
            return ChapterEvent(
                templateID: event.templateID,
                name: name ?? LocalizedText(event.templateID.replacingOccurrences(
                    of: "_", with: " ")),
                type: event.type, year: year)
        }

        return ChapterSnapshot(
            firstYear: first.year, lastYear: last.year, era: last.era,
            settlementName: settlementName,
            populationFirst: first.population, populationLast: last.population,
            populationPeak: peak.population, peakYear: peak.year,
            deaths: deaths,
            moraleMean: span.reduce(0) { $0 + $1.morale } / Double(span.count),
            giniLast: last.gini, faithLast: last.faith,
            leanestYear: leanest.year, leanestFood: leanest.food,
            drifts: drifts, events: events,
            // Whoever the chronicle was keeping and buried in these years. The
            // longest life first: an annal has room for one or two names, and
            // the one worth the room is the one that spans the most of it.
            lives: state.figures
                .filter { ($0.diedYear ?? .max) >= first.year
                    && ($0.diedYear ?? .max) <= last.year }
                .sorted { ($0.age ?? 0) != ($1.age ?? 0)
                    ? ($0.age ?? 0) > ($1.age ?? 0)
                    : $0.name < $1.name })
    }
}
