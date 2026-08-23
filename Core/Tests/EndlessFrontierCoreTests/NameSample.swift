import Testing
import Foundation
@testable import EndlessFrontierCore

@Suite("name sample", .enabled(if: ProcessInfo.processInfo.environment["EF_DIAG"] != nil, "diag"))
struct ZZNameSample {
    @Test("what a player's neighbourhood is called")
    func sample() {
        for language in [GameLanguage.cs, .en] {
            let names = HexCoord.disc(radius: 2).map {
                MapGenerator.name(for: $0, mapSeed: 4242, language: language)
            }
            print("\n\(language.rawValue): " + names.joined(separator: " · "))
        }
    }
}
