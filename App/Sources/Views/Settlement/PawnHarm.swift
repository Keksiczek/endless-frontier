import SwiftUI
import EndlessFrontierCore

/// **What a colonist's body shows** — the wounds, the bandages, the arm that
/// is not there any more.
///
/// `Body` has had parts with a `condition` and a `missing` flag, and ailments
/// that name a `WoundKind` and the part it landed on, since the medical model
/// went in. `PawnInspectorCard` reads all of it. The canvas read none of it:
/// `PawnLook`'s own header claims the figure carries "genes, age, trait,
/// **wounds**, three equipment slots" and it draws hair, build, height and
/// skin. So a colonist with a missing arm walked to work swinging two, and a
/// man bandaged from a raid looked exactly like the man who had missed it.
/// Keks: *"zranění neodpovídají tomu, co vidíme na plátně."*
///
/// Derived, never stored (rule 5) — a pure function of the pawn's own body,
/// asked once per figure per frame.
struct PawnHarm {

    /// How a limb is, as far as a drawing is concerned.
    enum Limb {
        case whole
        /// Hurt but there: it moves badly.
        case hurt
        /// Gone. A stump, and a stick to lean on if it was a leg.
        case gone

        var isGone: Bool { self == .gone }
    }

    var head: Limb = .whole
    var torso: Limb = .whole
    var leftArm: Limb = .whole
    var rightArm: Limb = .whole
    var leftLeg: Limb = .whole
    var rightLeg: Limb = .whole
    /// Parts somebody has dressed. Drawn as a band of clean linen — the visible
    /// difference between a colony with a healer and one without.
    var bandaged: Set<BodyPartKind> = []
    /// …and the parts still open, which show blood instead.
    var open: Set<BodyPartKind> = []

    /// Whether anything at all is worth drawing. The common case is a whole
    /// body, and it must cost one branch.
    var isHurt: Bool {
        head != .whole || torso != .whole || leftArm != .whole || rightArm != .whole
            || leftLeg != .whole || rightLeg != .whole
            || !bandaged.isEmpty || !open.isEmpty
    }

    /// Whether they cannot put weight on a leg — the limp, and the stick.
    var limps: Bool { leftLeg != .whole || rightLeg != .whole }

    static func of(_ pawn: Pawn) -> PawnHarm {
        var harm = PawnHarm()
        for kind in BodyPartKind.allCases {
            guard let part = pawn.body.part(kind) else { continue }
            let state: Limb = part.missing ? .gone : (part.condition < 0.72 ? .hurt : .whole)
            switch kind {
            case .head:     harm.head = state
            case .torso:    harm.torso = state
            case .leftArm:  harm.leftArm = state
            case .rightArm: harm.rightArm = state
            case .leftLeg:  harm.leftLeg = state
            case .rightLeg: harm.rightLeg = state
            }
        }
        for ailment in pawn.body.ailments {
            // Only injuries mark a body. A fever is a thing the card says and
            // the figure shows by being laid up, not by bleeding.
            guard ailment.wound != nil, let part = ailment.part else { continue }
            if ailment.tended { harm.bandaged.insert(part) } else { harm.open.insert(part) }
        }
        return harm
    }
}
