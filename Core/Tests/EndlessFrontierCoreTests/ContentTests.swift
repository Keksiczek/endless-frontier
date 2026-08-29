import Foundation
import Testing
@testable import EndlessFrontierCore

@Suite("Content integrity")
struct ContentIntegrityTests {
    private func registry() throws -> GameDataRegistry { try GameDataRegistry.bundled() }

    @Test("Every tech prerequisite references an existing tech")
    func techPrereqsExist() throws {
        let reg = try registry()
        for tech in reg.techs.values {
            for required in tech.requires {
                #expect(reg.tech(required) != nil, "Tech \(tech.id) requires missing \(required)")
            }
        }
    }

    @Test("Every building a tech unlocks exists")
    func techUnlocksExist() throws {
        let reg = try registry()
        for tech in reg.techs.values {
            for effect in tech.effects {
                if case let .unlockBuilding(buildingID) = effect {
                    #expect(reg.building(buildingID) != nil, "Tech \(tech.id) unlocks missing \(buildingID)")
                }
            }
        }
    }

    @Test("Every era-milestone tech exists")
    func eraMilestoneTechsExist() throws {
        let reg = try registry()
        for era in Era.allCases {
            guard let def = reg.eraDefinition(era) else { continue }
            for milestone in def.milestones {
                if case let .techResearched(id) = milestone {
                    #expect(reg.tech(id) != nil, "Era \(era.rawValue) needs missing tech \(id)")
                }
            }
        }
    }

    @Test("Every unlockable building is reachable from some tech (or is early-era)")
    func buildingsReachable() throws {
        let reg = try registry()
        var unlockable: Set<String> = []
        for tech in reg.techs.values {
            for effect in tech.effects {
                if case let .unlockBuilding(id) = effect { unlockable.insert(id) }
            }
        }
        for building in reg.buildings.values where building.era != .earlySettlement {
            #expect(unlockable.contains(building.id), "Building \(building.id) is unreachable (no tech unlocks it)")
        }
    }

    /// Every event has to happen **to somebody or somewhere**.
    ///
    /// Thirty-four of seventy-two did neither: a drought, a wildfire, a bandit
    /// raid and a golden age were all a number moving in a struct, and the
    /// colony you were watching went on exactly as before. Every hook to land
    /// them existed — `pawn_health`, `pawn_mood`, `damage_buildings` — and none
    /// of them were used. This is the guard so a new event cannot be written
    /// that way again.
    @Test("Every event lands on a person or on the place")
    func eventsHappenToSomebody() throws {
        let reg = try registry()
        func lands(_ effect: EventEffect) -> Bool {
            switch effect {
            case .pawnHealthDelta, .pawnMoodDelta, .addPawn, .removePawn,
                 .damageBuildings, .raid, .regionHazardDelta, .regionKindChange:
                return true
            default:
                return false
            }
        }
        let faceless = reg.events
            .filter { template in
                !template.effects.contains(where: lands)
                    && !template.choices.contains { $0.effects.contains(where: lands) }
            }
            .map { $0.id }
            .sorted()
        #expect(faceless.isEmpty,
                "these happen to nobody and nowhere: \(faceless.joined(separator: ", "))")
    }

    /// Content Claude touches ships in both languages in the same change. The
    /// forty-eight `narrative_hint`s that were plain strings decoded into a
    /// `LocalizedText` with one value in it, so a Czech player read the whole
    /// storyteller in English and nothing anywhere said so.
    @Test("Every event narrates in Czech as well as English")
    func eventsAreBilingual() throws {
        let reg = try registry()
        let english: [String] = reg.events
            .filter { (template: EventTemplate) -> Bool in
                template.narrativeHint.resolve(GameLanguage.cs)
                    == template.narrativeHint.resolve(GameLanguage.en)
            }
            .map { $0.id }
            .sorted()
        #expect(english.isEmpty,
                "these narrate in English to a Czech player: \(english.joined(separator: ", "))")
    }

    /// …and so does everything else the player reads.
    ///
    /// The event guard above covers one file. Buildings and techs were English
    /// -only for a long time, got translated, and `CLAUDE.md` went on saying
    /// they had not been — which is the failure mode a note cannot fix: prose
    /// about content drifts, a test walking the content does not.
    ///
    /// Deliberately over the **raw JSON** rather than over the decoded registry:
    /// a `LocalizedText` field nobody modelled in Swift yet is exactly where a
    /// half-translated entry hides.
    @Test("Every line of content reads in Czech as well as English")
    func allContentIsBilingual() throws {
        // Every JSON in `GameData`, enumerated rather than listed: a hardcoded
        // list stops covering the file somebody adds next week, which is the
        // same drift this test exists to stop.
        let files = Bundle.module.urls(forResourcesWithExtension: "json",
                                       subdirectory: "GameData") ?? []
        #expect(files.count >= 10, "only \(files.count) data files found — is the bundle right?")
        var english: [String] = []
        for url in files {
            let root = try JSONSerialization.jsonObject(with: Data(contentsOf: url))
            walk(root, path: url.deletingPathExtension().lastPathComponent, into: &english)
        }
        #expect(english.isEmpty,
                "these read in English to a Czech player: \(english.sorted().joined(separator: ", "))")
    }

    /// Every `{"en": …}` in the tree, and whether it has a Czech twin.
    private func walk(_ node: Any, path: String, into out: inout [String]) {
        if let object = node as? [String: Any] {
            if let en = object["en"] as? String, !en.isEmpty {
                let cs = object["cs"] as? String
                if cs == nil || cs?.isEmpty == true { out.append(path) }
                return
            }
            // `id` names the entry, so a failure says *which* one rather than
            // handing back an array index nobody can look up.
            let name = (object["id"] as? String).map { "\(path)/\($0)" } ?? path
            for (key, value) in object { walk(value, path: "\(name).\(key)", into: &out) }
        } else if let array = node as? [Any] {
            for item in array { walk(item, path: path, into: &out) }
        }
    }

    @Test("Content library has grown across eras")
    func contentVolume() throws {
        let reg = try registry()
        #expect(reg.buildings.count >= 20)
        #expect(reg.techs.count >= 14)
        #expect(reg.events.count >= 18)
        // Spans multiple eras.
        let eras = Set(reg.buildings.values.map(\.era))
        #expect(eras.contains(.medieval))
        #expect(eras.contains(.earlyIndustrial))
    }

    /// **Everything a colonist can be handed goes into a slot.**
    ///
    /// `GameEngine.equipItem` requires `slot == .equipment` *and* a non-nil
    /// `equipSlot`, and returns the world unchanged when either is missing.
    /// `ItemsPanel` switches on `slot` alone and offers an Equip menu for
    /// anything marked equipment. **Seventy-three items had the first and not
    /// the second**, so the player picked a colonist and nothing happened — no
    /// error, no message, the item still on the shelf.
    ///
    /// They were not obscure: eighty-nine recipes made them, a fifth of the
    /// whole book, and because `ItemEngine.equippedEffects` only reads what is
    /// *worn*, every skill bonus, mood bonus and health regen on all
    /// seventy-three was dead the entire time.
    @Test("Every item a colonist can be handed has somewhere to put it")
    func everyEquipmentHasASlot() throws {
        let reg = try registry()
        let homeless = reg.items.values
            .filter { $0.slot == .equipment && $0.equipSlot == nil }
            .map(\.id).sorted()
        #expect(homeless.isEmpty,
                "these say they are equipment and name no slot, so equipping them silently does nothing: \(homeless)")
    }

    /// **Everything a recipe needs can be got, and not only by digging it up.**
    ///
    /// `SiteEngine.lootPool` hands back every material *no recipe makes and no
    /// ground gives* — so an item with no source is not unreachable, it is
    /// **treasure**, and the game looks correct from every angle except the
    /// bench. Measured: 104 of 411 recipes needed at least one input that only
    /// an expedition could ever supply. `strong_plant_fibers` alone gated
    /// **fifty** of them — "bundles of tough, dried plant fibers… essential for
    /// many early crafts" — so weaving a fishing net waited on excavating a
    /// barrow, and `WoodProbe` duly showed `Weave Fiber Rope` on a standing
    /// order having made **zero** in two centuries.
    ///
    /// Three are treasure on purpose and their own names say so. Everything
    /// else must be makeable out of what the valley gives. The list is the
    /// design statement: add a fourth and this test will name it.
    @Test("Every material a recipe needs can be got without digging up a barrow")
    func noEverydayMaterialIsTreasureOnly() throws {
        let reg = try registry()
        var made: Set<String> = []
        for recipe in reg.recipes.values { made.insert(recipe.outputItemID) }

        var gathered: Set<String> = ["meat", "berries", "greens", "roots", "grain"]
        gathered.insert(ResourceLoop.hideItemID)
        for kind in LocalResourceKind.allCases {
            if let id = kind.rawMaterialID { gathered.insert(id) }
        }
        // A cache on the colony's *own* local map is a source, not treasure:
        // `star_iron` sits in a starfall crater somebody can walk to. This
        // clause is the one the first cut of this test missed, and the test
        // itself is what found it.
        for kind in LocalPOIKind.allCases {
            if let id = kind.cacheItemID { gathered.insert(id) }
        }
        // Found, never made — and meant to be. Their own names say so.
        let treasures: Set<String> = ["ancient_alloy", "crater_glass", "spirit_essence"]

        var blocked: [String: Int] = [:]
        for recipe in reg.recipes.values {
            for material in recipe.materials.keys {
                if made.contains(material) { continue }
                if gathered.contains(material) { continue }
                if treasures.contains(material) { continue }
                blocked[material, default: 0] += 1
            }
        }
        let named = blocked.sorted { $0.value > $1.value }
            .map { "\($0.key) x\($0.value)" }
            .joined(separator: ", ")
        #expect(blocked.isEmpty,
                "needed by recipes, obtainable only as loot: \(named)")
    }

    /// …and nothing the colony can make produces one of them.
    ///
    /// The slot check above is about the item; this is about the *cost*. A
    /// recipe whose output cannot be used is materials and worker-ticks spent
    /// on nothing, and the bench will happily take the order.
    @Test("No recipe makes a thing that cannot be used")
    func noRecipeMakesADeadThing() throws {
        let reg = try registry()
        let wasted = reg.recipes.values.compactMap { recipe -> String? in
            guard let item = reg.item(recipe.outputItemID) else { return recipe.id }
            guard item.slot == .equipment, item.equipSlot == nil else { return nil }
            return recipe.id
        }.sorted()
        #expect(wasted.isEmpty,
                "these recipes cost materials and produce something nobody can equip: \(wasted)")
    }

    // MARK: - When a recipe arrives

    /// The age a recipe can first be worked in: the later of what its bench and
    /// its study need, and of everything it consumes.
    ///
    /// Written here rather than in the Core because it is a question only the
    /// content asks — the engine's own gate is `CraftingEngine.canCraft`, which
    /// asks about *this* colony rather than about the ladder.
    private func reachableEra(_ recipe: RecipeDefinition, _ reg: GameDataRegistry,
                              _ cache: inout [String: Int], _ seen: Set<String> = []) -> Int {
        var era = 0
        if let id = recipe.requiresBuilding, let b = reg.building(id) {
            era = max(era, b.era.index)
        }
        if let id = recipe.requiresTech, let t = reg.tech(id) {
            era = max(era, t.era.index)
        }
        for material in recipe.materials.keys.sorted() {
            era = max(era, itemEra(material, reg, &cache, seen))
        }
        return era
    }

    /// The earliest age the colony can hold this thing at all: raw and gathered
    /// stuff is there from the first day, and anything made comes with the
    /// cheapest way of making it.
    private func itemEra(_ id: String, _ reg: GameDataRegistry,
                         _ cache: inout [String: Int], _ seen: Set<String> = []) -> Int {
        if let known = cache[id] { return known }
        if seen.contains(id) { return 0 }
        let routes = reg.recipes.values.filter { $0.outputItemID == id }
        guard !routes.isEmpty else { cache[id] = 0; return 0 }
        var best = Int.max
        for route in routes {
            best = min(best, reachableEra(route, reg, &cache, seen.union([id])))
        }
        let era = best == Int.max ? 0 : best
        cache[id] = era
        return era
    }

    /// **Rule 6 in the recipe book.** A material gated behind an age its
    /// consumer does not wait for is a recipe nobody can ever work: the bench
    /// takes the order, the standing order sits there, and nothing is made —
    /// which is exactly how `strong_plant_fibers` gated fifty recipes without
    /// erroring (§18).
    ///
    /// Stated as an invariant rather than a list, so the next content pass
    /// cannot re-introduce it by hand or by generator.
    @Test("Nothing is gated later than something that needs it")
    func nothingArrivesAfterItsConsumer() throws {
        let reg = try registry()
        var cache: [String: Int] = [:]
        var stranded: [String] = []
        for recipe in reg.recipes.values.sorted(by: { $0.id < $1.id }) {
            let mine = reachableEra(recipe, reg, &cache)
            for material in recipe.materials.keys.sorted() {
                let theirs = itemEra(material, reg, &cache)
                if theirs > mine {
                    stranded.append("\(recipe.id) wants \(material) an age later than itself")
                }
            }
        }
        #expect(stranded.isEmpty, "\(stranded.prefix(8).joined(separator: "; "))")
    }

    // MARK: - What a building looks like

    /// **Every building has a composition, and every composition has a
    /// building.**
    ///
    /// Measured 2026-08-27: 62 buildings share 30 `look` values and 51 of them
    /// share theirs with something else, while `StructureVariant`'s derived
    /// axes separate all 62 with no collisions at all. So the buildings looking
    /// alike was never a data problem — the drawing did not spend the
    /// difference it was handed (rule 107). `structures.json` is where the
    /// difference goes, and this is the pair of holes it can fall through: a
    /// building nobody wrote a composition for is drawn as a plain shed for
    /// ever, and a composition for a building that does not exist is a drawing
    /// nothing will ever ask for (rule 47).
    @Test("Every building says how it is put together")
    func everyBuildingHasAComposition() throws {
        let reg = try registry()
        let buildings = Set(reg.buildings.keys)
        let described = Set(reg.structures.keys)
        let bare = buildings.subtracting(described).sorted()
        let orphans = described.subtracting(buildings).sorted()
        let plain = bare.prefix(8).joined(separator: ", ")
        let stray = orphans.prefix(8).joined(separator: ", ")
        #expect(bare.isEmpty, "\(bare.count) buildings are drawn as a plain shed: \(plain)")
        #expect(orphans.isEmpty, "\(orphans.count) compositions name no building: \(stray)")
    }

    /// The closed sets, stated once. A word the renderer does not know draws
    /// nothing at all — the quiet failure `texture` in `ground.json` had for
    /// weeks — so an invented `roof` or `fabric` is a building that silently
    /// loses a wall rather than a build error.
    @Test("A composition uses only the parts the renderer knows")
    func compositionsSpeakTheVocabulary() throws {
        let reg = try registry()
        let roofs: Set = ["gable", "sawtooth", "flat", "barrel", "stepped"]
        let fabrics: Set = ["open", "thatch", "daub", "timber", "stone",
                            "brick", "panel", "glass", "sheet"]
        let trims: Set = ["none", "timber", "stone", "brick", "panel", "sheet"]
        let rooftops: Set = ["none", "vents", "array", "aerial", "tank"]
        let yards: Set = ["none", "beaten_earth", "gravel", "cobbles", "planking"]
        let accents: Set = ["none", "hearth", "ember", "awning", "cold_green", "lamp"]
        var strange: [String] = []
        for one in reg.structures.values.sorted(by: { $0.id < $1.id }) {
            if !roofs.contains(one.roof) { strange.append("\(one.id).roof=\(one.roof)") }
            if !fabrics.contains(one.fabric) { strange.append("\(one.id).fabric=\(one.fabric)") }
            if !trims.contains(one.trim) { strange.append("\(one.id).trim=\(one.trim)") }
            if !rooftops.contains(one.rooftop) { strange.append("\(one.id).rooftop=\(one.rooftop)") }
            if !yards.contains(one.yard) { strange.append("\(one.id).yard=\(one.yard)") }
            if !accents.contains(one.accent) { strange.append("\(one.id).accent=\(one.accent)") }
        }
        let odd = strange.prefix(10).joined(separator: ", ")
        #expect(strange.isEmpty, "\(odd)")
    }

    /// **The point of the bank, stated as a number.**
    ///
    /// A composition that gives every building the same height and the same
    /// three attachments would load, pass every check above, and leave the town
    /// exactly as indistinguishable as it was. So the guard is on the *spread*:
    /// buildings sharing a `look` must not share a silhouette.
    @Test("Buildings that share a look do not share a silhouette")
    func aSharedLookIsNotASharedBuilding() throws {
        let reg = try registry()
        var byLook: [String: [String]] = [:]
        for building in reg.buildings.values {
            guard let look = building.look else { continue }
            byLook[look, default: []].append(building.id)
        }
        var clones: [String] = []
        for (look, ids) in byLook.sorted(by: { $0.key < $1.key }) where ids.count > 1 {
            var seen: Set<String> = []
            for id in ids.sorted() {
                let one = reg.structure(id)
                // Height to a tenth, the roof, and what stands beside it. Two
                // buildings agreeing on all three are one drawing twice.
                let mark = "\(Int(one.standing * 10))/\(one.roof)/"
                    + one.attachments.sorted().joined(separator: "+")
                if !seen.insert(mark).inserted { clones.append("\(look): \(id)") }
            }
        }
        let twins = clones.prefix(8).joined(separator: ", ")
        #expect(clones.isEmpty,
                "\(clones.count) buildings are a twin of something sharing their look: \(twins)")
    }

    /// **A bench must not be the only thing a recipe is waiting for.**
    ///
    /// Measured 2026-08-27, before the fix: **101 recipes in the book were
    /// gated by nothing but a workbench from a later age than everything else
    /// they needed** — 91 of them at `workshop`, which is *medieval*, and which
    /// therefore held ninety-nine first-age crafts: bone chisels, grass hats,
    /// hide caps, stone-tipped spears. Nothing else about them was medieval.
    /// The result was an avalanche: 210 recipes makeable in the first age, and
    /// then **119 more the day the workshop went up** — more than a quarter of
    /// the whole book arriving in one afternoon.
    ///
    /// Gating cannot fix that, and §20.2 says why: by the time the workshop
    /// exists the early techs are two ages old, so putting `basic_tools` on a
    /// bone chisel changes nothing. The bench *is* the gate, so the bench has
    /// to be the one the recipe's own age has — hence `work_shelter`, and the
    /// ninety-nine that moved to it.
    ///
    /// A cap rather than zero, because a handful are honest: iron arrives at
    /// the bloomery in the first age and the things made *of* iron wait for a
    /// smithy the book does not have yet. That is a smaller avalanche of its
    /// own and wants measuring before it is moved (rule 72).
    @Test("No bench is the only thing holding a book of recipes back")
    func noBenchStrandsAnAgeOfRecipes() throws {
        let reg = try registry()
        var cache: [String: Int] = [:]
        var stranded: [String: [String]] = [:]
        for recipe in reg.recipes.values.sorted(by: { $0.id < $1.id }) {
            guard let benchID = recipe.requiresBuilding,
                  let bench = reg.building(benchID) else { continue }
            // Everything the recipe needs *except* the bench.
            var otherwise = 0
            if let id = recipe.requiresTech, let t = reg.tech(id) {
                otherwise = max(otherwise, t.era.index)
            }
            for material in recipe.materials.keys.sorted() {
                otherwise = max(otherwise, itemEra(material, reg, &cache))
            }
            guard bench.era.index > otherwise else { continue }
            stranded[benchID, default: []].append(recipe.id)
        }
        let worst = stranded.max { $0.value.count < $1.value.count }
        let names = worst?.value.prefix(6).joined(separator: ", ") ?? ""
        let bench = worst?.key ?? "—"
        let held = worst?.value.count ?? 0
        #expect(held <= 20,
                "\(bench) is the only thing \(held) recipes are waiting for: \(names)")
    }

    /// …and the same thing read from the other side: what the ladder looks like
    /// to somebody climbing it. No age after the first may hand the player a
    /// sixth of the book at once.
    @Test("No single age hands over a sixth of the book at once")
    func theBookArrivesGradually() throws {
        let reg = try registry()
        var cache: [String: Int] = [:]
        var perAge: [Int: Int] = [:]
        for recipe in reg.recipes.values {
            perAge[reachableEra(recipe, reg, &cache), default: 0] += 1
        }
        let total = reg.recipes.count
        // The first age is *meant* to be the widest — a colony has to be able
        // to make things on its first day. The spikes that read as an avalanche
        // are the later ones.
        let later = perAge.filter { $0.key > Era.earlySettlement.index }
        let worst = later.max { $0.value < $1.value }
        let age = worst?.key ?? -1
        let arriving = worst?.value ?? 0
        #expect(arriving * 6 <= total,
                "era \(age) makes \(arriving) of \(total) recipes available in one step")
    }

    /// **A second way of making a thing has to be worth taking.**
    ///
    /// A recipe is *strictly dominated* when another route to the same item
    /// arrives an age earlier and costs no more: there is no colony, at no
    /// moment of its life, that would choose it. Measured 2026-08-27 the book
    /// held nineteen; re-homing the workshop's first-age crafts fixed five of
    /// them by itself and fourteen are left, every one of the same shape — a
    /// generator writing a second, dearer recipe for something the book could
    /// already make.
    ///
    /// **They are not deleted, and that is deliberate.** The crafting panel
    /// folds to one row per thing, so the player never meets them unless they
    /// search; and a recipe id can be sitting in a standing order in somebody's
    /// save, where removing it would silently stop a bench (rule 3).
    ///
    /// **The decision, made 2026-08-29: a later route buys time.** A second way
    /// of making a thing does not have to be cheaper — it has to be *better at
    /// something*, and the thing a later age is actually better at is speed.
    /// All fourteen carry a `workTicks` well under the work the earlier route
    /// costs, so the choice is real: spend more stuff and have it today, or
    /// spend less and wait. Dominance is therefore measured on **both** axes
    /// now, and a route beaten on both is a route nobody would choose.
    @Test("A second way of making a thing is worth taking")
    func noBookOfRoutesNobodyWouldChoose() throws {
        let reg = try registry()
        var cache: [String: Int] = [:]
        var routes: [String: [RecipeDefinition]] = [:]
        for recipe in reg.recipes.values { routes[recipe.outputItemID, default: []].append(recipe) }
        func price(_ r: RecipeDefinition) -> Double {
            r.materials.values.reduce(0) { $0 + Double($1) }
                + ResourceType.allCases.reduce(0) { $0 + r.resourceCost[$1] }
        }
        var pointless: [String] = []
        for (_, ways) in routes where ways.count > 1 {
            for way in ways {
                let mine = reachableEra(way, reg, &cache)
                let beaten = ways.contains { other in
                    other.id != way.id
                        && reachableEra(other, reg, &cache) < mine
                        && price(other) <= price(way)
                        // …and no slower. A later route that costs more stuff
                        // and less *work* is a real choice — have it today, or
                        // spend less and wait — so it is not dominated.
                        && other.workPerUnit <= way.workPerUnit
                }
                if beaten { pointless.append(way.id) }
            }
        }
        #expect(pointless.isEmpty,
                "\(pointless.count) recipes nobody would ever choose: \(pointless.sorted().prefix(8))")
    }

    /// **A worn thing must not claim what the line already counts.**
    ///
    /// Measured 2026-08-29: 53 wearable items carried `colony_*` effects from a
    /// slot nothing read — 38 of them `colony_defense`, worth **+217** to a
    /// colony whose defence is thirty or forty. Switching them on would have
    /// been the same fact counted twice, because `CombatEngine.militia` already
    /// weighs every real weapon and every piece of armour into the line. They
    /// came off the items instead, and this keeps them off: a generator writing
    /// "+6 colony defence" onto a helmet is writing a claim the game will
    /// refuse to honour (rule 47's cousin — content that *would* be read and
    /// must not be).
    @Test("No worn thing claims a defence the line already counts")
    func wornGearDoesNotDoubleCount() throws {
        let reg = try registry()
        var claiming: [String] = []
        for item in reg.items.values where item.slot != .artifact {
            for effect in item.effects {
                if case .colonyDefense = effect { claiming.append(item.id) }
                // A sack of ore in a store does not run a workshop either.
                if case .colonyProduction = effect, item.slot == .material {
                    claiming.append(item.id)
                }
            }
        }
        #expect(claiming.isEmpty,
                "\(claiming.count) wearable things claim the colony's own numbers: \(claiming.sorted().prefix(6))")
    }

    /// **A weapon must not arrive before the age its damage belongs to.**
    ///
    /// The bands are not a taste: they are read off the recipes that already
    /// carry a `requiresTech`, whose damage runs p50 3 in the first age, 4 in
    /// the ancient, 14 medieval, 18 early industrial, 16 modern and 36 in the
    /// near future. Measured against them, the shipped book was already very
    /// nearly right — five recipes were not, and chainmail was the worst of
    /// them: two iron ingots, no bench, no study, from the first day.
    ///
    /// The check is one-sided on purpose. An age *later* than the band is a
    /// content choice (a relic forged out of treasure belongs where its
    /// treasure does); an age earlier undercuts every properly-gated weapon
    /// above it and makes them content nobody will ever choose.
    @Test("No weapon is made before the age its damage belongs to")
    func armsArriveInTheirOwnAge() throws {
        let reg = try registry()
        var cache: [String: Int] = [:]
        // damage → the earliest era that damage may be reached in
        func band(_ damage: Double) -> Int {
            switch damage {
            case ..<5.5:  return Era.earlySettlement.index
            case ..<8.5:  return Era.ancient.index
            case ..<15.5: return Era.medieval.index
            case ..<23.5: return Era.earlyIndustrial.index
            case ..<32.5: return Era.modern.index
            default:      return Era.nearFuture.index
            }
        }
        var early: [String] = []
        for recipe in reg.recipes.values.sorted(by: { $0.id < $1.id }) {
            guard let combat = reg.item(recipe.outputItemID)?.combat else { continue }
            let arrives = reachableEra(recipe, reg, &cache)
            let belongs = band(combat.damage)
            if arrives < belongs {
                early.append("\(recipe.id) (\(Int(combat.damage)) damage) in era \(arrives), band \(belongs)")
            }
        }
        #expect(early.isEmpty, "\(early.joined(separator: "; "))")
    }

    /// The same, for what a colonist wears: plate is not a thing a village
    /// hammers out in its first summer.
    @Test("No armour is made before the age its material belongs to")
    func armourArrivesInItsOwnAge() throws {
        let reg = try registry()
        var cache: [String: Int] = [:]
        let earliest: [ArmourProfile.Material: Era] = [
            .cloth: .earlySettlement, .hide: .earlySettlement, .leather: .earlySettlement,
            .wood: .earlySettlement, .bone: .earlySettlement, .bronze: .ancient,
            .mail: .medieval, .plate: .earlyIndustrial,
            .composite: .earlyIndustrial, .powered: .nearFuture
        ]
        var early: [String] = []
        for recipe in reg.recipes.values.sorted(by: { $0.id < $1.id }) {
            guard let armour = reg.item(recipe.outputItemID)?.armour,
                  let belongs = earliest[armour.material] else { continue }
            let arrives = reachableEra(recipe, reg, &cache)
            if arrives < belongs.index {
                early.append("\(recipe.id) (\(armour.material.rawValue)) in era \(arrives), band \(belongs.index)")
            }
        }
        #expect(early.isEmpty, "\(early.joined(separator: "; "))")
    }
}

@Suite("Pollution")
struct PollutionTests {
    /// A fixed id so the two towns draw the same society rolls (wages, unrest);
    /// pollution is then the only thing telling them apart.
    private func settlement(factories: Int) -> Settlement {
        Settlement(id: UUID(uuidString: "00000000-0000-0000-0F0C-000000000001")!,
                   name: "Town", kind: .capital, pawns: Fixtures.pawns(20),
                   buildings: factories > 0 ? [BuildingInstance(definitionID: "factory", count: factories)] : [],
                   storage: [.food: 500, .energy: 500], storageCapacity: .uniform(9999),
                   stats: SettlementStats(morale: 80))
    }

    @Test("Industry accumulates pollution over time")
    func accumulates() throws {
        let reg = try GameDataRegistry.bundled()
        var world = WorldState(settlements: [settlement(factories: 1)])
        world.stewardEnabled = false
        world = TickEngine.advance(world, ticks: 60, registry: reg).state
        #expect(world.settlements[0].stats.pollution > 5)
    }

    @Test("Heavy pollution drags morale below a clean settlement's")
    func pollutionHurtsMorale() throws {
        let reg = try GameDataRegistry.bundled()
        // The council off: this is a test about smoke, and a colony that
        // builds itself a library halfway through is measuring something else.
        var dirty = WorldState(settlements: [settlement(factories: 2)])   // pollution → 60
        var clean = WorldState(settlements: [settlement(factories: 0)])
        dirty.stewardEnabled = false
        clean.stewardEnabled = false
        dirty = TickEngine.advance(dirty, ticks: 120, registry: reg).state
        clean = TickEngine.advance(clean, ticks: 120, registry: reg).state
        #expect(dirty.settlements[0].stats.morale < clean.settlements[0].stats.morale)
    }
}

/// **Every key on an authored effect is one the decoder reads.**
///
/// `EventEffect.init(from:)` takes what it knows and drops the rest in silence,
/// so an effect can be spelled four different ways and only one of them does
/// anything. Measured on the shipped file: of twenty-odd `damage_buildings`,
/// twelve said `strength` and the rest said `delta`, `damage` or `amount` — all
/// three ignored, all three falling back to a severity of 0.5, so an authored
/// landslide and an authored dam breach were exactly as bad as each other.
/// `add_pawn` with `count: 3` added one person; `remove_pawn` with `count: 2`
/// took one.
///
/// The check works by round-tripping: decode the effect, encode it again, and
/// anything in the original that the encoded form has no place for is a key
/// nothing reads. No second list to keep in step with the decoder — the decoder
/// *is* the list.
@Suite("Nothing in an event is written for a reader that does not exist")
struct EffectShapeTests {
    @Test("Every key on every effect is one the game reads")
    func noKeyIsIgnored() throws {
        let url = try #require(Bundle.module.url(forResource: "events", withExtension: "json",
                                                 subdirectory: "GameData"))
        let raw = try JSONSerialization.jsonObject(with: Data(contentsOf: url))
        let events = try #require(raw as? [[String: Any]])

        func inspect(_ effects: Any?, in event: String, at place: String) throws {
            guard let effects = effects as? [[String: Any]] else { return }
            for (i, effect) in effects.enumerated() {
                let data = try JSONSerialization.data(withJSONObject: effect)
                let decoded = try JSONDecoder().decode(EventEffect.self, from: data)
                let round = try JSONSerialization.jsonObject(
                    with: try JSONEncoder().encode(decoded))
                let kept = Set((round as? [String: Any])?.keys ?? [:].keys)
                for key in Set(effect.keys).subtracting(kept).sorted() {
                    Issue.record("\(event) \(place)[\(i)] (\(effect["type"] ?? "?")) carries '\(key)', which nothing reads")
                }
            }
        }

        for event in events {
            let id = event["id"] as? String ?? "?"
            try inspect(event["effects"], in: id, at: "effects")
            for choice in (event["choices"] as? [[String: Any]]) ?? [] {
                try inspect(choice["effects"], in: id,
                            at: "choices.\(choice["id"] as? String ?? "?").effects")
            }
        }
    }
}

/// **A progress bar must not cost determinism.**
///
/// Catch-up after a long absence had no progress at all — a spinner over up to
/// 43,200 ticks, which in a debug build is minutes the player cannot tell from
/// a hang. Reporting it means running the catch-up in slices, and slicing a
/// simulation is exactly the kind of change that quietly stops two runs of the
/// same seed agreeing.
///
/// It is safe here for one reason worth stating: `TickEngine.advance` is a
/// plain `for _ in 0..<ticks` over a pure step, and `ticks` is nothing but the
/// loop's bound. This test is what keeps that true.
@Suite("A month of world runs the same whether or not anybody is watching")
struct CatchUpSliceTests {
    @Test("Catch-up in slices lands on the same world as catch-up in one go")
    func catchUpIsTheSameWorldEitherWay() throws {
        let registry = try GameDataRegistry.bundled()
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        var world = GameWorldFactory.newGame(registry: registry, seed: 4242, now: start)
        world.lastRealTimestamp = start
        // Far enough to cross several slices, and several game years.
        let later = start.addingTimeInterval(
            Double(registry.config.realSecondsPerTick) * 900)

        let whole = GameEngine.openSession(world, now: later, registry: registry)
        var seen: [(Int, Int)] = []
        let sliced = GameEngine.openSession(
            world, now: later, registry: registry, sliceTicks: 97,
            onProgress: { done, total in seen.append((done, total)) })

        #expect(sliced.state == whole.state,
                "slicing the catch-up must not change a single thing about the world")
        #expect(sliced.fired.count == whole.fired.count,
                "…nor swallow or duplicate an event")
        #expect(seen.first?.0 == 0, "progress must start at nothing")
        #expect(seen.last?.0 == seen.last?.1, "…and end at everything")
        #expect((seen.last?.1 ?? 0) > 0, "a long absence must report a total worth showing")
    }

    /// The slice size is a tuning knob, not a behaviour.
    @Test("Any slice size gives the same world", arguments: [1, 13, 240, 10_000])
    func sliceSizeDoesNotMatter(slice: Int) throws {
        let registry = try GameDataRegistry.bundled()
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        var world = GameWorldFactory.newGame(registry: registry, seed: 77, now: start)
        world.lastRealTimestamp = start
        let later = start.addingTimeInterval(Double(registry.config.realSecondsPerTick) * 300)

        let whole = GameEngine.openSession(world, now: later, registry: registry)
        let sliced = GameEngine.openSession(world, now: later, registry: registry,
                                            sliceTicks: slice, onProgress: { _, _ in })
        #expect(sliced.state == whole.state)
    }

    /// **Stopping the years to be shown something does not rewrite them.**
    ///
    /// A raid lasts under a minute of the two hours a colony year takes, and
    /// the app is in the foreground for a sliver of that — so nearly every raid
    /// in the game opened *and finished* inside a catch-up, was fought by the
    /// world clock with nobody watching, and reached the player as a line in
    /// the diary. The surface that lets you stand in one and give orders was
    /// reachable only by luck. Keks, finding it behind the debug button:
    /// *"vyvolat nájezd ukáže GUI, co jsem nikdy neviděl."*
    ///
    /// So a catch-up may now stop the moment one opens. This is the invariant
    /// that makes that safe: stopping halfway and finishing later has to land
    /// on exactly the world one straight run would have, and the time that was
    /// not simulated has to still be *owed* rather than swallowed.
    @Test("A catch-up stopped halfway and finished later is the same world")
    func stoppingTheCatchUpChangesNothing() throws {
        let registry = try GameDataRegistry.bundled()
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        var world = GameWorldFactory.newGame(registry: registry, seed: 4242, now: start)
        world.lastRealTimestamp = start
        let later = start.addingTimeInterval(Double(registry.config.realSecondsPerTick) * 400)

        let whole = GameEngine.openSession(world, now: later, registry: registry)

        // Stop at a tick picked out of the middle by a plain arithmetic rule,
        // so the halt is real but has nothing to do with what happens in the
        // world — the same shape a raid's halt has.
        let halfway = world.tick + 173
        let first = GameEngine.openSession(
            world, now: later, registry: registry, sliceTicks: 97,
            stoppingWhen: { $0.tick >= halfway }, onProgress: { _, _ in })
        #expect(first.stoppedShort, "the halt must actually have stopped it")
        #expect(first.result.state.tick == halfway)
        // The rest is still owed: the clock moved by what was simulated, not to
        // the moment the player arrived.
        #expect(first.result.state.lastRealTimestamp < later)

        let finished = GameEngine.openSession(
            first.result.state, now: later, registry: registry, sliceTicks: 97,
            stoppingWhen: nil, onProgress: { _, _ in })
        #expect(finished.result.state == whole.state,
                "stopping for a fight must not change a single thing about the world")
        #expect(finished.result.state.lastRealTimestamp == later)
    }
}

/// **A colony is a hundred hours of somebody's life and it lived in one file.**
///
/// `.atomic` promises the file is never *half* written. It promises nothing
/// about the contents being loadable, and every way a save goes bad — a schema
/// change that encodes fine and decodes badly, a disk that fills, a field that
/// stops being optional by mistake — replaces the good save with a bad one and
/// the good one is gone.
@Suite("A bad save does not cost the colony")
struct SaveBackupTests {
    private func store() -> WorldStore {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return WorldStore(url: dir.appendingPathComponent("world.json"))
    }

    private func world() throws -> WorldState {
        GameWorldFactory.newGame(registry: try GameDataRegistry.bundled(), seed: 7,
                                 now: Date(timeIntervalSince1970: 1_700_000_000))
    }

    @Test("The second save keeps the first")
    func savingRotates() throws {
        let store = store()
        var first = try world()
        first.tick = 100
        try store.save(first)
        #expect(!FileManager.default.fileExists(atPath: store.backupURL.path),
                "there is nothing to keep on the very first save")

        var second = first
        second.tick = 200
        try store.save(second)
        #expect(try store.load()?.tick == 200)
        let kept = try JSONDecoder().decode(
            WorldState.self, from: Data(contentsOf: store.backupURL))
        #expect(kept.tick == 100, "the backup must be the world before this one, not a copy of it")
    }

    /// The case the whole thing exists for.
    @Test("A save that will not decode falls back to the one that will")
    func corruptionIsSurvivable() throws {
        let store = store()
        var good = try world()
        good.tick = 500
        try store.save(good)
        var newer = good
        newer.tick = 600
        try store.save(newer)

        try Data("{ this is not a world }".utf8).write(to: store.url)
        let result = try store.loadRecovering()
        #expect(result.state?.tick == 500, "the colony must come back, one save behind")
        #expect(result.rescued, "…and the app must be able to say so")
    }

    @Test("A world that cannot be encoded never touches either file")
    func encodingFailsBeforeAnythingMoves() throws {
        let store = store()
        var first = try world()
        first.tick = 42
        try store.save(first)
        var second = first
        second.tick = 43
        try store.save(second)
        // Both files are sound; the encode-then-rotate order is what guarantees
        // it, and this is the ordering pinned so a refactor cannot swap them.
        #expect(try store.load()?.tick == 43)
        #expect(try JSONDecoder().decode(
            WorldState.self, from: Data(contentsOf: store.backupURL)).tick == 42)
    }

    @Test("Deleting a save deletes the backup with it")
    func deletingTakesBoth() throws {
        let store = store()
        try store.save(try world())
        try store.save(try world())
        try store.deleteSave()
        #expect(!FileManager.default.fileExists(atPath: store.url.path))
        #expect(!FileManager.default.fileExists(atPath: store.backupURL.path),
                "a player who deletes their world must not leave a copy of it behind")
    }
}
