import SwiftUI
import EndlessFrontierCore

/// Building, done on the settlement itself.
///
/// Placing used to happen on a separate abstract tile screen: you chose a spot
/// on one picture and found out what it looked like on another, so there was no
/// way to tell what would end up next to what, or whether a 3×3 would even fit.
/// These two bars turn the living canvas into the build surface — pick a
/// building, tap the ground to aim a full-size ghost, then commit.
///
/// The two steps are the whole point. A single tap-to-place would be quicker
/// and would put you right back to finding out where it went afterwards.

/// Pick something to put down.
struct BuildPickerBar: View {
    @Bindable var game: GameViewModel
    @Binding var plan: BuildPlan?
    var onClose: () -> Void

    private var cs: Bool { AppStrings.language == .cs }
    private func s(_ en: String, _ cz: String) -> String { cs ? cz : en }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(s("What to build", "Co postavit"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.text)
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(Theme.textDim)
                }
                .accessibilityLabel(s("Close", "Zavřít"))
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(game.placeableBuildings, id: \.id) { def in
                        button(for: def)
                    }
                }
            }
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14)
            .strokeBorder(Theme.boneFaint.opacity(0.35), lineWidth: 1))
    }

    private func button(for def: BuildingDefinition) -> some View {
        let affordable = game.canAfford(def.cost) && game.hasMaterials(for: def)
        return Button {
            withAnimation(.easeOut(duration: 0.15)) {
                plan = BuildPlan(definitionID: def.id, coord: nil)
            }
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                Text(def.name.resolve(AppStrings.language))
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(affordable ? Theme.text : Theme.textDim)
                    .lineLimit(1)
                // **What it is for.** The picker offered a name and a footprint
                // and nothing else, so choosing between eleven buildings meant
                // already knowing what all eleven did. Every building in the
                // data carries a line; it was simply never shown.
                Text(Self.summary(of: def))
                    .font(.system(size: 9))
                    .foregroundStyle(Theme.textDim)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: 128, alignment: .leading)
                HStack(spacing: 6) {
                    // The footprint: how much ground this will cost you is the
                    // thing you most need to know before choosing where.
                    Text("\(def.footprint.width)×\(def.footprint.height)")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Theme.accent.opacity(affordable ? 0.9 : 0.4))
                    Text(Self.priceLine(of: def, naming: game.itemName))
                        .font(.system(size: 9, weight: .semibold).monospacedDigit())
                        .foregroundStyle(affordable ? Theme.textDim : Theme.danger)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Theme.bone.opacity(0.07), in: RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9)
                .strokeBorder(Theme.boneFaint.opacity(0.3), lineWidth: 0.8))
        }
        .buttonStyle(.plain)
        .opacity(affordable ? 1 : 0.55)
    }

    /// What a building is *for*, in a few words.
    ///
    /// Prefers the numbers that actually change the game — beds, store, what it
    /// produces — over the flavour line, because "stores grain against the lean
    /// months" does not tell you it lifts the cap on every resource by 250.
    /// Falls back to the flavour when a building has no numbers to show.
    static func summary(of def: BuildingDefinition) -> String {
        let cs = AppStrings.language == .cs
        var parts: [String] = []
        if def.housing > 0 {
            parts.append("+\(Int(def.housing)) \(cs ? "lůžek" : "beds")")
        }
        if def.storage > 0 {
            parts.append("+\(Int(def.storage)) \(cs ? "skladu" : "store")")
        }
        for resource in ResourceType.allCases where def.production[resource] > 0 {
            parts.append("+\(Int(def.production[resource])) \(resource.displayName)")
        }
        if def.defense > 0 {
            parts.append("+\(Int(def.defense)) \(cs ? "obrany" : "defence")")
        }
        if def.workers > 0 {
            parts.append("\(def.workers) \(cs ? "prac." : "workers")")
        }
        guard parts.isEmpty else { return parts.joined(separator: " · ") }
        return def.description.resolve(AppStrings.language)
    }

    /// What it costs, with anything the colony is short of named.
    static func priceLine(
        of def: BuildingDefinition, naming itemName: (String) -> String
    ) -> String {
        var parts: [String] = []
        for resource in ResourceType.allCases where def.cost[resource] > 0 {
            parts.append("\(Int(def.cost[resource])) \(resource.displayName)")
        }
        for (materialID, count) in def.materialCost.sorted(by: { $0.key < $1.key }) {
            parts.append("\(count)× \(itemName(materialID))")
        }
        return parts.joined(separator: ", ")
    }
}

/// Aim, then commit.
struct BuildPlacementBar: View {
    @Bindable var game: GameViewModel
    @Binding var plan: BuildPlan?

    private var cs: Bool { AppStrings.language == .cs }
    private func s(_ en: String, _ cz: String) -> String { cs ? cz : en }

    private var definition: BuildingDefinition? {
        plan.flatMap { game.buildingDefinition($0.definitionID) }
    }

    /// Whether the ghost is standing somewhere it can actually go.
    private var fits: Bool {
        guard let plan, let coord = plan.coord,
              let settlement = game.selectedSettlement else { return false }
        return ColonyBuilder.canPlace(settlement, definitionID: plan.definitionID,
                                      at: coord, registry: game.registry)
    }

    private var affordable: Bool {
        guard let definition else { return false }
        return game.canAfford(definition.cost) && game.hasMaterials(for: definition)
    }

    /// One line saying exactly why the button is off, rather than a dead button.
    private var blocker: String? {
        guard let plan else { return nil }
        if plan.coord == nil { return s("Tap the ground to place it", "Ťukni na zem, kam ji chceš") }
        if !fits { return s("It doesn't fit here", "Sem se nevejde") }
        guard let definition else { return nil }
        if !game.canAfford(definition.cost) { return s("Not enough in the stores", "Ve skladu to není") }
        if !game.hasMaterials(for: definition) {
            return game.materialCostSummary(definition) ?? s("Missing goods", "Chybí zboží")
        }
        return nil
    }

    var body: some View {
        if let plan, let definition {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text(definition.name.resolve(AppStrings.language))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.text)
                    Text("\(definition.footprint.width)×\(definition.footprint.height)")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                    Spacer()
                    if let coord = plan.coord {
                        Text("\(coord.x), \(coord.y)")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(Theme.textDim)
                    }
                }
                if let blocker {
                    Label(blocker, systemImage: plan.coord == nil ? "hand.tap" : "exclamationmark.triangle")
                        .font(.system(size: 11))
                        .foregroundStyle(plan.coord == nil ? Theme.textDim : Theme.danger)
                }
                HStack(spacing: 8) {
                    Button {
                        withAnimation(.easeOut(duration: 0.15)) { self.plan = nil }
                    } label: {
                        Text(s("Cancel", "Zrušit"))
                            .font(.caption)
                            .foregroundStyle(Theme.textDim)
                            .padding(.horizontal, 14).padding(.vertical, 8)
                            .background(Theme.bone.opacity(0.07), in: Capsule())
                    }
                    .buttonStyle(.plain)

                    Button {
                        guard let coord = plan.coord else { return }
                        game.placeBuilding(plan.definitionID, at: coord)
                        withAnimation(.easeOut(duration: 0.15)) { self.plan = nil }
                    } label: {
                        Text(s("Build here", "Postavit sem"))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.ink)
                            .padding(.horizontal, 16).padding(.vertical, 8)
                            .background(Theme.accent, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(plan.coord == nil || !fits || !affordable)
                    .opacity(plan.coord == nil || !fits || !affordable ? 0.45 : 1)
                }
            }
            .padding(12)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Theme.boneFaint.opacity(0.35), lineWidth: 1))
        }
    }
}
