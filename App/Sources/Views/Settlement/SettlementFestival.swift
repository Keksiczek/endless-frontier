import SwiftUI
import EndlessFrontierCore

/// **Midsummer, on the green.**
///
/// `FestivalEngine` spends three months' rations in a night, lifts every mood
/// in the colony and writes a line in the journal — and the canvas drew nothing
/// at all, because the feast was one tick's arithmetic and left nothing behind
/// to draw. `Settlement.lastFestival` is that record now, and this is the
/// picture of it: a fire on the square, and the light it throws.
///
/// **Derived, never written** (rule 1). How far through the fires are comes
/// from `(tick, lastFestival.tick)` and how big they are from the lavishness
/// the engine already worked out — a lean year's fire is a small one.
enum SettlementFestival {

    /// How many ticks the fires burn for after the night itself. A tick is two
    /// real minutes, so this is about a quarter of an hour of watching: long
    /// enough to walk over and look, short enough that a colony is not
    /// permanently at a party.
    static let burnsFor = 4

    /// How far through the burning it is, 0…1 — or nil when there is no fire.
    static func burning(_ settlement: Settlement, tick: Double) -> (age: Double, lavishness: Double)? {
        guard let record = settlement.lastFestival else { return nil }
        let age = (tick - Double(record.tick)) / Double(burnsFor)
        guard age >= 0, age <= 1 else { return nil }
        return (age, record.lavishness)
    }

    static func draw(
        _ context: inout GraphicsContext, rect: CGRect, settlement: Settlement,
        tick: Double, time: Double, zoom: CGFloat
    ) {
        guard let fire = burning(settlement, tick: tick) else { return }
        let at = SettlementRenderer.point(SettlementGeometry.heart, in: rect)
        // A lean year is a small fire: the drawing is as thin as the feast was.
        let s = max(3, 9 * zoom) * CGFloat(0.55 + fire.lavishness * 0.65)
        // Guttering out towards the end, so the square empties rather than
        // switching off.
        let strength = (1 - fire.age) * (0.35 + fire.lavishness * 0.65)

        // The ring of stones the fire is built in — laid once, and still there
        // when the flames have gone.
        context.stroke(
            Path(ellipseIn: CGRect(x: at.x - s, y: at.y - s * 0.5, width: s * 2, height: s)),
            with: .color(Theme.bone.opacity(0.35)), lineWidth: 0.8)

        guard strength > 0.02 else { return }
        // The flames: three tongues on their own beat, so it moves without
        // anything in the simulation moving.
        var flame = Path()
        for i in 0..<3 {
            let lean = CGFloat(sin(time * (1.6 + Double(i) * 0.4) + Double(i))) * s * 0.22
            let x = at.x - s * 0.4 + s * 0.4 * CGFloat(i)
            flame.move(to: CGPoint(x: x, y: at.y))
            flame.addQuadCurve(to: CGPoint(x: x + lean * 0.4, y: at.y - s * (1.1 + CGFloat(i) * 0.2)),
                               control: CGPoint(x: x + lean, y: at.y - s * 0.6))
        }
        context.stroke(flame, with: .color(Theme.accent.opacity(0.55 * strength)),
                       style: StrokeStyle(lineWidth: max(0.8, s * 0.12), lineCap: .round))
        context.fill(
            Path(ellipseIn: CGRect(x: at.x - s * 0.5, y: at.y - s * 0.35,
                                   width: s, height: s * 0.7)),
            with: .color(Theme.accent.opacity(0.28 * strength)))
    }

    /// The light the fire throws, for the lamp pass — a feast at midnight is
    /// the one time the middle of a town is the brightest thing in it.
    static func lamps(
        _ settlement: Settlement, rect: CGRect, tick: Double, zoom: CGFloat
    ) -> [SettlementLight.Lamp] {
        guard let fire = burning(settlement, tick: tick) else { return [] }
        let strength = (1 - fire.age) * (0.3 + fire.lavishness * 0.7)
        guard strength > 0.02 else { return [] }
        return [SettlementLight.Lamp(
            at: SettlementRenderer.point(SettlementGeometry.heart, in: rect),
            radius: 150 * zoom, strength: 0.34 * strength,
            colour: SettlementLight.hearth, phase: 0)]
    }
}
