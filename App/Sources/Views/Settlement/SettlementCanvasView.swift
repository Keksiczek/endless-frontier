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
    /// The simulation clock, so an expedition walks smoothly rather than
    /// jumping once a minute.
    let clock: TickClock
    @Binding var selection: CanvasSelection
    /// What the player is placing, if they are placing anything. When this is
    /// set the canvas becomes the build surface: the grid and a full-size ghost
    /// are drawn over the colony, and a tap aims instead of selecting.
    @Binding var buildPlan: BuildPlan?

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

    /// Nearest thing to a tap: a walking colonist wins over a building when
    /// both are in reach, since they're what the eye was following.
    private func hitTest(_ location: CGPoint, size: CGSize) -> CanvasSelection {
        let viewRect = CGRect(origin: .zero, size: size)
        let rect = SettlementRenderer.worldRect(viewRect: viewRect, camera: camera)
        let t = Date().timeIntervalSince(start)
        let scene = AgentMotion.Scene(settlement: settlement, registry: registry,
                                      continuousTick: clock.continuous(at: Date()))
        let ticksPerYear = registry.config.ticksPerYear

        var best: CanvasSelection = .none
        var bestDistance = touchRadius * touchRadius
        for pawn in SettlementRenderer.visibleAgents(settlement) {
            let pose = AgentMotion.pose(for: pawn, map: map, scene: scene,
                                        time: t, ticksPerYear: ticksPerYear)
            guard map.isExplored(pose.position) else { continue }
            let p = SettlementRenderer.point(pose.position, in: rect)
            let d2 = distanceSquared(p, location)
            if d2 < bestDistance {
                bestDistance = d2
                best = .pawn(pawn.id)
            }
        }
        if case .pawn = best { return best }

        for building in SettlementRenderer.layout(settlement: settlement, registry: registry, rect: rect) {
            let d2 = distanceSquared(building.center, location)
            if d2 < bestDistance {
                bestDistance = d2
                best = .building(index: building.id, definitionID: building.definitionID)
            }
        }
        if case .building = best { return best }

        // The land answers last: deposits with their fullness, landmarks with
        // their name.
        for node in settlement.localMap?.nodes ?? [] where map.isExplored(node.position) {
            let d2 = distanceSquared(SettlementRenderer.point(node.position, in: rect), location)
            if d2 < bestDistance {
                bestDistance = d2
                let fullness = node.capacity > 0 ? Int(node.amount / node.capacity * 100) : 100
                best = .landmark("\(node.kind.displayLabel) · \(fullness) %")
            }
        }
        for poi in map.pois where poi.discovered && map.isExplored(poi.position) {
            let d2 = distanceSquared(SettlementRenderer.point(poi.position, in: rect), location)
            if d2 < bestDistance {
                bestDistance = d2
                best = .poi(poi.id)
            }
        }
        if case .none = best {
            // Nothing known is near the tap. If the player reached into the
            // dark, that's an instruction waiting to be given.
            let world = SettlementRenderer.normalised(location, in: rect)
            if !map.isExplored(world) { return .fog(world) }
        }
        return best
    }

    private func distanceSquared(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = a.x - b.x, dy = a.y - b.y
        return dx * dx + dy * dy
    }

    private var touchRadius: CGFloat { 22 }
}
