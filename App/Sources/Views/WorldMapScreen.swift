import SwiftUI
import EndlessFrontierCore

/// The world screen: the hex map plus a detail panel for the selected region.
/// Adaptive — side-by-side on iPad (regular width), map with a bottom card on
/// iPhone (compact width).
struct WorldMapScreen: View {
    @Bindable var game: GameViewModel
    @State private var selectedRegionID: UUID?
    @Environment(\.horizontalSizeClass) private var sizeClass

    private var selectedRegion: Region? {
        game.regions.first { $0.id == selectedRegionID }
    }

    var body: some View {
        ZStack {
            Theme.surface.ignoresSafeArea()
            if sizeClass == .regular {
                HStack(spacing: 0) {
                    WorldMapView(game: game, selectedRegionID: $selectedRegionID)
                    detailPanel
                        .frame(width: 340)
                        .background(Theme.surface)
                }
            } else {
                WorldMapView(game: game, selectedRegionID: $selectedRegionID)
                    .overlay(alignment: .bottom) {
                        if let region = selectedRegion {
                            RegionDetailCard(game: game, region: region) { selectedRegionID = nil }
                                .padding(12)
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                        }
                    }
            }
        }
        .foregroundStyle(Theme.text)
        .animation(.snappy, value: selectedRegionID)
        .alert("Site Explored", isPresented: siteOutcomeBinding, presenting: game.lastSiteOutcome) { _ in
            Button("Continue") { game.dismissSiteOutcome() }
        } message: { outcome in
            Text(outcome.narrative)
        }
    }

    private var siteOutcomeBinding: Binding<Bool> {
        Binding(
            get: { game.lastSiteOutcome != nil },
            set: { if !$0 { game.dismissSiteOutcome() } }
        )
    }

    @ViewBuilder
    private var detailPanel: some View {
        ScrollView {
            if let region = selectedRegion {
                RegionDetailCard(game: game, region: region) { selectedRegionID = nil }
                    .padding(16)
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "hand.tap.fill").font(.title)
                    Text("Select a region")
                        .font(.subheadline)
                }
                .foregroundStyle(Theme.textDim)
                .frame(maxWidth: .infinity, minHeight: 200)
                .padding(.top, 60)
            }
        }
    }
}

/// Detail + actions for one region.
struct RegionDetailCard: View {
    @Bindable var game: GameViewModel
    let region: Region
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(region.explorationState == .unknown ? "Unknown Region" : region.name)
                        .font(.title3.weight(.bold))
                    Text(subtitle).font(.caption).foregroundStyle(Theme.accent)
                }
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.textDim)
                }
                .buttonStyle(.plain)
            }

            if region.explorationState != .unknown {
                HStack(spacing: 16) {
                    label("Biome", game.biomeName(region.biomeID))
                    label("Hazard", "\(region.hazardLevel)")
                }
            }

            if let settlement = game.settlement(in: region) {
                label("Settlement", "\(settlement.name) (\(settlement.kind.rawValue))")
            }

            actions
        }
        .frontierCard()
    }

    @ViewBuilder
    private var actions: some View {
        if game.canExplore(region) {
            actionButton("Send Expedition", systemImage: "figure.walk") { game.explore(region.id) }
        } else if game.activeExpedition?.targetRegionID == region.id {
            Text("Expedition under way — \(game.activeExpedition?.ticksRemaining ?? 0) ticks left")
                .font(.caption).foregroundStyle(Theme.textDim)
        } else {
            if let siteLabel = game.siteActionLabel(for: region) {
                actionButton(siteLabel, systemImage: "flashlight.on.fill") { game.interactWithSite(region.id) }
            }
            if game.canFound(region) {
                actionButton("Found Outpost", systemImage: "house.lodge.fill") { game.foundOutpost(in: region.id) }
            }
            if region.explorationState == .unknown {
                Text("Explore an adjacent region first.")
                    .font(.caption).foregroundStyle(Theme.textDim)
            }
        }
    }

    private var subtitle: String {
        switch region.explorationState {
        case .unknown: return "Uncharted"
        case .partiallyExplored: return "Partially charted"
        case .fullyExplored: return region.kind == .homeland ? "Homeland" : region.kind.rawValue.capitalized
        }
    }

    private func label(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title.uppercased()).font(.caption2.weight(.bold)).tracking(1)
                .foregroundStyle(Theme.textDim)
            Text(value).font(.subheadline.weight(.medium))
        }
    }

    private func actionButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(Theme.accent.opacity(0.18), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .foregroundStyle(Theme.accent)
        }
        .buttonStyle(.plain)
    }
}
