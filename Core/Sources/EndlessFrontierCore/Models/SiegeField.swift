import Foundation

/// The ground a raid is fought over, in local-map coordinates.
///
/// This used to live in the app, as `SettlementBattle.Field`, because the only
/// thing that needed to know where anybody stood was the drawing: the fight
/// itself was arithmetic on one strength number and a round index, and the
/// canvas invented a plausible arrangement of people to hang it on.
///
/// It is in the Core now because the fight has positions of its own. A raider
/// walks in from the edge of the map, a colonist walks out to meet them, and
/// contact is **proximity** rather than "step ≥ 4". Once that is true the
/// geometry is simulation, not decoration — CLAUDE.md rule 8: two numbers that
/// must agree live in one place, and "where the line forms" is now one of them.
///
/// The precedent is `Pawn.currentJob.position` and `Pawn.haulWalk`:
/// Core-owned positions the renderer *reads*. Rule 5 is untouched — the canvas
/// still never writes any of this.
public struct SiegeField: Sendable, Equatable {

    /// Off the edge of the map, where the attackers come from.
    public static let originReach = 0.48
    /// The line the colony holds: just outside the palisade, where the ground
    /// is still open. The old canvas drew the front here and it looked right;
    /// it is the simulation's number now.
    public static let musterReach = 0.30
    /// The palisade itself, at the edge of the built town. Inside it a raider
    /// is among the stores and a colonist is behind cover.
    public static let wallReach = 0.26
    /// Past this the wall is behind you and counts for nothing.
    public static let openReach = 0.40
    /// Where the watch turns out from — in among the houses, so they are seen
    /// running to the line rather than already standing on it.
    public static let formUpReach = 0.20
    /// How much room one body takes in a rank.
    public static let rankSpacing = 0.019
    /// …and how far the next rank stands behind the one in front.
    ///
    /// The number that stops a fight being two rows. Deep enough that a body of
    /// people reads as having a front and a back; shallow enough that the rear
    /// is in the fight rather than watching it from a field away.
    public static let rankDepth = 0.026
    /// How much room one body keeps for itself once the fight is joined.
    ///
    /// Deliberately **less** than `SiegeEngine.reach`: two people pressed
    /// against each other are still fighting each other, and a personal space
    /// wider than arm's length would shove the melee apart every step it
    /// happened. This is what stops twenty people occupying one spot, and it is
    /// the whole mechanism of the press — a body that cannot get to the front
    /// ends up *behind* the people who are already there, which is a scrum.
    public static let bodySpace = 0.016

    /// How deep the press is allowed to be, out past the ring the posture holds.
    ///
    /// The ring is what made a battle two rows. `SiegeEngine.closingPoint`
    /// pulled every defender who had a target onto `posture.reach` — one radius
    /// for the whole line — so a formation that started three ranks deep
    /// flattened into an arc the instant anybody swung, however carefully it had
    /// formed up. A **band** instead of a ring gives the press somewhere to be,
    /// and the defenders inherit the depth of the warband they are fighting
    /// instead of being ironed onto a circle.
    ///
    /// Holding the line still means holding it: two and a half ranks is the
    /// give in a line of people leaning on each other, not permission to chase
    /// anybody across the field.
    public static let scrumDepth = rankDepth * 2.5

    /// How many bodies stand abreast before a second rank forms.
    ///
    /// Everyone used to be laid out on a **single arc** at one `reach`, both
    /// sides, so twenty defenders were twenty people in one line facing twenty
    /// raiders in another. Keks, watching it: *"bitva nevypadá jako bitva ale
    /// jako dvě řady lidí co mávají mečem."* A line is what a fence looks like.
    /// A body of people has depth, and the depth is where the shoving is.
    ///
    /// It has to **scale with the number**, not sit at a constant. A warband of
    /// ninety in ranks of seven is a column thirteen deep that funnels onto two
    /// defenders — which is how the first cut of this left six of eight
    /// defenders without a scratch. Growing as the square root keeps a body
    /// roughly two and a half times as wide as it is deep at every size: eight
    /// stand five abreast in two ranks, ninety stand fifteen abreast in six.
    ///
    /// It also quietly fixes what the single arc was doing before: ninety
    /// raiders on one line came out `rankSpacing × 89` = **1.69 wide**, on a map
    /// that is one unit across. Most of a warband was off the edge of the world.
    public static func abreast(of count: Int) -> Int {
        max(1, min(count, Int((Double(count) * 2.4).squareRoot().rounded(.up))))
    }

    /// What is being defended.
    public let heart: LocalPoint
    /// The unit vector pointing out along the bearing the attack came in on.
    public let axisX: Double
    public let axisY: Double

    /// **How far the built town actually reaches on this bearing.**
    ///
    /// The reaches above were written down when the colony was a ring of huts,
    /// and then the town grew and they did not. `SettlementGeometry.span` is
    /// 0.70, so the build grid's edge stands **0.35** from the heart on an
    /// axis — while the line formed up at a flat `musterReach` of 0.30, which
    /// is *inside the town*. Every raid in the game was therefore fought in
    /// among the houses, with the defenders running inward from their work to
    /// a crescent in the middle of their own settlement. Keks: *"všichni tam
    /// naběhnou v takovém umělém archu … taky se to kreslí přes aktuální
    /// mapu."* It was not being drawn over the map: it was being fought on top
    /// of it.
    ///
    /// So the fight's geometry is derived from the ground it is fought over.
    /// `edge` is the reach of the furthest thing the colony has built along
    /// this bearing (`ColonyMap.builtReach(along:)`), and the line, the wall
    /// and the muster all hang off it — rule 35: a number that must agree with
    /// another number should *be* it. A colony with no grid yet falls back to
    /// the old constant, which is what it was measured for.
    public let edge: Double

    /// The field a **siege** is being fought on: the same bearing and the same
    /// town edge the simulation stamped when the warband arrived, so the canvas
    /// and the engine cannot draw two different battles (rule 8).
    public init(_ siege: Siege, heart: LocalPoint = SettlementGeometry.heart) {
        self.init(approach: siege.approach, heart: heart,
                  edge: siege.edge > 0 ? siege.edge : SiegeField.wallReach)
    }

    public init(approach: Double,
                heart: LocalPoint = SettlementGeometry.heart,
                edge: Double = SiegeField.wallReach) {
        self.heart = heart
        self.edge = max(0.08, edge)
        axisX = cos(approach)
        axisY = sin(approach)
    }

    /// The palisade line on this bearing: the edge of the built town.
    public var wallAt: Double { edge }
    /// Where the line forms — a stride outside the last roof, on open ground.
    public var musterAt: Double { edge + Self.musterMargin }
    /// Past this the wall is behind you and counts for nothing.
    public var openAt: Double { edge + Self.openMargin }
    /// Where the watch turns out from: in among the houses.
    public var formUpAt: Double { max(0.04, edge - Self.formUpInset) }
    /// …and where the warband first sets foot on the map — always outside the
    /// line it is coming for, however far the town has spread.
    public var originAt: Double { max(Self.originReach, musterAt + Self.approachRun) }

    /// How far outside the last roof the line forms.
    public static let musterMargin = 0.05
    /// …how far out the wall stops being worth anything…
    public static let openMargin = 0.15
    /// …and how far inside it the watch turns out from.
    public static let formUpInset = 0.10
    /// The shortest ground a warband may have to cross to reach the line.
    public static let approachRun = 0.12

    /// A point `reach` out from the heart along the line of the attack.
    public func out(_ reach: Double) -> LocalPoint {
        LocalPoint(x: heart.x + axisX * reach, y: heart.y + axisY * reach)
    }

    public var origin: LocalPoint { out(originAt) }
    public var muster: LocalPoint { out(musterAt) }
    public var wall: LocalPoint { out(wallAt) }

    /// A place in a **body** of `count` bodies, `reach` out from the heart.
    ///
    /// Not a rank: at most `mostAbreast` stand shoulder to shoulder and the
    /// rest form up behind, each rank staggered half a place across so nobody
    /// is directly behind anybody and the mass reads as people rather than as a
    /// grid. Fanned into a shallow crescent as before, so the ends sag back.
    ///
    /// `behind` is which way "further back" runs, because that is the one thing
    /// a post cannot work out for itself: the defenders' rear is toward the
    /// town and the raiders' rear is out toward the country they came from.
    ///
    /// Deterministic and stateless — a pure function of `(index, count)`, so
    /// the same fight always forms up the same way and the canvas can ask where
    /// anybody is without the engine having to remember.
    public func post(index: Int, of count: Int, reach: Double,
                     behind: Double = -1) -> LocalPoint {
        let abreast = Self.abreast(of: count)
        let rank = index / abreast
        let slot = index % abreast
        // How many are actually in *this* rank — the last one is usually short,
        // and a short rank centres rather than hanging off one end.
        let inRank = min(abreast, count - rank * abreast)
        let stagger = rank.isMultiple(of: 2) ? 0.0 : 0.5
        let offset = inRank <= 1 && stagger == 0
            ? 0 : (Double(slot) - Double(inRank - 1) / 2 + stagger)
        // The crescent is a *fraction* of the way out along the rank, not a
        // multiple of the slot index. `offset` used to run −0.5…0.5 and now
        // counts places, so multiplying it by a flat 0.010 sagged the ends of a
        // seven-wide rank back by 0.03 instead of 0.007 — and with a defender
        // now held to their own ring, the flanks sat too deep to ever reach
        // anybody. Eight defenders against ninety raiders, one of them marked.
        let half = max(1, Double(inRank - 1) / 2)
        let sag = abs(offset) / half * 0.010
        let px = -axisY, py = axisX
        // **A line of people is not a curve.** The crescent was exact —
        // everybody on one arc, spaced to the millimetre — which reads as
        // geometry rather than as a body of frightened people finding a place
        // to stand. A hash of the place scatters each of them by up to half a
        // body, deterministically (no RNG, no state: the same fight forms up
        // the same way every replay), which is the whole difference between an
        // arc and a line.
        let scatter = Self.scatter(index: index, of: count)
        let along = reach - sag + behind * Double(rank) * Self.rankDepth + scatter.along
        let across = offset * Self.rankSpacing + scatter.across
        return LocalPoint(x: heart.x + px * across + axisX * along,
                          y: heart.y + py * across + axisY * along)
    }

    /// How far off their exact place in the rank one body stands, in map units.
    static func scatter(index: Int, of count: Int) -> (along: Double, across: Double) {
        func hash(_ salt: UInt64) -> Double {
            var h = (UInt64(bitPattern: Int64(index)) &+ salt) &* 0x9E37_79B9_7F4A_7C15
            h ^= h >> 29
            h = h &* 0xBF58_476D_1CE4_E5B9
            return Double(h >> 40) / Double(1 << 24)
        }
        // **Bounded by the press, not by taste.** Two neighbours are
        // `rankSpacing` apart and a body keeps `bodySpace` to itself, so a
        // scatter wider than the difference puts people inside each other
        // faster than `shoulder` parts them — which the press test catches:
        // 0.8 of a rank's depth had two fighters 0.0078 apart against a bar of
        // 0.008. Half a rank deep and just under half a place across leaves
        // the worst pair 0.010 apart and still reads as a line of people
        // rather than a curve.
        return ((hash(11) - 0.5) * rankDepth * 0.5,
                (hash(29) - 0.5) * rankSpacing * 0.45)
    }

    /// Where a defender holds the line…
    public func defenderPost(index: Int, of count: Int) -> LocalPoint {
        post(index: index, of: count, reach: musterAt)
    }

    /// …where the watch turns out from…
    public func musterPost(index: Int, of count: Int) -> LocalPoint {
        post(index: index, of: count, reach: formUpAt)
    }

    /// …and where a raider first sets foot on the map. Their rear is out toward
    /// the country they came from, so the depth runs the other way.
    public func attackerPost(index: Int, of count: Int) -> LocalPoint {
        post(index: index, of: count, reach: originAt, behind: 1)
    }

    /// How far out the post at `index` stands.
    ///
    /// Kept for what it measures rather than for what it once was going to fix.
    /// Holding each defender to *their own rank's ring* was the obvious way to
    /// make the formation survive contact, and it was tried and reverted: a ring
    /// is a wall, so the flanks and the rear ranks could never reach anybody and
    /// six of eight defenders came out of a raid without a scratch. The fix that
    /// worked runs the other way — no ring at all past `scrumDepth`, and
    /// `bodySpace` between bodies, so the press has depth because people are *in
    /// each other's way* rather than because a rule put them there. Crowding
    /// lets somebody find a way in; a ring forbids it.
    public func postReach(index: Int, of count: Int, reach: Double,
                          behind: Double = -1) -> Double {
        Self.distance(heart, post(index: index, of: count, reach: reach, behind: behind))
    }

    /// How much of the wall stands between somebody at `p` and the enemy —
    /// 1 among the buildings, nothing out at the muster line.
    ///
    /// **Cover is a place you stand.** It used to be a number attached to an
    /// order (`Posture.cover`), which is why pressing them could be tuned to
    /// cost the wall without anybody actually leaving it. Now pressing costs
    /// the wall because it takes you out from behind it, and giving ground
    /// keeps the wall because it puts you back inside. That is the pivot in one
    /// function.
    public func cover(at p: LocalPoint) -> Double {
        let d = Self.distance(heart, p)
        guard d > wallAt else { return 1 }
        let span = openAt - wallAt
        guard span > 0 else { return 0 }
        return max(0, min(1, 1 - (d - wallAt) / span))
    }

    /// Whether somebody at `p` is in among the buildings — for a raider, that
    /// is standing in the stores; for a colonist, it is being indoors.
    public func isInside(_ p: LocalPoint) -> Bool {
        Self.distance(heart, p) <= wallAt
    }

    public func reachFromHeart(_ p: LocalPoint) -> Double { Self.distance(heart, p) }

    public static func distance(_ a: LocalPoint, _ b: LocalPoint) -> Double {
        let dx = a.x - b.x, dy = a.y - b.y
        return (dx * dx + dy * dy).squareRoot()
    }

    /// A stride of at most `pace` from `a` toward `b`, stopping on it rather
    /// than overshooting — which is what makes two people closing on each other
    /// meet instead of oscillating around the gap between them.
    public static func stride(from a: LocalPoint, toward b: LocalPoint, pace: Double) -> LocalPoint {
        let dx = b.x - a.x, dy = b.y - a.y
        let d = (dx * dx + dy * dy).squareRoot()
        guard d > pace, d > 0 else { return b }
        return LocalPoint(x: a.x + dx / d * pace, y: a.y + dy / d * pace)
    }
}
