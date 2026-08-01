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

    // MARK: - The think-step

    /// How often the wild thinks, in ticks. A beast does not need a decision
    /// every minute of the year, and offline catch-up replays tens of thousands
    /// of ticks through here.
    public static let thinkInterval = 10
    /// How far a beast covers in one think, at a walk.
    static let stride = 0.012
    /// A frightened one covers this much instead.
    static let bolt = 0.055
    /// How near a predator has to be before prey notice it.
    static let alarmRange = 0.10
    /// How near a hunter has to be before prey bolt.
    static let hunterAlarmRange = 0.07

    /// Moves the wild one step of its own life: prey drift with the herd and
    /// bolt from anything that means them harm, predators close on the nearest
    /// meal, and the hurt lie up.
    ///
    /// Deliberately a *cadence* rather than every tick. This is the whole mind
    /// an animal gets — no schedule, no memory, no plan — but it is enough that
    /// the valley behaves like somewhere things live: a herd that keeps
    /// together, moves off when a wolf comes down, and is somewhere a hunter
    /// can actually walk to.
    public static func roam(
        _ map: LocalMap, tick: Int, threats: [LocalPoint] = []
    ) -> LocalMap {
        guard !map.wildlife.animals.isEmpty else { return map }
        var rng = SeededRNG(seed: map.terrainSeed
                            &+ UInt64(bitPattern: Int64(tick)) &* 0xD1B5_4A32_D192_ED03
                            &+ 0x4D_4F_56_45)
        let animals = map.wildlife.animals

        // Where the herd is, so prey have something to keep together around.
        let prey = animals.filter { !$0.species.isPredator }
        let centre: LocalPoint
        if prey.isEmpty {
            centre = LocalPoint(x: 0.5, y: 0.52)
        } else {
            centre = LocalPoint(
                x: prey.reduce(0) { $0 + $1.position.x } / Double(prey.count),
                y: prey.reduce(0) { $0 + $1.position.y } / Double(prey.count))
        }
        let predators = animals.filter { $0.species.isPredator }.map(\.position)

        var moved: [Animal] = []
        moved.reserveCapacity(animals.count)
        for var animal in animals {
            // The lame do not roam. Nor does anything badly hurt.
            guard animal.canWalk, animal.health > animal.species.baseHealth * 0.25 else {
                animal.activity = .resting
                moved.append(animal)
                continue
            }
            let scared = nearest(to: animal.position, among: predators + threats,
                                 within: animal.species.isPredator ? hunterAlarmRange : alarmRange,
                                 ignoringSelf: animal.position)
            let target: LocalPoint
            let pace: Double
            if let scared, !animal.species.isPredator {
                // Straight away from it, and quickly.
                animal.activity = .fleeing
                target = LocalPoint(x: animal.position.x * 2 - scared.x,
                                    y: animal.position.y * 2 - scared.y)
                pace = bolt
            } else if animal.species.isPredator {
                // A predator goes where the eating is.
                if let meal = nearest(to: animal.position, among: prey.map(\.position),
                                      within: 1, ignoringSelf: animal.position) {
                    animal.activity = .stalking
                    target = meal
                    pace = stride * 1.3
                } else {
                    animal.activity = .wary
                    target = centre
                    pace = stride
                }
            } else {
                // Grazing: with the herd, but not on top of it.
                //
                // Each beast keeps its *own* place in the herd rather than
                // walking at the centroid: a fresh random target every think
                // pulls every animal toward the middle, so the whole herd piles
                // onto one point and reads as one smeared deer. The standing
                // is a function of the animal's id, so a herd is a spread of
                // individuals that holds its shape as it drifts.
                animal.activity = .grazing
                let station = herdStation(animal.id)
                let wander = 0.02
                target = LocalPoint(
                    x: centre.x + station.x + (rng.nextUnit() - 0.5) * wander,
                    y: centre.y + station.y + (rng.nextUnit() - 0.5) * wander)
                pace = stride
            }
            animal.position = step(from: animal.position, toward: target, by: pace)
            moved.append(animal)
        }

        var updated = map
        updated.wildlife.animals = moved
        return updated
    }

    /// Where a given beast stands in its herd, relative to the herd's middle.
    ///
    /// Stable per animal, so the herd is a spread of individuals that keeps its
    /// shape as it drifts rather than a knot that re-forms every think. Spread
    /// wide enough that two deer never occupy the same few pixels.
    static func herdStation(_ id: UUID) -> (x: Double, y: Double) {
        var h: UInt64 = 0xCBF2_9CE4_8422_2325
        let b = id.uuid
        for byte in [b.0, b.1, b.2, b.3, b.4, b.5, b.6, b.7] {
            h = (h ^ UInt64(byte)) &* 0x0100_0000_01B3
        }
        let angle = Double(h % 6283) / 1000
        let radius = 0.020 + Double((h >> 21) % 1000) / 1000 * 0.055
        return (cos(angle) * radius, sin(angle) * radius * 0.75)
    }

    /// The nearest of `points` within `within`, skipping the one at `ignoringSelf`.
    static func nearest(to p: LocalPoint, among points: [LocalPoint],
                        within: Double, ignoringSelf: LocalPoint) -> LocalPoint? {
        var best: LocalPoint?
        var bestD = within * within
        for q in points {
            let dx = q.x - p.x, dy = q.y - p.y
            let d = dx * dx + dy * dy
            guard d > 1e-9 else { continue }   // itself
            if d < bestD { bestD = d; best = q }
        }
        return best
    }

    /// One step toward a point, kept on the map.
    static func step(from: LocalPoint, toward: LocalPoint, by distance: Double) -> LocalPoint {
        let dx = toward.x - from.x, dy = toward.y - from.y
        let length = (dx * dx + dy * dy).squareRoot()
        guard length > 1e-6 else { return from }
        let t = min(1, distance / length)
        return LocalPoint(x: min(0.97, max(0.03, from.x + dx * t)),
                          y: min(0.97, max(0.03, from.y + dy * t)))
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

        let capacity = map.wildlife.preyCapacity
        let living = map.wildlife.animals.count
        guard living > 1, living < capacity else { return map }

        var rng = SeededRNG(seed: map.terrainSeed &+ UInt64(bitPattern: Int64(tick)) &* 0x85EB_CA6B)
        let breeders = map.wildlife.animals.filter {
            !$0.species.isPredator && $0.health > $0.species.baseHealth * 0.6
        }
        guard !breeders.isEmpty else { return map }

        // Half the healthy breeding stock brings something through the spring.
        // A third was too few once hunters started taking *named* animals
        // rather than a fraction of a number: the wild could not put back what
        // a two-hunter colony took out, and a valley slid to the hunting floor
        // and stayed there.
        let room = capacity - living
        let born = min(room, max(1, breeders.count / 2))
        var updated = map
        for _ in 0..<born {
            let parent = breeders[Int(rng.nextUnit() * Double(breeders.count)) % breeders.count]
            let id = rng.nextUUID()
            updated.wildlife.animals.append(
                Animal(id: id, species: parent.species,
                       sex: rng.nextUnit() < 0.5 ? .male : .female, age: 0,
                       // A calf is born where its mother is standing.
                       position: parent.position))
        }
        return updated
    }
}
