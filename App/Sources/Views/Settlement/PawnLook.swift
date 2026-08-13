import SwiftUI
import EndlessFrontierCore

/// What one colonist looks like — hair, beard, build, height, skin.
///
/// **§11.20.** Every colonist was drawn by the same figure: a head circle, a
/// two-line body, and a tunic in their trade's colour. Two hundred people in a
/// two-hundred-year colony were two hundred instances of one drawing, while the
/// simulation underneath already knew they were different — genes, age, trait,
/// wounds, three equipment slots — and none of it reached the eye.
///
/// **Derived, never stored** (rule 5). A pure function of `(pawn.id, age,
/// genes)`, the same way `AgentMotion` derives position. A stored appearance is
/// a save migration and a determinism risk for nothing.
///
/// **Line art, not sprites** — decided in §11.20, and the reason that matters
/// is the first one: the whole settlement view is paths and tones, so a raster
/// figure would stop belonging to the place it stands in. Paths also survive
/// the zoom, and `SettlementCrowd.showsIndividuals` drops people to group marks
/// when the camera pulls back, so the detail only has to read close in.
///
/// Small closed sets doing combinatorial work: 6 hair shapes × 5 hair colours ×
/// 4 beards × 3 builds × 3 heights × 5 skin tones — a crowd of thousands out of
/// a few bytes of hash.
struct PawnLook {

    // MARK: - The parts

    enum Hair: CaseIterable {
        case bald, cropped, short, tousled, long, braided
    }

    enum Beard: CaseIterable {
        case none, stubble, short, full
    }

    let hair: Hair
    let hairColour: Color
    let beard: Beard
    /// Shoulder width, as a multiplier on the torso. Genes tilt this.
    let build: Double
    /// Overall height, as a multiplier on the figure's scale.
    let height: Double
    let skin: Color
    /// How far the shoulders come forward. Rises with age, so a colony that is
    /// all growing old together *looks* it without opening a panel (§11.17).
    let stoop: Double

    // MARK: - Palettes

    /// A colour as plain components.
    ///
    /// Kept as numbers rather than as `Color` because the greying blend runs
    /// **per colonist, per frame**, and reading components back out of a
    /// SwiftUI `Color` means bridging through `UIColor` every time. A hundred
    /// and thirty colonists at thirty frames is a bridge crossing nobody needs:
    /// mix the numbers, build one `Color` at the end.
    struct Tone {
        let r: Double, g: Double, b: Double
        var color: Color { Color(red: r, green: g, blue: b) }
        func blended(_ other: Tone, _ t: Double) -> Tone {
            let u = min(1, max(0, t))
            return Tone(r: r + (other.r - r) * u,
                        g: g + (other.g - g) * u,
                        b: b + (other.b - b) * u)
        }
    }

    /// Five skin tones. Warm and desaturated, so a face reads against the
    /// canvas's tones rather than sitting on top of them.
    static let skinTones: [Tone] = [
        Tone(r: 0.93, g: 0.86, b: 0.76),
        Tone(r: 0.89, g: 0.79, b: 0.66),
        Tone(r: 0.80, g: 0.66, b: 0.51),
        Tone(r: 0.65, g: 0.49, b: 0.36),
        Tone(r: 0.47, g: 0.35, b: 0.26),
    ]

    /// Five hair colours, before age gets at them.
    static let hairColours: [Tone] = [
        Tone(r: 0.16, g: 0.14, b: 0.13),   // black
        Tone(r: 0.31, g: 0.23, b: 0.16),   // dark brown
        Tone(r: 0.46, g: 0.32, b: 0.19),   // chestnut
        Tone(r: 0.68, g: 0.56, b: 0.34),   // fair
        Tone(r: 0.55, g: 0.28, b: 0.15),   // red
    ]

    /// What hair goes grey toward.
    static let grey = Tone(r: 0.78, g: 0.77, b: 0.74)

    // MARK: - Ages

    /// Hair starts to turn here…
    static let greyingFrom: Double = 42
    /// …and is as pale as it gets here.
    static let greyingBy: Double = 76
    /// Past this the shoulders start to come forward.
    static let stoopingFrom: Double = 54
    /// Past this hair thins, and some of it goes.
    static let thinningFrom: Double = 58

    // MARK: - Deriving one

    /// The look of a colonist at their present age.
    ///
    /// Each part reads its own slice of the hash, so they vary *independently*:
    /// pulling one value out of one stream and dividing it up would tie hair
    /// colour to build and give a colony of five kinds of person.
    static func of(_ pawn: Pawn, ageYears: Int) -> PawnLook {
        let seed = AgentMotion.hash(pawn.id)
        let years = Double(ageYears)
        let child = ageYears < Pawn.adultAgeYears

        // Hair. Age thins it: the longer styles give way and a few heads go
        // bare, which is why `bald` is first in the list and reachable only
        // here or by the roll.
        var hair = Hair.allCases[Int(pick(seed, 3) * Double(Hair.allCases.count))]
        if years >= thinningFrom {
            let thinning = ramp(years, from: thinningFrom, to: 82)
            if pick(seed, 47) < thinning * 0.55 {
                hair = pick(seed, 53) < 0.45 ? .bald : .cropped
            } else if hair == .long || hair == .braided {
                hair = .short
            }
        }
        // A child's hair is never a grown style.
        if child, hair == .braided { hair = .tousled }

        let base = hairColours[Int(pick(seed, 11) * Double(hairColours.count))]
        let greying = ramp(years, from: greyingFrom, to: greyingBy)
        let colour = base.blended(grey, greying * 0.85).color

        // Beards are for adults, and the roll is its own stream so a beard
        // says nothing about the hair above it.
        let beard: Beard = child
            ? .none
            : Beard.allCases[Int(pick(seed, 19) * Double(Beard.allCases.count))]

        // Build and height. **Genes tilt, they do not decide** — a courageous
        // colonist stands squarer, but the roll is still most of the answer, or
        // the look becomes a readout of the stat block.
        let squarer = (pawn.genes.courage - 0.5) * 0.14
        let build = (0.88 + pick(seed, 23) * 0.26 + squarer) * (child ? 0.86 : 1)
        let height = (0.94 + pick(seed, 29) * 0.14) * (child ? 0.82 : 1)

        let skin = skinTones[Int(pick(seed, 37) * Double(skinTones.count))].color
        let stoop = ramp(years, from: stoopingFrom, to: 84)

        return PawnLook(hair: hair, hairColour: colour, beard: beard,
                        build: build, height: height, skin: skin, stoop: stoop)
    }

    // MARK: - Maths

    /// A stable [0,1) value from one slice of a colonist's hash.
    ///
    /// The shift is what keeps the parts independent — the same trick
    /// `AgentMotion` uses for its per-colonist offsets.
    private static func pick(_ seed: UInt64, _ slice: UInt64) -> Double {
        var h = (seed &+ slice &* 0x9E37_79B9_7F4A_7C15) &* 0x2545_F491_4F6C_DD1D
        h ^= h &>> 29
        h = h &* 0xBF58_476D_1CE4_E5B9
        h ^= h &>> 32
        return Double(h & 0xFF_FFFF) / Double(0x100_0000)
    }

    /// 0 below `from`, 1 above `to`, smooth in between.
    private static func ramp(_ v: Double, from: Double, to: Double) -> Double {
        guard to > from else { return v >= to ? 1 : 0 }
        let t = min(1, max(0, (v - from) / (to - from)))
        return t * t * (3 - 2 * t)
    }
}
