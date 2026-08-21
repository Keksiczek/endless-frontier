import SwiftUI
import EndlessFrontierCore

/// **What makes one kind of building look unlike another kind that shares its
/// archetype.**
///
/// Twenty-three of the fifty-three buildings share a `look` with something
/// else: `factory`, `vehicle_works`, `assembly_plant`, `automated_factory` and
/// `garage` are all `plant`; `library`, `school` and `university` are all
/// `hall`. The renderer drew each bucket once, so five different industries
/// were one smoking block repeated, and a player could not tell the place that
/// builds lorries from the place that builds everything else.
///
/// The tempting fix is seventeen more `case`s and seventeen more drawings. That
/// is the plan `docs/HANDOFF-GENERATION.md` warns against — sixty hand-drawn
/// vehicles, one layer up. The fix that scales is **composition**: the glyph
/// says what shape the thing is, and this says how *this kind* of it is put
/// together.
///
/// Every field is derived from the definition, so the difference is meaningful
/// rather than random — a smoky works really has more chimneys than a clean
/// one, a place that houses lorries really has a door a lorry fits through, and
/// a building nobody works at night is dark at night. `kindSeed` breaks the
/// remaining ties, and is a hash of the **id**, so all four foundries in a town
/// agree with each other and differ from all four garages.
struct StructureVariant: Equatable, Hashable {
    /// How the top of the building is closed off.
    enum Roofline: String, CaseIterable {
        case gable      // a pitched roof — everything before the machines
        case sawtooth   // north-light glazing: the industrial workshop
        case flat       // the modern block
        case barrel     // a curved shell, late
        case stepped    // a ziggurat of storeys, for what stacks
    }

    /// What stands on top of it.
    enum Rooftop: String, CaseIterable {
        case none
        case vents      // it burns or cooks something
        case array      // it makes power
        case aerial     // it listens, teaches or governs
        case tank       // it holds something liquid
    }

    /// Stable per **kind**, so two definitions never collide and two instances
    /// of one definition always agree.
    let kindSeed: UInt64
    /// Openings across the front. Wider ground, more of them.
    let bays: Int
    /// Chimneys, flues, cooling stacks — what the work sends up.
    let stacks: Int
    /// A door a cart or a lorry fits through, rather than a person's door.
    let wideDoor: Bool
    let roofline: Roofline
    let rooftop: Rooftop
    /// Lights on after dark. A building with no posted workers is dark.
    let nightShift: Bool
    /// How substantial it is, 0…3, from what it cost to raise. A university is
    /// a bigger building than a library and looks it.
    let tier: Int
    /// How stoutly it is built, 0…3, from `defense` — the difference between a
    /// line of stakes and a rampart with a parapet.
    let heft: Int
    /// The most of what it holds, if it is a store. A granary keeps sacks on a
    /// raised floor; a warehouse stacks crates against a loading door.
    let stores: ResourceType?
    /// How many storeys stand up.
    ///
    /// `SettlementStructures.building` has taken `floors:` and drawn them since
    /// §2.3, and the signature did not know — so a one-storey longhouse and a
    /// two-storey courtyard house came out with the same signature while the
    /// canvas drew them differently. The guard was quietly weaker than the
    /// drawing. **An axis the drawing reads belongs in here**, which is the
    /// whole contract `signature` is for.
    let storeys: Int

    /// The fallback for a building the registry does not know — a definition
    /// that has been deleted from under a save, or a test with a bare registry.
    static let plain = StructureVariant(
        kindSeed: 0, bays: 3, stacks: 0, wideDoor: false,
        roofline: .gable, rooftop: .none, nightShift: false,
        tier: 0, heft: 0, stores: nil, storeys: 1)

    // MARK: - Derivation

    /// Everything below reads the definition and nothing else, so the same
    /// building always looks like itself — across frames, launches and saves.
    static func of(_ def: BuildingDefinition, housesConveyances: Bool) -> StructureVariant {
        let seed = kindSeed(for: def.id)
        return StructureVariant(
            kindSeed: seed,
            bays: bays(def),
            stacks: stacks(def, seed),
            wideDoor: housesConveyances,
            roofline: roofline(def, seed),
            rooftop: rooftop(def),
            nightShift: def.workers > 0,
            tier: bucket(price(def), [40, 120, 320]),
            heft: bucket(def.defense, [1, 20, 60]),
            stores: mostOf(def.storage),
            storeys: max(1, def.floors))
    }

    /// The most of what a store holds. `Resources` is a bag keyed by kind, not
    /// a dictionary, so ask it for each kind rather than reaching for `max`.
    private static func mostOf(_ store: Resources) -> ResourceType? {
        ResourceType.allCases
            .filter { store[$0] > 0 }
            .max { store[$0] < store[$1] }
    }

    /// What a building is worth, counting the worked materials at twice the raw
    /// ones — a brick is a fired clay plus the firing.
    private static func price(_ def: BuildingDefinition) -> Double {
        ResourceType.allCases.reduce(0) { $0 + def.cost[$1] }
            + Double(def.materialCost.values.reduce(0, +)) * 2
    }

    /// Which band a number falls in. Bands rather than the number itself,
    /// because the drawing wants "a big one" and not two decimal places.
    private static func bucket(_ value: Double, _ thresholds: [Double]) -> Int {
        for (i, t) in thresholds.enumerated() where value < t { return i }
        return thresholds.count
    }

    /// FNV-1a over the id. Any stable hash would do; `String.hashValue` would
    /// not — Swift seeds it per process, so a building would change its own
    /// roof between launches.
    static func kindSeed(for id: String) -> UInt64 {
        var h: UInt64 = 0xCBF2_9CE4_8422_2325
        for byte in id.utf8 {
            h ^= UInt64(byte)
            h = h &* 0x0000_0100_0000_01B3
        }
        return h
    }

    /// Openings across the front: the ground it covers decides the range, the
    /// kind decides where in that range it sits.
    /// Openings across the front, from the ground it covers.
    ///
    /// There was a coin toss on the end of this to break ties. It *made* one:
    /// a 2-wide palisade winning the toss and a 3-wide stone wall losing it
    /// came out with the same five bays. A meaningful axis beats a random one
    /// every time — the ties are broken by `tier`, `heft` and `stores`, all of
    /// which say something true about the building.
    private static func bays(_ def: BuildingDefinition) -> Int {
        2 + max(1, def.footprint.width)
    }

    /// What the work sends up. A clean industry has none, however large it is —
    /// which is the whole difference between a foundry and a fusion reactor.
    private static func stacks(_ def: BuildingDefinition, _ seed: UInt64) -> Int {
        guard def.pollution > 0 || def.consumption[.materials] > 0 else { return 0 }
        let smoke = def.pollution + def.consumption[.materials] * 0.25
        let count = 1 + Int(min(3, smoke.rounded(.down)))
        return count + Int((seed >> 11) % 2)
    }

    /// The era says what a roof *can* be; what the building does picks from it.
    private static func roofline(_ def: BuildingDefinition, _ seed: UInt64) -> Roofline {
        // Storeys stack, so a tall building steps back as it rises whatever
        // else it is.
        if def.floors >= 4 { return .stepped }
        switch def.era {
        case .earlySettlement, .ancient, .medieval:
            return .gable
        case .earlyIndustrial:
            // A works wants light on the bench; a hall or a store does not.
            return def.workers >= 3 ? .sawtooth : .gable
        case .modern:
            return (seed >> 17) % 3 == 0 ? .sawtooth : .flat
        case .nearFuture:
            return (seed >> 19) % 2 == 0 ? .barrel : .flat
        }
    }

    /// What stands on the roof, in the order a building would have paid for it.
    private static func rooftop(_ def: BuildingDefinition) -> Rooftop {
        if def.production[.energy] > 0 { return .array }
        if def.storage[.food] > 0 && def.era >= .earlyIndustrial { return .tank }
        if def.production[.knowledge] > 0 || def.production[.influence] > 0 { return .aerial }
        if def.pollution > 0 || def.work == .cooking { return .vents }
        return .none
    }

    /// A signature that stands in for "what this building looks like", so a
    /// test can say that no two kinds are drawn identically without rendering
    /// anything. Anything that changes the drawing belongs in here.
    var signature: String {
        [String(bays), String(stacks), wideDoor ? "1" : "0",
         roofline.rawValue, rooftop.rawValue, nightShift ? "1" : "0",
         "t\(tier)", "h\(heft)", stores?.rawValue ?? "-",
         "f\(storeys)"].joined(separator: "/")
    }
}

extension StructureVariant {
    /// The buildings a conveyance is kept or built at — the ones that need a
    /// door a cart fits through. Read from `conveyances.json` rather than
    /// listed here, so a new vehicle brings its own shed with it.
    static func conveyanceHomes(_ registry: GameDataRegistry) -> Set<String> {
        Set(registry.conveyances.values.compactMap(\.requiresBuilding))
    }
}
