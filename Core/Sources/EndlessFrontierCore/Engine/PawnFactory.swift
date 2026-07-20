import Foundation

/// Generates colonists deterministically from a seed, so recruitment events
/// produce the same person for the same world state on every run.
public enum PawnFactory {
    /// A colonist's name in the world's language, drawn deterministically from
    /// `rng` (see `NameForge` for the pools).
    public static func name(using rng: inout SeededRNG, language: GameLanguage = .cs) -> String {
        NameForge.colonistName(language: language, using: &rng)
    }

    /// Builds a colonist from a numeric seed (typically derived from world tick
    /// and current colonist count). Recruits arrive as working-age adults with
    /// their own genes.
    public static func generate(seed: UInt64, language: GameLanguage = .cs) -> Pawn {
        var rng = SeededRNG(seed: seed ^ 0xA11CE_5EED)
        let name = name(using: &rng, language: language)
        let traits = PawnTrait.allCases
        let trait = traits[Int(rng.next() % UInt64(traits.count))]
        // Pick a productive work kind (not idle) as the recruit's specialty.
        let works = WorkKind.allCases.filter { $0 != .idle }
        let work = works[Int(rng.next() % UInt64(works.count))]
        let skillLevel = 3 + Int(rng.next() % 8)   // 3…10
        let ageYears = 16 + Int(rng.next() % 25)   // 16…40
        return Pawn(
            id: rng.nextUUID(),
            name: name,
            trait: trait,
            skills: [work: skillLevel],
            assignedWork: work,
            age: ageYears * 60,   // in ticks at the standard 60 ticks/year
            genes: .founder(using: &rng)
        )
    }
}
