import SwiftUI
import EndlessFrontierCore

/// The in-settlement build grid — reworked around **one** interaction model
/// instead of four modes behind a segmented picker:
///
/// - Tap any building → its card (workers, synergies, **demolish** lives there).
/// - Pick something from the palette (buildings *and* zones in one strip) →
///   the grid shows where it fits and a single tap places it. Tap the picked
///   chip again to put it down.
/// - Multi-tile buildings preview their whole footprint; construction sites
///   show a hammer and their progress.
///
/// The grid's centre is the settlement heart on the living canvas, and
/// placement now grows from there (see `ColonyBuilder.centerFit`).
struct ColonyMapScreen: View {
    @Bindable var game: GameViewModel

    /// What the next tap on the grid will lay down, if anything.
    private enum Brush: Equatable {
        case building(String)
        case zone(ZoneKind)
    }

    @State private var brush: Brush?
    @State private var selectedCoord: TileCoord?

    private var cs: Bool { AppStrings.language == .cs }
    private func s(_ en: String, _ cz: String) -> String { cs ? cz : en }

    /// The grid to render — a default empty one until the player first builds.
    private var colony: ColonyMap { game.viewedColony ?? ColonyMap() }

    var body: some View {
        ZStack {
            Theme.surface.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    SettlementPicker(game: game)
                    palette
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

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(s("Base", "Osada"))
                .font(.system(.largeTitle, design: .serif).weight(.bold))
            Text(s("Tap a building to inspect it. Pick from the palette, then tap the grid to build.",
                   "Ťukni na budovu pro detail. Vyber z palety a ťukni do mřížky pro stavbu."))
                .font(.subheadline).foregroundStyle(Theme.textDim)
        }
    }

    // MARK: - One palette: buildings and zones together

    private var palette: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionHeader(title: s("Build", "Stavět"))
                Spacer()
                if brush != nil {
                    Button {
                        withAnimation(.easeOut(duration: 0.15)) { brush = nil }
                    } label: {
                        Label(s("Done", "Hotovo"), systemImage: "xmark.circle.fill")
                            .font(.caption.weight(.semibold))
                    }
                    .tint(Theme.accent)
                }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(game.placeableBuildings) { def in
                        Button {
                            toggle(.building(def.id))
                        } label: { paletteCell(def) }
                            .buttonStyle(.plain)
                    }
                    Divider().frame(height: 60)
                    ForEach(ZoneKind.allCases, id: \.self) { kind in
                        Button {
                            toggle(.zone(kind))
                        } label: { zoneCell(kind) }
                            .buttonStyle(.plain)
                    }
                }
            }
        }
        .frontierCard()
    }

    private func toggle(_ new: Brush) {
        withAnimation(.easeOut(duration: 0.15)) {
            brush = (brush == new) ? nil : new
            selectedCoord = nil
        }
    }

    private func paletteCell(_ def: BuildingDefinition) -> some View {
        let isSelected = brush == .building(def.id)
        let multiTile = def.footprint.width > 1 || def.footprint.height > 1
        return VStack(spacing: 4) {
            Image(systemName: buildingIcon(def)).font(.title3)
            Text(def.name.resolve(AppStrings.language)).font(.caption2.weight(.medium)).lineLimit(1)
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

    private func zoneCell(_ kind: ZoneKind) -> some View {
        let isSelected = brush == .zone(kind)
        return VStack(spacing: 4) {
            Image(systemName: zoneIcon(kind)).font(.title3)
            Text(zoneName(kind)).font(.caption2.weight(.medium))
            Text(s("morale", "morálka")).font(.caption2).foregroundStyle(Theme.textDim)
        }
        .frame(width: 76)
        .padding(.vertical, 10)
        .background(isSelected ? zoneColor(kind).opacity(0.25) : Theme.surfaceInset,
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(isSelected ? zoneColor(kind) : Color.clear, lineWidth: 1)
        )
        .foregroundStyle(isSelected ? zoneColor(kind) : Theme.text)
    }

    // MARK: - Grid

    private var gridCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SectionHeader(title: s("Layout", "Plán"))
                Spacer()
                Text("\(colony.placements.count) \(s("built", "staveb")) · \(colony.freeTiles) \(s("free", "volných"))")
                    .font(.caption).foregroundStyle(Theme.textDim)
            }
            ScrollView(.horizontal, showsIndicators: false) { grid }
            if let synergySummary {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles").foregroundStyle(Theme.good)
                    Text("\(s("Synergies", "Synergie")): \(synergySummary)")
                        .font(.caption).foregroundStyle(Theme.good)
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
        if morale != 0 { parts.append("+\(Int(morale)) \(s("morale", "morálka"))") }
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

    /// Whether the selected building's footprint would fit with its top-left
    /// on this tile — the grid literally shows where a tap can land.
    private func brushFits(at coord: TileCoord) -> Bool {
        guard case let .building(id) = brush else { return false }
        return ColonyBuilder.canPlace(game.selectedSettlement ?? Settlement(name: "", kind: .capital),
                                      definitionID: id, at: coord, registry: game.registry)
    }

    /// The construction project standing on this placement, if any.
    private func project(for placement: BuildingPlacement) -> ConstructionProject? {
        game.selectedSettlement?.constructions.first { $0.placementID == placement.id }
    }

    private func tile(_ coord: TileCoord) -> some View {
        let placement = colony.placement(at: coord)
        let isOrigin = placement?.coord == coord
        let zone = colony.zoneKind(at: coord)
        let isSelected = placement != nil && placement?.coord == selectedCoord
        let isHeart = abs(coord.x - colony.width / 2) <= 0 && abs(coord.y - colony.height / 2) <= 0
        let placeable = brush != nil && placement == nil && brushFits(at: coord)
        let underConstruction = placement?.underConstruction == true

        let baseFill: Color = {
            if placement != nil { return Theme.surfaceRaised }
            if placeable { return Theme.good.opacity(0.14) }
            if let zone { return zoneColor(zone).opacity(0.30) }
            return Theme.surfaceInset
        }()
        return RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(baseFill)
            .frame(width: 26, height: 26)
            .overlay {
                if isOrigin, let placement, let def = game.buildingDefinition(placement.definitionID) {
                    if underConstruction {
                        VStack(spacing: 0) {
                            Image(systemName: "hammer.fill")
                                .font(.system(size: 9))
                                .foregroundStyle(Theme.accent)
                            if let project = project(for: placement) {
                                Text("\(Int(project.fraction * 100))")
                                    .font(.system(size: 6).monospacedDigit())
                                    .foregroundStyle(Theme.textDim)
                            }
                        }
                    } else {
                        Image(systemName: buildingIcon(def))
                            .font(.system(size: 12))
                            .foregroundStyle(tileColor(placement))
                    }
                } else if placement == nil, let zone {
                    Image(systemName: zoneIcon(zone))
                        .font(.system(size: 9))
                        .foregroundStyle(zoneColor(zone))
                } else if placement == nil, isHeart {
                    // The settlement heart — this is the middle of the living
                    // canvas, so the player knows where "downtown" is.
                    Image(systemName: "plus")
                        .font(.system(size: 8))
                        .foregroundStyle(Theme.boneFaint)
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .strokeBorder(
                        isSelected ? Theme.accent
                            : (underConstruction ? Theme.accent.opacity(0.5)
                               : (placeable ? Theme.good.opacity(0.4) : Color.white.opacity(0.05))),
                        style: StrokeStyle(lineWidth: isSelected ? 2 : 1,
                                           dash: underConstruction ? [3, 2] : []))
            }
            .onTapGesture { tap(coord) }
            .accessibilityLabel(tileAccessibility(coord, placement))
    }

    // MARK: - Inspector (demolish lives here — no demolish "mode")

    private func inspector(_ placement: BuildingPlacement) -> some View {
        let def = game.buildingDefinition(placement.definitionID)
        let project = project(for: placement)
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionHeader(title: def?.name.resolve(AppStrings.language) ?? placement.definitionID)
                Spacer()
                Button(role: .destructive) {
                    game.demolish(at: placement.coord)
                    selectedCoord = nil
                } label: {
                    Label(placement.underConstruction
                          ? s("Cancel site", "Zrušit stavbu")
                          : s("Demolish", "Zbourat"),
                          systemImage: "trash.fill")
                        .font(.caption.weight(.semibold))
                }
                .tint(Theme.danger)
            }
            if let project {
                VStack(alignment: .leading, spacing: 4) {
                    Text(s("Under construction", "Ve výstavbě") + " · \(Int(project.fraction * 100)) %")
                        .font(.caption).foregroundStyle(Theme.accent)
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Theme.surfaceInset)
                            Capsule().fill(Theme.accent.opacity(0.85))
                                .frame(width: geo.size.width * CGFloat(project.fraction))
                        }
                    }
                    .frame(height: 4)
                }
            }
            if let def {
                let flavour = def.description.resolve(AppStrings.language)
                if !flavour.isEmpty {
                    Text(flavour).font(.caption).foregroundStyle(Theme.textDim)
                }
                let work = ColonyBuilder.workKind(for: def)
                HStack {
                    Label(work == .idle ? s("Unstaffed", "Bez obsluhy") : AppStrings.roleName(work),
                          systemImage: "person.fill")
                    Spacer()
                    Text("\(placement.assignedPawnIDs.count)/\(def.workers) \(s("workers", "pracovníků"))")
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
                    Button(s("Remove", "Odebrat")) { game.unassignPawn(pid) }
                        .font(.caption).buttonStyle(.plain).foregroundStyle(Theme.danger)
                }
            }

            if let def, def.workers > 0, !placement.underConstruction {
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
                    Label(s("Assign colonist", "Přidělit kolonistu"), systemImage: "plus.circle.fill")
                        .font(.subheadline.weight(.medium)).foregroundStyle(Theme.accent)
                }
            }
        }
        .frontierCard()
    }

    // MARK: - Interaction: one tap, no modes

    private func tap(_ coord: TileCoord) {
        // A building under the finger always answers first.
        if let placement = colony.placement(at: coord) {
            withAnimation(.easeOut(duration: 0.15)) {
                selectedCoord = (selectedCoord == placement.coord) ? nil : placement.coord
            }
            return
        }
        switch brush {
        case let .building(id):
            game.placeBuilding(id, at: coord)
        case let .zone(kind):
            if colony.zoneKind(at: coord) == kind {
                game.eraseZone(at: coord)
            } else {
                game.paintZone(kind, at: coord)
            }
        case nil:
            withAnimation(.easeOut(duration: 0.15)) { selectedCoord = nil }
        }
    }

    private var hint: String {
        switch brush {
        case let .building(id):
            let def = game.buildingDefinition(id)
            let size = def.map { "\($0.footprint.width)×\($0.footprint.height)" } ?? "1×1"
            return s("Green tiles fit a \(game.buildingName(id)) (\(size)). Tap one to break ground.",
                     "Zelená políčka: sem se vejde \(game.buildingName(id)) (\(size)). Ťukni a začne stavba.")
        case .zone:
            return s("Tap tiles to paint the zone; tap again to clear. Zones lift morale — a plaza becomes the town square.",
                     "Ťukáním maluj zónu; dalším ťuknutím ji smažeš. Zóny zvedají morálku — náves se stane středem dění.")
        case nil:
            return s("Tap a building for its card (workers, demolish). The + marks the settlement heart.",
                     "Ťukni na budovu pro kartu (pracovníci, bourání). Křížek značí srdce osady.")
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
        case .foraging: return "camera.macro"
        case .hunting: return "hare.fill"
        case .healing: return "cross.case.fill"
        case .building: return "hammer.fill"
        case .scouting: return "binoculars.fill"
        case .priest: return "sparkles"
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

    private func zoneName(_ kind: ZoneKind) -> String {
        switch kind {
        case .park: return s("Park", "Park")
        case .plaza: return s("Plaza", "Náves")
        case .garden: return s("Garden", "Zahrada")
        }
    }

    private func costSummary(_ cost: Resources) -> String {
        let parts = ResourceType.allCases
            .filter { cost[$0] > 0 }
            .map { "\(Int(cost[$0])) \($0.displayName.lowercased())" }
        return parts.isEmpty ? s("Free", "Zdarma") : parts.joined(separator: ", ")
    }

    private func tileAccessibility(_ coord: TileCoord, _ placement: BuildingPlacement?) -> String {
        if let placement, let def = game.buildingDefinition(placement.definitionID) {
            return "\(def.name), \(placement.assignedPawnIDs.count) \(s("workers", "pracovníků"))"
        }
        if let zone = colony.zoneKind(at: coord) {
            return "\(zoneName(zone)), \(coord.x), \(coord.y)"
        }
        return s("Empty tile", "Volné políčko") + " \(coord.x), \(coord.y)"
    }
}
