import Foundation
import EndlessFrontierCore

/// Purely presentational movement for the living settlement view. Positions
/// are derived from each colonist's stable id and a continuous frame clock —
/// never written back to the simulation, so the deterministic Core is
/// untouched and the world just *looks* alive.
///
/// V2 of the motion: colonists live a **day**. They wake at home, walk to the
/// workplace their actual `assignedWork` implies — the field, the quarry, the
/// scaffolding, the temple — gather on the green at midday, work the
/// afternoon, and drift home for the night. What you see is what the colony
/// is genuinely doing.
///
/// The day is **seasonal** (`DayShape`): people rise with the light and stop
/// when it goes, so midsummer is a long working day over a short night and
/// deep winter is the reverse. Note this is still the *look* of work — the
/// simulation has no clock of its own, and `ResourceLoop` produces the same
/// amount at midnight as at noon. Making the hours count is the job layer,
/// see `docs/RIMWORLD_LAYER.md`.
/// Places the simulation's clock on the frame clock.
///
/// A tick is a real minute, so anything driven by whole ticks moves once a
/// minute — a party crossing the valley would teleport. This carries the last
/// tick and when it happened, so the canvas can ask for a *fractional* tick at
/// any instant and interpolate. Read-only: the simulation never sees it.
struct TickClock: Equatable {
    let tick: Int
    let lastTickAt: Date
    let realSecondsPerTick: Double

    func continuous(at now: Date) -> Double {
        guard realSecondsPerTick > 0 else { return Double(tick) }
        let elapsed = now.timeIntervalSince(lastTickAt)
        return Double(tick) + min(1, max(0, elapsed / realSecondsPerTick))
    }
}

enum AgentMotion {
    /// Seconds of real time one settlement day takes on screen.
    ///
    /// Two and a half minutes was the wrong number, and every complaint about
    /// the valley being *restless* came back to it: the sun crossed the sky in
    /// the time it takes to read a card, so shadows swung visibly while you
    /// looked at them and the ground changed shade under your thumb. Five
    /// minutes is still a day you can watch happen — the town wakes, works,
    /// gathers at midday and goes to bed inside a sitting — without the light
    /// being the fastest-moving thing on the screen.
    static let dayLength: Double = 300

    /// How far apart two points on the map are — the walk a colonist has ahead
    /// of them.
    static func distance(_ a: LocalPoint, _ b: LocalPoint) -> Double {
        let dx = a.x - b.x, dy = a.y - b.y
        return (dx * dx + dy * dy).squareRoot()
    }

    /// How much ground a colonist covers in a day of walking, in map widths.
    ///
    /// Travel used to take a **fixed slice of the day whatever the distance**,
    /// so someone whose field was next door crept across it while someone whose
    /// field was clear across the valley crossed twenty times as much ground in
    /// the same moment — a village of ploddders with the odd sprinter shooting
    /// past them. Everyone now keeps the same pace and a long walk simply takes
    /// longer, which is also why the far side of the map now feels far.
    static let walkSpeed: Double = 4.5

    /// What a colonist is visibly doing right now — drives posture, tools and
    /// the inspector's "right now" line.
    enum Activity {
        case sleeping      // night, at home
        case atHome        // morning/evening indoors
        case walking       // between anchors
        case working       // at the workplace
        case socializing   // midday on the green
        case playing       // children
        case resting       // broken/sick — home all day
        case travelling    // out on the road to a landmark, or coming back
        case expedition    // at the landmark, working it
        case fighting      // called out of the day and into the line
        case hauling       // carrying a load home
        case riding        // carrying a load home on something with legs or wheels

        /// Which clip in `motions.json` draws this.
        ///
        /// The enum stays: what a colonist is *doing* is the simulation's
        /// answer and belongs in code. How the body moves while doing it is
        /// content, and lives in the bank — so a richer hunt is new entries
        /// rather than new cases in here.
        var motionID: String {
            switch self {
            case .sleeping:    return "sleeping"
            case .atHome:      return "at_home"
            case .walking:     return "walking"
            case .working:     return "working"
            case .socializing: return "socializing"
            case .playing:     return "playing"
            case .resting:     return "resting"
            case .travelling:  return "travelling"
            case .expedition:  return "expedition"
            case .fighting:    return "fighting"
            case .hauling:     return "hauling"
            case .riding:      return "riding"
            }
        }
    }

    /// A colonist's place and doing at an instant.
    struct Pose {
        let position: LocalPoint
        let activity: Activity
        /// 0…1 walk-cycle weight — legs swing only when actually under way.
        let stride: Double
        /// Which way they are looking, as the x-component of where they are
        /// going: −1 hard left, +1 hard right, 0 facing the viewer.
        ///
        /// Everyone used to face right for ever. A colonist walking west
        /// crossed the valley backwards with the hoe in their leading hand,
        /// which is the single thing that most made the figures read as
        /// sprites being slid about rather than as people going somewhere.
        let facing: Double

        init(position: LocalPoint, activity: Activity, stride: Double, facing: Double = 0) {
            self.position = position
            self.activity = activity
            self.stride = stride
            self.facing = max(-1, min(1, facing))
        }
    }

    /// Which moment of the hunt to draw, at *frame* resolution.
    ///
    /// A split, and the line matters. **A kill is the simulation's to report**:
    /// only `HuntEngine` knows a beast went down this tick, and no amount of
    /// looking at positions will tell you. **Closing is the canvas's to see**:
    /// the hunter's position and the animals' are both already on screen, and
    /// the distance between them is a fact about the picture.
    ///
    /// Left to the engine alone this changed twice a minute, because a hunt
    /// resolves once a tick and a tick is two real minutes — a chase drawn as
    /// a slideshow. Moving the *hunt* to the eight-step action clock instead
    /// would have multiplied every kill roll by eight (rule 34: a rate in the
    /// wrong unit), so the resolution the eye wants is taken where it is free.
    static func huntPhase(for pawn: Pawn, reported: HuntEngine.Phase?,
                          map: LocalMap, at position: LocalPoint) -> String? {
        guard pawn.assignedWork == .hunting else { return nil }
        // A kill stands until the engine says otherwise: the carcass has to be
        // carried home, and that is the one moment worth holding on screen.
        if reported == .killed { return HuntEngine.Phase.killed.rawValue }
        let quarry = map.wildlife.animals.filter { !$0.isPredator }
        guard !quarry.isEmpty else { return HuntEngine.Phase.stalking.rawValue }
        let nearest = quarry.map { animal -> Double in
            let dx = animal.position.x - position.x, dy = animal.position.y - position.y
            return (dx * dx + dy * dy).squareRoot()
        }.min() ?? .greatestFiniteMagnitude
        return nearest <= HuntEngine.reach
            ? HuntEngine.Phase.closing.rawValue
            : HuntEngine.Phase.stalking.rawValue
    }

    /// Which of several equally-fitting clips *this* colonist plays right now.
    ///
    /// The motion bank holds seven ways to work a field and six ways to work a
    /// building site, and until this existed the colony played one of each: the
    /// registry broke ties on id, so every farmer dug and seventeen clips of
    /// forty-eight were never drawn at all. Variety is not more content, it is
    /// a seed to choose content with.
    ///
    /// Seeded from the colonist **and the piece of work they are on**, which is
    /// what makes it read as people rather than as noise:
    ///
    /// - Two farmers in the same field are drawn doing different things,
    ///   because their ids differ.
    /// - One farmer keeps their clip for as long as they are on that plot —
    ///   the seed does not move between frames, so nobody flickers between
    ///   sowing and reaping sixty times a second.
    /// - Finishing a plot and starting the next one deals a new clip, which is
    ///   the moment the work genuinely changed.
    ///
    /// Presentation only, and pure: same colonist, same job, same clip, for
    /// ever. Nothing here is written back to the simulation (rule 5).
    static func motionVariant(for pawn: Pawn) -> UInt64 {
        var h: UInt64 = 0xCBF2_9CE4_8422_2325
        let u = pawn.id.uuid
        for byte in [u.0, u.1, u.2, u.3, u.4, u.5, u.6, u.7,
                     u.8, u.9, u.10, u.11, u.12, u.13, u.14, u.15] {
            h = (h ^ UInt64(byte)) &* 0x0100_0000_01B3
        }
        if let job = pawn.currentJob {
            let j = job.id.uuid
            for byte in [j.0, j.1, j.2, j.3, j.4, j.5, j.6, j.7] {
                h = (h ^ UInt64(byte)) &* 0x0100_0000_01B3
            }
        }
        return h ^ (h >> 29)
    }

    /// The x-component of a heading from `a` to `b`, normalised — what `Pose`
    /// carries as `facing`. Zero for two points on top of each other, so a
    /// colonist who has arrived does not spin.
    static func facing(from a: LocalPoint, to b: LocalPoint) -> Double {
        let dx = b.x - a.x, dy = b.y - a.y
        let len = (dx * dx + dy * dy).squareRoot()
        return len < 1e-6 ? 0 : dx / len
    }

    /// A building a colonist works *at*, and the ground it covers — so several
    /// workers spread across the lot instead of stacking on one point.
    ///
    /// It also carries the room's own furniture plan: a building is a room now
    /// (`SettlementInterior`), and a worker belongs at a *station* in it — the
    /// anvil, the desk, the counter — not somewhere on its roof. `stations`
    /// holds those places in the same normalised space the rest of the motion
    /// speaks, computed from exactly the seed and footprint the fittings are
    /// drawn from, so the smith stands at the anvil that is on the screen.
    struct WorkSite {
        let center: LocalPoint
        let halfW: Double
        let halfH: Double
        let stations: [LocalPoint]
        /// Which station each colonist on the roster holds.
        ///
        /// Picking a station by hashing the colonist put two of them on the
        /// same stool about half the time in a two-seat room — a hash spreads
        /// things *on average*, which is no use at all when there are two of
        /// them. The roster is an order, so it is the seating plan: the first
        /// name on the building's books takes the first station.
        let byPawn: [UUID: LocalPoint]
        /// **The way in.** A point just outside the front wall, on the door.
        ///
        /// Colonists used to arrive at their station by the shortest line from
        /// wherever they had been standing, which for half the colony meant
        /// walking through a side wall or the back of the roof. A building has
        /// had a drawn door the whole time and nothing that moved knew where it
        /// was. Read from `SettlementStructures.doorOffset`, the same number the
        /// door is drawn at, so they cannot disagree.
        let entrance: LocalPoint
        /// Which building this is, by `buildings.json` id — what the motion
        /// bank keys `serves_buildings` on, so the smith at the forge and the
        /// weaver at the loom are drawn doing different things.
        let definitionID: String
        /// The floor inside the walls, in normalised map units — the space a
        /// `SettlementInterior.Slot` is measured against.
        let roomW: Double
        let roomH: Double

        /// Where a furniture slot actually stands on the map.
        ///
        /// The one place this arithmetic is written down. `Slot`'s own comment
        /// used to call itself "lot-relative", and the interior drawing had
        /// long since moved to measuring against the **room** — so the beds
        /// `AgentMotion` placed (which had kept the lot) were the only thing in
        /// the game still using the old measure. A household went to sleep
        /// spread across the whole parcel while their beds were drawn in a
        /// tight ring inside the walls: nobody was on a mattress, and the ones
        /// the lot pushed together were drawn standing in each other.
        func place(_ slot: SettlementInterior.Slot) -> LocalPoint {
            LocalPoint(x: center.x + slot.dx * roomW, y: center.y + slot.dy * roomH)
        }

        init(_ b: SettlementRenderer.NormalizedBuilding,
             era: Era, registry: GameDataRegistry) {
            definitionID = b.definitionID
            center = b.center
            halfW = b.footprintW / 2
            halfH = b.footprintH / 2
            // Inside the walls the renderer actually draws, not across the whole
            // lot: the fittings are laid out in the room (see
            // `SettlementStructures.bodyRect`), so the people at them have to
            // be measured against the same room or the smith stands in the
            // yard hammering nothing.
            let walls = SettlementStructures.bodySize(
                b.glyph, s: b.size, seed: b.seed,
                aspect: b.footprintH > 0 ? b.footprintW / b.footprintH : 1)
            let roomW = walls.width * (1 - SettlementInterior.wallInset * 2)
            let roomH = walls.height * (1 - SettlementInterior.wallInset * 2)
            self.roomW = roomW
            self.roomH = roomH
            let places = SettlementInterior
                .stationSlots(for: b.glyph, seed: b.seed,
                              stations: b.assignedPawnIDs.count,
                              era: era, registry: registry)
                .map { LocalPoint(x: b.center.x + $0.dx * roomW,
                                  y: b.center.y + $0.dy * roomH) }
            stations = places
            var seating: [UUID: LocalPoint] = [:]
            for (index, id) in b.assignedPawnIDs.enumerated() where !places.isEmpty {
                seating[id] = places[index % places.count]
            }
            byPawn = seating
            // On the threshold: along the front wall at the door, and a step
            // clear of it so somebody standing in the doorway is *in* the
            // doorway rather than inside the room already.
            let dx = SettlementStructures.doorOffset(
                b.glyph, seed: b.seed, width: CGFloat(walls.width), s: CGFloat(b.size))
            entrance = LocalPoint(x: b.center.x + dx * walls.width,
                                  y: b.center.y + walls.height * 0.5 + b.size * 0.12)
        }
    }

    // MARK: - The stage

    /// Everything the motion needs to know about *where things are*, computed
    /// once per frame and shared with the renderer and hit-testing.
    struct Scene {
        let layout: [SettlementRenderer.NormalizedBuilding]
        let homes: [LocalPoint]
        /// The post the simulation gave each colonist: pawn id → the lot of the
        /// building they are actually on the roster of. This is the truth the
        /// canvas prefers over any guess made from their trade.
        let posts: [UUID: WorkSite]
        /// Places a trade is plied, for colonists the engine has not seated
        /// anywhere — the fallback, keyed by the work the building is for.
        let byTrade: [WorkKind: [WorkSite]]
        let sites: [WorkSite]       // active scaffolding
        let heart: LocalPoint
        /// A paved plaza the player laid out, if any — the midday crowd
        /// gathers there instead of the bare heart, so the layout you paint
        /// is the square you see people fill.
        let plaza: LocalPoint?
        /// Parties currently out, and where the places they went are, so a
        /// colonist on the road can be drawn on their actual road.
        let expeditions: [POIExpedition]
        let poiPositions: [Int: LocalPoint]
        /// `world.tick` plus the fraction of the current tick already elapsed.
        /// A tick is a real minute; without the fraction a walking party would
        /// cross the valley in half a dozen jumps.
        let continuousTick: Double

        /// The same instant on the **action grid** — `WorldClock.absoluteStep`
        /// with the fraction kept. Everything a person physically does is
        /// measured in steps now (`WalkPace`), so this is what a haul, an
        /// errand and a march are read against. One vocabulary, one answer.
        var continuousStep: Double {
            continuousTick * Double(WorldClock.actionStepsPerTick)
        }
        /// The fight going on right now, if one is. Everyone in its line is
        /// pulled out of their day and sent to it.
        let battle: (log: BattleLog, progress: Double)?
        /// …and the fight itself, when it is one that is actually happening.
        /// A live siege owns its fighters' positions, so a colonist in the line
        /// is drawn where the *simulation* has walked them rather than where a
        /// replay would have staged them.
        let siege: Siege?
        /// Where each household's beds are: dwelling id → the spots inside it
        /// that its residents sleep at. Built from the same room plan the
        /// interiors are drawn from, so a colonist asleep is asleep in a bed
        /// that is on the screen.
        let bedsByHome: [UUID: [LocalPoint]]
        /// One bed per colonist, taken in roster order.
        let beds: [UUID: LocalPoint]

        /// Who is on what, out of `Settlement.conveyances` — pawn id → the
        /// thing they are riding or driving this tick.
        ///
        /// The simulation's answer, not the canvas's guess:
        /// `StableEngine.assignRiders` decides, and this only reads it. A
        /// renderer that picked its own riders would be presentation writing
        /// the world with extra steps.
        let ridden: [UUID: Conveyance]

        /// The ground the town stands on, and the ways already worn into it —
        /// what a walk has to go round, and what it would rather go along.
        /// Read straight off the settlement so a colonist crossing town walks
        /// the same street `PathEngine` wore (`WalkRoutes`).
        let colony: ColonyMap?
        let worn: [TileCoord: Double]
        /// What the ground says is under water. A walk goes round it —
        /// `SettlementRoute.acrossWater` — so the town on a coast keeps to its
        /// own bank instead of strolling out to sea.
        let water: ((LocalPoint) -> PathEngine.WaterDepth)?

        init(settlement: Settlement, registry: GameDataRegistry, continuousTick: Double = 0,
             replay: SettlementBattle.Replay? = nil,
             /// The age the town is in, so a room is furnished for *now*
             /// (`FittingDefinition`). Defaults to the first age, which is what
             /// a settlement with no world around it — a preview, a test — is.
             era: Era = .earlySettlement) {
            self.colony = settlement.colony
            self.worn = settlement.paths.lookup()
            self.water = PathEngine.waterDepth(settlement)
            let layout = SettlementRenderer.normalizedLayout(settlement: settlement, registry: registry)
            self.layout = layout
            var homes: [LocalPoint] = []
            var posts: [UUID: WorkSite] = [:]
            var byTrade: [WorkKind: [WorkSite]] = [:]
            var sites: [WorkSite] = []
            var bedsByHome: [UUID: [LocalPoint]] = [:]
            for building in layout {
                if building.underConstruction {
                    sites.append(WorkSite(building, era: era, registry: registry))
                    continue
                }
                let site = WorkSite(building, era: era, registry: registry)
                let def = registry.building(building.definitionID)
                if (def?.housing ?? 0) > 0 {
                    homes.append(building.center)
                    // Where this household actually sleeps: the beds in the
                    // room, from the same plan the interior is drawn from.
                    if let placementID = building.placementID {
                        // As many beds as this dwelling actually sleeps —
                        // `maxPerDwelling` is a ceiling on absurdity, not a
                        // room plan, and a tenement would have laid out two
                        // hundred mattresses in one hut.
                        bedsByHome[placementID] = SettlementInterior
                            .bedSlots(seed: building.seed, sleepers: def?.sleepers ?? 4)
                            .map(site.place)
                    }
                }
                // Everyone the engine posted here stands here.
                for pawnID in building.assignedPawnIDs { posts[pawnID] = site }
                if let def, def.workers > 0 {
                    let kind = ColonyBuilder.workKind(for: def)
                    if kind != .idle { byTrade[kind, default: []].append(site) }
                }
            }
            self.homes = homes
            self.posts = posts
            var ridden: [UUID: Conveyance] = [:]
            for thing in settlement.conveyances {
                if let rider = thing.riderID { ridden[rider] = thing }
            }
            self.ridden = ridden
            self.byTrade = byTrade
            self.sites = sites
            self.heart = SettlementRenderer.colonyHeart
            if let colony = settlement.colony,
               let plazaTile = colony.zones.first(where: { $0.kind == .plaza }) {
                self.plaza = SettlementRenderer.canvasPoint(for: plazaTile.coord, in: colony)
            } else {
                self.plaza = nil
            }
            self.expeditions = settlement.expeditions
            self.continuousTick = continuousTick
            // The same question the canvas asks, so the line the colonists run
            // to is the line the raiders are drawn breaking on — including
            // when the player is watching a replay rather than the live fight.
            self.battle = SettlementBattle.live(
                settlement, continuousTick: continuousTick,
                secondsPerTick: registry.config.realSecondsPerTick, replay: replay)
            self.siege = settlement.siege
            self.bedsByHome = bedsByHome
            // A bed each, taken in the settlement's own roster order, so two
            // people who share a house do not share a mattress.
            var beds: [UUID: LocalPoint] = [:]
            var takenPerHome: [UUID: Int] = [:]
            for pawn in settlement.pawns {
                guard let homeID = pawn.homeID, let places = bedsByHome[homeID],
                      !places.isEmpty else { continue }
                let index = takenPerHome[homeID, default: 0]
                beds[pawn.id] = places[index % places.count]
                takenPerHome[homeID] = index + 1
            }
            self.beds = beds
            var positions: [Int: LocalPoint] = [:]
            for poi in settlement.localMap?.pois ?? [] {
                positions[poi.id] = poi.position
            }
            self.poiPositions = positions
        }

        /// Where the village gathers at midday.
        var green: LocalPoint { plaza ?? heart }

        /// The party a colonist is out with, and where it went.
        func journey(for pawn: Pawn) -> (expedition: POIExpedition, destination: LocalPoint)? {
            guard let id = pawn.expeditionID,
                  let expedition = expeditions.first(where: { $0.id == id }),
                  let destination = poiPositions[expedition.poiID] else { return nil }
            return (expedition, destination)
        }
    }

    // MARK: - The day

    /// One waypoint of the daily round: where to be from `at` (0…1 of the day).
    private struct Waypoint {
        let at: Double
        let place: LocalPoint
        let doing: Activity
    }

    /// A real thing of the kind this trade works — a tree for the axe, a block
    /// for the pick, a beast for the bow.
    ///
    /// Between the job board's postings there is a gap, and a colonist standing
    /// in that gap used to be drawn on the deposit glyph. A logger between two
    /// trees should be *at a tree*.
    private static func realThing(
        for pawn: Pawn, map: LocalMap, seed: UInt64
    ) -> LocalPoint? {
        func pick<T>(_ items: [T], _ position: (T) -> LocalPoint) -> LocalPoint? {
            let seen = items.filter { map.isExplored(position($0)) }
            let field = seen.isEmpty ? items : seen
            guard !field.isEmpty else { return nil }
            return position(field[Int(seed % UInt64(field.count))])
        }
        switch pawn.assignedWork {
        case .logging:
            return pick(map.trees.filter { $0.isMature }, \.position)
        case .mining:
            // The face of the massif is where the pick goes, not its middle.
            if let face = pick(map.stone.faces(), { StoneField.centre(of: $0) }) { return face }
            return pick(map.rocks, \.position)
        case .hunting:
            return pick(map.wildlife.animals.filter { !$0.isPredator }, \.position)
        default:
            return nil
        }
    }

    /// Where a colonist is (and what they're doing) at `time`.
    ///
    /// A fight outranks everything. While one is running, anyone the engine
    /// mustered into the line stops living their day and runs to their post —
    /// from wherever they happened to be, which is why the farmer arrives from
    /// the field and the smith from the bench. This is the whole of "the
    /// garrison converges": the colonist is not drawn a second time as a
    /// combat marker, they simply go where the fighting is.
    static func pose(for pawn: Pawn, map: LocalMap, scene: Scene,
                     time: Double, ticksPerYear: Int) -> Pose {
        // Somebody carrying a load, or walking out to fetch one, is where the
        // engine has walked them to. This is the one case where a colonist's
        // position is *simulation* rather than a function of the clock: a load
        // has to be picked up somewhere and put down somewhere else, and both
        // ends are real. Hauling outranks the day and yields only to a fight.
        if let haul = pawn.haulWalk, scene.battle == nil {
            // Asked with a *fractional* action step, the same as an errand and
            // a party on the road. Reading the walk's endpoint once a tick is
            // what made the village look dead: a tick is two real minutes, so a
            // hauler stood perfectly still — legs swinging — and then jumped a
            // stride. Interpolating fixed the jumping; putting the walk itself
            // on the step grid (`WalkPace`) is what fixed the standing.
            let at = haul.position(at: scene.continuousStep)
            // They face the way the walk is going, so somebody rounding a barn
            // turns with the corner rather than staring at the store through it.
            let ahead = haul.heading(at: scene.continuousStep)
            return Pose(position: at,
                        activity: pawn.carrying == nil
                            ? .walking
                            : (scene.ridden[pawn.id] == nil ? .hauling : .riding),
                        stride: 1,
                        facing: facing(from: .init(x: 0, y: 0), to: ahead))
        }
        let base = dailyPose(for: pawn, map: map, scene: scene,
                             time: time, ticksPerYear: ticksPerYear)
        // A fight that is happening knows where this colonist is standing: the
        // Core walked them there, one action step at a time. Nothing is
        // interpolated and nothing is guessed.
        if let siege = scene.siege,
           let there = SettlementBattle.post(
               for: pawn.id, siege: siege,
               within: SettlementBattle.withinStep(of: siege,
                                                   continuousTick: scene.continuousTick)) {
            let moving = SiegeField.distance(there.position, base.position) > SiegeEngine.pace
            return Pose(position: there.position, activity: .fighting,
                        stride: moving ? 1 : 0.3, facing: there.facing)
        }
        guard let battle = scene.battle,
              let post = SettlementBattle.station(
                for: pawn.id, log: battle.log, progress: battle.progress,
                from: base.position) else { return base }
        // Running out, they face the line; standing in it, they face the enemy.
        let field = SettlementBattle.ground(battle.log)
        return Pose(position: post.position, activity: .fighting,
                    stride: post.arrived ? 0.3 : 1,
                    facing: post.arrived ? field.axisX
                                         : facing(from: base.position, to: post.position))
    }

    /// Where a colonist would be if nothing were happening — the ordinary day.
    private static func dailyPose(for pawn: Pawn, map: LocalMap, scene: Scene,
                                  time: Double, ticksPerYear: Int) -> Pose {
        let seed = hash(pawn.id)
        // Someone out at the ruins is not living the village day at all. The
        // road outranks the schedule.
        if let journey = scene.journey(for: pawn) {
            return travelPose(journey: journey, scene: scene, seed: seed, time: time)
        }
        // …and neither is somebody who has left their work because they are
        // hungry or cold. The Core owns this walk (`ErrandEngine`): where they
        // set off from, where they are going and when they get there are all
        // simulation, and this reads them. It is the same contract as hauling
        // and the same one as a siege — the canvas never invents a position it
        // could ask for.
        if let errand = pawn.errand {
            let at = errand.position(at: scene.continuousStep)
            return Pose(position: at, activity: .walking, stride: 1,
                        facing: facing(from: at, to: errand.to))
        }
        let home = home(for: pawn, scene: scene, seed: seed)

        // The clock: everyone lives the same day, offset a little so the
        // village never marches in lockstep.
        let offset = (unit(seed &>> 24) - 0.5) * 0.08
        let day = ((time / dayLength) + Double(seed % 97) / 97 * 0.02 + offset)
            .truncatingRemainder(dividingBy: 1)
        let t = day < 0 ? day + 1 : day

        let schedule = schedule(for: pawn, map: map, scene: scene,
                                home: home, seed: seed, ticksPerYear: ticksPerYear,
                                time: time)

        // Find the leg of the day that has come: the last waypoint whose hour
        // has passed. A waypoint means "from now, do this here" — so the leg a
        // colonist is living is `current`, not the one they are heading for.
        var index = schedule.count - 1
        for i in 0..<schedule.count {
            let next = schedule[(i + 1) % schedule.count]
            if t >= schedule[i].at, i + 1 == schedule.count || t < next.at {
                index = i
                break
            }
        }
        let current = schedule[index]
        let previous = schedule[(index + schedule.count - 1) % schedule.count]
        let nextAt = schedule[(index + 1) % schedule.count].at

        // **Travel takes however long the walk is. Always.**
        //
        // The cap used to be `leg * 0.8`, and that is what made colonists break
        // into a trot between things: past that point the same ground was
        // covered in less time, so the pace rose without limit and a walk that
        // did not fit its leg became a sprint. The floor is still here — a hop
        // of nothing has to take *some* time or a figure teleports a foot — but
        // there is no ceiling, because a ceiling on the time is a licence to
        // break the pace, and one pace for everybody is the whole point
        // (`WalkPace`, rule 34).
        //
        // Nothing is left walking all day, either: the schedule no longer asks
        // for trips a walk cannot make (see the midday break in `schedule`), so
        // the case the cap was defending against does not arise.
        let legStart = current.at
        let legEnd = nextAt <= legStart ? nextAt + 1 : nextAt
        // **The street, not the ruler.** A leg worth routing is walked along
        // the same way `PathEngine` wears its track — round the lots rather
        // than over them — so the person and the path on the ground agree. A
        // short hop has no route and keeps the straight line it always had.
        let street = WalkRoutes.shared.route(
            from: previous.place, to: current.place,
            colony: scene.colony, worn: scene.worn, water: scene.water)
        // Time enough for the walk they are *actually* making: going round a
        // works is further than going through it, and a pace that ignored that
        // would have people breaking into a trot at every corner (rule 34).
        let span = street.map { WalkAlong.length($0) }
            ?? distance(previous.place, current.place)
        let walk = span / walkSpeed
        let travelSlice = min(max(0.004, walk), legEnd - legStart)
        let progress = t - legStart
        if previous.place != current.place, progress < travelSlice {
            let u = smoothstep(progress / travelSlice)
            // A touch of path wobble so walkers don't ride rails. Gentler on a
            // routed street: the way is a tile wide and a walker who wanders
            // off it is walking through the wall it goes round.
            let wobble = sin(u * .pi * 3 + unit(seed) * 6) * (street == nil ? 0.006 : 0.003)
            if let street {
                let step = WalkAlong.point(street, at: u)
                return Pose(position: clampPoint(LocalPoint(x: step.at.x + wobble,
                                                            y: step.at.y + wobble * 0.6)),
                            activity: .walking, stride: 1,
                            facing: facing(from: step.at, to: step.heading))
            }
            let x = previous.place.x + (current.place.x - previous.place.x) * u
            let y = previous.place.y + (current.place.y - previous.place.y) * u
            return Pose(position: clampPoint(LocalPoint(x: x + wobble, y: y + wobble * 0.6)),
                        activity: .walking, stride: 1,
                        facing: facing(from: previous.place, to: current.place))
        }

        // Arrived: hold with a personal drift.
        let drift = drift(seed: seed, time: time,
                          amplitude: driftAmplitude(for: current.doing))
        let p = clampPoint(LocalPoint(x: current.place.x + drift.x, y: current.place.y + drift.y))
        let stride: Double = current.doing == .working ? 0.35 : (current.doing == .playing ? 0.8 : 0)
        return Pose(position: p, activity: current.doing, stride: stride)
    }

    /// A colonist out with a party: walking the road to a landmark, working it,
    /// or carrying the haul home.
    ///
    /// The line they walk is the settlement heart to the place itself, so what
    /// the player sees on the canvas is literally the journey the simulation is
    /// running. Party members fan out a little around that line and around the
    /// site — a crew, not a conga.
    private static func travelPose(
        journey: (expedition: POIExpedition, destination: LocalPoint),
        scene: Scene, seed: UInt64, time: Double
    ) -> Pose {
        let expedition = journey.expedition
        let target = journey.destination
        let gate = scene.heart
        // The same grid the simulation runs on, asked with a fraction so the
        // last gap between two steps is smooth. One vocabulary, one answer.
        let step = scene.continuousStep
        let progress = expedition.phaseProgress(atStep: step)
        // A personal offset, so three people on one road read as three people.
        let spread = 0.014
        let lane = (unit(seed &>> 11) - 0.5) * spread
        let laneCross = (unit(seed &>> 19) - 0.5) * spread

        switch expedition.phase(atStep: step) {
        case .outbound, .returning:
            let outbound = expedition.phase(atStep: step) == .outbound
            // **The way they actually walked.** A party whose straight line
            // crossed deep water bends through a ford, and the Core settled
            // where that is when they set out (`POIExpedition.via`) — so this
            // draws the journey the colony is paying for rather than a second
            // guess at it. Before this, expeditions walked over the river.
            let legs: [LocalPoint] = outbound
                ? [gate] + (expedition.via.map { [$0] } ?? []) + [target]
                : [target] + (expedition.via.map { [$0] } ?? []) + [gate]
            let (from, to, legProgress) = leg(of: legs, at: progress)
            let u = smoothstep(legProgress)
            // A gentle bow off the straight line, so the road looks walked
            // rather than ruled.
            let bow = sin(u * .pi) * 0.02
            let x = from.x + (to.x - from.x) * u + lane + bow * (to.y - from.y)
            let y = from.y + (to.y - from.y) * u + laneCross - bow * (to.x - from.x)
            return Pose(position: clampPoint(LocalPoint(x: x, y: y)),
                        activity: .travelling, stride: 1,
                        facing: facing(from: from, to: to))
        case .working:
            let drift = drift(seed: seed, time: time, amplitude: 0.012)
            return Pose(position: clampPoint(LocalPoint(x: target.x + lane + drift.x,
                                                        y: target.y + laneCross + drift.y)),
                        activity: .expedition, stride: 0.45)
        case nil:
            // Home, but the tick that clears the party has not run yet.
            return Pose(position: clampPoint(LocalPoint(x: gate.x + lane, y: gate.y + laneCross)),
                        activity: .travelling, stride: 0.2)
        }
    }

    /// Which leg of a walk the party is on, and how far along it — measured by
    /// **length**, so a short dog-leg to a ford does not take as long as the
    /// long haul out to the ruins.
    static func leg(of points: [LocalPoint], at progress: Double)
        -> (from: LocalPoint, to: LocalPoint, progress: Double) {
        guard points.count > 2 else {
            return (points.first ?? LocalPoint(x: 0.5, y: 0.5),
                    points.last ?? LocalPoint(x: 0.5, y: 0.5), progress)
        }
        var lengths: [Double] = []
        for i in 1..<points.count {
            let dx = points[i].x - points[i - 1].x, dy = points[i].y - points[i - 1].y
            lengths.append((dx * dx + dy * dy).squareRoot())
        }
        let total = max(1e-9, lengths.reduce(0, +))
        var walked = progress * total
        for (i, length) in lengths.enumerated() {
            if walked <= length || i == lengths.count - 1 {
                return (points[i], points[i + 1], min(1, max(0, walked / max(1e-9, length))))
            }
            walked -= length
        }
        return (points[0], points[1], progress)
    }

    /// The shape of one day, as fractions of it.
    ///
    /// A colony is not a factory floor. People rise with the light, break at
    /// midday, and stop when the light goes — so the working day is long in
    /// summer, short in winter, and the night takes back whatever the day gives
    /// up. (Before this, everyone worked a flat fifteen hours and slept three
    /// and a half, all year round.)
    struct DayShape: Equatable {
        let wake: Double         // out of bed, still indoors
        let workStart: Double
        let middayStart: Double  // the gathering on the green
        let middayEnd: Double
        let workEnd: Double
        let bed: Double

        /// Hours actually spent at the workplace.
        var workingHours: Double {
            ((middayStart - workStart) + (workEnd - middayEnd)) * 24
        }
        /// Hours asleep — the night wraps past midnight, hence the two pieces.
        var sleepingHours: Double { ((1 - bed) + wake) * 24 }
    }

    /// How much daylight a season lends the working day, as a fraction of the
    /// day added to *each* end. Spring and autumn are the mean.
    static func daylight(_ season: Season) -> Double {
        switch season {
        case .summer: return 0.06
        case .spring, .autumn: return 0
        case .winter: return -0.07
        }
    }

    /// The day's shape in a given season — roughly 10 working hours and 8 of
    /// sleep at the equinox, stretching to 13 and 6 at midsummer and closing to
    /// 7 and 11 in deep winter.
    static func dayShape(_ season: Season) -> DayShape {
        let light = daylight(season)
        return DayShape(
            wake: 0.22 - light,
            workStart: 0.28 - light,
            middayStart: 0.48,
            middayEnd: 0.58,
            workEnd: 0.80 + light,
            // The night closes in faster than the morning opens, so bed moves
            // only half as far as the working day's ends.
            bed: 0.88 + light * 0.5)
    }

    /// The colonist's daily round.
    private static func schedule(
        for pawn: Pawn, map: LocalMap, scene: Scene,
        home: LocalPoint, seed: UInt64, ticksPerYear: Int, time: Double
    ) -> [Waypoint] {
        // The unwell keep to their bed.
        if pawn.isBroken || pawn.health < 35 {
            return [Waypoint(at: 0, place: home, doing: .resting)]
        }
        // The same season the canvas is painting — derived, never stored.
        let season = Season(tick: Int(scene.continuousTick), ticksPerYear: ticksPerYear)
        let shape = dayShape(season)

        // Children play on the green while the adults work, and keep longer
        // nights than their parents.
        if pawn.age < Pawn.adultAgeYears * ticksPerYear {
            let green = jitter(scene.green, seed: seed, radius: 0.05)
            return [
                Waypoint(at: 0.0, place: home, doing: .sleeping),
                Waypoint(at: shape.wake + 0.04, place: green, doing: .playing),
                Waypoint(at: shape.middayEnd,
                         place: jitter(scene.green, seed: seed &>> 5, radius: 0.06),
                         doing: .playing),
                Waypoint(at: shape.workEnd - 0.02, place: home, doing: .atHome),
                Waypoint(at: shape.bed - 0.06, place: home, doing: .sleeping),
            ]
        }

        let work = workplace(for: pawn, map: map, scene: scene, seed: seed, time: time)
        let social = jitter(scene.green, seed: seed &>> 9, radius: 0.045)
        // **Whether they come in for the midday at all.**
        //
        // Keks, on the gait: *"nyní jak chodí tak někdy rychle popoběhnou,
        // hlavně mezi věcmi."* That is this waypoint, and the cause is the same
        // shape as rule 34 in a different place — the day used to cap travel at
        // most of the leg, so a colonist whose field was across the valley
        // covered the same ground in a fraction of the time and *sprinted*.
        // Everybody kept the same pace right up until the schedule asked
        // somebody for more than a pace could give.
        //
        // Capping the time was the wrong end of it. A person who cannot get to
        // the green and back inside the midday break does not run there — they
        // eat where they are working, which is what a farmer on the far side of
        // a valley has always actually done. So the trip is dropped instead of
        // being hurried, and the pace holds for everyone.
        //
        // It fixes the crowding too, and that is not a coincidence: the green
        // was packed at midday because *the whole colony* was dragged onto it
        // however far away they were.
        // Only the walk *in* has to fit the break — the walk back out is made
        // against the long afternoon leg. But a trip that eats the whole break
        // is not a break, so half of it has to be left to stand about in.
        let midday = shape.middayEnd - shape.middayStart
        let comesIn = distance(work, social) / walkSpeed < midday * 0.5
        // **The threshold.** When the work is indoors, the last of the walk in
        // and the first of the walk out are made at the door, so a colonist
        // enters the way the building says you enter it. Outdoors this is nil
        // and the legs are the straight lines they always were — a field has no
        // door and putting one in front of it would be worse than the bug.
        let door = workEntrance(for: pawn, map: map, scene: scene)
        // How much of the day the doorstep leg takes. Small: this is the last
        // few steps of a walk, not a stop.
        let step = 0.012

        var day: [Waypoint] = []
        // Written out step by step rather than as one expression: the whole day
        // as a single chain of `+` was more than the type-checker would take.
        func go(_ at: Double, _ place: LocalPoint, _ doing: Activity) {
            day.append(Waypoint(at: at, place: place, doing: doing))
        }
        /// The last few steps into a building, taken at its door.
        func arrive(_ at: Double) {
            guard let door else { return }
            day.append(Waypoint(at: at - step, place: door, doing: .walking))
        }
        /// …and the first few steps out of it.
        func leave(_ at: Double) {
            guard let door else { return }
            day.append(Waypoint(at: at + step, place: door, doing: .walking))
        }

        go(0.0, home, .sleeping)
        go(shape.wake, home, .atHome)
        arrive(shape.workStart)
        go(shape.workStart, work, .working)
        if comesIn {
            leave(shape.middayStart)
            go(shape.middayStart, social, .socializing)
            arrive(shape.middayEnd)
        } else {
            // A break taken where the work is: they stop, they eat, they are
            // not drawn crossing the map twice for it.
            go(shape.middayStart, jitter(work, seed: seed &>> 13, radius: 0.02),
               .socializing)
        }
        go(shape.middayEnd, work, .working)
        leave(shape.workEnd)
        go(shape.workEnd, home, .atHome)
        go(shape.bed, home, .sleeping)
        return day
    }

    /// The building a colonist is posted to, by id — nil when their work is
    /// out of doors. What `serves_buildings` is matched against.
    static func workBuilding(for pawn: Pawn, scene: Scene) -> String? {
        scene.posts[pawn.id]?.definitionID
    }

    /// **The door of the building this colonist works in**, or nil when their
    /// work has no walls around it.
    ///
    /// A field, a wood, a quarry face and a scaffold have no way in — you are
    /// either standing on the work or you are not. A workshop does, and a
    /// colonist who arrives at the anvil without having passed the door reads
    /// as walking through the wall, which is what they have been doing.
    ///
    /// Deliberately answers for the **posted** case only, and in the same order
    /// `workplace` does: a colonist the engine has sent to a named job is at
    /// that job, outdoors, and gets no door.
    static func workEntrance(for pawn: Pawn, map: LocalMap, scene: Scene) -> LocalPoint? {
        guard pawn.currentJob == nil else { return nil }
        guard realThing(for: pawn, map: map, seed: hash(pawn.id)) == nil else { return nil }
        guard pawn.assignedWork.harvestedDeposits.isEmpty else { return nil }
        return scene.posts[pawn.id]?.entrance
    }

    /// The spot a colonist's trade is actually plied at.
    static func workplace(for pawn: Pawn, map: LocalMap, scene: Scene,
                          seed: UInt64, time: Double = 0) -> LocalPoint {
        // **The job the engine actually gave them, first**: *this* tree, *this*
        // outcrop, this scaffold.
        //
        // This used to run third, after a check against the deposit nodes — so
        // a logger the `JobBoard` had sent to a named tree was drawn standing
        // on the abstract "forest" blob instead, and the whole entity layer was
        // invisible in the one place it should have been most obvious. The
        // comment below it already claimed the job outranked everything; the
        // code above it quietly won.
        if let job = pawn.currentJob {
            return jitter(job.position, seed: seed, radius: 0.012)
        }
        // Otherwise: something real of the right kind, and only then the ground
        // it grows on. A wood is trees; a massif is blocks. Sending somebody to
        // the *node* is sending them to a number.
        if let thing = realThing(for: pawn, map: map, seed: seed) { return thing }
        let worked = Set(pawn.assignedWork.harvestedDeposits)
        if !worked.isEmpty {
            let matching = map.nodes.filter {
                worked.contains($0.kind) && map.isExplored($0.position)
                    && !FloraEngine.isEntityBacked($0.kind, in: map)
            }
            if !matching.isEmpty {
                return matching[Int(seed % UInt64(matching.count))].position
            }
            let any = map.nodes.filter {
                worked.contains($0.kind) && !FloraEngine.isEntityBacked($0.kind, in: map)
            }
            if !any.isEmpty { return any[Int(seed % UInt64(any.count))].position }
        }

        // The post the engine actually gave them. `LaborEngine.staffBuildings`
        // keeps this roster in step with each colonist's trade, so a smith on
        // the workshop's books is drawn standing in the workshop — the canvas
        // is showing the simulation's own answer, not guessing one.
        if let post = scene.posts[pawn.id] {
            // Their own seat if the roster gave them one, else somewhere on the lot.
            return post.byPawn[pawn.id] ?? spot(in: post, seed: seed)
        }

        switch pawn.assignedWork {
        case .hunting:
            // Hunters trail the same herd the canvas draws grazing.
            let herd = SettlementWildlife.herdCenter(map: map, time: time)
            return jitter(herd, seed: seed, radius: 0.035)
        case .building:
            if !scene.sites.isEmpty {
                return spot(in: scene.sites[Int(seed % UInt64(scene.sites.count))], seed: seed)
            }
            return trade(.mining, scene: scene, seed: seed)
                ?? jitter(scene.heart, seed: seed, radius: 0.05)
        case .priest:
            // No building produces priesthood, so the priest keeps the civic
            // house — the library or hall the colony gathers its learning in.
            return trade(.research, scene: scene, seed: seed) ?? scene.heart
        case .healing:
            // Unposted — no infirmary stands yet, so the healer does the rounds
            // of the houses.
            if !scene.homes.isEmpty {
                return scene.homes[Int(seed % UInt64(scene.homes.count))]
            }
            return jitter(scene.heart, seed: seed, radius: 0.04)
        case .scouting:
            // Scouts patrol the fringe, and the patrol itself slowly turns.
            let angle = unit(seed) * 2 * .pi
            return clampPoint(LocalPoint(x: 0.5 + cos(angle) * 0.30,
                                         y: 0.52 + sin(angle) * 0.26))
        default:
            // Any building this colony keeps for the trade, even if the engine
            // has not seated this particular colonist at it.
            return trade(pawn.assignedWork, scene: scene, seed: seed)
                ?? jitter(scene.heart, seed: seed, radius: 0.07)
        }
    }

    /// A spot inside some building this colony keeps for a given trade.
    private static func trade(_ kind: WorkKind, scene: Scene, seed: UInt64) -> LocalPoint? {
        guard let sites = scene.byTrade[kind], !sites.isEmpty else { return nil }
        return spot(in: sites[Int(seed % UInt64(sites.count))], seed: seed)
    }

    /// The house a colonist calls home.
    ///
    /// Their *own* house, where the engine has given them one: a colonist holds
    /// a dwelling now (`Pawn.homeID`) and sleeps in a bed inside it. Picking a
    /// house out of a list by hashing the colonist is what put a dozen people
    /// on one doorstep while three huts stood empty beside them — the same
    /// mistake, in the same shape, as seating workers by hash.
    static func home(for pawn: Pawn, scene: Scene, seed: UInt64) -> LocalPoint {
        if let homeID = pawn.homeID, let bed = scene.beds[homeID] {
            return bed
        }
        if !scene.homes.isEmpty {
            let base = scene.homes[Int(seed % UInt64(scene.homes.count))]
            return jitter(base, seed: seed &>> 3, radius: 0.012)
        }
        let idx = Double(seed % 12)
        let angle = idx / 12 * 2 * .pi
        let radius = 0.1 + unit(seed &>> 4) * 0.06
        return clampPoint(LocalPoint(x: scene.heart.x + cos(angle) * radius,
                                     y: scene.heart.y + sin(angle) * radius))
    }

    /// The inspector's "right now" line.
    ///
    /// **Reads the job before the trade.** The line used to be a function of
    /// `(activity, assignedWork)` alone, while `workplace` had already been
    /// taught to prefer `pawn.currentJob` — so the two disagreed about the same
    /// colonist. A farmer with no plot to work was *drawn inside the farm
    /// building* and *described as out in the field*, which is precisely the
    /// "je uvnitř, píše to venku" Keks reported. A job says what is being done
    /// and where; when there is one, it is the answer, and the figure standing
    /// there is standing on it.
    /// - Parameter housed: whether the colony actually keeps a building for
    ///   this trade. **The card used to assert one either way**: a craftsman in
    ///   a colony with no workshop read "Vyrábí u ponku" and a scholar with no
    ///   library read "Bádá nad svitky", while the figure stood in a field near
    ///   the middle of town, because that is where `workplace(for:)` puts a
    ///   worker with nowhere to go. Keks, with two screenshots: *"lidé vyrábí
    ///   tak, že mávají motykou … bádání nad svitky taky."* The trade was true
    ///   and the place was a fiction, and a card that names a place the colony
    ///   has not built is worse than one that says nothing.
    static func activityLabel(_ activity: Activity, work: WorkKind, cs: Bool,
                              job: Job? = nil, crop: Crop? = nil,
                              housed: Bool = true) -> String {
        if activity == .working, let job {
            return jobLabel(job, crop: crop, cs: cs)
        }
        if activity == .working, !housed, let open = openAirLabel(work, cs: cs) {
            return open
        }
        switch activity {
        case .sleeping: return cs ? "Spí doma" : "Asleep at home"
        case .atHome: return cs ? "Doma u ohně" : "At home by the fire"
        case .walking: return cs ? "Na cestě" : "On the way"
        case .socializing: return cs ? "Na návsi mezi lidmi" : "On the green with the others"
        case .playing: return cs ? "Hraje si" : "Playing"
        case .resting: return cs ? "Stůně doma" : "Laid up at home"
        case .hauling: return cs ? "Nese náklad do skladu" : "Carrying a load to the store"
        case .riding: return cs ? "Veze náklad do skladu" : "Driving a load to the store"
        case .fighting: return cs ? "V linii" : "In the line"
        case .travelling: return cs ? "Na cestě mimo osadu" : "On the road, away from the settlement"
        case .expedition: return cs ? "Pracuje na výpravě" : "Working the site"
        case .working:
            switch work {
            case .farming: return cs ? "Pracuje na poli" : "Working the field"
            case .logging: return cs ? "Káce v lese" : "Felling timber"
            case .mining: return cs ? "Láme kámen v lomu" : "Breaking stone at the quarry"
            case .foraging: return cs ? "Sbírá byliny" : "Gathering herbs"
            case .hunting: return cs ? "Na lovu na kraji divočiny" : "Hunting the wild fringe"
            case .research: return cs ? "Bádá nad svitky" : "Poring over scrolls"
            case .trade: return cs ? "Obchoduje u sýpky" : "Trading by the granary"
            case .healing: return cs ? "Obchází nemocné" : "Doing the healer's rounds"
            case .building: return cs ? "Staví na lešení" : "Up on the scaffolding"
            case .scouting: return cs ? "Na obchůzce po hranici" : "Walking the bounds"
            case .crafting: return cs ? "Vyrábí u ponku" : "At the bench"
            case .cooking: return cs ? "Vaří v kuchyni" : "Cooking in the kitchen"
            case .priest: return cs ? "Slouží v chrámu" : "Serving at the temple"
            case .garrison: return cs ? "Drží hlídku" : "Standing watch"
            case .idle: return cs ? "Postává na návsi" : "Idling on the green"
            }
        }
    }

    /// **What a trade looks like with nowhere to do it.**
    ///
    /// Only for the trades that need a roof and a bench: a logger and a farmer
    /// work out of doors by nature and their ordinary line is already true.
    /// Nil means "the usual line is honest", which is most of them.
    static func openAirLabel(_ work: WorkKind, cs: Bool) -> String? {
        switch work {
        case .crafting:
            return cs ? "Kutí pod širým nebem — není ponk"
                      : "Working in the open — there is no bench"
        case .research:
            return cs ? "Přemítá — nejsou svitky ani stůl"
                      : "Thinking it over — no scrolls, no desk"
        case .cooking:
            return cs ? "Vaří na ohni pod nebem" : "Cooking over an open fire"
        case .healing:
            return cs ? "Obchází nemocné po chalupách"
                      : "Doing the rounds of the houses"
        case .priest:
            return cs ? "Modlí se pod nebem — chrám nestojí"
                      : "At prayer in the open — no temple stands"
        case .trade:
            return cs ? "Smlouvá na návsi — není tržnice"
                      : "Dealing on the green — there is no market"
        default:
            return nil
        }
    }

    /// What the engine has this colonist doing, said out loud.
    ///
    /// Every line here names a *thing* — this plot, this fire — because that is
    /// what a `Job` is. Anything vaguer belongs in `activityLabel`'s fallback,
    /// which is for colonists the board has not reached yet.
    static func jobLabel(_ job: Job, crop: Crop?, cs: Bool) -> String {
        switch job.kind {
        case .fellTree:
            return cs ? "Kácí strom" : "Felling a tree"
        case .quarryRock, .cutStone:
            return cs ? "Láme kámen ve stěně" : "Breaking stone at the face"
        case .raiseBuilding:
            return cs ? "Staví na lešení" : "Up on the scaffolding"
        case .tendDeposit:
            return cs ? "Obdělává půdu" : "Working the ground"
        case .standWatch:
            return cs ? "Drží hlídku na hradbě" : "Standing watch on the wall"
        case .stalkAnimal:
            return cs ? "Stopuje zvěř" : "Stalking game"
        case .craftItem:
            return cs ? "Vyrábí u ponku" : "At the bench"
        case .cookMeal:
            return cs ? "Vaří u ohně v kuchyni" : "At the fire in the cookhouse"
        case .workPlot:
            guard let crop else {
                return cs ? "Na poli" : "Out in the field"
            }
            let what = crop.species.displayName.resolve(cs ? .cs : .en).lowercased()
            if crop.isRipe {
                return cs ? "Sklízí \(what)" : "Reaping the \(what)"
            }
            let percent = Int((crop.growth * 100).rounded())
            return cs ? "Obdělává \(what) — \(percent) % zralé"
                      : "Tending the \(what) — \(percent)% ripe"
        }
    }

    /// A little walk-cycle phase (0…2π) for the leg swing, per colonist.
    static func gaitPhase(for pawn: Pawn, time: Double) -> Double {
        let seed = hash(pawn.id)
        let speed = 4.0 + unit(seed &>> 16) * 2.5
        return time * speed + unit(seed) * 2 * .pi
    }

    // MARK: - Small motion

    private static func driftAmplitude(for activity: Activity) -> Double {
        switch activity {
        case .sleeping, .resting: return 0.001
        case .atHome: return 0.006
        case .working: return 0.014
        case .socializing: return 0.010
        case .playing: return 0.022
        case .walking, .travelling: return 0
        case .expedition: return 0.012
        // Holding a line is not standing still — but the drift is small, or
        // the rank dissolves while it is supposed to be holding.
        case .fighting: return 0.004
        // A hauler's position is the engine's own; drifting it would take them
        // off the path they are actually walking.
        case .hauling: return 0
        case .riding: return 0
        }
    }

    private static func drift(seed: UInt64, time: Double, amplitude: Double) -> (x: Double, y: Double) {
        guard amplitude > 0 else { return (0, 0) }
        let phase = unit(seed) * 2 * .pi
        let speed = 0.25 + unit(seed &>> 8) * 0.2
        let t = time * speed + phase
        return (sin(t) * amplitude, cos(t * 0.8 + phase) * amplitude)
    }

    private static func jitter(_ point: LocalPoint, seed: UInt64, radius: Double) -> LocalPoint {
        let angle = unit(seed &* 31) * 2 * .pi
        let r = unit(seed &* 17) * radius
        return clampPoint(LocalPoint(x: point.x + cos(angle) * r,
                                     y: point.y + sin(angle) * r))
    }

    /// A stable spot inside a work building's lot for one colonist — offset by
    /// their seed so several workers spread across the floor instead of stacking
    /// on its centre. Kept just inside the footprint so nobody stands on a wall.
    private static func spot(in site: WorkSite, seed: UInt64) -> LocalPoint {
        // A station if the room has one: standing at the bench beats standing
        // somewhere on the lot, and it is the same bench the renderer drew.
        // Nudged per colonist, because this path is for people the roster did
        // *not* seat — two of them picking the same bench should still read as
        // two people at a bench rather than as one.
        if !site.stations.isEmpty {
            let station = site.stations[Int(seed % UInt64(site.stations.count))]
            return clampPoint(LocalPoint(
                x: station.x + (unit(seed &* 7) - 0.5) * site.halfW * 0.5,
                y: station.y + (unit(seed &* 13) - 0.5) * site.halfH * 0.5))
        }
        let ox = (unit(seed &* 7) - 0.5) * 1.6 * site.halfW
        let oy = (unit(seed &* 13) - 0.5) * 1.6 * site.halfH
        return clampPoint(LocalPoint(x: site.center.x + ox, y: site.center.y + oy))
    }

    // MARK: - Maths

    private static func smoothstep(_ x: Double) -> Double {
        let c = min(1, max(0, x))
        return c * c * (3 - 2 * c)
    }

    private static func clamp(_ v: Double) -> Double { min(0.98, max(0.02, v)) }

    private static func clampPoint(_ p: LocalPoint) -> LocalPoint {
        LocalPoint(x: clamp(p.x), y: clamp(p.y))
    }

    /// A stable [0,1) value from a 64-bit seed.
    private static func unit(_ seed: UInt64) -> Double {
        var h = seed &* 0x2545_F491_4F6C_DD1D
        h ^= h &>> 32
        return Double(h & 0xFFFF_FFFF) / Double(0x1_0000_0000)
    }

    static func hash(_ id: UUID) -> UInt64 {
        let b = id.uuid
        var h: UInt64 = 0xCBF2_9CE4_8422_2325
        h = (h ^ UInt64(b.0)) &* 0x0100_0000_01B3
        h = (h ^ UInt64(b.3)) &* 0x0100_0000_01B3
        h = (h ^ UInt64(b.7)) &* 0x0100_0000_01B3
        h = (h ^ UInt64(b.11)) &* 0x0100_0000_01B3
        h = (h ^ UInt64(b.15)) &* 0x0100_0000_01B3
        return h
    }
}
