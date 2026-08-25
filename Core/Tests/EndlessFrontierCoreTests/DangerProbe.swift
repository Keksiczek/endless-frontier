import Testing
import Foundation
@testable import EndlessFrontierCore

/// A measuring instrument, not a guard rail.
///
/// The handoff's §4.1 said the game has no challenge and gave four separate
/// causes rather than one number. Retuning without measuring is how a project
/// gets a difficulty that is wrong in a new way, so this walks two centuries of
/// a real world and prints what actually happened to the people in it.
///
/// Off by default: it is slow, and it asserts almost nothing on purpose. Run it
/// while tuning with
///
/// ```
/// EF_PROBE=1 swift test --package-path Core --filter DangerProbe
/// ```
@Suite("Danger, measured", .enabled(
    if: ProcessInfo.processInfo.environment["EF_PROBE"] != nil,
    "a measuring instrument — set EF_PROBE=1 to run it"))
struct DangerProbe {

    @Test("Two hundred years of a colony nobody protects")
    func twoCenturies() throws {
        let registry = try GameDataRegistry.bundled()
        var state = GameWorldFactory.newGame(registry: registry, seed: 4242)
        // Counted properly: `lastBattle` *persists*, so sampling "is it set"
        // once a year says 236 fights when there were nine. Distinct ids.
        var fought = Set<UUID>()
        var repelled = 0
        var everHurt = Set<UUID>()
        var plagues = Set<UUID>()

        for _ in 0..<240 {
            state = BalanceHarness.autoPlay(state, registry: registry)
            state = TickEngine.advance(state, ticks: 50, registry: registry).state
            guard let capital = state.settlements.first else { continue }
            if let log = capital.lastBattle, fought.insert(log.id).inserted, log.repelled {
                repelled += 1
            }
            if let outbreak = capital.outbreak { plagues.insert(outbreak.id) }
            for pawn in capital.pawns where pawn.health < 100 { everHurt.insert(pawn.id) }
        }

        let capital = try #require(state.settlements.first)
        let hurtNow = capital.pawns.filter { $0.health < 100 }.count
        print("""

        ── danger, after 12 000 ticks (200 years) ────────────────────
        deaths        \(capital.deathTallies.sorted { $0.key < $1.key })
        population    \(capital.pawns.count)   morale \(Int(capital.stats.morale))
        food          \(Int(capital.storage[.food]))/\(Int(capital.storageCapacity[.food]))
        fights        \(fought.count)  (\(repelled) turned back)
        sicknesses    \(plagues.count)
        tribes        \(state.tribes.count)  standings \
        \(state.tribes.map { Int($0.standing) }.sorted())
        threat        \(Int(state.globalStats.threatLevel))  \
        predators \(Int(capital.localMap?.wildlife.predatorPressure ?? 0))
        hurt now      \(hurtNow)   ever hurt \(everHurt.count)
        broken now    \(capital.pawns.filter(\.isBroken).count)
        ──────────────────────────────────────────────────────────────

        """)
    }

    /// **Where the danger actually comes from**, and what the odds are that
    /// bring it.
    ///
    /// Measured 2026-08-25: seven outlaw raids in two centuries against
    /// sixty-three from peoples and fifty-seven from the wild. A camp is a
    /// place on the map with strength that grows and loot that fattens it, and
    /// it visited a colony once every thirty years — which makes it scenery
    /// (rule 12). This prints the two numbers the odds are built from, because
    /// a rate that never fires is either a small chance or a chance multiplied
    /// by something that is always zero, and those want opposite fixes
    /// (rule 23: read the field's own distribution before setting a threshold).
    @Test("Who comes over the hill, and how often")
    func raidCadence() throws {
        let registry = try GameDataRegistry.bundled()
        var state = GameWorldFactory.newGame(registry: registry, seed: 4242)
        var lures: [Double] = []
        var watches: [Double] = []
        var odds: [Double] = []
        var fromCamps = Set<UUID>()
        var fromPeoples = Set<UUID>()
        var fromWild = Set<UUID>()

        for _ in 0..<240 {
            state = BalanceHarness.autoPlay(state, registry: registry)
            state = TickEngine.advance(state, ticks: 50, registry: registry).state
            guard let capital = state.settlements.first else { continue }
            let lure = BanditEngine.temptation(capital)
            let watch = BanditEngine.watchfulness(capital, registry: registry)
            lures.append(lure)
            watches.append(watch)
            // Three checks a year, one roll each.
            let perCheck = min(0.4, BanditEngine.baseChance * lure * (1 - watch))
            odds.append(1 - pow(1 - perCheck,
                                Double(registry.config.ticksPerYear / OutlawCampEngine.interval)))
            for log in capital.battleHistory {
                if log.attackerCampID != nil { fromCamps.insert(log.id) }
                else if state.tribes.contains(where: { $0.name == log.attackerName }) {
                    fromPeoples.insert(log.id)
                } else { fromWild.insert(log.id) }
            }
        }

        func percentiles(_ values: [Double]) -> String {
            let sorted = values.sorted()
            guard !sorted.isEmpty else { return "—" }
            func at(_ q: Double) -> String {
                String(format: "%.3f", sorted[min(sorted.count - 1, Int(Double(sorted.count) * q))])
            }
            return "p10 \(at(0.1))  p50 \(at(0.5))  p90 \(at(0.9))"
        }
        let meanOdds = odds.isEmpty ? 0 : odds.reduce(0, +) / Double(odds.count)
        print("""

        ── who comes over the hill, 200 years ────────────────────────
        outlaw camps  \(fromCamps.count)
        peoples       \(fromPeoples.count)
        the wild      \(fromWild.count)
        temptation    \(percentiles(lures))
        watchfulness  \(percentiles(watches))
        raid odds/yr  \(percentiles(odds))   mean \(String(format: "%.3f", meanOdds))
        one raid every \(meanOdds > 0 ? String(format: "%.0f", 1 / meanOdds) : "∞") years
        camps left    \(state.camps.count { $0.isActive(at: state.tick) }) of \(state.camps.count)
        ──────────────────────────────────────────────────────────────

        """)
    }

    /// The part anybody actually plays. A colony of four hundred shrugging off
    /// a warband of a hundred and forty is *correct*; the question is whether
    /// the first thirty years have any teeth.
    @Test("The first thirty years")
    func earlyYears() throws {
        let registry = try GameDataRegistry.bundled()
        var state = GameWorldFactory.newGame(registry: registry, seed: 4242)
        var fought = Set<UUID>()
        var worstWound = 0.0

        for _ in 0..<36 {
            state = BalanceHarness.autoPlay(state, registry: registry)
            state = TickEngine.advance(state, ticks: 50, registry: registry).state
            guard let capital = state.settlements.first else { continue }
            if let log = capital.lastBattle { fought.insert(log.id) }
            worstWound = max(worstWound, 100 - (capital.pawns.map(\.health).min() ?? 100))
        }
        let capital = try #require(state.settlements.first)
        print("""

        ── the first thirty years ────────────────────────────────────
        population    \(capital.pawns.count)   morale \(Int(capital.stats.morale))
        deaths        \(capital.deathTallies.sorted { $0.key < $1.key })
        fights        \(fought.count)
        worst wound   −\(Int(worstWound))
        food          \(Int(capital.storage[.food]))/\(Int(capital.storageCapacity[.food]))
        defence       \(Int(capital.stats.defense))
        ──────────────────────────────────────────────────────────────

        """)
    }

    /// One raid, in isolation, at each posture — what it costs and what it
    /// leaves behind. The numbers the retune is aimed at.
    @Test("What one warband costs")
    func oneRaid() throws {
        let registry = try GameDataRegistry.bundled()
        for strength in [30.0, 60, 120] {
            for defense in [0.0, 20, 50] {
                var s = Settlement(
                    id: UUID(uuidString: "5E1E6E00-0000-0000-0000-000000000001")!,
                    name: "Hold", storage: [.food: 1000], storageCapacity: .uniform(2000),
                    stats: SettlementStats(defense: defense))
                for i in 0..<12 {
                    var p = Pawn(
                        id: UUID(uuidString: String(
                            format: "5E1E6E00-0000-0000-0000-%012d", i + 10))!,
                        name: "Hand \(i)")
                    p.age = 25 * 60
                    s.pawns.append(p)
                }
                s = SiegeEngine.begin(
                    s, attackerStrength: strength, attackerName: "Warband",
                    fortification: defense, tick: 100, registry: registry, seed: 0xBEEF)
                let opened = try #require(s.siege).openedAt
                s = SiegeEngine.advance(s, to: opened + (s.siege?.steps ?? Siege.stepsTotal),
                                        registry: registry)
                let dead = 12 - s.pawns.count
                let hurt = s.pawns.filter { $0.health < 100 }.count
                let worst = 100 - (s.pawns.map(\.health).min() ?? 100)
                print(String(
                    format: "str %5.0f  wall %4.0f  →  %@  dead %d  hurt %2d  worst −%.0f  food %.0f",
                    strength, defense,
                    (s.lastBattle?.repelled ?? false) ? "held " : "broke",
                    dead, hurt, worst, s.storage[.food]))
            }
        }
    }
}
