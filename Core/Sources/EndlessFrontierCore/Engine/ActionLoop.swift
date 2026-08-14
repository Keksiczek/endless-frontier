import Foundation

/// The inside of a world tick.
///
/// `TickEngine` runs the civilisation: harvests, births, wages, seasons, laws.
/// Those are world-tick things and they stay exactly where they were. This runs
/// the *other* kind of thing — what people are physically doing — on the finer
/// grid `WorldClock` defines, so a march, a shift and a fight advance several
/// times inside the tick the harvest lands on.
///
/// Why it matters beyond tidiness: a party used to cross the valley in whole
/// world-tick jumps, and the canvas covered for it by interpolating between
/// them. That interpolation was a guess about a position the simulation never
/// held. Now the position exists, at eight times the resolution, and the
/// drawing is a reading of the world rather than a plausible story about it.
///
/// Deterministic like everything else: every system here is a pure function of
/// `(state, clock, registry)`.
public enum ActionLoop {
    /// Advances one action step. Called `WorldClock.actionStepsPerTick` times
    /// per world tick, before the world systems settle the tick.
    public static func advanceStep(
        _ state: WorldState, clock: WorldClock, registry: GameDataRegistry
    ) -> WorldState {
        var s = state
        var concluded: [Siege] = []
        s.settlements = s.settlements.map { settlement in
            var next = LocalPOIEngine.advanceStep(settlement, clock: clock,
                                                  mapSeed: s.mapSeed, registry: registry)
            // People crossing their own colony: somebody carrying a load in
            // from the woods, and somebody who has left their work because they
            // are hungry or cold. Both used to be world-tick things, which made
            // the shortest possible walk an in-game week long and — at eight
            // times too coarse and thirty times too slow — turned the whole
            // working half of the town into scenery. See `WalkPace`.
            //
            // Errands before hauling, and both before the tick's own systems,
            // so a meal eaten on this step is a mood on this tick and a sack
            // carried in on it is on the shelf for the kitchens.
            if ErrandEngine.hasBusiness(next) {
                next = ErrandEngine.advanceStep(
                    next, registry: registry, clock: clock,
                    laws: SocietyEngine.modifiers(next, registry: registry))
            }
            next = HaulEngine.advanceStep(next, registry: registry, clock: clock)
            // …and the people walking in from outside the valley. A trader with
            // mules crossing your fields is a body over ground like any other,
            // and it was the last one still measured per world tick — thirty-
            // four real minutes to reach the square. What they came *for* stays
            // on the tick; see `VisitorEngine.advanceStep`.
            next = VisitorEngine.advanceStep(next, clock: clock)
            // A raid the player is in the middle of fighting.
            //
            // The app drives a live siege *ahead* of the world clock, at a pace
            // a person can give an order at. This is the other half of that
            // contract: when the world clock arrives at a step the player never
            // reached — because they closed the app, or never opened it — the
            // fighting happens anyway, exactly as it would have. A step is
            // fought once, by whoever gets there first, so backgrounding an app
            // mid-raid is neither a tactic nor a punishment.
            guard next.siege != nil else { return next }
            // The siege *as it finished*, not as it stood before the last step
            // — the tribe is charged for what the fight actually cost it.
            let fought = SiegeEngine.fight(next, to: clock.absoluteStep, registry: registry,
                                           language: s.language)
            if let finished = fought.concluded { concluded.append(finished) }
            return fought.settlement
        }
        // Parties out of the valley entirely, on the road to a ruin or an
        // anomaly on the world map. Same clock, one scale up.
        s = RegionExpeditionEngine.advanceStep(s, clock: clock, registry: registry)
        // What the attempt cost the people who made it is only known once the
        // fighting stops — the player's own orders decide how much of the
        // warband walks home. Charged here, where the tribes are reachable.
        for siege in concluded {
            s = SiegeEngine.chargeAttacker(s, for: siege)
        }
        return s
    }
}
