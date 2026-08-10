import Foundation

/// What wears a building down, and what puts it back up.
///
/// Buildings were immortal. You raised one and it stood for ever, whatever
/// happened to it: a raid that burned half the town cost goods and people and
/// left the town itself untouched, a blizzard did nothing to a roof, and the
/// mason's trade ended the day the last shingle went on. Nothing the colony
/// made ever needed keeping.
///
/// A building is a thing now. It weathers with the seasons, takes damage of
/// particular kinds from particular events, stops working when it gets bad
/// enough, and has to be repaired — which costs materials and somebody's week,
/// and is therefore a real claim on a colony that would rather be building
/// something new.
public enum BuildingEngine {

    // MARK: - The numbers

    /// Below this a building is derelict: it produces nothing, shelters nobody,
    /// and is drawn as a wreck. Deliberately not zero — a building that is
    /// merely battered should still work, or one bad winter would stop a colony
    /// dead.
    public static let derelictBelow: Double = 0.25
    /// Below this the colony wants it seen to. What posts a repair job.
    public static let repairBelow: Double = 0.92
    /// How often wear and repair are worked out, in ticks.
    public static let interval = 10
    /// Condition lost per interval to ordinary weather.
    public static let wearPerInterval: Double = 0.0016
    /// …multiplied by this in the seasons that are hard on a roof.
    public static let winterWear: Double = 2.6
    public static let autumnWear: Double = 1.5
    /// How much condition one builder puts back per interval.
    public static let repairPerBuilder: Double = 0.045
    /// Materials one point of condition costs to put back, as a share of what
    /// the building cost to raise. Repair is cheap next to rebuilding, which is
    /// what makes keeping a thing up the sensible choice.
    public static let repairCostShare: Double = 0.35

    /// The kinds of harm a building can take. What did it matters: a raid goes
    /// for what is worth taking, a storm takes the roofs, a fire spreads to
    /// whatever is next to it, and a beast only ever breaks a fence.
    public enum DamageKind: String, Codable, Sendable, CaseIterable {
        case raid       // people who came to take things
        case storm      // weather that got in
        case fire       // and spreads
        case beast      // something out of the trees
        case quake      // the ground itself

        /// How many buildings it reaches, as a share of the colony.
        var spread: Double {
            switch self {
            case .raid: return 0.30
            case .storm: return 0.55
            case .fire: return 0.22
            case .beast: return 0.08
            case .quake: return 0.75
            }
        }

        /// How hard it hits what it reaches, at severity 1.
        var bite: Double {
            switch self {
            case .raid: return 0.35
            case .storm: return 0.22
            case .fire: return 0.60
            case .beast: return 0.15
            case .quake: return 0.45
            }
        }

        public var displayName: LocalizedText {
            switch self {
            case .raid: return LocalizedText(values: [.en: "raiders", .cs: "nájezdníci"])
            case .storm: return LocalizedText(values: [.en: "the storm", .cs: "bouře"])
            case .fire: return LocalizedText(values: [.en: "the fire", .cs: "požár"])
            case .beast: return LocalizedText(values: [.en: "a beast", .cs: "šelma"])
            case .quake: return LocalizedText(values: [.en: "the tremor", .cs: "otřesy"])
            }
        }
    }

    // MARK: - Reading a building's state

    /// Whether this building is standing well enough to do its job.
    public static func isWorking(_ placement: BuildingPlacement) -> Bool {
        !placement.underConstruction && placement.condition >= derelictBelow
    }

    /// What a building actually produces, as a multiplier. A sound building is
    /// whole; a battered one gives less; a derelict one gives nothing.
    ///
    /// The curve is deliberately gentle above `derelictBelow` — the interesting
    /// state is "this needs seeing to", not "this stopped".
    public static func output(_ condition: Double) -> Double {
        guard condition >= derelictBelow else { return 0 }
        return 0.55 + 0.45 * min(1, (condition - derelictBelow) / (1 - derelictBelow))
    }

    /// The colony's average state of repair, for the ledger and the objective.
    public static func upkeepFraction(_ settlement: Settlement) -> Double {
        guard let colony = settlement.colony else { return 1 }
        let standing = colony.placements.filter { !$0.underConstruction }
        guard !standing.isEmpty else { return 1 }
        return standing.reduce(0.0) { $0 + $1.condition } / Double(standing.count)
    }

    /// Everything that wants a mason.
    public static func needingRepair(_ settlement: Settlement) -> [BuildingPlacement] {
        settlement.colony?.placements.filter {
            !$0.underConstruction && $0.condition < repairBelow
        } ?? []
    }

    // MARK: - Wear

    /// Weathers every standing building a little. On the interval, so offline
    /// catch-up is not paying for a per-tick pass over the whole colony.
    public static func weather(
        _ settlement: Settlement, registry: GameDataRegistry, tick: Int
    ) -> Settlement {
        guard var colony = settlement.colony, !colony.placements.isEmpty else {
            return settlement
        }
        let season = Season(tick: tick, ticksPerYear: max(1, registry.config.ticksPerYear))
        let multiplier: Double
        switch season {
        case .winter: multiplier = winterWear
        case .autumn: multiplier = autumnWear
        default: multiplier = 1
        }
        var changed = false
        for i in colony.placements.indices where !colony.placements[i].underConstruction {
            let before = colony.placements[i].condition
            guard before > 0 else { continue }
            colony.placements[i].condition = max(0, before - wearPerInterval * multiplier)
            changed = true
        }
        guard changed else { return settlement }
        var s = settlement
        s.colony = colony
        return s
    }

    // MARK: - Damage

    /// Hurts the colony's buildings.
    ///
    /// `severity` is 0…1 and scales both how many are reached and how hard.
    /// What gets hit is decided by the kind: a raid goes through the town from
    /// its edge inward — the outlying works first, which is why walls are worth
    /// having — while a storm and a tremor are indiscriminate, and a fire takes
    /// hold in one place and eats what is next to it.
    @discardableResult
    public static func damage(
        _ settlement: Settlement, kind: DamageKind, severity: Double,
        rng: inout SeededRNG
    ///
    /// `seat` is the lot the harm took hold on — the first of `targets`, which
    /// `pick` has already ordered by where the thing came from: the seat of a
    /// fire, the outermost roof a raid reached. It is here so the journal entry
    /// can carry a place and the canvas can take the player to it, instead of
    /// "three buildings were knocked about" somewhere in a valley.
    ) -> (settlement: Settlement, hit: Int, ruined: [String], seat: UUID?) {
        guard var colony = settlement.colony else { return (settlement, 0, [], nil) }
        let standing = colony.placements.indices.filter {
            !colony.placements[$0].underConstruction && colony.placements[$0].condition > 0
        }
        guard !standing.isEmpty else { return (settlement, 0, [], nil) }

        let strength = min(1, max(0, severity))
        let reach = max(1, Int((Double(standing.count) * kind.spread * (0.4 + strength)).rounded()))
        let targets = pick(kind: kind, from: standing, in: colony, count: reach, rng: &rng)

        var ruined: [String] = []
        for index in targets {
            let bite = kind.bite * strength * (0.6 + rng.nextUnit() * 0.8)
            let before = colony.placements[index].condition
            colony.placements[index].condition = max(0, before - bite)
            if before >= derelictBelow, colony.placements[index].condition < derelictBelow {
                ruined.append(colony.placements[index].definitionID)
            }
        }

        var s = settlement
        s.colony = colony
        // A building nobody can work in is a building nobody is posted to.
        if !ruined.isEmpty {
            s = evictDerelict(s)
        }
        return (s, targets.count, ruined, targets.first.map { colony.placements[$0].id })
    }

    /// Which buildings a given harm actually reaches.
    static func pick(
        kind: DamageKind, from standing: [Int], in colony: ColonyMap,
        count: Int, rng: inout SeededRNG
    ) -> [Int] {
        switch kind {
        case .raid:
            // From the outside in: whatever is furthest from the middle of the
            // colony is what they reach first.
            let centre = (x: Double(colony.width) / 2, y: Double(colony.height) / 2)
            return standing.sorted { a, b in
                let pa = colony.placements[a].coord, pb = colony.placements[b].coord
                let da = pow(Double(pa.x) - centre.x, 2) + pow(Double(pa.y) - centre.y, 2)
                let db = pow(Double(pb.x) - centre.x, 2) + pow(Double(pb.y) - centre.y, 2)
                return da == db ? a < b : da > db
            }.prefix(count).map { $0 }
        case .fire:
            // Takes hold somewhere and eats outward from there.
            guard let seat = standing.randomElement(using: &rng) else { return [] }
            let origin = colony.placements[seat].coord
            return standing.sorted { a, b in
                let pa = colony.placements[a].coord, pb = colony.placements[b].coord
                let da = abs(pa.x - origin.x) + abs(pa.y - origin.y)
                let db = abs(pb.x - origin.x) + abs(pb.y - origin.y)
                return da == db ? a < b : da < db
            }.prefix(count).map { $0 }
        case .storm, .quake, .beast:
            // Indiscriminate: a shuffle the seed decides.
            var pool = standing
            var picked: [Int] = []
            while picked.count < count, !pool.isEmpty {
                let at = Int(rng.nextUnit() * Double(pool.count)) % pool.count
                picked.append(pool.remove(at: at))
            }
            return picked
        }
    }

    /// Turns everyone out of a building that has stopped being one.
    static func evictDerelict(_ settlement: Settlement) -> Settlement {
        guard var colony = settlement.colony else { return settlement }
        var s = settlement
        var turnedOut: Set<UUID> = []
        for i in colony.placements.indices
        where colony.placements[i].condition < derelictBelow
            && !colony.placements[i].assignedPawnIDs.isEmpty {
            turnedOut.formUnion(colony.placements[i].assignedPawnIDs)
            colony.placements[i].assignedPawnIDs = []
        }
        let derelict = Set(colony.placements.filter { $0.condition < derelictBelow }.map(\.id))
        s.colony = colony
        guard !turnedOut.isEmpty || !derelict.isEmpty else { return settlement }
        // …and out of their beds, if that is what it was.
        for i in s.pawns.indices {
            if let home = s.pawns[i].homeID, derelict.contains(home) {
                s.pawns[i].homeID = nil
            }
        }
        return s
    }

    // MARK: - Repair

    /// Puts the builders to work on what needs it, worst first.
    ///
    /// Repair costs materials, so a colony with empty stores watches its town
    /// go to pieces — which is the point of having the mason's trade outlive
    /// the building of the thing.
    public static func repair(
        _ settlement: Settlement, registry: GameDataRegistry
    ) -> Settlement {
        guard var colony = settlement.colony else { return settlement }
        let broken = colony.placements.indices
            .filter { !colony.placements[$0].underConstruction
                       && colony.placements[$0].condition < repairBelow }
            .sorted { colony.placements[$0].condition < colony.placements[$1].condition }
        guard !broken.isEmpty else { return settlement }

        // Who is free to swing a hammer at it — and there is always somebody
        // able to do a little, or a colony with no dedicated mason would watch
        // its only house fall down.
        let ticksPerYear = max(1, registry.config.ticksPerYear)
        let masons = settlement.pawns.count {
            $0.assignedWork == .building && $0.isAdult(ticksPerYear: ticksPerYear)
                && !$0.isBroken && !$0.isAway
        }
        let hands = max(1, masons)

        var s = settlement
        var materials = s.storage[.materials]
        var work = Double(hands) * repairPerBuilder
        for index in broken {
            guard work > 0 else { break }
            let placement = colony.placements[index]
            let missing = 1 - placement.condition
            let put = min(work, missing)
            // What that costs out of the stores.
            let raiseCost = registry.building(placement.definitionID)?.cost[.materials] ?? 0
            let cost = raiseCost * repairCostShare * put
            guard materials >= cost else { break }
            materials -= cost
            work -= put
            colony.placements[index].condition = min(1, placement.condition + put)
        }
        s.storage[.materials] = max(0, materials)
        s.colony = colony
        return s
    }
}
