import Testing
import Foundation
@testable import EndlessFrontierCore

/// **The council, checked against a real colony rather than a seed.**
///
/// Every other probe in this tree starts a world and runs it. That measures the
/// game as it is *now*, which is exactly what a change wants to know — and
/// exactly not what a player who has been in one save for two hundred years
/// wants to know. Keks's own town is the evidence that started this: ninety
/// souls, ninety-eight buildings, seven banks, six universities, one windmill,
/// no workshop.
///
/// Point `EF_SAVE` at a `endless-frontier-world.json` and this loads it,
/// advances a decade and prints what the council did with it. Nothing is
/// written back — the save is opened, copied into memory and left alone.
///
/// ```
/// EF_SAVE=~/Library/.../Documents/endless-frontier-world.json \
///   swift test --package-path Core --filter ZZSaveDiag
/// ```
@Suite("save diag", .enabled(if: ProcessInfo.processInfo.environment["EF_SAVE"] != nil, "needs a save"))
struct ZZSaveDiag {

    static var saveURL: URL? {
        guard let path = ProcessInfo.processInfo.environment["EF_SAVE"] else { return nil }
        return URL(fileURLWithPath: NSString(string: path).expandingTildeInPath)
    }

    /// What stands, what it draws, and what the council would raise next.
    @Test("a real colony, a decade on")
    func aDecadeOn() throws {
        guard let url = Self.saveURL, let loaded = try WorldStore(url: url).load() else {
            print("no save at EF_SAVE"); return
        }
        let registry = try GameDataRegistry.bundled()
        var state = loaded

        func report(_ title: String, _ state: WorldState) {
            guard let s = state.settlements.first else { return }
            let generation = StewardEngine.production(of: s, .energy, registry: registry)
            let draw = StewardEngine.energyDraw(of: s, in: state, registry: registry)
            let domestic = ResourceLoop.domesticEnergyDemand(
                population: s.population, era: state.era, config: registry.config)
            let tally = s.buildings
                .sorted { $0.count == $1.count ? $0.definitionID < $1.definitionID : $0.count > $1.count }
            print("""

            ── \(title) ─────────────────────────────────────────────
            tick \(state.tick)  era \(state.era.rawValue)  souls \(s.pawns.count)
            buildings \(s.buildings.reduce(0) { $0 + $1.count })
            grid \(s.colony?.width ?? 0)×\(s.colony?.height ?? 0), \
            \(s.colony?.placements.count ?? 0) lots
            energy  make \(String(format: "%.1f", generation))  \
            draw \(String(format: "%.2f", draw)) \
            (people \(String(format: "%.2f", domestic)), \
            buildings \(String(format: "%.2f", draw - domestic)))  \
            store \(String(format: "%.0f", s.storage[.energy]))/\
            \(String(format: "%.0f", s.storageCapacity[.energy]))
            next   \(StewardEngine.nextBuilding(for: s, in: state, registry: registry) ?? "—")
            ────────────────────────────────────────────────────────
            """)
            for b in tally.prefix(24) {
                print(String(format: "  %-22@ %3d", b.definitionID, b.count))
            }
            // **Why the grid was not answered.** A clause that cannot find an
            // affordable answer falls through silently, and "the council never
            // looked" and "the council looked and could not pay" want opposite
            // fixes (rule 27's other half).
            let wanted = StewardEngine.wantedHere(s, in: state, registry: registry)
                .filter { $0.production[.energy] > 0 }
            let able = StewardEngine.buildableHere(s, in: state, registry: registry)
                .filter { $0.production[.energy] > 0 }
            // **What the benches have to work with.** Every building in the
            // book but twenty-eight names a made thing, and every made thing
            // in the early chain starts at `wood` — so this is the number the
            // whole colony's future runs through.
            let raw = ["wood", "timber_bundle", "charcoal", "iron_ore", "iron_ingot",
                       "clay", "brick", "rough_stone"]
            print("shelf: " + raw.map { "\($0) \(s.stockpile[$0, default: 0])" }
                    .joined(separator: "  "))
            // The rock, per deposit: what the ground has open right now against
            // what this particular valley is supposed to hold. Biome-specific
            // by construction — the nodes are what the generator laid down.
            let rocks = s.localMap?.rocks ?? []
            let live = rocks.filter { !$0.isSpent }
            let byKind = (s.localMap?.nodes ?? [])
                .filter { MineralEngine.isMineral($0.kind) }
                .map { node -> String in
                    let open = live.filter { $0.kind.deposit == node.kind }.count
                    return String(format: "%@ %.0f/%.0f(%d)",
                                  node.kind.rawValue, node.amount, node.capacity, open)
                }
                .joined(separator: "  ")
            print("rock: \(live.count) live of \(rocks.count) outcrops | \(byKind)")
            let trees = s.localMap?.trees ?? []
            let workable = trees.filter { $0.growth >= FloraEngine.minimumWorkableGrowth }.count
            let bearing = trees.filter { $0.growth >= FloraEngine.bearingGrowth }.count
            print("wood: \(trees.count) trees, \(workable) workable, \(bearing) bearing")
            let loggers = s.pawns.filter { $0.assignedWork == .logging }.count
            let crafters = s.pawns.filter { $0.assignedWork == .crafting }.count
            let atBench = s.pawns.filter { $0.currentJob?.kind == .craftItem }.count
            print("piles \(s.localMap?.piles.count ?? -1)  loggers \(loggers)  crafters \(crafters) "
                  + "(at a bench \(atBench))  orders \(s.craftOrders.count)")
            print("generators: unlocked \(wanted.map(\.id).sorted()), " +
                  "affordable \(able.map(\.id).sorted())")
            for def in wanted.sorted(by: { $0.id < $1.id }) {
                let shelf = def.materialCost
                    .map { "\($0.key) \(s.stockpile[$0.key, default: 0])/\($0.value)" }
                    .sorted().joined(separator: " ")
                print(String(format: "  %-16@ makes %4.0f  materials %5.0f/%-6.0f  shelf %@",
                             def.id, def.production[.energy],
                             s.storage[.materials], def.cost[.materials],
                             shelf.isEmpty ? "—" : shelf))
            }
        }

        report("as saved", state)
        // Played the way the game plays itself when nobody is looking.
        // `EF_YEARS` because a wood comes back over decades, not over a decade:
        // ten years is long enough to see whether saplings are being set and
        // far too short to see whether any of them ever reaches an axe.
        let years = Int(ProcessInfo.processInfo.environment["EF_YEARS"] ?? "") ?? 10
        for year in 1...years {
            state = BalanceHarness.autoPlay(state, registry: registry)
            state = TickEngine.advance(state, ticks: registry.config.ticksPerYear,
                                       registry: registry).state
            if year % 10 == 0 { report("\(year) years on", state) }
        }
    }
}
