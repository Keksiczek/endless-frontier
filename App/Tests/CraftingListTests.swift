import Testing
import Foundation
@testable import EndlessFrontier
@testable import EndlessFrontierCore

/// **One row per thing, not one per way of making it.**
///
/// Keks, on the audit: *"crafteni je moc velké."* Folding the groups (§16) made
/// four hundred recipes navigable and left the duplication underneath: measured
/// over the shipped book, 240 of the 420 recipes make something another recipe
/// already makes, 107 items have two or more routes, and 79 of those have them
/// in the *same age* — so the panel put "Sew Hide Vest" directly above "Stitch
/// Hide Vest" and left the player to work out they were one garment.
@MainActor
@Suite("The crafting list")
struct CraftingListTests {

    private func game(_ shape: ((inout WorldState) -> Void)? = nil) -> GameViewModel {
        let temp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("crafting-\(UUID().uuidString).json")
        let registry = (try? GameDataRegistry.bundled()) ?? GameDataRegistry()
        let store = WorldStore(url: temp)
        var seeded = GameWorldFactory.newGame(registry: registry, seed: 4242)
        // Every bench in the game, so the list is the whole book rather than
        // whatever a five-year-old colony happens to have raised (rule 89: a
        // fixture that omits the data the feature reads tests the fallback).
        let benches = registry.recipes.values.compactMap(\.requiresBuilding)
        seeded.settlements[0].buildings += Set(benches).sorted()
            .map { BuildingInstance(definitionID: $0, count: 1) }
        seeded.researchedTechs = Set(registry.techs.keys)
        shape?(&seeded)
        try? store.save(seeded)
        return GameViewModel(registry: registry, store: store)
    }

    @Test("A thing appears once, however many ways there are to make it")
    func oneRowPerThing() {
        let game = game()
        #expect(!game.recipeGroups.isEmpty)                     // rule 67
        for group in game.recipeGroups {
            let things = group.recipes.map(\.outputItemID)
            #expect(things.count == Set(things).count,
                    "\(group.title) lists the same thing twice")
        }
    }

    /// The fold must tidy, never hide: everything the colony could make is
    /// still on the list, just once.
    @Test("Folding the routes loses nothing")
    func nothingIsLost() {
        let game = game()
        let shown = Set(game.recipeGroups.flatMap { $0.recipes.map(\.outputItemID) })
        let possible = Set(game.recipesHere.map(\.outputItemID))
        #expect(shown == possible,
                "missing from the list: \(possible.subtracting(shown).sorted().prefix(6))")
    }

    /// And it says so, or a shorter list reads as content gone missing.
    @Test("A thing with several routes says how many")
    func routesAreCounted() {
        let game = game()
        let doubled = game.recipeGroups
            .flatMap { $0.recipes }
            .filter { game.waysToMake($0) > 1 }
        #expect(!doubled.isEmpty)
    }

    /// Somebody typing a recipe's name is asking for *that* recipe. A fold that
    /// answers with its sibling is a search that lies.
    @Test("A search still shows every way")
    func searchIsNotFolded() {
        let game = game()
        let byOutput = Dictionary(grouping: game.recipesHere, by: \.outputItemID)
        guard let twins = byOutput.values.first(where: { $0.count > 1 })?
            .sorted(by: { $0.id < $1.id }) else { return }
        // A word both routes' names share, so the search cannot be what splits
        // them: the output id itself is matched by the panel's search.
        game.recipeSearch = twins[0].outputItemID
        let found = game.recipeGroups.flatMap { $0.recipes }.map(\.id)
        for twin in twins {
            #expect(found.contains(twin.id), "\(twin.id) fell out of its own search")
        }
    }
}
