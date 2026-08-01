import SwiftUI
import EndlessFrontierCore

/// What the viewer currently has picked out of the scene. A tap lands on
/// whatever is nearest — a colonist walking past or the building behind them —
/// so the two selections are one choice, not two competing ones.
///
/// A building selection carries its `definitionID` as well as its layout index:
/// the index is what the renderer rings, but it only means anything next to the
/// layout's sort order, and the screen showing the inspector has no rect to
/// recompute that from.
enum CanvasSelection: Equatable {
    case none
    case pawn(UUID)
    case building(index: Int, definitionID: String)
    /// A tapped deposit, resolved to the line the info capsule shows. The map
    /// stops being anonymous.
    case landmark(String)
    /// A tapped point of interest, by id. Carries only the id so the card
    /// always reads live state: a place worked or rested since the tap must
    /// not still be offering yesterday's action.
    case poi(Int)
    /// A tapped patch of fog — the offer to send the scouts there.
    case fog(LocalPoint)
    /// A tapped beast, wild or kept. The wild are pawns with bodies and lives;
    /// until now they were the only thing on the canvas you could not ask about.
    case animal(UUID)
}

/// The living settlement: a `TimelineView`-driven `Canvas` where colonists walk
/// their day. All motion is presentational (see `AgentMotion`); the simulation
/// underneath is untouched. Pinch to zoom, drag to pan, tap to inspect a
/// colonist or a building.
struct SettlementCanvasView: View {
    let settlement: Settlement
    let map: LocalMap
    let registry: GameDataRegistry
    let season: Season
    /// Shipments on the road right now. The legs that cross this valley are
    /// drawn; the rest of the journey is out in country this map does not show.
    var caravans: [Caravan] = []
    /// The simulation clock, so an expedition walks smoothly rather than
    /// jumping once a minute.
    let clock: TickClock
    @Binding var selection: CanvasSelection
    /// What the player is placing, if they are placing anything. When this is
    /// set the canvas becomes the build surface: the grid and a full-size ghost
    /// are drawn over the colony, and a tap aims instead of selecting.
    @Binding var buildPlan: BuildPlan?
    /// A fight the player asked to see again. A raid is over in half a minute
    /// of an hour-long colony year; looking away used to mean missing it for
    /// good.
    var battleReplay: SettlementBattle.Replay?

    /// A fixed, *absolute* epoch so the animation clock is stable across
    /// redraws — and so anyone else (the pawn inspector's "right now" line)
    /// can derive the same clock without holding a reference to this view.
    private let start = Date(timeIntervalSinceReferenceDate: 0)
    @State private var camera = SettlementRenderer.Camera()
    /// The camera as it was when the current gesture began, so pinch and drag
    /// compose from a fixed base instead of accumulating drift.
    @State private var gestureBase = SettlementRenderer.Camera()

    var body: some View {
        GeometryReader { geo in
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
                let t = timeline.date.timeIntervalSince(start)
                let now = clock.continuous(at: timeline.date)
                Canvas { context, size in
                    SettlementRenderer.draw(
                        &context, size: size, settlement: settlement, map: map,
                        registry: registry, time: t, season: season,
                        camera: camera, continuousTick: now,
                        caravans: caravans,
                        seasonProgress: seasonProgress(at: now),
                        battleReplay: battleReplay,
                        selectedPawnID: selectedPawnID,
                        selectedBuildingID: selectedBuildingID)
                    if let plan = buildPlan {
                        // Over everything, including the fog: you are laying
                        // out your own ground, not discovering it.
                        let rect = SettlementRenderer.worldRect(
                            viewRect: CGRect(origin: .zero, size: size), camera: camera)
                        SettlementBuildOverlay.draw(
                            &context, rect: rect, settlement: settlement,
                            registry: registry, plan: plan)
                    }
                }
            }
            .background(Theme.ink)
            .contentShape(Rectangle())
            .gesture(pan(in: geo.size).simultaneously(with: zoom))
            .gesture(tap(in: geo.size))
            .overlay(alignment: .bottomTrailing) { zoomChrome }
            .accessibilityLabel(AppStrings.language == .cs
                                ? "Živá osada. Přiblížení \(Int(camera.scale * 100)) procent."
                                : "The living settlement. Zoom \(Int(camera.scale * 100)) percent.")
        }
    }

    /// How far through the current season the year has got, 0…1.
    ///
    /// The renderer needs this and not just the season itself: snow that lies
    /// the same depth on the first day of winter as at its heart is a tint with
    /// extra steps. Derived from the simulation clock, so a long absence
    /// caught up on opening lands you in exactly the winter the ledger says.
    private func seasonProgress(at tick: Double) -> Double {
        let perYear = Double(registry.config.ticksPerYear)
        guard perYear >= 4 else { return 0.5 }
        let perSeason = perYear / 4
        let ofYear = tick.truncatingRemainder(dividingBy: perYear)
        let year = ofYear < 0 ? ofYear + perYear : ofYear
        return (year.truncatingRemainder(dividingBy: perSeason)) / perSeason
    }

    private var selectedPawnID: UUID? {
        if case let .pawn(id) = selection { return id }
        return nil
    }

    private var selectedBuildingID: Int? {
        if case let .building(index, _) = selection { return index }
        return nil
    }

    // MARK: - Gestures

    private func tap(in size: CGSize) -> some Gesture {
        SpatialTapGesture().onEnded { value in
            // While placing, a tap aims the ghost rather than selecting what is
            // under it — otherwise you'd inspect the building you are trying to
            // build beside.
            if let plan = buildPlan {
                aim(plan, at: value.location, size: size)
                return
            }
            let hit = hitTest(value.location, size: size)
            withAnimation(.easeOut(duration: 0.15)) {
                selection = (hit == selection) ? .none : hit
            }
        }
    }

    /// Points the ghost at the tapped ground.
    private func aim(_ plan: BuildPlan, at location: CGPoint, size: CGSize) {
        guard let colony = settlement.colony else { return }
        let rect = SettlementRenderer.worldRect(
            viewRect: CGRect(origin: .zero, size: size), camera: camera)
        let world = SettlementRenderer.normalised(location, in: rect)
        let footprint = registry.building(plan.definitionID)?.footprint ?? TileSize()
        guard let coord = SettlementBuildOverlay.aim(
            at: world, colony: colony, footprint: footprint) else { return }
        var updated = plan
        updated.coord = coord
        withAnimation(.easeOut(duration: 0.12)) { buildPlan = updated }
    }

    private func pan(in size: CGSize) -> some Gesture {
        DragGesture()
            .onChanged { value in
                camera.offset = CGSize(
                    width: gestureBase.offset.width + value.translation.width,
                    height: gestureBase.offset.height + value.translation.height)
                camera = clamped(camera, in: size)
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

    /// Keeps the world from being dragged off-screen: at 1× there is nothing to
    /// pan, and further in you can only travel as far as the overhang.
    private func clamped(_ camera: SettlementRenderer.Camera, in size: CGSize) -> SettlementRenderer.Camera {
        var c = camera
        let slackX = max(0, size.width * (c.scale - 1) / 2)
        let slackY = max(0, size.height * (c.scale - 1) / 2)
        c.offset.width = min(slackX, max(-slackX, c.offset.width))
        c.offset.height = min(slackY, max(-slackY, c.offset.height))
        return c
    }

    // MARK: - Chrome

    @ViewBuilder
    private var zoomChrome: some View {
        if camera.scale > SettlementRenderer.Camera.minScale + 0.01 {
            Button {
                withAnimation(.easeOut(duration: 0.25)) {
                    camera = SettlementRenderer.Camera()
                    gestureBase = camera
                }
            } label: {
                Label("\(Int(camera.scale * 100))%", systemImage: "arrow.down.right.and.arrow.up.left")
                    .font(.caption2.weight(.semibold).monospacedDigit())
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial, in: Capsule())
            }
            .tint(Theme.text)
            .padding(12)
            .transition(.opacity)
            .accessibilityLabel(AppStrings.language == .cs ? "Oddálit zpět" : "Reset zoom")
        }
    }

    // MARK: - Hit testing

    /// Nearest thing to a tap, taken in layers.
    ///
    /// It used to answer for five kinds of thing and measure all of them the
    /// same way — the distance to a *point*. Two things were wrong with that,
    /// and between them they are the whole of "not everything is clickable":
    ///
    /// 1. **A building is a lot, not a dot.** Buildings own multi-tile
    ///    footprints now, and a granary four tiles across was tappable only
    ///    within 22pt of its centre — so the half of it you were actually
    ///    looking at answered nothing. Buildings are hit against their
    ///    *footprint*, and a tap inside one is a hit at zero distance.
    /// 2. **Half the world was not in the list.** Trees, rock, and the heaps of
    ///    timber lying at the stump are drawn, walked to, and worked — and
    ///    tapping any of them did nothing at all.
    ///
    /// The layers run people → beasts → built → the things on the ground →
    /// the land → the dark, and the first layer with anything in reach wins:
    /// a colonist walking past a wall is what the eye was following.
    private func hitTest(_ location: CGPoint, size: CGSize) -> CanvasSelection {
        let viewRect = CGRect(origin: .zero, size: size)
        let rect = SettlementRenderer.worldRect(viewRect: viewRect, camera: camera)
        let t = Date().timeIntervalSince(start)
        let scene = AgentMotion.Scene(settlement: settlement, registry: registry,
                                      continuousTick: clock.continuous(at: Date()),
                                      replay: battleReplay)
        let ticksPerYear = registry.config.ticksPerYear
        var probe = Probe(location: location, limit: touchRadius)

        for pawn in SettlementRenderer.visibleAgents(settlement) {
            let pose = AgentMotion.pose(for: pawn, map: map, scene: scene,
                                        time: t, ticksPerYear: ticksPerYear)
            guard map.isExplored(pose.position) else { continue }
            probe.offer(.pawn(pawn.id),
                        at: SettlementRenderer.point(pose.position, in: rect))
        }
        if let hit = probe.take() { return hit }

        // The beasts, wild and kept. They are pawns with bodies, wounds and a
        // mind — the only living things on the map you could not tap.
        for animal in map.wildlife.animals where map.isExplored(animal.position) {
            probe.offer(.animal(animal.id),
                        at: SettlementRenderer.point(animal.position, in: rect))
        }
        for kept in settlement.tamed {
            probe.offer(.animal(kept.animal.id),
                        at: SettlementRenderer.point(
                            SettlementWildlife.tamedPosition(kept, index: 0, time: t), in: rect))
        }
        if let hit = probe.take() { return hit }

        for building in SettlementRenderer.layout(settlement: settlement, registry: registry, rect: rect) {
            // The whole lot answers, not the pin in the middle of it. Widened a
            // touch so a thumb on the eaves still counts.
            let lot = CGRect(
                x: building.center.x - building.footprint.width / 2 - 4,
                y: building.center.y - building.footprint.height / 2 - 4,
                width: building.footprint.width + 8, height: building.footprint.height + 8)
            probe.offer(.building(index: building.id, definitionID: building.definitionID),
                        within: lot)
        }
        for poi in map.pois where poi.discovered && map.isExplored(poi.position) {
            probe.offer(.poi(poi.id), at: SettlementRenderer.point(poi.position, in: rect))
        }
        if let hit = probe.take() { return hit }

        // The things lying about: a heap of timber at the stump that is on its
        // way in, the wood it came out of, the rock somebody is cutting into.
        for pile in map.piles where map.isExplored(pile.position) {
            probe.offer(.landmark(pileLabel(pile)),
                        at: SettlementRenderer.point(pile.position, in: rect))
        }
        for tree in map.trees where map.isExplored(tree.position) {
            probe.offer(.landmark(treeLabel(tree)),
                        at: SettlementRenderer.point(tree.position, in: rect))
        }
        for rock in map.rocks where map.isExplored(rock.position) {
            probe.offer(.landmark(rockLabel(rock)),
                        at: SettlementRenderer.point(rock.position, in: rect))
        }
        if let hit = probe.take() { return hit }

        // The land answers last: deposits with their fullness.
        for node in settlement.localMap?.nodes ?? [] where map.isExplored(node.position) {
            let fullness = node.capacity > 0 ? Int(node.amount / node.capacity * 100) : 100
            probe.offer(.landmark("\(node.kind.displayLabel) · \(fullness) %"),
                        at: SettlementRenderer.point(node.position, in: rect))
        }
        if let hit = probe.take() { return hit }

        // Nothing known is near the tap. If the player reached into the dark,
        // that's an instruction waiting to be given.
        let world = SettlementRenderer.normalised(location, in: rect)
        return map.isExplored(world) ? .none : .fog(world)
    }

    /// Keeps the nearest candidate offered so far, within a reach.
    ///
    /// One layer's worth at a time: `take()` returns whatever the layer found
    /// and clears the slate, so a colonist in reach ends the search before a
    /// wall behind them is ever measured.
    private struct Probe {
        let location: CGPoint
        let limit: CGFloat
        private var best: CanvasSelection?
        private var bestDistance: CGFloat = .greatestFiniteMagnitude

        init(location: CGPoint, limit: CGFloat) {
            self.location = location
            self.limit = limit
        }

        mutating func offer(_ candidate: CanvasSelection, at point: CGPoint) {
            let dx = point.x - location.x, dy = point.y - location.y
            consider(candidate, distanceSquared: dx * dx + dy * dy, reach: limit * limit)
        }

        /// A thing with a footprint: inside it is a hit at zero distance, and
        /// near it is the distance to its edge.
        mutating func offer(_ candidate: CanvasSelection, within rect: CGRect) {
            let dx = max(rect.minX - location.x, 0, location.x - rect.maxX)
            let dy = max(rect.minY - location.y, 0, location.y - rect.maxY)
            consider(candidate, distanceSquared: dx * dx + dy * dy, reach: limit * limit)
        }

        private mutating func consider(
            _ candidate: CanvasSelection, distanceSquared d2: CGFloat, reach: CGFloat
        ) {
            guard d2 <= reach, d2 < bestDistance else { return }
            bestDistance = d2
            best = candidate
        }

        mutating func take() -> CanvasSelection? {
            defer { best = nil; bestDistance = .greatestFiniteMagnitude }
            return best
        }
    }

    // MARK: - What the land says when you tap it

    private func treeLabel(_ tree: Tree) -> String {
        let cs = AppStrings.language == .cs
        let name = tree.species.displayName.resolve(AppStrings.language)
        if tree.growth < SettlementFlora.saplingGrowth {
            return "\(name) · \(cs ? "semenáček" : "sapling")"
        }
        let felled = tree.chopped > 0.02
            ? " · \(cs ? "nařezáno" : "cut") \(Int(tree.chopped * 100)) %" : ""
        return "\(name) · \(Int(tree.timberYield.rounded())) \(cs ? "dřeva" : "timber")\(felled)"
    }

    private func rockLabel(_ rock: Rock) -> String {
        let name = rock.kind.displayName.resolve(AppStrings.language)
        return "\(name) · \(Int(rock.remaining * 100)) %"
    }

    private func pileLabel(_ pile: HaulPile) -> String {
        let cs = AppStrings.language == .cs
        let name = registry.item(pile.itemID)?.name.resolve(AppStrings.language) ?? pile.itemID
        let claimed = pile.claimedBy != nil
            ? " · \(cs ? "někdo pro to jde" : "someone is coming")"
            : " · \(cs ? "leží tu" : "lying here")"
        return "\(name) ×\(pile.amount)\(claimed)"
    }

    /// How far from a tap something may be and still be what was meant. In view
    /// points, so it is a thumb's width whatever the camera is doing.
    private var touchRadius: CGFloat { 22 }
}
