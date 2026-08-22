import Foundation

/// **What a people looks like, standing on their own ground.**
///
/// Keks, on the neighbours: *"nyní jsou to basic postavičky a stany na mapě"*
/// — and, asked how far to take it: *"ideálně plné národy, ale klidně bych to
/// nejdřív trochu osekal, ať není tak složitá simulace — jen ať vypadají a
/// chovají se nějak jako hlavní pawni."*
///
/// So this is **stage one**, and the line it must not cross is written down
/// here rather than trusted to memory: **stage one adds nothing to the tick.**
/// Nothing in this file is stored in `WorldState`, nothing here is advanced by
/// an engine, and the moment a tribe's pawns eat, it has become stage two —
/// the same engines running on a second settlement — which is a second
/// simulation's worth of ticks per people and wants measuring first.
///
/// What it *is*: a pure function from a tribe's own facts — its id, how many
/// they are, what they hold, what they are like — to a `Settlement` shaped
/// exactly like yours. Real `BuildingPlacement`s on the same build grid, real
/// `Pawn`s with bodies, ages, looks and trades, each with a roof of their own
/// and a bench to stand at. The canvas then draws them with the code it
/// already has: `SettlementRenderer.layout`, `AgentMotion`, `SettlementFigures`.
/// There is no second renderer and no second kind of person.
///
/// Their **numbers stay `DiplomacyEngine`'s**. `Tribe.population`, `standing`,
/// `stores` and `genes` go on deciding everything they do; the roster is what
/// those numbers *look like*, derived fresh whenever somebody opens their hex.
public enum TribeCamp {

    /// The most of a people who are actually drawn.
    ///
    /// A tribe of four hundred is four hundred figures at thirty frames a
    /// second on a phone, for a place the player is *visiting*. The colony's
    /// own canvas has the same cap for the same reason
    /// (`SettlementRenderer.maxVisibleAgents`); the difference is that here
    /// the roster is derived rather than real, so the cap is applied when it
    /// is built rather than when it is drawn.
    public static let mostDrawn = 40

    /// How many souls share one roof. Rough, and it only decides how many huts
    /// stand — a camp with one hut and thirty people in it reads as wrong long
    /// before anybody counts.
    static let perRoof = 4.0

    /// **A tribe as a settlement.** Deterministic in `(mapSeed, tribe.id)`, so
    /// the same people are the same people every time their hex is opened, and
    /// two runs of one world put the same person outside the same tent (rule 2).
    public static func settlement(
        for tribe: Tribe, mapSeed: UInt64, era: Era,
        registry: GameDataRegistry, language: GameLanguage = .cs
    ) -> Settlement {
        var rng = SeededRNG(seed: seed(mapSeed: mapSeed, tribe: tribe))
        let drawn = min(mostDrawn, max(2, Int(tribe.population.rounded())))

        let buildings = roster(for: tribe, era: era, drawn: drawn)
        var s = Settlement(
            id: tribe.id, name: tribe.name, kind: .outpost,
            regionID: tribe.regionID, foundedTick: tribe.foundedTick,
            buildings: buildings,
            storage: [.food: tribe.stores, .materials: tribe.stores * 0.4],
            colony: ColonyBuilder.seededLayout(for: buildings, registry: registry))

        // Their people. Drawn from the tribe's own stock, so a people who are
        // braver than you *are* braver than you when you look at them — the
        // genes `DiplomacyEngine` has always used to decide whether you get on
        // are the genes the person outside the tent is carrying.
        var people: [Pawn] = []
        for index in 0..<drawn {
            var pawn = PawnFactory.generate(
                seed: rng.next() &+ UInt64(index) &* 0x9E37_79B9_7F4A_7C15,
                language: language, stock: tribe.genes)
            // A camp is not a colony: nobody here is researching or banking.
            pawn.assignedWork = trade(for: index, of: drawn, tribe: tribe, using: &rng)
            people.append(pawn)
        }
        s.pawns = people

        // A roof each and a bench each, through the same two functions the
        // colony uses — so a tribesman stands in a doorway for the same reason
        // one of yours does, and `AgentMotion` needs to know nothing new.
        s = HouseholdEngine.assignHomes(s, registry: registry)
        for pawn in s.pawns {
            s = ColonyBuilder.autoAssign(s, pawnID: pawn.id, registry: registry)
        }
        return s
    }

    /// The seed everything about a camp comes from. Their own id and the
    /// world's — never a `UUID()` and never a clock (rule 2).
    static func seed(mapSeed: UInt64, tribe: Tribe) -> UInt64 {
        var h: UInt64 = mapSeed &* 0x9E37_79B9_7F4A_7C15
        for byte in tribe.id.uuidString.utf8 { h = (h ^ UInt64(byte)) &* 0x0100_0000_01B3 }
        return h ^ (h >> 29)
    }

    /// **What they have built.** Not a copy of your building list: a people who
    /// walked out of somebody's colony live in huts, keep a longhouse if there
    /// are enough of them to need one, and put a fence up if they have had to
    /// fight. Everything here is read off the tribe's own numbers, so a people
    /// who have grown, stockpiled or armed since you last looked have visibly
    /// done so.
    static func roster(for tribe: Tribe, era: Era, drawn: Int) -> [BuildingInstance] {
        var out: [BuildingInstance] = []
        func add(_ id: String, _ count: Int) {
            guard count > 0 else { return }
            out.append(BuildingInstance(definitionID: id, count: count))
        }
        // Roofs first: how many they are is the one thing a place says at a
        // glance, and it must say the same number `Tribe.population` does.
        add("hut", max(2, min(12, Int((Double(drawn) / perRoof).rounded(.up)))))
        // A hall, once there are enough of them to gather.
        add("longhouse", tribe.population >= 24 ? 1 : 0)
        // Fields, once they are too many to live off the wood alone.
        add("farm_basic", min(3, Int(tribe.population / 30)))
        // What they hunt with, and what they keep.
        add("hunters_lodge", tribe.genes.courage > 0.5 ? 1 : 0)
        add("granary", tribe.stores >= 80 ? 1 : 0)
        // A fence is a thing you build after somebody has come for you.
        add("palisade", tribe.defense >= 25 || tribe.wars > 0 ? 1 : 0)
        // …and a well, once the camp is a village rather than a stopping place.
        add("well", tribe.population >= 40 ? 1 : 0)
        return out
    }

    /// What one of them does. Weighted the way a camp is: mostly the food and
    /// the wood, a few hands on everything else, and a hunter or two if they
    /// are the sort of people who hunt.
    static func trade(
        for index: Int, of drawn: Int, tribe: Tribe, using rng: inout SeededRNG
    ) -> WorkKind {
        let roll = rng.nextUnit()
        if roll < 0.34 { return .farming }
        if roll < 0.52 { return .logging }
        if roll < 0.52 + 0.16 * tribe.genes.courage { return .hunting }
        if roll < 0.78 { return .building }
        if roll < 0.88 { return .crafting }
        if roll < 0.95 { return .cooking }
        return .garrison
    }
}
