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
    ///
    /// `stock` is **the people they come from**: a tribe's character for a
    /// wanderer or a prisoner, the colony's own for somebody it sent out to
    /// found an outpost. Passing `nil` rolls a stranger from nowhere, whose
    /// mean is 0.5 — which is what every newcomer used to be, and is why a
    /// colony's dispositions converged on the middle however hard the world
    /// selected (see `Genes.drawn(from:using:)`). Prefer to say where somebody
    /// came from; the game almost always knows.
    public static func generate(seed: UInt64, language: GameLanguage = .cs,
                                stock: Genes? = nil) -> Pawn {
        var rng = SeededRNG(seed: seed ^ 0xA11CE_5EED)
        let name = name(using: &rng, language: language)
        let traits = PawnTrait.allCases
        let trait = traits[Int(rng.next() % UInt64(traits.count))]
        // Pick a productive work kind (not idle) as the recruit's specialty.
        let works = WorkKind.allCases.filter { $0 != .idle }
        let work = works[Int(rng.next() % UInt64(works.count))]
        let skillLevel = 3 + Int(rng.next() % 8)   // 3…10
        // 16…30, not 16…40.
        //
        // A party that sails out to found a colony is young — and it has to be,
        // now that children come from marriages rather than from a birth rate:
        // a bond takes years of meeting to reach the wedding threshold, so
        // somebody who lands at thirty-eight is married at forty-four and past
        // it. Measured with the old spread: four married couples, not one of
        // them able to have children, and the colony gone by year seventy.
        let ageYears = 16 + Int(rng.next() % 15)   // 16…30
        return Pawn(
            id: rng.nextUUID(),
            name: name,
            trait: trait,
            skills: [work: skillLevel],
            assignedWork: work,
            age: ageYears * 60,   // in ticks at the standard 60 ticks/year
            genes: stock.map { Genes.drawn(from: $0, using: &rng) }
                ?? .founder(using: &rng)
        )
    }
}
