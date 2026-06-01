import SwiftUI
import EndlessFrontierCore

/// Exploration & expansion: send expeditions into the unknown and found
/// outposts in revealed regions.
struct FrontierPanel: View {
    @Bindable var game: GameViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            expeditionSection
            settleSection
        }
    }

    private var expeditionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Frontier")

            if let expedition = game.activeExpedition {
                HStack(spacing: 12) {
                    Image(systemName: "figure.walk.motion").foregroundStyle(Theme.accent)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Expedition to \(game.regionName(expedition.targetRegionID))")
                            .font(.subheadline.weight(.medium))
                        Text("\(expedition.ticksRemaining) ticks remaining")
                            .font(.caption).foregroundStyle(Theme.textDim)
                    }
                    Spacer()
                }
                .padding(.vertical, 10).padding(.horizontal, 12)
                .background(Theme.surfaceInset, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            } else if game.exploreableRegions.isEmpty {
                Text("Every nearby region has been charted.")
                    .font(.subheadline).foregroundStyle(Theme.textDim)
            } else {
                ForEach(game.exploreableRegions) { region in
                    Button {
                        game.explore(region.id)
                    } label: {
                        regionRow(
                            title: region.name,
                            subtitle: "Unknown · hazard \(region.hazardLevel) · ~\(game.expeditionDuration(for: region)) ticks",
                            systemImage: "map.fill"
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frontierCard()
    }

    @ViewBuilder
    private var settleSection: some View {
        if !game.foundableRegions.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "Settle")
                ForEach(game.foundableRegions) { region in
                    Button {
                        game.foundOutpost(in: region.id)
                    } label: {
                        regionRow(
                            title: region.name,
                            subtitle: "\(game.biomeName(region.biomeID)) · found an outpost",
                            systemImage: "house.lodge.fill"
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .frontierCard()
        }
    }

    private func regionRow(title: String, subtitle: String, systemImage: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage).foregroundStyle(Theme.textDim).frame(width: 24)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.subheadline.weight(.medium)).foregroundStyle(Theme.text)
                Text(subtitle).font(.caption).foregroundStyle(Theme.textDim)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(Theme.textDim)
        }
        .padding(.vertical, 10).padding(.horizontal, 12)
        .background(Theme.surfaceInset, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
