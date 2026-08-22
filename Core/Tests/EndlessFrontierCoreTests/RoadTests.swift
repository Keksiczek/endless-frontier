import Testing
import Foundation
@testable import EndlessFrontierCore

/// The world map had no road concept at all, so distance was a number nothing
/// the colony did could change: a party crossing a fen and a party crossing a
/// plain took the same time, a `TradeRoute` named two ends and no path, and
/// forty-six conveyances carried a `regionPace` the world had nowhere to spend.
///
/// These tests are mostly about **reachability** rather than arithmetic. A road
/// system that is correct and that no colony ever builds is the shape this
/// project keeps finding — see rules 6, 16 and 21.
@Suite("The ways between places")
struct RoadTests {

    private func registry() throws -> GameDataRegistry { try GameDataRegistry.bundled() }

    private func world(_ seed: UInt64 = 4242) throws -> WorldState {
        GameWorldFactory.newGame(registry: try registry(), seed: seed,
                                 now: Date(timeIntervalSince1970: 1_700_000_000))
    }

    /// A line of hexes with a named biome, so a test can say "cross a fen".
    private func line(_ biome: String, length: Int) -> [HexCoord: Region] {
        var out: [HexCoord: Region] = [:]
        for q in 0...length {
            let coord = HexCoord(q, 0)
            out[coord] = Region(id: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012X", q + 1))!,
                                name: "R\(q)", coord: coord, biomeID: biome)
        }
        return out
    }

    // MARK: - The link itself

    @Test("A road is the same road whichever end you name it from")
    func linksAreUndirected() {
        let there = RoadLink(a: HexCoord(0, 0), b: HexCoord(1, 0))
        let back = RoadLink(a: HexCoord(1, 0), b: HexCoord(0, 0))
        #expect(there.id == back.id, "a way built east must not become a second way built west")
        var net = RoadNetwork()
        net.lay(there)
        net.lay(back)
        #expect(net.all.count == 1)
    }

    /// Ids are derived and stable, never random — the founding-UUID fault
    /// (rule 3) cost a session, and roads are the same shape of thing.
    @Test("A road's name does not change between launches")
    func idsAreDerived() {
        #expect(RoadLink.key(HexCoord(2, -1), HexCoord(2, 0)) == "2,-1|2,0")
        #expect(RoadLink.key(HexCoord(2, 0), HexCoord(2, -1)) == "2,-1|2,0")
    }

    @Test("Paving a road never quietly un-paves it")
    func upgradesNeverDowngrade() {
        var net = RoadNetwork()
        net.lay(RoadLink(a: HexCoord(0, 0), b: HexCoord(1, 0), grade: .paved))
        net.lay(RoadLink(a: HexCoord(0, 0), b: HexCoord(1, 0), grade: .track))
        #expect(net.link(HexCoord(0, 0), HexCoord(1, 0))?.grade == .paved,
                "a track laid over stone must not undo the stone somebody paid for")
    }

    @Test("A ruined road is worth less than a kept one, and never less than none")
    func conditionScalesTheBenefit() {
        let sound = RoadLink(a: HexCoord(0, 0), b: HexCoord(1, 0), grade: .paved, condition: 1)
        let broken = RoadLink(a: HexCoord(0, 0), b: HexCoord(1, 0), grade: .paved, condition: 0.2)
        let track = RoadLink(a: HexCoord(0, 0), b: HexCoord(1, 0), grade: .track, condition: 1)
        #expect(sound.effectiveSpeed > broken.effectiveSpeed)
        #expect(broken.effectiveSpeed >= 1, "a wrecked road is still not slower than no road")
        #expect(sound.effectiveSpeed > track.effectiveSpeed)
    }

    // MARK: - Getting there

    @Test("Crossing hard country costs more than crossing easy country")
    func terrainIsWhatMakesARoadWorthBuilding() {
        let net = RoadNetwork()
        let plains = net.route(from: HexCoord(0, 0), to: HexCoord(4, 0),
                               regions: line("plains", length: 4))
        let fen = net.route(from: HexCoord(0, 0), to: HexCoord(4, 0),
                            regions: line("wetlands", length: 4))
        let plainsCost = try! #require(plains).cost
        let fenCost = try! #require(fen).cost
        #expect(fenCost > plainsCost * 1.5,
                "a fen must be genuinely worse to cross, or a road through one buys nothing")
    }

    @Test("A road through bad country saves more than a road across good")
    func roadsPayWhereTheCountryIsWorst() {
        func saving(_ biome: String) -> Double {
            let regions = line(biome, length: 4)
            let bare = RoadNetwork()
            var made = RoadNetwork()
            for q in 0..<4 {
                made.lay(RoadLink(a: HexCoord(q, 0), b: HexCoord(q + 1, 0), grade: .paved))
            }
            let before = bare.route(from: HexCoord(0, 0), to: HexCoord(4, 0), regions: regions)!.cost
            let after = made.route(from: HexCoord(0, 0), to: HexCoord(4, 0), regions: regions)!.cost
            return before - after
        }
        #expect(saving("wetlands") > saving("plains") * 2,
                "this is the whole design: paving a fen is worth several times paving a plain")
    }

    /// The pass is the piece a player would choose to hold, and the numbers
    /// have to agree without anything special-casing it.
    @Test("A pass is the cheap way through a range")
    func passesAreTheWayThrough() {
        var mountains = line("mountains", length: 2)
        let gap = HexCoord(1, 0)
        mountains[gap] = Region(id: UUID(uuidString: "00000000-0000-0000-0000-0000000000FF")!,
                                name: "Pass", coord: gap, biomeID: "mountains", feature: .pass)
        let plainRange = line("mountains", length: 2)
        let net = RoadNetwork()
        let throughPass = net.route(from: HexCoord(0, 0), to: HexCoord(2, 0), regions: mountains)!
        let throughRock = net.route(from: HexCoord(0, 0), to: HexCoord(2, 0), regions: plainRange)!
        #expect(throughPass.cost < throughRock.cost)
    }

    @Test("A route may not wander off the edge of the world")
    func routesStayOnTheMap() {
        let net = RoadNetwork()
        #expect(net.route(from: HexCoord(0, 0), to: HexCoord(40, 0),
                          regions: line("plains", length: 4)) == nil,
                "there is no country out there to walk across")
    }

    /// The trade a railway asks you to make, and the one thing that makes rail
    /// different from "a faster road".
    @Test("A rail conveyance cannot leave the rails")
    func railsAreATrade() {
        let regions = line("plains", length: 3)
        var net = RoadNetwork()
        net.lay(RoadLink(a: HexCoord(0, 0), b: HexCoord(1, 0), grade: .rail))
        net.lay(RoadLink(a: HexCoord(1, 0), b: HexCoord(2, 0), grade: .rail))
        #expect(net.route(from: HexCoord(0, 0), to: HexCoord(2, 0),
                          regions: regions, mover: .onRails) != nil)
        // …and the third hex has no rail to it.
        #expect(net.route(from: HexCoord(0, 0), to: HexCoord(3, 0),
                          regions: regions, mover: .onRails) == nil,
                "a locomotive must not drive across a field")
    }

    /// What stops "buy a lorry" being a substitute for building anything.
    @Test("A fast machine gains little off the road and everything on stone")
    func pavingIsWhatAMachineIsWaitingFor() {
        let regions = line("plains", length: 3)
        let lorry = RoadNetwork.Mover.wheeled(pace: 6)
        var track = RoadNetwork(); var paved = RoadNetwork()
        for q in 0..<3 {
            track.lay(RoadLink(a: HexCoord(q, 0), b: HexCoord(q + 1, 0), grade: .track))
            paved.lay(RoadLink(a: HexCoord(q, 0), b: HexCoord(q + 1, 0), grade: .paved))
        }
        let open = RoadNetwork().route(from: HexCoord(0, 0), to: HexCoord(3, 0),
                                       regions: regions, mover: lorry)!.cost
        let onTrack = track.route(from: HexCoord(0, 0), to: HexCoord(3, 0),
                                  regions: regions, mover: lorry)!.cost
        let onStone = paved.route(from: HexCoord(0, 0), to: HexCoord(3, 0),
                                  regions: regions, mover: lorry)!.cost
        #expect(onStone < onTrack)
        #expect(onTrack < open)
        #expect(onStone < open / 2, "stone is what a lorry is for")
    }

    // MARK: - Where roads come from

    @Test("Enough traffic beats a track, and nobody had to decide to")
    func trafficMakesTracks() throws {
        var s = try world()
        let a = s.regions[0].coord
        let b = try #require(a.neighbors().first { n in s.regions.contains { $0.coord == n } })
        for _ in 0..<Int(RoadEngine.trackThreshold) {
            s = RoadEngine.travelled(s, route: [a, b])
        }
        s = RoadEngine.beatTracks(s)
        #expect(s.roads.link(a, b)?.grade == .track)
    }

    /// Rule 6, asked directly: a grade nothing can ever reach is content behind
    /// glass. Each one must be laid by *some* reachable world.
    @Test("Every grade of road is one a colony can actually reach")
    func everyGradeIsReachable() throws {
        let reg = try registry()
        var s = try world()
        for grade in RoadGrade.allCases where grade != .track {
            s.era = grade.era
            if let tech = grade.requiresTech {
                #expect(reg.tech(tech) != nil, "'\(grade.rawValue)' wants a tech that does not exist")
                s.researchedTechs.insert(tech)
            }
            #expect(RoadEngine.nextGrade(after: nil, state: s) != nil,
                    "nothing could ever lay a \(grade.rawValue)")
        }
    }

    @Test("A colony with no learning cannot pave anything")
    func gradesAreGated() throws {
        var s = try world()
        s.era = .earlySettlement
        s.researchedTechs = []
        #expect(RoadEngine.nextGrade(after: nil, state: s) == nil,
                "a first-year camp must not be laying macadam")
    }

    /// The council's pick, checked against the thing a player would choose.
    @Test("The council builds through the worst country, not the busiest plain")
    func theCouncilBuildsWhereItPays() throws {
        var s = try world()
        s.era = .medieval
        s.researchedTechs = ["the_wheel", "masonry"]
        // Two edges, equal traffic: one over a mountain, one across plains.
        guard let hard = s.regions.firstIndex(where: { $0.biomeID == "mountains" })
                ?? s.regions.indices.dropFirst().first else { return }
        s.regions[hard].biomeID = "mountains"
        let easy = s.regions.indices.first { $0 != hard && s.regions[$0].biomeID != "mountains" }
        guard let easy else { return }
        s.regions[easy].biomeID = "plains"

        let seat = s.regions[0].coord
        s.roadTraffic[RoadLink.key(seat, s.regions[hard].coord)] = 100
        s.roadTraffic[RoadLink.key(seat, s.regions[easy].coord)] = 100
        let pick = RoadEngine.wanted(in: s, registry: try registry())
        let chosen = try #require(pick).link
        #expect(chosen.other(than: seat) == s.regions[hard].coord
                || s.regions[hard].coord == seat,
                "equal traffic, so the country is what decides — and the mountain is where a road pays")
    }

    /// Rule 16: build off a rate, never a share of the store. And rule 21: a
    /// purse capped below the cheapest thing can never buy anything.
    @Test("A colony that can afford a road builds one; one that cannot, does not")
    func buildingIsAffordable() throws {
        let reg = try registry()
        var s = try world()
        s.era = .medieval
        s.researchedTechs = ["the_wheel"]
        let seat = s.regions[0].coord
        let next = try #require(seat.neighbors().first { n in s.regions.contains { $0.coord == n } })
        s.roadTraffic[RoadLink.key(seat, next)] = 200

        var poor = s
        poor.settlements[0].storage[.materials] = 5
        #expect(RoadEngine.build(poor, registry: reg).roads.hasBuiltNothing,
                "a colony with five materials must not be paving anything")

        var rich = s
        rich.settlements[0].storage[.materials] = 4000
        let built = RoadEngine.build(rich, registry: reg)
        #expect(!built.roads.hasBuiltNothing, "…and one with a full warehouse must be able to")
        #expect(built.settlements[0].storage[.materials] < 4000, "…and must have paid for it")
    }

    @Test("A road nobody keeps goes back to being country")
    func roadsWearOut() throws {
        let reg = try registry()
        var s = try world()
        let a = s.regions[0].coord
        let b = try #require(a.neighbors().first { n in s.regions.contains { $0.coord == n } })
        s.roads.lay(RoadLink(a: a, b: b, grade: .track, condition: 0.001))
        s = RoadEngine.weather(s, registry: reg)
        #expect(s.roads.link(a, b) == nil, "an abandoned track is not a line on a map")

        // …but stone falls back to the levelled ground under it rather than
        // vanishing outright.
        var paved = try world()
        paved.roads.lay(RoadLink(a: a, b: b, grade: .paved, condition: 0.0001))
        paved = RoadEngine.weather(paved, registry: reg)
        #expect(paved.roads.link(a, b)?.grade == .road)
    }

    /// Determinism is the project's hardest invariant and roads are new state
    /// on the world.
    @Test("The same seed lays the same roads")
    func roadsAreDeterministic() throws {
        let reg = try registry()
        let a = TickEngine.advance(try world(9), ticks: 120, registry: reg)
        let b = TickEngine.advance(try world(9), ticks: 120, registry: reg)
        #expect(a.state.roads == b.state.roads)
        #expect(a.state.roadTraffic == b.state.roadTraffic)
    }

    /// Rule 3: every save written before the world had roads must decode.
    @Test("A save from before roads existed still opens")
    func oldSavesDecode() throws {
        var s = try world()
        s.roads.lay(RoadLink(a: HexCoord(0, 0), b: HexCoord(1, 0), grade: .road))
        let data = try JSONEncoder().encode(s)
        var json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        json.removeValue(forKey: "roads")
        json.removeValue(forKey: "roadTraffic")
        let stripped = try JSONSerialization.data(withJSONObject: json)
        let decoded = try JSONDecoder().decode(WorldState.self, from: stripped)
        #expect(decoded.roads.hasBuiltNothing)
        #expect(decoded.roadTraffic.isEmpty)
    }
}

/// **Does anything actually record a journey?**
///
/// The whole road system hangs off `RoadEngine.travelled` being called by the
/// things that move across the map. It is one line at each site, it is easy to
/// add a mover and forget it, and the failure is silent: roads simply never
/// appear and the system looks like a balance problem instead of a wiring one.
///
/// This is the guard for that — and it caught the fault on the way in, in the
/// expeditions, in a system written the same afternoon as the rule about it.
@Suite("Everything that crosses the map leaves a mark on it")
struct RoadWiringTests {
    private func world() throws -> WorldState {
        GameWorldFactory.newGame(registry: try GameDataRegistry.bundled(), seed: 31,
                                 now: Date(timeIntervalSince1970: 1_700_000_000))
    }

    @Test("An expedition to another region records the way it walked")
    func expeditionsLeaveTraffic() throws {
        let reg = try GameDataRegistry.bundled()
        var s = try world()
        // Somewhere to go, and hands free to go there.
        guard let settlement = s.settlements.first else { return }
        for index in s.regions.indices { s.regions[index].explorationState = .fullyExplored }
        s.settlements[0].storage[.food] = 900

        // `dispatch` only sends to a region with an active site, so find one.
        guard let site = s.regions.first(where: { $0.hasActiveSite && $0.id != settlement.regionID })
        else { return }
        let before = s.roadTraffic.values.reduce(0, +)
        if let sent = RegionExpeditionEngine.dispatch(
            s, settlementID: settlement.id, regionID: site.id, registry: reg) {
            #expect(sent.roadTraffic.values.reduce(0, +) > before,
                    "a party walked to another region and the ground did not notice")
        }
    }

    /// A caravan is the other mover, and the one that carries the most weight
    /// in whether a trade lane ever wears a track.
    @Test("A dispatched caravan records the way it went")
    func caravansLeaveTraffic() throws {
        let reg = try GameDataRegistry.bundled()
        var s = try world()
        guard s.settlements.count >= 1, let origin = s.settlements.first else { return }
        // A second town to send it to, sitting on a neighbouring hex.
        guard let seat = s.regions.first(where: { $0.id == origin.regionID }),
              let next = seat.coord.neighbors().first(where: { n in s.regions.contains { $0.coord == n } }),
              let there = s.regions.firstIndex(where: { $0.coord == next }) else { return }
        var daughter = Settlement(
            id: UUID(uuidString: "00000000-0000-0000-0000-0000000000D1")!,
            name: "Daughter", buildings: [])
        daughter.regionID = s.regions[there].id
        s.settlements.append(daughter)
        s.settlements[0].storage[.food] = 500
        // A caravan wants somebody walking with it: `canDispatch` refuses an
        // unguarded one, which is right and is also why the first cut of this
        // test proved nothing.
        guard let escort = s.settlements[0].pawns.first?.id else { return }

        let sent = CaravanEngine.dispatch(
            s, originID: origin.id, destinationID: daughter.id,
            resource: .food, amount: 20, guardIDs: [escort], registry: reg)
        // Say which half failed. "Traffic is zero" is true both when nothing
        // recorded the journey and when no caravan ever left, and those want
        // different fixes.
        #expect(sent.caravans.count == 1, "the caravan never left, so this proves nothing")
        #expect(sent.roadTraffic.values.reduce(0, +) > 0,
                "a caravan crossed the country and nothing recorded it")
    }
}

/// The one arithmetic mistake this seam invites: the route already knows what
/// is travelling, so dividing the result by the mover's pace *again* applies it
/// twice. It reads as a tuning problem and is not one.
@Suite("A conveyance's speed is counted once")
struct RoadPaceTests {
    @Test("A fast yard shortens a journey, and does not shorten it twice")
    func paceIsNotDoubleCounted() throws {
        let regions = [HexCoord(0, 0), HexCoord(1, 0), HexCoord(2, 0), HexCoord(3, 0)]
        var byCoord: [HexCoord: Region] = [:]
        for (i, coord) in regions.enumerated() {
            byCoord[coord] = Region(
                id: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012X", i + 1))!,
                name: "R\(i)", coord: coord, biomeID: "plains")
        }
        var paved = RoadNetwork()
        for i in 0..<3 {
            paved.lay(RoadLink(a: regions[i], b: regions[i + 1], grade: .paved))
        }
        let onFoot = paved.route(from: regions[0], to: regions[3],
                                 regions: byCoord, mover: .onFoot)!.cost
        let byLorry = paved.route(from: regions[0], to: regions[3],
                                  regions: byCoord, mover: .wheeled(pace: 6))!.cost
        #expect(byLorry < onFoot, "a lorry on stone must be quicker than walking")
        // Three hexes of plain at 2.8× road speed is the floor a *walking*
        // party pays; a lorry may beat it, but not by its full pace on top of
        // the road's — which is what a second division would give.
        #expect(byLorry > onFoot / 7,
                "the pace has been applied twice: this journey is faster than the machine is")
    }
}

/// **What actually wears a road.**
///
/// It took three measurements to find this, and each of the first two moved a
/// number and changed nothing on the map. Traffic was recorded only when a
/// caravan was dispatched or a party sent out — thirteen journeys in two
/// hundred years of a five-town realm, because supply only moves when somebody
/// is short. Any threshold tuned against that is tuned against noise.
///
/// Roads are worn by **people going back and forth between towns that are near
/// each other**, which is a rate that exists as long as the towns do.
@Suite("Neighbours wear the ground between them")
struct NeighbourlyTrafficTests {
    private func realm(_ towns: Int, pawnsEach: Int) throws -> WorldState {
        var s = GameWorldFactory.newGame(registry: try GameDataRegistry.bundled(), seed: 5,
                                         now: Date(timeIntervalSince1970: 1_700_000_000))
        let home = s.regions.first { $0.id == s.settlements.first?.regionID }
        guard let home else { return s }
        // Daughter towns on the hexes around the capital.
        let spots = home.coord.neighbors().filter { n in s.regions.contains { $0.coord == n } }
        for i in 0..<min(towns - 1, spots.count) {
            var town = Settlement(
                id: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012X", 0xD0 + i))!,
                name: "T\(i)", buildings: [])
            town.regionID = s.regions.first { $0.coord == spots[i] }?.id
            town.pawns = Array(s.settlements[0].pawns.prefix(pawnsEach))
            s.settlements.append(town)
        }
        return s
    }

    @Test("Two towns beside each other wear the ground between them")
    func neighboursLayTraffic() throws {
        var s = try realm(2, pawnsEach: 20)
        guard s.settlements.count > 1 else { return }
        s.tick = RoadEngine.visitInterval          // land on the cadence
        let after = RoadEngine.neighbourlyTraffic(s)
        #expect(after.roadTraffic.values.reduce(0, +) > 0,
                "people live a hex apart and never walk between them")
    }

    /// A hamlet beside a city wears the road at a *hamlet's* rate — it is the
    /// hamlet's feet doing the walking.
    @Test("More people wear the ground faster")
    func trafficScalesWithWhoIsWalking() throws {
        func laid(pawns: Int) throws -> Double {
            var s = try realm(2, pawnsEach: pawns)
            guard s.settlements.count > 1 else { return 0 }
            s.tick = RoadEngine.visitInterval
            return RoadEngine.neighbourlyTraffic(s).roadTraffic.values.reduce(0, +)
        }
        let few = try laid(pawns: 4)
        let many = try laid(pawns: 20)
        #expect(many > few)
    }

    /// Rule 4: this pathfinds, so it must not run every tick.
    @Test("It is counted on a cadence, not every tick")
    func itRunsOnTheThinkCadence() throws {
        var s = try realm(2, pawnsEach: 20)
        guard s.settlements.count > 1 else { return }
        s.tick = RoadEngine.visitInterval + 1
        #expect(RoadEngine.neighbourlyTraffic(s).roadTraffic.isEmpty,
                "a tick off the cadence must do no pathfinding at all")
    }

    /// A colony on its own has nowhere to walk to, and must not pay for the
    /// question.
    @Test("One town alone wears nothing")
    func aLoneColonyLaysNothing() throws {
        var s = try realm(1, pawnsEach: 20)
        s.tick = RoadEngine.visitInterval
        #expect(RoadEngine.neighbourlyTraffic(s).roadTraffic.isEmpty)
    }
}

/// The probe kept showing railways and no roads under them, with `nextGrade`
/// looking correct on the page. This asks it directly, in the states a real
/// colony passes through, because reading code is not measuring it.
@Suite("A colony builds the ladder, not the top of it")
struct RoadLadderTests {
    private func world() throws -> WorldState {
        GameWorldFactory.newGame(registry: try GameDataRegistry.bundled(), seed: 11,
                                 now: Date(timeIntervalSince1970: 1_700_000_000))
    }

    @Test("Even a modern colony lays a road on bare ground first")
    func theFirstRungIsARoad() throws {
        var s = try world()
        s.era = .modern
        s.researchedTechs = ["masonry", "railways", "machining", "steam_power"]
        #expect(RoadEngine.nextGrade(after: nil, state: s) == .road,
                "a world that could lay rail must still level the ground first")
        #expect(RoadEngine.nextGrade(after: .road, state: s) == .paved)
        #expect(RoadEngine.nextGrade(after: .paved, state: s) == .rail)
        #expect(RoadEngine.nextGrade(after: .rail, state: s) == nil)
    }

    /// The end-to-end version: give a colony traffic and a full warehouse, and
    /// see what it actually puts on the ground.
    @Test("What the council actually lays on a bare edge is a road")
    func theCouncilLaysARoad() throws {
        let reg = try GameDataRegistry.bundled()
        var s = try world()
        s.era = .modern
        s.researchedTechs = ["masonry", "railways", "machining", "steam_power"]
        s.settlements[0].storage[.materials] = 9000
        guard let seat = s.regions.first(where: { $0.id == s.settlements[0].regionID }),
              let next = seat.coord.neighbors().first(where: { n in s.regions.contains { $0.coord == n } })
        else { return }
        s.roadTraffic[RoadLink.key(seat.coord, next)] = 400

        let built = RoadEngine.build(s, registry: reg)
        #expect(built.roads.link(seat.coord, next)?.grade == .road,
                "the council skipped the ladder and laid the dearest thing it could reach")
    }
}

/// **What a war does to the ways.**
///
/// `RoadNetwork.remove` existed from the day the network did and nothing called
/// it: the model could lose a road and the world never did. A chokepoint is
/// only worth holding if losing it costs something, so this is the payoff
/// `RegionFeature.pass` has been waiting for.
@Suite("Raiders wreck the road they walk in on")
struct RoadCuttingTests {
    private func world() throws -> WorldState {
        GameWorldFactory.newGame(registry: try GameDataRegistry.bundled(), seed: 17,
                                 now: Date(timeIntervalSince1970: 1_700_000_000))
    }

    /// The plain case, and the one that says it is *their* road and not a die.
    @Test("A raid takes down a way on the raiders' line of march")
    func aRaidCutsTheRoad() throws {
        var s = try world()
        guard let capital = s.settlements.first,
              let seat = s.regions.first(where: { $0.id == capital.regionID }),
              let next = seat.coord.neighbors().first(where: { n in s.regions.contains { $0.coord == n } }),
              let neighbourRegion = s.regions.first(where: { $0.coord == next })
        else { return }
        s.roads.lay(RoadLink(a: seat.coord, b: next, grade: .paved))

        let after = RoadEngine.cut(s, from: neighbourRegion.id, to: capital.id)
        let left = after.roads.link(seat.coord, next)
        #expect(left?.grade == .road,
                "paving torn up leaves the levelled ground under it, not nothing")
        #expect((left?.condition ?? 1) < 1, "…and what is left is not in good repair")
    }

    /// A track has nothing under it.
    @Test("A cut track is simply gone")
    func aTrackDoesNotSurvive() throws {
        var s = try world()
        guard let capital = s.settlements.first,
              let seat = s.regions.first(where: { $0.id == capital.regionID }),
              let next = seat.coord.neighbors().first(where: { n in s.regions.contains { $0.coord == n } }),
              let neighbourRegion = s.regions.first(where: { $0.coord == next })
        else { return }
        s.roads.lay(RoadLink(a: seat.coord, b: next, grade: .track))
        #expect(RoadEngine.cut(s, from: neighbourRegion.id, to: capital.id)
                    .roads.link(seat.coord, next) == nil)
    }

    /// They wreck what hurts most, which is what makes a pass worth holding
    /// rather than a hex worth ignoring.
    @Test("They tear up the dearest piece, not the nearest")
    func theyCutWhatCostsMost() throws {
        var s = try world()
        guard let capital = s.settlements.first,
              let seat = s.regions.first(where: { $0.id == capital.regionID }) else { return }
        // A two-hex march: one cheap plain, then one dear mountain.
        let ring = seat.coord.neighbors().filter { n in s.regions.contains { $0.coord == n } }
        guard let middle = ring.first,
              let far = middle.neighbors().first(where: { n in
                  n != seat.coord && s.regions.contains { $0.coord == n } })
        else { return }
        for (index, region) in s.regions.enumerated() {
            if region.coord == middle { s.regions[index].biomeID = "plains" }
            if region.coord == far { s.regions[index].biomeID = "mountains" }
        }
        s.roads.lay(RoadLink(a: seat.coord, b: middle, grade: .paved))
        s.roads.lay(RoadLink(a: middle, b: far, grade: .paved))
        guard let raiders = s.regions.first(where: { $0.coord == far }) else { return }

        let after = RoadEngine.cut(s, from: raiders.id, to: capital.id)
        #expect(after.roads.link(middle, far)?.grade == .road,
                "the mountain stretch cost the most to make and is what they take")
        #expect(after.roads.link(seat.coord, middle)?.grade == .paved,
                "…and the easy stretch is left alone")
    }

    @Test("A colony with no roads loses nothing, and does not crash finding out")
    func nothingToCut() throws {
        let s = try world()
        guard let capital = s.settlements.first,
              let elsewhere = s.regions.first(where: { $0.id != capital.regionID }) else { return }
        #expect(RoadEngine.cut(s, from: elsewhere.id, to: capital.id).roads.hasBuiltNothing)
    }
}

/// **A ceiling enforced in one of three places is not a ceiling.**
///
/// `grudgeCeiling` was applied only where crowding adds to it; a raid (+6) and
/// a quarrel (+3) walked past. `DiplomacyProbe` showed the consequence at once:
/// all five peoples pinned at **119**, the same number to the point, because
/// they reach 110 by crowding and then step over it. A figure every neighbour
/// shares carries no information — it stops telling a people you have wronged
/// from one you have not.
@Suite("A grudge has one door and a top")
struct GrudgeCeilingTests {
    private func tribe(grudge: Double) -> Tribe {
        Tribe(id: UUID(uuidString: "00000000-0000-0000-0000-0000000000E1")!,
              name: "Them", foundedTick: 0,
              originStory: LocalizedText(values: [.en: "They left.", .cs: "Odešli."]),
              population: 40, genes: Genes(), grudge: grudge)
    }

    @Test("Anger cannot be pushed past the ceiling, from any direction")
    func theCeilingHolds() {
        var t = tribe(grudge: DiplomacyEngine.grudgeCeiling - 1)
        DiplomacyEngine.resent(&t, by: 50)
        #expect(t.grudge == DiplomacyEngine.grudgeCeiling)
        DiplomacyEngine.resent(&t, by: 6)
        #expect(t.grudge == DiplomacyEngine.grudgeCeiling, "a raid must not step over it either")
    }

    @Test("…and never below nothing")
    func itDoesNotGoNegative() {
        var t = tribe(grudge: 2)
        DiplomacyEngine.resent(&t, by: -40)
        #expect(t.grudge == 0)
    }

    /// The regression the probe found: five peoples, one number.
    @Test("Two peoples wronged differently do not end up equally angry")
    func angerStillDiscriminates() {
        var wronged = tribe(grudge: 20)
        var left = tribe(grudge: 20)
        for _ in 0..<40 { DiplomacyEngine.resent(&wronged, by: 6) }
        DiplomacyEngine.resent(&left, by: 6)
        #expect(wronged.grudge > left.grudge)
        #expect(wronged.grudge <= DiplomacyEngine.grudgeCeiling)
    }
}

/// **Where the crowding ceiling went.**
///
/// A lower ceiling for grudge-from-size was tried and measured: wars over two
/// hundred years fell from **67 to 2**. Crowding feeds grudge, grudge drags
/// standing, and war fires below a standing threshold — so capping the source
/// caps the conflict, and §8.5's finding was that a world nothing can anger has
/// nothing in it. What survives is the real fault: the ceiling was honoured at
/// one of the three places anger is added, so every people overshot to 119.
@Suite("Growth still makes a people angry enough to act")
struct CrowdingCeilingTests {
    private func tribe(grudge: Double) -> Tribe {
        Tribe(id: UUID(uuidString: "00000000-0000-0000-0000-0000000000E2")!,
              name: "Them", foundedTick: 0,
              originStory: LocalizedText(values: [.en: "They left.", .cs: "Odešli."]),
              population: 40, genes: Genes(), grudge: grudge)
    }

    /// The regression guard for the revert: if somebody caps crowding again,
    /// this fails and the comment above says what it cost last time.
    @Test("Size alone can still carry a people to the top of the scale")
    func crowdingReachesTheCeiling() {
        var t = tribe(grudge: 0)
        for _ in 0..<200 { DiplomacyEngine.resentCrowding(&t, by: 8) }
        #expect(t.grudge == DiplomacyEngine.grudgeCeiling,
                "capping this took the measured war count from 67 to 2")
    }

    @Test("…and not past it")
    func itStillHonoursTheCeiling() {
        var t = tribe(grudge: DiplomacyEngine.grudgeCeiling)
        DiplomacyEngine.resentCrowding(&t, by: 50)
        #expect(t.grudge == DiplomacyEngine.grudgeCeiling)
    }
}

/// **A road to a neighbour** — the verb `docs/NEIGHBOURS.md` puts first,
/// because it is the one that stands on the map.
///
/// The three verbs the game already had (gift, demand, pact) are a one-off
/// spend of influence that moves a number and is then over. `DiplomacyProbe`
/// measured standings swinging over bands of sixty to a hundred and sixty
/// points, which makes a gift's twelve into noise — so what a verb needs is not
/// a bigger number but something that **accrues, is visible, and can be lost**.
@Suite("A road toward a people is a thing you can see and lose")
struct RoadTowardTests {
    private func world() throws -> (WorldState, GameDataRegistry) {
        let registry = try GameDataRegistry.bundled()
        var s = GameWorldFactory.newGame(registry: registry, seed: 23,
                                         now: Date(timeIntervalSince1970: 1_700_000_000))
        s.era = .medieval
        s.settlements[0].storage[.materials] = 6000
        for index in s.tribes.indices { s.tribes[index].discovered = true }
        return (s, registry)
    }

    private func metTribe(_ s: WorldState) -> Tribe? {
        s.tribes.first { $0.discovered && $0.regionID != nil
            && $0.regionID != s.settlements.first?.regionID }
    }

    @Test("Building toward a people lays a stretch and costs materials")
    func itLaysARoadAndCharges() throws {
        let (s, reg) = try world()
        guard let them = metTribe(s) else { return }
        let purse = s.settlements[0].storage[.materials]

        let after = GameEngine.buildRoadToward(s, tribeID: them.id, registry: reg)
        #expect(!after.roads.hasBuiltNothing, "the verb did nothing at all")
        #expect(after.settlements[0].storage[.materials] < purse, "…and it was free")
    }

    /// The whole point: it accrues, and it eases the grievance of being the
    /// larger neighbour.
    @Test("It buys standing, and takes something off the grudge")
    func itMovesTheRelationship() throws {
        var (s, reg) = try world()
        guard let them = metTribe(s),
              let index = s.tribes.firstIndex(where: { $0.id == them.id }) else { return }
        s.tribes[index].standing = 0
        s.tribes[index].grudge = 40

        let after = GameEngine.buildRoadToward(s, tribeID: them.id, registry: reg)
        #expect(after.tribes[index].standing > 0)
        #expect(after.tribes[index].grudge < 40)
    }

    /// **The fault this test exists for.** `roadTowardCost` used to answer by
    /// calling `buildRoadToward` and seeing what changed — so a colony that
    /// could not afford the stretch got the same `nil` as one whose road was
    /// finished. A panel has to tell a price it cannot pay from a road that is
    /// already built.
    @Test("A colony too poor to build is still told the price")
    func priceIsNotTheSameAsPossibility() throws {
        var (s, reg) = try world()
        guard let them = metTribe(s) else { return }
        let price = GameEngine.roadTowardCost(s, tribeID: them.id, registry: reg)
        #expect(price != nil, "there is a road to build and no price was given")

        s.settlements[0].storage[.materials] = 0
        #expect(GameEngine.roadTowardCost(s, tribeID: them.id, registry: reg) == price,
                "an empty warehouse must not make the road look finished")
        #expect(GameEngine.buildRoadToward(s, tribeID: them.id, registry: reg).roads.hasBuiltNothing,
                "…and it must still not be built")
    }

    /// It grows outward from home rather than scattering paving in the
    /// wilderness, so a half-built road goes part of the way.
    @Test("The road grows out from home, one stretch at a time")
    func itGrowsOutward() throws {
        var (s, reg) = try world()
        guard let them = metTribe(s),
              let seatID = s.settlements[0].regionID,
              let seat = s.regions.first(where: { $0.id == seatID }) else { return }

        s = GameEngine.buildRoadToward(s, tribeID: them.id, registry: reg)
        #expect(s.roads.touching(seat.coord).count == 1,
                "the first stretch must start at the colony, not somewhere out there")
        let first = s.roads.all.count
        s = GameEngine.buildRoadToward(s, tribeID: them.id, registry: reg)
        #expect(s.roads.all.count >= first, "a second call must carry the road further or up a grade")
    }

    @Test("A people nobody has met cannot be built toward")
    func strangersHaveNoRoad() throws {
        var (s, reg) = try world()
        guard let them = metTribe(s),
              let index = s.tribes.firstIndex(where: { $0.id == them.id }) else { return }
        s.tribes[index].discovered = false
        #expect(GameEngine.roadTowardCost(s, tribeID: them.id, registry: reg) == nil)
        #expect(GameEngine.buildRoadToward(s, tribeID: them.id, registry: reg).roads.hasBuiltNothing)
    }
}

/// The roads that were here before anybody was, and the ones the player lays.
@Suite("What was here before, and what the player adds")
struct AncientAndPlayerRoadTests {

    @Test("A new world has stone in the wilderness and nothing built")
    func worldStartsWithRuins() throws {
        let registry = try GameDataRegistry.bundled()
        let state = GameWorldFactory.newGame(registry: registry, seed: 4242)
        #expect(state.roads.hasBuiltNothing)
        #expect(!state.roads.all.isEmpty, "a valley nobody ever crossed is a poorer valley")
        #expect(state.roads.all.allSatisfy { $0.origin == .ancient })
        #expect(state.roads.all.allSatisfy { $0.grade == .paved },
                "stone is what survives; a levelled track would not have")
    }

    @Test("The same seed leaves the same ruins")
    func ruinsAreDeterministic() throws {
        let registry = try GameDataRegistry.bundled()
        let a = GameWorldFactory.newGame(registry: registry, seed: 77).roads.all
        let b = GameWorldFactory.newGame(registry: registry, seed: 77).roads.all
        #expect(a == b)
    }

    @Test("Weather has already taken all it can take from an ancient way")
    func ruinsDoNotRotAway() throws {
        let registry = try GameDataRegistry.bundled()
        var state = GameWorldFactory.newGame(registry: registry, seed: 4242)
        let before = state.roads.all.count
        // Long enough that an unmaintained paved road laid today would be gone
        // several times over: `paved.wearPerTick` clears 1.0 in about 2500.
        for _ in 0..<6000 { state = RoadEngine.weather(state, registry: registry) }
        #expect(state.roads.all.count == before)
        #expect(state.roads.all.allSatisfy { $0.condition >= RoadEngine.ancientFloor - 0.001 })
    }

    @Test("Building on a ruin is cheaper than building on bare ground")
    func ruinsAreCheaperToBuildOn() throws {
        let registry = try GameDataRegistry.bundled()
        let state = GameWorldFactory.newGame(registry: registry, seed: 4242)
        guard let ruin = state.roads.all.first,
              let here = state.regions.first(where: { $0.coord == ruin.a }),
              let there = state.regions.first(where: { $0.coord == ruin.b })
        else { return }
        let onStone = RoadEngine.price(.rail, here: here, there: there, existing: ruin)
        let onGrass = RoadEngine.price(.rail, here: here, there: there, existing: nil)
        #expect(onStone < onGrass)
        #expect(onStone > 0, "clearing a buried causeway is still work")
    }

    @Test("A raid does not wreck a ruin — there is nothing left in it to take")
    func raidersLeaveRuinsAlone() throws {
        let registry = try GameDataRegistry.bundled()
        let state = GameWorldFactory.newGame(registry: registry, seed: 4242)
        guard let capital = state.settlements.first,
              let elsewhere = state.regions.first(where: { $0.id != capital.regionID })
        else { return }
        let after = RoadEngine.cut(state, from: elsewhere.id, to: capital.id)
        #expect(after.roads.all == state.roads.all)
    }

    // MARK: - A road the player lays

    @Test("The player lays a road on an edge they chose, and pays for it")
    func playerLaysARoad() throws {
        let registry = try GameDataRegistry.bundled()
        var state = GameWorldFactory.newGame(registry: registry, seed: 4242)
        guard let seatID = state.settlements[0].regionID,
              let seat = state.regions.first(where: { $0.id == seatID }),
              let neighbour = seat.coord.neighbors().first(where: { coord in
                  state.regions.contains { $0.coord == coord }
              }) else { return }
        // Both ends have to be known country, the purse has to be full, and the
        // age has to be one that knows how to level ground — a founding party
        // wears tracks and builds nothing, which is rule 66's ladder and not an
        // oversight.
        for index in state.regions.indices where state.regions[index].coord == neighbour {
            state.regions[index].explorationState = .fullyExplored
        }
        state.era = .ancient
        state.settlements[0].storage[.materials] = 5000

        let price = GameEngine.roadCost(state, from: seat.coord, to: neighbour)
        #expect(price != nil)
        let after = GameEngine.layRoad(state, from: seat.coord, to: neighbour, registry: registry)
        #expect(after.roads.link(seat.coord, neighbour) != nil)
        #expect(after.settlements[0].storage[.materials] < 5000)
    }

    @Test("A road cannot be laid into country nobody has walked")
    func unknownCountryCannotBeRoaded() throws {
        let registry = try GameDataRegistry.bundled()
        var state = GameWorldFactory.newGame(registry: registry, seed: 4242)
        guard let seatID = state.settlements[0].regionID,
              let seat = state.regions.first(where: { $0.id == seatID }),
              let neighbour = seat.coord.neighbors().first(where: { coord in
                  state.regions.contains { $0.coord == coord }
              }) else { return }
        for index in state.regions.indices where state.regions[index].coord == neighbour {
            state.regions[index].explorationState = .unknown
        }
        state.settlements[0].storage[.materials] = 5000
        #expect(GameEngine.roadCost(state, from: seat.coord, to: neighbour) == nil)
        #expect(GameEngine.layRoad(state, from: seat.coord, to: neighbour,
                                   registry: registry).roads.hasBuiltNothing)
    }

    @Test("Two hexes that do not touch have no edge to road")
    func onlyNeighboursCanBeJoined() throws {
        let registry = try GameDataRegistry.bundled()
        let state = GameWorldFactory.newGame(registry: registry, seed: 4242)
        let far = HexCoord(0, 0)
        let further = HexCoord(4, 4)
        #expect(GameEngine.roadCost(state, from: far, to: further) == nil)
    }
}

/// Water on the world map, and what it costs to get a road across it.
@Suite("The water, and the bridges over it")
struct RiverTests {

    @Test("A world has rivers in it, and they run downhill")
    func riversExistAndFall() {
        let hexes = HexCoord.disc(radius: 12)
        let courses = hexes.compactMap { coord in
            MapGenerator.river(at: coord, mapSeed: 4242).map { (coord, $0) }
        }
        #expect(!courses.isEmpty, "a world with no water on it has no bridges to build")
        for (coord, course) in courses {
            let here = MapGenerator.land(at: coord, mapSeed: 4242).elevation
            if let to = course.to {
                #expect(MapGenerator.land(at: to, mapSeed: 4242).elevation < here,
                        "water does not run uphill")
            }
            if let from = course.from {
                #expect(MapGenerator.land(at: from, mapSeed: 4242).elevation > here)
            }
        }
    }

    @Test("Water is a feature of some country, not of all of it")
    func riversAreRare() {
        let hexes = HexCoord.disc(radius: 14)
        let wet = hexes.count { MapGenerator.river(at: $0, mapSeed: 4242) != nil }
        let share = Double(wet) / Double(hexes.count)
        // Measured at 8% (`MapProbe.whereTheWaterRuns`). The bounds are wide on
        // purpose: this guards against the two failures that matter — a map
        // with no water, and a map that is all water — not against the number.
        #expect(share > 0.02 && share < 0.20)
    }

    @Test("The same seed runs the same water")
    func riversAreDeterministic() {
        for coord in HexCoord.disc(radius: 6) {
            #expect(MapGenerator.river(at: coord, mapSeed: 909)
                    == MapGenerator.river(at: coord, mapSeed: 909))
        }
    }

    @Test("A road that crosses water costs more than the same road on dry ground")
    func bridgesCostMore() throws {
        let registry = try GameDataRegistry.bundled()
        var dry = Region(name: "Dry", coord: HexCoord(0, 0), biomeID: registry.biomes.keys.sorted()[0])
        var wet = Region(name: "Wet", coord: HexCoord(1, 0), biomeID: registry.biomes.keys.sorted()[0])
        let onDry = RoadEngine.price(.road, here: dry, there: wet, existing: nil)
        wet.river = RiverCourse(from: HexCoord(1, -1), to: HexCoord(2, 0))
        let overWater = RoadEngine.price(.road, here: dry, there: wet, existing: nil)
        #expect(overWater > onDry)
        // …and following the bank does not.
        dry.river = RiverCourse(from: nil, to: HexCoord(1, 0))
        #expect(RoadEngine.price(.road, here: dry, there: wet, existing: nil) == onDry)
    }

    @Test("A way along the course follows the bank; anything else has to cross")
    func alongTheBankNeedsNoBridge() throws {
        let registry = try GameDataRegistry.bundled()
        let biome = registry.biomes.keys.sorted()[0]
        let upstream = Region(name: "Up", coord: HexCoord(0, 0), biomeID: biome,
                              river: RiverCourse(from: nil, to: HexCoord(1, 0)))
        let downstream = Region(name: "Down", coord: HexCoord(1, 0), biomeID: biome,
                                river: RiverCourse(from: HexCoord(0, 0), to: nil))
        let bank = Region(name: "Bank", coord: HexCoord(1, -1), biomeID: biome)
        #expect(!RoadEngine.needsBridge(upstream, downstream))
        #expect(RoadEngine.needsBridge(bank, downstream))
        #expect(!RoadEngine.needsBridge(bank, Region(name: "Far", coord: HexCoord(2, -1),
                                                    biomeID: biome)))
    }
}

/// The map, not the list. A road is a line between two places, and the
/// affordance for laying one was a row of text in a panel — so the edges the
/// player could actually build on had to be askable all at once.
@Suite("Every stretch the player could lay")
struct LayableEdgeTests {

    private func registry() throws -> GameDataRegistry { try GameDataRegistry.bundled() }

    private func world(_ seed: UInt64 = 4242) throws -> WorldState {
        GameWorldFactory.newGame(registry: try registry(), seed: seed,
                                 now: Date(timeIntervalSince1970: 1_700_000_000))
    }

    @Test("An edge is offered once, not once from each end")
    func edgesAreNotDoubled() throws {
        var state = try world()
        state.era = .medieval
        let edges = GameEngine.layableEdges(state)
        #expect(Set(edges.map(\.link.id)).count == edges.count)
    }

    @Test("Nothing is offered through country nobody has walked")
    func fogIsNotRoadable() throws {
        var state = try world()
        state.era = .medieval
        let known = Set(state.regions.filter { $0.explorationState != .unknown }.map(\.coord))
        for edge in GameEngine.layableEdges(state) {
            #expect(known.contains(edge.link.a) && known.contains(edge.link.b))
        }
    }

    /// Rule 28 — an empty list is not a diagnosis. The map's whole affordance
    /// hangs off this being non-empty once the age allows a road at all.
    /// Rule 28 — an empty list is not a diagnosis, it is a question. At the
    /// founding this comes back empty and **that is correct**: one hex is
    /// charted and a road wants two ends. The affordance appears with the
    /// second explored hex, which is what this asserts.
    @Test("A charted neighbour is a stretch the player can lay")
    func thereIsSomethingToLay() throws {
        var state = try world()
        state.era = .medieval
        #expect(GameEngine.layableEdges(state).isEmpty,
                "one charted hex has no edge to anywhere — the panel is right to be empty")
        let home = HexCoord(0, 0)
        guard let index = state.regions.firstIndex(where: { $0.coord == home.neighbors()[0] })
        else { return }
        state.regions[index].explorationState = .fullyExplored
        let edges = GameEngine.layableEdges(state)
        #expect(edges.count == 1, "one charted neighbour is exactly one stretch")
        #expect(edges.first?.link.grade == .road)
        #expect((edges.first?.cost ?? 0) > 0, "a way somebody could have for nothing is not a decision")
    }

    @Test("The map's edges agree with the panel's rows")
    func mapAndPanelAgree() throws {
        var state = try world()
        state.era = .medieval
        for index in state.regions.indices where abs(state.regions[index].coord.q) <= 2
            && abs(state.regions[index].coord.r) <= 2 {
            state.regions[index].explorationState = .fullyExplored
        }
        #expect(!GameEngine.layableEdges(state).isEmpty, "rule 67: assert the precondition first")
        for edge in GameEngine.layableEdges(state) {
            let asked = GameEngine.stretch(state, from: edge.link.a, to: edge.link.b)
            #expect(asked?.link.grade == edge.link.grade)
            #expect(asked.map { abs($0.cost - edge.cost) < 0.001 } == true)
        }
    }
}

/// A road was a fact about the world map that only the world map ever showed.
/// Keks: *"silnice jsou jen na mapě světa i když jsem je chtěl viditelné na
/// mapě osady."* The settlement's own canvas needs the way and the side of
/// the valley it comes in on.
@Suite("The ways arriving at a settlement")
struct RoadApproachTests {

    @Test("A road to the north comes in over the northern fence")
    func approachesCarryTheRightBearing() {
        let home = HexCoord(0, 0), north = HexCoord(0, -1)
        var net = RoadNetwork()
        net.lay(RoadLink(a: home, b: north, grade: .paved))
        let approaches = net.approaches(to: home)
        #expect(approaches.count == 1)
        let expected = Bearing.angle(from: home, toward: north)
        #expect(approaches.first.map { abs($0.angle - (expected ?? 0)) < 1e-9 } == true)
        // …and it leaves the valley on the same side of it.
        let edge = approaches[0].edgePoint
        #expect(edge.y < 0.5, "a way to the north must cross the map's northern edge")
    }

    @Test("A hex with no ways to it has no ways arriving")
    func noRoadsNoApproaches() {
        #expect(RoadNetwork().approaches(to: HexCoord(3, -2)).isEmpty)
    }

    @Test("Every way touching a hex arrives at it")
    func allSixCanArrive() {
        let home = HexCoord(1, 1)
        var net = RoadNetwork()
        for neighbour in home.neighbors() {
            net.lay(RoadLink(a: home, b: neighbour, grade: .road))
        }
        let approaches = net.approaches(to: home)
        #expect(approaches.count == 6)
        // Six ways in on six different bearings, not six drawn over each other.
        #expect(Set(approaches.map { Int(($0.angle * 1000).rounded()) }).count == 6)
    }

    @Test("The list is in the same order every time it is asked for")
    func orderIsStable() {
        let home = HexCoord(0, 0)
        var net = RoadNetwork()
        for neighbour in home.neighbors() { net.lay(RoadLink(a: home, b: neighbour)) }
        #expect(net.approaches(to: home).map(\.link.id) == net.approaches(to: home).map(\.link.id))
    }
}
