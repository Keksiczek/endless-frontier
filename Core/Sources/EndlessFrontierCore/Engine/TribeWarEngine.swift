import Foundation

/// **Marching on a neighbour.**
///
/// A war had one direction. Everything in `WarState` counted a raid *they*
/// made — how many came, how many the wall turned back, what they carried off —
/// and `DiplomacyEngine.declareWar` set a flag and then left the player to be
/// attacked. There was no party you could send, no engine to resolve one, and
/// no field to record it in. Keks, having looked for the button: *"nevím, jak
/// udělat nájezd na město."* He was right; it did not exist.
///
/// It is deliberately **not** a new system. A march is a `RegionExpedition` —
/// the same walk out, the same days at the far end, the same walk home the
/// colony already makes to a ruin or an outlaw camp — and what waits there is a
/// `SiteEncounter`, so the fight is the one the player has already learned. The
/// only things this file owns are what a people looks like when you walk into
/// them, and what it costs both sides afterwards.
///
/// `OutlawCampEngine` is the near neighbour and the template. The differences
/// are the ones that matter: outlaws are broken and re-form, because a country
/// with nothing left to fight is a country with nothing left to do; **a people
/// is not.** What you take off a tribe is taken, and if you keep marching they
/// run out of people.
public enum TribeWarEngine {

    /// How much of a people has to be put down before the march counts as
    /// having got in. Below this they were bloodied at the edge and the party
    /// came away — the honest outcome for a party that arrived too small.
    public static let brokeInAtShare = 0.6

    /// The most of their granary one march can carry off, at a total victory.
    /// A war of extermination should take several summers, not one.
    public static let maxPlunderShare = 0.35

    /// The most of their people one march can cost them, likewise.
    public static let maxPopulationShare = 0.18

    // MARK: - Whether you can go at all

    /// Whether the colony may march on whoever lives in `regionID`.
    ///
    /// A war has to be declared first. That is the whole reason the declaration
    /// exists: before this, `declareWar` bought the player nothing they could
    /// act on, so the verb was a mood.
    public static func target(
        in state: WorldState, regionID: UUID
    ) -> Tribe? {
        guard let tribe = state.tribes.first(where: { $0.regionID == regionID }),
              tribe.discovered, tribe.war != nil,
              // Somewhere the colony has actually been. You cannot march on a
              // rumour.
              state.regions.first(where: { $0.id == regionID })?.explorationState != .unknown
        else { return nil }
        return tribe
    }

    // MARK: - What is waiting there

    /// A people, laid out as a place a party walks into.
    ///
    /// Their fighters are `defense` divided among a plausible number of bodies,
    /// so the same total is a different fight for a small hard people than for
    /// a large soft one. Their granary is the cache — it is what a march is
    /// for, and it is the thing they lose that they notice.
    public static func encounter(
        for tribe: Tribe, party: [UUID], seed: UInt64
    ) -> SiteEncounter {
        var rng = SeededRNG(seed: seed)
        var things: [SiteEncounter.Thing] = []
        let middle = LocalPoint(x: 0.5, y: 0.5)
        func place(_ spread: Double) -> LocalPoint {
            let angle = rng.nextUnit() * 2 * .pi
            let radius = spread * (0.35 + rng.nextUnit() * 0.65)
            return LocalPoint(x: middle.x + cos(angle) * radius,
                              y: middle.y + sin(angle) * radius)
        }

        // Who turns out. Not everybody in a town fights: a share of the grown
        // population, floored at one so a people down to its last family is
        // still somebody standing in a doorway rather than an empty field.
        let heads = max(1, min(14, Int((tribe.population * defenderShare).rounded())))
        let each = max(0.5, tribe.defense / Double(heads))
        for index in 0..<heads {
            things.append(SiteEncounter.Thing(
                id: index, kind: .guardian, at: place(0.24),
                strength: each * (0.75 + rng.nextUnit() * 0.5),
                label: LocalizedText(values: [
                    .en: "A fighter of \(tribe.name)",
                    .cs: "Bojovník \(tribe.name)"])))
        }
        // A town that has been fought over before knows to dig. Their grudge is
        // the memory of it, so the ones you have hurt are the ones that are
        // ready for you.
        if tribe.grudge > 30 {
            things.append(SiteEncounter.Thing(
                id: things.count, kind: .trap, at: place(0.32),
                strength: min(12, tribe.grudge * 0.12),
                label: LocalizedText(values: [
                    .en: "A ditch and a stake line", .cs: "Příkop a řada kůlů"])))
        }
        things.append(SiteEncounter.Thing(
            id: things.count, kind: .cache, at: place(0.12), strength: 1,
            label: LocalizedText(values: [
                .en: "\(tribe.name)'s stores", .cs: "Sýpka \(tribe.name)"])))

        var places: [UUID: LocalPoint] = [:]
        for (index, id) in party.enumerated() {
            let angle = Double(index) / Double(max(1, party.count)) * 2 * .pi
            places[id] = LocalPoint(x: middle.x + cos(angle) * 0.38,
                                    y: middle.y + sin(angle) * 0.38)
        }
        return SiteEncounter(things: things, places: places, seed: rng.next())
    }

    /// The share of a people who stand and fight when somebody comes for them.
    static let defenderShare = 0.22

    // MARK: - What it cost, on both sides

    /// Applies a march's outcome, in proportion to how much of the place the
    /// party actually cleared.
    ///
    /// Everything here scales with `share`, including the failures: a party
    /// that got a third of the way in took a third of what it could have, cost
    /// them a third of what it might have, and earned a third of the hatred.
    /// A march is never free of consequence, and never total.
    public static func sacked(
        _ state: WorldState, tribeID: UUID, settlementIndex: Int, share: Double
    ) -> (WorldState, March?) {
        guard let index = state.tribes.firstIndex(where: { $0.id == tribeID })
        else { return (state, nil) }
        var s = state
        let before = s.tribes[index]
        let got = min(1, max(0, share))
        let brokeIn = got >= brokeInAtShare

        // Their granary, in proportion. Carried into the settlement that sent
        // the party — the food and materials of it; a people does not keep a
        // pile of knowledge for somebody to walk off with.
        let plunder = before.stores * maxPlunderShare * got
        s.tribes[index].stores = max(0, before.stores - plunder)
        if s.settlements.indices.contains(settlementIndex) {
            s.settlements[settlementIndex].storage[.food] += plunder * 0.6
            s.settlements[settlementIndex].storage[.materials] += plunder * 0.4
        }

        // What it cost them to hold the place, and the people who did not get
        // up. Both recover — `DiplomacyEngine` grows a tribe back — so a war is
        // attrition rather than a switch.
        let strengthLost = before.defense * got
        let dead = before.population * maxPopulationShare * got
        s.tribes[index].defense = max(0, before.defense - strengthLost)
        s.tribes[index].population = max(0, before.population - dead)

        // And what it did to how they feel about you, which is the part that
        // outlives the granary. Marching on a people is the strongest thing you
        // can do to a relationship, and it does not wash off.
        s.tribes[index].grudge = min(100, before.grudge + 12 + 28 * got)
        s.tribes[index].standing = max(-100, before.standing - (8 + 24 * got))

        if var war = s.tribes[index].war {
            war.sorties += 1
            if brokeIn { war.sortiesWon += 1 }
            war.theirStrengthSpent += strengthLost
            war.plunder += plunder
            s.tribes[index].war = war
        }

        return (s, March(tribeID: before.id, tribeName: before.name,
                         plunder: plunder, theirDead: dead,
                         strengthSpent: strengthLost, brokeIn: brokeIn,
                         scattered: s.tribes[index].population < 1))
    }

    /// What a colony learns when its party comes back from a neighbour.
    public struct March: Sendable, Equatable {
        public let tribeID: UUID
        public let tribeName: String
        /// What was carried home out of their stores.
        public let plunder: Double
        /// How many of them did not get up.
        public let theirDead: Double
        /// The weight of them that had to be put down to do it.
        public let strengthSpent: Double
        /// Whether the party got into the place rather than being held at it.
        public let brokeIn: Bool
        /// Whether that was the last of them.
        public let scattered: Bool
    }
}
