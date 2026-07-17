import Foundation
import Observation
import EndlessFrontierCore

/// A lightweight, in-app diagnostic log — a running record of what the
/// simulation did each session, so playtesting can be reported precisely.
///
/// It works by *diffing* the world before and after each catch-up (the engine
/// itself stays pure and side-effect-free): who was born, who arrived, who
/// died, and which events fired — flagging those whose effects live in an
/// unpresented choice, which is why "welcome the migrants" never adds anyone.
@MainActor
@Observable
final class Diagnostics {
    enum Kind: String {
        case info, birth, arrival, death, event, warning, tribe
    }

    struct Entry: Identifiable {
        let id = UUID()
        let year: Int
        let kind: Kind
        let text: String
    }

    private(set) var entries: [Entry] = []
    private let maxEntries = 400

    /// A single session's headline, so the user can see the shape at a glance.
    private(set) var lastSummary: String = "No session recorded yet."

    func clear() {
        entries.removeAll()
        lastSummary = "Cleared."
    }

    /// A copy-pasteable transcript for sending as feedback.
    var transcript: String {
        let header = "ENDLESS FRONTIER — DIAGNOSTICS\n\(lastSummary)\n" + String(repeating: "─", count: 32)
        let body = entries.map { "[y\($0.year)] \($0.kind.rawValue.uppercased()): \($0.text)" }
            .joined(separator: "\n")
        return header + "\n" + body
    }

    private func add(_ kind: Kind, _ text: String, year: Int) {
        entries.append(Entry(year: year, kind: kind, text: text))
        if entries.count > maxEntries { entries.removeFirst(entries.count - maxEntries) }
    }

    /// Records the difference a catch-up session made to the world.
    func recordSession(
        before: WorldState,
        after: WorldState,
        fired: [HistoricalEvent],
        registry: GameDataRegistry
    ) {
        let ticksPerYear = max(1, registry.config.ticksPerYear)
        let year = after.year(registry.config)
        let ticks = after.tick - before.tick
        guard ticks > 0 || !fired.isEmpty else { return }

        // Population, by identity so we can classify the newcomers.
        let beforeIDs = Set(before.settlements.flatMap { $0.pawns.map(\.id) })
        let afterPawns = after.settlements.flatMap(\.pawns)
        let afterIDs = Set(afterPawns.map(\.id))
        let arrivedOrBorn = afterPawns.filter { !beforeIDs.contains($0.id) }

        // A newcomer younger than working age was born here; anyone older
        // arrived from outside (an event, a caravan, a defection in).
        let bornThreshold = Pawn.adultAgeYears * ticksPerYear
        let births = arrivedOrBorn.filter { $0.age < bornThreshold }.count
        let arrivals = arrivedOrBorn.count - births
        let left = beforeIDs.subtracting(afterIDs).count

        let popBefore = Int(before.totalPopulation)
        let popAfter = Int(after.totalPopulation)

        lastSummary = "+\(ticks) ticks · population \(popBefore) → \(popAfter)"
            + " (births \(births), arrivals \(arrivals), left \(left))"
        add(.info, "Session ran \(ticks) ticks. Population \(popBefore) → \(popAfter).", year: year)

        if births > 0 { add(.birth, "\(births) child(ren) born.", year: year) }
        if arrivals > 0 {
            add(.arrival, "\(arrivals) colonist(s) arrived from outside.", year: year)
        }

        // Deaths by cause, diffed from the tallies.
        let deathsBefore = mergedDeaths(before)
        let deathsAfter = mergedDeaths(after)
        for (cause, n) in deathsAfter {
            let delta = n - (deathsBefore[cause] ?? 0)
            if delta > 0 { add(.death, "\(delta) died — \(cause).", year: year) }
        }

        // New neighbouring peoples (secession).
        let beforeTribes = Set(before.tribes.map(\.id))
        for tribe in after.tribes where !beforeTribes.contains(tribe.id) {
            add(.tribe, "A people split off: \(tribe.name) (\(Int(tribe.population)) souls).", year: year)
        }

        // Fired events. Choice events now queue for the player rather than
        // evaporating, so note that a decision is waiting.
        for event in fired {
            let template = registry.events.first { $0.id == event.templateID }
            let name = template?.name.resolve(AppStrings.language) ?? event.templateID
            if let template, !template.choices.isEmpty {
                add(.event, "Event fired: \(name) — queued for your decision "
                    + "(\(template.choices.count) choices).", year: year)
            } else {
                add(.event, "Event fired: \(name).", year: year)
            }
        }
        if !after.pendingEvents.isEmpty {
            add(.warning, "\(after.pendingEvents.count) decision(s) awaiting you on the Settlement screen.",
                year: year)
        }
    }

    private func mergedDeaths(_ state: WorldState) -> [String: Int] {
        var merged: [String: Int] = [:]
        for settlement in state.settlements {
            for (cause, n) in settlement.deathTallies { merged[cause, default: 0] += n }
        }
        return merged
    }
}
