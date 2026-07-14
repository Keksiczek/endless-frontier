import SwiftUI
import EndlessFrontierCore

/// The heart of V2: a living settlement you watch and steer. The canvas is the
/// hero; a slim status strip sits above it and the full colony controls live in
/// a swipe-up detail drawer, so the scene stays calm and legible.
struct SettlementScreen: View {
    @Bindable var game: GameViewModel
    @State private var selectedPawnID: UUID?
    @State private var showDetails = false

    var body: some View {
        ZStack {
            Theme.ink.ignoresSafeArea()
            VStack(spacing: 0) {
                StatusStrip(game: game)
                canvasArea
            }
        }
        .foregroundStyle(Theme.text)
        .sheet(isPresented: $showDetails) {
            SettlementDetailSheet(game: game)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationBackground(Theme.surface)
        }
        .sheet(isPresented: summaryBinding) {
            WhileAwayView(events: game.lastSessionEvents, registry: game.registry) {
                game.dismissSessionSummary()
            }
        }
    }

    private var canvasArea: some View {
        ZStack {
            if let map = game.viewedLocalMap, let settlement = game.selectedSettlement {
                SettlementCanvasView(
                    settlement: settlement, map: map, season: game.season,
                    selectedPawnID: $selectedPawnID)
                .overlay(alignment: .topTrailing) {
                    MinimapView(map: map).padding(12)
                }
                .overlay(alignment: .bottom) { bottomLayer }
            } else {
                emptyState
            }
        }
    }

    @ViewBuilder
    private var bottomLayer: some View {
        VStack(spacing: 10) {
            if let pawn = selectedPawn {
                PawnInspectorCard(pawn: pawn, ticksPerYear: game.ticksPerYear) {
                    withAnimation(.easeOut(duration: 0.15)) { selectedPawnID = nil }
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            controlBar
        }
        .padding(12)
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
            Button {
                showDetails = true
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
        guard let id = selectedPawnID else { return nil }
        return game.selectedSettlement?.pawns.first { $0.id == id }
    }

    private var summaryBinding: Binding<Bool> {
        Binding(
            get: { !game.lastSessionEvents.isEmpty },
            set: { if !$0 { game.dismissSessionSummary() } }
        )
    }
}
