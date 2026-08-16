import Foundation

/// Fights a raid **while the player is watching**, one action step at a time.
///
/// The whole of the difference from `BattleResolver`: that one takes a
/// settlement and hands back a finished outcome, and this one takes a
/// settlement mid-fight and hands back a settlement one step further into it.
/// Between two calls the player can change the colony's posture or pull a
/// bleeding colonist out of the line, and the next step reads what they did.
///
/// Three properties this has to keep, all of them load-bearing:
///
/// 1. **Determinism.** Each step's rolls come from `(siege.seed, step)`, so a
///    step is a pure function of where it sits in the fight — never of when it
///    was asked for. Orders live in `Siege`, which is saved, so the same world
///    plus the same orders replays to the same dead. This is why posture is a
///    field and not a callback.
/// 2. **Leaving is allowed.** A step is fought once, by whoever reaches it
///    first. The app drives the siege ahead of the world clock at a pace a
///    person can act at; if the app is not there, `ActionLoop` walks the world
///    clock over the top and the rest is fought exactly as it would have been.
///    Backgrounding an app mid-raid must never be a tactic, and must never be a
///    punishment.
/// 3. **The Core owes the canvas a record.** Moments accumulate as they happen,
///    so the fight can be drawn while it is still going on rather than replayed
///    once it is finished.
public enum SiegeEngine {

    // MARK: - Real time, on the ground

    /// How far a fighter covers in one action step, in local-map units.
    ///
    /// The warband forms up at `SiegeField.originReach` and the watch turns out
    /// from among the houses, so there is real ground between them and it takes
    /// real steps to cross. That gap is the thing that was missing: the enemy
    /// appears at the edge of the map and *walks in*, and the player has time
    /// to decide what to do about it before anybody is within reach of anybody.
    ///
    /// Deliberately slower than `WalkPace.perStep` — a line closing on an enemy
    /// advances warily, and the approach is the part of a raid the player reads
    /// and answers. Deliberately *on the same clock*, which is the thing that
    /// stopped being true everywhere else: this was the only movement in the
    /// game measured per action step, and it was the only movement that looked
    /// alive. `WalkPaceTests` pins the two together.
    public static let pace = 0.030
    /// Arm's length. Inside this, two people are fighting each other — which is
    /// what "the ranks are in contact" means now that there is a ground to be
    /// standing on. No step index decides it.
    public static let reach = 0.022
    /// How far an arrow carries. A bow is worth something before contact and
    /// awkward after it, which is what `CombatEngine.rangedBasePenalty` has
    /// always said and nothing could previously act on.
    public static let bowRange = 0.16

    /// How many steps the two ranks take to cross the ground between them when
    /// the colony holds its line. Nothing branches on this — the approach is
    /// emergent — but `meleePerStep` needs a divisor and this is where it
    /// honestly comes from.
    static var typicalApproachSteps: Int {
        max(1, Int(((SiegeField.originReach - SiegeField.musterReach) / pace).rounded(.up)))
    }
    /// The share of their weight a fighter lands in one step of contact.
    ///
    /// Derived from the steps they actually fight for, not written down: across
    /// a whole fight at `hold` the line delivers its full weight exactly once,
    /// which is what the one-tick resolver credited it with. A hand-picked
    /// number here is how an *undefended* colony quietly started turning back
    /// warbands that used to walk straight through it.
    static var meleePerStep: Double {
        1 / Double(max(1, Siege.stepsTotal - typicalApproachSteps))
    }
    /// …and the share an archer looses per step, while they still have the
    /// range to. There are only a few such steps, which is the point: closing
    /// fast costs you the volleys.
    static var rangedPerStep: Double { 1 / 10.0 }
    /// How hard the attackers answer, per point of strength, per step.
    ///
    /// Raised from 0.14 when blows stopped all landing on one man. The old
    /// resolver put the whole warband's answer onto the single weakest colonist
    /// every step — brutal arithmetic that still produced *no deaths in two
    /// hundred years*, because the wall soaked most of it and the one target
    /// healed between raids. Spread across a line it went slacker still. This
    /// is the number that makes a raid cost something, and it is tuned so a
    /// modest warband against a walled colony wounds and a big one kills.
    static let attackerDamagePerStrength = 0.24
    /// How much harm has to pile onto one colonist before the record marks it.
    ///
    /// Blows are spread across everybody in contact now rather than all landing
    /// on the weakest, so a raw moment per blow would be three hundred beats of
    /// nothing much. A wound is marked when it becomes something you would see.
    static let woundBeat = 10.0
    /// The fortification at which a wall turns aside half of what is thrown at
    /// it. Used as a *share*, never as a subtraction — see `wallShare`.
    static let fortificationHalfPoint = 24.0
    /// …and the most a wall can ever turn aside, however high it is built.
    static let fortificationCeiling = 0.85
    /// What a wall contributes to *breaking* an assault, beyond soaking.
    static let fortificationBite = 0.05
    /// The most of a shot that the ground can ever take, however good the cover.
    ///
    /// A share, never a subtraction — the same discipline as
    /// `fortificationCeiling`, and for the same reason: total cover that stops
    /// a shot *entirely* is a mechanic with a dead end in it, because an archer
    /// facing a wall would simply never shoot and the fight would stall. Even
    /// behind a building people lean out, and a volley into a wood still finds
    /// somebody. Cover is a heavy tax on shooting, not a veto (§11.27).
    static let coverBite = 0.8
    /// Condition a building loses per unit of shot it stopped.
    ///
    /// Sized against a raid rather than against a shot: a palisade that spends
    /// a whole raid being shot at comes out of it about a tenth worse, which is
    /// a mason's afternoon — enough that a wall is a thing you keep up, far too
    /// little to knock one down with arrows.
    static let chipPerShotStopped = 0.002
    /// …and per unit of blow the wall turned aside. Hacking at a palisade with
    /// a sword is harder on it than shooting at it, but there are fewer blows
    /// than there are arrows.
    static let chipPerBlowTurned = 0.0003
    /// How far a defender will step aside to put something between themselves
    /// and the people coming at them.
    ///
    /// Deliberately small: a colonist who is holding the line looks for the
    /// parapet **at their post**, not for the best cover in the valley. A
    /// bigger radius is a line that dissolves into everybody standing behind
    /// the nearest boulder, which is a rout with good arithmetic.
    ///
    /// Floored at slightly over one cell of the cover grid, because a stride
    /// shorter than the ground is measured in cannot reach different ground:
    /// the cells are 40 × 25, so a step of one rank-space moves nobody out of
    /// the row they are already in and cover to the north would be unreachable
    /// however close it stood.
    static var coverSearch: Double {
        max(SiegeField.rankSpacing * 1.6, 1.1 / Double(LocalMap.gridRows))
    }
    /// Food carried off per step by raiders who are **standing in the stores**,
    /// as a share of what is there. Giving ground is cheap in blood and dear in
    /// grain — that is the entire trade, and it has to actually bite.
    ///
    /// Gated on where they are, not on which order the player gave. Holding the
    /// line keeps them out at the muster post and they take nothing; falling
    /// back lets them walk in and they help themselves. The posture no longer
    /// *says* the grain goes; it goes because nobody is standing in the way.
    static let plunderPerStep = 0.030

    // MARK: - Opening

    /// Starts a raid the player can fight, in place of resolving one.
    ///
    /// Takes the same inputs `BattleResolver.resolve` does, so the two are
    /// interchangeable at the call site: a raid becomes a siege where somebody
    /// might be watching, and stays a resolved battle where nobody can be.
    public static func begin(
        _ settlement: Settlement,
        attackerStrength: Double,
        attackerName: String,
        attackerLabel: LocalizedText? = nil,
        attackerTribeID: UUID? = nil,
        fortification: Double,
        tick: Int,
        registry: GameDataRegistry,
        seed: UInt64,
        carriesOff: Double = 1
    ) -> Settlement {
        var rng = SeededRNG(seed: seed)
        var s = settlement
        let line = BattleResolver.defenders(s.pawns, registry: registry)
            .prefix(12).map(\.id)
        let id = rng.nextUUID()
        let approach = rng.nextUnit() * 2 * .pi
        // A wall is only a wall on the side it stands. What the colony has
        // built still decides how much of the attack it turns aside, but
        // **where** it built it now decides how much of that counts (§11.27).
        let facing = fortification * facingShare(
            s, registry: registry, approach: approach)
        var siege = Siege(
            id: id, startTick: tick,
            openedAt: WorldClock(tick: tick, step: 0).absoluteStep,
            attackerName: attackerName, attackerLabel: attackerLabel,
            attackerTribeID: attackerTribeID, approach: approach,
            attackers: BattleResolver.drawnStrength(attackerStrength),
            openingStrength: attackerStrength, fortification: facing,
            seed: rng.next(), line: Array(line), carriesOff: carriesOff)
        stageIfNeeded(&siege, in: s, registry: registry)
        s.siege = siege
        return s
    }

    /// Puts everybody on the ground: the watch among the houses, the warband at
    /// the edge of the map, abreast and facing each other down the line of the
    /// attack.
    ///
    /// Idempotent, and called from the fighting path as well as from `begin`,
    /// so a raid saved before combatants had positions is staged the first time
    /// anybody carries it forward instead of fighting an empty field.
    static func stageIfNeeded(
        _ siege: inout Siege, in settlement: Settlement, registry: GameDataRegistry
    ) {
        guard siege.fighters.isEmpty else { return }
        let field = SiegeField(approach: siege.approach)
        var out: [Siege.Combatant] = []
        for (index, id) in siege.line.enumerated() {
            out.append(Siege.Combatant(
                id: id, side: .colony,
                at: field.musterPost(index: index, of: siege.line.count),
                strength: 0))
        }
        // …and the towers, which stand where they were built and shoot from
        // there. They take no post and they do not march: that is the whole
        // point of one.
        out.append(contentsOf: emplacements(of: settlement, registry: registry))
        let count = max(1, siege.attackers)
        // Their share of the warband. The sum of these is `siege.strength`, and
        // the two are kept equal every step — the aggregate is what decides
        // whether the raid broke, and the figures are what it is made of.
        let share = max(0, siege.strength) / Double(count)
        for index in 0..<count {
            out.append(Siege.Combatant(
                id: raiderID(seed: siege.seed, index: index), side: .raider,
                at: field.attackerPost(index: index, of: count), strength: share))
        }
        siege.fighters = out
    }

    /// A stable id for one raider. Derived from the siege's own seed, so two
    /// runs of the same world put the same people on the same ground — an
    /// unseeded `UUID()` here would be CLAUDE.md rule 3 broken in a place no
    /// test would ever look.
    static func raiderID(seed: UInt64, index: Int) -> UUID {
        var rng = SeededRNG(seed: seed
                            &+ UInt64(bitPattern: Int64(index)) &* 0xD1B5_4A32_D192_ED03 &+ 1)
        return rng.nextUUID()
    }

    // MARK: - Fighting it

    /// Carries the settlement's siege forward to a given absolute action step.
    ///
    /// Idempotent by construction: a step already fought is never fought again,
    /// so the app running ahead of the world clock and the world clock catching
    /// up later add up to exactly one fight.
    public static func advance(
        _ settlement: Settlement, to absoluteStep: Int, registry: GameDataRegistry
    ) -> Settlement {
        fight(settlement, to: absoluteStep, registry: registry).settlement
    }

    /// The same, but also handing back the siege **as it finished**.
    ///
    /// The world needs the final numbers — what is left of the warband, what
    /// they carried off — and `conclude` clears the siege off the settlement,
    /// so a caller that only watched `settlement.siege` go from set to nil is
    /// left holding the state from *before* the last step. That is how the
    /// tribes came to be charged for a fight they had not finished yet.
    public static func fight(
        _ settlement: Settlement, to absoluteStep: Int, registry: GameDataRegistry,
        language: GameLanguage = .cs
    ) -> (settlement: Settlement, concluded: Siege?) {
        guard var siege = settlement.siege else { return (settlement, nil) }
        guard absoluteStep > siege.advancedTo else { return (settlement, nil) }
        var s = settlement

        // What stands on the ground this fight is happening on, stamped once
        // for the whole call rather than per step (§11.23's discipline, and
        // §11.27's mechanic). A raid does not fell trees while it is going on,
        // so one field answers every step of it.
        let cover = s.localMap.map {
            CoverField($0, colony: s.colony, registry: registry)
        } ?? CoverField()

        var reached = siege.advancedTo
        while reached < absoluteStep, !siege.isFinished {
            reached += 1
            siege.advancedTo = reached
            s = fightOneStep(s, siege: &siege, registry: registry, cover: cover)
        }
        siege.advancedTo = max(siege.advancedTo, min(absoluteStep, reached))
        s.siege = siege

        guard siege.isFinished else { return (s, nil) }
        return (conclude(s, registry: registry, language: language), siege)
    }

    /// One step of the fight: people move, and whoever is within reach of
    /// somebody trades blows with them.
    ///
    /// Read top to bottom, this is the whole shape of a raid — the fallen leave
    /// the field, everybody picks who they are going for, everybody takes one
    /// stride toward them, arrows go out at whatever is in range and not yet in
    /// reach, the ranks that have met exchange, and anybody who got past the
    /// line helps themselves to the stores.
    ///
    /// **No phase is written down.** "Coming over the ground" is nobody being
    /// within reach yet; "the ranks are in contact" is somebody being within
    /// reach. That is the difference between a fight with rounds and a fight
    /// with a ground to stand on.
    private static func fightOneStep(
        _ settlement: Settlement, siege: inout Siege, registry: GameDataRegistry,
        cover: CoverField = CoverField()
    ) -> Settlement {
        var s = settlement
        let step = siege.step
        // A step's rolls depend on where it sits in the fight and nothing else.
        var rng = SeededRNG(seed: siege.seed
                            &+ UInt64(bitPattern: Int64(step)) &* 0x9E37_79B9_7F4A_7C15)
        let field = SiegeField(approach: siege.approach)

        stageIfNeeded(&siege, in: s, registry: registry)
        // What the colony's towers are worth **right now** — read once and used
        // twice, by what is left standing and by what shoots.
        let towers = Dictionary(
            emplacements(of: s, registry: registry).map { ($0.id, $0.strength) },
            uniquingKeysWith: { first, _ in first })
        retire(&siege, pawns: s.pawns, towers: towers)
        aim(&siege, field: field)
        march(&siege, field: field, cover: cover)

        let met = engagements(siege, field: field)
        if !met.isEmpty, !siege.moments.contains(where: { $0.kind == .charge }) {
            siege.moments.append(moment(siege, .charge, amount: siege.strength))
        }

        // What the fight takes out of the town itself, gathered as it happens
        // and paid once at the end of the step. An arrow into a palisade and a
        // blow that the parapet turned aside are both wear on a real building,
        // and a wall that soaks a hundred raids untouched is the same dead
        // mechanic as a sword that never dulls (§11.26).
        var chips: [UUID: Double] = [:]
        var power = weights(of: s.pawns, siege: siege, registry: registry)
        for (id, standing) in towers { power[id] = (melee: 0, ranged: standing * towerShotShare) }
        loose(&siege, power: power, cover: cover, chips: &chips, rng: &rng)
        strike(&siege, power: power, met: met, rng: &rng)
        s = answer(s, siege: &siege, met: met, field: field, cover: cover,
                   chips: &chips, rng: &rng)
        // What the fighting did to what people were holding. A blade that has
        // been through four raids should be the cheaper blade it has become,
        // and a coat that stopped forty blows should be a coat somebody wants
        // replacing (§11.26 C).
        s = wearGear(s, met: met)
        // Ransacking is harm too, so it goes into the same tally and the town
        // is charged **once**, at the end of the step.
        s = ransack(s, siege: &siege, field: field, chips: &chips, registry: registry)
        return BuildingEngine.chip(s, by: chips)
    }

    // MARK: - The step, in pieces

    /// Takes the dead and the withdrawn off the field, and forgets an order to
    /// go for somebody who is no longer standing.
    private static func retire(
        _ siege: inout Siege, pawns: [Pawn], towers: [UUID: Double] = [:]
    ) {
        var health: [UUID: Double] = [:]
        for pawn in pawns { health[pawn.id] = pawn.health }
        for index in siege.fighters.indices {
            // A tower is not a person: what it is worth is what is left of the
            // building, and it stops shooting when it becomes a wreck rather
            // than when it dies.
            if siege.fighters[index].kind == .emplacement {
                let left = towers[siege.fighters[index].id] ?? 0
                siege.fighters[index].strength = left
                siege.fighters[index].down = left <= 0
                if siege.fighters[index].down { siege.fighters[index].target = nil }
                continue
            }
            switch siege.fighters[index].side {
            case .colony:
                let id = siege.fighters[index].id
                let alive = (health[id] ?? 0) > 0
                if !alive { siege.withdrawn.insert(id) }
                siege.fighters[index].down = !alive || siege.withdrawn.contains(id)
                // A colonist's weight on the field is what is left of them.
                // Kept here so the targeting can see it without carrying the
                // whole roster of pawns around.
                siege.fighters[index].strength = health[id] ?? 0
            case .raider:
                siege.fighters[index].down = siege.fighters[index].strength <= 0
            }
        }
        let standing = Set(siege.fighters.filter { !$0.down }.map(\.id))
        siege.orders = siege.orders.filter { _, order in
            guard case .engage(let mark) = order else { return true }
            return standing.contains(mark)
        }
    }

    /// Everybody picks who they are going for. Ties break on id, so a fight
    /// never depends on array order.
    ///
    /// The colony takes the nearest. The raiders take the nearest *weighted by
    /// how hurt they are* — a warband works on the man who is already bleeding,
    /// and that is the mechanism by which a raid produces a casualty instead of
    /// twelve people evenly and harmlessly bruised. It is deliberately mild:
    /// somebody at a fifth of their health is worth walking about a third
    /// further for, and no further.
    private static func aim(_ siege: inout Siege, field: SiegeField) {
        let colony = engageableColony(siege, field: field)
        let raiders = siege.fighters.filter { $0.side == .raider && !$0.down }
        for index in siege.fighters.indices {
            guard !siege.fighters[index].down else {
                siege.fighters[index].target = nil
                continue
            }
            let me = siege.fighters[index]
            siege.fighters[index].target = me.side == .colony
                ? nearest(to: me.at, among: raiders)?.id
                : nearest(to: me.at, among: colony, preferringWeak: true)?.id
        }
    }

    /// The point a fighter is trying to reach in order to be within reach of
    /// somebody — held inside the **band** this posture is willing to fight on.
    ///
    /// Without any limit at all, holding the line would mean nothing: the watch
    /// would follow a raider out into the fields and the wall would be behind
    /// nobody. With a *ring* — which is what this was — the whole line stood at
    /// exactly `posture.reach` the moment anybody had a target, and a battle
    /// that formed up three ranks deep flattened into two facing arcs. That is
    /// the complaint this is here to answer: *"bitva nevypadá jako bitva ale
    /// jako dvě řady lidí co mávají mečem."*
    ///
    /// A band of `SiegeField.scrumDepth` is the fix. Inside it a defender simply
    /// stands at arm's length from whoever they closed on, so the line takes the
    /// shape of the warband pressing into it; past it, they are still holding
    /// the line.
    private static func closingPoint(
        from me: LocalPoint, to enemy: LocalPoint, limit: Double, field: SiegeField
    ) -> LocalPoint {
        let gap = SiegeField.distance(me, enemy)
        let arm = reach * 0.8
        let want = gap <= arm ? me : SiegeField.stride(from: me, toward: enemy, pace: gap - arm)
        let out = field.reachFromHeart(want)
        let ceiling = limit + SiegeField.scrumDepth
        guard out > ceiling, out > 0 else { return want }
        let scale = ceiling / out
        return LocalPoint(x: field.heart.x + (want.x - field.heart.x) * scale,
                          y: field.heart.y + (want.y - field.heart.y) * scale)
    }

    /// Everybody takes one stride toward wherever they are trying to be, and
    /// then nobody is standing inside anybody.
    private static func march(_ siege: inout Siege, field: SiegeField, cover: CoverField) {
        let places = Dictionary(siege.fighters.map { ($0.id, $0.at) },
                                uniquingKeysWith: { first, _ in first })
        let posts = defenderPosts(siege, field: field, cover: cover)
        for index in siege.fighters.indices {
            let me = siege.fighters[index]
            guard let goal = destination(me, siege: siege, field: field,
                                         places: places, posts: posts) else { continue }
            siege.fighters[index].at = SiegeField.stride(from: me.at, toward: goal, pace: pace)
        }
        shoulder(&siege)
    }

    /// Bodies take up room: one relaxation pass that parts anybody standing
    /// inside anybody else.
    ///
    /// **This is where a battle stops being two rows.** Every fighter walks at
    /// the enemy they closed on, and the nearest enemy is whoever is at the
    /// front, so without this every last one of them converges on the same
    /// contact surface and the fight is an arc facing an arc. With it, the
    /// people who got there first are *in the way*: the rest bank up behind
    /// them, spill around the ends and press in where there is room, which is
    /// what a melee looks like from above.
    ///
    /// It is a crowd, deliberately, and not a formation. A rank rule was tried
    /// first (`SiegeField.postReach`) and it fought the targeting: a defender
    /// held to their own ring could not reach anybody and six of eight came out
    /// of a raid unmarked. Crowding never forbids anybody anything — it only
    /// makes them go round — so everybody still finds their way into the fight.
    ///
    /// Deterministic: the pushes are summed off a snapshot taken before anybody
    /// moves, so the result does not depend on who is updated first, and two
    /// bodies on exactly the same spot part by their place in the array rather
    /// than by anything that could differ between runs.
    private static func shoulder(_ siege: inout Siege) {
        for _ in 0..<shoulderPasses { shoulderOnce(&siege) }
    }

    /// How many times the press settles per step. One pass leaves a knot of a
    /// dozen people still half inside each other, because every one of them
    /// walked at the same spot before it ran; three is enough to part them
    /// without the crowd behaving like it is made of springs.
    static let shoulderPasses = 3

    private static func shoulderOnce(_ siege: inout Siege) {
        // Towers do not shove and are not shoved: a building is not in the
        // crowd, it is a thing the crowd is standing around.
        let standing = siege.fighters.enumerated()
            .filter { !$0.element.down && $0.element.kind != .emplacement }
            .map { (index: $0.offset, at: $0.element.at) }
        guard standing.count > 1 else { return }
        let space = SiegeField.bodySpace

        for me in standing {
            var pushX = 0.0, pushY = 0.0
            for them in standing where them.index != me.index {
                let dx = me.at.x - them.at.x, dy = me.at.y - them.at.y
                let apart = (dx * dx + dy * dy).squareRoot()
                guard apart < space else { continue }
                let overlap = (space - apart) / 2
                guard apart > 0 else {
                    pushX += me.index < them.index ? -overlap : overlap
                    continue
                }
                pushX += dx / apart * overlap
                pushY += dy / apart * overlap
            }
            // Nobody is shoved further than they could walk. In a deep press a
            // body has a dozen neighbours and the sum of their elbows would
            // otherwise throw it out of the fight altogether.
            let shove = (pushX * pushX + pushY * pushY).squareRoot()
            guard shove > 0 else { continue }
            let scale = shove > pace ? pace / shove : 1
            siege.fighters[me.index].at = LocalPoint(
                x: me.at.x + pushX * scale, y: me.at.y + pushY * scale)
        }
    }

    /// Where one fighter is trying to get to, in order of what overrules what:
    /// the player's own order, then the posture, then the post they were given.
    private static func destination(
        _ me: Siege.Combatant, siege: Siege, field: SiegeField,
        places: [UUID: LocalPoint], posts: [UUID: LocalPoint]
    ) -> LocalPoint? {
        switch me.side {
        case .raider:
            guard !me.down else { return nil }
            // Whoever they closed on — or the stores, if nobody is in the way.
            return me.target.flatMap { places[$0] } ?? field.heart
        case .colony:
            // A tower stands where it was built. That is the whole of what a
            // tower is, and it is why one is worth attacking.
            guard me.kind != .emplacement else { return nil }
            // Somebody pulled out of the line walks off it. Somebody who fell
            // stays where they fell: a body is a thing the canvas has to draw
            // in the place it happened.
            guard !me.down else {
                return siege.withdrawn.contains(me.id) ? field.heart : nil
            }
            if let order = siege.orders[me.id] {
                switch order {
                case .moveTo(let point): return point
                case .engage(let mark): return places[mark] ?? posts[me.id]
                }
            }
            guard siege.posture != .giveGround else { return field.heart }
            let post = posts[me.id] ?? field.muster
            guard let enemy = me.target.flatMap({ places[$0] }) else { return post }
            // Close on them — but no further out than this posture will go, so
            // holding the line still means holding it. They come to you, and
            // you keep the wall at your back.
            return closingPoint(from: me.at, to: enemy,
                                limit: siege.posture.reach, field: field)
        }
    }

    /// Who has actually met whom. A raider fights the colonist they closed on;
    /// a colonist fights whichever raider is nearest and within reach, which is
    /// not always the one fighting them.
    struct Melee {
        var raiders: [(raider: UUID, on: UUID)] = []
        var colony: [(colonist: UUID, on: UUID)] = []
        var isEmpty: Bool { raiders.isEmpty && colony.isEmpty }
    }

    private static func engagements(_ siege: Siege, field: SiegeField) -> Melee {
        var met = Melee()
        let colony = engageableColony(siege, field: field)
        let raiders = siege.fighters.filter { $0.side == .raider && !$0.down }
        for raider in raiders {
            guard let markID = raider.target,
                  let mark = colony.first(where: { $0.id == markID }),
                  SiegeField.distance(raider.at, mark.at) <= reach else { continue }
            met.raiders.append((raider.id, mark.id))
        }
        for one in colony {
            guard let near = nearest(to: one.at, among: raiders),
                  SiegeField.distance(one.at, near.at) <= reach else { continue }
            met.colony.append((one.id, near.id))
        }
        return met
    }

    /// Arrows, at whatever is in range and not yet in reach. The whole of what
    /// a bow is for: closing fast is what costs you the volleys.
    private static func loose(
        _ siege: inout Siege, power: [UUID: (melee: Double, ranged: Double)],
        cover: CoverField, chips: inout [UUID: Double], rng: inout SeededRNG
    ) {
        let raiders = siege.fighters.filter { $0.side == .raider && !$0.down }
        guard !raiders.isEmpty else { return }
        let archers = siege.fighters.filter {
            $0.side == .colony && !$0.down && (power[$0.id]?.ranged ?? 0) > 0
        }
        var total = 0.0
        for archer in archers {
            guard let mark = nearest(to: archer.at, among: raiders) else { continue }
            let gap = SiegeField.distance(archer.at, mark.at)
            // A tower shoots further than a bow in a hand, and it keeps
            // shooting at what is at its foot — there is nobody up there to be
            // pushed into a scuffle.
            let range = archer.kind == .emplacement ? towerRange : bowRange
            guard gap <= range, archer.kind == .emplacement || gap > reach else { continue }
            // What the world has to say about the line between them (§11.27).
            // A raider coming on through a wood or behind the old walls is a
            // harder shot than one crossing open ground, and *where the fight
            // happens* is now a thing the player can read off the map before it
            // starts. Derived from height and substance, never declared — see
            // `Cover`.
            let stopped = cover.struck(archer.at, mark.at)
            let sheltered = 1 - stopped.fraction * coverBite
            let loosed = (power[archer.id]?.ranged ?? 0) * siege.posture.bite
                * (0.8 + rng.nextUnit() * 0.4) * rangedPerStep
            let shot = loosed * sheltered
            // Whatever did not reach the raider went into whatever was in the
            // way — and if that was something the colony built, it is worse for
            // it afterwards.
            if let struck = stopped.building, loosed > shot {
                chips[struck, default: 0] += (loosed - shot) * chipPerShotStopped
            }
            guard shot > 0 else { continue }
            total += wound(raider: mark.id, by: shot, siege: &siege)
        }
        guard total > 0 else { return }
        siege.moments.append(moment(siege, .volley, amount: total))
    }

    /// The line, where it is in contact.
    private static func strike(
        _ siege: inout Siege, power: [UUID: (melee: Double, ranged: Double)],
        met: Melee, rng: inout SeededRNG
    ) {
        var total = 0.0
        for pair in met.colony {
            let swing = (power[pair.colonist]?.melee ?? 0) * siege.posture.bite
                * (0.85 + rng.nextUnit() * 0.3) * meleePerStep
            total += wound(raider: pair.on, by: swing, siege: &siege)
        }
        // The wall itself, while somebody is holding it: stakes, a ditch, and
        // stones off the parapet — worth something beyond soaking blows.
        if let first = met.colony.first {
            total += wound(raider: first.on,
                           by: siege.fortification * fortificationBite * meleePerStep,
                           siege: &siege)
        }
        guard total > 0 else { return }
        siege.moments.append(moment(siege, .clash, amount: total))
    }

    /// And they answer — every raider in contact, on the person in front of
    /// them.
    ///
    /// The old resolver put the whole warband's answer onto the single weakest
    /// colonist in the line, every step, which is how a raid produced one
    /// corpse and eleven people without a scratch. A blow lands on whoever is
    /// standing in front of the man swinging it, so a fight leaves a *line*
    /// hurt — which is the cost the colony then has to carry.
    private static func answer(
        _ settlement: Settlement, siege: inout Siege, met: Melee,
        field: SiegeField, cover: CoverField, chips: inout [UUID: Double],
        rng: inout SeededRNG
    ) -> Settlement {
        var s = settlement
        for pair in met.raiders {
            guard let attacker = siege.fighters.first(where: { $0.id == pair.raider }),
                  attacker.strength > 0,
                  let mark = siege.fighters.first(where: { $0.id == pair.on }) else { continue }
            // Somebody hacking at a tower is hacking at a *building*, and it
            // comes down in the end. A warband spending its raid on the
            // stonework is a warband that is not in the stores, which is the
            // trade a turret exists to offer.
            if mark.kind == .emplacement {
                chips[mark.id, default: 0] +=
                    attacker.strength * towerDamagePerStrength * siege.posture.exposure
                continue
            }
            guard let index = s.pawns.firstIndex(where: { $0.id == pair.on }),
                  s.pawns[index].health > 0 else { continue }
            let incoming = attacker.strength * attackerDamagePerStrength * siege.posture.exposure
            // **The wall is where it stands**, not a radius around the middle
            // of town. `SiegeField.cover(at:)` answered this off the distance
            // from the heart, so a colonist was sheltered by geometry whether
            // or not there was anything next to them and wherever the colony
            // had actually put its palisade. What shelters somebody at arm's
            // length is the parapet at their shoulder, which the ground itself
            // can now be asked about (§11.27).
            let shelter = cover.shelter(at: mark.at, from: attacker.at)
            let turned = wallShare(fortification: siege.fortification,
                                   cover: shelter.fraction)
            let past = incoming * (1 - turned)
            // …and what turned it is worse for having done so.
            if let struck = shelter.building, turned > 0 {
                chips[struck, default: 0] += incoming * turned * chipPerBlowTurned
            }
            guard past > 0 else { continue }

            let hit = past * CombatEngine.woundMultiplier(s.pawns[index])
            let name = s.pawns[index].name
            let before = siege.damage[pair.on, default: 0]
            // Between the two of them, which is where a blow actually lands and
            // where the blood goes. Half an arm's length from the man taking it.
            let impact = LocalPoint(x: (attacker.at.x + mark.at.x) / 2,
                                    y: (attacker.at.y + mark.at.y) / 2)
            // A blow lands *somewhere*: an arm, a leg — not a smaller number.
            // And it was made by *something*: a warband leaves cuts and stabs,
            // a wolf pack leaves bites, and `attackerTribeID` is the same
            // honest test of which it was that decides whether anybody can be
            // taken alive (`CaptiveEngine.take`).
            s.pawns[index] = MedicineEngine.wound(
                s.pawns[index], amount: hit, tick: siege.startTick, rng: &rng,
                from: siege.attackerTribeID == nil ? .bite : nil)
            siege.damage[pair.on] = before + hit

            if s.pawns[index].health <= 0 {
                siege.withdrawn.insert(pair.on)
                markDown(pair.on, in: &siege)
                siege.moments.append(moment(siege, .death, pawnID: pair.on,
                                            pawnName: name, amount: hit, spot: impact))
                continue
            }
            let beats = Int((before + hit) / woundBeat) - Int(before / woundBeat)
            guard beats > 0 else { continue }
            siege.moments.append(moment(siege, .wound, pawnID: pair.on, pawnName: name,
                                        amount: Double(beats) * woundBeat, spot: impact))
        }
        return s
    }

    /// Anybody who got in among the stores helps themselves.
    private static func ransack(
        _ settlement: Settlement, siege: inout Siege, field: SiegeField,
        chips: inout [UUID: Double], registry: GameDataRegistry
    ) -> Settlement {
        var s = settlement
        let breaking = siege.fighters.filter {
            $0.side == .raider && !$0.down && field.isInside($0.at)
        }
        guard !breaking.isEmpty else { return s }

        // **Taking things is not the only thing they do to the place.** A store
        // being emptied by people who did not build it comes out of it worse:
        // doors off, thatch pulled about, whatever would not go in a sack
        // broken on the way past. Charged to the building they are standing on,
        // so which building suffers is a fact about where they got in.
        if let colony = s.colony {
            for raider in breaking {
                guard let tile = SettlementGeometry.tile(at: raider.at, in: colony),
                      let placement = colony.placement(at: tile),
                      !placement.underConstruction else { continue }
                chips[placement.id, default: 0] += ransackDamagePerStep
            }
        }

        let taken = s.storage[.food] * plunderPerStep
        guard taken > 0 else { return s }
        s.storage[.food] -= taken
        siege.plundered += taken
        siege.moments.append(moment(siege, .plunder, amount: taken))
        return s
    }

    /// Condition a raider takes out of the building they are ransacking, per
    /// step. Small: a raid should leave a town needing work, not a ruin.
    static let ransackDamagePerStep = 0.006

    /// How much a swing takes out of the thing doing the swinging, and how much
    /// a blow takes out of what stopped it.
    ///
    /// Sized against a raid rather than a blow: somebody in contact for a whole
    /// fight comes out of it with a piece about a tenth more used up, so gear
    /// lasts roughly ten hard raids. Armour wears faster than weapons because
    /// armour is what the blows are landing on.
    static let weaponWearPerBlow = 0.004
    static let armourWearPerBlow = 0.006

    /// Wears what the people in contact were holding.
    ///
    /// Both ends of a blow: whoever swung wears their weapon, whoever was
    /// swung at wears their coat. A piece that has nothing left of it is
    /// scrapped rather than carried — `ItemEngine.scrapBroken`.
    static func wearGear(_ settlement: Settlement, met: Melee) -> Settlement {
        guard !met.isEmpty else { return settlement }
        var s = settlement
        // Sorted, so the same fight wears the same gear in the same order and
        // a replay comes out with the same kit (rule 2).
        for pair in met.colony.sorted(by: { $0.colonist.uuidString < $1.colonist.uuidString }) {
            guard let index = s.pawns.firstIndex(where: { $0.id == pair.colonist }),
                  let weapon = s.pawns[index].equipment[.weapon] else { continue }
            s.pawns[index].equipment[.weapon] = weapon.worn(by: weaponWearPerBlow)
        }
        for pair in met.raiders.sorted(by: { $0.on.uuidString < $1.on.uuidString }) {
            guard let index = s.pawns.firstIndex(where: { $0.id == pair.on }),
                  let coat = s.pawns[index].equipment[.armor] else { continue }
            s.pawns[index].equipment[.armor] = coat.worn(by: armourWearPerBlow)
        }
        return s
    }

    // MARK: - Reading the field

    /// The colonists a raider can actually get at. Somebody who has gone
    /// indoors while the colony gives ground is not one of them — that is what
    /// "nobody dies for grain" buys, and the grain is what it costs.
    private static func engageableColony(
        _ siege: Siege, field: SiegeField
    ) -> [Siege.Combatant] {
        siege.fighters.filter {
            $0.side == .colony && !$0.down
                && !(siege.posture == .giveGround && field.isInside($0.at))
        }
    }

    private static func nearest(
        to point: LocalPoint, among crowd: [Siege.Combatant], preferringWeak: Bool = false
    ) -> Siege.Combatant? {
        func score(_ who: Siege.Combatant) -> Double {
            let d = SiegeField.distance(point, who.at)
            guard preferringWeak else { return d }
            return d * (0.55 + 0.45 * min(1, max(0, who.strength / 100)))
        }
        return crowd.min {
            let a = score($0), b = score($1)
            return a == b ? $0.id.uuidString < $1.id.uuidString : a < b
        }
    }

    private static func defenderPosts(
        _ siege: Siege, field: SiegeField, cover: CoverField = CoverField()
    ) -> [UUID: LocalPoint] {
        var out: [UUID: LocalPoint] = [:]
        for (index, id) in siege.line.enumerated() {
            let post = field.defenderPost(index: index, of: siege.line.count)
            out[id] = sheltering(post, field: field, cover: cover)
        }
        return out
    }

    /// The best-covered spot within a step of a post, facing the way they are
    /// coming from.
    ///
    /// **This is what makes cover a place people go rather than a tax on a
    /// number.** A colonist who has a palisade, a boulder or the old walls
    /// within a stride of where they were told to stand puts it between
    /// themselves and the attack, and the canvas draws them there because the
    /// canvas draws whatever the Core says (rule 5). Somebody with nothing near
    /// them stands where they were sent, in the open, and takes what comes.
    ///
    /// Deterministic by construction: a fixed ring of candidates in a fixed
    /// order, and a strictly-better test, so the post itself wins every tie.
    static func sheltering(
        _ post: LocalPoint, field: SiegeField, cover: CoverField
    ) -> LocalPoint {
        guard !cover.isEmpty else { return post }
        // Measured against the **bearing** the attack comes in on, not against
        // the far end of the field. A distant origin re-aims the line by a
        // hair's breadth for any step a person could actually take, so every
        // candidate would look at the same two cells as the post and nobody
        // would ever move. What a defender is doing is putting something on the
        // side they are coming from.
        func shelter(at point: LocalPoint) -> Double {
            let probe = LocalPoint(x: point.x + field.axisX * SiegeField.musterReach,
                                   y: point.y + field.axisY * SiegeField.musterReach)
            return cover.shelter(at: point, from: probe).fraction
        }
        let from = field.origin
        var best = post
        var bestCover = shelter(at: post)
        let steps = 8
        for i in 0..<steps {
            let angle = Double(i) / Double(steps) * 2 * .pi
            let here = LocalPoint(x: post.x + cos(angle) * coverSearch,
                                  y: post.y + sin(angle) * coverSearch)
            // Stepping *toward* the enemy to hide behind something is walking
            // into them, so a candidate is only ever a place further from the
            // attack than the post it replaces, or level with it.
            guard SiegeField.distance(here, from) >= SiegeField.distance(post, from)
            else { continue }
            let sheltered = shelter(at: here)
            guard sheltered > bestCover else { continue }
            bestCover = sheltered
            best = here
        }
        return best
    }

    /// What each colonist still in the line is worth, in the same weights the
    /// rest of the game is balanced on.
    private static func weights(
        of pawns: [Pawn], siege: Siege, registry: GameDataRegistry
    ) -> [UUID: (melee: Double, ranged: Double)] {
        let holding = Set(siege.standing)
        var out: [UUID: (melee: Double, ranged: Double)] = [:]
        for defender in BattleResolver.defenders(
            pawns.filter { holding.contains($0.id) }, registry: registry) {
            out[defender.id] = (defender.melee, defender.ranged)
        }
        return out
    }

    /// Takes it out of one raider — and out of the warband's total in the same
    /// breath. The aggregate decides whether the raid broke and the figures are
    /// what it is made of, so the two must never be allowed to drift apart.
    @discardableResult
    private static func wound(raider id: UUID, by amount: Double, siege: inout Siege) -> Double {
        guard amount > 0,
              let index = siege.fighters.firstIndex(where: { $0.id == id }),
              siege.fighters[index].side == .raider,
              siege.fighters[index].strength > 0 else { return 0 }
        let taken = min(siege.fighters[index].strength, amount)
        siege.fighters[index].strength -= taken
        if siege.fighters[index].strength <= 0 {
            siege.fighters[index].down = true
            siege.fighters[index].target = nil
        }
        siege.strength = max(0, siege.strength - taken)
        return taken
    }

    private static func markDown(_ id: UUID, in siege: inout Siege) {
        guard let index = siege.fighters.firstIndex(where: { $0.id == id }) else { return }
        siege.fighters[index].down = true
        siege.fighters[index].target = nil
    }

    // MARK: - Buildings that fight

    /// How much of a tower's `defense` comes out of it as shooting, per step.
    ///
    /// A watchtower is `defense: 20` — the same currency a palisade's 12 is in,
    /// and it must not simply be added to the wall *and* fired from, or a tower
    /// counts twice. It does not: `ColonyBuilder.isRampart` is walls only, so a
    /// tower contributes nothing to `fortification` and everything it is worth
    /// arrives as arrows off the top of it.
    static let towerShotShare = 0.08
    /// How far a tower can reach. Further than a bow in a hand, because that is
    /// what standing on a tower is for.
    static let towerRange = bowRange * 1.5
    /// How much of a blow aimed at a tower goes into the building.
    ///
    /// Raiders can pull one down, and it takes them a while: a warband that
    /// spends its raid hacking at a tower is a warband that is not in the
    /// stores, which is the trade a turret is supposed to offer.
    ///
    /// Sized so that three raiders working on one tower for most of a raid wreck
    /// it and a couple in passing do not — about fifty raider-steps to bring a
    /// sound one down. Losing a tower every raid would make it a consumable;
    /// never losing one would make it free.
    static let towerDamagePerStrength = 0.004

    /// The colony's towers, as things standing on the field.
    ///
    /// Manned by the fact of being built and worked — `BuildingEngine.isWorking`
    /// already means "standing, finished, not a wreck", and a derelict tower
    /// shoots nothing.
    static func emplacements(
        of settlement: Settlement, registry: GameDataRegistry
    ) -> [Siege.Combatant] {
        guard let colony = settlement.colony else { return [] }
        return colony.placements.compactMap { placement in
            guard BuildingEngine.isWorking(placement),
                  let def = registry.building(placement.definitionID),
                  def.look == "tower", def.defense > 0 else { return nil }
            return Siege.Combatant(
                id: placement.id, side: .colony,
                at: SettlementGeometry.canvasPoint(for: placement, in: colony),
                strength: def.defense * placement.condition,
                kind: .emplacement)
        }
    }

    /// The least a rampart on the far side of town is still worth.
    ///
    /// Not zero, and deliberately: the ditch runs round, the stakes came out of
    /// the same wood, and a colony that has walled itself is a harder place to
    /// walk into from any side. It is worth about a third of a wall you are
    /// actually standing behind.
    static let strayRampartShare = 0.30

    /// How much of what the colony built to defend itself stands on the side
    /// the attack is coming from, `strayRampartShare`…1.
    ///
    /// **Ramparts only.** A barracks counts wherever it is, because what is in
    /// it is people and people walk to the fighting; a palisade cannot. So a
    /// colony with no walls at all is untouched by this — its `defense` is
    /// garrison and events, and neither has a side.
    ///
    /// Weighted by condition as well as by bearing, so a wall the last raid
    /// half knocked down turns aside half as much as it did. That is the other
    /// end of `chipPerShotStopped`: the damage a fight does to the town is a
    /// cost the *next* fight collects.
    static func facingShare(
        _ settlement: Settlement, registry: GameDataRegistry, approach: Double
    ) -> Double {
        guard let colony = settlement.colony else { return 1 }
        var standing = 0.0, facing = 0.0
        for placement in colony.placements {
            guard !placement.underConstruction,
                  placement.condition >= BuildingEngine.derelictBelow,
                  let def = registry.building(placement.definitionID),
                  ColonyBuilder.isRampart(def) else { continue }
            let weight = def.defense * placement.condition
            let bearing = ColonyBuilder.bearingFromHeart(of: placement, in: colony)
            let delta = abs(ColonyBuilder.angleDifference(bearing, approach))
            standing += weight
            facing += weight * max(strayRampartShare, cos(delta))
        }
        guard standing > 0 else { return 1 }
        return facing / standing
    }

    /// How much of a blow the wall turns aside, 0…`fortificationCeiling`.
    ///
    /// A **share**, deliberately, and not the flat `defense × k` subtraction
    /// the one-tick resolver used. A flat subtraction has a threshold above
    /// which the whole attack is cancelled — a palisade of twenty made a
    /// sixty-strong warband literally unable to hurt anybody, which is the
    /// recurring bug in this project wearing armour: a number that crosses
    /// zero and takes the mechanic with it. A raid on a strong wall should be
    /// survivable. It should never be free.
    static func wallShare(fortification: Double, cover: Double) -> Double {
        let standing = max(0, fortification) * max(0, cover)
        return min(fortificationCeiling, standing / (standing + fortificationHalfPoint))
    }

    /// Stamps a beat where it happened inside the fight.
    ///
    /// Placed at the *middle* of its step, so no beat ever lands on 0 or 1:
    /// those are the edges of the window the canvas plays against, and a beat
    /// sitting exactly on one is a beat that has either always happened or
    /// never happened.
    static func momentPosition(step: Int) -> Double {
        min(0.995, max(0.005, (Double(step) + 0.5) / Double(Siege.stepsTotal)))
    }

    private static func moment(
        _ siege: Siege, _ kind: BattleMoment.Kind, pawnID: UUID? = nil,
        pawnName: String? = nil, amount: Double = 0, spot: LocalPoint? = nil
    ) -> BattleMoment {
        BattleMoment(id: siege.moments.count, at: momentPosition(step: siege.step),
                     kind: kind, pawnID: pawnID, pawnName: pawnName, amount: amount,
                     spot: spot)
    }

    // MARK: - Ending it

    /// Settles a finished siege: the dead are buried, the record is written,
    /// and the raiders take home whatever they got past the door with.
    public static func conclude(
        _ settlement: Settlement, registry: GameDataRegistry,
        language: GameLanguage = .cs
    ) -> Settlement {
        guard let siege = settlement.siege, siege.isFinished else { return settlement }
        var s = settlement
        s.siege = nil

        // Whoever went down and did not get back up, if they were people and
        // there is anywhere to hold them. Taken here rather than during the
        // fighting for the same reason the dead leave the roster here: while
        // the line is still swinging, "down" is not yet "captured".
        s = CaptiveEngine.take(s, siege: siege, registry: registry, language: language)

        // The record, sealed. A siege that broke says so as its last beat.
        var moments = siege.moments
        if siege.repelled {
            moments.append(BattleMoment(id: moments.count, at: 0.995, kind: .repelled))
        }
        s.lastBattle = BattleLog(
            id: siege.id, tick: siege.startTick,
            attackerName: siege.attackerName, defenderName: s.name,
            moments: moments, repelled: siege.repelled,
            attackerLabel: siege.attackerLabel, approach: siege.approach,
            attackers: siege.attackers, line: siege.line)

        // The dead leave the roster once the fighting is over, not during it.
        let deaths = s.pawns.filter { $0.health <= 0 }.count
        if deaths > 0 {
            s.pawns.removeAll { $0.health <= 0 }
            s.deathTallies[PawnDeathCause.battle.rawValue, default: 0] += deaths
        }

        // A raid turned back carries nothing home; one that got through takes
        // what its surviving strength could carry, on top of anything it
        // helped itself to while the colony was giving ground.
        if !siege.repelled {
            // What they can actually carry. A warband brought sacks; a pack
            // of wolves took a sheep and the same eight-to-thirty-five per cent
            // of the granary, which is what emptied colonies that were never
            // short of hands.
            let share = min(0.35, 0.08 + siege.strength / 200) * max(0, siege.carriesOff)
            let loot = s.storage[.food] * share
            s.storage[.food] -= loot
        }

        let entry: LocalizedText
        if siege.repelled {
            entry = LocalizedText(values: [
                .en: "\(siege.attackerName) came for the walls and were turned back.",
                .cs: "\(siege.attackerName) přišli na hradby a byli odraženi."])
        } else if deaths > 0 {
            entry = LocalizedText(values: [
                .en: "\(siege.attackerName) broke the line — \(deaths) did not get up.",
                .cs: "\(siege.attackerName) prolomili řadu — \(deaths) už nevstali."])
        } else {
            entry = LocalizedText(values: [
                .en: "\(siege.attackerName) took what they came for and left.",
                .cs: "\(siege.attackerName) si vzali, pro co přišli, a odešli."])
        }
        // Where it happened, so the record can be walked back to. The muster is
        // the ground the two lines met on — the heart of the colony is where
        // they were headed, and pointing there says nothing about the fight.
        s.journal.append(tick: siege.startTick, kind: .danger, text: entry,
                         subject: .place(SiegeField(approach: siege.approach).muster))
        s.stats.morale = max(0, s.stats.morale - (siege.repelled ? 0 : 8))
        return s
    }

    /// Charges the people who sent the warband for what the attempt cost them.
    ///
    /// Deliberately *after* the fighting rather than when the raid was
    /// declared: how much of a warband walks home is exactly what the player's
    /// orders decide, so pressing them hurts the neighbours and giving ground
    /// leaves them strong enough to come again.
    public static func chargeAttacker(_ state: WorldState, for siege: Siege) -> WorldState {
        guard let tribeID = siege.attackerTribeID,
              let index = state.tribes.firstIndex(where: { $0.id == tribeID })
        else { return state }
        var s = state
        let spent = max(0, siege.openingStrength - siege.strength)
        s.tribes[index].population = max(4, s.tribes[index].population - spent * 0.12)
        // What they got past the door with goes into their own stores.
        s.tribes[index].stores += siege.plundered
        return s
    }

    // MARK: - Orders

    /// Sets what the line is doing. Recorded on the siege, so it is an input to
    /// the fight rather than a thing that happened outside it.
    public static func order(
        _ settlement: Settlement, posture: Siege.Posture
    ) -> Settlement {
        guard var siege = settlement.siege, !siege.isFinished else { return settlement }
        var s = settlement
        siege.posture = posture
        s.siege = siege
        return s
    }

    /// Pulls one colonist out of the line, or puts them back in.
    ///
    /// The line is who is *taking* the blows as well as who is dealing them,
    /// so this is a real decision: a bleeding smith you pull out stops being
    /// the weakest target, and the next weakest becomes it.
    public static func withdraw(
        _ settlement: Settlement, pawnID: UUID, out: Bool = true
    ) -> Settlement {
        guard var siege = settlement.siege, !siege.isFinished,
              siege.line.contains(pawnID) else { return settlement }
        var s = settlement
        // Someone already down cannot be sent back in.
        let isDown = s.pawns.first { $0.id == pawnID }?.health ?? 0 <= 0
        if out {
            siege.withdrawn.insert(pawnID)
        } else if !isDown {
            siege.withdrawn.remove(pawnID)
        }
        s.siege = siege
        return s
    }

    /// Sends one colonist to a place on the field, and holds them there.
    ///
    /// The other half of the pivot. A posture steers the whole line, which is
    /// right for a game run by standing orders — but "I go somewhere and do
    /// something" needs somewhere to go, and now that a colonist has a position
    /// the Core owns, a tap on the ground is an order the simulation can carry
    /// out. Recorded on the siege exactly as the posture is: the same world plus
    /// the same orders still replays to the same dead.
    public static func order(
        _ settlement: Settlement, pawnID: UUID, moveTo point: LocalPoint
    ) -> Settlement {
        commanded(settlement, pawnID: pawnID) { $0[pawnID] = .moveTo(point) }
    }

    /// Sends one colonist after one raider. Aiming, in the only sense a fight
    /// on a ground has: you pick who, and they go.
    public static func order(
        _ settlement: Settlement, pawnID: UUID, engage raiderID: UUID
    ) -> Settlement {
        commanded(settlement, pawnID: pawnID) { $0[pawnID] = .engage(raiderID) }
    }

    /// Lets a colonist go back to doing whatever the posture says.
    public static func clearOrder(_ settlement: Settlement, pawnID: UUID) -> Settlement {
        commanded(settlement, pawnID: pawnID) { $0.removeValue(forKey: pawnID) }
    }

    private static func commanded(
        _ settlement: Settlement, pawnID: UUID,
        _ change: (inout [UUID: Siege.Order]) -> Void
    ) -> Settlement {
        guard var siege = settlement.siege, !siege.isFinished,
              siege.line.contains(pawnID) else { return settlement }
        var s = settlement
        change(&siege.orders)
        s.siege = siege
        return s
    }
}
