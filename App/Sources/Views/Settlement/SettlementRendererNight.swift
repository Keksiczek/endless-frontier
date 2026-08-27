import SwiftUI
import EndlessFrontierCore

/// **Night, and what is lit in it.**
///
/// Split out of `SettlementRenderer` on 2026-08-27, when the renderer stood at
/// 2822 lines against a stated maximum of 800. The seams were the ones its own
/// `// MARK:` lines already drew; nothing here changed but the file it is in.
///
/// How dark the valley goes, the wash that makes it so, and where the lamps
/// stand — the windows, hearths and braziers `SettlementLight` then paints.
extension SettlementRenderer {
    /// How deep into night the settlement's shared day is (0 = broad day,
    /// 1 = the dead of night). Synced to `AgentMotion.dayLength`, so the world
    /// darkens exactly while the figures are in their beds — the day cycle the
    /// motion always had, finally *visible*.
    /// **Derived from when the sun is actually down** — rule 35, and the whole
    /// of what was wrong with it.
    ///
    /// Keks: *"teď všichni chodí spát, ale vypadá to stejně jako přes den."* He
    /// was right, and the arithmetic says so. `SettlementLight` sets the sun in
    /// the sky between `dawn` (0.25) and `dusk` (0.75), and the colonists' day
    /// puts them in bed from about 0.88 to about 0.22 — but this darkened only
    /// within 0.16 of midnight and reached full dark inside 0.06 of it. So from
    /// sunset at 0.75 until 0.84 the sun was down, the shadows were gone, the
    /// windows were lit, and the valley was painted **in broad daylight**. A
    /// third of the night was drawn as noon.
    ///
    /// Now there is one number for one thing: the sky is dark whenever the sun
    /// is under the horizon, ramping over `nightFall` at each end so dusk is a
    /// dusk and not a switch.
    static func nightness(time: Double) -> Double {
        let t = (time / AgentMotion.dayLength).truncatingRemainder(dividingBy: 1)
        let day = t < 0 ? t + 1 : t
        // Daylight is daylight; the ramps live at its two edges.
        guard day >= SettlementLight.dusk || day <= SettlementLight.dawn else { return 0 }
        // How long the sun has been down, and how long until it is up — the
        // **nearer** of the two is how dark it is, so both edges ramp and the
        // middle of the night is fully dark.
        let sinceDusk = (day - SettlementLight.dusk + 1).truncatingRemainder(dividingBy: 1)
        let untilDawn = (SettlementLight.dawn - day + 1).truncatingRemainder(dividingBy: 1)
        return max(0, min(1, min(sinceDusk, untilDawn) / nightFall))
    }

    /// How long dusk takes to become night, as a share of the day. About an
    /// hour and a half at the drawn day's length.
    static let nightFall = 0.06

    /// A cool veil over the lens at night. The fog stays darker still, and
    /// warm windows and fires read brighter against it.
    static func nightWash(
        _ context: inout GraphicsContext, rect: CGRect, night: Double,
        moonlight: Double = 0
    ) {
        guard night > 0.01 else { return }
        // Night **darkens**; it does not paint the valley blue.
        //
        // At 0.30 alpha of (0.03, 0.05, 0.12) this was the strongest single
        // wash in the whole stack and by far the most saturated, so every dusk
        // dragged the ground toward its own colour. Over autumn — which is the
        // one season whose earth is genuinely brown — brown plus that much blue
        // is *purple*, and the whole valley went violet every evening.
        //
        // A near-neutral slate at two thirds the strength reads as the light
        // going out, which is what it is.
        // **Night takes the colour out first.** Darkening alone left an autumn
        // valley glowing orange at two in the morning, because a wash scales
        // brightness and leaves saturation exactly where it was — and the eye
        // reads a saturated field as daylight however dim it is (the same
        // reason night photography looks wrong when it is only underexposed).
        // A saturation blend against grey is the honest version of what happens
        // at low light: hue goes, shape stays.
        var colourless = context
        colourless.blendMode = .saturation
        colourless.fill(Path(rect), with: .color(Color(white: 0.5).opacity(night * 0.8)))

        // …and then it has to actually go dark. At 0.20 the deepest midnight
        // was a fifth of a wash over a fully-lit valley, which is an evening
        // filter, not a night — the second half of "vypadá to stejně jako přes
        // den". Deep enough that a lit window and a fire are the brightest
        // things on the screen, shallow enough that the line art still reads.
        // **How dark it goes is the moon's business.** Every night used to be
        // exactly as dark as every other one — the only input was how far past
        // sunset the clock stood, so a fortnight of play was one night repeated
        // (Keks: *"noc je dost tmavá a jednotvárná"*). A full moon is genuinely
        // bright enough to cross a field by and a new moon is black, which is a
        // two-and-a-half-fold swing arriving on its own every twenty-nine days.
        let depth = darkness(moonlight: moonlight)
        context.fill(Path(rect),
                     with: .color(Color(red: 0.05, green: 0.06, blue: 0.10).opacity(night * depth)))
        // Moonlight is *cold*: what little it leaves you is blue.
        //
        // At 0.10 this was arithmetic nobody could see — a gibbous moon put six
        // hundredths of an alpha over the valley, so the picture went *lighter*
        // without going moonlit, and an autumn night read as a dimmed afternoon
        // rather than as a night with a moon over it. Colour is how the eye
        // tells moonlight from underexposure.
        //
        // This is not the mistake the wash above is a note about. That one
        // painted **every** night blue at 0.30 and turned autumn violet every
        // evening; this one is paid for by the moon and by nothing else, so a
        // new moon is still black, a storm still puts it out, and the blue only
        // arrives on the nights that have a moon to justify it.
        if moonlight > 0.25 {
            context.fill(Path(rect),
                         with: .color(Color(red: 0.46, green: 0.56, blue: 0.82)
                            .opacity(night * (moonlight - 0.25) * 0.24)))
        }
    }

    /// How heavy the night wash goes, given the moon. Pulled out so a test can
    /// state the thing that matters — a full moon night is markedly brighter
    /// than a new moon night — without rendering anything.
    static func darkness(moonlight: Double) -> Double {
        let lit = min(1, max(0, moonlight))
        return 0.62 - lit * 0.26
    }

    /// **Which roofs have a light under them.**
    ///
    /// A dark valley with nothing burning in it is a dark valley; the town has
    /// to be visible as a town after sunset, and the way a town is visible at
    /// night is that its windows are. Three kinds, and the rest of the colony
    /// sleeps unlit — a granary at two in the morning is a black shed, and it
    /// should look like one, or the whole place reads as floodlit.
    ///
    /// - **Homes burn brightest**, and by *who is in them*: an empty hut is
    ///   dark, a full longhouse throws light out of every bay. This is the one
    ///   that matters, because dwellings are what a colony is mostly made of.
    /// - **A fire that is never let out** — forge, cookhouse, kiln, works — is
    ///   banked overnight rather than lit, so it glows low and red whatever the
    ///   hour.
    /// - **A light somebody sits up with**: the watchtower's beacon, a lamp in
    ///   the hall, the clinic, a votive candle in the temple. Weak, and steady.
    ///
    /// Pure, and derived from the same `placed` the buildings were drawn from,
    /// so a lamp cannot end up standing where its house is not.
    static func nightLamps(placed: [PlacedBuilding]) -> [SettlementLight.Lamp] {
        placed.flatMap { lamps(for: $0) }
    }

    /// **Where a building's light actually comes out of it.**
    ///
    /// A dwelling's windows, one lamp apiece; anything else, the opening its
    /// fire is behind. Neither was true before: every building in the colony
    /// got one lamp hung at its own centre point, a hand's width above the
    /// middle of the roof — so a longhouse with four lit bays glowed from a
    /// single dot floating over its ridge while the panes drawn on its wall sat
    /// dark. The complaint was exact: *a bright point in the middle of the
    /// house, and not where the windows are.*
    ///
    /// The windows come from `SettlementStructures.dwelling`, the same function
    /// that draws them, so a lamp cannot land where its window is not — and a
    /// house whose shutters the seed happens to close is now genuinely dark
    /// rather than merely dimmer.
    ///
    /// Pure, and derived from the same `placed` the buildings were drawn from.
    static func lamps(for building: PlacedBuilding) -> [SettlementLight.Lamp] {
        guard !building.underConstruction else { return [] }
        let s = building.size
        // A ruin does not keep its fire in.
        let sound = 0.45 + building.condition * 0.55
        // Off the building's own seed, so its fire breathes on its own beat and
        // keeps that beat between frames.
        let phase = Double(building.seed % 628) / 100

        switch building.glyph {
        case .house, .tenement:
            // Nobody home, no fire lit.
            guard building.residents > 0 else { return [] }
            let openings = SettlementStructures.dwelling(
                at: building.center, s: s, seed: building.seed,
                footprint: building.footprint, floors: building.floors,
                glyph: building.glyph)
            let windows = openings.panes.filter(\.lit)
            guard !windows.isEmpty else { return [] }
            // Four to a dwelling is a full house; past that it is not any
            // brighter, it is just fuller. Divided across the lit windows, so a
            // longhouse showing four is not four times as bright as a hut
            // showing one — it is the same fire seen through more openings.
            let full = min(1.0, Double(building.residents) / 4)
            let each = (0.45 + full * 0.45) / Double(windows.count).squareRoot()
            return windows.enumerated().map { index, pane in
                SettlementLight.Lamp(
                    at: CGPoint(x: pane.rect.midX, y: pane.rect.midY),
                    // A window throws a pool about as wide as the house is, not
                    // as wide as the pane: the light spills.
                    radius: max(pane.rect.width * 2.2, s * 0.9),
                    strength: each * sound,
                    colour: SettlementLight.hearth,
                    // Each window on its own beat, or a house blinks in unison
                    // and reads as one lamp again.
                    phase: phase + Double(index) * 0.8)
            }
        case .forge, .plant, .cookhouse, .tanks:
            return [SettlementLight.Lamp(at: source(of: building, s: s),
                                         radius: s * 1.05, strength: 0.55 * sound,
                                         colour: SettlementLight.ember, phase: phase)]
        case .tower:
            return [SettlementLight.Lamp(at: source(of: building, s: s),
                                         radius: s * 1.10, strength: 0.60 * sound,
                                         colour: SettlementLight.hearth, phase: phase)]
        case .hall, .clinic, .temple, .lab:
            return [SettlementLight.Lamp(at: source(of: building, s: s),
                                         radius: s * 0.85, strength: 0.28 * sound,
                                         colour: SettlementLight.hearth, phase: phase)]
        default:
            return []
        }
    }

    /// The point a non-dwelling burns from — the mouth of the forge, the head
    /// of the tower, the door of the hall. Low on the body rather than at its
    /// centre, because a fire sits on a floor.
    static func source(of building: PlacedBuilding, s: CGFloat) -> CGPoint {
        switch building.glyph {
        case .tower:
            // A beacon is at the top of the tower or it is not a beacon.
            return CGPoint(x: building.center.x, y: building.center.y - s * 0.62)
        case .forge, .plant, .cookhouse, .tanks:
            // A banked fire is at floor level, in the mouth of the building.
            return CGPoint(x: building.center.x, y: building.center.y + s * 0.16)
        default:
            return CGPoint(x: building.center.x, y: building.center.y - s * 0.06)
        }
    }

}
