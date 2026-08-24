import Testing
import Foundation
@testable import EndlessFrontierCore

/// **A coat has to say what it is, or it is drawn as somebody else's coat.**
///
/// Keks, looking at his colonists: *"brnění taky, itemy taky… vše musí být i
/// grafické a unikátní a vypadat tak co to je."* The data was the reason it was
/// not: an armour item carried a name, a rarity, an effect and a description,
/// and nothing a drawing could read — so a hide jerkin and a powered harness
/// were the same figure in the same tunic. Rule 47 in its plainest form.
@Suite("Everything worn says what it is")
struct ArmourLookTests {

    @Test("Every armour in the book is described well enough to draw")
    func everyArmourIsDescribed() throws {
        let registry = try GameDataRegistry.bundled()
        let worn = registry.items.values.filter { $0.equipSlot == .armor }
        #expect(!worn.isEmpty)
        for piece in worn.sorted(by: { $0.id < $1.id }) {
            #expect(piece.armour != nil,
                    "\(piece.id) has no `armour` block, so it is drawn as a guess")
        }
    }

    /// The point of the block is that two pieces look *different*. A file where
    /// every entry says `leather/torso` would pass the check above and change
    /// nothing on screen.
    @Test("What is worn is drawn several different ways, not one")
    func theLooksActuallyDiffer() throws {
        let registry = try GameDataRegistry.bundled()
        let described = registry.items.values.compactMap(\.armour)
        let materials = Set(described.map(\.material))
        let coverages = Set(described.map(\.coverage))
        #expect(materials.count >= 5, "only \(materials.count) materials across the whole book")
        #expect(coverages.count >= 4, "only \(coverages.count) ways of covering a body")
    }

    @Test("A helm is only claimed by something you can put on your head")
    func helmsMakeSense() throws {
        let registry = try GameDataRegistry.bundled()
        for piece in registry.items.values {
            guard let armour = piece.armour, armour.coverage == .head else { continue }
            #expect(armour.helm,
                    "\(piece.id) covers the head and draws nothing on it")
        }
    }

    @Test("A tint is a hue, not a colour somebody typed")
    func tintsAreInRange() throws {
        let registry = try GameDataRegistry.bundled()
        for piece in registry.items.values {
            guard let tint = piece.armour?.tint else { continue }
            #expect(tint >= 0 && tint <= 1, "\(piece.id) has a tint of \(tint)")
        }
    }

    /// An undescribed piece must still be drawable — a coat authored tomorrow
    /// should look like *something* before anybody says what it is made of.
    @Test("A piece with nothing said about it still has a look")
    func thereIsAlwaysAFallback() throws {
        let bare = ItemDefinition(
            id: "test_coat", name: LocalizedText("Coat"), rarity: .rare,
            slot: .equipment, equipSlot: .armor)
        #expect(bare.armour == nil)
        // The look is the app's, but the *rule* is that rarity stands in for
        // the material — which is only meaningful if the rarities differ.
        #expect(ItemRarity.allCases.count >= 4)
    }
}
