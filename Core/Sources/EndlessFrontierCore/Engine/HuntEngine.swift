import Foundation

/// The hunt, fought rather than harvested.
///
/// Hunting used to be arithmetic with a number called `deerHerd`: a hunter's
/// week became a fraction of a herd, the fraction became food, and no animal
/// was ever involved. The valley could be full of deer you could see and the
/// larder would not know it, or empty and the larder would not notice either.
///
/// A hunt is now an encounter between two things that are in the same place. A
/// hunter walks up on a *named beast*, and what happens next depends on what
/// they are carrying — exactly as it does in a battle, because it is the same
/// question:
///
/// - **A bow, a sling, a rifle** kills at a distance. The hunter looses before
///   the animal knows they are there, so the shot lands on something vital and
///   the risk is small. A miss simply startles it and it bolts.
/// - **A spear, an axe, bare hands** means closing with it. More of the beast
///   survives the first blow, so more of them get away — and a boar, a wolf or
///   a bear that is still standing when you arrive will put you on your back.
///
/// The kill is a carcass: meat by the size of the animal and a hide off its
/// back, both banked as real goods. Nothing is culled by proportion any more.
///
/// Deterministic throughout — every roll comes from `(mapSeed, settlement, tick)`
/// — and linear in the number of hunters, which is what offline catch-up needs.
public enum HuntEngine {

    /// One hunter, reduced to what the hunt cares about.
    public struct Hunter: Sendable, Equatable {
        public let id: UUID
        public let name: String
        /// Their reach with a thrown or loosed weapon; 0 with none.
        public let ranged: Double
        /// What they can do at arm's length.
        public let melee: Double
        /// How much a wound they take is multiplied by — armour blunts it.
        public let woundMultiplier: Double

        public init(id: UUID, name: String, ranged: Double, melee: Double,
                    woundMultiplier: Double) {
            self.id = id
            self.name = name
            self.ranged = ranged
            self.melee = melee
            self.woundMultiplier = woundMultiplier
        }

        /// Whether this hunter kills at a distance. The single fact that
        /// decides how the encounter goes.
        public var shootsFromCover: Bool { ranged > melee * 0.5 && ranged > 0 }
    }

    /// What one tick of hunting did.
    /// What a hunter is visibly doing, so the canvas can show the hunt the
    /// simulation has always run.
    ///
    /// The hunt resolves inside one tick — find the quarry, roll, kill or
    /// wound — so there is no phase to *hold*; there is only what just
    /// happened. That is enough: the canvas needs to know whether this
    /// colonist is creeping, sprinting or walking home under a carcass, and
    /// those are the three answers the roll already produces.
    /// `quarry` only ever returns a beast already within `reach`, so "found
    /// something" and "close enough to try" are the same fact. That makes the
    /// three phases fall straight out of the loop rather than needing a second
    /// distance test that would always answer the same way.
    public enum Phase: String, Codable, Sendable {
        case stalking   // out in the wood with nothing within reach yet
        case closing    // a beast in front of them, about to try for it
        case killed     // took it this tick
    }

    public struct Bag: Sendable {
        public var map: LocalMap
        /// What each hunter did this tick. Presentation-only: nothing in the
        /// simulation reads it back.
        public var phases: [UUID: Phase] = [:]
        /// The beasts taken, whole — so the yield can be read off the carcass.
        public var kills: [Animal] = []
        /// Hunters hurt by something that fought back, and by how much.
        public var wounds: [(hunterID: UUID, hunterName: String,
                             species: String, damage: Double)] = []

        public var meat: Double { kills.reduce(0) { $0 + $1.meatYield } }
        public var hides: Int { kills.count }
    }

    /// How likely a shot from cover is to be fatal outright.
    static let rangedKillChance = 0.55
    /// …and a blow struck at arm's length.
    static let meleeKillChance = 0.32
    /// A wounded-but-not-killed beast takes this much damage.
    static let woundDamage: Double = 26
    /// The odds a dangerous animal that survives turns on the hunter.
    static let retaliationChance = 0.45
    /// How near a hunter has to be to have an encounter at all.
    /// How close a hunter has to be to try for a beast. Public because the
    /// canvas judges "closing" against the same number the roll does — two
    /// answers to one question is how a picture starts lying about the game.
    public static let reach = 0.16

    /// Runs one tick of hunting for a settlement's hunters.
    ///
    /// Each hunter takes the nearest beast in reach — the hunt catches what is
    /// *there*, which is the whole reason animals have positions — preferring
    /// the lame and the sick among equals, because that is what a hunt actually
    /// culls and what keeps a hunted herd healthy.
    public static func run(
        _ map: LocalMap, hunters: [Hunter], at posts: [UUID: LocalPoint],
        tick: Int, seed: UInt64,
        /// Beasts the player has marked for the hunt (`Designation`). A marked
        /// animal is taken before any other in reach.
        marked: Set<UUID> = []
    ) -> Bag {
        var bag = Bag(map: map)
        guard !hunters.isEmpty, !map.wildlife.animals.isEmpty else { return bag }
        var rng = SeededRNG(seed: seed &+ UInt64(bitPattern: Int64(tick)) &* 0x9E37_79B9_7F4A_7C15)
        var animals = map.wildlife.animals
        var taken: Set<UUID> = []

        for hunter in hunters {
            let from = posts[hunter.id] ?? LocalPoint(x: 0.5, y: 0.52)
            guard let index = quarry(in: animals, from: from, taken: taken,
                                     marked: marked) else {
                // Nothing within reach: still out there, still looking.
                bag.phases[hunter.id] = .stalking
                continue
            }
            var beast = animals[index]

            bag.phases[hunter.id] = .closing

            let fromCover = hunter.shootsFromCover
            let odds = fromCover ? rangedKillChance : meleeKillChance
            // A steadier hand kills cleaner; the skill is already weighed into
            // the weapon numbers the militia code produces.
            let sharpness = min(0.28, (fromCover ? hunter.ranged : hunter.melee) * 0.02)
            if rng.nextUnit() < odds + sharpness {
                // Clean: through the heart, or the throat.
                beast.injure(fromCover ? .torso : .head, by: beast.baseHealth)
                taken.insert(beast.id)
                animals[index] = beast
                bag.kills.append(beast)
                bag.phases[hunter.id] = .killed
                continue
            }

            // Not clean. It is hurt, and it knows where the hunter is.
            let part: AnimalBodyPartKind = fromCover ? .torso : .frontLeftLeg
            beast.injure(part, by: woundDamage)
            beast.activity = .fleeing
            // Away, hard — a wounded animal is the one that gets away.
            beast.position = AnimalEngine.step(
                from: beast.position,
                toward: LocalPoint(x: beast.position.x * 2 - from.x,
                                   y: beast.position.y * 2 - from.y),
                by: AnimalEngine.bolt * 1.5)

            if !beast.isAlive {
                taken.insert(beast.id)
                animals[index] = beast
                bag.kills.append(beast)
                bag.phases[hunter.id] = .killed
                continue
            }
            // And if it is something that fights back, and the hunter had to
            // walk up to it, it fights back.
            if beast.isDangerous, !fromCover, rng.nextUnit() < retaliationChance {
                let damage = beast.retaliation * hunter.woundMultiplier
                bag.wounds.append((hunter.id, hunter.name, beast.species, damage))
            }
            animals[index] = beast
        }

        guard !taken.isEmpty || animals != map.wildlife.animals else { return bag }
        var updated = map
        updated.wildlife.animals = animals.filter { !taken.contains($0.id) }
        bag.map = updated
        return bag
    }

    /// The beast a hunter goes for: the nearest one in reach, and among those
    /// at similar range, the one least able to get away.
    static func quarry(in animals: [Animal], from: LocalPoint, taken: Set<UUID>,
                       marked: Set<UUID> = []) -> Int? {
        var best: Int?
        var bestScore = Double.greatestFiniteMagnitude
        for (index, animal) in animals.enumerated() {
            guard !taken.contains(animal.id), !animal.isPredator else { continue }
            let dx = animal.position.x - from.x, dy = animal.position.y - from.y
            let distance = (dx * dx + dy * dy).squareRoot()
            guard distance <= reach else { continue }
            // Distance first, but a lame or sick beast is worth a step further
            // — and a beast the player pointed at is worth the whole valley:
            // the mark takes it clear of every unmarked animal in reach
            // (`Designation`), while still being bounded by `reach`, because a
            // hunting party is not a teleport.
            let frailty = (animal.canWalk ? 0.0 : -0.06)
                + (animal.health / animal.baseHealth - 1) * 0.04
            let score = distance + frailty - (marked.contains(animal.id) ? reach * 2 : 0)
            if score < bestScore { bestScore = score; best = index }
        }
        return best
    }

    /// Builds the hunting party from a settlement's colonists — the same
    /// weapon weighting the militia uses, because a bow is a bow whether it is
    /// pointed at a deer or at a raider.
    public static func party(
        _ settlement: Settlement, registry: GameDataRegistry, ticksPerYear: Int
    ) -> [Hunter] {
        settlement.pawns.filter {
            $0.assignedWork == .hunting && $0.isAdult(ticksPerYear: ticksPerYear)
                && !$0.isBroken && !$0.isAway && $0.health > 0
        }.map { pawn in
            let arms = CombatEngine.militia([pawn], registry: registry)
            return Hunter(id: pawn.id, name: pawn.name,
                          ranged: arms.ranged, melee: arms.melee,
                          woundMultiplier: CombatEngine.woundMultiplier(pawn))
        }
    }
}
