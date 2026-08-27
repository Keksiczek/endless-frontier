import Testing
import Foundation
@testable import EndlessFrontierCore

/// What a colonist's own history is made of.
///
/// `PawnInspectorCard` shows *what happened to them* out of
/// `ColonyLogEntry.subject`, so the section is worth exactly as much as two
/// things: how many lines carry a subject, and how long the journal keeps a
/// line at all. The second is the one nobody has measured — `ColonyLog` is a
/// ring of `capacity` entries shared by the whole colony, so a busy town can
/// forget a wedding before the bride is done dancing.
///
/// ```
/// EF_PROBE=1 swift test --package-path Core --filter MemoryProbe
/// ```
@Suite("What a colonist remembers, measured", .enabled(
    if: ProcessInfo.processInfo.environment["EF_PROBE"] != nil,
    "a measuring instrument — set EF_PROBE=1 to run it"))
struct MemoryProbe {

    @Test("How much of their own life a colonist can still see")
    func theRing() throws {
        let registry = try GameDataRegistry.bundled()
        var state = GameWorldFactory.newGame(registry: registry, seed: 4242)
        let ticksPerYear = registry.config.ticksPerYear

        print("""

        ── the journal as a memory ───────────────────────────────────
        capacity \(ColonyLog.capacity) entries · a year is \(ticksPerYear) ticks
        year   pop  held  spanY  subj  bldg place  withHist  p50  p90  max
        """)

        for step in 1...20 {
            state = TickEngine.advance(state, ticks: 600, registry: registry).state
            guard let s = state.settlements.first else { break }
            let year = Season.year(tick: state.tick, ticksPerYear: ticksPerYear)
            let held = s.journal.entries.count
            let oldest = s.journal.entries.first?.tick ?? state.tick
            let spanY = Double(state.tick - oldest) / Double(ticksPerYear)

            var pawnSubjects = 0, buildingSubjects = 0, placeSubjects = 0
            var perPawn: [UUID: Int] = [:]
            for entry in s.journal.entries {
                switch entry.subject {
                case let .pawn(id):
                    pawnSubjects += 1
                    perPawn[id, default: 0] += 1
                case .building: buildingSubjects += 1
                case .place:    placeSubjects += 1
                case nil:       break
                }
            }
            let lengths = s.pawns.map { perPawn[$0.id] ?? 0 }.sorted()
            let withHistory = lengths.count { $0 > 0 }
            func percentile(_ q: Double) -> Int {
                guard !lengths.isEmpty else { return 0 }
                return lengths[min(lengths.count - 1, Int(q * Double(lengths.count)))]
            }
            let share = s.pawns.isEmpty ? 0
                : Int((Double(withHistory) / Double(s.pawns.count)) * 100)

            print("""
            \(pad(year, 4))  \(pad(s.pawns.count, 4)) \(pad(held, 5)) \
            \(pad(String(format: "%.1f", spanY), 6)) \(pad(pawnSubjects, 5)) \
            \(pad(buildingSubjects, 5)) \(pad(placeSubjects, 5)) \
            \(pad("\(withHistory) (\(share)%)", 9)) \(pad(percentile(0.5), 4)) \
            \(pad(percentile(0.9), 4)) \(pad(lengths.last ?? 0, 4))
            """)
            _ = step
        }

        // What kinds of line ever name a person at all — the other half of the
        // question, and the one the handoff asked about.
        if let s = state.settlements.first {
            var byKind: [String: (total: Int, subjected: Int)] = [:]
            for entry in s.journal.entries {
                let key = entry.kind.rawValue
                var row = byKind[key] ?? (0, 0)
                row.total += 1
                if case .pawn = entry.subject { row.subjected += 1 }
                byKind[key] = row
            }
            print("\n  kind          held  namesSomebody")
            for key in byKind.keys.sorted() {
                let row = byKind[key]!
                print("  \(pad(key, 12)) \(pad(row.total, 5)) \(pad(row.subjected, 5))")
            }
        }
    }

    private func pad(_ value: Any, _ width: Int) -> String {
        let text = "\(value)"
        return text.count >= width ? text
            : String(repeating: " ", count: width - text.count) + text
    }
}
