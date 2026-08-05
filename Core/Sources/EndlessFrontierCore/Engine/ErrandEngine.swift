import Foundation

/// Sends people places **because of what they need**.
///
/// The colony had needs and they bit — mood, health, frostbite — and not one of
/// them ever caused a decision. `PawnEngine` fed a hungry colonist out of the
/// settlement's store wherever they happened to be standing, and warmth went up
/// because a hearth existed *somewhere*. Nobody walked to a granary; nobody
/// walked to a fire. Sixty people worked their trades and none of them was ever
/// doing anything because of their own state, which is the whole of "it has no
/// dynamism".
///
/// This is the middle that was missing. A need past its threshold posts an
/// `Errand` to the **nearest** place that can answer it, the walk takes real
/// ticks, and the need is satisfied **on arrival**. Three things follow that
/// were not true before:
///
/// - A granary on the far side of town costs the colony minutes of work.
/// - A colony whose store burned genuinely fails to feed people, rather than
///   feeding them out of a number.
/// - The canvas can draw somebody crossing the town for a reason, instead of a
///   worker who never leaves their tree.
///
/// Balance note: a meal was +6 hunger against a threshold of 70, so colonists
/// hovered at 70 and topped up almost every tick. Walking for that would be
/// absurd, so a meal at the granary is a *proper* one — it fills them — and
/// costs food in proportion. At steady state that is the same food per person
/// per tick the old top-up cost; what changes is that it happens somewhere.
///
/// Pure and deterministic: no randomness at all, and the only inputs are the
/// settlement, the registry and the tick.
public enum ErrandEngine {

    /// How far a colonist covers in one tick, in local-map units. The town is
    /// `SettlementGeometry.span` across, so crossing it is a few minutes.
    public static let pace: Double = 0.09
    /// Below this a colonist stops what they are doing and goes to eat. The
    /// same threshold the old inline top-up used, so nobody starts eating at a
    /// different moment than they used to — only somewhere different.
    public static let hungryBelow: Double = PawnEngine.mealHungerThreshold
    /// …and below this they go to a fire. Well above `freezingBelow`, because
    /// the point is to get warm *before* it costs them fingers.
    public static let coldBelow: Double = 40
    /// What a colonist walks away from a hearth with. Not a full 100: a fire
    /// takes the edge off, it does not replace a roof.
    public static let hearthWarmth: Double = 34
    /// The longest walk anybody will make for a need. Past this, whatever is
    /// out there is not worth the trip and they make do where they are — which
    /// is what stops an errand from eating a whole day.
    public static let furthestWorthGoing: Double = 0.55

    /// Food per point of hunger restored, taken straight from the old inline
    /// meal so the colony's upkeep is unchanged (rule 8: one number).
    public static var foodPerHungerPoint: Double {
        PawnEngine.foodPerMeal / PawnEngine.hungerPerMeal
    }

    // MARK: - The tick

    /// Arrivals first, then departures.
    ///
    /// In that order because a colonist who arrives this tick should be fed
    /// *before* `PawnEngine` reads their needs for mood, and because somebody
    /// who just ate must not be sent straight back out.
    public static func advanceOneTick(
        _ settlement: Settlement, registry: GameDataRegistry = GameDataRegistry(),
        tick: Int = 0, laws: LawModifiers = LawModifiers()
    ) -> Settlement {
        guard !settlement.pawns.isEmpty else { return settlement }
        var s = settlement
        var food = s.storage[.food]

        // Where the colony keeps what it has, and where it keeps a fire. Both
        // are lists of places rather than a number, which is the point.
        let larders = places(in: s, registry: registry) { $0.storage > 0 }
        let hearths = places(in: s, registry: registry) { $0.housing > 0 || $0.pollution > 0 }
        let ration = s.policy.ration
        let mealCost = PawnEngine.foodPerMeal * laws.foodUpkeepMultiplier * ration.foodPerMeal
        // A head's worth of what is in the store, so nobody eats the granary.
        let share = food / Double(max(1, s.pawns.count))

        for i in s.pawns.indices {
            // Somebody out at the ruins cannot walk to the granary, and they do
            // not need to: an expedition leaves with provisions, and the food
            // it costs is charged when it sets out. They eat where they are.
            //
            // This is the one case that keeps the old shape, and it has to:
            // without it a party of four out for two hundred ticks simply
            // starved to death in a colony whose granary was full. Measured —
            // eleven dead of hunger against a store at 1245 of 1250.
            guard !s.pawns[i].isAway else {
                s.pawns[i].errand = nil
                guard s.pawns[i].needs.hunger < hungryBelow, food >= mealCost else { continue }
                food = eat(&s.pawns[i], from: food, mealCost: mealCost,
                           ration: ration, share: share)
                s.pawns[i].needs = s.pawns[i].needs.clamped()
                continue
            }
            if let errand = s.pawns[i].errand {
                guard errand.hasArrived(at: tick) else { continue }
                switch errand.kind {
                case .eat:
                    food = eat(&s.pawns[i], from: food, mealCost: mealCost,
                               ration: ration, share: share)
                case .warmUp:
                    s.pawns[i].needs.warmth = max(s.pawns[i].needs.warmth, hearthWarmth)
                }
                s.pawns[i].needs = s.pawns[i].needs.clamped()
                s.pawns[i].errand = nil
                continue
            }
            // Nothing biting, nothing to do.
            let hungry = s.pawns[i].needs.hunger < hungryBelow
            let cold = s.pawns[i].needs.warmth < coldBelow
            guard hungry || cold else { continue }
            // Hunger first: being cold is survivable for longer than being
            // empty, and a person who is both goes for the food.
            let kind: Errand.Kind = hungry ? .eat : .warmUp
            // Somebody has to actually be able to answer it. No food in the
            // store and no trip is worth making — that is the colony *failing
            // to feed people*, which is exactly what should happen.
            if kind == .eat, food < mealCost { continue }
            let candidates = kind == .eat ? larders : hearths
            let start = anchor(of: s.pawns[i], in: s, registry: registry)
            guard let target = nearest(to: start, among: candidates) else {
                // No granary and no hearth built yet: a colony this young eats
                // at the fire in the middle of it, so the errand still happens
                // and still takes time.
                s.pawns[i].errand = leg(kind, from: start, to: SettlementGeometry.heart,
                                        tick: tick, placementID: nil)
                continue
            }
            guard SiegeField.distance(start, target.at) <= furthestWorthGoing else { continue }
            s.pawns[i].errand = leg(kind, from: start, to: target.at,
                                    tick: tick, placementID: target.id)
        }

        s.storage[.food] = max(0, food)
        return s
    }

    // MARK: - Pieces

    /// A meal, out of the store.
    ///
    /// Returns what is left of the food. A colonist fills up if the store can
    /// afford it and takes what there is if it cannot — a half-empty granary
    /// feeds people badly rather than not at all.
    ///
    /// `share` is the one thing a per-tick top-up got right for free and a sit-
    /// down meal has to be told: in a famine nobody may eat the granary. The old
    /// code handed every colonist the same six points every tick, so a nearly
    /// empty store was spread evenly over everybody by construction. A meal that
    /// fills you would let whoever reached the door first take the last of it,
    /// which turns a lean winter into a lottery. Capping one sitting at a head's
    /// worth of what is in the store keeps a famine a famine for everyone.
    private static func eat(
        _ pawn: inout Pawn, from food: Double, mealCost: Double,
        ration: ColonyPolicy.Ration, share: Double
    ) -> Double {
        let wanted = max(0, 100 - pawn.needs.hunger)
        guard wanted > 0, food > 0, mealCost > 0 else { return food }
        // What one point of hunger costs at whatever the colony calls a meal.
        // Straight off the two numbers the old inline top-up used, so full
        // rations in plenty cost the granary exactly what they always did.
        let perPoint = mealCost / (PawnEngine.hungerPerMeal * ration.hungerPerMeal)
        let cost = min(min(food, max(mealCost, share)), wanted * perPoint)
        pawn.needs.hunger += cost / perPoint
        return food - cost
    }

    private static func leg(
        _ kind: Errand.Kind, from: LocalPoint, to: LocalPoint, tick: Int,
        placementID: UUID?
    ) -> Errand {
        let ticks = max(1, Int((SiegeField.distance(from, to) / pace).rounded(.up)))
        return Errand(kind: kind, from: from, to: to, leftAt: tick,
                      arrivesAt: tick + ticks, placementID: placementID)
    }

    /// Where a colonist is when the need bites: at their work if they have any,
    /// at their door if they have one, and in the middle of town otherwise.
    static func anchor(
        of pawn: Pawn, in settlement: Settlement, registry: GameDataRegistry
    ) -> LocalPoint {
        if let job = pawn.currentJob { return job.position }
        if let home = pawn.homeID, let colony = settlement.colony,
           let placement = colony.placements.first(where: { $0.id == home }) {
            return SettlementGeometry.canvasPoint(for: placement, in: colony)
        }
        return SettlementGeometry.heart
    }

    /// Every finished building that satisfies `wanted`, with where it stands.
    static func places(
        in settlement: Settlement, registry: GameDataRegistry,
        wanted: (BuildingDefinition) -> Bool
    ) -> [(id: UUID, at: LocalPoint)] {
        guard let colony = settlement.colony else { return [] }
        return colony.placements.compactMap { placement in
            guard !placement.underConstruction,
                  let def = registry.building(placement.definitionID),
                  wanted(def) else { return nil }
            return (placement.id, SettlementGeometry.canvasPoint(for: placement, in: colony))
        }
    }

    /// Ties break on id, never on array order — the same colony must always
    /// send the same person to the same door.
    static func nearest(
        to point: LocalPoint, among places: [(id: UUID, at: LocalPoint)]
    ) -> (id: UUID, at: LocalPoint)? {
        places.min {
            let a = SiegeField.distance(point, $0.at), b = SiegeField.distance(point, $1.at)
            return a == b ? $0.id.uuidString < $1.id.uuidString : a < b
        }
    }
}
