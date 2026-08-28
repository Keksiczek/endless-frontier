import SwiftUI
import EndlessFrontierCore

/// **The buildings, drawn** — the roof, the ground it stands on, the shadow it
/// casts and the goods stacked beside it.
extension SettlementRenderer {
    /// **What is standing on this building's floor.**
    ///
    /// A store is drawn from the colony's own books: the resource this
    /// definition holds the most room for, as a share of the colony's roof
    /// over that resource. A granary in a colony sitting on four thousand
    /// sacks is packed to the walls; the same granary the winter after is
    /// swept. Nothing here writes anything.
    static func stock(
        of definitionID: String, in settlement: Settlement, registry: GameDataRegistry
    ) -> (fullness: Double, fitting: SettlementInterior.Fitting)? {
        guard let def = registry.building(definitionID) else { return nil }
        // What this building is for, rather than what it happens to hold a
        // little of: the resource it makes the most room for.
        var kept: (resource: ResourceType, room: Double)?
        for resource in ResourceType.allCases where def.storage[resource] > 0 {
            if kept == nil || def.storage[resource] > kept!.room {
                kept = (resource, def.storage[resource])
            }
        }
        guard let kept else { return nil }
        let roof = settlement.storageCapacity[kept.resource]
        guard roof > 0 else { return nil }
        let fullness = min(1, max(0, settlement.storage[kept.resource] / roof))
        let fitting: SettlementInterior.Fitting
        switch kept.resource {
        case .food: fitting = .sack
        case .materials: fitting = .crate
        default: fitting = .barrel
        }
        return (fullness, fitting)
    }

    /// **What a store is actually holding**, in the order it holds most of.
    ///
    /// The colony's `stockpile` is concrete goods; `storage` is the abstract
    /// ledger. A warehouse draws the first, because that is what a person
    /// walking into it would see.
    static func goods(
        of definitionID: String, in settlement: Settlement, registry: GameDataRegistry
    ) -> [(kind: SettlementInterior.Goods, count: Int)] {
        guard let def = registry.building(definitionID),
              !def.storage.amounts.filter({ $0.value > 0 }).isEmpty,
              !settlement.stockpile.isEmpty else { return [] }
        var byKind: [SettlementInterior.Goods: Int] = [:]
        for (itemID, count) in settlement.stockpile where count > 0 {
            byKind[SettlementInterior.Goods.of(itemID), default: 0] += count
        }
        // Sorted by how much of it there is, ties on the kind's own name so a
        // store does not reshuffle its floor between frames.
        return byKind.sorted {
            $0.value == $1.value ? $0.key.rawValue < $1.key.rawValue : $0.value > $1.value
        }.map { (kind: $0.key, count: heapHeight($0.value)) }
    }

    /// How high a heap of `count` goods stands, 1…3. A store is not a bar
    /// chart: past a wagonload more of the same thing looks the same.
    static func heapHeight(_ count: Int) -> Int {
        switch count {
        case ..<20: return 1
        case ..<120: return 2
        default: return 3
        }
    }

    static func buildings(
        _ context: inout GraphicsContext, placed: [PlacedBuilding],
        time: Double, night: Double = 0, showLabels: Bool = false,
        zoom: CGFloat = 1, sun: SettlementLight.Sun = SettlementLight.sun(time: 0),
        selectedBuildingID: Int?,
        /// **The wood, drawn in the same pass as the town.** A tree standing in
        /// front of a house has to be drawn after it and one behind it before,
        /// and no amount of ordering two whole passes can do both — the wood
        /// was a block drawn before the buildings, so every tree in the town
        /// was behind every roof in it (`RENDER_25D.md` §3). Empty draws the
        /// town alone, which is what the tests and the thumbnail want.
        trees: [Tree] = [], rect: CGRect = .zero, season: Season = .summer,
        /// The book the rooms are furnished out of (`FittingDefinition`), and
        /// the age they are furnished for.
        registry: GameDataRegistry,
        era: Era
    ) {
        // Foundations first — every building's plot, drawn before any structure,
        // so a later lot never paints over an earlier roof and adjacent lots
        // knit into one cleared, built-up ground the town sits on.
        for building in placed {
            floorPlot(&context, at: building.center, footprint: building.footprint,
                      underConstruction: building.underConstruction, seed: building.seed,
                      // **A farm's ground is its field.** Cleared earth was
                      // laid over the whole lot and the plots drawn on top of
                      // it, so the one building that is mostly *ground under
                      // crop* read as a yard with some green in it. Only the
                      // top row — the yard the shed stands in — is swept.
                      yardOnly: building.glyph == .farm)
        }
        // Then what the town throws across its own ground. Every shadow in one
        // path, filled once: a shadow must never fall on the *building* next
        // door, only on the earth between them.
        castShadows(&context, placed: placed, sun: sun)
        // Then the insides: floor, fittings, walls. Drawn under the roofs, so
        // pushing the camera in lifts the roof off a room that is already there
        // rather than swapping one drawing for another.
        let roof = SettlementInterior.roofFade(zoom: zoom)
        if roof < 0.999 {
            for building in placed where !building.underConstruction {
                SettlementInterior.draw(
                    &context, glyph: building.glyph, at: building.center,
                    footprint: building.footprint, size: building.size,
                    seed: building.seed, era: era,
                    workers: building.workers, residents: building.residents,
                    night: night, time: time, stock: building.stock,
                    goods: building.goods, variant: building.variant,
                    building: building.definitionID, registry: registry)
            }
        }
        // **One sorted pass, on the foot.** Depth is where a thing *stands*, not
        // which array it came out of: a building's foot is the bottom of its
        // lot, a tree's is the point it grows at.
        enum Standing {
            case built(PlacedBuilding)
            case tree(Tree)
        }
        let standing: [(foot: CGFloat, thing: Standing)] =
            placed.map { (foot: $0.center.y + $0.footprint.height / 2, thing: .built($0)) }
            + trees.map { (foot: SettlementRenderer.point($0.position, in: rect).y,
                           thing: .tree($0)) }

        for entry in standing.sorted(by: { $0.foot < $1.foot }) {
            guard case .built(let building) = entry.thing else {
                if case .tree(let tree) = entry.thing {
                    SettlementFlora.draw(&context, tree: tree, rect: rect,
                                         season: season, time: time, registry: registry)
                }
                continue
            }
            if building.underConstruction {
                SettlementStructures.site(at: building.center, s: building.size,
                                          progress: building.progress, time: time, context: &context)
            } else if roof > 0.001 {
                // The roof, as solid as the distance warrants.
                var roofContext = context
                roofContext.opacity = roof
                SettlementStructures.building(building.glyph, at: building.center,
                                              s: building.size, time: time, night: night,
                                              seed: building.seed, era: building.era,
                                              footprint: building.footprint,
                                              fabric: building.fabric, floors: building.floors,
                                              variant: building.variant,
                                              context: &roofContext)
            }
            // What time and trouble have done to it, over whatever is drawn —
            // a ruin has to read as one whether its roof is on or off.
            if !building.underConstruction, building.condition < 0.92 {
                SettlementStructures.wear(&context, at: building.center,
                                          footprint: building.footprint,
                                          condition: building.condition, seed: building.seed)
            }
            if building.id == selectedBuildingID {
                let r = building.size * 2.6
                context.stroke(
                    Path(ellipseIn: CGRect(x: building.center.x - r, y: building.center.y - r,
                                           width: r * 2, height: r * 2)),
                    with: .color(Theme.accent), lineWidth: 1.5)
            }
            if showLabels {
                let caption = building.underConstruction
                    ? "\(Int(building.progress * 100)) %"
                    : building.name
                let label = Text(caption)
                    .font(.system(size: 5.5, weight: .medium))
                    .foregroundStyle(Theme.bone.opacity(0.75))
                context.draw(context.resolve(label),
                             at: CGPoint(x: building.center.x,
                                         y: building.center.y + building.size * 2.5))
            }
        }
    }

    /// How tall a structure stands, as a multiple of its glyph size — what
    /// decides how far it throws a shadow. A tower reaches across the square at
    /// evening; a field of panels barely lifts off the ground.
    static func height(of glyph: BuildingGlyph) -> CGFloat {
        switch glyph {
        case .tower:     return 3.4
        case .temple:    return 2.8
        case .plant:     return 2.6
        case .hall:      return 2.2
        case .mill:      return 2.2
        case .pad:       return 2.4
        case .granary:   return 1.9
        case .cookhouse: return 1.6
        case .house:     return 1.7
        case .market:    return 1.6
        case .workshop:  return 1.5
        case .generator: return 1.4
        case .mine:      return 1.2
        case .array:     return 0.6
        // The trades.
        case .tenement:  return 3.6
        case .turbine:   return 3.4
        case .dish:      return 2.6
        case .tanks:     return 2.4
        case .forge:     return 2.2
        case .vault:     return 2.0
        case .rail:      return 1.9
        case .dam:       return 1.8
        case .aqueduct:  return 1.8
        case .lab:       return 1.7
        case .clinic:    return 1.6
        case .barracks:  return 1.5
        case .lodge:     return 1.6
        case .sawmill:   return 1.3
        case .wall:      return 1.2
        case .well:      return 0.9
        case .farm:      return 1.1
        }
    }

    /// Everything the town throws on the ground, as one silhouette.
    static func castShadows(
        _ context: inout GraphicsContext, placed: [PlacedBuilding],
        sun: SettlementLight.Sun
    ) {
        guard sun.strength > 0.01 else { return }
        var shadows = Path()
        for building in placed where !building.underConstruction {
            let tall = building.size * height(of: building.glyph)
            // A shadow starts at the foot of the wall, not at the roof line.
            let foot = CGPoint(x: building.center.x, y: building.center.y + building.size * 0.3)
            let base = CGSize(width: max(4, building.footprint.width * 0.78),
                              height: max(3, building.footprint.height * 0.52))
            shadows.addPath(SettlementLight.boxShadow(
                at: foot, footprint: base, height: tall, sun: sun))
        }
        guard !shadows.isEmpty else { return }
        context.fill(shadows, with: .color(SettlementLight.shadowColour(sun)))
    }

    /// The plot a structure stands on — cleared, framed ground the size of the
    /// building's footprint. This is the foundation of the multi-tile world:
    /// a 2×2 building owns a 2×2 lot, adjacent lots merge into built-up land,
    /// and a construction site reserves its ground with a dashed outline. Read
    /// only from the layout; nothing here touches the simulation.
    static func floorPlot(
        _ context: inout GraphicsContext, at c: CGPoint, footprint: CGSize,
        underConstruction: Bool, seed: UInt64 = 0, yardOnly: Bool = false
    ) {
        guard footprint.width > 2, footprint.height > 2 else { return }
        // **The ground a building has worn round itself.**
        //
        // Keks: *"budovy jen levitují nad zemí a pod nimi vše normálně roste."*
        // The lot itself was there — packed earth, opaque, the size of the
        // footprint — and it stopped dead at the wall, with wild grass running
        // up to a hard rounded rectangle. A building on a rectangle of dirt on
        // a field is a sticker, not a place: what a house actually has round it
        // is a scuffed apron where the ground has been walked bare, fading into
        // the grass rather than ending at a line.
        //
        // Opaque, and ragged, and both for the same reason. Opaque because the
        // ground tiles overlap by a hair and any translucent fill over them
        // blends the overlap twice and rules a bright grid across every yard
        // in the town (rule 9). Ragged because a straight edge is what made it
        // read as pasted on.
        apron(&context, at: c, footprint: footprint, seed: seed)
        // A hair of margin so neighbouring lots still read as separate parcels.
        let w = footprint.width * 0.92
        // A farm keeps only the strip its shed stands on; the rest of the lot
        // is `FarmEngine`'s plots, drawn as broken earth by `SettlementCrops`.
        let h = footprint.height * (yardOnly ? 0.34 : 0.92)
        let top = yardOnly ? c.y - footprint.height / 2 + h / 2 : c.y - h / 2
        let rect = CGRect(x: c.x - w / 2, y: top, width: w, height: h)
        let radius = min(w, h) * 0.16
        let shape = Path(roundedRect: rect, cornerRadius: radius)
        if underConstruction {
            context.fill(shape, with: .color(Theme.bone.opacity(0.05)))
            context.stroke(shape, with: .color(Theme.boneFaint.opacity(0.65)),
                           style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
        } else {
            // Packed, cleared earth — warmer and a touch darker than the wild
            // grass, so the built ground reads as a place people made.
            //
            // Opaque, and rule 9 is why: ground tiles overlap by a hair so no
            // seam shows, and a *translucent* lot laid over them blends that
            // overlap twice and rules a bright grid inside every yard in the
            // town. At 0.6 alpha over dark grass it also came out as a near
            // black slab — the thing that read as a hole in the map.
            context.fill(shape, with: .color(Color(red: 0.27, green: 0.23, blue: 0.18)))
            context.stroke(shape, with: .color(Theme.boneFaint.opacity(0.4)), lineWidth: 0.8)
            // And the ground darkening where the wall meets it. Over the earth
            // rather than over the world, so rule 9 is untouched: this is a
            // shadow on a lot, not a wash on the map.
            let footing = CGRect(x: rect.minX, y: rect.maxY - max(1.2, rect.height * 0.10),
                                 width: rect.width, height: max(1.2, rect.height * 0.10))
            context.fill(Path(roundedRect: footing, cornerRadius: radius * 0.5),
                         with: .color(Color(red: 0.17, green: 0.14, blue: 0.11)))
        }
    }

    /// The scuffed ground round a lot: wider than the building, ragged at the
    /// edge, half way in colour between the packed yard and the country it is
    /// standing in. See `floorPlot`.
    static func apron(
        _ context: inout GraphicsContext, at c: CGPoint, footprint: CGSize, seed: UInt64
    ) {
        let w = footprint.width * 1.16, h = footprint.height * 1.16
        guard w > 3, h > 3 else { return }
        // Eight points round the lot, each pushed out by a little, so no two
        // buildings wear their ground the same way. Fixed per building: an
        // apron that changed shape between frames would shimmer.
        var path = Path()
        let steps = 10
        for i in 0..<steps {
            let angle = Double(i) / Double(steps) * 2 * .pi
            var hash = (seed &+ UInt64(i) &* 0x9E37_79B9_7F4A_7C15) &* 0xBF58_476D_1CE4_E5B9
            hash ^= hash >> 31
            let wobble = 0.88 + Double(hash >> 40) / Double(1 << 24) * 0.24
            let p = CGPoint(x: c.x + CGFloat(cos(angle) * wobble) * w / 2,
                            y: c.y + CGFloat(sin(angle) * wobble) * h / 2)
            if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
        }
        path.closeSubpath()
        context.fill(path, with: .color(Color(red: 0.33, green: 0.30, blue: 0.22)))
    }

    // MARK: - Colonists

}
