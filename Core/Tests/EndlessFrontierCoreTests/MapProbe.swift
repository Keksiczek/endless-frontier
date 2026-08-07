import Testing
import Foundation
@testable import EndlessFrontierCore

/// The world map, printed so somebody can look at it.
///
/// Off by default like `DangerProbe` and `GrowthProbe`, and for the same
/// reason: it measures rather than asserts. `WorldGeographyTests` pins the
/// numbers — how often neighbours agree, how big the largest stretch is — but a
/// number cannot tell you whether the thing reads as a *place*. This can.
///
/// ```
/// EF_PROBE=1 swift test --package-path Core --filter MapProbe
/// ```
@Suite("The map, drawn", .enabled(
    if: ProcessInfo.processInfo.environment["EF_PROBE"] != nil,
    "a measuring instrument — set EF_PROBE=1 to run it"))
struct MapProbe {

    /// One letter per country, so a whole world fits on a screen.
    private func glyph(_ biomeID: String) -> String {
        switch biomeID {
        case "mountains": return "▲"
        case "coast":     return "~"
        case "desert":    return "░"
        case "tundra":    return "*"
        case "forest":    return "♣"
        case "plains":    return "."
        default:          return "?"
        }
    }

    @Test("Four worlds, side by side")
    func drawTheWorld() throws {
        let registry = try GameDataRegistry.bundled()
        let radius = 8

        for seed in [UInt64(4242), 7, 99, 1_234_567] {
            var rows: [Int: String] = [:]
            var counts: [String: Int] = [:]
            var same = 0, touching = 0
            for coord in HexCoord.disc(radius: radius) {
                let biome = MapGenerator.region(
                    at: coord, mapSeed: seed, registry: registry).biomeID
                counts[biome, default: 0] += 1
                for neighbour in coord.neighbors()
                where neighbour.distance(to: .origin) <= radius {
                    touching += 1
                    if MapGenerator.region(at: neighbour, mapSeed: seed,
                                           registry: registry).biomeID == biome { same += 1 }
                }
                // Axial → a staggered row, so the hexes line up on screen.
                let indent = String(repeating: " ", count: abs(coord.r))
                rows[coord.r, default: indent] += glyph(biome) + " "
            }
            let agreement = touching == 0 ? 0 : Double(same) / Double(touching) * 100
            let census = counts.sorted { ($0.value, $1.key) > ($1.value, $0.key) }
                .map { "\(glyph($0.key))\($0.value)" }.joined(separator: " ")

            print("""

            ── seed \(seed) ──────────────────────────────────────────
            \(rows.keys.sorted().map { rows[$0] ?? "" }.joined(separator: "\n"))

            neighbours agreeing: \(Int(agreement))%   ·   \(census)
            """)
        }
        print("──────────────────────────────────────────────────────────────\n")
    }

    /// What the three fields actually look like under the biomes — the thing
    /// to read when a world comes out all one country.
    @Test("The land underneath")
    func drawTheFields() {
        func band(_ v: Double) -> String {
            switch v {
            case ..<(-0.6): return "▁"
            case ..<(-0.2): return "▃"
            case ..<0.2:    return "▅"
            case ..<0.6:    return "▆"
            default:        return "█"
            }
        }
        print("\n── the land, seed 4242 ───────────────────────────────────────")
        for (name, pick) in [
            ("height  ", { (l: (elevation: Double, moisture: Double, warmth: Double)) in l.elevation }),
            ("moisture", { (l: (elevation: Double, moisture: Double, warmth: Double)) in l.moisture }),
            ("warmth  ", { (l: (elevation: Double, moisture: Double, warmth: Double)) in l.warmth })
        ] {
            var rows: [Int: String] = [:]
            for coord in HexCoord.disc(radius: 8) {
                let indent = String(repeating: " ", count: abs(coord.r))
                rows[coord.r, default: indent] += band(pick(MapGenerator.land(at: coord, mapSeed: 4242)))
            }
            print("\n\(name)\n\(rows.keys.sorted().map { rows[$0] ?? "" }.joined(separator: "\n"))")
        }
        print("──────────────────────────────────────────────────────────────\n")
    }
}
