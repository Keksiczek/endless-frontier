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
        #expect(RoadEngine.build(poor, registry: reg).roads.isEmpty,
                "a colony with five materials must not be paving anything")

        var rich = s
        rich.settlements[0].storage[.materials] = 4000
        let built = RoadEngine.build(rich, registry: reg)
        #expect(!built.roads.isEmpty, "…and one with a full warehouse must be able to")
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
        #expect(decoded.roads.isEmpty)
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
