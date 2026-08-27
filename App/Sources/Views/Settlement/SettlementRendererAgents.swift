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

    static func agents(
        _ context: inout GraphicsContext, rect: CGRect, settlement: Settlement,
        map: LocalMap, continuousTick: Double, registry: GameDataRegistry,
        time: Double, zoom: CGFloat, selectedPawnID: UUID?,
        battleReplay: SettlementBattle.Replay? = nil
    ) {
        let scene = AgentMotion.Scene(settlement: settlement, registry: registry,
                                      continuousTick: continuousTick, replay: battleReplay)
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
                        SettlementFigures.draw(
                            pawn: pawn, pose: pose, at: point(pose.position, in: rect),
                            time: time, ticksPerYear: ticksPerYear,
                            selected: pawn.id == selectedPawnID, zoom: zoom,
                            motion: registry.motion(activity: pose.activity.motionID,
                                        work: pawn.assignedWork.rawValue,
                                        phase: AgentMotion.huntPhase(
                                            for: pawn,
                                            reported: settlement.huntPhases[pawn.id],
                                            map: map, at: pose.position),
                                        variant: AgentMotion.motionVariant(for: pawn),
                                        building: AgentMotion.workBuilding(for: pawn, scene: scene)),
                            registry: registry, context: &context)
                    }
                    continue
                }
                SettlementCrowd.draw(&context, cluster: cluster,
                                     at: point(cluster.position, in: rect),
                                     time: time, zoom: zoom)
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
            var at = point(pose.position, in: rect)
            if let ridden, let carriage {
                SettlementConveyances.draw(
                    carriage, thing: ridden, at: at,
                    s: SettlementFigures.bodyHeight(zoom: zoom), facing: CGFloat(pose.facing),
                    time: time, loaded: pawn.carrying != nil,
                    beast: ridden.animalID.flatMap { id in
                        settlement.tamed.first { $0.id == id }?.animal.build
                    },
                    context: &context)
                // Somebody on a beast sits above it; somebody walking beside a
                // cart does not move at all.
                if carriage.kind == .mount {
                    at.y -= SettlementFigures.bodyHeight(zoom: zoom) * 0.62
                }
            }
            SettlementFigures.draw(
                pawn: pawn, pose: pose, at: at,
                time: time, ticksPerYear: ticksPerYear,
                selected: pawn.id == selectedPawnID, zoom: zoom, armed: armed,
                motion: registry.motion(activity: pose.activity.motionID,
                                        work: pawn.assignedWork.rawValue,
                                        phase: AgentMotion.huntPhase(
                                            for: pawn,
                                            reported: settlement.huntPhases[pawn.id],
                                            map: map, at: pose.position),
                                        variant: AgentMotion.motionVariant(for: pawn),
                                        building: AgentMotion.workBuilding(for: pawn, scene: scene),
                                        conveyance: carriage),
                registry: registry, context: &context)
        }
    }

    // MARK: - Fog of war

}
