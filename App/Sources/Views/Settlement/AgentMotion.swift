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
    static let dayLength: Double = 150

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
    }

    /// A colonist's place and doing at an instant.
    struct Pose {
        let position: LocalPoint
        let activity: Activity
        /// 0…1 walk-cycle weight — legs swing only when actually under way.
        let stride: Double
    }

    /// A building a colonist works *at*, and the ground it covers — so several
    /// workers spread across the lot instead of stacking on one point.
    struct WorkSite {
        let center: LocalPoint
        let halfW: Double
        let halfH: Double
        init(_ b: SettlementRenderer.NormalizedBuilding) {
            center = b.center
            halfW = b.footprintW / 2
            halfH = b.footprintH / 2
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

        init(settlement: Settlement, registry: GameDataRegistry, continuousTick: Double = 0) {
            let layout = SettlementRenderer.normalizedLayout(settlement: settlement, registry: registry)
            self.layout = layout
            var homes: [LocalPoint] = []
            var posts: [UUID: WorkSite] = [:]
            var byTrade: [WorkKind: [WorkSite]] = [:]
            var sites: [WorkSite] = []
            for building in layout {
                if building.underConstruction {
                    sites.append(WorkSite(building))
                    continue
                }
                let site = WorkSite(building)
                let def = registry.building(building.definitionID)
                if (def?.housing ?? 0) > 0 { homes.append(building.center) }
                // Everyone the engine posted here stands here.
                for pawnID in building.assignedPawnIDs { posts[pawnID] = site }
                if let def, def.workers > 0 {
                    let kind = ColonyBuilder.workKind(for: def)
                    if kind != .idle { byTrade[kind, default: []].append(site) }
                }
            }
            self.homes = homes
            self.posts = posts
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

    /// Where a colonist is (and what they're doing) at `time`.
    static func pose(for pawn: Pawn, map: LocalMap, scene: Scene,
                     time: Double, ticksPerYear: Int) -> Pose {
        let seed = hash(pawn.id)
        // Someone out at the ruins is not living the village day at all. The
        // road outranks the schedule.
        if let journey = scene.journey(for: pawn) {
            return travelPose(journey: journey, scene: scene, seed: seed, time: time)
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

        // Travel takes a short slice at the start of each leg — the walk *to*
        // this leg's place — and the rest of the leg is spent there, drifting
        // gently. Kept short: a colonist should be seen doing the thing, not
        // gliding towards it.
        let legStart = current.at
        let legEnd = nextAt <= legStart ? nextAt + 1 : nextAt
        let travelSlice = min(0.025, (legEnd - legStart) * 0.4)
        let progress = t - legStart
        if previous.place != current.place, progress < travelSlice {
            let u = smoothstep(progress / travelSlice)
            let x = previous.place.x + (current.place.x - previous.place.x) * u
            let y = previous.place.y + (current.place.y - previous.place.y) * u
            // A touch of path wobble so walkers don't ride rails.
            let wobble = sin(u * .pi * 3 + unit(seed) * 6) * 0.006
            return Pose(position: clampPoint(LocalPoint(x: x + wobble, y: y + wobble * 0.6)),
                        activity: .walking, stride: 1)
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
        let step = scene.continuousTick * Double(WorldClock.actionStepsPerTick)
        let progress = expedition.phaseProgress(atStep: step)
        // A personal offset, so three people on one road read as three people.
        let spread = 0.014
        let lane = (unit(seed &>> 11) - 0.5) * spread
        let laneCross = (unit(seed &>> 19) - 0.5) * spread

        switch expedition.phase(atStep: step) {
        case .outbound, .returning:
            let outbound = expedition.phase(atStep: step) == .outbound
            let from = outbound ? gate : target
            let to = outbound ? target : gate
            let u = smoothstep(progress)
            // A gentle bow off the straight line, so the road looks walked
            // rather than ruled.
            let bow = sin(u * .pi) * 0.02
            let x = from.x + (to.x - from.x) * u + lane + bow * (to.y - from.y)
            let y = from.y + (to.y - from.y) * u + laneCross - bow * (to.x - from.x)
            return Pose(position: clampPoint(LocalPoint(x: x, y: y)),
                        activity: .travelling, stride: 1)
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
        return [
            Waypoint(at: 0.0, place: home, doing: .sleeping),
            Waypoint(at: shape.wake, place: home, doing: .atHome),
            Waypoint(at: shape.workStart, place: work, doing: .working),
            Waypoint(at: shape.middayStart, place: social, doing: .socializing),
            Waypoint(at: shape.middayEnd, place: work, doing: .working),
            Waypoint(at: shape.workEnd, place: home, doing: .atHome),
            Waypoint(at: shape.bed, place: home, doing: .sleeping),
        ]
    }

    /// The spot a colonist's trade is actually plied at.
    static func workplace(for pawn: Pawn, map: LocalMap, scene: Scene,
                          seed: UInt64, time: Double = 0) -> LocalPoint {
        // Any ground this trade works — a miner belongs at the iron seam as
        // much as at the quarry, and on a map with no ore, at the quarry.
        let worked = Set(pawn.assignedWork.harvestedDeposits)
        if !worked.isEmpty {
            let matching = map.nodes.filter { worked.contains($0.kind) && map.isExplored($0.position) }
            if !matching.isEmpty {
                return matching[Int(seed % UInt64(matching.count))].position
            }
            let any = map.nodes.filter { worked.contains($0.kind) }
            if !any.isEmpty { return any[Int(seed % UInt64(any.count))].position }
        }
        // The post the engine actually gave them. `LaborEngine.staffBuildings`
        // keeps this roster in step with each colonist's trade, so a smith on
        // the workshop's books is drawn standing in the workshop — the canvas
        // is showing the simulation's own answer, not guessing one.
        if let post = scene.posts[pawn.id] { return spot(in: post, seed: seed) }

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

    /// The house a colonist calls home — stable per colonist.
    static func home(for pawn: Pawn, scene: Scene, seed: UInt64) -> LocalPoint {
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
    static func activityLabel(_ activity: Activity, work: WorkKind, cs: Bool) -> String {
        switch activity {
        case .sleeping: return cs ? "Spí doma" : "Asleep at home"
        case .atHome: return cs ? "Doma u ohně" : "At home by the fire"
        case .walking: return cs ? "Na cestě" : "On the way"
        case .socializing: return cs ? "Na návsi mezi lidmi" : "On the green with the others"
        case .playing: return cs ? "Hraje si" : "Playing"
        case .resting: return cs ? "Stůně doma" : "Laid up at home"
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
            case .priest: return cs ? "Slouží v chrámu" : "Serving at the temple"
            case .idle: return cs ? "Postává na návsi" : "Idling on the green"
            }
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
