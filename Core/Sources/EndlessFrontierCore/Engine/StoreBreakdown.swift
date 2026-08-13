import Foundation

/// One link of the chain behind a number in the resource bar.
public struct StoreStage: Sendable, Equatable, Identifiable {
    public let id: String
    public let label: LocalizedText
    /// What is held at this stage, in the units the player sees.
    public let amount: Double
    /// The sentence that says *why* this stage matters when it is the one that
    /// is empty, or the one that is piling up. `nil` when it is unremarkable.
    public let note: LocalizedText?

    public init(id: String, label: LocalizedText, amount: Double, note: LocalizedText? = nil) {
        self.id = id
        self.label = label
        self.amount = amount
        self.note = note
    }
}

/// What is behind a resource's headline number, stage by stage.
///
/// **`storage[.food]` does not mean "food".** It means *meals ready to eat* and
/// nothing else — CLAUDE.md is explicit about it — and everything upstream is
/// invisible to the player: crops standing in the plots, a harvest reaped and
/// lying where it fell, sacks on the shelf nobody has cooked. So a player
/// reading `food: 0` cannot tell whether the colony has no crop, a full harvest
/// nobody carried in, or a granary full of grain and no cook. Three completely
/// different problems, one number (§11.24).
///
/// That is not a hypothetical. Finding the 2026-08-13 famine took most of a day
/// and came down to printing **`shelf` and `lying` next to each other** in a
/// probe: production was healthy, plots stood at 140 against 79 wanted, cooks
/// and farmers both scaled — and the harvest was lying in the fields under a
/// dead colonist's claim. Either column alone says nothing. The pair says it at
/// a glance. This is that pair, given to the player.
///
/// Derived, never stored, and read from the same state the canvas draws
/// (rule 18).
public enum StoreBreakdown {

    /// The chain behind the food number, in the order it actually flows:
    /// growing → reaped and lying → on the shelf → cooked.
    public static func food(
        _ settlement: Settlement, registry: GameDataRegistry
    ) -> [StoreStage] {
        let kinds = CookingEngine.foodstuffs(registry)
        let map = settlement.localMap

        // Standing in the plots. `standing` is what reaping it *now* would
        // give, so a field cut early counts for proportionally less.
        let growing = map?.crops.reduce(0.0) { $0 + $1.standing } ?? 0
        let ripe = map?.crops.count { $0.isRipe } ?? 0
        let plots = map?.crops.count ?? 0

        // Reaped and lying where it fell, waiting for a pair of hands.
        let lying = map?.piles
            .filter { kinds.contains($0.itemID) }
            .reduce(0) { $0 + $1.amount } ?? 0

        let shelf = kinds.reduce(0) { $0 + settlement.stockpile[$1, default: 0] }
        let cooks = settlement.pawns.count { $0.assignedWork == .cooking }
        let meals = settlement.storage[.food]

        return [
            StoreStage(
                id: "growing",
                label: LocalizedText(values: [.en: "Growing", .cs: "Roste na poli"]),
                amount: growing,
                note: plots == 0
                    ? LocalizedText(values: [
                        .en: "No ground is tilled.",
                        .cs: "Není zorané pole."])
                    : LocalizedText(values: [
                        .en: "\(ripe) of \(plots) plots ripe",
                        .cs: "\(ripe) z \(plots) záhonů zralých"])),
            StoreStage(
                id: "lying",
                label: LocalizedText(values: [.en: "Reaped, not carried", .cs: "Sklizeno, nedoneseno"]),
                amount: Double(lying),
                note: lying > 0
                    ? LocalizedText(values: [
                        .en: "Lying in the fields until somebody fetches it.",
                        .cs: "Leží na poli, dokud pro to někdo nedojde."])
                    : nil),
            StoreStage(
                id: "shelf",
                label: LocalizedText(values: [.en: "On the shelf", .cs: "Na polici"]),
                amount: Double(shelf),
                note: shelf > 0 && cooks == 0
                    ? LocalizedText(values: [
                        .en: "Raw, and nobody is cooking.",
                        .cs: "Syrové, a nikdo nevaří."])
                    : nil),
            StoreStage(
                id: "meals",
                label: LocalizedText(values: [.en: "Ready to eat", .cs: "Hotová jídla"]),
                amount: meals,
                note: LocalizedText(values: [
                    .en: "\(cooks) cooking",
                    .cs: "\(cooks) u ohně"])),
        ]
    }

    /// Timber and stone: on the ground, on the shelf as made goods, and in the
    /// store as the abstract figure the ledger spends.
    public static func materials(
        _ settlement: Settlement, registry: GameDataRegistry
    ) -> [StoreStage] {
        let foods = CookingEngine.foodstuffs(registry)
        let map = settlement.localMap
        let lying = map?.piles
            .filter { !foods.contains($0.itemID) }
            .reduce(0) { $0 + $1.amount } ?? 0
        // What the bench has made and the buildings ask for by name.
        let made = CraftingEngine.materialCounts(settlement)
            .reduce(0) { $0 + $1.value }

        return [
            StoreStage(
                id: "lying",
                label: LocalizedText(values: [.en: "Felled, not carried", .cs: "Poraženo, nedoneseno"]),
                amount: Double(lying),
                note: lying > 0
                    ? LocalizedText(values: [
                        .en: "Trunks and blocks still at the stump.",
                        .cs: "Kmeny a bloky pořád u pařezu."])
                    : nil),
            StoreStage(
                id: "made",
                label: LocalizedText(values: [.en: "Made goods", .cs: "Vyrobené zboží"]),
                amount: Double(made),
                note: made == 0
                    ? LocalizedText(values: [
                        .en: "Nothing on the shelf — most buildings need timber bundles.",
                        .cs: "Nic na polici — většina budov chce trámy."])
                    : nil),
            StoreStage(
                id: "store",
                label: LocalizedText(values: [.en: "In store", .cs: "Ve skladu"]),
                amount: settlement.storage[.materials],
                note: nil),
        ]
    }

    /// Everything else has no chain worth drawing yet: one number, and what it
    /// is spent on. Returned so the panel treats all five alike rather than
    /// special-casing two.
    public static func plain(
        _ resource: ResourceType, _ settlement: Settlement
    ) -> [StoreStage] {
        [StoreStage(id: "store",
                    label: LocalizedText(values: [.en: "In store", .cs: "Ve skladu"]),
                    amount: settlement.storage[resource],
                    note: nil)]
    }

    /// The chain behind any resource.
    public static func of(
        _ resource: ResourceType, in settlement: Settlement, registry: GameDataRegistry
    ) -> [StoreStage] {
        switch resource {
        case .food: return food(settlement, registry: registry)
        case .materials: return materials(settlement, registry: registry)
        case .energy, .knowledge, .influence: return plain(resource, settlement)
        }
    }
}
