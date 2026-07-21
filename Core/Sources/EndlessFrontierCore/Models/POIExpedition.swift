import Foundation

/// A party of colonists sent out to work a point of interest: who went, where,
/// and how far through the journey they are.
///
/// The first cut of `LocalPOIEngine` paid out the moment the player pressed the
/// button — the goods appeared, nobody moved, and the ruins on the far side of
/// the valley cost exactly as much as the spring next door. An expedition is
/// the same interaction made *physical*: named people leave the settlement,
/// their hands are missing from the fields while they are gone, the walk takes
/// as long as the distance says, and the haul only lands when they are home.
///
/// Everything here is derived from tick arithmetic rather than stored progress,
/// so a save resumed after three days of offline catch-up lands in exactly the
/// state it would have reached had the app stayed open.
public struct POIExpedition: Codable, Sendable, Equatable, Identifiable {
    /// Where a party is in its journey.
    public enum Phase: String, Codable, Sendable {
        case outbound   // walking out
        case working    // at the place, doing what it holds
        case returning  // walking home, carrying whatever they found
    }

    public let id: UUID
    public let poiID: Int
    /// Who went. Order is stable so the canvas can fan them out predictably.
    public let memberIDs: [UUID]
    public let departedTick: Int
    /// Ticks of walking *each way* — a function of how far the place is.
    public let travelTicks: Int
    /// Ticks spent working once they arrive.
    public let workTicks: Int
    /// Set during the working phase if the place hurt someone, so the party
    /// carries the news home rather than the injury landing out of nowhere.
    public var casualtyID: UUID?
    public var casualtyDied: Bool

    public init(id: UUID, poiID: Int, memberIDs: [UUID], departedTick: Int,
                travelTicks: Int, workTicks: Int,
                casualtyID: UUID? = nil, casualtyDied: Bool = false) {
        self.id = id
        self.poiID = poiID
        self.memberIDs = memberIDs
        self.departedTick = departedTick
        self.travelTicks = max(1, travelTicks)
        self.workTicks = max(1, workTicks)
        self.casualtyID = casualtyID
        self.casualtyDied = casualtyDied
    }

    // MARK: - Where the party is
    //
    // One clock, one vocabulary. This type used to answer the same question
    // three different ways — by world tick, by absolute action step, and by a
    // fractional tick for the canvas — which is how a codebase ends up with a
    // march that means one thing to the simulation and another to the drawing.
    // Action steps are the truth; everything else is derived from them.

    /// The absolute action step the party set out on. A party leaves at the top
    /// of its world tick, so this is exact rather than an approximation.
    public var departedStep: Int { departedTick * WorldClock.actionStepsPerTick }
    public var travelSteps: Int { travelTicks * WorldClock.actionStepsPerTick }
    public var workSteps: Int { workTicks * WorldClock.actionStepsPerTick }
    public var totalSteps: Int { totalTicks * WorldClock.actionStepsPerTick }

    /// Total world ticks from setting out to walking back through the gate.
    public var totalTicks: Int { travelTicks * 2 + workTicks }

    /// Action steps walked since departure. Fractional so the canvas can ask
    /// between two steps without a second API to do it with.
    public func elapsedSteps(at step: Double) -> Double { max(0, step - Double(departedStep)) }

    /// Where the party is, or `nil` once it is home and done.
    public func phase(atStep step: Double) -> Phase? {
        let e = elapsedSteps(at: step)
        if e < Double(travelSteps) { return .outbound }
        if e < Double(travelSteps + workSteps) { return .working }
        if e < Double(totalSteps) { return .returning }
        return nil
    }

    /// How far through the current phase the party is, 0…1.
    public func phaseProgress(atStep step: Double) -> Double {
        let e = elapsedSteps(at: step)
        switch phase(atStep: step) {
        case .outbound:  return min(1, e / Double(travelSteps))
        case .working:   return min(1, (e - Double(travelSteps)) / Double(workSteps))
        case .returning: return min(1, (e - Double(travelSteps + workSteps)) / Double(travelSteps))
        case nil:        return 1
        }
    }

    public func isFinished(atStep step: Double) -> Bool { phase(atStep: step) == nil }

    // MARK: - Asking with a clock

    public func phase(at clock: WorldClock) -> Phase? {
        phase(atStep: Double(clock.absoluteStep))
    }

    public func phaseProgress(at clock: WorldClock) -> Double {
        phaseProgress(atStep: Double(clock.absoluteStep))
    }

    public func isFinished(at clock: WorldClock) -> Bool {
        isFinished(atStep: Double(clock.absoluteStep))
    }

    /// Whether the party has just arrived at the site on this exact step — the
    /// moment the work, and its risk, begins.
    public func arrivesAtSite(_ clock: WorldClock) -> Bool {
        Int(elapsedSteps(at: Double(clock.absoluteStep))) == travelSteps
    }

    /// World ticks until the party is home, rounded up — what the card shows.
    public func ticksRemaining(at clock: WorldClock) -> Int {
        let left = Double(totalSteps) - elapsedSteps(at: Double(clock.absoluteStep))
        guard left > 0 else { return 0 }
        return Int((left / Double(WorldClock.actionStepsPerTick)).rounded(.up))
    }

    /// How far through the whole journey, 0…1 — a bar that only ever fills.
    public func journeyProgress(at clock: WorldClock) -> Double {
        guard totalSteps > 0 else { return 1 }
        return min(1, elapsedSteps(at: Double(clock.absoluteStep)) / Double(totalSteps))
    }
}
