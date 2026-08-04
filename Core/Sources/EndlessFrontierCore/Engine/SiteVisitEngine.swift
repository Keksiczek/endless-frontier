import Foundation

/// What happens at a place once the party actually gets there.
///
/// `SiegeEngine`'s lesson, applied to the last part of the game that was still
/// a single dice roll. A visit used to be: walk out for a few ticks, roll once
/// against `hazardChance`, add resources, walk home. The walk was simulated at
/// eight steps a tick and the *destination* was a number — so an expedition
/// felt instant however long it lasted, because nothing happened in the middle
/// of it. There was nothing to find, no way to fail, and it happened to nobody.
///
/// A place holds **things** now: something guarding it, something waiting to be
/// sprung, and something worth carrying home. The party walks between them on
/// the same action clock and deals with what it reaches. What comes back is
/// what they managed to open, not what the table said the place was worth.
///
/// The three properties the siege had to keep apply here for the same reasons:
///
/// 1. **Determinism.** A step's rolls come from `(site.seed, step)`, so a step
///    is a pure function of where it sits and never of when it was asked for.
/// 2. **A step is worked once.** Whoever reaches it first works it.
/// 3. **The place owes a record.** Beats accumulate as they happen, so a party
///    can be watched rather than reported on afterwards.
///
/// (Not to be confused with `SiteEngine`, which is the *world* map's ruins and
/// anomalies. Those are still resolved in one call — see `docs/BACKLOG.md`.)
public enum SiteVisitEngine {

    /// How far a member of the party covers in one action step at the site.
    /// A place is only a few of these across: this is a room, not a valley.
    public static let pace = 0.014
    /// Arm's length — close enough to open it, spring it, or be bitten by it.
    public static let reach = 0.011
    /// How wide a site is, in local-map units either side of the place itself.
    public static let siteReach = 0.055
    /// The share of a guardian one pair of hands puts down per step of contact.
    static let biteFactor = 0.10
    /// …and how hard a guardian answers, per point of what is left of it.
    static let guardianDamage = 0.10

    // MARK: - Laying the place out

    /// Builds the site a party has just walked up to. Deterministic from the
    /// seed it is given, so the same expedition meets the same place however
    /// many times it is replayed — and two parties sent to the same ruin in
    /// different years do not.
    public static func lay(out poi: LocalPOI, party: [UUID], seed: UInt64) -> SiteEncounter {
        var rng = SeededRNG(seed: seed)
        var things: [SiteEncounter.Thing] = []

        func place() -> LocalPoint {
            let angle = rng.nextUnit() * 2 * .pi
            let radius = siteReach * (0.35 + rng.nextUnit() * 0.65)
            return LocalPoint(x: poi.position.x + cos(angle) * radius,
                              y: poi.position.y + sin(angle) * radius)
        }
        func add(_ kind: SiteEncounter.Thing.Kind, _ strength: Double,
                 _ label: LocalizedText, itemID: String? = nil) {
            things.append(SiteEncounter.Thing(
                id: things.count, kind: kind, at: place(), strength: strength,
                itemID: itemID, label: label))
        }

        // What is worth carrying home. Always at least one, or there was no
        // reason to come.
        for _ in 0..<(1 + Int(rng.nextUnit() * Double(poi.kind.cacheCount))) {
            add(.cache, 1, poi.kind.cacheLabel, itemID: poi.kind.cacheItemID)
        }
        // What the place does to you all by itself.
        if poi.kind.hazardDamage > 0 {
            for _ in 0..<(1 + Int(rng.nextUnit() * 2)) {
                add(.trap, poi.kind.hazardDamage, poi.kind.trapLabel)
            }
        }
        // And what is living in it: a place nobody has walked into for four
        // hundred years is not empty.
        for _ in 0..<poi.kind.guardianCount where rng.nextUnit() < 0.8 {
            add(.guardian, poi.kind.guardianStrength * (0.7 + rng.nextUnit() * 0.6),
                poi.kind.guardianLabel)
        }

        // The party comes up to the edge of the place and walks in.
        var places: [UUID: LocalPoint] = [:]
        for (index, id) in party.enumerated() {
            let angle = Double(index) / Double(max(1, party.count)) * 2 * .pi
            places[id] = LocalPoint(x: poi.position.x + cos(angle) * siteReach * 1.6,
                                    y: poi.position.y + sin(angle) * siteReach * 1.6)
        }
        var site = SiteEncounter(things: things, places: places, seed: rng.next())
        site.beats.append(SiteEncounter.Beat(id: 0, kind: .arrived,
                                             amount: Double(things.count)))
        return site
    }

    // MARK: - Working it

    /// One action step at the place: everybody walks toward whatever they have
    /// picked out, and deals with it once they have reached it.
    public static func advanceStep(
        _ settlement: Settlement, expeditionIndex index: Int, step: Int,
        registry: GameDataRegistry
    ) -> Settlement {
        var s = settlement
        guard let site = s.expeditions[index].site else { return s }
        let worked = work(s, site: site, party: s.expeditions[index].memberIDs,
                          step: step, registry: registry)
        s = worked.settlement
        s.expeditions[index].site = worked.site
        return s
    }

    /// One step at a place, given the site and who is standing in it.
    ///
    /// Split out of `advanceStep` so the *world* map's ruins can be worked by
    /// the same code as the valley's: a `RegionExpedition` is the same journey
    /// one scale up, and a room with a chest and something living in it does
    /// not care which map it is on.
    public static func work(
        _ settlement: Settlement, site: SiteEncounter, party members: [UUID],
        step: Int, registry: GameDataRegistry
    ) -> (settlement: Settlement, site: SiteEncounter) {
        var s = settlement
        var site = site
        guard !site.isCleared else { return (s, site) }
        var rng = SeededRNG(seed: site.seed
                            &+ UInt64(bitPattern: Int64(step)) &* 0x9E37_79B9_7F4A_7C15)

        let party = members.filter { id in
            s.pawns.first { $0.id == id }.map { $0.health > 0 && !$0.isBroken } ?? false
        }
        guard !party.isEmpty else { return (s, sealed(site, .driven)) }

        aim(&site, party: party)
        walk(&site, party: party)
        s = act(s, site: &site, party: party, registry: registry, rng: &rng)
        if site.isCleared { site = sealed(site, .cleared) }
        return (s, site)
    }

    /// Everybody picks the nearest thing still to be dealt with — anything
    /// alive first, because you cannot rob a room with something in it.
    private static func aim(_ site: inout SiteEncounter, party: [UUID]) {
        let open = site.things.filter { !$0.done }
        guard !open.isEmpty else { site.marks = [:]; return }
        let alive = open.filter { $0.kind == .guardian }
        let field = alive.isEmpty ? open : alive
        for id in party {
            guard let me = site.places[id] else { continue }
            site.marks[id] = field.min {
                let a = distance(me, $0.at), b = distance(me, $1.at)
                return a == b ? $0.id < $1.id : a < b
            }?.id
        }
    }

    private static func walk(_ site: inout SiteEncounter, party: [UUID]) {
        for id in party {
            guard let me = site.places[id], let markID = site.marks[id],
                  let mark = site.things.first(where: { $0.id == markID }) else { continue }
            site.places[id] = stride(from: me, toward: mark.at, pace: pace)
        }
    }

    /// Whoever has arrived at something deals with it.
    private static func act(
        _ settlement: Settlement, site: inout SiteEncounter, party: [UUID],
        registry: GameDataRegistry, rng: inout SeededRNG
    ) -> Settlement {
        var s = settlement
        for id in party {
            guard let me = site.places[id], let markID = site.marks[id],
                  let slot = site.things.firstIndex(where: { $0.id == markID }),
                  !site.things[slot].done,
                  distance(me, site.things[slot].at) <= reach,
                  let pawn = s.pawns.first(where: { $0.id == id }) else { continue }
            let label = site.things[slot].label

            switch site.things[slot].kind {
            case .cache:
                site.things[slot].done = true
                if let item = site.things[slot].itemID { site.loot[item, default: 0] += 1 }
                beat(&site, .opened, pawn, label)

            case .trap:
                site.things[slot].done = true
                // A careful hand spots it first. Scouting is the trade that
                // keeps people out of holes, so the skill has somewhere to
                // bite that is not a number on a panel.
                let wary = min(0.7, Double(pawn.skill(.scouting)) * 0.06)
                guard rng.nextUnit() >= wary else {
                    beat(&site, .sprung, pawn, label)
                    continue
                }
                s = hurt(s, id: id, amount: site.things[slot].strength, rng: &rng)
                beat(&site, .sprung, pawn, label, amount: site.things[slot].strength)

            case .guardian:
                let power = CombatEngine.militia([pawn], registry: registry).total
                let dealt = power * biteFactor * (0.8 + rng.nextUnit() * 0.4)
                let answer = site.things[slot].strength * guardianDamage
                site.things[slot].strength = max(0, site.things[slot].strength - dealt)
                if site.things[slot].strength <= 0 {
                    site.things[slot].done = true
                    beat(&site, .killed, pawn, label)
                } else {
                    s = hurt(s, id: id, amount: answer, rng: &rng)
                    beat(&site, .fought, pawn, label, amount: answer)
                }
            }
        }
        return s
    }

    private static func hurt(
        _ settlement: Settlement, id: UUID, amount: Double, rng: inout SeededRNG
    ) -> Settlement {
        var s = settlement
        guard amount > 0, let slot = s.pawns.firstIndex(where: { $0.id == id }) else { return s }
        let landed = amount * CombatEngine.woundMultiplier(s.pawns[slot])
        s.pawns[slot] = MedicineEngine.wound(s.pawns[slot], amount: landed, tick: 0, rng: &rng)
        return s
    }

    private static func beat(
        _ site: inout SiteEncounter, _ kind: SiteEncounter.Beat.Kind,
        _ pawn: Pawn, _ label: LocalizedText, amount: Double = 0
    ) {
        // A record that grows without bound is a save file that grows without
        // bound; a place is a handful of things and this is a handful of lines.
        guard site.beats.count < 60 else { return }
        site.beats.append(SiteEncounter.Beat(
            id: site.beats.count, kind: kind, pawnID: pawn.id, pawnName: pawn.name,
            thingLabel: label, amount: amount))
    }

    /// Seals the record: cleared out, driven off, or simply out of time.
    public static func sealed(
        _ site: SiteEncounter, _ why: SiteEncounter.Beat.Kind
    ) -> SiteEncounter {
        var out = site
        let ended: Set<SiteEncounter.Beat.Kind> = [.cleared, .left, .driven]
        guard !out.beats.contains(where: { ended.contains($0.kind) }) else { return out }
        out.beats.append(SiteEncounter.Beat(id: out.beats.count, kind: why,
                                            amount: Double(out.unopenedCaches)))
        return out
    }

    // MARK: - Maths

    static func distance(_ a: LocalPoint, _ b: LocalPoint) -> Double {
        let dx = a.x - b.x, dy = a.y - b.y
        return (dx * dx + dy * dy).squareRoot()
    }

    static func stride(from a: LocalPoint, toward b: LocalPoint, pace: Double) -> LocalPoint {
        let dx = b.x - a.x, dy = b.y - a.y
        let d = (dx * dx + dy * dy).squareRoot()
        guard d > pace, d > 0 else { return b }
        return LocalPoint(x: a.x + dx / d * pace, y: a.y + dy / d * pace)
    }
}
