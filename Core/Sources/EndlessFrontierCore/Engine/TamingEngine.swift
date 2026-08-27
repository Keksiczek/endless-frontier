import Foundation

/// Beasts that work for you.
///
/// The wild became pawns — bodies, wounds, a small mind, a place on the map —
/// and stayed food. Every animal in the valley was something to shoot. But a
/// colony's relationship with animals is older and more interesting than that:
/// you feed one until it stops running, and then it hauls your timber, guards
/// your gate, or gives you something every spring without dying for it.
///
/// Taming is a slow, uncertain thing done by hand. A colonist works at a beast
/// over many visits; how likely it is to come round depends on what it is — a
/// hare is nearly hopeless and a boar can be bribed — and on how badly the
/// colony has been treating it. A tamed animal then belongs to the settlement:
/// it eats, it works, it can be hurt, and if it is hungry or badly used it can
/// turn back to the wild or on the hand that feeds it.
///
/// Deterministic, on a cadence, and cheap: one pass over a handful of beasts.
public enum TamingEngine {

    /// How often taming work is resolved, in ticks.
    public static let interval = 10
    /// How much progress one tamer makes per pass, before the species has its
    /// say. A beast takes a season of visits, not an afternoon.
    public static let workPerTamer: Double = 0.06
    /// A tamed animal eats this much of the colony's food per tick.
    public static let feedPerTick: Double = 0.05
    /// Below this share of its own health, a hungry animal starts to go wild
    /// again.
    public static let neglectBelow: Double = 0.45
    /// The most beasts a colony keeps. A farmyard, not a menagerie.
    public static let maxTamed = 8

    /// How willing a species is to be tamed at all, 0…1 per pass of work.
    ///
    /// This is what makes taming a *choice*: a boar is worth the season it
    /// costs, a bear is a long shot that pays for itself at the gate, and
    /// nobody sane spends a winter on a hare.
    public static func wildness(_ species: String, registry: GameDataRegistry) -> Double {
        registry.beast(species)?.tameability ?? 0.4
    }

    /// What a tamed beast of this kind is *for*.
    public static func calling(_ species: String, registry: GameDataRegistry) -> TamedRole {
        registry.beast(species)?.role ?? .companion
    }

    // MARK: - Working at it

    /// One pass of taming: the colonists who keep animals work at the nearest
    /// wild beast, and one of them may come round.
    public static func advanceOneTick(
        _ settlement: Settlement, registry: GameDataRegistry, tick: Int, mapSeed: UInt64
    ) -> Settlement {
        guard tick % interval == 0, let map = settlement.localMap,
              map.wildlife.usesEntities else { return settlement }

        let ticksPerYear = max(1, registry.config.ticksPerYear)
        // Whoever is out among the animals is the one who gentles them. A colony
        // with no hunters tames nothing, which is the right answer: taming is
        // something you do because you are already out there.
        let tamers = settlement.pawns.count {
            $0.assignedWork == .hunting && $0.isAdult(ticksPerYear: ticksPerYear)
                && !$0.isBroken && !$0.isAway && $0.body.canWork
        }
        guard tamers > 0 else { return settlement }
        guard settlement.tamed.count < maxTamed else { return settlement }

        var s = settlement
        var updated = map
        var rng = SeededRNG(seed: tameSeed(mapSeed: mapSeed, settlementID: s.id, tick: tick))

        // The likeliest beast: nearest the town, and the most biddable of those.
        let heart = SettlementGeometry.heart
        guard let index = updated.wildlife.animals.indices
            .filter({ !updated.wildlife.animals[$0].isPredator
                        || settlement.stats.defense > 20 })
            .min(by: { a, b in
                let pa = updated.wildlife.animals[a], pb = updated.wildlife.animals[b]
                let da = distance(pa.position, heart) - wildness(pa.species, registry: registry) * 0.2
                let db = distance(pb.position, heart) - wildness(pb.species, registry: registry) * 0.2
                return da < db
            }) else { return settlement }

        var beast = updated.wildlife.animals[index]
        beast.tameProgress += workPerTamer * Double(tamers) * wildness(beast.species, registry: registry)
        if beast.tameProgress < 1 {
            updated.wildlife.animals[index] = beast
            s.localMap = updated
            return s
        }

        // It has come round. Off the wild list and onto the colony's books.
        updated.wildlife.animals.remove(at: index)
        beast.tameProgress = 1
        beast.position = ResourceLoop.jitter(heart, by: 0.06, rng: &rng)
        s.localMap = updated
        s.tamed.append(TamedAnimal(animal: beast, role: calling(beast.species, registry: registry),
                                   tamedTick: tick))
        s.note(tick: tick, kind: .arrival, text: LocalizedText(values: [
            .en: "A \(registry.beast(beast.species)?.name.resolve(.en).lowercased() ?? beast.species) stopped running and stayed.",
            .cs: "\(registry.beast(beast.species)?.name.resolve(.cs) ?? beast.species) přestal utíkat a zůstal."]))
        return s
    }

    // MARK: - Keeping them

    /// One tick of the farmyard: the beasts eat, work, and occasionally leave.
    public static func keepAnimals(
        _ settlement: Settlement, registry: GameDataRegistry, tick: Int, mapSeed: UInt64
    ) -> Settlement {
        guard !settlement.tamed.isEmpty else { return settlement }
        var s = settlement
        var rng = SeededRNG(seed: tameSeed(mapSeed: mapSeed, settlementID: s.id,
                                           tick: tick) ^ 0x4B_45_45_50)

        var food = s.storage[.food]
        var kept: [TamedAnimal] = []
        for var beast in s.tamed {
            // It eats. A colony that cannot feed its animals loses them, which
            // is the honest cost of keeping any.
            let meal = feedPerTick
            if food >= meal {
                food -= meal
                beast.animal.health = min(beast.animal.baseHealth,
                                          beast.animal.health + 0.2)
            } else {
                beast.animal.health = max(0, beast.animal.health - 0.6)
            }

            guard beast.animal.isAlive else {
                s.note(tick: tick, kind: .death, text: LocalizedText(values: [
                    .en: "The colony's \((registry.beast(beast.animal.species)?.name.resolve(.en) ?? beast.animal.species).lowercased()) did not last the season.",
                    .cs: "\((registry.beast(beast.animal.species)?.name.resolve(.cs) ?? beast.animal.species)) osady sezónu nepřečkal."]))
                continue
            }
            // Badly kept, and it goes back to what it was.
            let condition = beast.animal.health / beast.animal.baseHealth
            if condition < neglectBelow, rng.nextUnit() < 0.05 {
                s.note(tick: tick, kind: .departure, text: LocalizedText(values: [
                    .en: "The \((registry.beast(beast.animal.species)?.name.resolve(.en) ?? beast.animal.species).lowercased()) went back to the woods.",
                    .cs: "\((registry.beast(beast.animal.species)?.name.resolve(.cs) ?? beast.animal.species)) se vrátil do lesa."]))
                continue
            }
            kept.append(beast)
        }
        s.storage[.food] = max(0, food)
        s.tamed = kept
        return s
    }

    /// What the colony's beasts are worth, as multipliers the economy reads.
    ///
    /// Deliberately modest: a mule is a help, not an industrial revolution.
    /// Beasts of burden move goods, guards make the walls mean more, and a
    /// companion lifts the colony's spirits.
    public static func bonuses(_ settlement: Settlement) -> (haul: Double, defense: Double, mood: Double) {
        var haul = 0.0, defense = 0.0, mood = 0.0
        for beast in settlement.tamed {
            let vigour = min(1, beast.animal.health / beast.animal.baseHealth)
            switch beast.role {
            case .beastOfBurden: haul += 0.12 * vigour
            case .guard: defense += 3.5 * vigour
            case .companion: mood += 0.8 * vigour
            // A mount's worth is not a multiplier on the economy — it is the
            // walk it saves, and that is `Conveyance`'s to say at the four
            // seams in `docs/MOUNTS_AND_VEHICLES.md`. Putting a haul bonus
            // here as well would pay for the same animal twice.
            case .mount: break
            }
        }
        return (min(0.6, haul), min(20, defense), min(6, mood))
    }

    // MARK: - Maths

    static func distance(_ a: LocalPoint, _ b: LocalPoint) -> Double {
        let dx = a.x - b.x, dy = a.y - b.y
        return (dx * dx + dy * dy).squareRoot()
    }

    static func tameSeed(mapSeed: UInt64, settlementID: UUID, tick: Int) -> UInt64 {
        var h: UInt64 = mapSeed &* 0x9E37_79B9_7F4A_7C15
        let b = settlementID.uuid
        h ^= UInt64(b.0) << 56 | UInt64(b.1) << 48 | UInt64(b.2) << 40 | UInt64(b.3) << 32
            | UInt64(b.4) << 24 | UInt64(b.5) << 16 | UInt64(b.6) << 8 | UInt64(b.7)
        h = (h ^ UInt64(bitPattern: Int64(tick))) &* 0xD1B5_4A32_D192_ED03
        return h ^ 0x54_41_4D_45
    }
}
