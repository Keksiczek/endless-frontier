import Testing
import Foundation
@testable import EndlessFrontierCore

@Suite("coverprobe", .enabled(if: ProcessInfo.processInfo.environment["EF_DIAG"] != nil, "diag"))
struct CoverProbe {
    @Test("cover tally")
    func tally() {
        for biome in ["plains", "forest", "desert", "tundra", "mountains", "coast"] {
            var t: [GroundCover: Int] = [:]
            var heights: [Double] = []
            for c in 0..<LocalMap.gridColumns {
                for r in 0..<LocalMap.gridRows {
                    t[LocalTerrain.cover(terrainSeed: 9, biomeID: biome, column: c, row: r), default: 0] += 1
                    let land = LocalTerrain.shape(of: biome)
                    heights.append(min(1, max(0, LocalTerrain.elevation(9, c, r) + land.lift)))
                }
            }
            let total = t.values.reduce(0, +)
            let top = t.sorted { $0.value > $1.value }
                .map { "\($0.key.rawValue) \(Int(Double($0.value) / Double(total) * 100))%" }
            heights.sort()
            let p = { (q: Double) in String(format: "%.2f", heights[Int(Double(heights.count - 1) * q)]) }
            print("\(biome.padding(toLength: 10, withPad: " ", startingAt: 0)) h[p10 \(p(0.1)) p50 \(p(0.5)) p90 \(p(0.9))]  \(top.joined(separator: ", "))")
        }
    }
}
