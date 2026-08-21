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
            var landforms: [String: Int] = [:]
            for coord in HexCoord.disc(radius: radius) {
                if let f = MapGenerator.feature(at: coord, mapSeed: seed) {
                    landforms[f.rawValue, default: 0] += 1
                }
            }
            let features = landforms.isEmpty ? "no landmarks at all"
                : landforms.sorted { ($0.value, $1.key) > ($1.value, $0.key) }
                    .map { "\($0.key)×\($0.value)" }.joined(separator: " ")

            print("""

            ── seed \(seed) ──────────────────────────────────────────
            \(rows.keys.sorted().map { rows[$0] ?? "" }.joined(separator: "\n"))

            neighbours agreeing: \(Int(agreement))%   ·   \(census)
            landmarks: \(features)
            """)
        }
        print("──────────────────────────────────────────────────────────────\n")
    }

    /// How much the ground actually moves from one hex to the next.
    ///
    /// The number every landform threshold is measured against, and the reason
    /// the first cut of them was wrong in both directions at once: the
    /// elevation field is smooth at hex scale, so "higher than all six
    /// neighbours by 0.10" almost never happens while "flat to within 0.22"
    /// almost always does. Read this before touching `MapGenerator.feature`.
    @Test("How much the ground moves between neighbours")
    func relief() {
        var spread: [Double] = []     // highest neighbour − lowest neighbour
        var fromMean: [Double] = []   // this hex − the mean of its neighbours
        var above: [Double] = []      // this hex − its highest neighbour
        for seed in [UInt64(4242), 7, 99, 1_234_567] {
            for coord in HexCoord.disc(radius: 9) {
                let here = MapGenerator.land(at: coord, mapSeed: seed).elevation
                let n = coord.neighbors().map { MapGenerator.land(at: $0, mapSeed: seed).elevation }
                guard let hi = n.max(), let lo = n.min() else { continue }
                spread.append(hi - lo)
                fromMean.append(here - n.reduce(0, +) / Double(n.count))
                above.append(here - hi)
            }
        }
        func percentiles(_ name: String, _ values: [Double]) {
            let s = values.sorted()
            func at(_ p: Double) -> String {
                String(format: "%+.3f", s[min(s.count - 1, Int(Double(s.count) * p))])
            }
            print("\(name)  p5 \(at(0.05))  p25 \(at(0.25))  p50 \(at(0.50))  "
                  + "p75 \(at(0.75))  p95 \(at(0.95))  p99 \(at(0.99))")
        }
        print("\n── relief, \(spread.count) hexes ─────────────────────────────")
        percentiles("neighbour spread ", spread)
        percentiles("this − mean      ", fromMean)
        percentiles("this − highest   ", above)
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

    /// **Where the water runs, and how much of it there is.**
    ///
    /// The moisture percentiles first, then the count of hexes the river rule
    /// actually puts water on — because a threshold picked against a
    /// distribution nobody printed is how this file got a world with
    /// twenty-nine plateaus and never a pass (rule 23).
    @Test("Where the water runs")
    func whereTheWaterRuns() {
        let hexes = HexCoord.disc(radius: 20)
        let wet = hexes.map { MapGenerator.land(at: $0, mapSeed: 4242).moisture }
        func percentiles(_ name: String, _ values: [Double]) {
            let sorted = values.sorted()
            func at(_ p: Double) -> String {
                String(format: "%+.3f", sorted[min(sorted.count - 1, Int(Double(sorted.count) * p))])
            }
            print("\(name)  p5 \(at(0.05))  p25 \(at(0.25))  p50 \(at(0.50))  "
                  + "p75 \(at(0.75))  p95 \(at(0.95))  p99 \(at(0.99))")
        }
        print("\n── the water, \(hexes.count) hexes ──────────────────────────")
        percentiles("moisture        ", wet)

        percentiles("elevation       ", hexes.map { MapGenerator.land(at: $0, mapSeed: 4242).elevation })

        let courses = hexes.compactMap { MapGenerator.river(at: $0, mapSeed: 4242) }
        let sources = courses.count { $0.isSource }
        let mouths = courses.count { $0.isMouth }
        print(String(format: "\nat the shipped threshold: river hexes %d of %d (%.1f%%)"
                     + "  ·  springs %d  ·  mouths %d",
                     courses.count, hexes.count,
                     Double(courses.count) / Double(hexes.count) * 100,
                     sources, mouths))

        // **The sweep, so the threshold is chosen against the shape of the
        // whole map rather than against one number somebody liked.** A world
        // where a third of the hexes hold a river is a world where a bridge is
        // a flat tax; one where none do has no rivers at all. What is wanted is
        // water rare enough to be a feature of *this* valley and common enough
        // to be met.
        print("\nmoisture   share   courses   longest")
        for wetEnough in [0.06, 0.20, 0.30, 0.40, 0.45, 0.50, 0.60] {
            var river: Set<String> = []
            func key(_ c: HexCoord) -> String { "\(c.q),\(c.r)" }
            func wet(_ c: HexCoord) -> Bool {
                MapGenerator.land(at: c, mapSeed: 4242).moisture >= wetEnough
            }
            func course(_ c: HexCoord) -> (from: HexCoord?, to: HexCoord?)? {
                guard wet(c) else { return nil }
                let onward = MapGenerator.downhill(from: c, mapSeed: 4242)
                let feeder = c.neighbors().first {
                    wet($0) && MapGenerator.downhill(from: $0, mapSeed: 4242) == c
                }
                guard feeder != nil
                        || MapGenerator.land(at: c, mapSeed: 4242).elevation
                            >= MapGenerator.springElevation else { return nil }
                guard feeder != nil || onward != nil else { return nil }
                return (feeder, onward)
            }
            for coord in hexes where course(coord) != nil { river.insert(key(coord)) }
            var lengths: [Int] = []
            var walked: Set<String> = []
            for coord in hexes {
                guard let c = course(coord), c.from == nil, !walked.contains(key(coord))
                else { continue }
                var length = 1, here = coord
                while let next = course(here)?.to, course(next) != nil,
                      !walked.contains(key(next)) {
                    walked.insert(key(next)); here = next; length += 1
                    if length > 60 { break }
                }
                lengths.append(length)
            }
            print(String(format: "%8.2f  %5.1f%%  %8d  %8d", wetEnough,
                         Double(river.count) / Double(hexes.count) * 100,
                         lengths.count, lengths.max() ?? 0))
        }
        print("──────────────────────────────────────────────────────────────\n")
    }
}
