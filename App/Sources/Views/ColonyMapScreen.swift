import SwiftUI
import EndlessFrontierCore

/// The in-settlement base layer: see your colony's layout on a tile grid,
/// build (multi-tile footprints) and demolish, paint amenity zones, and put
/// named colonists to work on specific buildings. This is the spatial
/// RimWorld-style surface the art pass will later render with real sprites
/// instead of SF Symbols.
struct ColonyMapScreen: View {
    @Bindable var game: GameViewModel

    enum Mode: String, CaseIterable, Identifiable {
        case inspect = "Inspect"
        case build = "Build"
        case demolish = "Demolish"
        case zone = "Zone"
        var id: String { rawValue }
    }

    @State private var mode: Mode = .inspect
    @State private var selectedBuilding: String?
    @State private var selectedZone: ZoneKind = .park
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
                    if mode == .zone { zonePalette }
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
            Text("Lay out your colony, paint amenities, and put colonists to work.")
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
        let multiTile = def.footprint.width > 1 || def.footprint.height > 1
        return VStack(spacing: 4) {
            Image(systemName: buildingIcon(def)).font(.title3)
            Text(def.name).font(.caption2.weight(.medium)).lineLimit(1)
            Text(costSummary(def.cost)).font(.caption2).foregroundStyle(Theme.textDim)
            if multiTile {
                Text("\(def.footprint.width)×\(def.footprint.height)")
                    .font(.caption2.weight(.semibold)).foregroundStyle(Theme.accent)
            }
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

    // MARK: - Zone palette

    private var zonePalette: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Choose a zone")
            HStack(spacing: 10) {
                ForEach(ZoneKind.allCases, id: \.self) { kind in
                    Button { selectedZone = kind } label: {
                        HStack(spacing: 6) {
                            Image(systemName: zoneIcon(kind))
                            Text(kind.displayName).font(.caption.weight(.medium))
                        }
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(selectedZone == kind ? zoneColor(kind).opacity(0.25) : Theme.surfaceInset,
                                    in: Capsule())
                        .overlay(Capsule().strokeBorder(selectedZone == kind ? zoneColor(kind) : .clear, lineWidth: 1))
                        .foregroundStyle(selectedZone == kind ? zoneColor(kind) : Theme.text)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frontierCard()
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
            if let synergySummary {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles").foregroundStyle(Theme.good)
                    Text("Synergies: \(synergySummary)").font(.caption).foregroundStyle(Theme.good)
                }
            }
            Text(hint).font(.caption).foregroundStyle(Theme.textDim)
        }
        .frontierCard()
    }

    /// A one-line summary of the layout bonuses the current arrangement earns.
    private var synergySummary: String? {
        let production = game.viewedAdjacencyProduction
        let morale = game.viewedAdjacencyMorale
        var parts: [String] = []
        for resource in ResourceType.allCases where production[resource] != 0 {
            parts.append("+\(Int(production[resource])) \(resource.displayName.lowercased())")
        }
        if morale != 0 { parts.append("+\(Int(morale)) morale") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
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
        let isOrigin = placement?.coord == coord
        let zone = colony.zoneKind(at: coord)
        let isSelected = placement != nil && placement?.coord == selectedCoord
        let baseFill: Color = {
            if placement != nil { return Theme.surfaceRaised }
            if let zone { return zoneColor(zone).opacity(0.30) }
            return Theme.surfaceInset
        }()
        return RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(baseFill)
            .frame(width: 26, height: 26)
            .overlay {
                if isOrigin, let placement, let def = game.buildingDefinition(placement.definitionID) {
                    Image(systemName: buildingIcon(def))
                        .font(.system(size: 12))
                        .foregroundStyle(tileColor(placement))
                } else if placement == nil, let zone {
                    Image(systemName: zoneIcon(zone))
                        .font(.system(size: 9))
                        .foregroundStyle(zoneColor(zone))
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

                let synergies = game.synergyText(for: def)
                if !synergies.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(synergies, id: \.self) { line in
                            Label(line, systemImage: "sparkles")
                                .font(.caption2).foregroundStyle(Theme.textDim)
                        }
                    }
                }
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
            selectedCoord = colony.placement(at: coord)?.coord
        case .build:
            if let id = selectedBuilding { game.placeBuilding(id, at: coord) }
        case .demolish:
            game.demolish(at: coord)
            if let selected = selectedCoord, colony.placement(at: selected) == nil { selectedCoord = nil }
        case .zone:
            if colony.zoneKind(at: coord) == selectedZone {
                game.eraseZone(at: coord)
            } else {
                game.paintZone(selectedZone, at: coord)
            }
        }
    }

    private var hint: String {
        switch mode {
        case .inspect:
            return "Tap a building to see who works there and assign colonists."
        case .build:
            guard let id = selectedBuilding else { return "Pick a building above, then tap a tile for its top-left." }
            return "Tap a tile to build \(game.buildingName(id)) (its footprint fills down and right)."
        case .demolish:
            return "Tap a building to tear it down."
        case .zone:
            return "Tap tiles to paint a \(selectedZone.displayName) zone; tap again to clear it. Zones lift morale."
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

    private func zoneColor(_ kind: ZoneKind) -> Color {
        switch kind {
        case .park: return Theme.good
        case .plaza: return Theme.accent
        case .garden: return Color(red: 0.55, green: 0.74, blue: 0.45)
        }
    }

    private func zoneIcon(_ kind: ZoneKind) -> String {
        switch kind {
        case .park: return "tree.fill"
        case .plaza: return "building.columns.fill"
        case .garden: return "leaf.fill"
        }
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
        if let zone = colony.zoneKind(at: coord) {
            return "\(zone.displayName) zone, tile \(coord.x), \(coord.y)"
        }
        return "Empty tile \(coord.x), \(coord.y)"
    }
}
