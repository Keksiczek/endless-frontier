#!/usr/bin/env python3
"""What can be generated, and what each thing *is* in the game.

One entry per data file. Everything mechanical — the shape of a record, the
allowed effect types, the era names — is read out of the file that already
exists rather than written down twice: a registry that restates the schema is a
registry that drifts away from it, and then the model is told to write content
the loader will reject.

So each kind carries only what the repository cannot tell you by looking:
**what the thing means**, and what makes a good one.
"""

from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
GAME_DATA = ROOT / "Core/Sources/EndlessFrontierCore/Resources/GameData"

# Keys whose values are a closed vocabulary in practice. The generator collects
# the distinct values each one already holds and tells the model it may not
# invent new ones — an effect type the `EffectApplier` has never heard of is the
# single most likely way for generated content to load and then do nothing.
ENUM_KEYS = (
    "type", "era", "resource", "scope", "selector", "kind", "category",
    "work", "look", "slot", "equipSlot", "substance", "biome", "season", "rarity", "tier",
    "trigger", "target", "effect", "station", "fabric",
)

# Values the *code* accepts that no content happens to use yet. Collecting the
# vocabulary out of the content gets the closed set right in one direction only:
# it can never offer a value the game does not know, and it silently hides every
# value the game knows and the content has not reached for.
#
# That is not theoretical. The first bulk run wanted a bonus for tanning hides,
# found no `crafting` in the offered list because not one of 76 items uses it,
# and invented `work: "materials"` — which the check caught, but only after the
# entry was written and paid for. A model offered the real word writes the real
# word.
#
# Copied from the enums, and only where the enum is small and settled:
#   · `WorkKind`  — `Pawn.swift`
#   · building `look` — `SettlementRenderer.BuildingGlyph`, whose `temple` no
#     building states even though the renderer draws it
SUPPLEMENTS: dict[str, set[str]] = {
    "work": {
        "farming", "logging", "mining", "research", "trade", "foraging",
        "hunting", "healing", "building", "scouting", "priest", "garrison",
        "crafting", "cooking", "idle",
    },
    "look": {"temple"},
    # Every string `EventEffect.init(from:)` switches on. The content uses ten
    # of these thirteen, so measurement alone hid `remove_pawn`, `unlock_tech`
    # and `trigger_event` — three of the most *interesting* things an event can
    # do, invisible to the generator purely because nobody had written one yet.
    # A vocabulary taken from content can only ever narrow; the code is the
    # authority on what is legal.
    "type": {
        "add_pawn", "damage_buildings", "pawn_health", "pawn_mood", "raid",
        "region_hazard", "region_kind", "remove_pawn", "resource_delta",
        "set_world_flag", "stat_delta", "trigger_event", "unlock_tech",
    },
}

# `stat` is deliberately **not** in the list above, because collecting its
# values out of the existing content gets it wrong in both directions: the
# content uses a fraction of what the game accepts, and — this is the part that
# matters — *writing* a stat and *reading* one accept different sets.
#
#   · an effect (`"type": "stat_delta"`) goes through
#     `GlobalStats.applying(delta:to:)` / `SettlementStats.applying(delta:to:)`,
#     both of which end in `default: break`. A name outside these sets loads
#     without complaint and then does nothing at all.
#   · a condition goes through `WorldQuery.globalValue` / `settlementValue`,
#     which fall through to `ResourceType`, so any resource is a legal thing to
#     *test* and none of them is a legal thing to *set*.
#
# Copied from those four switches. If a stat is ever added to one of them, add
# it here — a check that cries wolf gets switched off, which is worse than not
# having it.
WRITABLE_GLOBAL_STATS = {
    "prosperity", "stability", "threatLevel", "knowledgeOutput", "influenceOutput",
}
WRITABLE_SETTLEMENT_STATS = {"stability", "morale", "growth", "defense", "pollution"}
RESOURCES = {"food", "materials", "energy", "knowledge", "influence"}
READABLE_GLOBAL_STATS = WRITABLE_GLOBAL_STATS | {"population"} | RESOURCES
READABLE_SETTLEMENT_STATS = WRITABLE_SETTLEMENT_STATS | RESOURCES

# A bare name with no `scope.` prefix parses to an **empty** stat in
# `StatPath.parse`, so it is dead as an effect — but era milestones hand their
# raw string straight to `WorldQuery`, where a bare name is exactly right.
SCOPE_PREFIXES = ("settlement:all", "settlement:any", "settlement:closest", "global")

KINDS: dict[str, dict] = {
    "events": {
        "file": "events.json",
        "brief": """An event is something that *happens to somebody, somewhere* — the
storyteller picks one, applies its typed effects to the world, and the chronicle
records it. The best ones are specific and local: not "a good harvest" but a
particular field, a particular family, a particular argument. Some offer the
player a choice with a real cost on both sides; a choice where one option is
plainly better is not a choice.

Weight is how often it may fire; disasters and threats are rarer than flavour.
Conditions keep an event where it belongs — no shipwreck inland, no plague in a
village of six.

**Every event must land on somebody or somewhere.** At least one effect — in the
event itself or in one of its choices — has to be one that touches a person or
the ground: `pawn_health`, `pawn_mood`, `add_pawn`, `remove_pawn`,
`damage_buildings`, `raid`, `region_hazard`, `region_kind`. An
event that only moves resource or stat numbers happens to nobody and nowhere,
and the tests reject it.""",
        "wants": "roughly a third flavour, a third opportunity/quest, a third threat/disaster",
    },
    "items": {
        "file": "items.json",
        "brief": """A thing a colonist can own, carry, wear or wield. It has a place in
the world's economy: something makes it, something wears it out, somebody wants
it. Tools and weapons belong to an era — a colony of seven has no steel.""",
        "wants": "tools, clothing, weapons, trade goods, oddments worth finding",
    },
    "recipes": {
        "file": "recipes.json",
        "brief": """What a crafter can turn one pile of things into. Inputs must be things
the colony can actually get, and the output must be an item that exists.""",
        "wants": "recipes for items that currently have no way of being made",
    },
    "meals": {
        "file": "meals.json",
        "brief": """What a cook makes out of the harvest. `storage[.food]` means *meals
ready to eat* and nothing else, so every meal is the last step of the food chain:
raw crops and meat in, something a colonist eats out.""",
        "wants": "meals that use the crops and game the biomes actually produce",
    },
    "quests": {
        "file": "quests.json",
        "brief": """Something the colony can be asked to do that takes time and hands, and
that can fail. A quest is a small story with a place in it.""",
        "wants": "errands, expeditions, obligations to neighbours",
    },
    "laws": {
        "file": "laws.json",
        "brief": """What the assembly votes on every six years and the player then ratifies
or vetoes. A law must be arguable: it should help one part of the colony and cost
another, so that ratifying it is a decision and not a free gift.""",
        "wants": "laws about work, property, faith, the old, the young, outsiders",
    },
    "cults": {
        "file": "cults.json",
        "brief": """A faith a temple can seed. It has something it holds sacred, something
it forbids, and an effect on how the colony bears hardship.""",
        "wants": "faiths that grow out of a frontier valley's own troubles",
    },
    "plagues": {
        "file": "plagues.json",
        "brief": """An illness that moves through a colony: how it spreads, what it does to
a body, what holds it back.""",
        "wants": "illnesses of crowding, cold, bad water and bad food",
    },
    "buildings": {
        "file": "buildings.json",
        "brief": """A place colonists walk to in order to work and to make things. It owns
ground (a footprint), it holds the items of its trade, it wears out and wants
mending. Cost, workers and production have to sit sensibly beside the buildings
already in the file for the same era.""",
        "wants": "buildings that fill a gap in an era rather than duplicating one",
    },
    "techs": {
        "file": "techs.json",
        "brief": """A node in the tech DAG. It must depend on things that already exist and
unlock something the player can see happen.""",
        "wants": "techs that open buildings or trades the era is missing",
    },
    "motions": {
        "file": "motions.json",
        "brief": """How a body moves while it is doing something. Every part is a wave:
`amplitude` is how far it travels in body-scale units (a leg at a walk is 1.7),
`frequency` is how fast against the walk cycle (1 follows the feet, 5 is a hand
at a bench), `phase` in radians is how far behind it runs. `lean` tips the body
into the direction of travel, `bob` lifts it on each step, `slouch` bends it
over. `reach` and `hand_height` place the tool hand at rest.

Numbers are small: amplitudes 0…2, frequencies 0.5…6, lean and bob 0…1. A body
that stands still while working has legs at 0 and a busy `tool_arm`. Write the
motion of a real action — closing on an animal, gutting it, carrying it home —
not an emotion.""",
        "wants": "the hunt (stalking, closing, the kill, the carcass carried home), "
                 "and the trades that currently all look like the same arm going up and down",
    },
    "scenery": {
        "file": "scenery.json",
        "brief": """The colour of one thing standing on the ground — a crop, a tree, a
rock, a landform. `red`/`green`/`blue` are 0…1 and *dark*: this is a
night-leaning line-art world and almost nothing goes above 0.55.

`autumn_red`/`autumn_green`/`autumn_blue` are optional and mean "this turns".
Broadleaves state them, conifers and rocks do not — that difference is the whole
reason an autumn wood reads as an autumn wood, because the broadleaves turn
*around* the evergreens instead of the canopy changing all at once.

**The id must match a raw value of `CropSpecies`, `TreeSpecies`, `RockKind` or
`LandformKind`.** A new entry under a name none of those enums answers to is a
colour nothing will ever ask for. Adding a genuinely new species needs the Swift
enum and a drawing routine first.""",
        "wants": "nothing, until a new species exists in the Swift — this bank describes what is there",
    },
    "ground": {
        "file": "ground.json",
        "brief": """What one kind of ground looks like. `red`/`green`/`blue` are the raw
earth before the season passes over it (0…1, and these are *dark* — the canvas is
a night-leaning line-art world, so nothing here goes above about 0.35).
`texture_alpha` is how much grain shows: growing ground takes more than bare
ground, a fern bed is grain all the way down at 0.42 and clay is nearly smooth at
0.24.

`texture` names a mark the renderer already knows how to draw. It is a closed
list and you may not invent one: blades, pebbles, ripples, crack, glint, reed,
frond, sprig, stipple, chips, driedCrack.

A new ground has to read as a *neighbour* of the ones beside it, or the map turns
into confetti — scree is rock gone pale and loose, heath is grass gone dry and
purple, fern is meadow in shade.""",
        "wants": "country the twelve covers cannot currently make — salt flat, ash, shingle, peat",
    },
    "biomes": {
        "file": "biomes.json",
        "brief": """A kind of country a valley can be. It decides what grows, what lives
there, how hard the weather is, and what the ground looks like.""",
        "wants": "country the map generator cannot currently make",
    },
}

# Asked for and not listed above, because JSON alone will not do it. Each of
# these is a Swift change first — a data file and a loader — and only then worth
# generating into. Saying so here beats generating a file nothing reads.
NEEDS_SWIFT_FIRST = {
    "animals": "`AnimalFactory` builds beasts in code; there is no animals.json to write into.",
    "traits": "Pawn genes and traits are code (`Pawn+Genes`), not data.",
    "flora": "Trees and scenery are chosen by `SettlementFlora` from biome code, not from a file.",
    "names": "Colonist names come from a code table, not from GameData.",
}


def path_for(kind: str) -> Path:
    return GAME_DATA / KINDS[kind]["file"]


# What each typed record *must* carry, and what it may not.
#
# The vocabulary check above polices **values** — it knows `colony_production`
# is a real effect type. It has nothing to say about **fields**, and that is a
# different bug with the same blast radius: six generated items wrote
# `colony_production` with `amount` instead of `perTick`, which is legal-looking
# JSON, a `keyNotFound` at load, and — before the registry was made loud — the
# entire item table silently gone. Rule 9b names this exact effect by name and
# it still happened, which is the argument for checking it rather than
# remembering it.
#
# Read off the `init(from:)` switches. `decode` is required, `decodeIfPresent`
# is not.
SHAPES: dict[str, dict[str, tuple[str, ...]]] = {
    # item effects — `Item.swift`
    "skill_bonus": {"needs": ("work", "amount")},
    "mood_bonus": {"needs": ("amount",)},
    "health_regen": {"needs": ("amount",)},
    "colony_production": {"needs": ("resource", "perTick")},
    "colony_defense": {"needs": ("amount",)},
    "colony_morale": {"needs": ("amount",)},
    # storyteller effects — `EventEffect.swift`
    "set_world_flag": {"needs": ("flag",)},
    "resource_delta": {"needs": ("resource", "delta")},
    "stat_delta": {"needs": ("stat", "delta")},
}

# Fields that must be whole numbers, because the Swift side decodes an `Int`
# and a `2.5` there is the same silent catastrophe as a missing key.
INTEGER_FIELDS = {("skill_bonus", "amount")}
