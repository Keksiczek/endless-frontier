import SwiftUI
import EndlessFrontierCore

/// The world screen: the hex map plus a detail panel for the selected region.
/// Adaptive — side-by-side on iPad (regular width), map with a bottom card on
/// iPhone (compact width).
struct WorldMapScreen: View {
    @Bindable var game: GameViewModel
    @State private var selectedRegionID: UUID?
    /// The region whose chunk is open for survey, if any.
    @State private var surveyRegion: Region?
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
                            RegionDetailCard(game: game, region: region,
                                             onSurvey: { surveyRegion = region }) { selectedRegionID = nil }
                                .padding(12)
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                        }
                    }
            }
        }
        // The valley was never empty: as long as unmet peoples wait beyond the
        // fog, the map itself says so — a reason to keep sending expeditions.
        .overlay(alignment: .top) {
            if game.unmetTribeCount > 0, selectedRegion == nil {
                HStack(spacing: 6) {
                    Image(systemName: "tent.2.fill").font(.caption2)
                    Text(AppStrings.language == .cs
                         ? "\(game.unmetTribeCount) národy dosud nepoznány — vyšli výpravy"
                         : "\(game.unmetTribeCount) peoples not yet met — send expeditions")
                        .font(.caption)
                }
                .foregroundStyle(Theme.textDim)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(.ultraThinMaterial, in: Capsule())
                .padding(.top, 8)
                .allowsHitTesting(false)
            }
        }
        .foregroundStyle(Theme.text)
        .animation(.snappy, value: selectedRegionID)
        // A find is a place, not a dialog. What the expedition turned up now
        // shows over the living survey of the country it came from — the same
        // view the world map already opens for any explored region.
        .sheet(isPresented: siteOutcomeBinding) {
            if let outcome = game.lastSiteOutcome {
                ZStack(alignment: .bottom) {
                    if let region = game.region(named: outcome.regionName) {
                        RegionCanvasView(region: region, game: game)
                    } else {
                        Theme.ink.ignoresSafeArea()
                    }
                    SiteOutcomeCard(outcome: outcome) { game.dismissSiteOutcome() }
                        .padding(14)
                }
            }
        }
        // Opening a chunk: any explored region unfolds into a living survey.
        .sheet(item: $surveyRegion) { region in
            RegionCanvasView(region: region, game: game)
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
            VStack(spacing: 16) {
                if let region = selectedRegion {
                    RegionDetailCard(game: game, region: region,
                                     onSurvey: { surveyRegion = region }) { selectedRegionID = nil }
                } else if game.world.tribes.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "hand.tap.fill").font(.title)
                        Text(AppStrings.language == .cs ? "Vyber region" : "Select a region")
                            .font(.subheadline)
                    }
                    .foregroundStyle(Theme.textDim)
                    .frame(maxWidth: .infinity, minHeight: 160)
                    .padding(.top, 40)
                }
                // Peoples who grew out of your own settlement.
                TribesPanel(game: game)
            }
            .padding(16)
        }
    }
}

/// Detail + actions for one region.
struct RegionDetailCard: View {
    @Bindable var game: GameViewModel
    let region: Region
    /// Opens the region's living chunk (survey view), when offered.
    var onSurvey: (() -> Void)? = nil
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

            if let tribe = game.tribes.first(where: { $0.regionID == region.id }) {
                tribeRow(tribe)
            }

            // An explored region is a place, not a row of stats — open it.
            if region.explorationState == .fullyExplored,
               game.settlement(in: region) == nil,
               let onSurvey {
                actionButton(AppStrings.language == .cs ? "Prohlédnout krajinu" : "Survey the land",
                             systemImage: "binoculars.fill", action: onSurvey)
            }

            actions
        }
        .frontierCard()
    }

    @ViewBuilder
    private var actions: some View {
        if game.canExplore(region) {
            // The cost is shown, and an expedition the colony can't pay for is
            // visibly out of reach. It used to be a lit button that silently
            // did nothing when the woodpile ran low — which reads as the game
            // being broken, not the colony being broke.
            let affordable = game.canAffordExpedition(to: region)
            let cost = game.expeditionCost(for: region)
            VStack(alignment: .leading, spacing: 6) {
                actionButton("Send Expedition", systemImage: "figure.walk") {
                    game.explore(region.id)
                }
                .disabled(!affordable)
                .opacity(affordable ? 1 : 0.45)
                HStack(spacing: 10) {
                    ForEach(ResourceType.allCases.filter { cost[$0] > 0 }, id: \.self) { resource in
                        let short = game.selectedSettlementStorage(resource) < cost[resource]
                        HStack(spacing: 3) {
                            Image(systemName: resource.symbolName).font(.caption2)
                            Text("\(Int(cost[resource].rounded()))")
                                .font(.caption2.monospacedDigit())
                        }
                        .foregroundStyle(short ? Theme.danger : Theme.textDim)
                    }
                    if !affordable {
                        Text(AppStrings.cannotAffordExpedition)
                            .font(.caption2).foregroundStyle(Theme.danger)
                    }
                }
            }
        } else if game.activeExpedition?.targetRegionID == region.id {
            Text("Expedition under way — \(game.activeExpedition?.ticksRemaining ?? 0) ticks left")
                .font(.caption).foregroundStyle(Theme.textDim)
        } else if game.activeExpedition != nil, region.explorationState == .unknown {
            // Only one expedition can be out at a time — say so, rather than
            // showing an unexplained dead end.
            Text(AppStrings.expeditionAlreadyOut)
                .font(.caption).foregroundStyle(Theme.textDim)
        } else {
            if let party = game.partyOut(toRegion: region.id) {
                // Somebody is already on that road. Say where they are rather
                // than offering the button again.
                partyLine(party)
            } else if let siteLabel = game.siteActionLabel(for: region) {
                actionButton(siteLabel, systemImage: "figure.walk.departure") {
                    game.sendToSite(region.id)
                }
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

    /// The people who live in this hex — who they are, how they stand with
    /// you, and where they came from.
    private func tribeRow(_ tribe: Tribe) -> some View {
        let cs = AppStrings.language == .cs
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: "tent.fill")
                    .font(.caption)
                    .foregroundStyle(Theme.accent)
                Text(tribe.name)
                    .font(.subheadline.weight(.semibold))
                Text("· \(Int(tribe.population)) \(cs ? "duší" : "souls")")
                    .font(.caption)
                    .foregroundStyle(Theme.textDim)
                Spacer()
                Text(AppStrings.standingName(tribe.status))
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Theme.surfaceInset, in: Capsule())
            }
            Text(tribe.originStory.resolve(AppStrings.language))
                .font(.caption)
                .foregroundStyle(Theme.textDim)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .background(Theme.surfaceInset.opacity(0.6), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var subtitle: String {
        switch region.explorationState {
        case .unknown: return "Uncharted"
        case .partiallyExplored: return "Partially charted"
        case .fullyExplored:
            return region.kind == .homeland
                ? "Homeland"
                : region.kind.rawValue.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    private func label(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title.uppercased()).font(.caption2.weight(.bold)).tracking(1)
                .foregroundStyle(Theme.textDim)
            Text(value).font(.subheadline.weight(.medium))
        }
    }

    /// Where a party already on that road has got to. Sending people out is a
    /// journey now, so the panel owes you the middle of it.
    private func partyLine(_ party: RegionExpedition) -> some View {
        let cs = AppStrings.language == .cs
        let left = party.ticksRemaining(at: game.world.tick)
        let where_: String
        switch party.phase(at: game.world.tick) {
        case .outbound:  where_ = cs ? "na cestě tam" : "on the road out"
        case .working:   where_ = cs ? "prohledávají to" : "searching it"
        case .returning: where_ = cs ? "na cestě domů" : "on the road home"
        }
        return VStack(alignment: .leading, spacing: 5) {
            Label("\(party.memberIDs.count) — \(where_)", systemImage: "figure.walk")
                .font(.caption.weight(.medium))
                .foregroundStyle(Theme.accent)
            ProgressView(value: party.progress(at: game.world.tick))
                .tint(Theme.accent)
            Text(cs ? "Zpátky za \(left) taktů." : "Back in \(left) ticks.")
                .font(.caption2).foregroundStyle(Theme.textDim)
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
