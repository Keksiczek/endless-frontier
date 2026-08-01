import Foundation

/// Who lives where.
///
/// A settlement has always known how many souls it can *hold* — the housing
/// capacity its dwellings add up to — and never which of them lives in which
/// house. Nobody had an address. The canvas therefore picked a house for each
/// colonist out of a list every time it drew them, which is why a dozen people
/// slept stacked on one doorstep while three huts stood empty beside it, and
/// why a town of sixty read as a crowd rather than as a place.
///
/// This gives every colonist a **home**: one dwelling, held until it is pulled
/// down or they die. A dwelling holds as many as it has room for — beds, not
/// ledger capacity — and the colonists a colony has no room for **sleep
/// rough**, which is not a cosmetic detail: they rest worse and their mood
/// says so, so "build another house" becomes a thing the colony asks you for by
/// visibly suffering rather than by a number going up.
///
/// Deterministic and cheap: one pass over the pawns in their stored order, on
/// the same ten-tick cadence as staffing, because offline catch-up replays tens
/// of thousands of ticks through here.
public enum HouseholdEngine {

    /// How many people one tile of dwelling actually sleeps.
    ///
    /// Deliberately *not* `BuildingDefinition.housing`, which is an economic
    /// capacity — a hut says 30, which is a village in a shed. A house is a
    /// household: a one-tile hut sleeps a family, a two-by-two longhouse sleeps
    /// three of them. The ledger keeps its own number and the population cap is
    /// untouched; this is about where people are, and how well they sleep.
    public static let sleepersPerTile = 4

    /// The most one dwelling will ever take, however large it is — past this
    /// the room is a dormitory and the point of a home is lost.
    public static let maxPerDwelling = 24

    /// How much of a colonist's nightly rest a real bed is worth. Sleeping
    /// rough recovers this share of it and no more.
    public static let roughSleepFactor = 0.55
    /// …and what it costs their spirits, in mood points, while it lasts. Big
    /// enough to notice on a face and in the ledger, small enough that a colony
    /// briefly outgrowing its roofs does not spiral.
    public static let roughSleepMood: Double = 8

    /// How often homes are reassigned, in ticks.
    public static let interval = LaborEngine.staffingInterval

    /// How many sleepers a placement can take.
    public static func beds(_ placement: BuildingPlacement, registry: GameDataRegistry) -> Int {
        // Nobody sleeps in a house with the roof off.
        guard BuildingEngine.isWorking(placement) else { return 0 }
        guard let def = registry.building(placement.definitionID), def.housing > 0 else { return 0 }
        let tiles = max(1, placement.width * placement.height)
        // A dwelling never sleeps more than its own ledger capacity claims it
        // can hold, so a bunkhouse-by-data stays a bunkhouse.
        return min(maxPerDwelling, min(Int(def.housing), tiles * sleepersPerTile))
    }

    /// Gives everyone who can have a home a home, and leaves the rest without
    /// one. Keeps existing households together: a colonist is only moved when
    /// the house they lived in has gone.
    public static func assignHomes(
        _ settlement: Settlement, registry: GameDataRegistry
    ) -> Settlement {
        guard let colony = settlement.colony else { return settlement }
        // Dwellings that are actually standing, in the grid's own order so the
        // same colony always fills the same houses first.
        var room: [UUID: Int] = [:]
        var order: [UUID] = []
        for placement in colony.placements where !placement.underConstruction {
            let count = beds(placement, registry: registry)
            guard count > 0 else { continue }
            room[placement.id] = count
            order.append(placement.id)
        }

        var pawns = settlement.pawns
        var changed = false

        // Anyone whose house is still standing keeps it — a home you are moved
        // out of every ten ticks is not a home.
        for i in pawns.indices {
            guard let home = pawns[i].homeID else { continue }
            if let left = room[home], left > 0 {
                room[home] = left - 1
            } else {
                pawns[i].homeID = nil
                changed = true
            }
        }
        // Then house the homeless, in stored order, filling each dwelling
        // before moving to the next — a full house and an empty one beats two
        // half-empty ones, and it keeps households together on the canvas.
        var cursor = 0
        for i in pawns.indices where pawns[i].homeID == nil {
            while cursor < order.count, (room[order[cursor]] ?? 0) <= 0 { cursor += 1 }
            guard cursor < order.count else { break }
            let home = order[cursor]
            pawns[i].homeID = home
            room[home] = (room[home] ?? 1) - 1
            changed = true
        }

        guard changed else { return settlement }
        var s = settlement
        s.pawns = pawns
        return s
    }

    /// How many colonists have nowhere to sleep. What the objective, the
    /// journal and eventually the player read.
    public static func homeless(_ settlement: Settlement) -> Int {
        settlement.pawns.count { $0.homeID == nil && !$0.isAway }
    }

    /// The share of the colony without a bed, 0…1.
    public static func homelessFraction(_ settlement: Settlement) -> Double {
        let living = settlement.pawns.count { !$0.isAway }
        guard living > 0 else { return 0 }
        return Double(homeless(settlement)) / Double(living)
    }
}
