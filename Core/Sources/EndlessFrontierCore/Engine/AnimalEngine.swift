import Foundation

/// Runs the wild the way the colony is run: one tick at a time, per animal.
///
/// `Animal` gave the wild bodies; this gives it a life. Beasts age, wounds knit,
/// illness runs its course, cold and heat bite when the season turns against
/// them, and what dies is taken off the map. The herd also replenishes, so a
/// valley hunted flat recovers — slowly, and only if breeding stock is left.
///
/// Deterministic: every roll comes from `(terrainSeed, tick)`, never `Date()`
/// or an unseeded generator, so the same world always runs the same wild.
/// Linear in the number of animals — offline catch-up replays tens of thousands
/// of ticks through here.
public enum AnimalEngine {

    /// How fast an untended wound closes, per tick.
    static let healPerTick = 0.0015
    /// Severity taken per tick per degree outside the comfort band.
    static let exposureRate = 0.0025
    /// How fast an illness runs, per tick — most pass, some carry off the weak.
    static let diseaseProgressPerTick = 0.0012
    /// Health lost per tick per point of severity, summed over conditions.
    static let sufferingPerTick = 0.9
    /// Health regained per tick by a beast carrying nothing.
    static let thrivePerTick = 0.25
    /// An animal's life, in ticks. Roughly seventy years at 60 ticks a year is
    /// far too long for a deer, so this is deliberately short.
    static let lifespanTicks = 900

    /// Advances every animal on a settlement's local map by one tick.
    public static func advanceOneTick(
        _ map: LocalMap, tick: Int, ticksPerYear: Int
    ) -> LocalMap {
        guard !map.wildlife.animals.isEmpty else { return map }
        var rng = SeededRNG(seed: map.terrainSeed &+ UInt64(bitPattern: Int64(tick)) &* 0x9E37_79B9)
        let season = Season(tick: tick, ticksPerYear: ticksPerYear)
        let outside = temperature(season)

        var animals: [Animal] = []
        animals.reserveCapacity(map.wildlife.animals.count)
        for var animal in map.wildlife.animals {
            animal.age += 1

            // Cold and heat, when the season leaves the beast's comfort band.
            let cold = outside < animal.species.comfortLow
            let hot = outside > animal.species.comfortHigh
            if cold {
                worsen(&animal, .frostbite, by: (animal.species.comfortLow - outside) * exposureRate,
                       label: LocalizedText(values: [.en: "Frostbite", .cs: "Omrzliny"]))
            } else if hot {
                worsen(&animal, .heatstroke, by: (outside - animal.species.comfortHigh) * exposureRate,
                       label: LocalizedText(values: [.en: "Heatstroke", .cs: "Úpal"]))
            }

            // What it carries: wounds knit, illness runs, both cost it.
            var suffering = 0.0
            var kept: [AnimalCondition] = []
            for var condition in animal.conditions {
                switch condition.kind {
                case .injury:
                    condition.severity -= healPerTick
                case .frostbite:
                    // Frostbite does not mend in a blizzard. Healing an exposure
                    // the moment it was taken is why cold could never
                    // accumulate: each tick added a little and took it straight
                    // back off, leaving nothing above the keep-threshold.
                    if !cold { condition.severity -= healPerTick }
                case .heatstroke:
                    if !hot { condition.severity -= healPerTick }
                case .disease:
                    // An illness peaks and then breaks.
                    condition.severity += condition.severity < 0.5
                        ? diseaseProgressPerTick : -diseaseProgressPerTick * 2
                }
                // Kept until it is actually healed away. A keep-threshold of
                // 0.01 was higher than a mild exposure's per-tick increment
                // (a bear in 31°C takes 0.0075), so the condition was created
                // and binned on the same tick, for ever — the same way cold
                // could never take hold before exposure stopped self-healing.
                if condition.severity > 0 {
                    suffering += condition.severity
                    kept.append(condition)
                }
            }
            animal.conditions = kept

            if suffering > 0 {
                animal.health = max(0, animal.health - suffering * sufferingPerTick)
            } else if animal.health < animal.species.baseHealth {
                animal.health = min(animal.species.baseHealth, animal.health + thrivePerTick)
            }

            // Old age comes for it in the end.
            if animal.age > lifespanTicks, rng.nextUnit() < 0.004 {
                animal.health = 0
            }
            if animal.isAlive { animals.append(animal) }
        }

        guard animals.count != map.wildlife.animals.count || animals != map.wildlife.animals else {
            return map
        }
        var updated = map
        updated.wildlife.animals = animals
        return updated
    }

    /// Rough outside temperature for a season, in °C. Crude on purpose — the
    /// point is that winter bites and summer bakes, not a weather model.
    ///
    /// These have to actually *reach past* the species' comfort bands or the
    /// frostbite and heatstroke conditions are dead letters. A first pass had
    /// winter at −12 against a hardiest floor of −15, so nothing on the map
    /// could ever be cold; the spread below is chosen so the soft-skinned
    /// (boar, deer, fox) suffer a hard winter while the hare and the big
    /// predators shrug it off, and the thick-coated (bear, wolf) are the ones
    /// that suffer high summer. `bandsAreReachable` pins this.
    public static func temperature(_ season: Season) -> Double {
        switch season {
        case .spring: return 11
        case .summer: return 31
        case .autumn: return 9
        case .winter: return -22
        }
    }

    /// Adds a condition of a kind, or deepens the one already there.
    static func worsen(_ animal: inout Animal, _ kind: AnimalConditionKind,
                       by amount: Double, label: LocalizedText) {
        guard amount > 0 else { return }
        if let i = animal.conditions.firstIndex(where: { $0.kind == kind }) {
            animal.conditions[i].severity = min(1, animal.conditions[i].severity + amount)
        } else {
            animal.conditions.append(
                AnimalCondition(id: stableID(animal.id, kind), kind: kind,
                                severity: min(1, amount), label: label))
        }
    }

    /// A condition's id has to be stable, or a save would differ from the world
    /// that wrote it and the determinism tests would catch us.
    static func stableID(_ animalID: UUID, _ kind: AnimalConditionKind) -> UUID {
        var h: UInt64 = 0xCBF2_9CE4_8422_2325
        for byte in animalID.uuidString.utf8 { h = (h ^ UInt64(byte)) &* 0x0100_0000_01B3 }
        for byte in kind.rawValue.utf8 { h = (h ^ UInt64(byte)) &* 0x0100_0000_01B3 }
        var bytes = [UInt8](repeating: 0, count: 16)
        for i in 0..<8 {
            bytes[i] = UInt8((h >> (8 * UInt64(i))) & 0xFF)
            bytes[i + 8] = UInt8((h.byteSwapped >> (8 * UInt64(i))) & 0xFF)
        }
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5],
                           bytes[6], bytes[7], bytes[8], bytes[9], bytes[10], bytes[11],
                           bytes[12], bytes[13], bytes[14], bytes[15]))
    }

    /// Takes `count` prey off the map, worst-off first — the hunt catches the
    /// lame and the sick before it catches the strong, which is what keeps a
    /// hunted herd healthy. Returns the map and how many were actually taken.
    @discardableResult
    public static func hunt(_ map: LocalMap, count: Int) -> (map: LocalMap, taken: Int) {
        guard count > 0 else { return (map, 0) }
        let prey = map.wildlife.animals.enumerated()
            .filter { !$0.element.species.isPredator }
            .sorted { lhs, rhs in
                if lhs.element.canWalk != rhs.element.canWalk { return !lhs.element.canWalk }
                return lhs.element.health < rhs.element.health
            }
        guard !prey.isEmpty else { return (map, 0) }
        let doomed = Set(prey.prefix(count).map(\.offset))
        guard !doomed.isEmpty else { return (map, 0) }
        var updated = map
        updated.wildlife.animals = map.wildlife.animals.enumerated()
            .filter { !doomed.contains($0.offset) }
            .map(\.element)
        return (updated, doomed.count)
    }

    /// Lets the wild breed back toward what the land can feed. Only mature,
    /// healthy prey breed, and only while there is room — so a valley hunted
    /// flat stays flat until something is left to breed from.
    public static func breed(
        _ map: LocalMap, tick: Int, ticksPerYear: Int
    ) -> LocalMap {
        // Once a year, in spring — beasts do not calve in January.
        let seasonLength = max(1, ticksPerYear / 4)
        guard tick % seasonLength == 0,
              Season(tick: tick, ticksPerYear: ticksPerYear) == .spring else { return map }

        let capacity = Int(max(0, map.wildlife.deerCapacity / 4))
        let living = map.wildlife.animals.count
        guard living > 1, living < capacity else { return map }

        var rng = SeededRNG(seed: map.terrainSeed &+ UInt64(bitPattern: Int64(tick)) &* 0x85EB_CA6B)
        let breeders = map.wildlife.animals.filter {
            !$0.species.isPredator && $0.health > $0.species.baseHealth * 0.6
        }
        guard !breeders.isEmpty else { return map }

        let room = capacity - living
        let born = min(room, max(1, breeders.count / 3))
        var updated = map
        for _ in 0..<born {
            let parent = breeders[Int(rng.nextUnit() * Double(breeders.count)) % breeders.count]
            updated.wildlife.animals.append(
                Animal(id: rng.nextUUID(), species: parent.species,
                       sex: rng.nextUnit() < 0.5 ? .male : .female, age: 0))
        }
        return updated
    }
}
