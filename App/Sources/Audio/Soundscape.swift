import Foundation
import EndlessFrontierCore

/// **What the valley sounds like right now, as numbers.**
///
/// The whole mapping from world to sound lives here, and it is a pure function
/// of facts the canvas already reads: the season, what the sky is doing, how far
/// into the night it is, how many people are awake, whether anyone is attacking.
/// Nothing in this file makes a sound — `AudioEngine` does that — which is the
/// same split that makes everything else in the app testable: the *decision* is
/// a value, the device is a thin thing at the end of it.
///
/// It is also rule 5 in the ears: sound is presentation. Nothing here can reach
/// the simulation, and nothing in the simulation knows it is being listened to.
struct Soundscape: Equatable {

    /// Gains, 0…1, one per voice.
    var wind: Double = 0
    var rain: Double = 0
    var crickets: Double = 0
    var village: Double = 0
    var fire: Double = 0

    /// Silence. What a settlement nobody is looking at sounds like.
    static let quiet = Soundscape()

    /// The facts the mix is made of — read off the same state the canvas draws.
    struct World {
        var season: Season = .summer
        /// Degrees, from `Climate.temperature(_:)`.
        var temperature: Double = 15
        /// What the sky is doing over and above the season, from
        /// `Climate.weather(_:)`. Negative is a hard, wet, cold spell.
        var weather: Double = 0
        /// How far into the night it is, 0…1 — `SettlementRenderer.nightness`.
        var night: Double = 0
        /// People in the colony, and how many of them are up.
        var population: Int = 0
        var awake: Int = 0
        /// A fight in progress drowns the village out.
        var underAttack: Bool = false
        /// Whether the colony has a fire going — a hearth, a cookhouse, a forge.
        var hearths: Int = 0
    }

    /// Above this much bad weather the sky is raining rather than merely grey.
    static let rainThreshold = 1.5
    /// A colony this size is as loud as a colony gets.
    static let loudEnoughVillage = 40.0

    static func mix(_ world: World) -> Soundscape {
        var out = Soundscape()

        // **Wind is always there and never the same.** It rises with the cold
        // and with a bad spell, because that is when the valley is loudest, and
        // winter has nothing growing to soften it.
        let cold = max(0, (12 - world.temperature) / 30)
        let spell = max(0, -world.weather) / 6
        let bare = world.season == .winter ? 0.18 : (world.season == .autumn ? 0.09 : 0)
        out.wind = clamp(0.18 + cold * 0.5 + spell * 0.5 + bare)

        // Rain, when the sky has actually turned. Colder than freezing it is
        // snow, which is quiet — the loudest sky is a warm downpour.
        if -world.weather > rainThreshold {
            let force = clamp((-world.weather - rainThreshold) / 4)
            out.rain = world.temperature <= 0 ? force * 0.15 : force
        }

        // Crickets are a summer night and nothing else. They stop when it is
        // cold, which is the thing everybody knows without being told.
        if world.temperature > 12 {
            out.crickets = clamp(world.night * (world.season == .winter ? 0 : 1)
                                 * clamp((world.temperature - 12) / 10))
        }

        // The village: how many people are up and about, against how big a
        // colony has to get before it is as loud as it will ever be. Asleep is
        // not silent — a house with twelve people in it breathes — but it is
        // most of the way there.
        let up = Double(world.awake)
        let abed = Double(max(0, world.population - world.awake))
        out.village = clamp((up + abed * 0.12) / loudEnoughVillage) * (1 - world.night * 0.35)

        // A fire is a fire whether anybody is awake, and at night it is the
        // only thing in the colony still making a noise.
        out.fire = clamp(Double(world.hearths) / 4) * (0.55 + world.night * 0.45)

        // A raid takes the village over: nobody is chatting, and what you can
        // hear is weather and people shouting, which the fight's own stings do.
        if world.underAttack {
            out.village *= 0.35
            out.crickets = 0
        }
        return out
    }

    private static func clamp(_ v: Double) -> Double { min(1, max(0, v)) }
}

/// One-off sounds: something happened, and it happened *now*.
///
/// Deliberately few. A sound for every journal line is a game that pings at you
/// forty times a minute and gets muted, which is worse than silence.
enum Sting: String, CaseIterable {
    /// A roof goes on.
    case hammer
    /// The assembly sits, a decision is waiting.
    case bell
    /// Somebody is coming, and not to trade.
    case horn
    /// A birth, an arrival, a discovery — the good news.
    case chime
    /// A death.
    case knell

    /// What a journal entry sounds like, or nothing at all.
    ///
    /// The mapping is on the *kind*, not on the text, so it keeps working as
    /// content is added — and most kinds are silent on purpose.
    static func of(_ kind: ColonyLogEntry.Kind?) -> Sting? {
        switch kind {
        case .construction: return .hammer
        case .danger: return .horn
        case .birth, .arrival, .discovery: return .chime
        case .death: return .knell
        case .faith: return .bell
        // A declaration and a peace are both worth looking up for.
        case .diplomacy: return .chime
        case .social, .work, .departure, .none: return nil
        }
    }
}
