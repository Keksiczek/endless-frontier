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
    }

    /// A colonist's place and doing at an instant.
    struct Pose {
        let position: LocalPoint
        let activity: Activity
        /// 0…1 walk-cycle weight — legs swing only when actually under way.
        let stride: Double
    }

    // MARK: - The stage

    /// Everything the motion needs to know about *where things are*, computed
    /// once per frame and shared with the renderer and hit-testing.
    struct Scene {
        let layout: [SettlementRenderer.NormalizedBuilding]
        let homes: [LocalPoint]
        let civic: LocalPoint?      // temple/library — scholars and priests
        let workshop: LocalPoint?
        let granary: LocalPoint?
        let sites: [LocalPoint]     // active scaffolding
        let heart: LocalPoint
        /// A paved plaza the player laid out, if any — the midday crowd
        /// gathers there instead of the bare heart, so the layout you paint
        /// is the square you see people fill.
        let plaza: LocalPoint?

        init(settlement: Settlement, registry: GameDataRegistry) {
            let layout = SettlementRenderer.normalizedLayout(settlement: settlement, registry: registry)
            self.layout = layout
            var homes: [LocalPoint] = []
            var civic: LocalPoint?
            var workshop: LocalPoint?
            var granary: LocalPoint?
            var sites: [LocalPoint] = []
            for building in layout {
                if building.underConstruction {
                    sites.append(building.center)
                    continue
                }
                switch building.glyph {
                case .house: homes.append(building.center)
                case .temple: civic = civic ?? building.center
                case .workshop, .mill, .generator: workshop = workshop ?? building.center
                case .granary: granary = granary ?? building.center
                default: break
                }
            }
            self.homes = homes
            self.civic = civic
            self.workshop = workshop
            self.granary = granary
            self.sites = sites
            self.heart = SettlementRenderer.colonyHeart
            if let colony = settlement.colony,
               let plazaTile = colony.zones.first(where: { $0.kind == .plaza }) {
                self.plaza = SettlementRenderer.canvasPoint(for: plazaTile.coord, in: colony)
            } else {
                self.plaza = nil
            }
        }

        /// Where the village gathers at midday.
        var green: LocalPoint { plaza ?? heart }
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

        // Find the current leg of the day.
        var from = schedule[schedule.count - 1]
        var to = schedule[0]
        for i in 0..<schedule.count {
            let next = schedule[(i + 1) % schedule.count]
            if t >= schedule[i].at, i + 1 == schedule.count || t < next.at {
                from = schedule[i]
                to = next
                break
            }
        }

        // Travel takes a fixed slice at the start of each leg; the rest of the
        // leg is spent *at* the destination, drifting gently.
        let legStart = from.at
        let legEnd = to.at <= legStart ? to.at + 1 : to.at
        let travelSlice = min(0.06, (legEnd - legStart) * 0.6)
        let progress = t - legStart
        if from.place != to.place, progress < travelSlice {
            let u = smoothstep(progress / travelSlice)
            let x = from.place.x + (to.place.x - from.place.x) * u
            let y = from.place.y + (to.place.y - from.place.y) * u
            // A touch of path wobble so walkers don't ride rails.
            let wobble = sin(u * .pi * 3 + unit(seed) * 6) * 0.006
            return Pose(position: clampPoint(LocalPoint(x: x + wobble, y: y + wobble * 0.6)),
                        activity: .walking, stride: 1)
        }

        // Settled at the destination: hold with a personal drift.
        let drift = drift(seed: seed, time: time,
                          amplitude: driftAmplitude(for: to.doing))
        let p = clampPoint(LocalPoint(x: to.place.x + drift.x, y: to.place.y + drift.y))
        let stride: Double = to.doing == .working ? 0.35 : (to.doing == .playing ? 0.8 : 0)
        return Pose(position: p, activity: to.doing, stride: stride)
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
        // Children play on the green while the adults work.
        if pawn.age < Pawn.adultAgeYears * ticksPerYear {
            let green = jitter(scene.green, seed: seed, radius: 0.05)
            return [
                Waypoint(at: 0.0, place: home, doing: .sleeping),
                Waypoint(at: 0.12, place: green, doing: .playing),
                Waypoint(at: 0.5, place: jitter(scene.green, seed: seed &>> 5, radius: 0.06), doing: .playing),
                Waypoint(at: 0.88, place: home, doing: .atHome),
                Waypoint(at: 0.94, place: home, doing: .sleeping),
            ]
        }

        let work = workplace(for: pawn, map: map, scene: scene, seed: seed, time: time)
        let social = jitter(scene.green, seed: seed &>> 9, radius: 0.045)
        return [
            Waypoint(at: 0.0, place: home, doing: .sleeping),
            Waypoint(at: 0.07, place: home, doing: .atHome),
            Waypoint(at: 0.11, place: work, doing: .working),
            Waypoint(at: 0.46, place: social, doing: .socializing),
            Waypoint(at: 0.56, place: work, doing: .working),
            Waypoint(at: 0.84, place: home, doing: .atHome),
            Waypoint(at: 0.93, place: home, doing: .sleeping),
        ]
    }

    /// The spot a colonist's trade is actually plied at.
    static func workplace(for pawn: Pawn, map: LocalMap, scene: Scene,
                          seed: UInt64, time: Double = 0) -> LocalPoint {
        if let deposit = pawn.assignedWork.harvestedDeposit {
            let matching = map.nodes.filter { $0.kind == deposit && map.isExplored($0.position) }
            if !matching.isEmpty {
                return matching[Int(seed % UInt64(matching.count))].position
            }
            let any = map.nodes.filter { $0.kind == deposit }
            if !any.isEmpty { return any[Int(seed % UInt64(any.count))].position }
        }
        switch pawn.assignedWork {
        case .hunting:
            // Hunters trail the same herd the canvas draws grazing.
            let herd = SettlementWildlife.herdCenter(map: map, time: time)
            return jitter(herd, seed: seed, radius: 0.035)
        case .building:
            if !scene.sites.isEmpty {
                return scene.sites[Int(seed % UInt64(scene.sites.count))]
            }
            return scene.workshop ?? scene.heart
        case .research:
            return scene.civic ?? scene.workshop ?? jitter(scene.heart, seed: seed, radius: 0.03)
        case .priest:
            return scene.civic ?? scene.heart
        case .trade:
            return scene.granary ?? scene.workshop ?? jitter(scene.heart, seed: seed, radius: 0.04)
        case .healing:
            // The healer does the rounds of the houses.
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
            return jitter(scene.heart, seed: seed, radius: 0.07)
        }
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
        case .walking: return 0
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
