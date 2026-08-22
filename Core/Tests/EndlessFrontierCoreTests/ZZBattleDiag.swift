import Testing
import Foundation
@testable import EndlessFrontierCore

/// **How a fight actually goes**, as distinct from how long it is allowed to.
///
/// Keks, watching one: *"netrvalo jak dlouho by melo, salvy jsou takove stale
/// stejne animace a boj neni moc dynamicky."* Three complaints that could each
/// be a different fault — a fight cut short, a fight with one weapon in it, or
/// a fight where only one side ever does anything — and they want measuring
/// apart before anything is tuned.
///
/// ```
/// EF_DIAG=1 swift test --package-path Core --filter ZZBattleDiag
/// ```
@Suite("battle diag", .enabled(if: ProcessInfo.processInfo.environment["EF_DIAG"] != nil, "diag"))
struct ZZBattleDiag {

    @Test("what a raid is made of")
    func theShapeOfAFight() throws {
        let registry = try GameDataRegistry.bundled()
        var world = GameWorldFactory.newGame(registry: registry, seed: 4242)
        // A colony with people in it, and a few years of the council arming
        // them — a fight between twelve founders is not the fight to measure.
        world = TickEngine.advance(world, ticks: 3000, registry: registry).state

        print("""

        ── fights ─────────────────────────────────────────────────────
        A step is 1.4 real seconds while the player watches (`siegeStepSeconds`).
        `steps` is what the fight was allotted, `ran` is what it used.

        raiders  line armed | steps  ran   secs | ended on      | volleys  kinds       | wounds parts
        """)

        for strength in [4.0, 10.0, 25.0, 60.0, 120.0] {
            guard var settlement = world.settlements.first else { break }
            settlement.siege = nil
            settlement = SiegeEngine.begin(
                settlement, attackerStrength: strength, attackerName: "Test",
                fortification: 10, tick: world.tick, registry: registry,
                seed: 99 &+ UInt64(strength))
            guard let opened = settlement.siege else { continue }
            let allotted = opened.steps
            let line = opened.line.count
            // How many of the line are actually carrying something that shoots.
            let arms = SiegeEngine.armaments(of: settlement.pawns, registry: registry)
            let armed = opened.line.count { arms[$0] != nil }

            var ran = 0
            while settlement.siege?.isFinished == false, ran < 400 {
                let to = (settlement.siege?.advancedTo ?? 0) + 1
                settlement = SiegeEngine.fight(settlement, to: to,
                                               registry: registry).settlement
                ran += 1
                if settlement.siege == nil { break }
            }
            // `conclude` clears the siege, so read the record it left behind.
            let record = settlement.lastBattle
            let moments = record?.moments ?? opened.moments
            let volleys = moments.count { $0.kind == BattleMoment.Kind.volley }
            let kinds = Set(moments.compactMap(\.projectile)).map(\.rawValue).sorted()
            let ended = record?.repelled == true
                ? "warband broken"
                : (ran >= allotted ? "clock ran out" : "line gone")
            let hurts = moments.filter { $0.kind == BattleMoment.Kind.wound
                || $0.kind == BattleMoment.Kind.death }
            let parts = Set(hurts.compactMap(\.part)).map(\.rawValue).sorted()
            let woundKinds = Set(hurts.compactMap(\.wound)).map(\.rawValue).sorted()
            print(String(format: "%7.0f %5d %5d | %5d %4d %6.0f | %-13@ | %7d  %-12@ | %6d %@ %@",
                         strength, line, armed, allotted, ran, Double(ran) * 1.4,
                         ended, volleys,
                         kinds.isEmpty ? "—" : kinds.joined(separator: ","),
                         hurts.count,
                         parts.isEmpty ? "—" : parts.prefix(3).joined(separator: ","),
                         woundKinds.isEmpty ? "" : woundKinds.joined(separator: ",")))
        }

        // What the colony is actually holding. One weapon in the whole line is
        // one animation, however many the book contains.
        if let settlement = world.settlements.first {
            let arms = SiegeEngine.armaments(of: settlement.pawns, registry: registry)
            var byKind: [String: Int] = [:]
            for profile in arms.values {
                byKind[profile.projectile.rawValue, default: 0] += 1
            }
            print("\narmed \(arms.count) of \(settlement.pawns.count) — \(byKind)")
            let onTheShelf = Set(settlement.inventory.compactMap {
                registry.item($0.definitionID)?.combat?.projectile.rawValue
            })
            print("kinds on the shelf: \(onTheShelf.sorted())")
            // **Why nothing is made.** `bestGear` needs a recipe the colony can
            // work *and* the made things it is built out of on the pile.
            let best = QuartermasterEngine.bestGear(
                for: .weapon, at: settlement, in: world, registry: registry)
            let bestRanged = QuartermasterEngine.bestGear(
                for: .weapon, at: settlement, in: world, registry: registry,
                preferring: .ranged)
            print("bestGear(weapon) \(best ?? "—")  ranged \(bestRanged ?? "—")  "
                  + "wantsRanged \(QuartermasterEngine.wantsRanged(at: settlement, registry: registry))")
            // What it could work if the pile were full, against what it can.
            let workable = registry.recipes.values.filter {
                QuartermasterEngine.canWork($0, for: .weapon, at: settlement,
                                            in: world, registry: registry)
            }
            let held = CraftingEngine.materialCounts(settlement)
            let fed = workable.filter { r in r.materials.allSatisfy { (held[$0.key] ?? 0) >= $0.value } }
            print("weapon recipes: workable \(workable.count), of those with materials \(fed.count)")
            print("pile: \(held.filter { $0.value > 0 }.sorted { $0.key < $1.key }.prefix(10))")
            print("orders on the bench: \(settlement.craftOrders.count) of \(CraftingEngine.maxOrders)")
        }
        print("──────────────────────────────────────────────────────────────\n")
    }
}
