import Foundation

/// Resolves the buffs items provide: equipment buffs the carrying colonist;
/// artifacts held in a settlement's inventory buff the whole colony.
public enum ItemEngine {
    // MARK: - Equipment (per colonist)

    private static func equippedEffects(_ pawn: Pawn, registry: GameDataRegistry) -> [ItemEffect] {
        pawn.equipment.values
            // A tool that has come apart in the hand does nothing for the hand.
            .filter { !$0.isBroken }
            .compactMap { registry.item($0.definitionID) }
            .flatMap(\.effects)
    }

    // MARK: - What use does to a thing

    /// How much of a tool a day's work uses up, per `BuildingEngine.interval`.
    ///
    /// A tool at work is the third source of wear named in §11.26 C, beside
    /// combat and lying out in the weather. Sized so an axe swung every working
    /// day is worth replacing after a few years rather than after a lifetime —
    /// which is what gives the bench something to do once everybody is armed,
    /// and what makes a hoe a thing the colony **keeps** making.
    static let wearPerWorkInterval = 0.0016

    /// Wears the tools of everybody who is actually working, and throws away
    /// what has come apart.
    ///
    /// Only the working: somebody asleep, ill, away or idle is not wearing
    /// anything out. Runs on the building interval, never per tick — this walks
    /// every colonist (rule 4).
    public static func wearTools(
        _ settlement: Settlement, registry: GameDataRegistry, tick: Int
    ) -> Settlement {
        var s = settlement
        for i in s.pawns.indices {
            guard s.pawns[i].currentJob != nil, s.pawns[i].health > 0,
                  !s.pawns[i].isBroken, !s.pawns[i].isAway else { continue }
            for slot in EquipmentSlot.allCases {
                guard let piece = s.pawns[i].equipment[slot],
                      let def = registry.item(piece.definitionID),
                      // Gear that helps you *work* is gear work wears out. A
                      // coat on a farmer's back is worn by the weather, not by
                      // the furrow, and is left to the fighting and the years.
                      def.effects.contains(where: { effect in
                          if case .skillBonus = effect { return true }
                          return false
                      }) else { continue }
                s.pawns[i].equipment[slot] = piece.worn(by: wearPerWorkInterval)
            }
        }
        return scrapBroken(s, registry: registry, tick: tick)
    }

    /// Takes what has come apart out of people's hands.
    ///
    /// A broken piece already does nothing — no effects, no fighting profile,
    /// no armour — so leaving it in the slot would only mean the quartermaster
    /// sees a full slot and the colonist stands there holding a stick. It is
    /// scrapped rather than shelved: a ruined thing is not stock.
    public static func scrapBroken(
        _ settlement: Settlement, registry: GameDataRegistry, tick: Int
    ) -> Settlement {
        var s = settlement
        for i in s.pawns.indices {
            for slot in EquipmentSlot.allCases {
                guard let piece = s.pawns[i].equipment[slot], piece.isBroken else { continue }
                s.pawns[i].equipment[slot] = nil
                let what = registry.item(piece.definitionID)?.name
                let name = s.pawns[i].name
                // Phrased so the Czech needs no agreement with the person —
                // colonists have names and no grammatical gender, and a line
                // that guesses one is a line that gets it wrong half the time.
                s.journal.append(
                    tick: tick, kind: .work,
                    text: LocalizedText(values: [
                        .en: "\(name): \(what?.resolve(.en).lowercased() ?? "gear") worn out, thrown on the scrap.",
                        .cs: "\(name): \(what?.resolve(.cs).lowercased() ?? "výstroj") dosloužila, jde na šrot."]),
                    subject: .pawn(s.pawns[i].id))
            }
        }
        return s
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
