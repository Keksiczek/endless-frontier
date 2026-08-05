import Testing
import Foundation
@testable import EndlessFrontierCore

/// Winter has to actually bite, and the things that keep it out have to
/// actually keep it out. This is the recurring bug shape in this codebase — a
/// threshold beyond the reach of the rate meant to cross it — so the reachable
/// cases are pinned first.
@Suite("Cold, and what keeps it out")
struct ComfortTests {

    private func registry() -> GameDataRegistry {
        GameDataRegistry(
            buildings: [
                BuildingDefinition(id: "hut", era: .earlySettlement, name: "Hut",
                                   cost: [.materials: 10], housing: 8)
            ],
            techs: [], eras: [], biomes: [], events: [], config: .default)
    }

    @Test("A person out in a hard winter with nothing is in real trouble")
    func winterIsReachable() {
        let bare = ComfortEngine.target(season: .winter, housed: false,
                                        clothing: 0, shelter: 0)
        #expect(bare < ComfortEngine.freezingBelow,
                "winter must be able to hurt someone with nothing: \(bare)")
    }

    // MARK: - The land has weather of its own

    /// A biome that does not change the weather is a colour. Temperature was a
    /// four-case switch on `Season`, so a tundra valley in January was exactly
    /// as cold as a coastal one — the map said "tundra" and the body did not
    /// agree.
    @Test("Where you settle decides how hard the winter is")
    func theLandChangesTheWeather() throws {
        let reg = try GameDataRegistry.bundled()
        let tundra = try #require(reg.biome("tundra")).climate
        let coast = try #require(reg.biome("coast")).climate
        #expect(tundra.temperature(.winter) < coast.temperature(.winter) - 10)
        #expect(try #require(reg.biome("desert")).climate.temperature(.summer)
                > coast.temperature(.summer))
    }

    /// The point of choosing a tundra: a hard winter is dangerous even to
    /// somebody who did everything right.
    @Test("A tundra winter reaches past a roof and a coat")
    func tundraBitesThroughShelter() throws {
        let reg = try GameDataRegistry.bundled()
        let tundra = try #require(reg.biome("tundra")).climate
        let sheltered = ComfortEngine.target(
            season: .winter, housed: true, clothing: 1,
            shelter: ComfortEngine.maxHearthWarmth, climate: tundra)
        let temperate = ComfortEngine.target(
            season: .winter, housed: true, clothing: 1,
            shelter: ComfortEngine.maxHearthWarmth)
        #expect(sheltered < temperate,
                "a tundra has to be colder than the middling country")
        #expect(sheltered < ComfortEngine.freezingBelow + 25,
                "…and close enough to the bone to be worth the choice: \(sheltered)")
    }

    /// One number, read by both. A colonist freezing in a valley where the deer
    /// are comfortable is two switch statements that stopped agreeing (rule 8).
    @Test("People and beasts read the same thermometer")
    func oneThermometer() throws {
        let reg = try GameDataRegistry.bundled()
        let tundra = try #require(reg.biome("tundra")).climate
        for season in [Season.spring, .summer, .autumn, .winter] {
            #expect(AnimalEngine.temperature(season, climate: tundra)
                    == ComfortEngine.reckon(season: season, housed: false, clothing: 0,
                                            shelter: 0, climate: tundra).outside)
        }
    }

    /// The other half of "it is cosmetic": every term was computed and none was
    /// ever shown, so a player could not tell a coat from a roof from a valley.
    @Test("The card can say why somebody is cold")
    func theReckoningAddsUp() {
        let r = ComfortEngine.reckon(season: .winter, housed: true, clothing: 2,
                                     shelter: 14, climate: Climate(shift: -13))
        #expect(r.outside == Climate.base(.winter) - 13)
        #expect(r.roof == ComfortEngine.shelterWarmth)
        #expect(r.clothes == 2 * ComfortEngine.clothingWarmth)
        #expect(r.fires == 14)
        #expect(r.weather < 0)
        #expect(abs(r.warmth - min(100, max(0, 100 + r.weather + r.roof + r.clothes + r.fires)))
                < 1e-9)
    }

    @Test("A summer day gives nothing back for a roof — there is nothing to keep out")
    func summerHasNoShelterTerm() {
        let r = ComfortEngine.reckon(season: .summer, housed: true, clothing: 2, shelter: 20)
        #expect(r.roof == 0 && r.clothes == 0 && r.fires == 0)
    }

    @Test("A biome written before the land had weather is middling country")
    func oldBiomesDecode() throws {
        let old = #"{"id":"plains","name":{"en":"Plains","cs":"Pláně"}}"#.data(using: .utf8)!
        let biome = try JSONDecoder().decode(BiomeDefinition.self, from: old)
        #expect(biome.temperatureShift == 0)
        #expect(biome.climate == .temperate)
    }

    @Test("A roof, a coat and a fire between them make winter survivable")
    func shelterWorks() {
        let sheltered = ComfortEngine.target(season: .winter, housed: true,
                                             clothing: 2,
                                             shelter: ComfortEngine.maxHearthWarmth)
        #expect(sheltered > ComfortEngine.freezingBelow,
                "a housed, clothed colonist by a fire should not be freezing: \(sheltered)")
    }

    @Test("Summer is comfortable for everyone")
    func summerIsFine() {
        for housed in [true, false] {
            #expect(ComfortEngine.target(season: .summer, housed: housed,
                                         clothing: 0, shelter: 0) > 60)
        }
    }

    @Test("Cold costs health, and warmth does not")
    func exposureHurts() {
        var cold = Pawn(name: "Out", needs: PawnNeeds(warmth: 0), health: 100)
        var warm = Pawn(name: "In", needs: PawnNeeds(warmth: 90), health: 100)
        for _ in 0..<20 {
            cold = ComfortEngine.advanceOneTick(cold, season: .winter, shelter: 0)
            warm = ComfortEngine.advanceOneTick(warm, season: .summer, shelter: 0)
        }
        #expect(cold.health < 100)
        #expect(warm.health == 100)
    }

    @Test("Warmth settles toward what the day offers rather than jumping")
    func warmthIsGradual() {
        var pawn = Pawn(name: "Cools", needs: PawnNeeds(warmth: 100))
        let after = ComfortEngine.advanceOneTick(pawn, season: .winter, shelter: 0)
        #expect(after.needs.warmth < 100)
        #expect(after.needs.warmth > 50, "one tick should not strip a whole winter's worth")
        // …and it keeps going.
        pawn = after
        for _ in 0..<60 { pawn = ComfortEngine.advanceOneTick(pawn, season: .winter, shelter: 0) }
        #expect(pawn.needs.warmth < ComfortEngine.freezingBelow)
    }

    @Test("A colony with houses and forges keeps its people warmer")
    func firesCount() {
        var bare = Settlement(id: UUID(), name: "Bare", regionID: UUID())
        var warm = bare
        warm.buildings = [BuildingInstance(definitionID: "hut", count: 3)]
        #expect(ComfortEngine.shelter(warm, registry: registry())
                > ComfortEngine.shelter(bare, registry: registry()))
        bare.buildings = []
        #expect(ComfortEngine.shelter(bare, registry: registry()) == 0)
    }

    @Test("Warmth is one of the needs mood is made of")
    func moodFeelsTheCold() {
        let cold = Pawn(name: "A", needs: PawnNeeds(hunger: 80, rest: 80,
                                                    recreation: 80, warmth: 5))
        let warm = Pawn(name: "B", needs: PawnNeeds(hunger: 80, rest: 80,
                                                    recreation: 80, warmth: 90))
        #expect(cold.needs.average < warm.needs.average)
    }

    @Test("The ledger says why, not just how much")
    func moodHasReasons() {
        let miserable = Pawn(name: "Cold and homeless",
                             trait: .pessimist,
                             needs: PawnNeeds(hunger: 20, rest: 30,
                                              recreation: 40, warmth: 10),
                             homeID: nil)
        let factors = MoodLedger.factors(for: miserable, registry: registry())
        #expect(factors.contains { $0.id == "roofless" })
        #expect(factors.contains { $0.id == "warmth" && $0.amount < 0 })
        #expect(factors.contains { $0.id == "hunger" && $0.amount < 0 })
        #expect(factors.contains { $0.id == "trait" })
        // Biggest reason first — that is the whole use of the list.
        #expect(abs(factors[0].amount) >= abs(factors[factors.count - 1].amount))
    }

    @Test("A contented colonist's reasons are the good ones")
    func goodMoodsHaveReasonsToo() {
        let happy = Pawn(name: "Snug", needs: PawnNeeds(hunger: 95, rest: 95,
                                                        recreation: 90, warmth: 95),
                         homeID: UUID())
        let factors = MoodLedger.factors(for: happy, registry: registry())
        #expect(!factors.isEmpty)
        #expect(factors.allSatisfy { $0.amount > 0 })
    }

    @Test("A save written before warmth decodes warm rather than frozen")
    func oldSavesAreNotFrozen() throws {
        let json = #"{"hunger":80,"rest":80,"recreation":70}"#
        let needs = try JSONDecoder().decode(PawnNeeds.self, from: Data(json.utf8))
        #expect(needs.warmth == 80)
    }
}
