import Foundation

/// A concrete piece of work, at a place, on a thing.
///
/// A colonist's `assignedWork` is a *trade* — "logging" — and a post is a
/// building they hold a bench at. Neither is a job: neither says *which tree*.
/// Until now nobody ever went to a particular thing; the canvas picked a
/// plausible-looking spot from the trade and the simulation harvested an
/// abstract pool, so a logger drawn under a tree had no relationship to it.
///
/// A `Job` closes that: it names the work, where it happens, and what it is
/// being done to. The engine hands them out (`JobBoard`), the economy works
/// them, and the canvas draws the colonist at the thing itself.
public enum JobKind: String, Codable, Sendable, CaseIterable {
    case fellTree
    case quarryRock
    case raiseBuilding
    case tendDeposit     // fields and herb patches — ground, not a thing
    case standWatch
    case stalkAnimal     // *this* deer, standing over there
    case cutStone        // *this* block of the hillside, at the face

    /// The trade that does this work.
    public var work: WorkKind {
        switch self {
        case .fellTree: return .logging
        case .quarryRock, .cutStone: return .mining
        case .raiseBuilding: return .building
        case .tendDeposit: return .farming
        case .standWatch: return .garrison
        case .stalkAnimal: return .hunting
        }
    }
}

public struct Job: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public let kind: JobKind
    /// Where the work is, in local-map space.
    public let position: LocalPoint
    /// The tree, outcrop, building site or beast it is being done to, when it
    /// is being done to something. Ids are per-kind, hence a field each.
    public let treeID: Int?
    public let rockID: Int?
    public let placementID: UUID?
    public let animalID: UUID?

    public init(id: UUID, kind: JobKind, position: LocalPoint,
                treeID: Int? = nil, rockID: Int? = nil, placementID: UUID? = nil,
                animalID: UUID? = nil) {
        self.id = id
        self.kind = kind
        self.position = position
        self.treeID = treeID
        self.rockID = rockID
        self.placementID = placementID
        self.animalID = animalID
    }

    // MARK: - Codable (resilient: quarry came before the hunt)

    private enum CodingKeys: String, CodingKey {
        case id, kind, position, treeID, rockID, placementID, animalID
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        kind = try c.decode(JobKind.self, forKey: .kind)
        position = try c.decode(LocalPoint.self, forKey: .position)
        treeID = try c.decodeIfPresent(Int.self, forKey: .treeID)
        rockID = try c.decodeIfPresent(Int.self, forKey: .rockID)
        placementID = try c.decodeIfPresent(UUID.self, forKey: .placementID)
        animalID = try c.decodeIfPresent(UUID.self, forKey: .animalID)
    }

    public var work: WorkKind { kind.work }
}

/// Hands out the colony's work.
///
/// Deliberately *not* RimWorld's full think-tree: there is no interruption, no
/// opportunistic pickup and no reservation across ticks beyond what is stored on
/// the pawn. What it does have is the part that matters for a colony you watch —
/// every worker is on a named piece of work at a named place, and when that work
/// is finished or gone they are given another.
///
/// Deterministic throughout: jobs are built in the map's own stored order and
/// handed to pawns in theirs, so the same world always assigns the same work.
public enum JobBoard {
    /// How often work is re-posted and re-assigned, in ticks. Jobs outlive a
    /// single tick — a tree takes many to fell — so this need not run often, and
    /// offline catch-up replays tens of thousands of ticks through it.
    public static let interval = 10

    /// The work this settlement is offering right now, in a stable order.
    ///
    /// Everything here is derived from the world as it stands: no state to keep
    /// in sync, nothing to leak, and a job for a tree that has been felled
    /// simply stops being offered.
    public static func post(
        for settlement: Settlement, registry: GameDataRegistry
    ) -> [Job] {
        var jobs: [Job] = []
        guard let map = settlement.localMap else { return jobs }

        // Only ground the colony has actually charted. Sending a logger to a
        // tree out in the fog had them walk off into country nobody has seen —
        // and the canvas, which refuses to draw anyone under fog, simply made
        // them vanish on the way.
        func charted(_ p: LocalPoint) -> Bool { map.isExplored(p) }

        // Standing wood worth an axe, biggest first — the same order the felling
        // itself uses, so the job you are sent to is the one that gets chopped.
        for tree in map.trees
            .filter({ $0.growth >= FloraEngine.minimumWorkableGrowth && charted($0.position) })
            .sorted(by: { $0.timberYield == $1.timberYield
                          ? $0.id < $1.id : $0.timberYield > $1.timberYield }) {
            jobs.append(Job(id: jobID("fell", tree.id), kind: .fellTree,
                            position: tree.position, treeID: tree.id))
        }
        // Outcrops, **round-robined by what they are made of**.
        //
        // Posting them in plain id order put every granite bank ahead of every
        // clay bank, and the assigner takes jobs off the front: a coastal
        // colony with four miners and a dozen stone outcrops worked stone for
        // four hundred ticks and never touched one of its three clay beds. The
        // clay was not missing — it was behind a queue the miners could not
        // clear. (Rule 6 again, in its supply form: a resource whose only route
        // to the player is through an inexhaustible-enough backlog of another.)
        //
        // Interleaving by kind means the trade always has a face of each thing
        // the valley holds open at once, and nearest-first inside a kind still
        // eats a hillside from its near edge.
        let workable = map.rocks.filter { !$0.isSpent && charted($0.position) }
        let byKind = Dictionary(grouping: workable, by: \.kind)
            .mapValues { $0.sorted { $0.id < $1.id } }
        let rockKinds = byKind.keys.sorted { $0.rawValue < $1.rawValue }
        for slot in 0..<(byKind.values.map(\.count).max() ?? 0) {
            for kind in rockKinds {
                guard let seam = byKind[kind], slot < seam.count else { continue }
                let rock = seam[slot]
                jobs.append(Job(id: jobID("quarry", rock.id), kind: .quarryRock,
                                position: rock.position, rockID: rock.id))
            }
        }
        // The rock face: only blocks with open ground beside them, nearest the
        // town first, so a colony eats into a hillside from its near edge and
        // you can watch the working advance.
        for block in StoneEngine.workableBlocks(
            map.stone, from: SettlementGeometry.heart, charted: charted) {
            jobs.append(Job(id: jobID("hew", block), kind: .cutStone,
                            position: StoneField.centre(of: block), rockID: block))
        }
        // The game itself: a hunter is sent after *this* beast, standing where
        // it is standing. It moves, so the job's position is only good for as
        // long as the board is — which is exactly why the board is re-posted.
        for animal in map.wildlife.animals
            .filter({ !$0.species.isPredator && charted($0.position) })
            .sorted(by: { $0.id.uuidString < $1.id.uuidString }) {
            jobs.append(Job(id: jobID("stalk", animal.id), kind: .stalkAnimal,
                            position: animal.position, animalID: animal.id))
        }
        // Ground that is worked rather than a thing that is taken.
        for node in map.nodes
        where (node.kind == .field || node.kind == .herbs) && charted(node.position) {
            jobs.append(Job(id: jobID("tend", node.id), kind: .tendDeposit,
                            position: node.position))
        }
        // Scaffolding, and the walls that want a watch.
        if let colony = settlement.colony {
            for placement in colony.placements {
                let position = SettlementGeometry.canvasPoint(for: placement, in: colony)
                if placement.underConstruction {
                    jobs.append(Job(id: placement.id, kind: .raiseBuilding,
                                    position: position, placementID: placement.id))
                } else if (registry.building(placement.definitionID)?.defense ?? 0) > 0 {
                    jobs.append(Job(id: placement.id, kind: .standWatch,
                                    position: position, placementID: placement.id))
                }
            }
        }
        return jobs
    }

    /// Puts every working adult on a job their trade can do, and takes away any
    /// job that has stopped existing — the tree came down, the roof went on.
    public static func assign(
        _ settlement: Settlement, registry: GameDataRegistry
    ) -> Settlement {
        let jobs = post(for: settlement, registry: registry)
        let ticksPerYear = max(1, registry.config.ticksPerYear)

        var byTrade: [WorkKind: [Job]] = [:]
        for job in jobs { byTrade[job.work, default: []].append(job) }
        var taken: Set<UUID> = []
        var changed = false
        var pawns = settlement.pawns

        // Anyone already on a job that still exists keeps it: work should not be
        // dropped and re-picked every ten ticks, or nothing would ever finish.
        for i in pawns.indices {
            guard let held = pawns[i].currentJob else { continue }
            let stillOffered = byTrade[held.work]?.contains { $0.id == held.id } ?? false
            if stillOffered, !taken.contains(held.id),
               pawns[i].assignedWork == held.work,
               pawns[i].isAdult(ticksPerYear: ticksPerYear),
               !pawns[i].isBroken, !pawns[i].isAway {
                taken.insert(held.id)
            } else {
                pawns[i].currentJob = nil
                changed = true
            }
        }

        // Then fill the idle hands from what is left, in stable order.
        for i in pawns.indices {
            guard pawns[i].currentJob == nil,
                  pawns[i].isAdult(ticksPerYear: ticksPerYear),
                  !pawns[i].isBroken, !pawns[i].isAway else { continue }
            guard let offers = byTrade[pawns[i].assignedWork] else { continue }
            guard let job = offers.first(where: { !taken.contains($0.id) }) else { continue }
            pawns[i].currentJob = job
            taken.insert(job.id)
            changed = true
        }

        guard changed else { return settlement }
        var s = settlement
        s.pawns = pawns
        return s
    }

    /// A stable id per job, so the same work is the same job every time it is
    /// posted — otherwise a colonist would be "given" the tree they are already
    /// chopping as a brand-new job every cycle and never get anywhere.
    static func jobID(_ prefix: String, _ target: Int) -> UUID {
        hashedID(prefix) { h in (h ^ UInt64(bitPattern: Int64(target))) &* 0x0100_0000_01B3 }
    }

    /// The same, for work done to a thing that is identified by a UUID rather
    /// than by an index — a beast, unlike a tree, is not numbered by the map.
    static func jobID(_ prefix: String, _ target: UUID) -> UUID {
        hashedID(prefix) { start in
            var h = start
            for byte in target.uuidString.utf8 { h = (h ^ UInt64(byte)) &* 0x0100_0000_01B3 }
            return h
        }
    }

    private static func hashedID(_ prefix: String, _ mix: (UInt64) -> UInt64) -> UUID {
        var h: UInt64 = 0xCBF2_9CE4_8422_2325
        for byte in prefix.utf8 { h = (h ^ UInt64(byte)) &* 0x0100_0000_01B3 }
        h = mix(h)
        var bytes = [UInt8](repeating: 0, count: 16)
        for i in 0..<8 {
            bytes[i] = UInt8((h >> (8 * UInt64(i))) & 0xFF)
            bytes[i + 8] = UInt8((h.byteSwapped >> (8 * UInt64(i))) & 0xFF)
        }
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5],
                           bytes[6], bytes[7], bytes[8], bytes[9], bytes[10], bytes[11],
                           bytes[12], bytes[13], bytes[14], bytes[15]))
    }
}

/// Where a placed building sits in local-map space.
///
/// The renderer has always known this, but the Core needs it too now that jobs
/// carry positions — and the answer must be the same in both, or a colonist
/// would be sent to a building that is drawn somewhere else.
public enum SettlementGeometry {
    /// The colony grid's centre on the local map, and how wide a slice of it the
    /// grid covers. Mirrored by `SettlementRenderer.colonyHeart` / `colonySpan`.
    public static let heart = LocalPoint(x: 0.5, y: 0.52)
    /// Widened with the renderer's `colonySpan` when buildings gained insides,
    /// and again when a town of sixty was still not legible at a glance.
    /// These two numbers are one number in two places: a colonist sent to a
    /// scaffold at 0.42 while the scaffold is drawn at 0.58 stands in a field.
    ///
    /// Whatever this is, two other numbers must clear it: the ground a new map
    /// reveals (`LocalMapGenerator`) and the rock kept off the build grid
    /// (`StoneEngine.colonyClearance`). The grid's far **corner** is at
    /// `span * √2 / 2` from the heart, which is what both have to reach.
    public static let span: Double = 0.58

    /// How far the grid's furthest corner lies from the heart. The one number
    /// the reveal radius and the rock clearance are both derived from, so
    /// widening the town cannot quietly leave its edges in the fog or under a
    /// mountain.
    public static var cornerReach: Double { span * 0.70710678 }

    public static func canvasPoint(for placement: BuildingPlacement, in colony: ColonyMap) -> LocalPoint {
        let w = Double(max(1, colony.width)), h = Double(max(1, colony.height))
        // The footprint's middle, not its top-left corner.
        let fx = (Double(placement.coord.x) + Double(placement.width) / 2) / w - 0.5
        let fy = (Double(placement.coord.y) + Double(placement.height) / 2) / h - 0.5
        return LocalPoint(x: heart.x + fx * span, y: heart.y + fy * span)
    }
}
