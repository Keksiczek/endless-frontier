import Foundation

/// **What stands between a shooter and what they are shooting at.**
///
/// Keks, on why the footprints matter: *"chci ty budovy mít opravdu unikátní
/// proto, co jsou — mít třeba v budoucnu turrety. Takže bude důležité, aby bylo
/// vše na svém místě, zabíralo plochy, když třeba bude krýt kulky nebo šípy ze
/// zbraní."* And on what decides it: *"věci dle výšky a toho, co to je,
/// poskytují krytí."*
///
/// So cover is **derived, not declared**. There is no `providesCover` flag on
/// forty objects to drift apart from each other; there are two properties every
/// physical thing on the map has to have anyway, and the rule is read off them:
///
/// - **`Stature`** — how high it stands, measured against a person on the
///   ground. This is the axis that decides how much of a body is behind it.
/// - **`Substance`** — what it is made of, as far as a shaft is concerned. A
///   hedge and a palisade are the same height and are not the same wall.
///
/// Multiplied, they give the three cases that prove the model is right rather
/// than convenient:
///
/// - a **bush** stops the eye and not the arrow (knee-high foliage, ≈ 0.08)
/// - a **boulder** stops both (waist-high stone, 0.5)
/// - a **ravine** stops neither, because nothing *rises* from it — you shoot
///   straight over it, and it is the case that proves the axis is height and
///   not "is it solid" (`LandformKind.ravine.blocksMovement` is true, and its
///   cover is nothing at all)
///
/// **Cover and movement are separate questions**, and `LandformKind` already
/// said so with "you walk the streets, not the walls". A low ruin wall is
/// passable *and* covering. Collapsing the two axes gets both wrong.
///
/// Note what is deliberately **not** used: `BuildingDefinition.floors`. It
/// measures upward, is read only by `HouseholdEngine`, and is never drawn — the
/// canvas is top-down and you see the ground floor. Cover is decided at the
/// height of a person standing on the ground, so a one-storey wall and a
/// five-storey block stop an arrow identically. Every building is simply total.
public enum Cover {

    /// How high a thing stands, against a person on the ground.
    ///
    /// This is the field the small things never had — `Landform`, `SceneryProp`,
    /// the rocks and the piles all carried no height at all, which is exactly
    /// where the interesting values live, because everything a *building* does
    /// is "total".
    public enum Stature: String, Codable, Sendable, CaseIterable, Comparable {
        /// Moss, flowers, a puddle. Nothing rises from this tile — and a ravine
        /// belongs here too, being ground that goes the other way.
        case underfoot
        /// A stump, a low wall, a bush, a heap of timber.
        case knee
        /// A boulder, brambles, reeds, a cairn.
        case waist
        /// A standing stone, a cactus, a palisade.
        case chest
        /// A tree, a crag, a mesa, anything with a roof on it.
        case overhead

        /// The share of a standing body this height hides.
        ///
        /// Not linear, and not the height itself: crouching behind knee-high
        /// cover hides more of you than a quarter, and chest-high cover leaves
        /// only a head. What a shot has to get past is a *body*, not a metre.
        public var bodyHidden: Double {
            switch self {
            case .underfoot: return 0
            case .knee: return 0.3
            case .waist: return 0.55
            case .chest: return 0.75
            case .overhead: return 1
            }
        }

        private var rank: Int {
            switch self {
            case .underfoot: return 0
            case .knee: return 1
            case .waist: return 2
            case .chest: return 3
            case .overhead: return 4
            }
        }

        public static func < (a: Stature, b: Stature) -> Bool { a.rank < b.rank }
    }

    /// What a thing is made of, as far as something flying at it is concerned.
    public enum Substance: String, Codable, Sendable, CaseIterable {
        /// Water, ice, open ground. There is nothing here to stop.
        case air
        /// Leaves, stems, thorns, snow. Stops the eye and not the shaft — which
        /// is the whole reason this axis exists separately from height.
        case foliage
        /// A trunk, a log, a palisade, a plank wall.
        case wood
        /// Rock, masonry, a boulder, a massif.
        case stone

        /// The share of what is hidden that this actually stops.
        public var stops: Double {
            switch self {
            case .air: return 0
            case .foliage: return 0.25
            case .wood: return 0.75
            case .stone: return 1
            }
        }
    }

    /// How much of a shot this thing takes, `0…1`.
    ///
    /// One multiplication, and it is the whole model: how much of you is behind
    /// it, times how much of that it can actually stop.
    public static func fraction(_ stature: Stature, _ substance: Substance) -> Double {
        stature.bodyHidden * substance.stops
    }

    /// Everything on the map that is worth putting between yourself and an
    /// arrow, as the pair that decides it.
    public typealias Body = (stature: Stature, substance: Substance)

    /// A building whose content says nothing about what it is made of: a roof
    /// over your head, of timber, which is what a frontier shack is.
    ///
    /// The fallback, never the answer — see `body(of:registry:)`. It exists so
    /// a definition that names no materials still stands in the way of an
    /// arrow, not so anything can skip asking.
    public static let building: Body = (.overhead, .wood)
    /// A face of the massif, and the loose rock at its foot.
    public static let massif: Body = (.overhead, .stone)

    /// What a **building** is, as a thing standing in the way of a shot.
    ///
    /// Derived from the same two facts as everything else, and both of them are
    /// already in the data:
    ///
    /// - **how high** — a wall is something you stand *behind*, chest-high and
    ///   roofless; everything else has a roof on it and is total. This is the
    ///   only case where `look` decides anything mechanical, and it does so
    ///   because "wall" is the one archetype that describes a *shape* rather
    ///   than a trade.
    /// - **what of** — whatever the thing was actually built out of, taken from
    ///   `materialCost`: a palisade of six timber bundles is wood and stone
    ///   walls of eight bricks are stone. A shaft knows the difference and the
    ///   player already reads it off the building.
    ///
    /// Before this every one of the forty-nine buildings was `(.overhead,
    /// .stone)` — a granary of green timber stopped an arrow exactly as well as
    /// mortared ramparts, which is the sort of thing that makes the whole
    /// footprint layer decorative.
    public static func body(of definition: BuildingDefinition,
                            registry: GameDataRegistry) -> Body {
        (definition.look == "wall" ? .chest : .overhead, substance(of: definition, registry: registry))
    }

    /// What a building is mostly made of. The commonest material by count wins,
    /// because a watchtower of three bundles and two bricks is a timber tower
    /// with a brick footing and not a keep.
    public static func substance(of definition: BuildingDefinition,
                                 registry: GameDataRegistry) -> Substance {
        var best: Substance?
        var most = 0
        // Sorted, because two materials in equal quantity must not resolve by
        // dictionary order — that is rule 2 in the quietest place there is.
        for (itemID, count) in definition.materialCost.sorted(by: { $0.key < $1.key }) {
            guard count > 0, count > most,
                  let substance = registry.item(itemID)?.substance else { continue }
            best = substance
            most = count
        }
        return best ?? building.substance
    }
}

// MARK: - What each thing on the map is

public extension SceneryKind {
    /// How high this stands and what it is made of — the two facts cover is
    /// read off (`Cover`).
    ///
    /// Worth having for the drawing regardless of shooting: a renderer that
    /// knows a thing is chest-high stone can size and shade it honestly instead
    /// of by a species table.
    var body: Cover.Body {
        switch self {
        // Grown things. Foliage stops the eye and not the shaft, which is why
        // a wood is somewhere to hide and not somewhere to be safe.
        case .tree, .pine, .deadTree:  return (.overhead, .wood)
        case .cactus:                  return (.chest, .foliage)
        case .brambles, .reeds:        return (.waist, .foliage)
        case .tallGrass:               return (.waist, .foliage)
        case .bush:                    return (.knee, .foliage)
        case .stump, .fallenLog:       return (.knee, .wood)
        case .driftwood:               return (.knee, .wood)
        case .flowers, .mushroom:      return (.underfoot, .foliage)
        // Stone, in every size it comes in.
        case .cliff, .crag, .ruinPillar, .standingStone:
            return self == .standingStone ? (.chest, .stone) : (.overhead, .stone)
        case .boulder, .cairn:         return (.waist, .stone)
        case .rock:                    return (.knee, .stone)
        // Ground that happens to be piled up, and ground that is wet. A dune is
        // shoulder-high sand and stops an arrow about as well as a hedge does;
        // a snowdrift is worse.
        case .dune:                    return (.chest, .foliage)
        case .snowdrift, .anthill:     return (.knee, .foliage)
        case .pond, .hotSpring, .iceFloe: return (.underfoot, .air)
        }
    }
}

public extension LandformKind {
    /// Cover and movement are **different questions**, and this type is where
    /// that shows: a ruin field is passable and covering, a ravine is
    /// impassable and covering nothing at all. See `Cover`.
    var body: Cover.Body {
        switch self {
        // Low roofless walls of something that stood here first — you walk the
        // streets and you shelter behind the stonework.
        case .ruinField: return (.chest, .stone)
        // A block of rock standing out of flat country: a wall at your back,
        // which is what its own note already says.
        case .mesa: return (.overhead, .stone)
        // Water and palms in dry country.
        case .oasis: return (.knee, .foliage)
        // **The case that proves the axis is height.** Both of these are ground
        // going the *other* way — a cut and a bowl. A ravine stops a walker
        // dead and stops an arrow not at all, because nothing rises from it and
        // you shoot straight over the top.
        case .ravine, .hollow: return (.underfoot, .air)
        }
    }
}

public extension TreeSpecies {
    /// A juniper is scrub; everything else in the wood is a trunk.
    var body: Cover.Body {
        self == .juniper ? (.waist, .foliage) : (.overhead, .wood)
    }
}
