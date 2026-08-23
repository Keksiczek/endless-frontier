import Foundation

/// **Everything a `modifier` tech effect is allowed to touch, and what touching
/// it means.**
///
/// Research did plenty and changed nothing you could watch. Counted across
/// `techs.json`: thirty-nine effects unlock a building, five open an event
/// category, and every one of the ten `modifier` effects moved one of exactly
/// two numbers — `knowledgeOutput` (nine of them) and `influenceOutput` (one).
/// So the whole reward of the tech tree was *a new row in the build menu* and
/// *research that produces more research*. Keks, on the science screen: **"ať to
/// není jen text, ale ať to něco dělá."**
///
/// This is the list of things it can now do, and the honest part of it is that
/// the list is **closed and checked**: `ResearchStatTests` fails if a case here
/// is never read by any engine, because a stat that nothing reads is exactly
/// the failure this repository keeps paying for (rule 52 — a field the checker
/// validates, the generator writes, and nothing consumes).
///
/// Adding one is three steps: a case here, one multiplication at the seam it
/// names, and a line in the test that proves the seam moved.
public enum ResearchStat: String, CaseIterable, Sendable {

    /// How much a tech's `delta` means where it lands.
    public enum Kind: Sendable {
        /// Added straight onto a per-tick output. `+3` is three more a tick.
        case addedToOutput
        /// A factor on a rate: `+0.25` makes it a quarter faster, `-0.25` a
        /// quarter slower. Floored at `minimumFactor`, so no stack of studies
        /// can turn a rate negative and run it backwards.
        case factor
    }

    // The two that already existed. Research feeding itself is not wrong — it
    // is just not *enough*, and these stay exactly as they were.
    case knowledgeOutput
    case influenceOutput

    /// What comes off a ripe plot. The most visible number in the game: more
    /// grain at the field, more meals out of the cookhouse, in the same season.
    case cropYield
    /// How fast a frame becomes a roof. Watched directly — scaffolding is on
    /// the canvas and a shorter wait is the whole reward.
    case buildSpeed
    /// How hard weather and years bite a standing building. A colony that has
    /// studied this has fewer ruins in it, which is a thing you *see*.
    case buildingWear
    /// How fast a hurt colonist mends. The difference between a broken leg
    /// being a season and being a year.
    case recovery

    // **The five added when the tree turned out to be too short to be a tree.**
    //
    // Measured (`EF_PROBE=1 … ResearchProbe`): a colony finishes **all 37
    // techs by year 70** and then banks knowledge for a century and a half
    // with nothing to buy. The instinct is to write more techs, and it is
    // wrong on its own: with six levers in the whole game, twenty more studies
    // would have been twenty more `+1 knowledgeOutput` — research that
    // produces research, which is the fault this file was written to end.
    // A tree is only as long as the number of *different things* a study can
    // change.

    /// What a kill brings home. Meat on the table and a hide off its back —
    /// the hunters' half of the food chain, which had no study touching it.
    case huntYield
    /// What the axe and the pick take out of a day: timber at the stump,
    /// stone and ore at the face, herbs out of the wood.
    case gatherYield
    /// How much one pair of hands carries in one trip. The difference between
    /// a colony that is behind on its hauling and one that is not.
    case carryCapacity
    /// What the wall is worth when somebody comes over the ground at it.
    /// Studied fortification, rather than another building to raise.
    case wallStrength
    /// How fast a colonist gets good at their trade. The slowest-acting study
    /// in the game and the one that compounds — a colony that studies teaching
    /// is a colony of masters twenty years later.
    case trainingSpeed

    public var kind: Kind {
        switch self {
        case .knowledgeOutput, .influenceOutput: return .addedToOutput
        case .cropYield, .buildSpeed, .buildingWear, .recovery,
             .huntYield, .gatherYield, .carryCapacity, .wallStrength, .trainingSpeed:
            return .factor
        }
    }

    /// The name a tech effect writes in `techs.json`, which is the stat
    /// prefixed with `global.` — the spelling the existing ten already use.
    public var effectName: String { "global." + rawValue }

    /// A factor may not fall below this however many studies stack against it.
    /// A negative rate does not mean "slower", it means "backwards".
    public static let minimumFactor: Double = 0.1
}

public extension WorldState {

    /// The factor research has earned for a world rate — 1 when nothing has
    /// been studied, so every call site reads the same whether or not the
    /// colony has a library.
    ///
    /// Multiply, never add: `rate * state.researchFactor(.cropYield)`. The one
    /// place the meaning of a `modifier` delta is written down for rates.
    func researchFactor(_ stat: ResearchStat) -> Double {
        guard stat.kind == .factor else { return 1 }
        let delta = statModifiers[stat.rawValue] ?? 0
        return max(ResearchStat.minimumFactor, 1 + delta)
    }

    /// …and the flat addition, for the two per-tick outputs that work that way.
    func researchBonus(_ stat: ResearchStat) -> Double {
        guard stat.kind == .addedToOutput else { return 0 }
        return statModifiers[stat.rawValue] ?? 0
    }
}
