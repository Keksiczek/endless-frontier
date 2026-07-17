import Foundation

/// Generates colonists deterministically from a seed, so recruitment events
/// produce the same person for the same world state on every run.
public enum PawnFactory {
    /// Name syllables, carried over from the sim this world grew out of.
    ///
    /// Colonists used to be twelve hard-coded English names — Rurik, Sable,
    /// Wren — handed out over and over in a world meant to be kept for weeks,
    /// so a chronicle spanning centuries was full of people who sounded like
    /// strangers to it. Built from syllables instead, the colony sounds Slavic,
    /// which is the voice this game inherited: Bohumil, Svamír, Mladěj,
    /// Radslav. Two lists of fifteen make 225 names, and doubling a first
    /// syllable now and then stretches that further without ever reading wrong.
    static let firstSyllables = [
        "Bo", "Ra", "Mi", "Ve", "Da", "Ka", "Ly", "No",
        "Ta", "Zi", "Ja", "Ol", "Bře", "Sva", "Mla"
    ]
    static let lastSyllables = [
        "ren", "mil", "slav", "na", "rek", "va", "dan", "mír",
        "ta", "goj", "run", "děj", "ša", "na", "dor"
    ]

    /// A colonist's name, drawn deterministically from `rng`.
    public static func name(using rng: inout SeededRNG) -> String {
        let first = firstSyllables[Int(rng.next() % UInt64(firstSyllables.count))]
        let last = lastSyllables[Int(rng.next() % UInt64(lastSyllables.count))]
        // Occasionally a middle syllable, for a longer, older-sounding name.
        guard rng.nextUnit() < longNameChance else { return first + last }
        let middle = firstSyllables[Int(rng.next() % UInt64(firstSyllables.count))]
        return first + middle.lowercased() + last
    }

    /// How often a name takes a third syllable.
    static let longNameChance = 0.25

    /// Builds a colonist from a numeric seed (typically derived from world tick
    /// and current colonist count). Recruits arrive as working-age adults with
    /// their own genes.
    public static func generate(seed: UInt64) -> Pawn {
        var rng = SeededRNG(seed: seed ^ 0xA11CE_5EED)
        let name = name(using: &rng)
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
