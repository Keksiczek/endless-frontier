import Testing
import Foundation
@testable import EndlessFrontierCore

/// Wounds you can read.
///
/// Keks, after a fight: *"se souboji by se možná hodilo víc popisů zranění a
/// typu, jako v RimWorldu."* The body already knew a blow landed on the left
/// arm and how badly — combat has gone through `MedicineEngine.wound` for a
/// while — but it could not say **what kind of blow**, so a wolf's bite and a
/// spear through the shoulder both read as "Left arm".
@Suite("A wound says what made it")
struct WoundKindTests {

    private func id(_ n: Int) -> UUID {
        UUID(uuidString: String(format: "0D0D0D0D-0000-0000-0000-%012d", n))!
    }

    @Test("A blow leaves a wound of some named kind")
    func everyWoundHasAKind() {
        var rng = SeededRNG(seed: 7)
        var pawn = Pawn(id: id(1), name: "Rarun")
        pawn = MedicineEngine.wound(pawn, amount: 20, tick: 5, rng: &rng)
        let wound = pawn.body.ailments.first
        #expect(wound?.wound != nil, "a blow landed and nothing says what made it")
        #expect(wound?.part != nil, "and nothing says where")
    }

    /// The name has to *do* something, or it is decoration: a stab is what
    /// kills somebody an hour after the fighting stopped and a bruise is what
    /// they walk off.
    @Test("What made a wound decides how it bleeds")
    func kindChangesTheBleeding() {
        func rate(_ kind: WoundKind) -> Double {
            Ailment(id: id(2), kind: .wound, part: .torso,
                    severity: 0.5, wound: kind).bleedRate
        }
        #expect(rate(.stab) > rate(.cut))
        #expect(rate(.cut) > rate(.burn))
        #expect(rate(.burn) > rate(.bruise))
        #expect(rate(.bruise) > 0, "a bruise that does nothing is not an injury")
        // Tending still stops it, whatever made it.
        for kind in WoundKind.allCases {
            #expect(Ailment(id: id(3), kind: .wound, part: .torso, severity: 0.9,
                            tended: true, wound: kind).bleedRate == 0)
        }
    }

    @Test("A beast leaves bites and a warband does not")
    func theAttackerDecidesTheWound() throws {
        let registry = try GameDataRegistry.bundled()

        func woundsFrom(tribe: UUID?) throws -> [WoundKind] {
            var settlement = Settlement(
                id: id(4), name: "Wallside", storage: [.food: 800], storageCapacity: .uniform(2000))
            settlement.pawns = (0..<10).map {
                Pawn(id: UUID(uuidString: String(format: "0D0D0D0D-0000-0000-0001-%012d", $0))!,
                     name: "Hand \($0)")
            }
            settlement.siege = Siege(
                id: id(5), startTick: 0, openedAt: 0, attackerName: "Whoever",
                attackerTribeID: tribe, approach: 0, attackers: 14,
                openingStrength: 50, fortification: 4, seed: 0xBEEF,
                line: settlement.pawns.map(\.id))
            for step in 1...Siege.stepsTotal {
                settlement = SiegeEngine.advance(settlement, to: step, registry: registry)
            }
            return settlement.pawns.flatMap { $0.body.ailments.compactMap(\.wound) }
        }

        let bitten = try woundsFrom(tribe: nil)                 // wolves
        let cut = try woundsFrom(tribe: id(6))                  // people
        #expect(!bitten.isEmpty, "nobody was hurt, so nothing is being tested")
        #expect(bitten.allSatisfy { $0 == .bite }, "a wolf pack left something other than bites")
        #expect(!cut.contains(.bite), "a warband bit somebody")
        #expect(Set(cut).count > 1, "every blow from a warband was the same kind")
    }

    @Test("A card can name the wound and the place in one line")
    func theTitleReadsAsASentence() {
        let stab = Ailment(id: id(7), kind: .wound, part: .leftArm,
                           severity: 0.5, wound: .stab)
        #expect(stab.title.resolve(.en) == "Stab — left arm")
        #expect(stab.title.resolve(.cs) == "Bodná rána — levá paže")
        // Something with no edge and nowhere in particular still reads.
        let ill = Ailment(id: id(8), kind: .sickness, severity: 0.3)
        #expect(ill.title.resolve(.cs) == "Nemoc")
    }

    @Test("A wound saved before anybody asked what made it still loads")
    func oldSavesDecode() throws {
        let wound = Ailment(id: id(9), kind: .wound, part: .head, severity: 0.4)
        var data = try JSONSerialization.jsonObject(
            with: JSONEncoder().encode(wound)) as? [String: Any] ?? [:]
        data.removeValue(forKey: "wound")
        let back = try JSONDecoder().decode(
            Ailment.self, from: JSONSerialization.data(withJSONObject: data))
        #expect(back.wound == nil)
        // …and bleeds at exactly the rate it always did.
        #expect(back.bleedRate == 0.4 * Body.bleedPerSeverity)
    }
}
