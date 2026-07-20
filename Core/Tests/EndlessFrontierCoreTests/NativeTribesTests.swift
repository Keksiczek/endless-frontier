import Foundation
import Testing
@testable import EndlessFrontierCore

/// The valley was never empty: native peoples are seeded at world creation,
/// hidden until an expedition meets them, and only then diplomatically alive.
@Suite("Native tribes")
struct NativeTribesTests {
    private func registry() throws -> GameDataRegistry { try GameDataRegistry.bundled() }

    @Test("A new world starts with hidden native peoples in distant regions")
    func worldSeedsNatives() throws {
        let world = GameWorldFactory.newGame(registry: try registry(), seed: 42)
        let natives = world.tribes.filter(\.isNative)
        #expect(natives.count == GameWorldFactory.nativeTribeCount)
        #expect(natives.allSatisfy { !$0.discovered })
        // Each lives in a real region, away from the homeland.
        for tribe in natives {
            let home = world.regions.first { $0.id == tribe.regionID }
            #expect(home != nil)
            #expect(home?.kind != .homeland)
            #expect((home?.coord.distance(to: .origin) ?? 0) >= GameWorldFactory.nativeMinDistance)
        }
        // No two peoples share a home.
        #expect(Set(natives.compactMap(\.regionID)).count == natives.count)
    }

    @Test("The same seed settles the same peoples in the same hills")
    func nativesAreDeterministic() throws {
        let reg = try registry()
        let a = GameWorldFactory.newGame(registry: reg, seed: 7, now: Date(timeIntervalSince1970: 0))
        let b = GameWorldFactory.newGame(registry: reg, seed: 7, now: Date(timeIntervalSince1970: 0))
        #expect(a.tribes == b.tribes)
    }

    @Test("An expedition into their region is first contact")
    func expeditionDiscoversTribe() throws {
        let reg = try registry()
        var world = GameWorldFactory.newGame(registry: reg, seed: 42)
        guard let native = world.tribes.first(where: { $0.isNative }),
              let homeID = native.regionID else {
            Issue.record("no native tribe to discover")
            return
        }
        // March straight into their land (bypassing adjacency for the test).
        world.activeExpedition = Expedition(targetRegionID: homeID, ticksRemaining: 1)
        let result = ExplorationEngine.advanceOneTick(world, registry: reg)

        let met = result.state.tribes.first { $0.id == native.id }
        #expect(met?.discovered == true)
        #expect(result.fired.contains { $0.templateID == "first_contact" })
        #expect(result.state.settlements[0].journal.entries.contains { $0.kind == .discovery })
    }

    @Test("An undiscovered people has no relations to move — and can't be courted")
    func undiscoveredAreInert() throws {
        let reg = try registry()
        var world = GameWorldFactory.newGame(registry: reg, seed: 42)
        world.settlements[0].storage[.influence] = 500

        guard let native = world.tribes.first(where: { $0.isNative }) else {
            Issue.record("no native tribe")
            return
        }
        // Player actions bounce off a people you haven't met.
        let gifted = GameEngine.sendGift(world, tribeID: native.id, registry: reg)
        #expect(gifted == world)

        // A year of diplomacy leaves their standing untouched (they grow, though).
        let year = DiplomacyEngine.advanceYear(world, registry: reg)
        let after = year.tribes.first { $0.id == native.id }
        #expect(after?.standing == native.standing)
        #expect((after?.population ?? 0) > native.population)
    }

    @Test("Native peoples don't use up the malcontents' room to secede")
    func nativesDontBlockSecession() throws {
        let reg = try registry()
        let world = GameWorldFactory.newGame(registry: reg, seed: 42)
        // All three slots are natives; the emergent count is still zero, so
        // secession's cap check must pass (the roll itself is separate).
        #expect(world.tribes.filter { !$0.isNative }.count < DiplomacyEngine.maxTribes)
        #expect(world.tribes.count >= DiplomacyEngine.maxTribes)
    }

    @Test("A tribe saved before natives existed decodes as met and emergent")
    func legacyTribeDecodes() throws {
        let tribe = Tribe(id: UUID(), name: "Old", foundedTick: 0,
                          originStory: LocalizedText("They left."),
                          population: 10, genes: Genes())
        var json = try JSONSerialization.jsonObject(
            with: JSONEncoder().encode(tribe)) as! [String: Any]
        json.removeValue(forKey: "isNative")
        json.removeValue(forKey: "discovered")
        let decoded = try JSONDecoder().decode(
            Tribe.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(decoded.isNative == false)
        #expect(decoded.discovered == true)
    }
}
