import SwiftUI
import EndlessFrontierCore

/// **The moon, and what it does to a night.**
///
/// Keks, watching the valley after dark: *"noc je dost tmavá a jednotvárná,
/// možná přidat fáze měsíce."* Both halves of that are one fault. Every night
/// was exactly as dark as every other night, because the only thing deciding
/// how dark it went was how far past sunset the clock stood — so a fortnight of
/// play was a fortnight of the same night, and the only way to make it *less*
/// monotonous was to make it lighter, which would have made it less like night.
///
/// The moon fixes it in the direction that adds rather than subtracts. A full
/// moon is genuinely bright — you can walk a field by it — and a new moon is
/// black. That is a **two-and-a-half-fold** swing in how dark the valley goes,
/// on a twenty-nine-and-a-half day cycle nobody has to be told about, and it
/// arrives without a single new decision for the player to make.
///
/// There is no sky on a map drawn from above, so the moon is not *drawn*: it is
/// read off the light, and named in the status strip where the hour already is.
enum MoonPhase {

    /// A synodic month — new moon to new moon. The real number, because there
    /// is no reason to invent a worse one.
    static let synodicDays = 29.53

    /// Which drawn day this is. The day is `AgentMotion.dayLength` of real
    /// time, and the epoch is the one everything else counts from
    /// (`DayClock.epoch`), so the moon agrees with the clock and the sun.
    static func day(at time: Double) -> Double { time / AgentMotion.dayLength }

    /// Where in the cycle we are, `0…1`: 0 is new, 0.5 is full.
    static func cycle(at time: Double) -> Double {
        let turns = day(at: time) / synodicDays
        let t = turns.truncatingRemainder(dividingBy: 1)
        return t < 0 ? t + 1 : t
    }

    /// How much of the disc is lit, `0…1`. New is 0, full is 1, and the two
    /// quarters are a half apiece.
    static func illumination(at time: Double) -> Double {
        (1 - cos(cycle(at: time) * 2 * .pi)) / 2
    }

    /// The eight phases everybody can name.
    enum Phase: CaseIterable {
        case new, waxingCrescent, firstQuarter, waxingGibbous
        case full, waningGibbous, lastQuarter, waningCrescent

        /// SF Symbols carries the whole set, drawn the right way round.
        var symbol: String {
            switch self {
            case .new: return "moonphase.new.moon"
            case .waxingCrescent: return "moonphase.waxing.crescent"
            case .firstQuarter: return "moonphase.first.quarter"
            case .waxingGibbous: return "moonphase.waxing.gibbous"
            case .full: return "moonphase.full.moon"
            case .waningGibbous: return "moonphase.waning.gibbous"
            case .lastQuarter: return "moonphase.last.quarter"
            case .waningCrescent: return "moonphase.waning.crescent"
            }
        }

        var czech: String {
            switch self {
            case .new: return "Nov"
            case .waxingCrescent: return "Dorůstající srpek"
            case .firstQuarter: return "První čtvrť"
            case .waxingGibbous: return "Dorůstající měsíc"
            case .full: return "Úplněk"
            case .waningGibbous: return "Couvající měsíc"
            case .lastQuarter: return "Poslední čtvrť"
            case .waningCrescent: return "Couvající srpek"
            }
        }

        var english: String {
            switch self {
            case .new: return "New moon"
            case .waxingCrescent: return "Waxing crescent"
            case .firstQuarter: return "First quarter"
            case .waxingGibbous: return "Waxing gibbous"
            case .full: return "Full moon"
            case .waningGibbous: return "Waning gibbous"
            case .lastQuarter: return "Last quarter"
            case .waningCrescent: return "Waning crescent"
            }
        }

        func name(_ language: GameLanguage) -> String {
            language == .cs ? czech : english
        }
    }

    static func phase(at time: Double) -> Phase {
        // Eight equal arcs, each centred on its name — so "full moon" covers
        // the night either side of it, which is what anybody looking up would
        // say too.
        let eighth = ((cycle(at: time) * 8) + 0.5).truncatingRemainder(dividingBy: 8)
        switch Int(eighth) {
        case 0: return .new
        case 1: return .waxingCrescent
        case 2: return .firstQuarter
        case 3: return .waxingGibbous
        case 4: return .full
        case 5: return .waningGibbous
        case 6: return .lastQuarter
        default: return .waningCrescent
        }
    }

    /// How much light the moon is actually putting on the valley, `0…1`.
    ///
    /// Not the same as `illumination`: a gibbous moon is nearly as bright as a
    /// full one to the eye, and a thin crescent is worth almost nothing, so the
    /// light is the lit fraction bent toward its ends. The cloud comes off the
    /// same `Climate.weather` the rain does — a full moon behind a storm lights
    /// nothing, which is the darkest the valley ever gets.
    static func moonlight(at time: Double, weather: Double) -> Double {
        let lit = illumination(at: time)
        let curve = lit * lit * (3 - 2 * lit)          // smoothstep
        let cloud = min(1, max(0, -weather / 5))
        return curve * (1 - cloud * 0.85)
    }
}
