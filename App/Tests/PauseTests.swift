import Testing
import Foundation
@testable import EndlessFrontier
@testable import EndlessFrontierCore

/// **Standing the world still.**
///
/// The game had no pause. A decision card arrived while the colony carried on
/// around it, so by the time the three choices had been read the moment they
/// were about had moved on — Keks: *"věci se dějí ale ty si řekneš u těch
/// eventů ok stalo se, nijak neovlivním"* — and a raid played out over a
/// running simulation with everything else still happening on top of it.
///
/// The trap this has to avoid is the interesting one: ticks are derived from
/// `lastRealTimestamp` against the wall clock, so a pause that merely stops
/// calling `advanceLive` hands the whole paused duration over on resume. A
/// pause would then *cause* the catch-up it exists to prevent.
@MainActor
@Suite("Pausing the world")
struct PauseTests {

    /// A view model on a **throwaway save**. The default store is the player's
    /// real one, and a test that pauses their colony and moves its clock is not
    /// a test, it is a bug with a `@Test` on it.
    private func game(_ shape: ((inout WorldState) -> Void)? = nil) -> GameViewModel {
        let temp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("pause-\(UUID().uuidString).json")
        let registry = (try? GameDataRegistry.bundled()) ?? GameDataRegistry()
        let store = WorldStore(url: temp)
        // `world` is `private(set)`, which is right — nothing outside the view
        // model may write the simulation. A test that needs a particular world
        // hands it in the way the app does: through the save.
        if let shape {
            var seeded = GameWorldFactory.newGame(registry: registry, seed: 4242)
            shape(&seeded)
            try? store.save(seeded)
        }
        return GameViewModel(registry: registry, store: store)
    }

    /// A world with one card already on the desk.
    private func waiting() -> GameViewModel? {
        let registry = (try? GameDataRegistry.bundled()) ?? GameDataRegistry()
        guard let template = registry.events.first else { return nil }
        return game { $0.pendingEvents = [PendingEvent(templateID: template.id, tick: $0.tick)] }
    }

    @Test("A new world is running")
    func startsRunning() {
        let g = game()
        #expect(!g.isPaused)
        #expect(g.pauseHeadline == nil)
    }

    @Test("A paused world does not advance")
    func pausedWorldHolds() {
        let g = game()
        let start = Date()
        g.setPaused(true, now: start)
        let tick = g.world.tick
        // Well past a tick's worth of real time.
        g.advanceLive(now: start.addingTimeInterval(600))
        #expect(g.world.tick == tick, "the world moved while it was stopped")
    }

    /// The whole point of carrying `lastRealTimestamp` forward.
    @Test("Resuming does not dump the paused time on the colony")
    func resumeDoesNotCatchUp() {
        let g = game()
        let start = Date()
        let before = g.world.lastRealTimestamp
        g.setPaused(true, now: start)
        // Ten minutes of standing still.
        g.setPaused(false, now: start.addingTimeInterval(600))
        let carried = g.world.lastRealTimestamp.timeIntervalSince(before)
        #expect(abs(carried - 600) < 1,
                "the stamp moved \(carried)s for a 600s pause — resume would replay it")
    }

    @Test("A resumed world runs again")
    func resumeRuns() {
        let g = game()
        let start = Date()
        g.setPaused(true, now: start)
        g.setPaused(false, now: start)
        #expect(!g.isPaused)
    }

    @Test("Pausing twice does not lose the first pause's clock")
    func doublePauseIsIdempotent() {
        let g = game()
        let start = Date()
        g.setPaused(true, now: start)
        // A second ask 60s later must not reset when it stopped, or that
        // minute is silently handed back to the colony on resume.
        g.setPaused(true, now: start.addingTimeInterval(60))
        let before = g.world.lastRealTimestamp
        g.setPaused(false, now: start.addingTimeInterval(120))
        let carried = g.world.lastRealTimestamp.timeIntervalSince(before)
        #expect(abs(carried - 120) < 1, "carried \(carried)s, not the full 120s")
    }

    @Test("Every reason for stopping says so in the player's language")
    func everyReasonSpeaks() {
        for reason in [GameViewModel.PauseReason.player, .siege, .decision] {
            let g = game()
            g.setPaused(true, reason: reason)
            let headline = g.pauseHeadline
            #expect(headline != nil && !(headline!.isEmpty),
                    "\(reason) stops the world and does not say why")
        }
    }

    /// **Where most decisions actually come from.** Edge-detection across one
    /// live tick was the obvious way and the wrong one: a card that arrived
    /// while the years were being replayed never crossed that edge, so the
    /// player came back to a decision that had been waiting and a colony
    /// carrying on around it — the complaint, exactly.
    @Test("A decision already waiting stops the world")
    func aWaitingDecisionStops() throws {
        guard let g = waiting() else { return }
        g.stopForAnythingImportant()
        #expect(g.isPaused)
        #expect(g.pause == .decision)
    }

    /// …and stops **once**. Resuming while the same card is still on the desk
    /// must not immediately re-pause, or the resume button does nothing.
    @Test("Resuming does not re-stop for the decision already answered for")
    func resumeSticksWhileTheSameCardStands() throws {
        guard let g = waiting() else { return }
        g.stopForAnythingImportant()
        g.setPaused(false)
        g.stopForAnythingImportant()
        #expect(!g.isPaused, "the same card stopped the world twice — resume is a no-op")
    }

    @Test("A world with nothing waiting stops for nothing")
    func quietWorldRuns() {
        let g = game { $0.pendingEvents = [] }
        g.stopForAnythingImportant()
        #expect(!g.isPaused)
    }

    @Test("Turning auto-pause off leaves the world running")
    func theSettingIsHonoured() throws {
        guard let g = waiting() else { return }
        let was = g.pausesForImportantThings
        defer { g.pausesForImportantThings = was }
        g.pausesForImportantThings = false
        g.stopForAnythingImportant()
        #expect(!g.isPaused)
    }

    @Test("Only a raid and a decision stop the world by themselves")
    func onlyTwoAreAutomatic() {
        #expect(GameViewModel.PauseReason.siege.isAutomatic)
        #expect(GameViewModel.PauseReason.decision.isAutomatic)
        #expect(!GameViewModel.PauseReason.player.isAutomatic)
    }
}
