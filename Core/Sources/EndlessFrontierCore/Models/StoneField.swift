import Foundation

/// The mountain, as blocks you dig into.
///
/// Stone came in two shapes before this, and neither was a mountain. There was
/// a `stone` deposit — a number on the ground that went down as miners worked
/// — and there were `Rock` outcrops, which are boulders: things standing *on*
/// the land. Neither is the thing a colony in the hills actually does, which is
/// to find a cliff and go into it.
///
/// A `StoneField` is a lattice of solid rock cells sitting on the local map. It
/// is dug **at the face**: only a block with open ground beside it can be
/// worked, so a colony eats into a massif from its edge and leaves a widening
/// bite behind, the way a quarry actually looks. Each block gives up its stone
/// once and never grows back — a mountain is a finite thing, and the fact that
/// it runs out is the reason a colony has to go somewhere else eventually.
///
/// Deliberately on the same lattice as the fog grid: the mountain is something
/// you have to *find*, it hides what is behind it, and a block is a
/// map-sized unit rather than a floating decoration. What each block is made
/// of is computed from a seed rather than stored, exactly as the ground cover
/// is, so a save stays small.
public struct StoneField: Codable, Sendable, Equatable {
    /// The blocks still standing, as `row * LocalMap.gridColumns + column`.
    public var solid: Set<Int>
    /// Pick-work banked into a block, 0…1. Only blocks somebody has started on
    /// appear here — the same trick a half-felled tree uses, so the work is in
    /// the world rather than in the colonist.
    public var cut: [Int: Double]
    /// Seed for what the seams are made of.
    public var seed: UInt64
    /// Whether this map has a stone layer at all.
    ///
    /// Not the same question as `solid.isEmpty`: a massif dug flat has no solid
    /// blocks either, and treating the two alike is the mistake that made a
    /// logged-out wood read as half-full for a whole session (see
    /// `LocalMap.usesEntityLand`).
    public var usesBlocks: Bool

    public init(solid: Set<Int> = [], cut: [Int: Double] = [:], seed: UInt64 = 0,
                usesBlocks: Bool = false) {
        self.solid = solid
        self.cut = cut
        self.seed = seed
        self.usesBlocks = usesBlocks || !solid.isEmpty
    }

    // MARK: - Codable (resilient: most maps have no mountain in them)

    private enum CodingKeys: String, CodingKey { case solid, cut, seed, usesBlocks }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        solid = try c.decodeIfPresent(Set<Int>.self, forKey: .solid) ?? []
        cut = try c.decodeIfPresent([Int: Double].self, forKey: .cut) ?? [:]
        seed = try c.decodeIfPresent(UInt64.self, forKey: .seed) ?? 0
        usesBlocks = try c.decodeIfPresent(Bool.self, forKey: .usesBlocks) ?? !solid.isEmpty
    }

    public var isEmpty: Bool { solid.isEmpty }
    public var blockCount: Int { solid.count }

    // MARK: - Where a block is

    public static func index(column: Int, row: Int) -> Int {
        row * LocalMap.gridColumns + column
    }

    public static func column(of index: Int) -> Int { index % LocalMap.gridColumns }
    public static func row(of index: Int) -> Int { index / LocalMap.gridColumns }

    /// The middle of a block, in the normalised space everything else uses.
    public static func centre(of index: Int) -> LocalPoint {
        LocalPoint(x: (Double(column(of: index)) + 0.5) / Double(LocalMap.gridColumns),
                   y: (Double(row(of: index)) + 0.5) / Double(LocalMap.gridRows))
    }

    /// The block a point falls in, if it falls in one.
    public func block(at point: LocalPoint) -> Int? {
        let index = LocalMap.cellIndex(point)
        return solid.contains(index) ? index : nil
    }

    public func isSolid(_ index: Int) -> Bool { solid.contains(index) }

    /// Whether a point is inside the mountain — which is also the question
    /// "can anything be built or walked here".
    public func blocks(_ point: LocalPoint) -> Bool {
        solid.contains(LocalMap.cellIndex(point))
    }

    // MARK: - The face

    /// Whether a block can be worked: it must have open ground beside it.
    ///
    /// This is the whole of "you dig *into* it". Without it a colony would mine
    /// the middle of a mountain first and leave a shell, which is neither how
    /// rock works nor anything you would want to look at.
    public func isFace(_ index: Int) -> Bool {
        guard solid.contains(index) else { return false }
        let col = Self.column(of: index), row = Self.row(of: index)
        for (dx, dy) in [(-1, 0), (1, 0), (0, -1), (0, 1)] {
            let c = col + dx, r = row + dy
            // The edge of the map counts as open: a massif running off the side
            // can still be worked from the map's rim.
            guard c >= 0, c < LocalMap.gridColumns, r >= 0, r < LocalMap.gridRows else {
                return true
            }
            if !solid.contains(Self.index(column: c, row: r)) { return true }
        }
        return false
    }

    /// Every workable block, in a stable order — the order the job board hands
    /// them out in, so the same colony always digs the same corridor.
    public func faces() -> [Int] {
        solid.filter(isFace).sorted()
    }

    /// What a given block is made of. Computed, never stored: seams run in
    /// patches rather than per-block noise, so a vein of ore is a vein.
    public func kind(of index: Int) -> RockKind {
        let col = Self.column(of: index), row = Self.row(of: index)
        let patch = hash(seed &+ 0x5EA_11, col / 3, row / 3)
        let roll = Double(patch & 0xFFFF) / 65535
        // Most of a mountain is just rock. Ore is worth going in for.
        if roll < 0.12 { return .ironSeam }
        if roll < 0.24 { return .clayBank }
        if roll < 0.62 { return .granite }
        return .limestone
    }

    private func hash(_ seed: UInt64, _ a: Int, _ b: Int) -> UInt64 {
        var h = seed &* 0x9E37_79B9_7F4A_7C15
        h = (h ^ UInt64(bitPattern: Int64(a))) &* 0xD1B5_4A32_D192_ED03
        h = (h ^ UInt64(bitPattern: Int64(b))) &* 0xCBF2_9CE4_8422_2325
        return h ^ (h >> 29)
    }
}
