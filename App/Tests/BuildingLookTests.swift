import Testing
import Foundation
import EndlessFrontierCore
@testable import EndlessFrontier

/// Forty-seven buildings used to be drawn as eight shapes, and the mapping was
/// blunt enough that a library, a school, a bank, a market and an observatory
/// were all the same Greek temple, while a spaceport was a workshop shed. These
/// tests run the real `buildings.json` through the mapping, because the point of
/// the change is what the *shipping content* looks like, not a fixture.
@Suite("A colony's skyline has more than one idea in it")
struct BuildingLookTests {

    private func allBuildings() throws -> [BuildingDefinition] {
        Array(try GameDataRegistry.bundled().buildings.values)
    }

    private func glyph(_ id: String, _ defs: [BuildingDefinition])
        -> SettlementRenderer.BuildingGlyph? {
        defs.first { $0.id == id }.map(SettlementRenderer.glyph(for:))
    }

    /// **Furniture written for a room nobody furnishes is furniture nobody
    /// sees.** A well, an aqueduct, a wall, a dam, a panel field, a turbine and
    /// a launch apron have no inside (`SettlementInterior.roofless`), so a
    /// fitting whose only rooms are those is content that loads, validates and
    /// draws nothing — rule 47 in the furniture.
    @Test("No fitting stands only in a room nobody furnishes")
    func fittingsStandWhereSomebodyLooks() throws {
        let registry = try GameDataRegistry.bundled()
        let defs = Array(registry.buildings.values)
        let byID = Dictionary(uniqueKeysWithValues: defs.map { ($0.id, $0) })

        /// A room name is either an archetype — the glyph a `look` draws — or a
        /// building by id (rule 108). Both resolve to the glyph that decides
        /// whether anything is drawn inside.
        func glyphs(of room: String) -> SettlementRenderer.BuildingGlyph? {
            if let named = SettlementRenderer.glyph(named: room) { return named }
            return byID[room].map(SettlementRenderer.glyph(for:))
        }

        for (id, fitting) in registry.fittings {
            let rooms = fitting.rooms.compactMap(glyphs(of:))
            #expect(!rooms.isEmpty,
                    "\(id) stands in \(fitting.rooms), none of which is a room or a building")
            #expect(rooms.contains { !SettlementInterior.roofless.contains($0) },
                    "\(id) stands only in \(fitting.rooms), which have no inside")
        }
    }

    /// The set that decides whether a room is drawn and the book that furnishes
    /// rooms are two lists of the same idea, and rule 92 says they will drift.
    /// So they are held to each other against the **shipped** content: nothing
    /// stands in a roofless structure, and everything else has something in it.
    @Test("The book furnishes exactly the rooms that have an inside")
    func rooflessRoomsAreUnfurnished() throws {
        let registry = try GameDataRegistry.bundled()
        for glyph in SettlementRenderer.BuildingGlyph.allCases {
            let furniture = registry.fittings(inRoom: glyph.rawValue, era: .medieval)
            if SettlementInterior.roofless.contains(glyph) {
                #expect(furniture.isEmpty,
                        "\(glyph.rawValue) has no inside, and \(furniture.count) things stand in it")
            } else {
                #expect(!furniture.isEmpty,
                        "\(glyph.rawValue) is drawn as a room and the book furnishes it with nothing")
            }
        }
    }

    /// **A name the renderer does not know draws nothing** — which reads as a
    /// plainer building rather than as a fault, and is exactly how 54 names sat
    /// in `structures.json` for a day being validated, generated and drawn by
    /// nobody (rule 47). Fifty-four names, fifteen forms; a new composition
    /// with a new name fails here before anybody wonders why the yard is empty.
    /// **The one that would have caught it.** The first placement refused
    /// anything that did not fit whole inside the plot — and a body is nearly
    /// as wide as its lot, so for an ordinary house every side position tested
    /// false and the yards stayed empty. The drawing was written, the data was
    /// there, and the arithmetic between them threw the work away without a
    /// word. Counting is the whole guard.
    @Test("Everything a composition names is actually placed",
          arguments: [(2, 2), (3, 3), (4, 3), (3, 2)])
    func compositionsArePlaced(w: Int, h: Int) throws {
        let registry = try GameDataRegistry.bundled()
        let lot = CGRect(x: 100, y: 100, width: CGFloat(w) * 14, height: CGFloat(h) * 14)
        let body = lot.insetBy(dx: lot.width * 0.1, dy: lot.height * 0.16)
            .offsetBy(dx: 0, dy: lot.height * 0.05)
        var thin: [String] = []
        for (id, composition) in registry.structures where !composition.attachments.isEmpty {
            let drawable = composition.attachments.filter { SettlementAttachments.form(of: $0) != nil }
            let placed = SettlementAttachments.places(
                names: composition.attachments, body: body, lot: lot, seed: 99)
            if placed.count < drawable.count { thin.append(id) }
        }
        #expect(thin.isEmpty, "nothing was put in the yard of: \(thin.sorted().prefix(8))")
    }

    @Test("Every attachment in the bank is a thing the canvas can draw")
    func attachmentsAreDrawable() throws {
        let registry = try GameDataRegistry.bundled()
        var unknown: Set<String> = []
        for (_, composition) in registry.structures {
            for name in composition.attachments where SettlementAttachments.form(of: name) == nil {
                unknown.insert(name)
            }
        }
        #expect(unknown.isEmpty, "nothing is drawn for: \(unknown.sorted())")
    }

    /// …and the bank has to actually reach the drawing. `StructureVariant` was
    /// carrying `standing` and `accent` and dropping `attachments` on the floor,
    /// so every yard in the colony was empty however full the composition was.
    @Test("A building's own composition reaches the drawing")
    func compositionsCarryTheirAttachments() throws {
        let registry = try GameDataRegistry.bundled()
        let furnished = registry.buildings.values.filter {
            !(registry.structure($0.id).attachments.isEmpty)
        }
        #expect(furnished.count > 30,
                "only \(furnished.count) buildings have anything standing beside them")
        for def in furnished {
            let variant = StructureVariant.of(def, housesConveyances: false,
                                              composition: registry.structure(def.id))
            #expect(!variant.attachments.isEmpty,
                    "\(def.id) has attachments in the bank and none in its variant")
        }
    }

    /// **A rider is deep where the horse's feet are.** The town's sorted pass
    /// compares the ground a thing stands on, so handing it the seat of a mount
    /// — which is drawn two thirds of a body higher — would put a rider behind
    /// the house they are riding past.
    @Test("Everybody is handed over with the ground they stand on")
    func agentsCarryTheirFoot() throws {
        let registry = try GameDataRegistry.bundled()
        var settlement = Settlement(
            id: UUID(uuidString: "00000000-0000-0000-2222-000000000001")!,
            name: "Footville",
            buildings: [BuildingInstance(definitionID: "hut", count: 2)])
        settlement.pawns = (0..<6).map { PawnFactory.generate(seed: UInt64($0 + 1)) }
        settlement.colony = ColonyMap(width: 16, height: 16)
        let map = LocalMap(river: RiverShape(baseY: 0.5, amplitude: 0.05, phase: 0),
                           nodes: [], pois: [],
                           exploredCells: Set(0..<(LocalMap.gridColumns * LocalMap.gridRows)))
        let rect = CGRect(x: 0, y: 0, width: 400, height: 400)

        let standing = SettlementRenderer.standingAgents(
            rect: rect, settlement: settlement, map: map, continuousTick: 3,
            registry: registry, time: 12, zoom: 3, selectedPawnID: nil)
        #expect(!standing.isEmpty, "nobody was handed over to the sorted pass")
        for item in standing {
            #expect(item.foot >= rect.minY && item.foot <= rect.maxY,
                    "somebody is standing off the map at \(item.foot)")
        }
    }

    /// **Every field the bank carries is spent somewhere.** `attachments` sat
    /// unread for a day, and `fabric`, `trim`, `roof`, `rooftop` and `yard` sat
    /// beside it — a composition that says `barrel` and is drawn `gable` is a
    /// bank nobody reads (rule 47). This asks the variant, which is what the
    /// drawing asks.
    @Test("A composition's roof, fabric, yard and attachments all reach the drawing")
    func compositionsAreSpent() throws {
        let registry = try GameDataRegistry.bundled()
        var checked = 0
        for def in registry.buildings.values {
            let bank = registry.structure(def.id)
            let variant = StructureVariant.of(def, housesConveyances: false, composition: bank)
            #expect(variant.fabric == bank.fabric, "\(def.id) draws a wall the bank did not name")
            #expect(variant.yard == bank.yard, "\(def.id) draws a yard the bank did not name")
            #expect(variant.attachments == bank.attachments,
                    "\(def.id) drops what the bank stands beside it")
            if let named = StructureVariant.Roofline(rawValue: bank.roof) {
                #expect(variant.roofline == named,
                        "\(def.id) is roofed \(variant.roofline.rawValue), the bank says \(bank.roof)")
                checked += 1
            }
            #expect(SettlementFabric.known(variant.fabric),
                    "\(def.id) is walled in '\(variant.fabric)', which the canvas cannot draw")
        }
        #expect(checked > 40, "only \(checked) rooflines came from the bank")
    }

    @Test("Buildings that are nothing alike are not drawn alike")
    func landmarkBuildingsGetTheirOwnShape() throws {
        let defs = try allBuildings()
        #expect(glyph("hut", defs) == .house)
        #expect(glyph("apartment_block", defs) == .tenement)
        #expect(glyph("library", defs) == .hall)
        #expect(glyph("university", defs) == .hall)
        #expect(glyph("market", defs) == .market)
        #expect(glyph("bank", defs) == .vault)
        #expect(glyph("palisade", defs) == .wall)
        #expect(glyph("watchtower", defs) == .tower)
        #expect(glyph("solar_array", defs) == .array)
        #expect(glyph("wind_farm", defs) == .turbine)
        #expect(glyph("spaceport", defs) == .pad)
        // A craftsman's shed and a heavy plant are not the same building.
        #expect(glyph("workshop", defs) == .workshop)
        #expect(glyph("factory", defs) == .plant)
        // The three the numbers cannot tell apart — all just "make materials".
        #expect(glyph("lumberyard", defs) == .sawmill)
        #expect(glyph("quarry", defs) == .mine)
        #expect(glyph("foundry", defs) == .forge)
        // …and the four that all just "produce food or store it".
        #expect(glyph("farm_basic", defs) == .farm)
        #expect(glyph("granary", defs) == .granary)
        #expect(glyph("well", defs) == .well)
        #expect(glyph("hunters_lodge", defs) == .lodge)
    }

    /// The point of the whole pass: nothing may be left to the *derivation*.
    ///
    /// Thirty-six of the forty-seven stated no `look` at all, and the numbers
    /// cannot tell a farm from a granary from a well — so thirteen buildings
    /// came out as the same lecture hall and nine as the same smoking block.
    /// Deriving is the fallback for content that has not caught up; shipping
    /// content should never need it.
    @Test("Every shipped building says what it looks like")
    func nothingIsLeftToTheDerivation() throws {
        let unnamed = try allBuildings().filter { $0.look == nil }.map(\.id).sorted()
        #expect(unnamed.isEmpty, "these fall back to a guessed shape: \(unnamed)")
    }

    /// The bug a screenshot found and the tests had not: `size` came from
    /// `0.021 × max(w, h)`, which has nothing to do with the lot, so a 3×2 was
    /// drawn twice as wide as its own plot and the colony read as a heap of
    /// overlapping glyphs.
    @Test("A building is drawn small enough to stand on its own lot",
          arguments: [(1, 1), (2, 1), (2, 2), (3, 2), (3, 3)])
    func structuresFitTheirFootprint(w: Int, h: Int) {
        let reg = GameDataRegistry(
            buildings: [BuildingDefinition(id: "b", era: .earlySettlement, name: "B",
                                           cost: [.materials: 10],
                                           production: [.materials: 3],
                                           footprint: TileSize(width: w, height: h))],
            techs: [], eras: [], biomes: [], events: [], config: .default)
        var s = Settlement(id: UUID(uuidString: "00000000-0000-0000-F17F-000000000001")!,
                           name: "Fitville",
                           buildings: [BuildingInstance(definitionID: "b", count: 1)])
        var colony = ColonyMap(width: 12, height: 12)
        colony.placements = [BuildingPlacement(
            id: UUID(uuidString: "00000000-0000-0000-F17F-000000000002")!,
            definitionID: "b", coord: TileCoord(4, 4), width: w, height: h)]
        s.colony = colony
        let b = SettlementRenderer.normalizedLayout(settlement: s, registry: reg)[0]
        // Measured off the walls the renderer actually draws rather than off a
        // remembered "a body is about 2.2 × size" — that constant was a guess
        // covering every glyph, and `lotSize` now sizes each glyph against its
        // own proportions so the building fills the plot it paid for. Asking
        // `bodySize` is asking the drawing.
        //
        // The widest a body ever gets is at the top of its own size jitter, so
        // that is what has to fit.
        //
        // **Deliberately without `height:`.** Whether a building fits its lot
        // is a question about the *plan*, and `standing` is not part of the
        // plan: a tall building rises out of its footprint rather than spilling
        // sideways into next door's (`SettlementStructures.bodyRect`).
        let walls = SettlementStructures.bodySize(
            b.glyph, s: b.size * SettlementRenderer.maxBodyJitter, seed: b.seed,
            aspect: b.footprintH > 0 ? b.footprintW / b.footprintH : 1)
        #expect(walls.width <= b.footprintW + 1e-9,
                "a \(w)×\(h) body is \(walls.width) across a \(b.footprintW) lot")
        #expect(walls.height <= b.footprintH + 1e-9,
                "a \(w)×\(h) body is \(walls.height) tall on a \(b.footprintH) lot")
        // …and it is not lost in the middle of it either. The complaint this
        // sizing answers was that the buildings were too small for what has to
        // fit inside them, so a body that fills less than three quarters of its
        // plot across is the bug coming back.
        // …and down as well as across. Sizing solves on whichever axis binds
        // first, so before `bodySize` learned to take up the slack a house on a
        // square lot filled 85% across and **58% down** — a squat model of a
        // house with bare ground above and below, and a room shrunk to match.
        #expect(walls.height >= b.footprintH * 0.72,
                "a \(w)×\(h) body is \(walls.height) tall on a \(b.footprintH) lot")
        #expect(walls.width >= b.footprintW * 0.72,
                "a \(w)×\(h) building is rattling around in its own lot")
    }

    /// Two buildings on neighbouring tiles must not grow into each other.
    @Test("Neighbouring buildings do not overlap")
    func neighboursKeepTheirDistance() {
        let reg = GameDataRegistry(
            buildings: [BuildingDefinition(id: "b", era: .earlySettlement, name: "B",
                                           cost: [.materials: 10],
                                           production: [.materials: 3])],
            techs: [], eras: [], biomes: [], events: [], config: .default)
        var s = Settlement(id: UUID(uuidString: "00000000-0000-0000-F17F-000000000003")!,
                           name: "Rowville",
                           buildings: [BuildingInstance(definitionID: "b", count: 2)])
        var colony = ColonyMap(width: 12, height: 12)
        colony.placements = [
            BuildingPlacement(id: UUID(uuidString: "00000000-0000-0000-F17F-000000000004")!,
                              definitionID: "b", coord: TileCoord(4, 4)),
            BuildingPlacement(id: UUID(uuidString: "00000000-0000-0000-F17F-000000000005")!,
                              definitionID: "b", coord: TileCoord(5, 4))
        ]
        s.colony = colony
        let layout = SettlementRenderer.normalizedLayout(settlement: s, registry: reg)
        let gap = abs(layout[1].center.x - layout[0].center.x)
        // Half of each body, at the widest its jitter goes — the same question
        // as before, asked of the drawing rather than of a constant.
        func halfWidth(_ b: SettlementRenderer.NormalizedBuilding) -> Double {
            SettlementStructures.bodySize(
                b.glyph, s: b.size * SettlementRenderer.maxBodyJitter, seed: b.seed,
                aspect: b.footprintH > 0 ? b.footprintW / b.footprintH : 1).width / 2
        }
        // They are sized to fill their lots, so neighbours touch rather than
        // clear — the epsilon is float slack, not headroom.
        #expect(gap >= halfWidth(layout[0]) + halfWidth(layout[1]) - 1e-9)
    }

    /// `look` is content, so a typo must not silently pick a shape.
    @Test("Every look named in the content is one the renderer knows")
    func statedLooksAllResolve() throws {
        for def in try allBuildings() {
            guard let look = def.look else { continue }
            #expect(SettlementRenderer.glyph(named: look) != nil,
                    "\(def.id) asks for an unknown look '\(look)'")
        }
    }

    /// The regression that matters: no single silhouette may swallow the town.
    @Test("No one silhouette carries most of the colony")
    func silhouettesAreSpread() throws {
        let defs = try allBuildings()
        var counts: [String: Int] = [:]
        for def in defs { counts["\(SettlementRenderer.glyph(for: def))", default: 0] += 1 }
        let biggest = counts.values.max() ?? 0
        // Before this change the temple alone took 12 of 47.
        #expect(counts.count >= 24, "only \(counts.count) distinct silhouettes: \(counts)")
        #expect(Double(biggest) / Double(defs.count) < 0.12,
                "one silhouette takes \(biggest) of \(defs.count): \(counts)")
    }

    /// A fusion-era colony should not still be built out of wattle and thatch.
    @Test("What a building is made of follows the era that raised it")
    func materialsAgeWithTheEra() {
        let early = SettlementStructures.materials(.earlySettlement)
        let industrial = SettlementStructures.materials(.earlyIndustrial)
        let future = SettlementStructures.materials(.nearFuture)
        #expect(early.wall != industrial.wall)
        #expect(industrial.wall != future.wall)
        // Timber is warm (more red than blue); panel and glass are cool.
        #expect(early.wall.0 > early.wall.2)
        #expect(future.wall.2 > future.wall.0)
    }
}

/// **Does the inside match the outside?**
///
/// Three things claim to know where the floor of a building is: the drawing
/// (`SettlementInterior.draw`), the motion that stands workers at its fittings
/// (`AgentMotion.WorkSite`), and the motion that puts a household to bed. They
/// agreed on two of the three, and the third — the beds — was still measuring
/// against the *lot*, so a household slept spread across the parcel while its
/// mattresses were drawn in a ring inside the walls.
@Suite("The room is the room, wherever you ask from")
struct InteriorFitTests {

    private func registry(w: Int, h: Int, housing: Double = 30,
                          standing: Double? = nil) -> GameDataRegistry {
        GameDataRegistry(
            buildings: [BuildingDefinition(id: "b", era: .earlySettlement, name: "B",
                                           cost: [.materials: 10], housing: housing,
                                           footprint: TileSize(width: w, height: h))],
            techs: [], eras: [], biomes: [], events: [],
            structures: standing.map { [StructureDefinition(id: "b", standing: $0)] } ?? [],
            fittings: TestBook.fittings,
            config: .default)
    }

    /// A tall building is *held above its own footprint*, and the gap is the
    /// wall face (`RENDER_25D.md` §2). Zero for an ordinary shed, so a colony
    /// without a bank draws where it always did.
    @Test("What stands taller is lifted, not just stretched")
    func standingLiftsTheDrawing() {
        let shed = registry(w: 3, h: 3)
        let tower = registry(w: 3, h: 3, standing: 3.2)
        func lift(_ reg: GameDataRegistry) -> Double {
            let b = SettlementRenderer.normalizedLayout(settlement: colony(w: 3, h: 3),
                                                        registry: reg)[0]
            return SettlementStructures.rise(
                b.glyph, s: b.size, seed: b.seed,
                aspect: b.footprintH > 0 ? b.footprintW / b.footprintH : 1,
                height: Double(b.variant.heightScale))
        }
        #expect(lift(shed) == 0, "a shed with no bank entry is lifted off the ground")
        #expect(lift(tower) > 0, "a tower that stands 3.2 is drawn flat on its plot")
    }

    /// **A storey goes on at the top, and everybody in the building goes up
    /// with it.**
    ///
    /// `bodyRect` leaves the foot where the plan put it and adds the height
    /// above, so the drawn body's middle rises by half of whatever was added.
    /// `AgentMotion` measured its stations from the building's *map point*,
    /// which is the plan's middle — so in a tall building the workers stood
    /// half a storey below the floor they were drawn on. One number, three
    /// readers (rule 35): `SettlementStructures.bodyLift`.
    @Test("A storey lifts the room and the people in it together")
    func tallRoomsCarryTheirWorkers() {
        let reg = registry(w: 3, h: 3, standing: 2.6)
        let b = SettlementRenderer.normalizedLayout(settlement: colony(w: 3, h: 3),
                                                    registry: reg)[0]
        let aspect = b.footprintH > 0 ? b.footprintW / b.footprintH : 1
        let lift = SettlementStructures.bodyLift(b.glyph, s: b.size, seed: b.seed,
                                                 aspect: aspect,
                                                 height: Double(b.variant.heightScale),
                                                 footprintHeight: b.footprintH)
        // Not a vacuous test: this building really is taller than a shed.
        #expect(b.variant.heightScale > 1.05, "the structure bank did not make it tall")
        #expect(lift > 0, "a taller building has to lift its room")

        let site = AgentMotion.WorkSite(b, era: .earlySettlement, registry: reg)
        let walls = SettlementStructures.bodySize(b.glyph, s: b.size, seed: b.seed,
                                                  aspect: aspect,
                                                  height: Double(b.variant.heightScale))
        let middle = b.center.y - lift
        for bed in SettlementInterior.bedSlots(seed: b.seed, sleepers: 6).map(site.place) {
            #expect(abs(bed.y - middle) <= walls.height / 2 + 1e-9,
                    "somebody is standing outside the walls that were drawn for them")
        }
    }

    private func colony(w: Int, h: Int) -> Settlement {
        var s = Settlement(id: UUID(uuidString: "00000000-0000-0000-1111-000000000001")!,
                           name: "Insideville",
                           buildings: [BuildingInstance(definitionID: "b", count: 1)])
        var c = ColonyMap(width: 16, height: 16)
        c.placements = [BuildingPlacement(
            id: UUID(uuidString: "00000000-0000-0000-1111-000000000002")!,
            definitionID: "b", coord: TileCoord(5, 5), width: w, height: h)]
        s.colony = c
        return s
    }

    /// Every fitting the motion places has to land inside the walls the
    /// renderer draws — that is the whole claim `Slot` makes.
    @Test("Everything the motion places stands inside the drawn walls",
          arguments: [(2, 2), (3, 3), (3, 2), (4, 3)])
    func fittingsLandInsideTheWalls(w: Int, h: Int) {
        let reg = registry(w: w, h: h)
        let b = SettlementRenderer.normalizedLayout(settlement: colony(w: w, h: h),
                                                    registry: reg)[0]
        let site = AgentMotion.WorkSite(b, era: .earlySettlement, registry: reg)
        // The walls as they are actually drawn — height and all. See the note
        // in `roomIsTheWallsNotTheLot`.
        let walls = SettlementStructures.bodySize(
            b.glyph, s: b.size, seed: b.seed,
            aspect: b.footprintH > 0 ? b.footprintW / b.footprintH : 1,
            height: Double(b.variant.heightScale))
        let beds = SettlementInterior.bedSlots(seed: b.seed, sleepers: 8).map(site.place)
        #expect(!beds.isEmpty)
        let middle = b.center.y - SettlementStructures.bodyLift(
            b.glyph, s: b.size, seed: b.seed,
            aspect: b.footprintH > 0 ? b.footprintW / b.footprintH : 1,
            height: Double(b.variant.heightScale),
            footprintHeight: b.footprintH)
        for bed in beds {
            #expect(abs(bed.x - b.center.x) <= walls.width / 2 + 1e-9,
                    "a bed is drawn outside the walls it belongs to")
            #expect(abs(bed.y - middle) <= walls.height / 2 + 1e-9)
        }
    }

    /// …and the room the fittings are measured against is the room the walls
    /// enclose, not the parcel the building was given.
    @Test("The floor is the walls inset, not the lot")
    func roomIsTheWallsNotTheLot() {
        let reg = registry(w: 3, h: 3)
        let b = SettlementRenderer.normalizedLayout(settlement: colony(w: 3, h: 3),
                                                    registry: reg)[0]
        let site = AgentMotion.WorkSite(b, era: .earlySettlement, registry: reg)
        // **The same walls, height and all.** `bodySize` reads `standing` out
        // of `structures.json` now (`StructureVariant.heightScale`), and three
        // callers share the formula precisely so they cannot disagree — a test
        // that asks for the walls without the height is a fourth caller
        // disagreeing with the other three, which is the fault this test exists
        // to catch, pointed at itself.
        let walls = SettlementStructures.bodySize(
            b.glyph, s: b.size, seed: b.seed,
            aspect: b.footprintH > 0 ? b.footprintW / b.footprintH : 1,
            height: Double(b.variant.heightScale))
        let inset = 1 - SettlementInterior.wallInset * 2
        #expect(abs(site.roomW - walls.width * inset) < 1e-9)
        #expect(abs(site.roomH - walls.height * inset) < 1e-9)
        #expect(site.roomW < b.footprintW, "the floor is not the whole parcel")
    }

    /// The complaint this answers: eight people posted to a room that laid out
    /// five places had three of them standing inside somebody else.
    @Test("A room seats everybody the engine posts to it")
    func nobodyShareAStool() {
        for crowd in [2, 5, 8, 11] {
            let places = SettlementInterior.stationSlots(
                for: .workshop, seed: 0x51F0_1234, stations: crowd,
                era: .earlySettlement, registry: registry(w: 3, h: 3))
            #expect(places.count >= crowd,
                    "fewer places than colonists — the rest stand on each other")
            // …and no two of those places are the same point.
            let distinct = Set(places.map { "\(($0.dx * 1000).rounded())/\(($0.dy * 1000).rounded())" })
            #expect(distinct.count == places.count, "two fittings in the same spot")
        }
    }
}

/// **No two buildings are drawn the same.**
///
/// Twenty-three of the fifty-three shared a `look` with something else, so five
/// industries were one smoking block and four laboratories were one glass one.
/// The archetype is right — a factory *is* shaped like a plant — so the fix is
/// composition rather than seventeen more hand-drawn shapes, and
/// `StructureVariant` is the composition.
///
/// `signature` stands in for the drawing: every field of it is read by
/// `SettlementStructures`, so two buildings with the same signature really do
/// come out identical on the canvas. This is the standing rule ("every thing
/// must be unique and do something") made into something that can fail.
@Suite("Every building looks like itself")
struct StructureVariantTests {
    private func variants() throws -> [(BuildingDefinition, StructureVariant)] {
        let registry = try GameDataRegistry.bundled()
        let sheds = StructureVariant.conveyanceHomes(registry)
        return registry.buildings.values.map {
            ($0, StructureVariant.of($0, housesConveyances: sheds.contains($0.id)))
        }
    }

    @Test("No two buildings share both an archetype and a composition")
    func everyBuildingIsItsOwnDrawing() throws {
        var seen: [String: String] = [:]
        for (def, variant) in try variants() {
            let key = "\(SettlementRenderer.glyph(for: def).hashValue)|\(variant.signature)"
            if let other = seen[key] {
                Issue.record("'\(def.id)' is drawn exactly like '\(other)' — same shape, same composition")
            }
            seen[key] = def.id
        }
    }

    /// The five that were one drawing before this existed. Named outright so a
    /// future change that collapses them again fails on the case that mattered.
    @Test("The five plants are five different places")
    func theIndustriesDiffer() throws {
        let byID = Dictionary(uniqueKeysWithValues: try variants().map { ($0.0.id, $0.1) })
        let plants = ["factory", "vehicle_works", "assembly_plant", "automated_factory", "garage"]
        let signatures = Set(plants.compactMap { byID[$0]?.signature })
        #expect(signatures.count == plants.count,
                "a player must be able to tell the place that builds lorries from the place that builds everything")
    }

    /// Derivation must be a function of the *definition*, or a building
    /// redecorates itself between launches.
    @Test("A building's look does not change between runs")
    func derivationIsStable() throws {
        let registry = try GameDataRegistry.bundled()
        let sheds = StructureVariant.conveyanceHomes(registry)
        for def in registry.buildings.values {
            let once = StructureVariant.of(def, housesConveyances: sheds.contains(def.id))
            let twice = StructureVariant.of(def, housesConveyances: sheds.contains(def.id))
            #expect(once == twice)
        }
        // …and not on `String.hashValue`, which Swift seeds per process. Pinned
        // to the literal FNV-1a value so a change of hash is a failing test
        // rather than a town that quietly rebuilds itself overnight.
        #expect(StructureVariant.kindSeed(for: "garage") == 0x9826_1AD9_7975_232C)
    }

    /// Each axis has to say something true, or it is decoration with extra
    /// steps. These are the four claims the drawing makes.
    @Test("What the drawing says about a building is true of it")
    func axesMeanSomething() throws {
        let byID = Dictionary(uniqueKeysWithValues: try variants().map { ($0.0.id, $0.1) })
        let registry = try GameDataRegistry.bundled()

        // A clean industry raises no chimney, however big it is.
        if let fusion = byID["fusion_reactor"], let plant = byID["power_plant"] {
            #expect(fusion.stacks == 0, "fusion burns nothing — it must not smoke")
            #expect(plant.stacks > 0, "a coal-fired plant must")
        }
        // Somewhere that keeps a vehicle has a door one fits through.
        let sheds = StructureVariant.conveyanceHomes(registry)
        #expect(!sheds.isEmpty, "conveyances.json must still name the buildings vehicles are kept at")
        for shed in sheds {
            #expect(byID[shed]?.wideDoor == true, "'\(shed)' keeps vehicles and needs a door for them")
        }
        // Nobody posted, nothing lit.
        for (def, variant) in try variants() where def.workers == 0 {
            #expect(!variant.nightShift, "'\(def.id)' has no workers and must be dark at night")
        }
        // A stouter wall is drawn stouter.
        if let palisade = byID["palisade"], let stone = byID["stone_walls"] {
            #expect(stone.heft > palisade.heft, "masonry turns more aside than stakes, and looks it")
        }
    }
}
