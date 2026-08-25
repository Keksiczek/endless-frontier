import Foundation

/// A fight that is **still happening**.
///
/// `BattleResolver` settles a raid inside one tick: eight rounds of arithmetic
/// run between two frames, the outcome is decided, and the `BattleLog` is a
/// recording played back afterwards. That is why a raid could be *watched* and
/// never *fought* — by the time the canvas was told anything, it was over.
///
/// A siege is the same fight with its middle left open. It is live state on the
/// settlement: the attackers' remaining strength, who is standing in the line,
/// which action step the fighting has reached, and — the point of all of it —
/// **what the player has told the line to do**. Orders are recorded here, so
/// they are an *input* to the resolution rather than a hole in it: the same
/// seed and the same orders replay to the same dead.
///
/// Pacing is not the model's business. A siege advances by absolute action
/// step, and whoever reaches a step first advances it: the app drives it at a
/// pace a person can act at, and if nobody is watching, `ActionLoop` walks the
/// world clock over the top of it and the rest is fought exactly as it would
/// have been. This is what makes leaving mid-battle safe.
public struct Siege: Codable, Sendable, Equatable, Identifiable {

    /// What the colony has been told to do. The one lever the player holds
    /// while the fighting is going on, and a real choice rather than a
    /// difficulty slider: what you save costs what you spend.
    public enum Posture: String, Codable, Sendable, CaseIterable {
        /// Stand at the wall. The fortification does its work; the line trades
        /// evenly. What the colony does with nobody steering it.
        case hold
        /// Push out past the wall and break them. Much more damage dealt, and
        /// the wall stops covering the people who left it.
        case press
        /// Fall back into the town. Almost nobody is hurt — and the granaries
        /// are open, so the raiders take what they came for.
        case giveGround

        /// How hard the line hits at this posture.
        public var bite: Double {
            switch self {
            case .hold: return 1
            case .press: return 1.75
            case .giveGround: return 0.25
            }
        }

        /// …and how much of what comes back actually lands on somebody.
        public var exposure: Double {
            switch self {
            case .hold: return 1
            case .press: return 1.6
            case .giveGround: return 0.2
            }
        }

        /// How far out from the town this posture is willing to fight.
        ///
        /// This replaces the old `cover` multiplier, and the difference is the
        /// whole pivot: a posture no longer *says* how much of the wall counts,
        /// it says **where people stand**, and `SiegeField.cover(at:)` reads the
        /// wall off the ground they are standing on. Pressing loses the wall
        /// because it walks out from behind it.
        public var reach: Double {
            switch self {
            case .hold: return SiegeField.musterReach
            case .press: return SiegeField.originReach
            case .giveGround: return 0
            }
        }

        public var label: LocalizedText {
            switch self {
            case .hold: return LocalizedText(values: [
                .en: "Hold the wall", .cs: "Držet hradbu"])
            case .press: return LocalizedText(values: [
                .en: "Press them", .cs: "Vyrazit na ně"])
            case .giveGround: return LocalizedText(values: [
                .en: "Give ground", .cs: "Ustoupit"])
            }
        }

        public var note: LocalizedText {
            switch self {
            case .hold: return LocalizedText(values: [
                .en: "The wall does its work.", .cs: "Hradba dělá svoje."])
            case .press: return LocalizedText(values: [
                .en: "Break them faster — and out from behind the wall.",
                .cs: "Zlomit je rychleji — a zpoza hradby ven."])
            case .giveGround: return LocalizedText(values: [
                .en: "Nobody dies for grain.", .cs: "Za obilí se neumírá."])
            }
        }
    }

    /// One figure on the field, and **where it is standing**.
    ///
    /// The fight used to be arithmetic on one strength number paired against a
    /// round index: raider seven fought colonist three because seven and three
    /// were opposite each other in two lists. Nobody walked anywhere, which is
    /// exactly why the rounds felt strange to stand in — the canvas drew an
    /// arrangement of people the simulation did not have.
    ///
    /// A combatant has a position the Core owns and moves. Contact is being
    /// close enough to reach, the approach is *not being close enough yet*
    /// rather than a step count, and an order to go somewhere is a thing the
    /// simulation can actually carry out.
    public struct Combatant: Codable, Sendable, Equatable, Identifiable {
        public enum Side: String, Codable, Sendable { case colony, raider }

        /// Whether this is somebody standing on the field or something the
        /// colony built that fights from where it stands.
        ///
        /// **The first thing in the game that is a building which acts.** A
        /// watchtower holds ground, has a line to what it is shooting at, and
        /// is worth attacking because of where it stands — none of which an
        /// abstract `defense` number can express (§11.27). It is a combatant
        /// rather than a special case in the resolver because everything the
        /// field already does — position, targeting, reach, the canvas reading
        /// where things are — is exactly what a turret needs.
        public enum Kind: String, Codable, Sendable { case person, emplacement }

        /// **What a raider came here to do**, and goes on doing until it is
        /// done or they are.
        ///
        /// Every raider used to want the same thing — the nearest colonist —
        /// and `aim` re-decided it from scratch every step, so the whole field
        /// converged into two lines that shuffled sideways against each other
        /// and nobody on it had an intention that outlived a single step.
        /// Keks: *"chovat se že útočí nějak cíleně, ne že teď vedle sebe
        /// hýbají dvě čáry lidí."*
        ///
        /// A warband is not one thing. Some of it comes to fight, some of it
        /// came for the granary and will walk round a line rather than through
        /// it, and some of it came to burn a particular roof. That is three
        /// different destinations out of the same arithmetic, and it is what
        /// makes a raid look aimed rather than magnetic.
        public enum Intent: String, Codable, Sendable, CaseIterable {
            /// Fight whoever is in the way. What the whole warband used to be.
            case fight
            /// The stores. Turns aside only for somebody actually blocking.
            case plunder
            /// One building, picked before they set off.
            case burn
        }

        /// A colonist's pawn id, a raider's own stable id, or — for an
        /// emplacement — the id of the building itself.
        public let id: UUID
        public let side: Side
        /// What it is. Old saves have none and are people, which is what
        /// everything on a field before this was.
        public var kind: Kind = .person
        /// Where they are, in local-map coordinates.
        public var at: LocalPoint
        /// What a raider is still worth — their share of the warband, spent as
        /// the line cuts them down. A colonist's weight is their health, so
        /// this holds their opening power and is only read, never spent.
        public var strength: Double
        /// Who they have closed on, if anybody.
        public var target: UUID?
        /// Down, or gone from the field.
        public var down: Bool
        /// What they came for. Colonists defend and towers stand still, so
        /// this only ever means anything on a raider.
        public var intent: Intent = .fight
        /// The place their intent is aimed at — the roof they came to burn.
        /// `nil` for everybody whose business is with people rather than with
        /// a piece of ground.
        public var goal: LocalPoint?
        /// **The step this body last took a blow on, and where it came from.**
        ///
        /// The fight had swings and it had blood on the ground, and nothing in
        /// between: a blade passed through a body that went on walking exactly
        /// as before, and the only sign a blow had landed was a stain
        /// appearing. Keks: *"radoby se mydlí."* A hit is a thing that happens
        /// **to** somebody, so the body has to know it was hit — the canvas
        /// reads these two and jolts the figure away from the blow for the
        /// step it lands in (rule 5: it reads, it never writes).
        public var struckAtStep: Int?
        public var struckFrom: LocalPoint?

        public init(id: UUID, side: Side, at: LocalPoint, strength: Double,
                    target: UUID? = nil, down: Bool = false,
                    kind: Kind = .person, intent: Intent = .fight,
                    goal: LocalPoint? = nil,
                    struckAtStep: Int? = nil, struckFrom: LocalPoint? = nil) {
            self.id = id
            self.side = side
            self.kind = kind
            self.at = at
            self.strength = strength
            self.target = target
            self.down = down
            self.intent = intent
            self.goal = goal
            self.struckAtStep = struckAtStep
            self.struckFrom = struckFrom
        }

        private enum CodingKeys: String, CodingKey {
            case id, side, kind, at, strength, target, down, intent, goal
            case struckAtStep, struckFrom
        }

        /// Written by hand because a synthesised decoder does **not** fall back
        /// to a property's default value: a raid saved before turrets existed
        /// carries no `kind`, and the synthesised one would refuse to load it —
        /// which is a battle in progress lost to an app update.
        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decode(UUID.self, forKey: .id)
            side = try c.decode(Side.self, forKey: .side)
            kind = try c.decodeIfPresent(Kind.self, forKey: .kind) ?? .person
            at = try c.decode(LocalPoint.self, forKey: .at)
            strength = try c.decode(Double.self, forKey: .strength)
            target = try c.decodeIfPresent(UUID.self, forKey: .target)
            down = try c.decodeIfPresent(Bool.self, forKey: .down) ?? false
            // A raid saved before anybody had a purpose is a field of people
            // who all came to fight, which is what it was.
            intent = try c.decodeIfPresent(Intent.self, forKey: .intent) ?? .fight
            goal = try c.decodeIfPresent(LocalPoint.self, forKey: .goal)
            // A fight saved before bodies reacted to blows simply has nobody
            // flinching until the next one lands (rule 3).
            struckAtStep = try c.decodeIfPresent(Int.self, forKey: .struckAtStep)
            struckFrom = try c.decodeIfPresent(LocalPoint.self, forKey: .struckFrom)
        }
    }

    /// What the player has told **one** colonist to do, by tapping them and
    /// then tapping the ground or an enemy.
    ///
    /// Recorded on the siege exactly as `posture` is, for exactly the same
    /// reason: the fight may depend on the player's orders, but given the same
    /// seed *and the same orders* it has to replay to the same dead. An order
    /// that lived in the view would be a hole in determinism.
    public enum Order: Codable, Sendable, Equatable {
        /// Go there and hold it.
        case moveTo(LocalPoint)
        /// Go for that one.
        case engage(UUID)
    }

    /// How many action steps a siege runs before it is decided one way or the
    /// other, when nothing says otherwise.
    ///
    /// **Read in real seconds, because that is what a player experiences.**
    /// `GameViewModel.siegeStepSeconds` is 1.4 while somebody is watching, so
    /// this is about a minute for a middling raid, half that for a handful of
    /// bandits, and a little over two minutes for a host.
    ///
    /// It was 24 — thirty-four seconds — and measured fights ran shorter still,
    /// between **seven and thirty-six seconds** end to end (`ZZBattleDiag`).
    /// Keks: *"netrvalo jak dlouho by melo."*
    ///
    /// It is no longer the clock: `isFinished` ends a fight when a side breaks.
    /// What this still does is set the *pace* — `meleePerStep` divides the
    /// line's weight by it, so a bigger number is a slower, longer exchange
    /// rather than a shorter one that hits harder.
    public static let stepsTotal = 40

    /// The shortest a fight can be and still be one. Below about this the
    /// approach is not over before the thing is decided, and a raid the player
    /// cannot react to is a number, not a battle.
    public static let stepsFloor = 20

    /// …and the longest. A fight that runs on for ever is a bug wearing
    /// drama's coat, and the siege holds the colony's line the whole time it
    /// lasts.
    public static let stepsCeiling = 96

    /// **How long *this* fight lasts.**
    ///
    /// Every siege used to run exactly `stepsTotal`. Three bandits and a whole
    /// tribe's warband took the same twenty-four steps, and a fight could end
    /// early on a break but never run long — so a big battle was cut off by the
    /// clock rather than decided, and a colony that was one step from finishing
    /// somebody was simply told the time was up. Keks: *"ať boje nemají pevné
    /// trvání, to je docela omezení."*
    ///
    /// Length comes from the size of the **assault** now: a raid by six is
    /// short, a siege by a host is long, and both are bounded so neither
    /// becomes a flicker or a chore.
    ///
    /// **Off the attackers alone, and that is deliberate.** Counting the
    /// defenders too — the obvious first version — made a well-manned town
    /// *lengthen* its own siege, and a longer siege is more steps of plunder:
    /// a town of sixty lost more stores to the same raid than a town of ten,
    /// which is the exact opposite of what defending is for. How many hold the
    /// line already decides the fight through the line's weight; letting it
    /// decide the clock as well pays the attacker for the defence.
    public static func lengthFor(attackers: Int) -> Int {
        // Square-rooted rather than linear: doubling a warband should make the
        // fight noticeably longer, not twice as long, or a late-era war would
        // run for an hour of real time.
        let scaled = Double(stepsTotal) * (Double(max(1, attackers)) / 12).squareRoot()
        return max(stepsFloor, min(stepsCeiling, Int(scaled.rounded())))
    }

    public let id: UUID
    /// The world tick the attack arrived on.
    public let startTick: Int
    /// The absolute action step the fighting has been carried up to. The whole
    /// pacing contract: a step is fought once, by whoever reaches it first.
    public var advancedTo: Int
    /// The absolute action step the siege opened on.
    public let openedAt: Int

    public let attackerName: String
    public let attackerLabel: LocalizedText?
    /// The people who sent them, when a people did. What the attempt cost them
    /// is only known when the fighting stops, so the tribe is charged at the
    /// end rather than when the raid was declared.
    public let attackerTribeID: UUID?
    /// The camp they walked out of, when outlaws sent them. Kept apart from
    /// `attackerTribeID` on purpose: a camp is not a people, it has no
    /// standing to lose and nothing to negotiate, and the only thing charged
    /// to it at the end is what the fighting cost it — see `OutlawCamp`.
    public var attackerCampID: UUID?
    /// The bearing they came in on, so the canvas draws the same fight the
    /// simulation is running.
    public let approach: Double
    /// **How far the built town reached on that bearing when they arrived.**
    ///
    /// The fight's whole geometry hangs off this — where the line forms, where
    /// the wall is worth something, where the warband starts. It is stamped
    /// once, when the raid opens, for the same reason `steps` is: a town that
    /// finishes a barn mid-siege must not move the line the fight is already
    /// being fought on. Zero means "no grid" and the field falls back to the
    /// old constants (`SiegeField.edge`).
    public var edge: Double = 0
    /// How many figures the raid puts on the field.
    public let attackers: Int
    /// What the attack was worth when it arrived, and what is left of it.
    public let openingStrength: Double
    public var strength: Double
    /// The colony's standing defence — walls do not swing, but they absorb.
    public let fortification: Double
    /// Rolls come from this and the step index, so a step's outcome is a pure
    /// function of where it sits in the fight.
    public let seed: UInt64
    /// **The age the fight is being fought in.**
    ///
    /// A warband carries the arms of its own century, and until this was here
    /// the fight had no way to know which century that was: `fightOneStep`
    /// takes a `Settlement`, and an era belongs to the world. Stored on the
    /// siege rather than looked up, so a raid saved half-fought is finished
    /// with the weapons it started with.
    public var era: Era = .earlySettlement

    /// **How many steps this fight runs**, from how big it is. See
    /// `lengthFor(attackers:defenders:)`.
    ///
    /// Stored rather than recomputed, because the line thins as people fall
    /// and a fight whose length shortened every time somebody went down would
    /// accelerate toward its own end. It is decided once, when the attack
    /// arrives, and then it is the clock.
    public let steps: Int

    /// Everyone who turned out, in the order they took the line.
    public var line: [UUID]
    /// …and the ones the player has pulled out of it. They stop being a target
    /// and stop counting toward the line's weight.
    public var withdrawn: Set<UUID>
    /// How much of the stores this attacker can actually carry off, as a
    /// multiple of the usual share.
    ///
    /// A warband comes with sacks and mules; a wolf pack takes a sheep. Both
    /// used to take the same eight-to-thirty-five per cent of the granary, and
    /// with a pack arriving every few years that quietly emptied the colony —
    /// measured, 388 starved over two centuries in a town that was never short
    /// of hands. What an attacker *is* has to decide what it can steal.
    public var carriesOff: Double

    /// What the player has told the line to do, right now.
    public var posture: Posture
    /// Everyone on the field, with a place on it. Colonists first, in the order
    /// they took the line, then the raiders as they come over the ground.
    public var fighters: [Combatant]
    /// …and what individual colonists have been told, over the top of the
    /// posture. Empty is the normal case: a colony is run by standing orders
    /// and a battle should not demand that sixty people be steered one by one.
    public var orders: [UUID: Order]
    /// Damage dealt so far, by pawn — applied to the colonists as it lands.
    public var damage: [UUID: Double]
    /// The record as it accumulates, so the canvas can draw a fight that has
    /// not finished yet.
    public var moments: [BattleMoment]
    /// Food carried off while the colony gave ground.
    public var plundered: Double

    public init(
        id: UUID, startTick: Int, openedAt: Int,
        attackerName: String, attackerLabel: LocalizedText? = nil,
        attackerTribeID: UUID? = nil,
        attackerCampID: UUID? = nil,
        approach: Double, attackers: Int,
        /// How far the built town reaches on that bearing. Zero for a colony
        /// with no grid — the field falls back to its constants.
        edge: Double = 0,
        openingStrength: Double, fortification: Double, seed: UInt64,
        line: [UUID], posture: Posture = .hold, carriesOff: Double = 1,
        steps: Int? = nil,
        era: Era = .earlySettlement
    ) {
        self.id = id
        self.startTick = startTick
        self.openedAt = openedAt
        self.advancedTo = openedAt
        self.attackerName = attackerName
        self.attackerLabel = attackerLabel
        self.attackerTribeID = attackerTribeID
        self.attackerCampID = attackerCampID
        self.approach = approach
        self.edge = edge
        self.attackers = attackers
        self.openingStrength = max(0, openingStrength)
        self.strength = max(0, openingStrength)
        self.fortification = max(0, fortification)
        self.seed = seed
        self.steps = steps ?? Self.lengthFor(attackers: attackers)
        self.era = era
        self.line = line
        self.withdrawn = []
        self.posture = posture
        self.carriesOff = carriesOff
        self.fighters = []
        self.orders = [:]
        self.damage = [:]
        self.moments = []
        self.plundered = 0
    }

    /// Which step of its own fight the siege is on, `0 ..< steps`.
    public var step: Int { max(0, advancedTo - openedAt) }

    /// How far through the fight it is, 0…1 — what the canvas plays against.
    public var progress: Double {
        min(1, Double(step) / Double(max(1, steps)))
    }

    /// **What share of its opening weight a warband will take before it runs.**
    ///
    /// Nobody fights to the last man. A raid is a business proposition, and it
    /// stops being one long before the warband is annihilated — so the fight
    /// ends when they break, which is a thing that *happens in the fight*
    /// rather than a number the clock reaches.
    public static let routAtShare = 0.30

    /// …and how thin the line can get before the rest of it gives way. A
    /// colony does not stand and be killed to the last defender either.
    public static let lineBreaksBelow = 0.25

    /// A last stop, so a fight that somehow cannot resolve is a long fight and
    /// not a hung game. Nothing should ever reach it; `ZZBattleDiag` prints
    /// when anything does.
    public static let stepsHardCeiling = 400

    /// Whether the warband has had enough.
    public var routed: Bool {
        strength <= max(0, openingStrength * Self.routAtShare)
    }

    /// **Whether the fighting is over.**
    ///
    /// Keks: *"bojovat by se melo dokud nepadne jedna strana nebo utecou."*
    /// It used to end on `step >= steps` alone — a clock — so a fight one
    /// exchange from being decided was told the time was up, and a raid could
    /// be over in seven seconds with both sides intact.
    ///
    /// It ends on the **rout** now, which is a thing that happens in the fight.
    /// The clock is still here and is now only a backstop, because a fight
    /// where neither side can finish the other does exist: measured with the
    /// clock taken out entirely, ninety raiders against six defenders ran
    /// eighty steps for 90 → 56 strength and would have needed three hundred
    /// more. A stalemate has to end somehow, and "they gave it up and went
    /// home" is the honest reading of one.
    ///
    /// **A broken line does not end it.** They have the run of the place and
    /// they stay for it — ending here, which is what it used to do, meant a
    /// colony whose line gave way *kept its stores*, so a town of ten came out
    /// of a raid better than a town of sixty.
    public var isFinished: Bool {
        routed || step >= steps
    }

    /// The colonists actually holding the line right now.
    public var standing: [UUID] {
        line.filter { !withdrawn.contains($0) }
    }

    /// Whether the colony held. Only meaningful once it is finished.
    ///
    /// Breaking a warband counts, and it is the ordinary way a raid ends now:
    /// they do not have to be killed to the last man to have been driven off.
    public var repelled: Bool { routed }

    // MARK: - The field, read

    public var raiders: [Combatant] { fighters.filter { $0.side == .raider } }
    /// The **people** holding the line. A tower is not one of them: it is not in
    /// the roster, it is not counted as somebody still standing, and it does not
    /// leave a body when it falls. See `emplacements`.
    public var defenders: [Combatant] {
        fighters.filter { $0.side == .colony && $0.kind == .person }
    }
    /// …and the things the colony built that fight from where they stand.
    public var emplacements: [Combatant] {
        fighters.filter { $0.kind == .emplacement }
    }

    /// Whether anybody is close enough to anybody to be fighting them. What
    /// "the ranks are in contact" means now that there is a ground to be on —
    /// the phase is read off the field rather than off a step number.
    public var inContact: Bool {
        let colony = fighters.filter { $0.side == .colony && !$0.down }
        guard !colony.isEmpty else { return false }
        return fighters.contains { raider in
            guard raider.side == .raider, !raider.down else { return false }
            return colony.contains { SiegeField.distance($0.at, raider.at) <= SiegeEngine.reach }
        }
    }

    /// Where a given fighter is standing, if they are on this field.
    public func place(of id: UUID) -> LocalPoint? {
        fighters.first { $0.id == id }?.at
    }

    // MARK: - Codable (resilient: sieges postdate the first battles)

    private enum CodingKeys: String, CodingKey {
        case id, startTick, advancedTo, openedAt, attackerName, attackerLabel
        case attackerTribeID, attackerCampID
        case approach, attackers, openingStrength, strength, fortification, seed
        case line, withdrawn, posture, damage, moments, plundered, carriesOff
        case steps, era, edge
        case fighters, orders
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        startTick = try c.decode(Int.self, forKey: .startTick)
        openedAt = try c.decodeIfPresent(Int.self, forKey: .openedAt) ?? 0
        advancedTo = try c.decodeIfPresent(Int.self, forKey: .advancedTo) ?? openedAt
        attackerName = try c.decode(String.self, forKey: .attackerName)
        attackerLabel = try c.decodeIfPresent(LocalizedText.self, forKey: .attackerLabel)
        attackerTribeID = try c.decodeIfPresent(UUID.self, forKey: .attackerTribeID)
        attackerCampID = try c.decodeIfPresent(UUID.self, forKey: .attackerCampID)
        approach = try c.decodeIfPresent(Double.self, forKey: .approach) ?? 0
        // A fight saved before the town's own edge decided where the line
        // forms is finished on the constants it started on (rule 3).
        edge = try c.decodeIfPresent(Double.self, forKey: .edge) ?? 0
        attackers = try c.decodeIfPresent(Int.self, forKey: .attackers) ?? 1
        openingStrength = try c.decodeIfPresent(Double.self, forKey: .openingStrength) ?? 0
        strength = try c.decodeIfPresent(Double.self, forKey: .strength) ?? 0
        fortification = try c.decodeIfPresent(Double.self, forKey: .fortification) ?? 0
        seed = try c.decodeIfPresent(UInt64.self, forKey: .seed) ?? 1
        line = try c.decodeIfPresent([UUID].self, forKey: .line) ?? []
        // A save from before fights had lengths of their own gets the old
        // fixed one, which is exactly what it was fought at.
        steps = try c.decodeIfPresent(Int.self, forKey: .steps) ?? Self.stepsTotal
        era = try c.decodeIfPresent(Era.self, forKey: .era) ?? .earlySettlement
        withdrawn = try c.decodeIfPresent(Set<UUID>.self, forKey: .withdrawn) ?? []
        posture = try c.decodeIfPresent(Posture.self, forKey: .posture) ?? .hold
        carriesOff = try c.decodeIfPresent(Double.self, forKey: .carriesOff) ?? 1
        // A raid saved before anybody had a position on the field: the engine
        // stages the roster on the next step it fights (rule 3 — every new
        // field optional, with a default that the code can actually work from).
        fighters = try c.decodeIfPresent([Combatant].self, forKey: .fighters) ?? []
        orders = try c.decodeIfPresent([UUID: Order].self, forKey: .orders) ?? [:]
        damage = try c.decodeIfPresent([UUID: Double].self, forKey: .damage) ?? [:]
        moments = try c.decodeIfPresent([BattleMoment].self, forKey: .moments) ?? []
        plundered = try c.decodeIfPresent(Double.self, forKey: .plundered) ?? 0
    }
}
