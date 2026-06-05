import Foundation

/// Resolves the buffs items provide: equipment buffs the carrying colonist;
/// artifacts held in a settlement's inventory buff the whole colony.
public enum ItemEngine {
    // MARK: - Equipment (per colonist)

    private static func equippedEffects(_ pawn: Pawn, registry: GameDataRegistry) -> [ItemEffect] {
        pawn.equipment.values
            .compactMap { registry.item($0.definitionID) }
            .flatMap(\.effects)
    }

    public static func skillBonus(_ pawn: Pawn, work: WorkKind, registry: GameDataRegistry) -> Int {
        equippedEffects(pawn, registry: registry).reduce(0) { acc, effect in
            if case let .skillBonus(w, amount) = effect, w == work { return acc + amount }
            return acc
        }
    }

    public static func moodBonus(_ pawn: Pawn, registry: GameDataRegistry) -> Double {
        equippedEffects(pawn, registry: registry).reduce(0) { acc, effect in
            if case let .moodBonus(amount) = effect { return acc + amount }
            return acc
        }
    }

    public static func healthRegenBonus(_ pawn: Pawn, registry: GameDataRegistry) -> Double {
        equippedEffects(pawn, registry: registry).reduce(0) { acc, effect in
            if case let .healthRegen(amount) = effect { return acc + amount }
            return acc
        }
    }

    // MARK: - Artifacts (per colony)

    private static func artifactEffects(_ settlement: Settlement, registry: GameDataRegistry) -> [ItemEffect] {
        settlement.inventory.compactMap { registry.item($0.definitionID) }
            .filter { $0.slot == .artifact }
            .flatMap(\.effects)
    }

    public static func colonyProduction(_ settlement: Settlement, registry: GameDataRegistry) -> Resources {
        var resources = Resources()
        for effect in artifactEffects(settlement, registry: registry) {
            if case let .colonyProduction(resource, perTick) = effect {
                resources[resource] = resources[resource] + perTick
            }
        }
        return resources
    }

    public static func colonyDefenseBonus(_ settlement: Settlement, registry: GameDataRegistry) -> Double {
        artifactEffects(settlement, registry: registry).reduce(0) { acc, effect in
            if case let .colonyDefense(amount) = effect { return acc + amount }
            return acc
        }
    }

    public static func colonyMoraleBonus(_ settlement: Settlement, registry: GameDataRegistry) -> Double {
        artifactEffects(settlement, registry: registry).reduce(0) { acc, effect in
            if case let .colonyMorale(amount) = effect { return acc + amount }
            return acc
        }
    }
}
