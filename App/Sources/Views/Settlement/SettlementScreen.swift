import SwiftUI
import EndlessFrontierCore

/// The heart of V2: a living settlement you watch and steer. The canvas is the
/// hero; a slim status strip sits above it and the full colony controls live in
/// a swipe-up detail drawer, so the scene stays calm and legible.
struct SettlementScreen: View {
    @Bindable var game: GameViewModel
    @State private var selection: CanvasSelection = .none

    /// Which drawer is open, if any.
    ///
    /// These used to be three separate `.sheet` modifiers stacked on one view.
    /// SwiftUI honours exactly one — the rest are dropped, logging "only
    /// presenting a single sheet is supported" and, from the player's side,
    /// simply not opening when tapped. A screen where buttons sometimes do
    /// nothing is worse than one that's missing them.
    private enum Drawer: String, Identifiable {
        case layout, details
        var id: String { rawValue }
    }
    @State private var drawer: Drawer?

    var body: some View {
        ZStack {
            Theme.ink.ignoresSafeArea()
            VStack(spacing: 0) {
                StatusStrip(game: game)
                canvasArea
            }
        }
        .foregroundStyle(Theme.text)
        .sheet(item: $drawer) { which in
            switch which {
            case .layout:
                NavigationStack {
                    ColonyMapScreen(game: game)
                        .navigationTitle(AppStrings.layout)
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button(AppStrings.done) { drawer = nil }
                            }
                        }
                }
                .presentationBackground(Theme.surface)
            case .details:
                SettlementDetailSheet(game: game)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
                    .presentationBackground(Theme.surface)
            }
        }
        // The "while you were away" summary is a full-screen cover rather than
        // a second sheet: it belongs to arriving, not to browsing, and stacking
        // it as a sheet is what made the other two unreliable.
        .fullScreenCover(isPresented: summaryBinding) {
            WhileAwayView(events: game.lastSessionEvents, registry: game.registry) {
                game.dismissSessionSummary()
            }
        }
    }

    private var canvasArea: some View {
        ZStack {
            if let map = game.viewedLocalMap, let settlement = game.selectedSettlement {
                SettlementCanvasView(
                    settlement: settlement, map: map, registry: game.registry,
                    season: game.season, selection: $selection)
                .overlay(alignment: .topTrailing) {
                    MinimapView(map: map).padding(12)
                }
                .overlay(alignment: .top) { toastStack }
                .overlay(alignment: .bottom) { bottomLayer }
            } else {
                emptyState
            }
        }
    }

    /// Passing notes from the living world — a birth, a quarrel, a roof going
    /// on. They drift in at the top and take themselves away.
    private var toastStack: some View {
        VStack(spacing: 6) {
            ForEach(game.toasts) { toast in
                HStack(spacing: 8) {
                    Image(systemName: toast.icon)
                        .font(.caption)
                        .foregroundStyle(toastTint(toast))
                    Text(toast.text)
                        .font(.caption)
                        .foregroundStyle(Theme.text)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(Theme.boneFaint.opacity(0.35), lineWidth: 1))
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .padding(.top, 10)
        .padding(.horizontal, 60)   // clear of the minimap
        .frame(maxWidth: .infinity)
        .animation(.spring(duration: 0.35), value: game.toasts)
        .allowsHitTesting(false)
    }

    private func toastTint(_ toast: GameViewModel.LiveToast) -> Color {
        switch toast.kind {
        case .danger, .death: return Theme.danger
        case .birth, .social: return Theme.good
        case .discovery: return Theme.accent
        default: return Theme.textDim
        }
    }

    @ViewBuilder
    private var bottomLayer: some View {
        VStack(spacing: 10) {
            // A decision outranks idle curiosity about the scene.
            if let decision = game.currentDecision {
                EventDecisionCard(game: game, template: decision,
                                  queued: max(0, game.pendingEvents.count - 1))
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            } else if let pawn = selectedPawn {
                PawnInspectorCard(pawn: pawn, ticksPerYear: game.ticksPerYear,
                                  activity: activityLine(for: pawn),
                                  bonds: bondLines(for: pawn)) {
                    withAnimation(.easeOut(duration: 0.15)) { selection = .none }
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            } else if case let .landmark(text) = selection {
                HStack(spacing: 8) {
                    Image(systemName: "mappin.circle.fill")
                        .font(.caption)
                        .foregroundStyle(Theme.accent)
                    Text(text)
                        .font(.caption)
                        .foregroundStyle(Theme.text)
                    Button {
                        withAnimation(.easeOut(duration: 0.15)) { selection = .none }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(Theme.textDim)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial, in: Capsule())
                .transition(.move(edge: .bottom).combined(with: .opacity))
            } else if let building = selectedBuilding {
                BuildingInspectorCard(
                    definition: building.definition, standing: building.standing,
                    upkeep: building.upkeep,
                    synergies: game.synergyText(for: building.definition)
                ) {
                    withAnimation(.easeOut(duration: 0.15)) { selection = .none }
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            controlBar
        }
        .padding(12)
        .animation(.easeOut(duration: 0.2), value: game.pendingEvents.count)
    }

    private var controlBar: some View {
        HStack(spacing: 12) {
            if let settlement = game.selectedSettlement {
                Label("\(settlement.pawns.count)/\(game.housingCapacity(settlement))",
                      systemImage: "person.2.fill")
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(Theme.text)
            }
            Spacer()
            // The build grid was written, tested and then never reachable —
            // nothing anywhere constructed ColonyMapScreen, so the layout, its
            // zones and every adjacency synergy the loop computes each tick
            // were invisible.
            Button {
                drawer = .layout
            } label: {
                Label(AppStrings.layout, systemImage: "square.grid.3x3.fill")
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.bordered)
            .tint(Theme.text)
            Button {
                drawer = .details
            } label: {
                Label(AppStrings.details, systemImage: "slider.horizontal.3")
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.boneFaint.opacity(0.4), lineWidth: 1))
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label(AppStrings.language == .cs ? "Zakládá se osada" : "Founding a settlement",
                  systemImage: "sparkles")
        } description: {
            Text(AppStrings.language == .cs
                 ? "Svět se rodí — za okamžik tu bude živo."
                 : "The world is being born — life is moments away.")
        }
        .foregroundStyle(Theme.textDim)
    }

    private var selectedPawn: Pawn? {
        guard case let .pawn(id) = selection else { return nil }
        return game.selectedSettlement?.pawns.first { $0.id == id }
    }

    /// The "right now" line: the same clock and scene the canvas draws from,
    /// so the card says what the figure is visibly doing.
    private func activityLine(for pawn: Pawn) -> String? {
        guard let map = game.viewedLocalMap, let settlement = game.selectedSettlement else { return nil }
        let scene = AgentMotion.Scene(settlement: settlement, registry: game.registry)
        let pose = AgentMotion.pose(for: pawn, map: map, scene: scene,
                                    time: Date().timeIntervalSinceReferenceDate,
                                    ticksPerYear: game.ticksPerYear)
        return AgentMotion.activityLabel(pose.activity, work: pawn.assignedWork,
                                         cs: AppStrings.language == .cs)
    }

    /// The colonist's bonds, resolved to living names — spouse first, then the
    /// strongest of the rest.
    private func bondLines(for pawn: Pawn) -> [PawnInspectorCard.BondLine] {
        guard let settlement = game.selectedSettlement else { return [] }
        return settlement.relationships(of: pawn.id)
            .sorted {
                if ($0.kind == .partner) != ($1.kind == .partner) { return $0.kind == .partner }
                return $0.strength > $1.strength
            }
            .prefix(4)
            .compactMap { bond in
                guard let otherID = bond.other(than: pawn.id),
                      let other = settlement.pawns.first(where: { $0.id == otherID }) else { return nil }
                return PawnInspectorCard.BondLine(id: otherID, name: other.name, kind: bond.kind)
            }
    }

    /// The tapped structure, resolved to what the inspector needs to show.
    private var selectedBuilding: (definition: BuildingDefinition, standing: Int, upkeep: Resources)? {
        guard case let .building(_, definitionID) = selection,
              let definition = game.buildingDefinition(definitionID) else { return nil }
        let standing = game.selectedSettlement?.buildings
            .first { $0.definitionID == definitionID }?.count ?? 0
        return (definition, standing, game.upkeep(for: definition))
    }

    private var summaryBinding: Binding<Bool> {
        Binding(
            get: { !game.lastSessionEvents.isEmpty },
            set: { if !$0 { game.dismissSessionSummary() } }
        )
    }
}
