import SwiftUI
import EndlessFrontierCore

/// The in-settlement base layer: see your colony's layout on a tile grid,
/// build and demolish, and put named colonists to work on specific buildings.
/// This is the spatial RimWorld-style surface the art pass will later render
/// with real sprites instead of SF Symbols.
struct ColonyMapScreen: View {
    @Bindable var game: GameViewModel

    enum Mode: String, CaseIterable, Identifiable {
        case inspect = "Inspect"
        case build = "Build"
        case demolish = "Demolish"
        var id: String { rawValue }
    }

    @State private var mode: Mode = .inspect
    @State private var selectedBuilding: String?
    @State private var selectedCoord: TileCoord?

    /// The grid to render — a default empty one until the player first builds.
    private var colony: ColonyMap { game.viewedColony ?? ColonyMap() }

    var body: some View {
        ZStack {
            Theme.surface.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    SettlementPicker(game: game)
                    modePicker
                    if mode == .build { buildPalette }
                    gridCard
                    if let coord = selectedCoord, let placement = colony.placement(at: coord) {
                        inspector(placement)
                    }
                }
                .padding(20)
            }
        }
        .foregroundStyle(Theme.text)
    }

    // MARK: - Header & mode

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Base").font(.system(.largeTitle, design: .serif).weight(.bold))
            Text("Lay out your colony and put colonists to work.")
                .font(.subheadline).foregroundStyle(Theme.textDim)
        }
    }

    private var modePicker: some View {
        Picker("Mode", selection: $mode) {
            ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
        }
        .pickerStyle(.segmented)
    }

    // MARK: - Build palette

    private var buildPalette: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Choose a building")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(game.placeableBuildings) { def in
                        Button { selectedBuilding = def.id } label: { paletteCell(def) }
                            .buttonStyle(.plain)
                    }
                }
            }
        }
        .frontierCard()
    }

    private func paletteCell(_ def: BuildingDefinition) -> some View {
        let isSelected = selectedBuilding == def.id
        return VStack(spacing: 4) {
            Image(systemName: buildingIcon(def)).font(.title3)
            Text(def.name).font(.caption2.weight(.medium)).lineLimit(1)
            Text(costSummary(def.cost)).font(.caption2).foregroundStyle(Theme.textDim)
        }
        .frame(width: 96)
        .padding(.vertical, 10)
        .background(isSelected ? Theme.accent.opacity(0.22) : Theme.surfaceInset,
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(isSelected ? Theme.accent : Color.clear, lineWidth: 1)
        )
        .foregroundStyle(game.canAfford(def.cost) ? Theme.text : Theme.textDim)
    }

    // MARK: - Grid

    private var gridCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SectionHeader(title: "Layout")
                Spacer()
                Text("\(colony.placements.count) built · \(colony.freeTiles) free")
                    .font(.caption).foregroundStyle(Theme.textDim)
            }
            ScrollView(.horizontal, showsIndicators: false) { grid }
            Text(hint).font(.caption).foregroundStyle(Theme.textDim)
        }
        .frontierCard()
    }

    private var grid: some View {
        VStack(spacing: 3) {
            ForEach(Array(0..<colony.height), id: \.self) { y in
                HStack(spacing: 3) {
                    ForEach(Array(0..<colony.width), id: \.self) { x in
                        tile(TileCoord(x, y))
                    }
                }
            }
        }
    }

    private func tile(_ coord: TileCoord) -> some View {
        let placement = colony.placement(at: coord)
        let isSelected = selectedCoord == coord
        return RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(placement == nil ? Theme.surfaceInset : Theme.surfaceRaised)
            .frame(width: 26, height: 26)
            .overlay {
                if let placement, let def = game.buildingDefinition(placement.definitionID) {
                    Image(systemName: buildingIcon(def))
                        .font(.system(size: 12))
                        .foregroundStyle(tileColor(placement))
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .strokeBorder(isSelected ? Theme.accent : Color.white.opacity(0.05),
                                  lineWidth: isSelected ? 2 : 1)
            }
            .onTapGesture { tap(coord) }
            .accessibilityLabel(tileAccessibility(coord, placement))
    }

    // MARK: - Inspector

    private func inspector(_ placement: BuildingPlacement) -> some View {
        let def = game.buildingDefinition(placement.definitionID)
        return VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: def?.name ?? placement.definitionID)
            if let def {
                if !def.description.isEmpty {
                    Text(def.description).font(.caption).foregroundStyle(Theme.textDim)
                }
                let work = ColonyBuilder.workKind(for: def)
                HStack {
                    Label(work == .idle ? "Unstaffed" : work.rawValue.capitalized, systemImage: "person.fill")
                    Spacer()
                    Text("\(placement.assignedPawnIDs.count)/\(def.workers) workers")
                        .foregroundStyle(Theme.textDim)
                }
                .font(.caption)
            }

            ForEach(placement.assignedPawnIDs, id: \.self) { pid in
                HStack(spacing: 8) {
                    Image(systemName: "person.fill").foregroundStyle(Theme.good)
                    Text(game.pawnName(pid)).font(.subheadline)
                    Spacer()
                    Button("Remove") { game.unassignPawn(pid) }
                        .font(.caption).buttonStyle(.plain).foregroundStyle(Theme.danger)
                }
            }

            if let def, def.workers > 0 {
                Menu {
                    ForEach(game.viewedPawns) { pawn in
                        Button {
                            game.assignPawn(pawn.id, toPlacement: placement.id)
                        } label: {
                            Label(pawn.name,
                                  systemImage: placement.assignedPawnIDs.contains(pawn.id) ? "checkmark" : "person")
                        }
                    }
                } label: {
                    Label("Assign colonist", systemImage: "plus.circle.fill")
                        .font(.subheadline.weight(.medium)).foregroundStyle(Theme.accent)
                }
            }
        }
        .frontierCard()
    }

    // MARK: - Interaction

    private func tap(_ coord: TileCoord) {
        switch mode {
        case .inspect:
            selectedCoord = colony.placement(at: coord) != nil ? coord : nil
        case .build:
            if let id = selectedBuilding { game.placeBuilding(id, at: coord) }
        case .demolish:
            game.demolish(at: coord)
            if selectedCoord == coord { selectedCoord = nil }
        }
    }

    private var hint: String {
        switch mode {
        case .inspect:
            return "Tap a building to see who works there and assign colonists."
        case .build:
            guard let id = selectedBuilding else { return "Pick a building above, then tap an empty tile." }
            return "Tap an empty tile to build \(game.buildingName(id))."
        case .demolish:
            return "Tap a building to tear it down."
        }
    }

    // MARK: - Presentation helpers

    private func buildingIcon(_ def: BuildingDefinition) -> String {
        if def.housing > 0 { return "house.fill" }
        if def.defense > 0 { return "shield.lefthalf.filled" }
        switch ColonyBuilder.workKind(for: def) {
        case .farming: return "leaf.fill"
        case .logging: return "tree.fill"
        case .mining: return "mountain.2.fill"
        case .research: return "book.fill"
        case .trade: return "bag.fill"
        case .idle: return def.production[.energy] > 0 ? "bolt.fill" : "building.2.fill"
        }
    }

    private func tileColor(_ placement: BuildingPlacement) -> Color {
        guard let def = game.buildingDefinition(placement.definitionID) else { return Theme.textDim }
        if def.workers == 0 { return Theme.textDim }
        return placement.assignedPawnIDs.isEmpty ? Theme.accent : Theme.good
    }

    private func costSummary(_ cost: Resources) -> String {
        let parts = ResourceType.allCases
            .filter { cost[$0] > 0 }
            .map { "\(Int(cost[$0])) \($0.displayName.lowercased())" }
        return parts.isEmpty ? "Free" : parts.joined(separator: ", ")
    }

    private func tileAccessibility(_ coord: TileCoord, _ placement: BuildingPlacement?) -> String {
        if let placement, let def = game.buildingDefinition(placement.definitionID) {
            return "\(def.name), \(placement.assignedPawnIDs.count) workers"
        }
        return "Empty tile \(coord.x), \(coord.y)"
    }
}
