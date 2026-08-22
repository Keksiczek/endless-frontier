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
    /// **A tapped thing the colony can be told to work**: a tree, a seam of
    /// rock, a heap lying out in the open.
    ///
    /// These used to be `.landmark`, which is a *string* — so the map could
    /// name what you had tapped and nothing more, and the only thing to do
    /// about a wood you wanted cleared was to hope somebody wandered over.
    /// Carrying the target's identity is what lets the card offer an order
    /// (`Designation`); the label rides along because the card says it too.
    case thing(target: Designation.Target, label: String)
}

/// Somewhere the canvas is being asked to take the player.
///
/// The colony is a valley and the things that happen in it are small: a raid
/// runs for half a minute at one edge of a map you are looking at the middle
/// of, a wildfire takes hold in a corner, and the only sign of either was a
/// line of text going past at the top of the screen. So you read that something
/// had happened, panned around hunting for it, and found it already over — the
/// game and the diary reading like two different games running side by side.
///
/// This is the answer: what happened says *who or what* it happened to
/// (`ColonyLogEntry.Subject`), the canvas is the only thing that knows where
/// that is, and the camera goes there.
struct CanvasFocus: Equatable {
    enum Target: Equatable {
        case pawn(UUID)
        /// A `ColonyMap.Placement` id — the lot, not the definition.
        case building(UUID)
        case place(LocalPoint)
    }
    /// A fresh id re-aims even at the same target, so a second raid on the same
    /// ground still takes you back to it.
    let id: UUID
    let target: Target
    var scale: CGFloat = SettlementRenderer.Camera.closeUp

    init(id: UUID = UUID(), target: Target,
         scale: CGFloat = SettlementRenderer.Camera.closeUp) {
        self.id = id
        self.target = target
        self.scale = scale
    }

    /// The focus a journal entry asks for, if it happened to anything.
    init?(_ subject: ColonyLogEntry.Subject?, id: UUID = UUID()) {
        switch subject {
        case let .pawn(who):      self.init(id: id, target: .pawn(who))
        case let .building(lot):  self.init(id: id, target: .building(lot))
        case let .place(spot):    self.init(id: id, target: .place(spot))
        case nil:                 return nil
        }
    }
}

/// What a tap means while a raid is going on.
///
/// The colony is run by standing orders and a battle should not suddenly demand
/// that sixty people be steered one at a time — so this is deliberately the
/// *same* two taps the rest of the canvas already uses: pick somebody, then
/// point. "I go somewhere and do something", in the player's own words.
///
/// Nothing here decides anything. It is handed up to the view model, which
/// writes it onto the siege, where it becomes an input the simulation replays
/// from (`SiegeEngine.order`). Rule 5 is untouched.
enum SiegeCommand: Equatable {
    /// Go there and hold it.
    case move(pawn: UUID, to: LocalPoint)
    /// Go for that one.
    case engage(pawn: UUID, raider: UUID)
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
    /// What the sky is doing (`Climate.weather`). The renderer needs it for one
    /// thing: cloud is what decides whether the moon lights anything.
    var weather: Double = 0
    /// Shipments on the road right now. The legs that cross this valley are
    /// drawn; the rest of the journey is out in country this map does not show.
    var caravans: [Caravan] = []
    /// The made ways arriving at this valley from the world map, so a road
    /// somebody paid for is visible where they live rather than only on the
    /// map of the world.
    var approaches: [RoadApproach] = []
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
    /// Somewhere the game is asking the camera to go. Set it and the view pans
    /// and closes in once, then leaves the camera alone — a camera that keeps
    /// correcting the player is worse than one that never moves.
    var focus: CanvasFocus?
    /// Where a tap goes while a raid is on: an order for the colonist who is
    /// already picked out, rather than another inspection.
    var onSiegeOrder: ((SiegeCommand) -> Void)?

    /// A fixed, *absolute* epoch so the animation clock is stable across
    /// redraws — and so anyone else (the pawn inspector's "right now" line)
    /// can derive the same clock without holding a reference to this view.
    private let start = DayClock.epoch
    @State private var camera = SettlementRenderer.Camera()
    /// The camera as it was when the current gesture began, so pinch and drag
    /// compose from a fixed base instead of accumulating drift.
    @State private var gestureBase = SettlementRenderer.Camera()
    /// The last focus this view actually flew to. SwiftUI re-evaluates the body
    /// thirty times a second here; without it the camera would be re-aimed on
    /// every frame and the player could never pan away from a fire.
    @State private var answered: UUID?

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
                        caravans: caravans, approaches: approaches,
                        seasonProgress: seasonProgress(at: now),
                        weather: weather,
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
            .onChange(of: focus?.id) { _, _ in fly(to: focus, in: geo.size) }
            .onAppear { fly(to: focus, in: geo.size) }
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

    // MARK: - Being taken somewhere

    /// Pans and closes in on whatever the game asked to be shown — **once**.
    ///
    /// Once is the whole discipline of it. The camera is the player's, and a
    /// view that keeps re-centring is a view you cannot look away from; so a
    /// focus is answered the first time it is seen and then never again, and
    /// the next pan or pinch immediately overrules it.
    private func fly(to focus: CanvasFocus?, in size: CGSize) {
        guard let focus, focus.id != answered,
              size.width > 0, size.height > 0,
              let point = place(of: focus.target) else { return }
        answered = focus.id
        let aimed = SettlementRenderer.Camera.framing(point, in: size, scale: focus.scale)
        withAnimation(.easeInOut(duration: 0.55)) { camera = aimed }
        // The next gesture composes from where the flight put us, not from
        // where the camera was before it.
        gestureBase = aimed
    }

    /// Where on the map the thing being pointed at actually is.
    ///
    /// **Presentation answers this, and it has to.** A colonist's position is a
    /// function of `(pawn.id, clock)` and exists only in `AgentMotion`; the
    /// simulation has never held one and must not start (rule 5). So the Core
    /// says *who*, and this says *where they are standing right now*.
    private func place(of target: CanvasFocus.Target) -> LocalPoint? {
        switch target {
        case let .place(spot):
            return spot
        case let .building(lot):
            return SettlementRenderer
                .normalizedLayout(settlement: settlement, registry: registry)
                .first { $0.placementID == lot }?.center
        case let .pawn(id):
            guard let pawn = settlement.pawns.first(where: { $0.id == id }) else { return nil }
            let now = Date()
            let scene = AgentMotion.Scene(settlement: settlement, registry: registry,
                                          continuousTick: clock.continuous(at: now),
                                          replay: battleReplay)
            return AgentMotion.pose(for: pawn, map: map, scene: scene,
                                    time: now.timeIntervalSince(start),
                                    ticksPerYear: registry.config.ticksPerYear).position
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
            // A raid you are standing in: once you have somebody picked out of
            // the line, a tap tells *them* where to go instead of inspecting
            // whatever happens to be under your thumb.
            if let command = siegeOrder(at: value.location, size: size) {
                onSiegeOrder?(command)
                return
            }
            let hit = hitTest(value.location, size: size)
            withAnimation(.easeOut(duration: 0.15)) {
                selection = (hit == selection) ? .none : hit
            }
        }
    }

    /// The order a tap carries, if there is a fight on and somebody in the line
    /// is picked out to carry it.
    ///
    /// Nearest raider wins if the tap landed on one — "take that one" — and
    /// open ground is "go there". The selection is deliberately kept, so a
    /// player can walk one fighter around without re-picking them every time.
    private func siegeOrder(at location: CGPoint, size: CGSize) -> SiegeCommand? {
        guard let siege = settlement.siege, !siege.isFinished,
              case let .pawn(id) = selection,
              siege.line.contains(id), !siege.withdrawn.contains(id) else { return nil }
        let rect = SettlementRenderer.worldRect(
            viewRect: CGRect(origin: .zero, size: size), camera: camera)

        var mark: UUID?
        var nearest = touchRadius * touchRadius
        for raider in siege.raiders where !raider.down {
            let p = SettlementRenderer.point(raider.at, in: rect)
            let dx = p.x - location.x, dy = p.y - location.y
            let d2 = dx * dx + dy * dy
            guard d2 < nearest else { continue }
            nearest = d2
            mark = raider.id
        }
        if let mark { return .engage(pawn: id, raider: mark) }
        return .move(pawn: id, to: SettlementRenderer.normalised(location, in: rect))
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

        // The same cull the drawing uses, so a tap can only ever land on a
        // roof that is actually on screen.
        for building in SettlementRenderer.layout(
            settlement: settlement, registry: registry, rect: rect,
            viewport: viewRect) {
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
        // Outsiders on your ground: a trader's party, an envoy under a
        // standard, a family the winter turned out. They are drawn walking in
        // and were the one kind of *person* on the map that answered nothing.
        for visitor in map.visitors where map.isExplored(visitor.position) {
            probe.offer(.landmark(visitorLabel(visitor)),
                        at: SettlementRenderer.point(visitor.position, in: rect))
        }
        // …and your own carts, on the road between your towns.
        for caravan in caravans {
            guard let leg = SettlementConvoys.position(
                of: caravan, for: settlement.id) else { continue }
            probe.offer(.landmark(caravanLabel(caravan, outbound: leg.outbound)),
                        at: SettlementRenderer.point(leg.position, in: rect))
        }
        if let hit = probe.take() { return hit }

        // The things lying about: a heap of timber at the stump that is on its
        // way in, the wood it came out of, the rock somebody is cutting into.
        for pile in map.piles where map.isExplored(pile.position) {
            probe.offer(.thing(target: .pile(pile.id), label: pileLabel(pile)),
                        at: SettlementRenderer.point(pile.position, in: rect))
        }
        for tree in map.trees where map.isExplored(tree.position) {
            probe.offer(.thing(target: .tree(tree.id), label: treeLabel(tree)),
                        at: SettlementRenderer.point(tree.position, in: rect))
        }
        for rock in map.rocks where map.isExplored(rock.position) {
            probe.offer(.thing(target: .rock(rock.id), label: rockLabel(rock)),
                        at: SettlementRenderer.point(rock.position, in: rect))
        }
        // The land's own furniture: flowers, reeds, a snag, a cactus, the
        // mushrooms under the wood. Drawn since the beginning and, until now,
        // the one layer of the valley with nothing to say for itself.
        for prop in map.scenery where map.isExplored(prop.position) {
            probe.offer(.landmark(sceneryLabel(prop.kind)),
                        at: SettlementRenderer.point(prop.position, in: rect))
        }
        if let hit = probe.take() { return hit }

        // The land answers last: deposits with their fullness.
        //
        // Only the ones that *are* a patch. A wood is trees and a massif is
        // blocks — both already answer for themselves, above — so offering the
        // node as well put a second, invisible "Forest · 87 %" target on top of
        // the trees and stole the tap from them.
        for node in settlement.localMap?.nodes ?? []
        where map.isExplored(node.position) && !FloraEngine.isEntityBacked(node.kind, in: map) {
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

    private func visitorLabel(_ visitor: Visitor) -> String {
        let cs = AppStrings.language == .cs
        let name = visitor.kind.displayName.resolve(AppStrings.language)
        let doing: String
        switch visitor.phase {
        case .arriving: doing = cs ? "přichází" : "on their way in"
        case .visiting: doing = cs ? "je ve městě" : "here"
        case .leaving:  doing = cs ? "odchází" : "on their way out"
        }
        return "\(name) · \(doing)"
    }

    private func caravanLabel(_ caravan: Caravan, outbound: Bool) -> String {
        let cs = AppStrings.language == .cs
        let what = caravan.resource.displayName
        let way = outbound ? (cs ? "odváží" : "carrying out") : (cs ? "veze" : "bringing in")
        return "\(way) \(Int(caravan.cargo)) \(what)"
    }

    private func sceneryLabel(_ kind: SceneryKind) -> String {
        let name = kind.displayName.resolve(AppStrings.language)
        guard let note = kind.note?.resolve(AppStrings.language) else { return name }
        return "\(name) · \(note)"
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
