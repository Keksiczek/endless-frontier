import SwiftUI
import EndlessFrontierCore

/// The heart of V2: a living settlement you watch and steer. The canvas is the
/// hero; a slim status strip sits above it and the full colony controls live in
/// a swipe-up detail drawer, so the scene stays calm and legible.
struct SettlementScreen: View {
    @Bindable var game: GameViewModel
    @State private var selection: CanvasSelection = .none
    /// What the player is placing, if anything. Set from the picker; the canvas
    /// turns into the build surface while it holds a value.
    @State private var buildPlan: BuildPlan?
    /// Whether the "what to build" strip is showing.
    @State private var picking = false
    /// The fight the player asked to see again, and when they asked. Held here
    /// rather than in the view model because it is a *viewing* state: nothing
    /// about the world changes when you rewatch a battle.
    @State private var battleReplay: SettlementBattle.Replay?

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
        // A raid runs on its own, much faster clock while somebody is here to
        // answer it. Starting the driver is *all* this does — the fight itself
        // is the simulation's, and it happens whether or not this screen is up.
        .onChange(of: game.siege?.id) { _, id in
            if id != nil { game.startSiegeLoop() } else { game.stopSiegeLoop() }
        }
        .onAppear { if game.siege != nil { game.startSiegeLoop() } }
        .onDisappear { game.stopSiegeLoop() }
    }

    private var canvasArea: some View {
        ZStack {
            if let map = game.viewedLocalMap, let settlement = game.selectedSettlement {
                SettlementCanvasView(
                    settlement: settlement, map: map, registry: game.registry,
                    season: game.season, caravans: game.world.caravans,
                    clock: game.tickClock, selection: $selection,
                    buildPlan: $buildPlan, battleReplay: battleReplay,
                    onSiegeOrder: { game.command($0) })
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
            // Laying a building out owns the screen while it is happening: the
            // ghost on the canvas and this bar are one interaction.
            // A raid outranks everything. It is happening now, it is happening
            // to you, and it is the one thing on this screen with a clock on
            // it — laying out a granary can wait.
            if let siege = game.siege {
                SiegeCommandCard(
                    siege: siege, defenders: siegeDefenders(siege),
                    onPosture: { game.order(posture: $0) },
                    onToggle: { game.setInLine($0, holding: $1) })
                .transition(.move(edge: .bottom).combined(with: .opacity))
            } else if buildPlan != nil {
                BuildPlacementBar(game: game, plan: $buildPlan)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            } else if picking {
                BuildPickerBar(game: game, plan: $buildPlan) {
                    withAnimation(.easeOut(duration: 0.15)) { picking = false }
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            } else if let decision = game.currentDecision {
                EventDecisionCard(game: game, template: decision,
                                  queued: max(0, game.pendingEvents.count - 1))
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            } else if let battle = game.battleReport {
                // A fight just happened here — show what it cost before idle
                // curiosity about the scene.
                BattleReportCard(
                    battle: battle,
                    onReplay: { battleReplay = SettlementBattle.Replay(log: battle) },
                    onClose: {
                        withAnimation(.easeOut(duration: 0.15)) { game.dismissBattleReport() }
                    })
                .transition(.move(edge: .bottom).combined(with: .opacity))
            } else if let pawn = selectedPawn {
                PawnInspectorCard(pawn: pawn, ticksPerYear: game.ticksPerYear,
                                  activity: activityLine(for: pawn),
                                  bonds: bondLines(for: pawn),
                                  moodFactors: MoodLedger.factors(for: pawn,
                                                                  registry: game.registry),
                                  housed: pawn.homeID != nil,
                                  store: game.equippableStore,
                                  definitionOf: { game.itemDefinition($0) },
                                  onEquip: { game.equip($0, toPawn: pawn.id) },
                                  onUnequip: { game.unequip(pawn.id, slot: $0) }) {
                    withAnimation(.easeOut(duration: 0.15)) { selection = .none }
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            } else if case let .poi(id) = selection, let poi = game.poi(id) {
                let party = game.expedition(forPOI: id)
                POIInspectorCard(
                    poi: poi, ticksPerYear: game.ticksPerYear, tick: game.world.tick,
                    expedition: party,
                    partyNames: party.map { game.partyNames($0) } ?? [],
                    canDispatch: game.canDispatch(to: poi),
                    onDispatch: { game.dispatchToPOI(id) },
                    onClose: {
                        withAnimation(.easeOut(duration: 0.15)) { selection = .none }
                    })
                .transition(.move(edge: .bottom).combined(with: .opacity))
            } else if case let .animal(id) = selection, let found = game.animal(id) {
                AnimalInspectorCard(animal: found.animal, kept: found.kept) {
                    withAnimation(.easeOut(duration: 0.15)) { selection = .none }
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            } else if case let .fog(point) = selection {
                ScoutOrderCard(scouts: game.scoutCount) {
                    game.sendScouts(to: point)
                    withAnimation(.easeOut(duration: 0.15)) { selection = .none }
                } onClose: {
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
        .animation(.easeOut(duration: 0.25), value: game.battleReport?.id)
    }

    /// A button label that will not wrap: one line, allowed to shrink, and on a
    /// genuinely narrow screen the word drops away and the icon carries it.
    private func compactLabel(_ text: String, icon: String) -> some View {
        ViewThatFits(in: .horizontal) {
            Label(text, systemImage: icon)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .fixedSize()
            Image(systemName: icon)
                .font(.subheadline.weight(.semibold))
                .accessibilityLabel(text)
        }
    }

    private var controlBar: some View {
        // Four controls in one capsule is more than a phone's width holds with
        // words on all of them: on a real device this wrapped into "St av ět"
        // and "De tail y". Everything here now refuses to wrap and shrinks
        // instead, and the two secondary actions keep only their icon on the
        // narrowest screens.
        HStack(spacing: 8) {
            if let settlement = game.selectedSettlement {
                Label("\(settlement.pawns.count)/\(game.housingCapacity(settlement))",
                      systemImage: "person.2.fill")
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                    .fixedSize()
            }
            Spacer(minLength: 4)
            // The build grid was written, tested and then never reachable —
            // nothing anywhere constructed ColonyMapScreen, so the layout, its
            // zones and every adjacency synergy the loop computes each tick
            // were invisible.
            // Building happens *here*, on the colony you are looking at — the
            // abstract grid screen is still one tap further in for the fiddly
            // work (zones, per-building staffing), but choosing where a roof
            // goes should never have needed a second picture of the town.
            Button {
                withAnimation(.easeOut(duration: 0.15)) {
                    if buildPlan != nil { buildPlan = nil } else { picking.toggle() }
                }
            } label: {
                compactLabel(AppStrings.language == .cs ? "Stavět" : "Build",
                             icon: "hammer.fill")
            }
            .buttonStyle(.bordered)
            .tint(picking || buildPlan != nil ? Theme.accent : Theme.text)
            Button {
                drawer = .layout
            } label: {
                // The layout screen is the least-reached of the four, so it is
                // the one that gives up its word first.
                Image(systemName: "square.grid.3x3.fill")
                    .font(.subheadline.weight(.semibold))
                    .accessibilityLabel(AppStrings.layout)
            }
            .buttonStyle(.bordered)
            .tint(Theme.text)
            Button {
                drawer = .details
            } label: {
                compactLabel(AppStrings.details, icon: "slider.horizontal.3")
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)
        }
        .padding(.horizontal, 12)
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

    /// The line, resolved to people the card can name and show the state of.
    private func siegeDefenders(_ siege: Siege) -> [SiegeCommandCard.Defender] {
        guard let settlement = game.selectedSettlement else { return [] }
        return siege.line.compactMap { id in
            guard let pawn = settlement.pawns.first(where: { $0.id == id }) else { return nil }
            return SiegeCommandCard.Defender(
                id: id, name: pawn.name,
                condition: max(0, min(1, pawn.health / 100)),
                holding: !siege.withdrawn.contains(id))
        }
    }

    private var selectedPawn: Pawn? {
        guard case let .pawn(id) = selection else { return nil }
        return game.selectedSettlement?.pawns.first { $0.id == id }
    }

    /// The "right now" line: the same clock and scene the canvas draws from,
    /// so the card says what the figure is visibly doing.
    private func activityLine(for pawn: Pawn) -> String? {
        guard let map = game.viewedLocalMap, let settlement = game.selectedSettlement else { return nil }
        let scene = AgentMotion.Scene(settlement: settlement, registry: game.registry,
                                      continuousTick: game.continuousTick())
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
