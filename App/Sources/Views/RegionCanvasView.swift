import SwiftUI
import EndlessFrontierCore

/// Opens any *explored* region as a living chunk — RimWorld-style: the same
/// deterministic terrain generator that would build a settlement map here
/// builds the survey view, so what the scouts saw is exactly what settlers
/// would get. Deposits, landmarks, wildlife and (if a met people lives here)
/// their camp and their folk, all moving. Pan and pinch like the home canvas.
///
/// Nothing here simulates: the chunk is a pure function of `(mapSeed,
/// regionID, kind, biome)` plus the frame clock, generated on demand and
/// thrown away — saves don't grow by a byte.
struct RegionCanvasView: View {
    let region: Region
    @Bindable var game: GameViewModel
    @Environment(\.dismiss) private var dismiss

    private let start = Date(timeIntervalSinceReferenceDate: 0)
    @State private var camera = SettlementRenderer.Camera()
    @State private var gestureBase = SettlementRenderer.Camera()

    private var cs: Bool { AppStrings.language == .cs }

    /// The chunk itself: fully revealed (this is a survey, not a fog crawl),
    /// with its finds marked on the record.
    private var map: LocalMap {
        var m = LocalMapGenerator.generate(
            mapSeed: game.world.mapSeed,
            regionID: region.id,
            biome: game.registry.biome(region.biomeID),
            flavor: region.kind)
        m.reveal(around: LocalPoint(x: 0.5, y: 0.5), radius: 1.2)
        return m
    }

    /// The met people living in this region, if any.
    private var residentTribe: Tribe? {
        game.tribes.first { $0.regionID == region.id }
    }

    var body: some View {
        ZStack {
            Theme.ink.ignoresSafeArea()
            GeometryReader { geo in
                TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
                    let t = timeline.date.timeIntervalSince(start)
                    Canvas { context, size in
                        SettlementRenderer.drawWilderness(
                            &context, size: size, map: map,
                            season: game.season, time: t, camera: camera,
                            regionKind: region.kind, tribe: residentTribe)
                    }
                }
                .contentShape(Rectangle())
                .gesture(pan(in: geo.size).simultaneously(with: zoom))
            }
            .overlay(alignment: .top) { header }
        }
        .foregroundStyle(Theme.text)
        .presentationBackground(Theme.ink)
    }

    private var header: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(region.name)
                    .font(.system(.headline, design: .serif))
                HStack(spacing: 6) {
                    Text(game.biomeName(region.biomeID))
                    if let chip = kindChip {
                        Text("· \(chip)").foregroundStyle(Theme.accent)
                    }
                    if let tribe = residentTribe {
                        Text("· \(tribe.name)").foregroundStyle(Theme.accent)
                    }
                }
                .font(.caption)
                .foregroundStyle(Theme.textDim)
            }
            Spacer()
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(Theme.textDim)
            }
            .accessibilityLabel(cs ? "Zavřít průzkum" : "Close survey")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: Capsule())
        .padding(12)
    }

    private var kindChip: String? {
        switch region.kind {
        case .ruins: return cs ? "zříceniny" : "ruins"
        case .dungeon: return cs ? "podzemí" : "dungeon"
        case .anomaly: return cs ? "anomálie" : "anomaly"
        case .sanctuary: return cs ? "svatyně" : "sanctuary"
        case .lostCity: return cs ? "mrtvé město" : "lost city"
        case .homeland, .wilderness: return nil
        }
    }

    // MARK: - Gestures (the home canvas's camera, reused)

    private func pan(in size: CGSize) -> some Gesture {
        DragGesture()
            .onChanged { value in
                camera.offset = CGSize(
                    width: gestureBase.offset.width + value.translation.width,
                    height: gestureBase.offset.height + value.translation.height)
                let slackX = max(0, size.width * (camera.scale - 1) / 2)
                let slackY = max(0, size.height * (camera.scale - 1) / 2)
                camera.offset.width = min(slackX, max(-slackX, camera.offset.width))
                camera.offset.height = min(slackY, max(-slackY, camera.offset.height))
            }
            .onEnded { _ in gestureBase = camera }
    }

    private var zoom: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                camera.scale = min(SettlementRenderer.Camera.maxScale,
                                   max(SettlementRenderer.Camera.minScale,
                                       gestureBase.scale * value.magnification))
            }
            .onEnded { _ in gestureBase = camera }
    }
}
