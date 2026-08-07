import Foundation

/// The world beyond the valley, arriving.
///
/// Trade and diplomacy were a panel: numbers moved, a line appeared in the
/// journal, and nobody ever walked in. This is the same trade and the same
/// diplomacy — the standings, the stores, the grudges are untouched — happening
/// to somebody, somewhere, in front of you. A party comes in over the edge of
/// your own ground, crosses it, does its business in the square, and goes back
/// the way it came.
///
/// Who comes is decided by the world as it stands. A people who like you send
/// traders; a people who are unsure send an envoy to find out; a people who are
/// starving send their families. Nobody comes to a colony at war with them, and
/// nobody comes to a colony nobody has met.
///
/// Deterministic — every roll comes from `(mapSeed, settlement, tick)` — and on
/// a cadence, because offline catch-up replays tens of thousands of ticks.
public enum VisitorEngine {

    /// How often the roads are checked, in ticks.
    ///
    /// A tick is about six days, so these numbers are a calendar rather than a
    /// budget: a check every thirty ticks at roughly a one-in-six chance is a
    /// party in the valley once every year or two, which is what a visit should
    /// feel like. The first pass ran four times as often and it was both a
    /// fairground and the most expensive thing in the tick.
    public static let interval = 30
    /// The chance per check that *somebody* is on the road, before the world
    /// has any say in it.
    public static let baseChance = 0.10
    /// …and how much a well-disposed neighbour adds.
    public static let chancePerFriend = 0.06
    /// The most parties on the map at once. A valley is not a fairground.
    public static let maxVisitors = 2

    // MARK: - Word getting around

    /// What a colony has to look like from outside before anybody moves to it,
    /// and how likely they are to when it does.
    ///
    /// A closed founding party is a loop with no input from outside itself, and
    /// §11.10 measured what that costs: about 0.2 births a year against 0.24
    /// deaths, so every village decays to nothing on a two-century timescale
    /// however well it is run. Rule 13 in the population's clothes — a thing
    /// that is supposed to build up has to be fed by something that is true
    /// whether or not it has already started.
    ///
    /// So this is fed by what the colony *is*, not by what it has done: a full
    /// larder, a roof going spare and people in good heart. All three, because
    /// any one of them alone is a number that drifts. That makes prosperity the
    /// growth lever and gives rule 19 a second, literal meaning — beds do not
    /// merely permit a colony to grow, they are the reason somebody comes.
    ///
    /// Deliberately small. §11.2 asked for a village you can hold in your head,
    /// so this is worth a household every decade or two to a colony that is
    /// doing everything right, and nothing at all to one that is not.
    public static let settlerChance = 0.16
    /// Food per head the larder has to hold before the colony looks like it
    /// could feed one more.
    public static let settlerFoodPerHead: Double = 14
    /// …and beds standing empty, so there is somewhere to put them.
    public static let settlerSpareBeds = 2
    /// …and a town that is not visibly miserable.
    public static let settlerMorale: Double = 55
    /// How long a party stands in the square before starting home.
    public static let stayTicks = 12
    /// How far they cover per tick.
    public static let pace: Double = 0.03
    /// Close enough to the square to be *at* it.
    public static let arrivalRadius: Double = 0.03

    // MARK: - The tick

    /// The decision each kind of party puts in front of the Leader when it
    /// reaches the square.
    ///
    /// Authored content, not code: the choices, their costs and their
    /// consequences live in `events.json` in both languages, and the whole
    /// decision UI — the card, the deadline, the queue — is the one the
    /// storyteller already uses. A party that merely arrived and left again was
    /// scenery; a party you have to *answer* is the game.
    public static func decision(for kind: VisitorKind) -> String? {
        switch kind {
        case .refugee: return "visitors_refugees"
        case .envoy: return "visitors_envoy"
        case .trader: return "visitors_traders"
        // A traveller used to want nothing from you, which made them the one
        // kind of visitor who could not change anything. Some of them have been
        // walking a long time and would rather stop — and a colony that only
        // ever grows out of its own cradle decays on a two-century timescale
        // however well it is run (§11.10). This is the door that is a decision.
        case .wanderer: return "visitors_wanderer"
        // Word gets around on its own, and a family that has decided to move is
        // not asking permission — see `settle`. That door has no card, which is
        // the whole reason it is a different door: an unanswered decision
        // expires with none of its effects applied (`StoryPlanner.expire
        // Decisions`), so a colony whose *only* way to grow needs a tap is a
        // colony that dies whenever nobody is watching.
        case .settler: return nil
        }
    }

    public static func advanceOneTick(
        _ state: WorldState, registry: GameDataRegistry, mapSeed: UInt64
    ) -> WorldState {
        let tick = state.tick
        // Nothing to do on the overwhelming majority of ticks: nobody is on the
        // road and it is not a day for checking. Returning `state` untouched
        // rather than a rebuilt copy is what keeps this off the offline
        // catch-up's bill — a settlement is a big value, and writing one back
        // forty thousand times to change nothing is not free.
        let anyoneAbout = state.settlements.contains { !($0.localMap?.visitors.isEmpty ?? true) }
        guard anyoneAbout || tick % interval == 0 else { return state }

        var s = state
        if anyoneAbout {
            for index in s.settlements.indices
            where !(s.settlements[index].localMap?.visitors.isEmpty ?? true) {
                let stepped = walk(s.settlements[index], world: s, tick: tick)
                s.settlements[index] = stepped.settlement
                // A party that has reached the square wants an answer. Only the
                // capital's callers reach the Leader — an outpost settles its
                // own visits, which is what an outpost is for.
                if let ask = stepped.asks, index == 0,
                   registry.events.contains(where: { $0.id == ask }) {
                    s.pendingEvents.removeAll { $0.templateID == ask }
                    s.pendingEvents.append(PendingEvent(templateID: ask, tick: tick))
                }
            }
        }
        guard tick % interval == 0 else { return s }
        for index in s.settlements.indices {
            s = arrive(s, settlementIndex: index, registry: registry,
                       tick: tick, mapSeed: mapSeed)
        }
        return s
    }

    // MARK: - Coming and going

    /// Moves every party a step and settles the business of any that have
    /// reached the square.
    static func walk(
        _ settlement: Settlement, world: WorldState, tick: Int
    ) -> (settlement: Settlement, asks: String?) {
        guard let existing = settlement.localMap, !existing.visitors.isEmpty else {
            return (settlement, nil)
        }
        var asks: String?
        var s = settlement
        var map = existing
        let square = SettlementGeometry.heart
        var remaining: [Visitor] = []
        remaining.reserveCapacity(map.visitors.count)

        for var visitor in map.visitors {
            switch visitor.phase {
            case .arriving:
                visitor.position = step(from: visitor.position, toward: square, by: pace)
                if within(visitor.position, square, arrivalRadius) {
                    visitor.phase = VisitorPhase.visiting
                    visitor.ticksRemaining = stayTicks
                }
            case .visiting:
                if !visitor.settled {
                    s = settle(s, visitor: visitor, world: world, tick: tick)
                    asks = asks ?? decision(for: visitor.kind)
                    visitor.settled = true
                }
                visitor.ticksRemaining -= 1
                if visitor.ticksRemaining <= 0 { visitor.phase = VisitorPhase.leaving }
            case .leaving:
                // Settlers are the one party who came to stop. They unpacked in
                // the square and they are colonists now, so there is nobody left
                // to walk back out.
                if visitor.kind == .settler { continue }
                visitor.position = step(from: visitor.position, toward: visitor.entry, by: pace)
                // Gone off the edge, and out of the save.
                if within(visitor.position, visitor.entry, arrivalRadius) { continue }
            }
            remaining.append(visitor)
        }

        map.visitors = remaining
        s.localMap = map
        return (s, asks)
    }

    /// Rolls for a party on the road, and puts them at the edge if one comes.
    static func arrive(
        _ state: WorldState, settlementIndex: Int, registry: GameDataRegistry,
        tick: Int, mapSeed: UInt64
    ) -> WorldState {
        var s = state
        guard let map = s.settlements[settlementIndex].localMap,
              map.visitors.count < maxVisitors else { return s }

        // Word getting around is the colony's own business and answers to
        // nobody's politics, so it is rolled first and on its **own** stream.
        // Inserting a draw into the one below would shift every roll after it
        // and quietly re-deal two centuries of visits in every existing save
        // (rule 2: new draws go at the end of a pass, never into the middle).
        if let party = settlerParty(s.settlements[settlementIndex],
                                    registry: registry, mapSeed: mapSeed, tick: tick) {
            var updated = map
            updated.visitors.append(party)
            s.settlements[settlementIndex].localMap = updated
            s.settlements[settlementIndex].journal.append(
                tick: tick, kind: .arrival,
                text: approachText(kind: .settler, from: party.fromName))
            return s
        }

        // Who out there is on speaking terms.
        let known = s.tribes.filter { $0.discovered && $0.status != .war }
        var rng = SeededRNG(seed: visitorSeed(mapSeed: mapSeed,
                                              settlementID: s.settlements[settlementIndex].id,
                                              tick: tick))
        let chance = min(0.35, baseChance + Double(known.count) * chancePerFriend)
        guard rng.nextUnit() < chance else { return s }

        // A wanderer needs nobody; everyone else comes from a people.
        let tribe = known.isEmpty ? nil : known[Int(rng.nextUnit() * Double(known.count)) % known.count]
        let kind = pick(for: tribe, rng: &rng)
        let name = tribe?.name ?? wandererOrigin(rng: &rng)

        // In from an edge, at a spot that is not the same one every time.
        let entry = edgePoint(rng: &rng)
        var updated = map
        updated.visitors.append(Visitor(
            id: rng.nextUUID(), kind: kind, fromName: name, tribeID: tribe?.id,
            position: entry, entry: entry))
        s.settlements[settlementIndex].localMap = updated
        s.settlements[settlementIndex].journal.append(
            tick: tick, kind: .discovery, text: approachText(kind: kind, from: name))
        return s
    }

    /// A household on the road to *this* colony, if it is the sort of place
    /// anybody would move to.
    ///
    /// All three conditions, and each is doing a different job: the larder says
    /// the colony can feed one more, the empty beds say there is somewhere to
    /// put them, and morale says the people already there are not visibly
    /// wretched. Any one alone is a number that drifts into range and stays
    /// there; the three together are a description of a place that is working.
    ///
    /// Nil when the colony is not that place — which is the half that keeps a
    /// badly run one able to die.
    static func settlerParty(
        _ settlement: Settlement, registry: GameDataRegistry,
        mapSeed: UInt64, tick: Int
    ) -> Visitor? {
        let mouths = max(1, settlement.population)
        guard settlement.storage[.food] / mouths >= settlerFoodPerHead,
              settlement.stats.morale >= settlerMorale else { return nil }
        let beds = ResourceLoop.housingCapacity(settlement, registry: registry)
        guard beds - settlement.population >= Double(settlerSpareBeds) else { return nil }

        var rng = SeededRNG(seed: visitorSeed(mapSeed: mapSeed,
                                              settlementID: settlement.id,
                                              tick: tick) ^ 0x5345_5454_4C45_5253)
        guard rng.nextUnit() < settlerChance else { return nil }
        let entry = edgePoint(rng: &rng)
        return Visitor(id: rng.nextUUID(), kind: .settler,
                       fromName: wandererOrigin(rng: &rng), tribeID: nil,
                       position: entry, entry: entry)
    }

    /// What kind of party a given people sends.
    ///
    /// Their standing decides it, which is the whole point: diplomacy stops
    /// being a number you read and becomes who turns up at your gate.
    static func pick(for tribe: Tribe?, rng: inout SeededRNG) -> VisitorKind {
        guard let tribe else { return .wanderer }
        // A people who cannot feed themselves send their families, whatever
        // they think of you.
        if tribe.stores < tribe.population * 0.4 { return .refugee }
        switch tribe.status {
        case .allied, .friendly:
            return rng.nextUnit() < 0.75 ? .trader : .envoy
        case .neutral:
            return rng.nextUnit() < 0.45 ? .trader : .envoy
        case .tense, .war:
            // They still send somebody to talk — that is what an envoy is for.
            return .envoy
        }
    }

    // MARK: - The business

    /// What a visit is actually worth. Deliberately small: a caravan is a
    /// caravan, a visit is a visit, and the point of this layer is that the
    /// world *turns up* rather than that it pays well.
    static func settle(
        _ settlement: Settlement, visitor: Visitor, world: WorldState, tick: Int
    ) -> Settlement {
        var s = settlement
        switch visitor.kind {
        case .trader:
            // Goods for goods: what a colony has too much of goes, what it is
            // short of comes. A market makes it worth more.
            let value = 18 + Double(s.buildings.reduce(0) { $0 + $1.count }) * 0.4
            s.storage[.influence] = min(s.storageCapacity, s.storage[.influence] + value * 0.5)
            s.storage[.materials] = min(s.storageCapacity, s.storage[.materials] + value)
            s.journal.append(tick: tick, kind: .arrival, text: LocalizedText(values: [
                .en: "Traders from \(visitor.fromName) unpacked in the square and did good business.",
                .cs: "Obchodníci z \(visitor.fromName) složili na návsi a odbyt byl dobrý."]))
        case .envoy:
            s.storage[.influence] = min(s.storageCapacity, s.storage[.influence] + 10)
            s.stats.morale = min(100, s.stats.morale + 2)
            s.journal.append(tick: tick, kind: .arrival, text: LocalizedText(values: [
                .en: "An envoy of \(visitor.fromName) was heard in the square.",
                .cs: "Vyslanec \(visitor.fromName) byl vyslechnut na návsi."]))
        case .refugee:
            s.journal.append(tick: tick, kind: .arrival, text: LocalizedText(values: [
                .en: "Families out of \(visitor.fromName) came in off the road, with nothing.",
                .cs: "Rodiny z \(visitor.fromName) přišly po cestě, bez ničeho."]))
        case .wanderer:
            s.storage[.knowledge] = min(s.storageCapacity, s.storage[.knowledge] + 8)
            s.stats.morale = min(100, s.stats.morale + 1)
            s.journal.append(tick: tick, kind: .discovery, text: LocalizedText(values: [
                .en: "A traveller out of \(visitor.fromName) told the evening's stories.",
                .cs: "Poutník z \(visitor.fromName) vyprávěl u ohně."]))
        case .settler:
            // They put the handcart down and that is that. No card: an
            // unanswered decision expires with none of its effects applied, so
            // a colony whose only door to growth needs a tap is a colony that
            // dies every time nobody is watching. This one is the world
            // deciding, and the player's say over it is upstream — the larder,
            // the roofs and the mood are what brought them.
            //
            // Deterministic: the party's own id seeds the household, so the
            // same world always takes in the same people (rule 2).
            var rng = SeededRNG(seed: householdSeed(visitor.id) ^ UInt64(bitPattern: Int64(tick)))
            var arrived: [String] = []
            for _ in 0..<VisitorKind.settler.partySize {
                let pawn = PawnFactory.generate(seed: rng.next(), language: world.language)
                arrived.append(pawn.name)
                s.pawns.append(pawn)
            }
            let who = arrived.joined(separator: " a ")
            let whoEN = arrived.joined(separator: " and ")
            s.journal.append(tick: tick, kind: .arrival, text: LocalizedText(values: [
                .en: "\(whoEN) came up the road from \(visitor.fromName), heard the place was doing well, and stayed.",
                .cs: "\(who) přišli po cestě od \(visitor.fromName), slyšeli, že se tu daří, a zůstali."]))
        }
        return s
    }

    /// A stable stream for the household a settler party turns into.
    static func householdSeed(_ id: UUID) -> UInt64 {
        let b = id.uuid
        var h: UInt64 = UInt64(b.0) << 56 | UInt64(b.1) << 48 | UInt64(b.2) << 40
            | UInt64(b.3) << 32 | UInt64(b.4) << 24 | UInt64(b.5) << 16
            | UInt64(b.6) << 8 | UInt64(b.7)
        h = (h ^ 0x484F_5553_4548_4F4C) &* 0x9E37_79B9_7F4A_7C15
        return h
    }

    static func approachText(kind: VisitorKind, from: String) -> LocalizedText {
        switch kind {
        case .trader:
            return LocalizedText(values: [
                .en: "A trading party out of \(from) is on the road.",
                .cs: "Po cestě jde kupecká výprava z \(from)."])
        case .envoy:
            return LocalizedText(values: [
                .en: "\(from) has sent an envoy.",
                .cs: "\(from) posílá vyslance."])
        case .refugee:
            return LocalizedText(values: [
                .en: "People are walking in from \(from).",
                .cs: "Od \(from) přicházejí lidé."])
        case .wanderer:
            return LocalizedText(values: [
                .en: "Somebody is coming up the road.",
                .cs: "Po cestě někdo přichází."])
        case .settler:
            return LocalizedText(values: [
                .en: "A handcart is coming up the road from \(from), and it is loaded for good.",
                .cs: "Po cestě od \(from) jede vozík, a je naložený nastálo."])
        }
    }

    /// Where a nameless traveller says they are from.
    static func wandererOrigin(rng: inout SeededRNG) -> String {
        let places = ["the north road", "the far hills", "downriver", "the old coast road"]
        return places[Int(rng.nextUnit() * Double(places.count)) % places.count]
    }

    // MARK: - Maths

    /// A spot on the edge of the map, away from the corners.
    static func edgePoint(rng: inout SeededRNG) -> LocalPoint {
        let along = 0.12 + rng.nextUnit() * 0.76
        switch Int(rng.nextUnit() * 4) % 4 {
        case 0: return LocalPoint(x: along, y: 0.02)
        case 1: return LocalPoint(x: 0.98, y: along)
        case 2: return LocalPoint(x: along, y: 0.98)
        default: return LocalPoint(x: 0.02, y: along)
        }
    }

    static func within(_ a: LocalPoint, _ b: LocalPoint, _ radius: Double) -> Bool {
        let dx = a.x - b.x, dy = a.y - b.y
        return dx * dx + dy * dy <= radius * radius
    }

    static func step(from: LocalPoint, toward: LocalPoint, by distance: Double) -> LocalPoint {
        let dx = toward.x - from.x, dy = toward.y - from.y
        let length = (dx * dx + dy * dy).squareRoot()
        guard length > 1e-9 else { return toward }
        let t = min(1, distance / length)
        return LocalPoint(x: from.x + dx * t, y: from.y + dy * t)
    }

    static func visitorSeed(mapSeed: UInt64, settlementID: UUID, tick: Int) -> UInt64 {
        var h: UInt64 = mapSeed &* 0x9E37_79B9_7F4A_7C15
        let b = settlementID.uuid
        h ^= UInt64(b.0) << 56 | UInt64(b.1) << 48 | UInt64(b.2) << 40 | UInt64(b.3) << 32
            | UInt64(b.4) << 24 | UInt64(b.5) << 16 | UInt64(b.6) << 8 | UInt64(b.7)
        h = (h ^ UInt64(bitPattern: Int64(tick))) &* 0xD1B5_4A32_D192_ED03
        return h ^ 0x5654_5349_544F_5253
    }
}
