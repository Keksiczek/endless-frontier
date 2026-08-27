import Foundation

/// How a colony hands itself on: the day a child is counted an adult, and the
/// old teaching the young what they know.
///
/// Both halves are about the same measured failure as `FestivalEngine`, from the
/// other end. A colony that peaks near seventy and decays to twenty-nine is not
/// short of food or safety — it runs out of *people at the age where things
/// happen*, and everything it had learned goes into the ground with the people
/// who learned it. Midsummer finds the young each other; this makes sure there
/// are young to find, and that they are worth something when they arrive.
///
/// **No randomness at all.** Who grew up with whom is decided by age, and who
/// teaches whom by skill — both sorted, both tie-broken by id. A replay is
/// identical because there is nothing to replay.
public enum GenerationEngine {

    // MARK: - Coming of age

    /// How near in age two people have to be to have grown up together.
    static let grewUpTogetherYears = 3
    /// How many of them a new adult carries into their own life.
    static let childhoodFriends = 3
    /// What a childhood is worth against a chat by the well
    /// (`SocialEngine.strengthPerChat`, 7) and a night at the fire
    /// (`FestivalEngine.strengthAtTheFire`, 16).
    ///
    /// More than either, and it should be: these are people who have known each
    /// other their whole lives. It is deliberately *below*
    /// `SocialEngine.weddingMinStrength` — growing up together is not a
    /// betrothal, it is a head start, and the fire or a few years of village
    /// life still has to do the rest.
    static let childhoodBondStrength = 24.0

    // MARK: - What the old know

    /// The age from which a colonist is worth learning from.
    static let teachingAge = 45
    /// …and the skill they need before they have anything to teach.
    static let teachingMinSkill = 8
    /// The gap that makes a pupil a pupil.
    static let teachingGap = 3
    /// Extra progress a pupil makes per tick beside an elder, against
    /// `PawnEngine.xpPerTickWorking` (0.5).
    ///
    /// Learning at somebody's elbow is worth about half again as much as
    /// learning alone — enough that a trade survives the person who was good at
    /// it, which is the point, and not so much that youth is a disadvantage.
    static let xpPerTickTaught = 0.3
    /// How often the pairing is worked out. Every tick would be an O(n²) sweep
    /// over the whole colony for a number that changes on the scale of years.
    static let teachingInterval = 5

    public static func advanceOneTick(
        _ state: WorldState, registry: GameDataRegistry
    ) -> WorldState {
        var s = state
        let ticksPerYear = max(1, registry.config.ticksPerYear)
        for index in s.settlements.indices {
            s.settlements[index] = comeOfAge(
                s.settlements[index], tick: s.tick, ticksPerYear: ticksPerYear)
            if s.tick % teachingInterval == 0 {
                s.settlements[index] = teach(
                    s.settlements[index], tick: s.tick, ticksPerYear: ticksPerYear)
            }
        }
        return s
    }

    /// Anybody who crossed into adulthood on this tick.
    ///
    /// Exact equality is safe and deliberate: `PopulationEngine` advances every
    /// colonist's age by exactly one per tick, so the crossing happens on one
    /// tick and is caught on it. A `>=` here would fire for every adult in the
    /// colony, every tick, for ever.
    static func comeOfAge(
        _ settlement: Settlement, tick: Int, ticksPerYear: Int
    ) -> Settlement {
        let threshold = Pawn.adultAgeYears * ticksPerYear
        // Cheapest possible early-out, and it matters: this runs every tick for
        // every settlement, and on all but a handful of ticks in a colonist's
        // life the answer is nobody. Filtering and sorting first put an
        // allocation on the hot path of the whole simulation.
        guard settlement.pawns.contains(where: { $0.age == threshold }) else { return settlement }
        var s = settlement
        let arrived = s.pawns.filter { $0.age == threshold }
            .sorted { $0.id.uuidString < $1.id.uuidString }

        for young in arrived {
            // The people they grew up alongside: nearest in age first, and the
            // ones they already know skipped — a childhood does not need to be
            // announced twice.
            let peers = s.pawns
                .filter { other in
                    other.id != young.id
                        && abs(other.age - young.age) <= grewUpTogetherYears * ticksPerYear
                }
                .sorted { a, b in
                    let da = abs(a.age - young.age), db = abs(b.age - young.age)
                    return da == db ? a.id.uuidString < b.id.uuidString : da < db
                }
                .prefix(childhoodFriends * 2)

            var made = 0
            for peer in peers where made < childhoodFriends {
                if let existing = s.relationships.firstIndex(where: {
                    $0.involves(young.id) && $0.involves(peer.id)
                }) {
                    // Already somebody to them; a shared childhood only deepens
                    // it, and never turns a grudge into a friendship.
                    guard s.relationships[existing].kind == .friend else { continue }
                    s.relationships[existing].strength = min(
                        100, max(s.relationships[existing].strength, childhoodBondStrength))
                    made += 1
                    continue
                }
                SocialEngine.makeRoom(&s, for: young.id)
                SocialEngine.makeRoom(&s, for: peer.id)
                s.relationships.append(Relationship(
                    between: young.id, and: peer.id, kind: .friend,
                    strength: childhoodBondStrength))
                made += 1
            }

            s.note(tick: tick, kind: .social, text: LocalizedText(values: [
                .en: "\(young.name) is counted a grown colonist now, and takes a share of the work.",
                .cs: "\(young.name) se dnes počítá mezi dospělé a bere si svůj díl práce."]),
                             subject: .pawn(young.id), keptBy: [young.id])
        }
        return s
    }

    /// The old at the elbow of the young.
    ///
    /// One elder to one pupil per pass, best to best: the most skilled elder
    /// takes the pupil who has furthest to come in that trade. Nobody teaches
    /// two people at once — a trade is learned by standing beside somebody, not
    /// by being lectured at.
    static func teach(
        _ settlement: Settlement, tick: Int, ticksPerYear: Int
    ) -> Settlement {
        var s = settlement
        var taught: [(pupil: Int, from: String)] = []

        for work in WorkKind.allCases {
            let elders = s.pawns.indices
                .filter {
                    s.pawns[$0].assignedWork == work
                        && s.pawns[$0].ageYears(ticksPerYear: ticksPerYear) >= teachingAge
                        && s.pawns[$0].skill(work) >= teachingMinSkill
                        && !s.pawns[$0].isBroken && s.pawns[$0].health > 0
                }
                .sorted { a, b in
                    s.pawns[a].skill(work) == s.pawns[b].skill(work)
                        ? s.pawns[a].id.uuidString < s.pawns[b].id.uuidString
                        : s.pawns[a].skill(work) > s.pawns[b].skill(work)
                }
            guard !elders.isEmpty else { continue }

            var pupils = s.pawns.indices
                .filter {
                    s.pawns[$0].assignedWork == work
                        && s.pawns[$0].isAdult(ticksPerYear: ticksPerYear)
                        && s.pawns[$0].ageYears(ticksPerYear: ticksPerYear) < teachingAge
                        && !s.pawns[$0].isBroken && s.pawns[$0].health > 0
                }
                .sorted { a, b in
                    s.pawns[a].skill(work) == s.pawns[b].skill(work)
                        ? s.pawns[a].id.uuidString < s.pawns[b].id.uuidString
                        : s.pawns[a].skill(work) < s.pawns[b].skill(work)
                }

            for elder in elders {
                guard let pupil = pupils.first else { break }
                guard s.pawns[elder].skill(work) - s.pawns[pupil].skill(work) >= teachingGap
                else { break }   // sorted, so nobody further down qualifies either
                pupils.removeFirst()

                var xp = (s.pawns[pupil].skillXP[work] ?? 0)
                    + xpPerTickTaught * Double(teachingInterval)
                let level = s.pawns[pupil].skill(work)
                if xp >= PawnEngine.xpPerLevel, level < PawnEngine.maxSkill {
                    s.pawns[pupil].skills[work] = level + 1
                    xp -= PawnEngine.xpPerLevel
                    // The moment a trade is genuinely passed on is worth a line;
                    // the daily standing-beside is not.
                    if level + 1 >= s.pawns[elder].skill(work) {
                        taught.append((pupil, s.pawns[elder].name))
                    }
                }
                s.pawns[pupil].skillXP[work] = xp
            }
        }

        // `WorkKind` has no name of its own in the Core — the app names the
        // trades — so the line says what happened without naming it, rather
        // than shipping an English enum case to a Czech player.
        for done in taught {
            s.note(tick: tick, kind: .work, text: LocalizedText(values: [
                .en: "\(s.pawns[done.pupil].name) has learned everything \(done.from) had to teach.",
                .cs: "\(s.pawns[done.pupil].name) se od \(done.from) naučil(a) všemu, co uměl(a)."]),
                             subject: .pawn(s.pawns[done.pupil].id),
                             keptBy: [s.pawns[done.pupil].id])
        }
        return s
    }
}
