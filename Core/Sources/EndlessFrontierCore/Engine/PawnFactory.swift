import Foundation

/// Generates colonists deterministically from a seed, so recruitment events
/// produce the same person for the same world state on every run.
public enum PawnFactory {
    static let names = [
        "Rurik", "Sable", "Wren", "Cass", "Dorn", "Lina",
        "Pike", "Yara", "Bram", "Tove", "Esca", "Pell"
    ]

    /// Builds a colonist from a numeric seed (typically derived from world tick
    /// and current colonist count).
    public static func generate(seed: UInt64) -> Pawn {
        var rng = SeededRNG(seed: seed ^ 0xA11CE_5EED)
        let name = names[Int(rng.next() % UInt64(names.count))]
        let traits = PawnTrait.allCases
        let trait = traits[Int(rng.next() % UInt64(traits.count))]
        // Pick a productive work kind (not idle) as the recruit's specialty.
        let works = WorkKind.allCases.filter { $0 != .idle }
        let work = works[Int(rng.next() % UInt64(works.count))]
        let skillLevel = 3 + Int(rng.next() % 8)   // 3…10
        return Pawn(
            id: rng.nextUUID(),
            name: name,
            trait: trait,
            skills: [work: skillLevel],
            assignedWork: work
        )
    }
}
