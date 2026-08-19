import Foundation

/// **The yard.** What the colony builds to move things with, what keeping it
/// costs, and how it is lost.
///
/// Step two of `docs/MOUNTS_AND_VEHICLES.md`. Deliberately only this much: a
/// conveyance can be made, kept and lost, and nothing yet moves any faster.
/// The four seams that make it *felt* — pace on the local map, cargo in the
/// haul, and the two roads — come next, each with its own conversion, because
/// one multiplier applied to two different units is rule 34 waiting to happen.
///
/// Deterministic like the rest: every roll is seeded from
/// `(mapSeed, settlementID, tick)`, and every id is derived rather than fresh
/// (rule 3).
public enum StableEngine {

    /// How much of its condition a cart loses per tick just by existing.
    ///
    /// A cart in daily use is worn out in about sixty years of game time,
    /// which at two real minutes a tick is a long campaign — long enough that
    /// replacing one is an event rather than a chore, and short enough that a
    /// colony which stops maintaining its yard notices.
    public static let wearPerTick: Double = 1.0 / (60 * 60)

    /// Below this a cart is scrap. Not zero: a thing falls apart before it
    /// reaches nothing, and a conveyance that vanishes at exactly 0 reads as a
    /// number running out rather than as a cart breaking.
    public static let scrapBelow: Double = 0.08

    /// The most conveyances one colony keeps, so a steward left alone cannot
    /// fill the valley with carts (rule 15: an autonomous order is priced
    /// differently from a tap).
    public static let yardLimit = 24

    // MARK: - Making one

    /// Whether this colony could build one right now: the era has come, the
    /// shop stands, the knowledge exists, and the materials are on the pile.
    public static func canBuild(
        _ definitionID: String, in state: WorldState, settlement: Settlement,
        registry: GameDataRegistry
    ) -> Bool {
        guard settlement.conveyances.count < yardLimit,
              let def = registry.conveyance(definitionID),
              def.era.index <= state.era.index
        else { return false }
        if let building = def.requiresBuilding,
           !settlement.buildings.contains(where: { $0.definitionID == building }) {
            return false
        }
        if let tech = def.requiresTech, !state.researchedTechs.contains(tech) { return false }
        // A mount needs a beast already gentled and not already carrying
        // somebody — you do not build a horse.
        if def.kind == .mount {
            guard freeBeast(for: def, in: settlement) != nil else { return false }
        }
        let held = CraftingEngine.materialCounts(settlement)
        return def.materials.allSatisfy { (held[$0.key] ?? 0) >= $0.value }
    }

    /// A tamed beast of the right species that is not already somebody's mount.
    static func freeBeast(
        for def: ConveyanceDefinition, in settlement: Settlement
    ) -> TamedAnimal? {
        let taken = Set(settlement.conveyances.compactMap(\.animalID))
        return settlement.tamed
            .filter { beast in
                guard !taken.contains(beast.id), beast.animal.isAlive else { return false }
                guard let wanted = def.requiresAnimal else { return false }
                return beast.animal.species.rawValue == wanted
            }
            .min { $0.id.uuidString < $1.id.uuidString }
    }

    /// Builds one, spending the materials. Returns the settlement unchanged
    /// when it cannot.
    public static func build(
        _ settlement: Settlement, definitionID: String, in state: WorldState,
        registry: GameDataRegistry
    ) -> Settlement {
        guard canBuild(definitionID, in: state, settlement: settlement, registry: registry),
              let def = registry.conveyance(definitionID)
        else { return settlement }
        var s = settlement
        for (materialID, count) in def.materials.sorted(by: { $0.key < $1.key }) {
            s.stockpile[materialID] = max(0, (s.stockpile[materialID] ?? 0) - count)
        }
        let beast = def.kind == .mount ? freeBeast(for: def, in: s) : nil
        if let beast, let i = s.tamed.firstIndex(where: { $0.id == beast.id }) {
            s.tamed[i].role = .mount
        }
        s.conveyances.append(Conveyance(
            id: conveyanceID(settlementID: s.id, definitionID: definitionID,
                             tick: state.tick, ordinal: s.conveyances.count),
            definitionID: definitionID,
            animalID: beast?.id,
            madeAtTick: state.tick))
        s.journal.append(tick: state.tick, kind: .construction, text: LocalizedText(values: [
            .en: "The colony has a \(def.name.resolve(.en).lowercased()).",
            .cs: "Osada má \(def.name.resolve(.cs).lowercased())."]))
        return s
    }

    // MARK: - Keeping them

    /// One tick of the yard: upkeep is paid, carts wear, and what cannot be
    /// kept is lost.
    ///
    /// A mount's *food* is `TamingEngine`'s to take — the beast is in `tamed`
    /// and eats there whether or not anybody rides it. This takes only what the
    /// conveyance itself costs on top, which for a horse is nothing and for a
    /// truck is fuel.
    public static func advanceOneTick(
        _ settlement: Settlement, in state: WorldState, registry: GameDataRegistry
    ) -> Settlement {
        guard !settlement.conveyances.isEmpty else { return settlement }
        var s = settlement
        let alive = Set(s.tamed.filter { $0.animal.isAlive }.map(\.id))
        var kept: [Conveyance] = []

        for var thing in s.conveyances {
            guard let def = registry.conveyance(thing.definitionID) else {
                // A conveyance whose definition has gone is not silently kept:
                // it would be a row nothing can read, which is the failure this
                // repository keeps paying for.
                continue
            }
            // A mount is its beast. When the beast dies or walks back into the
            // woods, the saddle is not a mount any more.
            if let animalID = thing.animalID, !alive.contains(animalID) {
                s.journal.append(tick: state.tick, kind: .death, text: LocalizedText(values: [
                    .en: "The colony is without its \(def.name.resolve(.en).lowercased()).",
                    .cs: "Osada přišla o \(def.name.resolve(.cs).lowercased())."]))
                continue
            }
            // What it costs to keep on top of feeding the beast — fuel, mostly.
            var short = false
            for resource in ResourceType.allCases {
                let due = def.upkeep[resource]
                guard due > 0 else { continue }
                if s.storage[resource] >= due {
                    s.storage[resource] -= due
                } else {
                    short = true
                }
            }
            // Wheels wear; a beast does not, because its body already does.
            if !thing.isMount {
                // Something that cannot be fuelled is not driven, and something
                // that is not driven does not wear. It simply does nothing,
                // which is the right punishment for a fuel shortage.
                thing.condition -= short ? 0 : wearPerTick
            }
            guard thing.condition > scrapBelow else {
                s.journal.append(tick: state.tick, kind: .work, text: LocalizedText(values: [
                    .en: "The \(def.name.resolve(.en).lowercased()) has been broken up for what was left of it.",
                    .cs: "\(def.name.resolve(.cs)) rozebrali na to, co z něj zbylo."]))
                continue
            }
            kept.append(thing)
        }
        s.conveyances = kept
        return s
    }

    // MARK: - Reading the yard

    /// The best pace the colony can put a body on, on its own map — 1 when it
    /// has nothing, which is walking.
    ///
    /// This is the number the local-map seam will multiply by. It is here
    /// rather than at the seam so there is one place that answers "what can
    /// this colony move at", and so that place is testable before anything
    /// reads it.
    public static func bestPace(
        _ settlement: Settlement, registry: GameDataRegistry
    ) -> Double {
        settlement.conveyances
            .compactMap { registry.conveyance($0.definitionID)?.pace }
            .max() ?? 1
    }

    /// …and the same for the road between settlements.
    public static func bestRegionPace(
        _ settlement: Settlement, registry: GameDataRegistry
    ) -> Double {
        settlement.conveyances
            .compactMap { registry.conveyance($0.definitionID)?.regionPace }
            .max() ?? 1
    }

    /// How much more than their own backs the colony's carriers can move,
    /// counting every conveyance in the yard.
    public static func cargoCapacity(
        _ settlement: Settlement, registry: GameDataRegistry
    ) -> Int {
        settlement.conveyances
            .compactMap { registry.conveyance($0.definitionID)?.cargo }
            .reduce(0, +)
    }

    /// The most a yard may add to how fast the colony's carriers move.
    ///
    /// The same shape and the same reason as `TamingEngine.bonuses`, which caps
    /// its pack-animal `haul` at 0.6: a colony that fills its yard should be
    /// noticeably quicker and not teleport. Rule 14 — this is multiplied by
    /// nothing, but it *stacks*, and a stack with no ceiling is the same fault.
    public static let maximumHaulLift: Double = 0.8

    /// What the yard adds to every hauler's pace, as a bonus to add to 1.
    ///
    /// Colony-wide rather than per colonist, following the precedent already
    /// in `HaulEngine`: the beasts of burden make *every* carrier quicker
    /// because the colony's carrying is a shared effort, not a queue for one
    /// mule. A cart standing in the yard is a cart anybody may take.
    ///
    /// Weighted by condition, so a yard of wrecks is worth less than a yard —
    /// and by `cargo` rather than `pace`, because what a cart does for hauling
    /// is carry more per trip, and this is where "more per trip" lands until
    /// a load has a size of its own (see `docs/MOUNTS_AND_VEHICLES.md`).
    public static func haulLift(
        _ settlement: Settlement, registry: GameDataRegistry
    ) -> Double {
        guard !settlement.conveyances.isEmpty else { return 0 }
        let total = settlement.conveyances.reduce(0.0) { sum, thing in
            guard let def = registry.conveyance(thing.definitionID) else { return sum }
            let soundness = thing.isMount ? 1 : max(0, thing.condition)
            return sum + Double(def.cargo) * 0.05 * soundness
        }
        return min(maximumHaulLift, total)
    }

    /// Whether the colony can get a load across a given ground at all — the
    /// field that stops the whole system being an upgrade ladder.
    public static func canCross(
        _ cover: GroundCover, _ settlement: Settlement, registry: GameDataRegistry
    ) -> Bool {
        settlement.conveyances.contains {
            registry.conveyance($0.definitionID)?.canCross(cover) ?? false
        }
    }

    // MARK: - Ids

    /// Derived, never fresh. The same colony building the same thing on the
    /// same tick gets the same id in every run, which is what determinism
    /// rests on (rule 3 — a random `UUID()` here would drift every launch).
    static func conveyanceID(
        settlementID: UUID, definitionID: String, tick: Int, ordinal: Int
    ) -> UUID {
        var h: UInt64 = 0xCBF2_9CE4_8422_2325
        for byte in [settlementID.uuid.0, settlementID.uuid.3, settlementID.uuid.7,
                     settlementID.uuid.11, settlementID.uuid.15] {
            h = (h ^ UInt64(byte)) &* 0x0100_0000_01B3
        }
        for scalar in definitionID.unicodeScalars {
            h = (h ^ UInt64(scalar.value)) &* 0x0100_0000_01B3
        }
        h = (h ^ UInt64(bitPattern: Int64(tick))) &* 0x0100_0000_01B3
        h = (h ^ UInt64(bitPattern: Int64(ordinal))) &* 0x0100_0000_01B3
        let low = h ^ (h >> 31)
        var bytes = [UInt8]()
        for shift in stride(from: 56, through: 0, by: -8) {
            bytes.append(UInt8((h >> UInt64(shift)) & 0xFF))
        }
        for shift in stride(from: 56, through: 0, by: -8) {
            bytes.append(UInt8((low >> UInt64(shift)) & 0xFF))
        }
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3],
                           bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11],
                           bytes[12], bytes[13], bytes[14], bytes[15]))
    }
}
