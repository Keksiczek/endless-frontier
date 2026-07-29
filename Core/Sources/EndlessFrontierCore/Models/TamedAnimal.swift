import Foundation

/// What a tamed beast is kept for.
///
/// Not a job in the colonists' sense — an animal has no trade and no schedule —
/// but the reason you spent a season gentling it rather than shooting it.
public enum TamedRole: String, Codable, Sendable, CaseIterable {
    /// Hauls. A boar or a deer under a pack takes the weight off people.
    case beastOfBurden = "beast_of_burden"
    /// Watches. A wolf at the gate is worth several spears.
    case `guard`
    /// Keeps somebody company, and the colony's spirits up.
    case companion

    public var displayName: LocalizedText {
        switch self {
        case .beastOfBurden: return LocalizedText(values: [.en: "Pack animal", .cs: "Soumar"])
        case .guard: return LocalizedText(values: [.en: "Guard", .cs: "Hlídač"])
        case .companion: return LocalizedText(values: [.en: "Companion", .cs: "Společník"])
        }
    }
}

/// One animal that belongs to the settlement.
///
/// It is the same `Animal` the wild is made of — the same body, the same
/// wounds, the same illnesses — only now it lives inside the colony, eats out
/// of its stores and does something in return. Keeping it is a cost as well as
/// a gift, which is the only way an animal is a decision rather than a pickup.
public struct TamedAnimal: Codable, Sendable, Equatable, Identifiable {
    public var animal: Animal
    public var role: TamedRole
    /// The tick it came round, for the chronicle.
    public let tamedTick: Int
    /// What the colony calls it. Nil until somebody names it.
    public var name: String?

    public var id: UUID { animal.id }

    public init(animal: Animal, role: TamedRole, tamedTick: Int, name: String? = nil) {
        self.animal = animal
        self.role = role
        self.tamedTick = tamedTick
        self.name = name
    }
}
