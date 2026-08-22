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
    /// What the last tap landed on — a deposit, a landmark, the camp.
    @State private var info: String?

    private var cs: Bool { AppStrings.language == .cs }

    /// The chunk itself: fully revealed (this is a survey, not a fog crawl),
    /// with its finds marked on the record.
    private var map: LocalMap {
        var m = LocalMapGenerator.generate(
            mapSeed: game.world.mapSeed,
            regionID: region.id,
            biome: game.registry.biome(region.biomeID),
            flavor: region.kind,
            hazard: region.hazardLevel)
        m.reveal(around: LocalPoint(x: 0.5, y: 0.5), radius: 1.2)
        return m
    }

    /// The met people living in this region, if any.
    private var residentTribe: Tribe? {
        game.tribes.first { $0.regionID == region.id }
    }

    /// **The people who live here, as a place.** Derived from the tribe's own
    /// numbers by `TribeCamp` — real roofs, real pawns with bodies and days —
    /// and cached against what those numbers *are*, so it is rebuilt when the
    /// people change and not thirty times a second.
    ///
    /// Nothing here is simulated and nothing is saved: it is exactly as much
    /// of a people as the drawing needs, which is stage one of the two
    /// `docs/HANDOFF-2026-08-22.md` §4.4 lays out.
    @State private var camp: Settlement?
    @State private var campKey: String?

    private var currentCampKey: String? {
        guard let tribe = residentTribe else { return nil }
        return "\(tribe.id)|\(Int(tribe.population))|\(Int(tribe.stores))"
            + "|\(Int(tribe.defense))|\(tribe.wars)|\(game.world.era.rawValue)"
    }

    /// Off the main actor. Deriving a camp lays out a build grid, which is the
    /// same work the colony does at its founding — cheap enough to do once and
    /// far too dear to do while a sheet is animating in.
    private func refreshCamp() async {
        let key = currentCampKey
        guard key != campKey else { return }
        campKey = key
        guard let people = residentTribe else { camp = nil; return }
        let seed = game.world.mapSeed
        let era = game.world.era
        let registry = game.registry
        let language = AppStrings.language
        camp = await Task.detached(priority: .userInitiated) {
            TribeCamp.settlement(for: people, mapSeed: seed, era: era,
                                 registry: registry, language: language)
        }.value
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
                            regionKind: region.kind, tribe: residentTribe,
                            camp: camp,
                            continuousTick: game.tickClock.continuous(at: timeline.date),
                            registry: game.registry)
                    }
                }
                .contentShape(Rectangle())
                .gesture(pan(in: geo.size).simultaneously(with: zoom))
                .gesture(SpatialTapGesture().onEnded { value in
                    withAnimation(.easeOut(duration: 0.15)) {
                        info = inspect(value.location, size: geo.size)
                    }
                })
            }
            .overlay(alignment: .top) { header }
            .overlay(alignment: .bottom) { bottomBar }
        }
        .foregroundStyle(Theme.text)
        .presentationBackground(Theme.ink)
        .task { await refreshCamp() }
        .task(id: currentCampKey) { await refreshCamp() }
    }

    /// The tap-to-ask layer and, when the land is open, the reason you came:
    /// settle it — straight from the survey, the way you'd want to in RimWorld.
    private var bottomBar: some View {
        VStack(spacing: 8) {
            if let info {
                Text(info)
                    .font(.caption)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(.ultraThinMaterial, in: Capsule())
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            if game.canFound(region) {
                settleButton
            }
        }
        .padding(.bottom, 16)
        .padding(.horizontal, 16)
    }

    private var settleButton: some View {
        let cost = ExpansionEngine.outpostFoundingCost
        let affordable = game.canAfford(cost)
        return VStack(spacing: 4) {
            Button {
                game.foundOutpost(in: region.id)
                // Walk straight into the new home.
                if let founded = game.settlement(in: region) {
                    game.selectSettlement(founded.id)
                    game.tab = .settlement
                }
                dismiss()
            } label: {
                Label(cs ? "Založit osadu zde" : "Settle here",
                      systemImage: "house.lodge.fill")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)
            .disabled(!affordable)
            .opacity(affordable ? 1 : 0.5)
            HStack(spacing: 10) {
                ForEach(ResourceType.allCases.filter { cost[$0] > 0 }, id: \.self) { resource in
                    HStack(spacing: 3) {
                        Image(systemName: resource.symbolName).font(.caption2)
                        Text("\(Int(cost[resource]))").font(.caption2.monospacedDigit())
                    }
                    .foregroundStyle(game.selectedSettlementStorage(resource) < cost[resource]
                                     ? Theme.danger : Theme.textDim)
                }
                if !affordable {
                    Text(cs ? "Nedostatek zásob" : "Can't afford it yet")
                        .font(.caption2).foregroundStyle(Theme.danger)
                }
            }
        }
    }

    // MARK: - Tap-to-ask

    /// What stands at a tapped spot — the "co je co" of the survey.
    private func inspect(_ location: CGPoint, size: CGSize) -> String? {
        let viewRect = CGRect(origin: .zero, size: size)
        let rect = SettlementRenderer.worldRect(viewRect: viewRect, camera: camera)
        let n = LocalPoint(x: (location.x - rect.minX) / rect.width,
                           y: (location.y - rect.minY) / rect.height)
        let reach = 0.05 / Double(camera.scale)

        func near(_ p: LocalPoint) -> Double {
            let dx = p.x - n.x, dy = p.y - n.y
            return dx * dx + dy * dy
        }

        var best: (distance: Double, text: String)?
        for poi in map.pois where poi.discovered {
            let d = near(poi.position)
            if d < reach * reach, d < (best?.distance ?? .infinity) {
                best = (d, poi.kind.displayLabel)
            }
        }
        for node in map.nodes {
            let d = near(node.position)
            if d < reach * reach, d < (best?.distance ?? .infinity) {
                let fullness = node.capacity > 0 ? Int(node.amount / node.capacity * 100) : 100
                best = (d, "\(node.kind.displayLabel) · \(fullness) %")
            }
        }
        if let tribe = residentTribe {
            let d = near(LocalPoint(x: 0.5, y: 0.5))
            if d < reach * reach * 4, d < (best?.distance ?? .infinity) {
                best = (d, cs
                    ? "\(tribe.name) — \(Int(tribe.population)) duší, \(AppStrings.standingName(tribe.status).lowercased())"
                    : "\(tribe.name) — \(Int(tribe.population)) souls, \(AppStrings.standingName(tribe.status).lowercased())")
            }
        }
        return best?.text ?? (info == nil ? nil : nil)   // tap on nothing clears
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
