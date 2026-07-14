import Foundation
import EndlessFrontierCore

/// Purely presentational movement for the living settlement view. Positions are
/// derived from each colonist's stable id and a continuous frame clock — never
/// written back to the simulation, so the deterministic Core is untouched and
/// the world just *looks* alive.
///
/// The motion is deliberately calm: colonists drift around a role-appropriate
/// anchor and occasionally amble toward the settlement's heart, so the scene
/// reads as a working village rather than a swarm.
enum AgentMotion {
    /// Where a colonist appears on the local map (normalised 0…1) at `time`.
    static func position(for pawn: Pawn, map: LocalMap, time: Double) -> LocalPoint {
        let seed = hash(pawn.id)
        let phase = unit(seed) * 2 * .pi
        let anchor = anchor(for: pawn, map: map, seed: seed)

        // A slow personal drift around the anchor (a small Lissajous figure).
        let driftSpeed = 0.18 + unit(seed &>> 8) * 0.14
        let t = time * driftSpeed + phase
        let driftX = sin(t) * driftAmplitude
        let driftY = cos(t * 0.8 + phase) * driftAmplitude

        // An occasional amble between the anchor and the village heart, eased
        // so colonists pause at each end rather than pacing mechanically.
        let commutePhase = time * 0.05 + phase
        let raw = 0.5 - 0.5 * cos(commutePhase)            // 0…1
        let commute = smoothstep(raw) * commuteReach
        let toCenterX = (center.x - anchor.x) * commute
        let toCenterY = (center.y - anchor.y) * commute

        let x = clamp(anchor.x + driftX + toCenterX)
        let y = clamp(anchor.y + driftY + toCenterY)
        return LocalPoint(x: x, y: y)
    }

    /// A little walk-cycle phase (0…2π) for the leg swing, per colonist.
    static func gaitPhase(for pawn: Pawn, time: Double) -> Double {
        let seed = hash(pawn.id)
        let speed = 4.0 + unit(seed &>> 16) * 2.5
        return time * speed + unit(seed) * 2 * .pi
    }

    // MARK: - Anchors

    private static let center = LocalPoint(x: 0.5, y: 0.52)
    private static let driftAmplitude = 0.03
    private static let commuteReach = 0.55

    /// The home base a colonist orbits: their work deposit if they gather, a
    /// wild fringe for hunters, otherwise a spot in the ring of buildings.
    private static func anchor(for pawn: Pawn, map: LocalMap, seed: UInt64) -> LocalPoint {
        if let deposit = pawn.assignedWork.harvestedDeposit {
            let matching = map.nodes.filter { $0.kind == deposit }
            if !matching.isEmpty {
                return matching[Int(seed % UInt64(matching.count))].position
            }
        }
        if pawn.assignedWork == .hunting {
            // Hunters range the wild edges, away from the built-up heart.
            let angle = unit(seed) * 2 * .pi
            return LocalPoint(x: clamp(0.5 + cos(angle) * 0.34),
                              y: clamp(0.5 + sin(angle) * 0.30))
        }
        // Everyone else lives in a ring around the settlement's centre.
        let idx = Double(seed % 12)
        let angle = idx / 12 * 2 * .pi
        let radius = 0.1 + unit(seed &>> 4) * 0.06
        return LocalPoint(x: clamp(center.x + cos(angle) * radius),
                          y: clamp(center.y + sin(angle) * radius))
    }

    // MARK: - Maths

    private static func smoothstep(_ x: Double) -> Double {
        let c = min(1, max(0, x))
        return c * c * (3 - 2 * c)
    }

    private static func clamp(_ v: Double) -> Double { min(0.98, max(0.02, v)) }

    /// A stable [0,1) value from a 64-bit seed.
    private static func unit(_ seed: UInt64) -> Double {
        var h = seed &* 0x2545_F491_4F6C_DD1D
        h ^= h &>> 32
        return Double(h & 0xFFFF_FFFF) / Double(0x1_0000_0000)
    }

    private static func hash(_ id: UUID) -> UInt64 {
        let b = id.uuid
        var h: UInt64 = 0xCBF2_9CE4_8422_2325
        h = (h ^ UInt64(b.0)) &* 0x0100_0000_01B3
        h = (h ^ UInt64(b.3)) &* 0x0100_0000_01B3
        h = (h ^ UInt64(b.7)) &* 0x0100_0000_01B3
        h = (h ^ UInt64(b.11)) &* 0x0100_0000_01B3
        h = (h ^ UInt64(b.15)) &* 0x0100_0000_01B3
        return h
    }
}
