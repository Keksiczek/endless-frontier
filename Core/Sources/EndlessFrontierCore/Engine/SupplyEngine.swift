import Foundation

/// One of your settlements keeping another alive.
///
/// A realm of several towns had exactly one way of moving goods between them:
/// a standing trade route, which is a frictionless per-tick trickle nobody
/// decides on and nobody can see. So an outpost founded in the mountains — no
/// fields, all ore — either had a route drawn to it at some point or slowly
/// starved while the capital's granary sat full three valleys away.
///
/// Supply is the colony noticing. When one of your settlements is genuinely
/// short of something another has plenty of, a caravan is loaded and sent: real
/// cargo, real guards out of the sending town, several ticks on the road, and
/// the same chance of being ambushed as any other. It is slower than a trade
/// route and it can be lost — which is the point, because it is *shipping*
/// rather than an accountant's entry.
///
/// Deterministic and on a long cadence: one pass over the settlements, and the
/// caravan machinery does the rest.
public enum SupplyEngine {

    /// How often the realm looks at itself, in ticks.
    public static let interval = 40
    /// Below this many ticks of stores, a settlement is *short*.
    ///
    /// Measured in mouths rather than in units: twenty souls with two hundred
    /// food are fine, and five souls with the same are rich.
    public static let shortOfDays: Double = 12
    /// A settlement will not send goods that take it below this share of its
    /// own comfortable level — nobody starves their own town to save another.
    public static let keepBackShare: Double = 0.55
    /// The most one caravan carries.
    public static let maxCargo: Double = 120
    /// How many guards go with it. They come out of the sending town's
    /// working population, so a shipment costs the sender labour as well.
    public static let escortSize = 2
    /// Only one shipment on the road at a time between the same two towns.
    public static let maxInFlightPerPair = 1

    /// The resources worth shipping. Knowledge and influence do not travel in
    /// a cart.
    public static let shipped: [ResourceType] = [.food, .materials]

    /// **The goods worth shipping**, by item id.
    ///
    /// Keks, on a colony whose whole industry was starved of timber and whose
    /// valley genuinely cannot feed it: *"to už asi neni řešení, je to prostě
    /// náročné to uživit … taky můžeme posílat dřevo z jiných osad."* He is
    /// right on both halves. A plains valley of fifty trees does not feed a
    /// town of a hundred and thirty, and planting more of them is a rate the
    /// forest sets, not one the colony does. What a *realm* can do is carry
    /// timber in from the outpost in the hills that has more wood than people.
    ///
    /// Deliberately the **bottom of the chain** and not the whole shelf: the
    /// raw goods and the first thing made out of each, which is where a
    /// shortage actually bites. Shipping finished gear between towns is a
    /// different feature (it would need to move `ItemInstance`s, which carry
    /// quality and wear), and shipping food-stuffs would quietly undo the
    /// cooking chain's local character.
    public static let shippedGoods: [String] = [
        "wood", "timber_bundle", "charcoal",
        "rough_stone", "brick", "clay",
        "iron_ore", "iron_ingot"
    ]

    /// How many of a good a settlement wants in hand, per pair of hands.
    ///
    /// Flat per soul rather than per bench: a colony's appetite for timber is
    /// its building programme and its fires, and both scale with how many
    /// people there are. Small — a cart of forty timber bundles is a real
    /// delivery — so a town is *short* only when it is genuinely bare, and the
    /// realm does not spend its whole life carting goods in circles.
    public static let goodsPerSoul: Double = 0.5

    /// The fewest of a good worth loading a cart with. A cart carrying four
    /// bricks across two valleys is a cart that should not have gone.
    public static let leastWorthCarting = 12

    /// What a settlement wants to have in hand, given how many mouths it feeds.
    public static func comfortable(_ settlement: Settlement, resource: ResourceType) -> Double {
        let mouths = max(1, Double(settlement.pawns.count))
        switch resource {
        case .food: return mouths * shortOfDays
        case .materials: return mouths * 6
        default: return 0
        }
    }

    /// Looks at the realm and loads whatever needs loading.
    public static func advanceOneTick(
        _ state: WorldState, registry: GameDataRegistry
    ) -> WorldState {
        guard state.tick % interval == 0, state.settlements.count > 1 else { return state }
        var s = state

        for resource in shipped {
            // Who is short, worst first — the one closest to going hungry gets
            // the first cart.
            let needy = s.settlements.indices
                .map { (index: $0, gap: comfortable(s.settlements[$0], resource: resource)
                                        - s.settlements[$0].storage[resource]) }
                .filter { $0.gap > 0 }
                .sorted { $0.gap > $1.gap }
            guard !needy.isEmpty else { continue }

            // One cart per resource per check, to the town that needs it most.
            //
            // The first pass loaded a cart for *every* short settlement on
            // every check, each of which scans the whole realm for a donor: a
            // realm that grows over a long game turns that into a convoy fleet
            // and an offline catch-up into an O(settlements²) bill per check —
            // which is exactly what `catchUpScalesLinearly` caught. A realm
            // sends a cart and looks again later, which is also how shipping
            // actually works.
            for want in needy.prefix(1) {
                guard let giver = donor(in: s, for: resource, excluding: want.index) else { break }
                let destinationID = s.settlements[want.index].id
                let originID = s.settlements[giver].id
                // One cart at a time on any given road.
                let inFlight = s.caravans.count {
                    $0.originID == originID && $0.destinationID == destinationID
                }
                guard inFlight < maxInFlightPerPair else { continue }

                let sparable = spare(s.settlements[giver], resource: resource)
                let cargo = min(maxCargo, min(sparable, want.gap))
                guard cargo >= 10 else { continue }

                // Who walks with it: able adults who are not away, in the
                // settlement's own order so the same realm always sends the
                // same people.
                let ticksPerYear = max(1, registry.config.ticksPerYear)
                let escort = s.settlements[giver].pawns
                    .filter { $0.isAdult(ticksPerYear: ticksPerYear) && !$0.isBroken
                                && !$0.isAway && $0.health > 40 }
                    .prefix(escortSize).map(\.id)
                guard escort.count == escortSize else { continue }

                let before = s.caravans.count
                s = CaravanEngine.dispatch(s, originID: originID,
                                           destinationID: destinationID,
                                           resource: resource, amount: cargo,
                                           guardIDs: escort)
                guard s.caravans.count > before else { continue }
                if let oi = s.settlements.firstIndex(where: { $0.id == originID }) {
                    let to = s.settlements[want.index].name
                    s.settlements[oi].journal.append(
                        tick: s.tick, kind: .departure, text: LocalizedText(values: [
                            .en: "A cart went out to \(to) with what they were short of.",
                            .cs: "Do \(to) vyjel vůz s tím, co jim chybělo."]))
                }
            }
        }
        return shipGoods(s, registry: registry)
    }

    /// The same pass, for the things on the shelf.
    ///
    /// Kept as its own function rather than folded into the loop above because
    /// the two measure differently at every step: a resource has a roof and a
    /// per-tick draw, a good is a whole-unit count with neither. Sharing the
    /// loop would have meant a `switch` in five places to say which of two
    /// quantities every line meant (rule 8, the other way round).
    static func shipGoods(_ state: WorldState, registry: GameDataRegistry) -> WorldState {
        var s = state
        for item in shippedGoods {
            let needy = s.settlements.indices
                .map { (index: $0, gap: wanted(s.settlements[$0]) - Double(s.settlements[$0].stockpile[item, default: 0])) }
                .filter { $0.gap > 0 }
                .sorted { $0.gap > $1.gap }
            guard let want = needy.first,
                  let giver = goodsDonor(in: s, for: item, excluding: want.index)
            else { continue }

            let destinationID = s.settlements[want.index].id
            let originID = s.settlements[giver].id
            let inFlight = s.caravans.count {
                $0.originID == originID && $0.destinationID == destinationID
            }
            guard inFlight < maxInFlightPerPair else { continue }

            let cargo = min(maxCargo, min(spareGoods(s.settlements[giver], item: item), want.gap))
            guard cargo >= Double(leastWorthCarting) else { continue }

            let ticksPerYear = max(1, registry.config.ticksPerYear)
            let escort = s.settlements[giver].pawns
                .filter { $0.isAdult(ticksPerYear: ticksPerYear) && !$0.isBroken
                            && !$0.isAway && $0.health > 40 }
                .prefix(escortSize).map(\.id)
            guard escort.count == escortSize else { continue }

            let before = s.caravans.count
            s = CaravanEngine.dispatch(s, originID: originID,
                                       destinationID: destinationID,
                                       load: .goods(item), amount: cargo.rounded(.down),
                                       guardIDs: escort, registry: registry)
            guard s.caravans.count > before else { continue }
            if let oi = s.settlements.firstIndex(where: { $0.id == originID }) {
                let to = s.settlements[want.index].name
                let goodName = registry.item(item)?.name
                s.settlements[oi].journal.append(
                    tick: s.tick, kind: .departure, text: LocalizedText(values: [
                        .en: "A load of \(goodName?.resolve(.en) ?? item) went out to \(to).",
                        .cs: "Do \(to) vyjel náklad — \(goodName?.resolve(.cs) ?? item)."]))
            }
        }
        return s
    }

    /// What a settlement wants to have of any one good.
    static func wanted(_ settlement: Settlement) -> Double {
        max(1, Double(settlement.pawns.count)) * goodsPerSoul
    }

    /// The settlement best able to spare some of a good.
    static func goodsDonor(in state: WorldState, for item: String, excluding index: Int) -> Int? {
        state.settlements.indices
            .filter { $0 != index
                        && spareGoods(state.settlements[$0], item: item) >= Double(leastWorthCarting) }
            .max { spareGoods(state.settlements[$0], item: item)
                    < spareGoods(state.settlements[$1], item: item) }
    }

    /// What a settlement can send of a good without going short itself.
    static func spareGoods(_ settlement: Settlement, item: String) -> Double {
        let keep = wanted(settlement) / keepBackShare
        return max(0, Double(settlement.stockpile[item, default: 0]) - keep)
    }

    /// The settlement best able to spare some, if any is.
    static func donor(in state: WorldState, for resource: ResourceType,
                      excluding index: Int) -> Int? {
        state.settlements.indices
            .filter { $0 != index && spare(state.settlements[$0], resource: resource) >= 10 }
            .max { spare(state.settlements[$0], resource: resource)
                    < spare(state.settlements[$1], resource: resource) }
    }

    /// What a settlement can send without hurting itself.
    static func spare(_ settlement: Settlement, resource: ResourceType) -> Double {
        let keep = comfortable(settlement, resource: resource) / keepBackShare
        return max(0, settlement.storage[resource] - keep)
    }
}
