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
                s = SiegeEngine.advance(s, to: opened + Siege.stepsTotal, registry: registry)
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
