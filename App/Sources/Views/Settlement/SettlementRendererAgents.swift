import SwiftUI
import EndlessFrontierCore

/// **The people on the ground.**
///
/// Which colonists are drawn, and where — every position here comes from
/// `AgentMotion`, which derives it from `(pawn.id, frame clock)`. Nothing in
/// this file may feed back into `WorldState` (rule 1).
extension SettlementRenderer {
    /// Who gets drawn when the crowd is capped.
    ///
    /// The cap keeps a boom-town cheap, but taking a plain `prefix` means that
    /// in a colony past ninety souls the party out at the ruins — the one thing
    /// the player is deliberately watching — could fall off the end of the array
    /// and simply not be drawn. Anyone away goes in first; the rest fill the
    /// remaining seats.
    static func visibleAgents(_ settlement: Settlement) -> [Pawn] {
        guard settlement.pawns.count > maxVisibleAgents else { return settlement.pawns }
        let away = settlement.pawns.filter(\.isAway)
        guard !away.isEmpty else { return Array(settlement.pawns.prefix(maxVisibleAgents)) }
        let home = settlement.pawns.filter { !$0.isAway }
        return away + home.prefix(max(0, maxVisibleAgents - away.count))
    }

    /// **The people, as standing things.**
    ///
    /// One entry per person or crowd mark, each with the ground it stands on,
    /// so the town's own sorted pass can draw a colonist in front of the house
    /// they are walking past and behind the one they are walking behind. Drawn
    /// as a block after the buildings — which is what this was — every
    /// colonist in the colony stood in front of every roof in it.
    static func standingAgents(
        rect: CGRect, settlement: Settlement,
        map: LocalMap, continuousTick: Double, registry: GameDataRegistry,
        time: Double, zoom: CGFloat, selectedPawnID: UUID?,
        battleReplay: SettlementBattle.Replay? = nil,
        battleBeat: SettlementBattle.Beat? = nil
    ) -> [(foot: CGFloat, draw: (inout GraphicsContext) -> Void)] {
        var standing: [(foot: CGFloat, draw: (inout GraphicsContext) -> Void)] = []
        agents(rect: rect, settlement: settlement, map: map, continuousTick: continuousTick,
               registry: registry, time: time, zoom: zoom, selectedPawnID: selectedPawnID,
               battleReplay: battleReplay, battleBeat: battleBeat) { foot, draw in
            standing.append((foot: foot, draw: draw))
        }
        return standing
    }

    /// Draw everybody where they stand, ignoring what they are standing in
    /// front of. Kept for a thumbnail and for the tests, which want the whole
    /// crowd and no town.
    static func agents(
        _ context: inout GraphicsContext, rect: CGRect, settlement: Settlement,
        map: LocalMap, continuousTick: Double, registry: GameDataRegistry,
        time: Double, zoom: CGFloat, selectedPawnID: UUID?,
        battleReplay: SettlementBattle.Replay? = nil,
        battleBeat: SettlementBattle.Beat? = nil
    ) {
        var copy = context
        for item in standingAgents(rect: rect, settlement: settlement, map: map,
                                   continuousTick: continuousTick, registry: registry,
                                   time: time, zoom: zoom, selectedPawnID: selectedPawnID,
                                   battleReplay: battleReplay, battleBeat: battleBeat)
            .sorted(by: { $0.foot < $1.foot }) {
            item.draw(&copy)
        }
        context = copy
    }

    /// The one place a person is turned into a drawing. Everything above is
    /// about *when* to run these; this is what they are.
    private static func agents(
        rect: CGRect, settlement: Settlement,
        map: LocalMap, continuousTick: Double, registry: GameDataRegistry,
        time: Double, zoom: CGFloat, selectedPawnID: UUID?,
        battleReplay: SettlementBattle.Replay?,
        battleBeat: SettlementBattle.Beat?,
        emit: (CGFloat, @escaping (inout GraphicsContext) -> Void) -> Void
    ) {
        let scene = AgentMotion.Scene(settlement: settlement, registry: registry,
                                      continuousTick: continuousTick, replay: battleReplay,
                                      battleBeat: battleBeat)
        let ticksPerYear = registry.config.ticksPerYear
        let close = SettlementCrowd.showsIndividuals(zoom: zoom)

        // Pushed in, people are people. Pulled back, a town of sixty drawn as
        // sixty eleven-pixel figures is a smear — so they gather into group
        // marks that say how many and at what, and resolve back into people as
        // the camera comes in.
        guard close else {
            let standing = visibleAgents(settlement).compactMap {
                pawn -> (id: UUID, position: LocalPoint, trade: WorkKind, hurt: Bool)? in
                let pose = AgentMotion.pose(for: pawn, map: map, scene: scene,
                                            time: time, ticksPerYear: ticksPerYear)
                guard map.isExplored(pose.position) else { return nil }
                return (pawn.id, pose.position, pawn.assignedWork,
                        pawn.body.needsTending || pawn.isBroken)
            }
            for cluster in SettlementCrowd.cluster(standing) {
                guard cluster.count >= SettlementCrowd.minimumGroup else {
                    // Two people read better as two people than as a mark
                    // saying "2".
                    for id in cluster.members {
                        guard let pawn = settlement.pawns.first(where: { $0.id == id }) else { continue }
                        let pose = AgentMotion.pose(for: pawn, map: map, scene: scene,
                                                    time: time, ticksPerYear: ticksPerYear)
                        let at = point(pose.position, in: rect)
                        let motion = registry.motion(
                            activity: pose.activity.motionID,
                            work: pawn.assignedWork.rawValue,
                            phase: AgentMotion.huntPhase(
                                for: pawn,
                                reported: settlement.huntPhases[pawn.id],
                                map: map, at: pose.position),
                            variant: AgentMotion.motionVariant(for: pawn),
                            building: AgentMotion.workBuilding(for: pawn, scene: scene))
                        emit(at.y) { context in
                            SettlementFigures.draw(
                                pawn: pawn, pose: pose, at: at,
                                time: time, ticksPerYear: ticksPerYear,
                                selected: pawn.id == selectedPawnID, zoom: zoom,
                                motion: motion, registry: registry, context: &context)
                        }
                    }
                    continue
                }
                let mark = point(cluster.position, in: rect)
                emit(mark.y) { context in
                    SettlementCrowd.draw(&context, cluster: cluster, at: mark,
                                         time: time, zoom: zoom)
                }
            }
            return
        }

        for pawn in visibleAgents(settlement) {
            let pose = AgentMotion.pose(for: pawn, map: map, scene: scene,
                                        time: time, ticksPerYear: ticksPerYear)
            guard map.isExplored(pose.position) else { continue }
            // What they would do with what they are carrying — the same split
            // the simulation fights on, so a bow is drawn being drawn.
            // What is actually in their hands. A colony's militia is its
            // farmers: somebody who owns nothing swings the tool of their
            // trade, and somebody whose trade has no edge on it swings fists.
            // **What they are actually holding**, not which of two families it
            // belongs to. `weaponProfile` carries the whole weapon now, so a
            // crossbow is not a bow and a musket is not a crossbow.
            let armed: SettlementFigures.Armament = CombatEngine
                .weaponProfile(pawn, registry: registry)
                .map { .held($0) } ?? .none
            // What they are on, if the yard put them on something. Drawn
            // first, so the body sits on it rather than behind it — and asked
            // of the motion bank too, because a rider's legs do not walk.
            let ridden = scene.ridden[pawn.id]
            let carriage = ridden.flatMap { registry.conveyance($0.definitionID) }
            let ground = point(pose.position, in: rect)
            var at = ground
            // Somebody on a beast sits above it; somebody walking beside a
            // cart does not move at all. The **foot** is the ground either way
            // — that is what the depth sort compares.
            if let carriage, carriage.kind == .mount {
                at.y -= SettlementFigures.bodyHeight(zoom: zoom) * 0.62
            }
            let beast = ridden?.animalID.flatMap { id in
                settlement.tamed.first { $0.id == id }?.animal.build
            }
            let motion = registry.motion(
                activity: pose.activity.motionID,
                work: pawn.assignedWork.rawValue,
                phase: AgentMotion.huntPhase(
                    for: pawn,
                    reported: settlement.huntPhases[pawn.id],
                    map: map, at: pose.position),
                variant: AgentMotion.motionVariant(for: pawn),
                building: AgentMotion.workBuilding(for: pawn, scene: scene),
                conveyance: carriage)
            let carrying = pawn.carrying != nil
            emit(ground.y) { context in
                // What they are on, if the yard put them on something. Drawn
                // first, so the body sits on it rather than behind it.
                if let ridden, let carriage {
                    SettlementConveyances.draw(
                        carriage, thing: ridden, at: ground,
                        s: SettlementFigures.bodyHeight(zoom: zoom),
                        facing: CGFloat(pose.facing),
                        time: time, loaded: carrying, beast: beast, context: &context)
                }
                SettlementFigures.draw(
                    pawn: pawn, pose: pose, at: at,
                    time: time, ticksPerYear: ticksPerYear,
                    selected: pawn.id == selectedPawnID, zoom: zoom, armed: armed,
                    motion: motion, registry: registry, context: &context)
            }
        }
    }

    // MARK: - Fog of war

}
